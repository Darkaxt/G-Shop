import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../models/config/drive_source_config.dart';
import '../../models/config/provider_config.dart';
import '../../models/config/source.dart';
import '../../models/library_identity.dart';
import '../../models/owned_removal_record.dart';
import '../../models/transfer_record.dart';
import '../database_service.dart';
import '../installation_index.dart';
import '../owned_storage.dart';
import '../owned_installation_removal.dart';
import '../transfer_journal.dart';
import '../stage_retirement.dart';
import '../owned_replacement.dart';
import 'drive_api.dart';
import 'drive_authorization.dart';
import 'drive_catalogue.dart';
import 'drive_download_boundary.dart';
import 'drive_media.dart';
import 'drive_transfer_engine.dart';
import 'drive_verification.dart';
import 'google_drive_sign_in.dart';

/// Bounded diagnostics for one offline maintenance pass, never artifact data.
class StageRetirementRecoveryReport {
  final int examined;
  final int retired;
  final int pending;
  final int skippedActive;
  final bool stopped;
  final Map<String, int> issues;
  StageRetirementRecoveryReport(
      {this.examined = 0,
      this.retired = 0,
      this.pending = 0,
      this.skippedActive = 0,
      this.stopped = false,
      Map<String, int> issues = const {}})
      : issues = Map.unmodifiable(issues);
}

typedef OwnedRemovalRecoveryReport = ({
  int examined,
  int removed,
  int pending,
  int skippedActive,
  bool stopped,
  Map<String, int> issues,
});

/// Process-wide native account lane and source-scoped refresh/transfer jobs. No token
/// resides in provider configs or download items. Background calls never consent.
class DriveRuntime {
  static final instance = DriveRuntime();
  DriveCatalogue? _catalogue;
  DriveCatalogue get catalogue =>
      _catalogue ??= DriveCatalogue(DatabaseService().database);
  TransferJournal? _journal;
  TransferJournal get journal =>
      _journal ??= TransferJournal(DatabaseService().database);
  final OwnedStorage _storage;
  final DriveAuthorization Function(String) _createAuthorization;
  final DriveApi Function(DriveAuthorization, String) _createApi;
  final DriveMediaApi Function(DriveAuthorization, String) _createMediaApi;
  DriveAuthorization? _authorization;
  String? _clientId;
  final _apis = <String, DriveApi>{};
  final _mediaApis = <String, DriveMediaApi>{};
  final _startingTransfers = <String>{};
  final _reservations = <String, Future<TransferRecord>>{};
  final _transfers = <String, DriveTransferOperation>{};
  final _transferResults = <String, Future<void>>{};
  final _refreshes = <String, Future<void>>{};
  final _refreshCancellation = <String, CancelToken>{};
  bool _disconnecting = false;
  int _laneGeneration = 0;

  DriveRuntime(
      {DriveCatalogue? catalogue,
      TransferJournal? journal,
      OwnedStorage? storage,
      DriveApi Function(DriveAuthorization, String)? createApi,
      DriveMediaApi Function(DriveAuthorization, String)? createMediaApi,
      DriveAuthorization Function(String)? createAuthorization})
      : _catalogue = catalogue,
        _journal = journal,
        _storage = storage ?? const OwnedStorage(),
        _createApi = createApi ??
            ((authorization, account) =>
                DriveApi(authorization: authorization, accountId: account)),
        _createMediaApi = createMediaApi ??
            ((authorization, account) => DriveMediaApi(
                authorization: authorization, accountId: account)),
        _createAuthorization = createAuthorization ??
            ((id) => DriveAuthorization(GoogleDriveSignIn(serverClientId: id)));

