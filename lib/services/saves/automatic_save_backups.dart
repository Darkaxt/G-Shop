import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/config/source.dart';
import '../../models/library_identity.dart';
import '../../models/retroarch_battery_route.dart';
import '../../models/pcsx_save_layout.dart';
import '../../models/game_item.dart';
import '../library_store.dart';
import '../owned_emulator_launcher.dart';
import '../drive/drive_runtime.dart';
import 'drive_save_backup_area.dart';
import 'drive_save_backup_generation.dart';
import 'save_backup_game_job.dart';
import 'save_backup_setup.dart';
import 'save_capture.dart';

/// Explicit save association, never a title-only game match.
/// Watches request work; each emulator's capture boundary still decides when
/// bytes are safe. RetroArch uses root writer checks and a mutation guard.
class AutomaticSaveMapping {
  final String clientId, accountId, areaId, editionId, directory, slot, title;
  final bool isMelon, isPpssppSavedata;
  final RetroArchBatteryRoute? retroArchRoute;
  final PcsxSaveLayout? pcsxLayout;
  final String? romRoot;
  bool get isPcsx => pcsxLayout != null;
  PcsxSaveCard? get pcsxCard => pcsxLayout?.cards.single;
  bool get isRetroArch => retroArchRoute != null;
  final RemoteArtifactId artifactId;
  AutomaticSaveMapping._(Map<String, dynamic> value)
      : isMelon = value['schema'] == 2 && value['route'] == 'melon',
        isPpssppSavedata =
            value['schema'] == 2 && value['route'] == 'ppsspp-savedata',
        retroArchRoute = value['schema'] == 3 && value['route'] == 'retroarch'
            ? RetroArchBatteryRoute.forPlatform(value['platform'] as String?)
            : null,
        pcsxLayout = value['schema'] == 4 && value['route'] == 'pcsx'
            ? PcsxSaveLayout.decode(value['pcsx'] as Map<String, dynamic>?)
            : null,
        romRoot = value['schema'] == 4 && value['route'] == 'pcsx'
            ? value['romRoot'] as String?
            : null,
        clientId = value['clientId'] as String,
        accountId = value['accountId'] as String,
        areaId = value['areaId'] as String,
        editionId = value['editionId'] as String,
        directory = value['directory'] as String,
        slot = value['slot'] as String,
        title = value['title'] as String,
        artifactId = RemoteArtifactId.fromJson(
            value['artifact'] as Map<String, dynamic>) {
    if (!(value['schema'] == 1 && !value.containsKey('route') ||
            isMelon ||
            isPpssppSavedata ||
            isRetroArch ||
            isPcsx) ||
        (isPcsx &&
            (pcsxLayout!.cards.length != 1 ||
                pcsxCard!.name != slot ||
                !{'libretro', 'shared'}.contains(pcsxCard!.mode) ||
                romRoot == null ||
                romRoot!.isEmpty ||
                romRoot!.length > 4096 ||
                RegExp(r'[\x00-\x1f\x7f]').hasMatch(romRoot!))) ||
        [clientId, accountId, areaId, editionId, title]
            .any((s) => s.trim().isEmpty || s.length > 1024) ||
        artifactId.providerId != 'drive' ||
        artifactId.accountId != accountId ||
        !(isPcsx
            ? directory == pcsxLayout!.directory
            : isRetroArch
                ? directory == retroArchRoute!.directory
                : isMelon
                    ? SaveCapture.validMelonDirectory(directory)
                    : isPpssppSavedata
                        ? SaveCapture.validPpssppSavedataDirectory(directory)
                        : SaveCapture.validPpssppDirectory(directory)) ||
        !(isPcsx
            ? slot == pcsxCard!.name
            : isRetroArch
                ? SaveCapture.validName(slot)
                : isMelon
                    ? SaveCapture.validMelonName(slot)
                    : isPpssppSavedata
                        ? slot == directory.split('/').last &&
                            SaveCapture.validPpssppSavedataMember(slot)
                        : SaveCapture.validPpssppName(slot))) {
      throw const FormatException('Invalid automatic save mapping');
    }
  }

