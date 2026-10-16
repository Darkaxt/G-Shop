import 'dart:async';
import 'migration/migration_maintenance.dart';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/config/app_config.dart';
import '../models/config/provider_config.dart';
import '../models/game_item.dart';
import '../models/rom_cache_policy.dart';
import '../models/owned_removal_record.dart';
import '../models/system_model.dart';
import '../models/transfer_record.dart';
import 'drive/drive_runtime.dart';
import 'library_query.dart';
import 'owned_emulator_launcher.dart';
import 'owned_storage.dart';
import 'rom_cache_store.dart';
import 'source_resolver.dart';
import 'transfer_journal.dart';

class RomCacheGame {
  final RomCacheEntry entry;
  final String title;
  final List<InstalledArtifact> installations;
  final ProviderConfig? provider;
  final Map<String, ProviderConfig> providers;
  RomCacheGame(this.entry, this.title, List<InstalledArtifact> installations,
      this.provider,
      {Map<String, ProviderConfig> providers = const {}})
      : installations = List.unmodifiable(installations),
        providers = Map.unmodifiable(providers);
}

class RomCacheSnapshot {
  final RomCachePolicy policy;
  final List<RomCacheGame> games;
  final RomCachePlan plan;
  final DateTime time;
  final bool clockTrusted;
  RomCacheSnapshot(this.policy, List<RomCacheGame> games, this.plan,
      {required this.time, required this.clockTrusted})
      : games = List.unmodifiable(games);
}

/// One application-owned pass. Settings and pins cancel/join this same pass
/// before changing policy. Existing quarantine journals own filesystem recovery;
/// this class only selects complete game groups and authorizes exact removals.
class RomCacheRuntime extends ChangeNotifier {
  final RomCacheStore store;
  final Future<AppConfig> Function() configuration;
  final DriveRuntime drive;
  final OwnedStorage storage;
  final Future<Map<String, int>> Function()? clockSample;
  final Future<void> Function(bool, DateTime?)? schedule;
  final Future<void> Function(CancelToken)? acquirePass;
  final Future<void> Function()? releasePass;
  Future<void>? _editing;
  CancelToken? _editingCancellation;
  Future<void>? _operation;
  CancelToken? _cancel;
  bool _disposed = false;
  String? issue;
  int removedGames = 0;
  RomCacheSnapshot? latest;
  RomCacheRuntime(
      {required this.store,
      required this.configuration,
      DriveRuntime? drive,
      this.storage = const OwnedStorage(),
      this.clockSample,
      this.schedule,
      this.acquirePass,
      this.releasePass})
      : drive = drive ?? DriveRuntime.instance;
  bool get busy => _operation != null || _editing != null;