  /// Durable exact-file reservation for the normal queue. This creates no ROM
  /// bytes and performs no online requests. A repeated intent finds the same
  /// journal record, including after a crash before queue preferences were saved.
  Future<TransferRecord> reserveTransfer({
    required ProviderConfig config,
    required RemoteArtifact artifact,
    required String destinationRoot,
    required String relativePath,
  }) async {
    _requireConnectedLane();
    _requireArtifactSource(config, artifact);
    DriveVerification(artifact);
    if (relativePath != artifact.displayName ||
        relativePath.isEmpty ||
        relativePath == '.' ||
        relativePath == '..' ||
        RegExp(r'[\\/\x00-\x1f<>:"|?*]').hasMatch(relativePath)) {
      throw const DriveTransferException(DriveTransferIssue.invalidSource);
    }
    final id = sha256
        .convert(utf8.encode(jsonEncode([
          artifact.id.key,
          artifact.version,
          destinationRoot,
          relativePath
        ])))
        .toString();
    final existing = _reservations[id];
    if (existing != null) {
      final record = await existing;
      _requireReservationSnapshot(record, artifact);
      return record;
    }
    final generation = _laneGeneration;
    final reservation = () async {
      final plan = await _storage.prepare(destinationRoot);
      _requireConnectedLane();
      if (generation != _laneGeneration) {
        throw const DriveAuthorizationException(
            DriveAuthorizationIssue.cancelled);
      }
      if (plan.destinationRoot != destinationRoot) {
        throw const OwnedStorageException('changed');
      }
      final existing = await journal.transfer(id);
      if (existing != null) {
        _requireReservationSnapshot(existing, artifact);
        final expectedPath = existing.replacesInstallation == null
            ? relativePath
            : _replacementPath(relativePath, id);
        if (existing.destinationRoot != destinationRoot ||
            existing.relativePath != expectedPath ||
            existing.stagePath != plan.stagePath(id)) {
          throw const OwnedStorageException('changed');
        }
        return existing;
      }
      InstalledArtifact? previous;
      final index = InstallationIndex(journal, storage: _storage);
      await for (final row in journal.targetsInRoot(destinationRoot,
          artifactKey: artifact.id.key)) {
        final installed = row.installation;
        if (installed == null ||
            row.transfer.lifecycle != TransferLifecycle.completed) {
          continue;
        }
        await index.requireInstallation(row.transfer, installed);
        if (InstallationSnapshot.sameContent(installed.artifact, artifact)) {
          return row.transfer;
        }
        if (previous != null) {
          throw const OwnedStorageException('replacement_pending');
        }
        previous = installed;
      }
      final target =
          previous == null ? relativePath : _replacementPath(relativePath, id);
      return journal.create(TransferRecord(
          id: id,
          artifact: artifact,
          destinationRoot: destinationRoot,
          relativePath: target,
          replacesInstallation: previous,
          stagePath: plan.stagePath(id)));
    }();
    _reservations[id] = reservation;
    try {
      return await reservation;
    } finally {
      if (identical(_reservations[id], reservation)) _reservations.remove(id);
    }
  }

  static String _replacementPath(String name, String id) =>
      '${String.fromCharCodes(p.basenameWithoutExtension(name).runes.take(32))}.rshop-$id${p.extension(name)}';

  static void _requireReservationSnapshot(
      TransferRecord record, RemoteArtifact artifact) {
    if (!const DeepCollectionEquality()
        .equals(record.artifact.toJson(), artifact.toJson())) {
      throw const DriveTransferException(DriveTransferIssue.sourceChanged);
    }
  }

  static void _requireArtifactSource(
      ProviderConfig config, RemoteArtifact artifact) {
    if (config.type != ProviderType.drive ||
        config.drive?.isConfigured != true ||
        config.sourceId?.isNotEmpty != true ||
        config.path?.isNotEmpty != true ||
        artifact.id.providerId != 'drive' ||
        artifact.id.sourceId != config.sourceId ||
        artifact.id.accountId != config.drive!.accountId) {
      throw const DriveTransferException(DriveTransferIssue.invalidSource);
    }
  }

  /// Offline revalidation of an already committed exact installation. A saved
  /// completed bit is not proof that another app has left its bytes in place.
  Future<void> requireInstalledTransfer(TransferRecord record) async {
    final installation = await journal.installationForTarget(
        destinationRoot: record.destinationRoot,
        relativePath: record.relativePath);
    await InstallationIndex(journal, storage: _storage)
        .requireInstallation(record, installation);
  }

  Future<TransferRecord> finishRetainedStage(TransferRecord record) =>
      retireCommittedStage(journal, _storage, record);

  Future<String?> finishReplacement(TransferRecord record) =>
      retireReplacedInstallation(journal, _storage, record);