  factory AutomaticSaveMapping.fromJob(SaveBackupGameJob job,
      {required String title, String? saveName, String? romRoot}) {
    if (job.isPcsx) {
      return AutomaticSaveMapping._({
        'schema': 4,
        'route': 'pcsx',
        'romRoot': romRoot,
        'pcsx': {
          'directory': job.pcsxLayout!.directory,
          'cards': [
            {
              'slot': job.pcsxCard!.slot,
              'mode': job.pcsxCard!.mode,
              'name': job.pcsxCard!.name
            }
          ]
        },
        'clientId': job.clientId,
        'accountId': job.accountId,
        'areaId': job.areaId,
        'editionId': job.editionId,
        'artifact': job.artifactId.toJson(),
        'title': title,
        'directory': job.pcsxLayout!.directory,
        'slot': job.pcsxCard!.name,
      });
    }
    if (!job.isStandalone &&
        (saveName == null || !SaveCapture.validName(saveName))) {
      throw const FormatException('Reviewed RetroArch save name required');
    }
    return AutomaticSaveMapping._({
      'schema': !job.isStandalone
          ? 3
          : job.isMelon || job.isPpssppSavedata
              ? 2
              : 1,
      if (!job.isStandalone) ...{
        'route': 'retroarch',
        'platform': job.retroArchRoute.platformId
      },
      if (job.isMelon) 'route': 'melon',
      if (job.isPpssppSavedata) 'route': 'ppsspp-savedata',
      'clientId': job.clientId,
      'accountId': job.accountId,
      'areaId': job.areaId,
      'editionId': job.editionId,
      'directory': !job.isStandalone
          ? job.retroArchRoute.directory
          : job.isMelon
              ? job.melonDirectory
              : job.ppssppSavedataDirectory ?? job.ppssppDirectory,
      'slot': !job.isStandalone
          ? saveName
          : job.isMelon
              ? job.melonName
              : job.isPpssppSavedata
                  ? job.ppssppSavedataDirectory!.split('/').last
                  : job.ppssppSlot,
      'artifact': job.artifactId.toJson(),
      'title': title,
    });
  }

  String get slotStorageKey => isPcsx
      ? 'save_pcsx_mapping_v1_${sha256.convert(utf8.encode(jsonEncode([
              clientId,
              accountId,
              editionId,
              artifactId.key,
              pcsxCard!.slot
            ])))}'
      : isRetroArch
          ? 'save_retroarch_mapping_v1_${sha256.convert(utf8.encode(jsonEncode([
                  clientId,
                  accountId,
                  editionId,
                  artifactId.key,
                  retroArchRoute!.platformId
                ])))}'
          : isMelon
              ? melonMappingKey(clientId, accountId, editionId, artifactId)
              : isPpssppSavedata
                  ? ppssppSavedataMappingKey(
                      clientId, accountId, editionId, artifactId)
                  : ppssppMappingKey(
                      clientId, accountId, editionId, artifactId);
  static String ppssppSavedataMappingKey(String clientId, String accountId,
          String editionId, RemoteArtifactId artifact) =>
      'save_ppsspp_savedata_mapping_v1_${sha256.convert(utf8.encode(jsonEncode([
            clientId,
            accountId,
            editionId,
            artifact.key
          ])))}';
  static String melonMappingKey(String clientId, String accountId,
          String editionId, RemoteArtifactId artifact) =>
      'save_melon_mapping_v1_${sha256.convert(utf8.encode(jsonEncode([
            clientId,
            accountId,
            editionId,
            artifact.key
          ])))}';
  static String ppssppMappingKey(String clientId, String accountId,
          String editionId, RemoteArtifactId artifact) =>
      'save_ppsspp_mapping_v1_${sha256.convert(utf8.encode(jsonEncode([
            clientId,
            accountId,
            editionId,
            artifact.key
          ])))}';
  String get key => sha256
      .convert(utf8.encode(jsonEncode([
        clientId,
        accountId,
        areaId,
        editionId,
        artifactId.key,
        directory,
        slot,
        if (isPcsx) ...[pcsxCard!.slot, pcsxCard!.mode, romRoot],
        if (isRetroArch) retroArchRoute!.journalId,
        if (isMelon) 'melondualds-sram-v1',
        if (isPpssppSavedata) 'ppsspp-savedata-v1',
      ])))
      .toString();
  Map<String, Object?> get selection => {
        'directory': directory,
        'name': slot,
        if (isPcsx) ...{
          'mode': pcsxCard!.mode,
          'card': pcsxCard!.slot,
          'romRoot': romRoot,
        }
      };
  bool matchesSelection(Object? value) =>
      value is Map &&
      selection.entries.every((entry) => value[entry.key] == entry.value);
  String encode() => jsonEncode({
        'schema': isPcsx
            ? 4
            : isRetroArch
                ? 3
                : isMelon || isPpssppSavedata
                    ? 2
                    : 1,
        if (isRetroArch) ...{
          'route': 'retroarch',
          'platform': retroArchRoute!.platformId
        },
        if (isMelon) 'route': 'melon',
        if (isPpssppSavedata) 'route': 'ppsspp-savedata',
        if (isPcsx) ...{
          'route': 'pcsx',
          'pcsx': pcsxLayout!.toJson(),
          'romRoot': romRoot,
        },
        'clientId': clientId,
        'accountId': accountId,
        'areaId': areaId,
        'editionId': editionId,
        'artifact': artifactId.toJson(),
        'directory': directory,
        'slot': slot,
        'title': title,
      });
}

