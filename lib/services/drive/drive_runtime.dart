import 'package:dio/dio.dart';

import '../../models/config/drive_source_config.dart';
import '../../models/config/provider_config.dart';
import '../../models/config/source.dart';
import '../database_service.dart';
import '../owned_storage.dart';
import '../transfer_journal.dart';
import 'drive_api.dart';
import 'drive_authorization.dart';
import 'drive_catalogue.dart';
import 'drive_download_boundary.dart';
import 'drive_media.dart';
import 'drive_transfer_engine.dart';
import 'google_drive_sign_in.dart';

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

  /// Starts only an already reserved exact transfer. The normal queue remains
  /// responsible for choosing when to invoke this API; it does not enqueue files.
  Future<DriveTransferOperation> startTransfer({
    required ProviderConfig config,
    required String transferId,
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
      final operation = engine.start(transferId);
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