  Future<void> recoverPendingReplacements(
      {bool Function()? shouldContinue}) async {
    await for (final record
        in journal.pendingReplacements(shouldContinue: shouldContinue)) {
      if (!(shouldContinue?.call() ?? true)) return;
      if (_startingTransfers.contains(record.id) ||
          _transfers.containsKey(record.id)) {
        continue;
      }
      await finishReplacement(record);
    }
  }

  /// Explicit removal intents survive queue loss and account sign-out. One
  /// offline pass resumes them; conflicts remain for review, never busy retries.
  /// Shutdown stops between intents and joins the current namespace mutation.
  Future<OwnedRemovalRecoveryReport> recoverPendingRemovals(
      {bool Function()? shouldContinue}) async {
    var examined = 0, removed = 0, pending = 0, skippedActive = 0;
    var stopped = false;
    final issues = <String, int>{};
    void addIssue(String code) =>
        issues.update(code, (count) => count + 1, ifAbsent: () => 1);
    bool canContinue() {
      if (shouldContinue?.call() ?? true) return true;
      stopped = true;
      return false;
    }

    StreamIterator<OwnedRemovalRecord>? records;
    if (canContinue()) {
      try {
        records = StreamIterator(
            journal.pendingRemovals(shouldContinue: canContinue));
        final remover = OwnedInstallationRemoval(journal, storage: _storage);
        while (canContinue() && await records.moveNext()) {
          if (!canContinue()) break;
          final record = records.current;
          examined++;
          if (_startingTransfers.contains(record.installation.transferId) ||
              _transfers.containsKey(record.installation.transferId)) {
            skippedActive++;
            continue;
          }
          try {
            await remover.recover(record.id);
            removed++;
          } on OwnedStorageException catch (error) {
            pending++;
            // The native adapter exposes only its bounded machine-code enum.
            addIssue(error.code);
          } catch (_) {
            pending++;
            addIssue('removal_pending');
          }
        }
      } catch (_) {
        addIssue('journal_unavailable');
      } finally {
        try {
          await records?.cancel();
        } catch (_) {
          addIssue('journal_unavailable');
        }
      }
    }
    return (
      examined: examined,
      removed: removed,
      pending: pending,
      skippedActive: skippedActive,
      stopped: stopped,
      issues: Map<String, int>.unmodifiable(issues)
    );
  }

  /// One offline pass over durable cleanup intents, including installs whose
  /// completed queue rows were not persisted. Live operations own their inline
  /// cleanup; the shared helper serializes every other attempt by target path.
  Future<StageRetirementRecoveryReport> recoverPendingStageRetirements(
      {bool Function()? shouldContinue}) async {
    var examined = 0;
    var retired = 0;
    var pending = 0;
    var skippedActive = 0;
    var stopped = false;
    final issues = <String, int>{};
    void addIssue(String? issue) {
      const known = {
        'invalid_arguments',
        'collision',
        'not_found',
        'unsupported',
        'cross_volume',
        'out_of_space',
        'access_denied',
        'changed',
        'closed',
        'io_error',
        'close_unconfirmed',
        'retirement_pending',
        'journal_unavailable',
      };
      final code = known.contains(issue) ? issue! : 'retirement_pending';
      issues.update(code, (count) => count + 1, ifAbsent: () => 1);
    }

    bool canContinue() {
      if (shouldContinue?.call() ?? true) return true;
      stopped = true;
      return false;
    }

    StreamIterator<TransferRecord>? records;
    if (canContinue()) {
      try {
        records = StreamIterator(
            journal.pendingStageRetirements(shouldContinue: canContinue));
        while (canContinue() && await records.moveNext()) {
          if (!canContinue()) break;
          final record = records.current;
          examined++;
          if (_startingTransfers.contains(record.id) ||
              _transfers.containsKey(record.id)) {
            skippedActive++;
            continue;
          }
          try {
            final result = await finishRetainedStage(record);
            if (result.stageRetired) {
              retired++;
            } else {
              pending++;
              addIssue(result.stageRetirementIssue ?? 'retirement_pending');
            }
          } catch (_) {
            // Cleanup cannot alter the already committed installation outcome.
            pending++;
            addIssue('retirement_pending');
          }
        }
      } catch (_) {
        addIssue('journal_unavailable');
      } finally {
        try {
          await records?.cancel();
        } catch (_) {
          addIssue('journal_unavailable');
        }
      }
    }
    return StageRetirementRecoveryReport(
        examined: examined,
        retired: retired,
        pending: pending,
        skippedActive: skippedActive,
        stopped: stopped,
        issues: issues);
  }