class AutomaticSaveStatus {
  final bool enabled;
  final String? outcome, issue;
  const AutomaticSaveStatus({required this.enabled, this.outcome, this.issue});
}

/// One process-owned serial lane, with durable opt-in and event requests.
/// No timers, recursive file scans or automatic conflict choices.
/// Android dispatch shares this lane or acquires the native cross-engine gate.
class AutomaticSaveBackups extends ChangeNotifier {
  final Future<Database> database;
  final SharedPreferences preferences;
  final List<Source> Function() sources;
  final Future<void> Function()? refreshConfiguration;
  final Future<void> Function(bool enabled)? scheduleBackground;
  final Future<Set<String>> Function(List<AutomaticSaveMapping>)?
      configureWatches;
  final SaveBackupGameJob Function(
      AutomaticSaveMapping, Future<String> Function())? createJob;
  Future<void>? _operation;
  Future<void> _events = Future.value();
  SaveBackupGameJob? _active;
  String? _activeKey;
  String? _backgroundIssue;
  String? _watchIssue;
  Set<String> _watchedKeys = {};
  bool _disposed = false;
  int _cancelGeneration = 0;
  AutomaticSaveBackups(
      {required this.database,
      required this.preferences,
      required this.sources,
      this.refreshConfiguration,
      this.scheduleBackground,
      this.configureWatches,
      this.createJob});
  bool get busy => _operation != null;
  String? get activeMappingKey => _activeKey;
  String? get backgroundIssue => _backgroundIssue;
  String? get watchIssue => _watchIssue;

  void watchUnavailable() {
    _watchedKeys = {};
    _watchIssue = 'watch_unavailable';
    _notify();
  }

  void backgroundUnavailable() {
    _backgroundIssue = 'schedule_unavailable';
    _notify();
  }

  Future<Database> _db() async {
    final db = await database;
    await db.execute('''CREATE TABLE IF NOT EXISTS automatic_save_backups(
      mapping_key TEXT PRIMARY KEY, record_json TEXT NOT NULL,
      enabled INTEGER NOT NULL, requested INTEGER NOT NULL DEFAULT 0,
      handled INTEGER NOT NULL DEFAULT 0, outcome TEXT, issue TEXT)''');
    return db;
  }