  Future<RomCacheSnapshot> snapshot(
      {bool preview = false, bool recovering = false}) async {
    final config = await configuration();
    final db = await store.database;
    final policy = await store.policy();
    final sample = await (clockSample ?? storage.cacheClock)();
    final clockTrusted = await store.observeClock(sample);
    final groups = <String,
        List<
            ({
              InstalledArtifact installed,
              Map<String, Object?> cached,
              LibraryRetentionMember? member,
              bool sample,
              String? block,
              ProviderConfig? provider
            })>>{};
    // Only exact current owners. Dependency discs are counted with their parent.
    final rows =
        await db.rawQuery('''SELECT i.record_json FROM installed_artifacts i
      JOIN transfer_records t ON t.transfer_id=i.transfer_id
      JOIN transfer_target_owners o ON o.installation_id=i.installation_id
        AND o.transfer_id=i.transfer_id AND o.destination_root=i.destination_root
        AND o.relative_path=i.relative_path
      WHERE t.bundle_owner IS NULL ORDER BY i.installation_id''');
    final journal = TransferJournal(store.database);
    final query = LibraryQuery(store.database);
    for (final row in rows) {
      final installed = InstalledArtifact.fromJson(
          (jsonDecode(row['record_json'] as String) as Map)
              .cast<String, dynamic>());
      final cachedRows = await db.query('games',
          where: 'artifact_key=? AND is_folder=0',
          whereArgs: [installed.artifact.id.key],
          limit: 2);
      final cached =
          cachedRows.length == 1 ? cachedRows.single : <String, Object?>{};
      final platform = cached['systemSlug'] as String?;
      LibraryRetentionMember? member;
      var sample = false;
      String? block;
      ProviderConfig? provider;
      if (platform == null ||
          cached['remote_artifact'] == null ||
          !const DeepCollectionEquality().equals(
              jsonDecode(cached['remote_artifact'] as String),
              installed.artifact.toJson())) {
        block = 'identity_unresolved';
      } else {
        final retention = await query.retentionForArtifact(
            platformId: platform, artifact: installed.artifact);
        if (retention.members.length != 1) {
          block = 'identity_unresolved';
        } else {
          member = retention.members.single;
          sample =
              retention.disposition(member) == LibraryRetentionDisposition.keep;
        }
        final system = config.systemById(platform);
        if (system == null ||
            !p.isWithin(
                p.normalize(system.targetFolder),
                p.normalize(p.join(
                    installed.destinationRoot, installed.relativePath)))) {
          block ??= 'location_changed';
        } else {
          final providers = SourceResolver.providersFor(system, config.sources)
              .where((s) =>
                  s.type == ProviderType.drive &&
                  s.sourceId == installed.artifact.id.sourceId &&
                  s.drive?.accountId == installed.artifact.id.accountId)
              .toList();
          if (providers.length == 1) provider = providers.single;
          if (provider == null) block ??= 'source_unavailable';
        }
        final model = SystemModel.supportedSystems
            .where((s) => s.id == platform)
            .firstOrNull;
        if (model == null ||
            !OwnedEmulatorLauncher.supports(
                GameItem(
                    filename: installed.artifact.displayName,
                    displayName: '',
                    url: '',
                    remoteArtifact: installed.artifact),
                model)) {
          block ??= 'restore_unproved';
        }
      }
      final transfer = await journal.transfer(installed.transferId);
      if (transfer == null ||
          transfer.lifecycle != TransferLifecycle.completed ||
          transfer.publication?.method == PublicationMethod.copy &&
              !transfer.stageRetired) {
        block ??= 'transfer_active';
      }
      if (!recovering && await journal.hasPendingRemoval(installed.transferId)) {
        block ??= 'removal_pending';
      }
      final key = member?.groupKey ?? 'artifact:${installed.artifact.id.key}';
      groups.putIfAbsent(key, () => []).add((
        installed: installed,
        cached: cached,
        member: member,
        sample: sample,
        block: block,
        provider: provider
      ));
    }
    final games = <RomCacheGame>[];
    for (final group in groups.entries) {
      final members = group.value;
      final installs = members.map((m) => m.installed).toList();
      final usages = [
        for (final install in installs) await store.usage(install.id)
      ];
      DateTime? newest(Iterable<DateTime?> values) {
        DateTime? result;
        for (final value in values) {
          if (value != null && (result == null || value.isAfter(result))) {
            result = value;
          }
        }
        return result;
      }

      final installedAt = usages.any((u) => u?.installedAt == null)
          ? null
          : newest(usages.map((u) => u?.installedAt));
      final lastUsedAt = newest(usages.map((u) => u?.lastUsedAt));
      final pinned = await store.isPinned(group.key);
      final entry = RomCacheEntry(
          id: group.key,
          platform: members.first.cached['systemSlug'] as String? ?? 'unknown',
          bytes: installs.fold(
              0,
              (sum, i) =>
                  sum +
                  i.sizeBytes +
                  i.dependencies.fold(0, (sum, d) => sum + d.sizeBytes)),
          installedAt: installedAt,
          lastUsedAt: lastUsedAt,
          pinned: pinned,
          offlineSample: members.any((m) => m.sample),
          block: members.map((m) => m.block).whereType<String>().firstOrNull);
      games.add(RomCacheGame(
          entry,
          members.first.cached['displayName'] as String? ??
              installs.first.artifact.displayName,
          installs,
          members.first.provider,
          providers: {
            for (final m in members)
              if (m.provider != null) m.installed.id: m.provider!
          }));
    }
    final result = RomCacheSnapshot(
        policy,
        games,
        (preview ? policy.copyWith(enabled: true) : policy).plan(
            games.map((g) => g.entry),
            now: DateTime.fromMillisecondsSinceEpoch(sample['wallMillis']!,
                isUtc: true),
            clockTrusted: clockTrusted),
        time: DateTime.fromMillisecondsSinceEpoch(sample['wallMillis']!,
            isUtc: true),
        clockTrusted: clockTrusted);
    latest = result;
    if (!_disposed) notifyListeners();
    return result;
  }