  /// Starts only an already reserved exact transfer. The normal queue remains
  /// responsible for choosing when to invoke this API; it does not enqueue files.
  Future<DriveTransferOperation> startTransfer({
    required ProviderConfig config,
    required String transferId,
    void Function(TransferRecord)? onCheckpoint,
  }) async {
    _requireConnectedLane();
    final drive = config.drive;
    if (config.type != ProviderType.drive ||
        drive == null ||
        !drive.isConfigured ||
        config.sourceId?.isNotEmpty != true ||
        config.path?.isNotEmpty != true) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.setupRequired);
    }
    if (_transfers.containsKey(transferId) ||
        !_startingTransfers.add(transferId)) {
      throw StateError('Transfer already active');
    }
    final generation = _laneGeneration;
    try {
      final record = await journal.transfer(transferId);
      _requireConnectedLane();
      if (generation != _laneGeneration) {
        throw const DriveAuthorizationException(
            DriveAuthorizationIssue.cancelled);
      }
      if (record == null) throw StateError('Unknown transfer');
      if (record.artifact.id.providerId != 'drive' ||
          record.artifact.id.sourceId != config.sourceId ||
          record.artifact.id.accountId != drive.accountId) {
        throw const DriveTransferException(DriveTransferIssue.invalidSource);
      }
      final api = apiFor(drive);
      final media = _mediaApis.putIfAbsent(
          drive.accountId,
          () => _createMediaApi(
              authorizationFor(drive.serverClientId), drive.accountId));
      final engine = DriveTransferEngine(
          journal: journal,
          storage: _storage,
          revalidate: (artifact, cancellation) => DriveDownloadBoundary(
                  config: config,
                  artifact: artifact,
                  catalogue: catalogue,
                  api: api)
              .revalidate(cancellation: cancellation),
          openMedia: (artifact, offset, cancellation) =>
              media.open(artifact, offset: offset, cancelToken: cancellation));
      // No await separates this last gate from registration. A disconnect can
      // neither overlook this operation nor let a pending old-lane load start.
      _requireConnectedLane();
      final operation = engine.start(transferId, onCheckpoint: onCheckpoint);
      _transfers[transferId] = operation;
      void settled() {
        if (identical(_transfers[transferId], operation)) {
          _transfers.remove(transferId);
          _transferResults.remove(transferId);
        }
      }

      // Observe errors immediately, even when a caller waits on result later.
      // The original result retains its outcome; this future is the drain join.
      _transferResults[transferId] = operation.result.then<void>(
          (_) => settled(),
          onError: (Object _, StackTrace __) => settled());
      return operation;
    } finally {
      _startingTransfers.remove(transferId);
    }
  }

  DriveAuthorization authorizationFor(String serverClientId) {
    _requireConnectedLane();
    if (serverClientId.trim().isEmpty) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.setupRequired);
    }
    if (_clientId != null && _clientId != serverClientId) {
      // GoogleSignIn is a native singleton. Do not create competing authorization
      // lanes with different OAuth projects; changing the project needs relaunch.
      throw const DriveCatalogueException('oauthClientChangedRestartRequired');
    }
    _clientId = serverClientId;
    return _authorization ??= _createAuthorization(serverClientId);
  }

  DriveApi apiFor(DriveSourceConfig config) {
    if (!config.isConfigured) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.setupRequired);
    }
    final authorization = authorizationFor(config.serverClientId);
    return _apis.putIfAbsent(
        config.accountId, () => _createApi(authorization, config.accountId));
  }

  Future<void> refreshSource(Source source, {CancelToken? cancelToken}) {
    if (source.type != SourceType.drive || source.drive == null) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.setupRequired);
    }
    return refreshConfig(
        ProviderConfig(
            type: ProviderType.drive,
            priority: source.priority,
            sourceId: source.id,
            drive: source.drive),
        cancelToken: cancelToken);
  }

  Future<void> refreshConfig(ProviderConfig config,
      {CancelToken? cancelToken}) async {
    _requireConnectedLane();
    final drive = config.drive;
    if (drive == null ||
        !drive.isConfigured ||
        config.sourceId?.isNotEmpty != true) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.setupRequired);
    }
    final scope = DriveCatalogue.scopeKey(
        config.sourceId!, drive.accountId, drive.rootFolderId);
    final existing = _refreshes[scope];
    if (existing != null) {
      await existing;
      return;
    }
    final cancellation = cancelToken ?? CancelToken();
    final operation = catalogue.refresh(
        sourceId: config.sourceId!,
        accountId: drive.accountId,
        rootFolderId: drive.rootFolderId,
        api: apiFor(drive),
        cancelToken: cancellation);
    _refreshes[scope] = operation;
    _refreshCancellation[scope] = cancellation;
    try {
      await operation;
    } finally {
      if (identical(_refreshes[scope], operation)) {
        _refreshes.remove(scope);
        _refreshCancellation.remove(scope);
      }
    }
  }

  void _requireConnectedLane() {
    if (_disconnecting) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.cancelled);
    }
  }

  /// The native account session is app-wide, so disconnect drains every source's
  /// owned refresh and transfer. Settings, catalogue, stage bytes and installed
  /// manifests are retained. Transport teardown follows actual resource drain.
  Future<void> disconnect({bool revoke = false}) async {
    _requireConnectedLane();
    _disconnecting = true;
    _laneGeneration++;
    try {
      for (final cancellation in _refreshCancellation.values) {
        cancellation.cancel();
      }
      final transfers = _transferResults.values.toList();
      for (final transfer in _transfers.values.toList()) {
        transfer.pause();
      }
      // signOut invalidates outstanding grants synchronously. Attach all error
      // handlers immediately and await actual native/refresh completion, not a timer.
      await Future.wait<void>([
        if (_authorization != null) _authorization!.signOut(revoke: revoke),
        for (final refresh in _refreshes.values.toList())
          refresh.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
        ...transfers,
      ]);
    } finally {
      for (final api in _apis.values) {
        api.close();
      }
      _apis.clear();
      for (final media in _mediaApis.values) {
        media.close();
      }
      _mediaApis.clear();
      _disconnecting = false;
    }
  }

  Future<List<DriveFile>> folders(Source source) async {
    final drive = source.drive;
    if (drive == null || !drive.isConfigured) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.setupRequired);
    }
    final generation = await catalogue.activeGeneration(
        sourceId: source.id,
        accountId: drive.accountId,
        rootFolderId: drive.rootFolderId);
    if (generation == null) {
      throw const DriveCatalogueException('refreshRequired');
    }
    final result = <DriveFile>[
      await catalogue.requireFolder(
          sourceId: source.id,
          accountId: drive.accountId,
          rootFolderId: drive.rootFolderId,
          folderId: drive.rootFolderId,
          generation: generation)
    ];
    var offset = 0;
    while (true) {
      final page = await catalogue.entries(
          sourceId: source.id,
          accountId: drive.accountId,
          rootFolderId: drive.rootFolderId,
          folderId: drive.rootFolderId,
          generation: generation,
          limit: 500,
          offset: offset);
      result.addAll(page.where((e) => e.file.isFolder).map((e) => e.file));
      if (page.length < 500) break;
      offset += page.length;
    }
    return result;
  }

  /// Source-level exclusion report from the published snapshot only. Unsupported
  /// records stay inspectable without traversing shortcuts or exporting documents.
  Future<Map<String, int>> unsupportedCounts(Source source) async {
    final drive = source.drive;
    if (drive == null || !drive.isConfigured) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.setupRequired);
    }
    final generation = await catalogue.activeGeneration(
        sourceId: source.id,
        accountId: drive.accountId,
        rootFolderId: drive.rootFolderId);
    if (generation == null) {
      throw const DriveCatalogueException('refreshRequired');
    }
    final counts = <String, int>{};
    var offset = 0;
    while (true) {
      final page = await catalogue.entries(
          sourceId: source.id,
          accountId: drive.accountId,
          rootFolderId: drive.rootFolderId,
          folderId: drive.rootFolderId,
          generation: generation,
          limit: 500,
          offset: offset);
      for (final entry in page) {
        final reason = entry.file.unsupportedReason;
        if (reason != null) {
          counts.update(reason, (count) => count + 1, ifAbsent: () => 1);
        }
      }
      if (page.length < 500) break;
      offset += page.length;
    }
    return Map.unmodifiable(counts);
  }
}