  Future<AutomaticSaveStatus> status(AutomaticSaveMapping mapping) async {
    final db = await _db();
    final rows = await db.query('automatic_save_backups',
        where: 'mapping_key = ?', whereArgs: [mapping.key]);
    if (rows.isEmpty) return const AutomaticSaveStatus(enabled: false);
    final row = rows.single;
    return AutomaticSaveStatus(
        enabled: row['enabled'] == 1,
        outcome: row['outcome'] as String?,
        issue: row['issue'] as String?);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> setEnabled(AutomaticSaveMapping mapping, bool enabled) async {
    final db = await _db();
    if (enabled) {
      await refreshConfiguration?.call();
      if (mapping.isRetroArch || mapping.isPcsx) {
        _requireConfiguration(mapping, requireSelection: false);
        final selected =
            jsonDecode(preferences.getString(mapping.slotStorageKey) ?? '{}');
        if (!mapping.matchesSelection(selected)) {
          // This explicit opt-in commits the newly reviewed launch destination.
          // Retire the former association before changing its selection; old
          // journals and every local/cloud copy remain available for recovery.
          final rows = await db.query('automatic_save_backups', limit: 4097);
          if (rows.length > 4096) {
            throw const FormatException('Too many mappings');
          }
          for (final row in rows) {
            final old = AutomaticSaveMapping._(
                jsonDecode(row['record_json'] as String)
                    as Map<String, dynamic>);
            if (old.key != row['mapping_key']) {
              throw const FormatException('Changed mapping');
            }
            if (old.slotStorageKey != mapping.slotStorageKey ||
                old.key == mapping.key) {
              continue;
            }
            await setEnabled(old, false);
            final job = _open(old);
            try {
              await job.refresh();
              if (job.issue != null ||
                  job.pendingName != null ||
                  job.restorePending ||
                  job.conflicts.isNotEmpty) {
                throw PlatformException(code: 'pending_save_operation');
              }
            } finally {
              await job.cancelAndJoin();
              job.dispose();
              job.areas.close();
              job.generations.close();
            }
          }
          if (!await preferences.setString(
              mapping.slotStorageKey, jsonEncode(mapping.selection))) {
            throw PlatformException(code: 'mapping_unavailable');
          }
        }
      }
      _requireConfiguration(mapping);
      await db.transaction((tx) async {
        final old = await tx.query('automatic_save_backups',
            where: 'mapping_key = ?', whereArgs: [mapping.key]);
        if (old.isEmpty) {
          final count = Sqflite.firstIntValue(await tx
              .rawQuery('SELECT COUNT(*) FROM automatic_save_backups'))!;
          if (count >= 4096) throw StateError('Save mapping limit reached');
          await tx.insert('automatic_save_backups', {
            'mapping_key': mapping.key,
            'record_json': mapping.encode(),
            'enabled': 1
          });
        } else {
          await tx.update('automatic_save_backups',
              {'record_json': mapping.encode(), 'enabled': 1},
              where: 'mapping_key = ?', whereArgs: [mapping.key]);
        }
      });
    } else {
      await db.update('automatic_save_backups', {'enabled': 0},
          where: 'mapping_key = ?', whereArgs: [mapping.key]);
      if (_activeKey == mapping.key) await _active?.cancelAndJoin();
    }
    await reconcileSchedule();
    _notify();
  }

  Future<void> reconcileSchedule() async {
    await reconcileWatches();
    if (scheduleBackground == null) return;
    final db = await _db();
    final enabled = (Sqflite.firstIntValue(await db.rawQuery(
                'SELECT COUNT(*) FROM automatic_save_backups WHERE enabled = 1')) ??
            0) >
        0;
    try {
      await scheduleBackground!(enabled);
      _backgroundIssue = null;
    } on PlatformException {
      backgroundUnavailable();
    } on MissingPluginException {
      backgroundUnavailable();
    }
  }

  /// Arm only saved, enabled associations. Serialize configuration with durable
  /// event admission so a delayed opt-in cannot reinstall an opted-out watch.
  /// This is process-lifetime observation, with periodic/return recovery below.
  Future<void> reconcileWatches() {
    if (configureWatches == null) return Future.value();
    final generation = _cancelGeneration;
    final event = _events.then((_) async {
      if (_disposed || generation != _cancelGeneration) return;
      final db = await _db();
      final mappings = <AutomaticSaveMapping>[];
      var invalid = false;
      try {
        await refreshConfiguration?.call();
        final rows = await db.query('automatic_save_backups',
            where: 'enabled = 1', limit: 4097);
        if (rows.length > 4096) {
          throw const FormatException('Too many mappings');
        }
        for (final row in rows) {
          try {
            final raw = row['record_json'] as String;
            if (raw.length > 16384) {
              throw const FormatException('Invalid mapping');
            }
            final mapping =
                AutomaticSaveMapping._(jsonDecode(raw) as Map<String, dynamic>);
            if (mapping.key != row['mapping_key']) {
              throw const FormatException('Changed mapping');
            }
            _requireConfiguration(mapping);
            mappings.add(mapping);
          } catch (_) {
            invalid = true;
          }
        }
        if (_disposed || generation != _cancelGeneration) return;
        final watched = await configureWatches!(mappings);
        final expected = mappings.map((mapping) => mapping.key).toSet();
        if (!expected.containsAll(watched)) {
          throw const FormatException('Invalid watch receipt');
        }
        _watchedKeys = Set.unmodifiable(watched);
        _watchIssue = invalid || watched.length != expected.length
            ? 'watch_unavailable'
            : null;
      } catch (_) {
        // Stop old associations too when current configuration is unavailable.
        try {
          await configureWatches!([]);
        } catch (_) {}
        _watchedKeys = {};
        _watchIssue = 'watch_unavailable';
      }
      _notify();
    });
    _events = event.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return event;
  }

  /// Aggregate receipt for Android dispatch; identities and save data stay in
  /// the existing journal. A completed service is not proof of backup success.
  Future<Map<String, int>> passSummary() async {
    final db = await _db();
    final row = (await db.rawQuery('''SELECT COUNT(*) AS enabled,
      COALESCE(SUM(requested > handled), 0) AS pending,
      COALESCE(SUM(issue IS NULL AND outcome = 'verified'), 0) AS verified,
      COALESCE(SUM(issue IS NULL AND outcome = 'unchanged'), 0) AS unchanged,
      COALESCE(SUM(issue IS NOT NULL), 0) AS attention
      FROM automatic_save_backups WHERE enabled = 1''')).single;
    return row.map((key, value) => MapEntry(key, value as int));
  }

  void _requireConfiguration(AutomaticSaveMapping mapping,
      {bool requireSelection = true}) {
    final configured = sources().any((s) =>
        s.enabled &&
        s.type == SourceType.drive &&
        s.id == mapping.artifactId.sourceId &&
        s.drive?.accountId == mapping.accountId &&
        s.drive?.serverClientId == mapping.clientId);
    final setup = jsonDecode(preferences.getString(
            SaveBackupSetup.storageKey(mapping.clientId, mapping.accountId)) ??
        '{}');
    final slot =
        jsonDecode(preferences.getString(mapping.slotStorageKey) ?? '{}');
    if (!configured ||
        setup is! Map ||
        setup['ready'] != true ||
        setup['areaId'] != mapping.areaId ||
        (requireSelection &&
            (slot is! Map ||
                slot['directory'] != mapping.directory ||
                slot[mapping.isMelon ||
                            mapping.isPpssppSavedata ||
                            mapping.isRetroArch ||
                            mapping.isPcsx
                        ? 'name'
                        : 'slot'] !=
                    mapping.slot ||
                mapping.isPcsx && !mapping.matchesSelection(slot)))) {
      throw PlatformException(code: 'source_changed');
    }
  }

  Future<String> _resolve(AutomaticSaveMapping mapping) async {
    await refreshConfiguration?.call();
    _requireConfiguration(mapping);
    final db = await _db();
    final rows = await db.query('automatic_save_backups',
        where: 'mapping_key = ? AND enabled = 1', whereArgs: [mapping.key]);
    if (_disposed ||
        rows.length != 1 ||
        rows.single['record_json'] != mapping.encode()) {
      throw PlatformException(code: 'source_changed');
    }
    return mapping.slot;
  }

  SaveBackupGameJob _open(AutomaticSaveMapping mapping) {
    Future<String> resolve() async {
      final name = await _resolve(mapping);
      if (mapping.isPcsx) await _resolvePcsxGrant(mapping);
      return name;
    }

    if (createJob != null) return createJob!(mapping, () => _resolve(mapping));
    final authorization =
        DriveRuntime.instance.authorizationFor(mapping.clientId);
    return SaveBackupGameJob(
        database: database,
        capture: SaveCapture(),
        areas: DriveSaveBackupAreaApi(
            authorization: authorization, accountId: mapping.accountId),
        generations: DriveSaveBackupGenerationApi(
            authorization: authorization, accountId: mapping.accountId),
        clientId: mapping.clientId,
        accountId: mapping.accountId,
        areaId: mapping.areaId,
        editionId: mapping.editionId,
        artifactId: mapping.artifactId,
        ppssppDirectory: mapping.isMelon ||
                mapping.isPpssppSavedata ||
                mapping.isRetroArch ||
                mapping.isPcsx
            ? null
            : mapping.directory,
        ppssppSlot: mapping.isMelon ||
                mapping.isPpssppSavedata ||
                mapping.isRetroArch ||
                mapping.isPcsx
            ? null
            : mapping.slot,
        ppssppSavedataDirectory:
            mapping.isPpssppSavedata ? mapping.directory : null,
        melonDirectory: mapping.isMelon ? mapping.directory : null,
        melonName: mapping.isMelon ? mapping.slot : null,
        retroArchRoute: mapping.retroArchRoute ?? RetroArchBatteryRoute.mgba,
        pcsxLayout: mapping.pcsxLayout,
        pcsxCard: mapping.pcsxCard,
        resolvePcsxGrant:
            mapping.isPcsx ? () => _resolvePcsxGrant(mapping) : null,
        resolveSaveName: resolve);
  }

  Future<Map<String, Object>> _resolvePcsxGrant(
      AutomaticSaveMapping mapping) async {
    await _resolve(mapping);
    final artifact = await LibraryStore(database).artifact(mapping.artifactId);
    if (artifact == null) throw PlatformException(code: 'source_changed');
    final grant = await OwnedEmulatorLauncher().resolveRetroArchPcsxGrant(
        GameItem(
            filename: artifact.displayName,
            displayName: artifact.displayName,
            url: '',
            remoteArtifact: artifact),
        mapping.romRoot!);
    final current = PcsxSaveLayout.decode(
        await const MethodChannel('com.retro.rshop/storage')
            .invokeMapMethod<String, dynamic>(
                'reviewOwnedRetroArchPcsxSaves', grant));
    if (!current.containsSelection(mapping.pcsxLayout!, mapping.pcsxCard!)) {
      throw PlatformException(code: 'source_changed');
    }
    return grant;
  }

  /// A watch acknowledges only after this exact enabled mapping is durably
  /// pending. Unknown/disabled keys cannot implicitly enable a game. Keeping
  /// request transactions separate from IO also records events received while
  /// an earlier capture/upload is still running.
  Future<void> requestChanged(String mappingKey) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(mappingKey)) {
      throw const FormatException('Invalid save watch identity');
    }
    await _request(mappingKey);
  }

  Future<void> _request(String? mappingKey) {
    final generation = _cancelGeneration;
    final event = _events.then((_) async {
      if (_disposed || generation != _cancelGeneration) return;
      final db = await _db();
      await db.rawUpdate(
          'UPDATE automatic_save_backups SET requested = requested + 1 WHERE enabled = 1'
          '${mappingKey == null ? '' : ' AND mapping_key = ?'}',
          mappingKey == null ? [] : [mappingKey]);
    });
    _events = event.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return event;
  }

  /// Drain recorded watch/background requests through the same serial lane as
  /// manual operations. A crash leaves requested > handled and the game journal
  /// retains its exact sealed capture/reserved remote IDs for idempotent resume.
  Future<void> backupPending() => _drain();

  /// Only an explicitly enabled, exact artifact/edition association participates.
  /// Launch waits on the existing serial lane and on native watch registration.
  Future<void> prepareLaunch(
      {required RemoteArtifactId artifactId,
      String? editionId,
      Future<String> Function(RetroArchBatteryRoute)? reviewRetroArchSave,
      Future<PcsxSaveLayout> Function()? reviewPcsxSaves}) async {
    final generation = _cancelGeneration;
    final db = await _db();
    final enabled = await db.query('automatic_save_backups',
        where: 'enabled = 1', limit: 4097);
    if (enabled.length > 4096) throw const FormatException('Too many mappings');
    final rows = <Map<String, Object?>>[];
    for (final row in enabled) {
      try {
        final raw = row['record_json'] as String;
        if (raw.length > 16384) throw const FormatException('Invalid mapping');
        final value = jsonDecode(raw) as Map<String, dynamic>;
        final saved = RemoteArtifactId.fromJson(
            value['artifact'] as Map<String, dynamic>);
        if (saved.key == artifactId.key) rows.add(row);
      } catch (_) {
        // An unidentifiable association stays visibly unresolved; it must not
        // turn an unrelated, unconfigured game into a cloud/backup operation.
        watchUnavailable();
      }
    }
    // Unconfigured games do not wait behind another game's network transfer.
    if (rows.isEmpty) return;
    final previous = _operation;
    return _track(Future<void>.microtask(() async {
      try {
        await previous;
      } catch (_) {
        // Its original caller and durable status own that result. This queued
        // game's distinct operation must still run after actual completion.
      }
      if (_disposed || generation != _cancelGeneration) {
        throw PlatformException(code: 'cancelled');
      }
      for (final row in rows) {
        final raw = row['record_json'] as String;
        if (raw.length > 16384) throw const FormatException('Invalid mapping');
        final mapping =
            AutomaticSaveMapping._(jsonDecode(raw) as Map<String, dynamic>);
        SaveBackupGameJob? job;
        String? failure;
        Future<void> reviewTarget() async {
          if (mapping.isPcsx &&
              (reviewPcsxSaves == null ||
                  !(await reviewPcsxSaves()).containsSelection(
                      mapping.pcsxLayout!, mapping.pcsxCard!))) {
            throw PlatformException(code: 'source_changed');
          }
          if (mapping.isRetroArch &&
              (reviewRetroArchSave == null ||
                  await reviewRetroArchSave(mapping.retroArchRoute!) !=
                      mapping.slot)) {
            throw PlatformException(code: 'source_changed');
          }
        }

        try {
          if (mapping.key != row['mapping_key'] ||
              (editionId != null && mapping.editionId != editionId)) {
            throw PlatformException(code: 'source_changed');
          }
          await _resolve(mapping);
          await reviewTarget();
          if (_disposed || generation != _cancelGeneration) {
            throw PlatformException(code: 'cancelled');
          }
          _activeKey = mapping.key;
          job = _active = _open(mapping);
          job.addListener(_notify);
          await job.reconcileBeforeLaunch(mapping.slot);
          await _resolve(mapping);
          await reviewTarget();
          failure = job.issue ??
              (job.restorePending ? 'pending_restore' : null) ??
              (job.conflicts.isNotEmpty ? 'save_conflict' : null);
          if (failure == null &&
              !{'verified', 'unchanged', 'restored', 'no_save'}
                  .contains(job.phase)) {
            failure = 'backup_unavailable';
          }
          if (failure != null) throw PlatformException(code: failure);
        } on PlatformException catch (error) {
          failure = error.code;
          rethrow;
        } catch (_) {
          failure = 'backup_unavailable';
          rethrow;
        } finally {
          final outcome = job?.phase;
          if (job != null) {
            await job.cancelAndJoin();
            job.removeListener(_notify);
            job.dispose();
            job.areas.close();
            job.generations.close();
          }
          _active = null;
          _activeKey = null;
          await db.update(
              'automatic_save_backups', {'outcome': outcome, 'issue': failure},
              where: 'mapping_key = ? AND record_json = ?',
              whereArgs: [mapping.key, mapping.encode()]);
          _notify();
        }
      }
      await reconcileWatches();
      if (_disposed || generation != _cancelGeneration) {
        throw PlatformException(code: 'cancelled');
      }
      if (configureWatches == null ||
          !rows.every((row) => _watchedKeys.contains(row['mapping_key']))) {
        throw PlatformException(code: 'watch_unavailable');
      }
    }));
  }

  Future<void> _track(Future<void> operation) {
    late final Future<void> tracked;
    tracked = operation.whenComplete(() {
      if (identical(_operation, tracked)) _operation = null;
    });
    _operation = tracked;
    return tracked;
  }

  /// Called by actual startup/resume/background events, also recovering changes
  /// missed while Android had no live watcher process.
  Future<void> checkEnabled() async {
    final generation = _cancelGeneration;
    await reconcileWatches();
    await _request(null);
    if (_disposed || generation != _cancelGeneration) return;
    await backupPending();
  }

  Future<void> _drain() {
    final generation = _cancelGeneration;
    if (_operation case final pending?) {
      return pending
          .then<void>((_) {}, onError: (Object _, StackTrace __) {})
          .then<void>((_) async {
        if (_disposed || generation != _cancelGeneration) return;
        await _drain();
      });
    }
    final operation = Future<void>.microtask(() async {
      final db = await _db();
      final generation = _cancelGeneration;
      while (!_disposed && generation == _cancelGeneration) {
        final rows = await db.query('automatic_save_backups',
            where: 'enabled = 1 AND requested > handled',
            orderBy: 'mapping_key',
            limit: 1);
        if (rows.isEmpty) break;
        final row = rows.single;
        String? outcome, issue;
        SaveBackupGameJob? job;
        try {
          final raw = row['record_json'] as String;
          if (raw.length > 16384) {
            throw const FormatException('Invalid mapping');
          }
          final mapping =
              AutomaticSaveMapping._(jsonDecode(raw) as Map<String, dynamic>);
          if (mapping.key != row['mapping_key']) {
            throw const FormatException('Changed mapping');
          }
          await _resolve(mapping);
          _activeKey = mapping.key;
          job = _active = _open(mapping);
          job.addListener(_notify);
          await job.load();
          if (job.conflicts.isNotEmpty) {
            issue = 'save_conflict';
          } else if (job.restorePending) {
            issue = 'pending_restore';
          } else {
            await job.backup(mapping.slot);
            // A concurrent manual operation may own the same durable job.
            // Refresh after joining it, never interpret another object's idle
            // fields as proof of our requested capture being verified.
            await job.load();
            outcome = job.phase;
            issue = job.issue;
            if (outcome == 'idle' && issue == null) {
              issue = 'manual_operation_joined';
            }
          }
        } on PlatformException catch (error) {
          issue = error.code == 'source_changed'
              ? error.code
              : 'backup_unavailable';
        } catch (_) {
          issue = 'backup_unavailable';
        } finally {
          if (job != null) {
            await job.cancelAndJoin();
            job.removeListener(_notify);
            job.dispose();
            job.areas.close();
            job.generations.close();
          }
          _active = null;
          _activeKey = null;
        }
        await db.update(
            'automatic_save_backups',
            {
              'handled': row['requested'],
              'outcome': outcome,
              'issue': issue,
            },
            where: 'mapping_key = ? AND record_json = ?',
            whereArgs: [row['mapping_key'], row['record_json']]);
        _notify();
      }
    });
    return _track(operation);
  }

  Future<void> cancelAndJoin() async {
    _cancelGeneration++;
    await _active?.cancelAndJoin();
    await _operation;
    await _events;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelGeneration++;
    _active?.cancelAndJoin();
    super.dispose();
  }
}