  Future<void> updatePolicy(RomCachePolicy policy) async {
    await _edit(() => store.savePolicy(policy));
  }

  Future<void> setPinned(String collectionKey, bool value) async {
    await _edit(() => store.setPinned(collectionKey, value));
  }

  Future<void> _edit(Future<void> Function() write) async {
    final preceding = _editing;
    final done = Completer<void>();
    _editing = done.future;
    if (!_disposed) notifyListeners();
    var admitted = false;
    try {
      await preceding;
      await _joinOperation();
      final cancellation = CancelToken();
      _editingCancellation = cancellation;
      await acquirePass?.call(cancellation);
      admitted = true;
      if (cancellation.isCancelled) {
        throw const OwnedStorageException('cancelled');
      }
      await write();
    } finally {
      try {
        if (admitted) await releasePass?.call();
      } finally {
        _editingCancellation = null;
        if (identical(_editing, done.future)) _editing = null;
        done.complete();
        if (!_disposed) notifyListeners();
      }
    }
    await reconcile();
  }

  Future<void> cancelAndJoin() async {
    _editingCancellation?.cancel();
    await _joinOperation();
    await _editing;
  }

  Future<void> _joinOperation() async {
    _cancel?.cancel();
    await _operation;
  }

  Future<void> acknowledgeClock() async {
    await _edit(() async {
      await store.observeClock(await (clockSample ?? storage.cacheClock)(),
          acknowledge: true);
    });
  }

  Future<void> reconcile() {
    if (_disposed || MigrationMaintenance.active) return Future.value();
    if (_editing case final editing?) return editing.then((_) => reconcile());
    if (_operation case final pending?) return pending;
    final cancellation = CancelToken();
    _cancel = cancellation;
    late Future<void> operation;
    operation = Future<void>.microtask(() async {
      issue = null;
      removedGames = 0;
      var admitted = false;
      try {
        await acquirePass?.call(cancellation);
        admitted = true;
        if (cancellation.isCancelled) return;
        await _recover(cancellation);
        final initial = await snapshot();
        final revision = await store.revision();
        for (final victim in initial.plan.victims) {
          if (cancellation.isCancelled) break;
          final game =
              initial.games.singleWhere((g) => g.entry.id == victim.entry.id);
          final db = await store.database;
          // Group identity is stable across redownloads; exact install identities
          // stay in the decision, never inferred from a title or a filename.
          final installation = game.installations.first;
          {
            try {
              for (final member in game.installations) {
                await db.insert(
                    'rom_cache_decisions',
                    {
                      'installation_id': member.id,
                      'policy_revision': revision,
                      'reason': victim.reasons.join(','),
                      'outcome': 'checking',
                      'issue': null,
                    },
                    conflictAlgorithm: ConflictAlgorithm.replace);
              }
              Future<void> eligible() async {
                if (cancellation.isCancelled ||
                    await store.revision() != revision) {
                  throw const OwnedStorageException('changed');
                }
                final fresh = await snapshot();
                if (!fresh.plan.victims
                    .any((v) => v.entry.id == game.entry.id)) {
                  throw const OwnedStorageException('changed');
                }
                final updated =
                    fresh.games.singleWhere((g) => g.entry.id == game.entry.id);
                if (!const DeepCollectionEquality().equals([
                  for (final i in game.installations) i.toJson()
                ], [
                  for (final i in updated.installations) i.toJson()
                ])) {
                  throw const OwnedStorageException('changed');
                }
                for (final member in game.installations) {
                  await storage.requireCacheIdle(member);
                }
              }

              await drive.rotateOwnedInstallation(
                  config: game.provider!,
                  installation: installation,
                  cancellation: cancellation,
                  requireEligible: eligible,
                  groupMembers: game.installations.skip(1).toList(),
                  groupSources: game.providers);
              for (final member in game.installations) {
                await db.update('rom_cache_decisions',
                    {'outcome': 'removed', 'issue': null},
                    where: 'installation_id=?', whereArgs: [member.id]);
              }
            } catch (error) {
              final code = error is OwnedStorageException
                  ? error.code
                  : cancellation.isCancelled
                      ? 'cancelled'
                      : 'cloud_unavailable';
              issue = code;
              for (final member in game.installations) {
                await db.update('rom_cache_decisions',
                    {'outcome': 'blocked', 'issue': code},
                    where: 'installation_id=?', whereArgs: [member.id]);
              }
            }
          }
          if (!cancellation.isCancelled) {
            final fresh = await snapshot();
            if (!fresh.games.any((g) => g.entry.id == game.entry.id)) {
              removedGames++;
            }
          }
        }
      } catch (_) {
        issue = 'cache_unavailable';
      } finally {
        try {
          final finalState = await snapshot();
          await schedule?.call(
              finalState.policy.enabled, finalState.plan.nextExpiry);
        } catch (_) {
          issue ??= 'cache_unavailable';
        } finally {
          try {
            if (admitted) await releasePass?.call();
          } finally {
            if (identical(_operation, operation)) {
              _operation = null;
              _cancel = null;
            }
            if (!_disposed) notifyListeners();
          }
        }
      }
    });
    _operation = operation;
    if (!_disposed) notifyListeners();
    return operation;
  }

