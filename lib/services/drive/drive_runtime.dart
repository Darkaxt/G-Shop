import 'package:dio/dio.dart';

import '../../models/config/drive_source_config.dart';
import '../../models/config/provider_config.dart';
import '../../models/config/source.dart';
import '../database_service.dart';
import 'drive_api.dart';
import 'drive_authorization.dart';
import 'drive_catalogue.dart';
import 'google_drive_sign_in.dart';

/// Process-wide native account lane and source-scoped refresh jobs. No token
/// resides in provider configs or download items. Background calls never consent.
class DriveRuntime {
  static final instance = DriveRuntime();
  DriveCatalogue? _catalogue;
  DriveCatalogue get catalogue =>
      _catalogue ??= DriveCatalogue(DatabaseService().database);
  final DriveAuthorization Function(String) _createAuthorization;
  DriveAuthorization? _authorization;
  String? _clientId;
  final _apis = <String, DriveApi>{};
  final _refreshes = <String, Future<void>>{};
  final _refreshCancellation = <String, CancelToken>{};
  bool _disconnecting = false;

  DriveRuntime(
      {DriveCatalogue? catalogue,
      DriveAuthorization Function(String)? createAuthorization})
      : _catalogue = catalogue,
        _createAuthorization = createAuthorization ??
            ((id) => DriveAuthorization(GoogleDriveSignIn(serverClientId: id)));

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
        config.accountId,
        () => DriveApi(
            authorization: authorization, accountId: config.accountId));
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
  /// owned refresh. Settings, published catalogue and installed files are retained.
  Future<void> disconnect({bool revoke = false}) async {
    _requireConnectedLane();
    _disconnecting = true;
    try {
      for (final cancellation in _refreshCancellation.values) {
        cancellation.cancel();
      }
      // signOut invalidates outstanding grants synchronously. Attach all error
      // handlers immediately and await actual native/refresh completion, not a timer.
      await Future.wait<void>([
        if (_authorization != null) _authorization!.signOut(revoke: revoke),
        for (final refresh in _refreshes.values.toList())
          refresh.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      ]);
    } finally {
      for (final api in _apis.values) {
        api.close();
      }
      _apis.clear();
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