  Future<void> _recover(CancelToken cancellation) async {
    final journal = TransferJournal(store.database);
    await for (final removal in journal.pendingRemovals(
        shouldContinue: () => !cancellation.isCancelled)) {
      if (!removal.policyDriven || removal.parentRemovalId != null) continue;
      final transfer = await journal.transfer(removal.installation.transferId);
      if (transfer?.bundleOwner != null) {
        continue; // Its exact root resumes the whole bundle.
      }
      try {
        final current = await snapshot(recovering: true);
        final matches = current.games.where(
            (g) => g.installations.any((i) => i.id == removal.installation.id));
        if (matches.length != 1) {
          throw const OwnedStorageException('identity_unresolved');
        }
        final game = matches.single;
        final config = await configuration();
        final system = config.systemById(game.entry.platform);
        if (system == null) {
          throw const OwnedStorageException('location_changed');
        }
        final sources = <String, ProviderConfig>{};
        for (final root in [removal.installation, ...removal.groupMembers]) {
          final providers = SourceResolver.providersFor(system, config.sources)
              .where((s) =>
                  s.type == ProviderType.drive &&
                  s.sourceId == root.artifact.id.sourceId &&
                  s.drive?.accountId == root.artifact.id.accountId)
              .toList();
          if (providers.length != 1) {
            throw const OwnedStorageException('source_unavailable');
          }
          sources[root.id] = providers.single;
        }
        final revision = await store.revision();
        Future<void> eligible() async {
          if (cancellation.isCancelled || await store.revision() != revision) {
            throw const OwnedStorageException('changed');
          }
          final fresh = await snapshot(recovering: true);
          if (!fresh.plan.victims.any((v) => v.entry.id == game.entry.id)) {
            throw const OwnedStorageException('protected');
          }
          await storage.requireCacheIdle(removal.installation,
              removalId: removal.id);
        }

        await drive.rotateOwnedInstallation(
            config: game.provider!,
            installation: removal.installation,
            cancellation: cancellation,
            requireEligible: eligible,
            removalId: removal.id,
            groupMembers: removal.groupMembers,
            groupSources: sources);
        await (await store.database).update(
            'rom_cache_decisions', {'outcome': 'removed', 'issue': null},
            where: 'installation_id=?', whereArgs: [removal.installation.id]);
        if ((await journal.removal(removal.id))?.phase ==
            OwnedRemovalPhase.completed) {
          removedGames++;
        }
      } catch (error) {
        issue = error is OwnedStorageException
            ? error.code
            : cancellation.isCancelled
                ? 'cancelled'
                : 'cloud_unavailable';
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    _editingCancellation?.cancel();
    super.dispose();
  }
}
