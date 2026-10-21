import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../drive/drive_authorization.dart';

enum SaveBackupAreaIssue {
  invalidResponse,
  unownedArea,
  incompleteSearch,
  areaLimit,
  accessDenied,
  notFound,
  quota,
  unavailable,
  cancelled,
}

class SaveBackupAreaException implements Exception {
  final SaveBackupAreaIssue issue;
  const SaveBackupAreaException(this.issue);
  @override
  String toString() => 'Save backup area: ${issue.name}';
}

class SaveBackupArea {
  final String id;
  final String accountId;
  const SaveBackupArea._(this.id, this.accountId);
}

/// Save-only setup boundary. No general folder selection, file update, delete,
/// sharing, ROM media or arbitrary URL API is exposed. An existing directory's
/// name and the user's broad read grant cannot establish backup ownership.
class DriveSaveBackupAreaApi {
  static const _folderMime = 'application/vnd.google-apps.folder';
  static const _properties = {'rshopSaveBackup': '1', 'kind': 'area'};
  static const _fields =
      'id,name,mimeType,driveId,ownedByMe,isAppAuthorized,trashed,shared,appProperties';
  static const maxMetadataBytes = 256 * 1024;
  final DriveAuthorization authorization;
  final String accountId;
  final HttpClientAdapter _transport;

  DriveSaveBackupAreaApi(
      {required this.authorization,
      required this.accountId,
      HttpClientAdapter? transport})
      : _transport = transport ?? IOHttpClientAdapter();

  Future<List<SaveBackupArea>> discover({CancelToken? cancellation}) async {
    final areas = <SaveBackupArea>[];
    final pages = <String>{};
    String? page;
    do {
      final data = await _request('GET', 'files',
          query: {
            'q': "trashed = false and mimeType = '$_folderMime' and "
                "appProperties has { key='rshopSaveBackup' and value='1' } and "
                "appProperties has { key='kind' and value='area' }",
            'spaces': 'drive',
            'pageSize': 100,
            'fields': 'nextPageToken,incompleteSearch,files($_fields)',
            if (page != null) 'pageToken': page,
          },
          cancellation: cancellation);
      if (data == null ||
          data['incompleteSearch'] == true ||
          data['files'] is! List) {
        throw const SaveBackupAreaException(
            SaveBackupAreaIssue.incompleteSearch);
      }
      final items = data['files'] as List;
      if (items.length > 100 || items.length + areas.length > 100) {
        // An explicit recoverable setup error, not a truncated successful view.
        throw const SaveBackupAreaException(SaveBackupAreaIssue.areaLimit);
      }
      for (final item in items) {
        final area = _parseArea(item);
        if (areas.any((previous) => previous.id == area.id)) {
          throw const SaveBackupAreaException(
              SaveBackupAreaIssue.invalidResponse);
        }
        areas.add(area);
      }
      final next = data['nextPageToken'];
      if (next != null &&
          (next is! String || next.isEmpty || !pages.add(next))) {
        throw const SaveBackupAreaException(
            SaveBackupAreaIssue.invalidResponse);
      }
      page = next as String?;
    } while (page != null);
    return List.unmodifiable(areas);
  }

  /// Persist this opaque ID as a creation intent BEFORE createReservedArea.
  /// A process/connection loss replays the same ID, not another empty folder.
  Future<String> reserveAreaId({CancelToken? cancellation}) async {
    final data = await _request('GET', 'files/generateIds',
        query: {
          'count': 1,
          'space': 'drive',
          'type': 'files',
          'fields': 'ids',
        },
        cancellation: cancellation);
    final ids = data?['ids'];
    if (ids is! List || ids.length != 1 || !_validId(ids.single)) {
      throw const SaveBackupAreaException(SaveBackupAreaIssue.invalidResponse);
    }
    return ids.single as String;
  }

  Future<SaveBackupArea> verifyArea(String id,
      {CancelToken? cancellation}) async {
    _requireId(id);
    final data = await _request('GET', 'files/${Uri.encodeComponent(id)}',
        query: {'fields': _fields}, cancellation: cancellation);
    if (data == null) {
      throw const SaveBackupAreaException(SaveBackupAreaIssue.notFound);
    }
    return _parseArea(data, expectedId: id);
  }

  Future<SaveBackupArea> createReservedArea(String id,
      {CancelToken? cancellation}) async {
    _requireId(id);
    final previous = await _request('GET', 'files/${Uri.encodeComponent(id)}',
        query: {'fields': _fields}, cancellation: cancellation);
    if (previous != null) return _parseArea(previous, expectedId: id);
    final created = await _request('POST', 'files',
        query: {'fields': _fields},
        body: {
          'id': id,
          'name': 'G-Shop Save Backups',
          'mimeType': _folderMime,
          'parents': ['root'],
          'appProperties': _properties
        },
        cancellation: cancellation);
    if (created == null) {
      throw const SaveBackupAreaException(SaveBackupAreaIssue.invalidResponse);
    }
    return _parseArea(created, expectedId: id);
  }

  SaveBackupArea _parseArea(Object? raw, {String? expectedId}) {
    if (raw is! Map || !_validId(raw['id'])) {
      throw const SaveBackupAreaException(SaveBackupAreaIssue.invalidResponse);
    }
    final id = raw['id'] as String;
    final properties = raw['appProperties'];
    if ((expectedId != null && id != expectedId) ||
        raw['mimeType'] != _folderMime ||
        raw['ownedByMe'] != true ||
        raw['isAppAuthorized'] != true ||
        raw['trashed'] != false ||
        raw['shared'] != false ||
        raw['driveId'] != null ||
        properties is! Map ||
        _properties.entries
            .any((entry) => properties[entry.key] != entry.value)) {
      throw const SaveBackupAreaException(SaveBackupAreaIssue.unownedArea);
    }
    return SaveBackupArea._(id, accountId);
  }

  bool _validId(Object? id) =>
      id is String && RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(id);
  void _requireId(String id) {
    if (!_validId(id)) {
      throw const SaveBackupAreaException(SaveBackupAreaIssue.invalidResponse);
    }
  }

  void _check(CancelToken? cancellation) {
    if (cancellation?.isCancelled == true) {
      throw const SaveBackupAreaException(SaveBackupAreaIssue.cancelled);
    }
  }

  Future<Map<String, dynamic>?> _request(String method, String path,
      {required Map<String, Object> query,
      Map<String, Object>? body,
      CancelToken? cancellation}) async {
    try {
      String? rejected;
      final encoded = body == null
          ? null
          : Uint8List.fromList(utf8.encode(jsonEncode(body)));
      for (var attempt = 0; attempt < 2; attempt++) {
        _check(cancellation);
        final grant = await authorization.acquireBackup(
            expectedAccountId: accountId, rejectedToken: rejected);
        _check(cancellation);
        final request = RequestOptions(
            baseUrl: 'https://www.googleapis.com/drive/v3/',
            path: path,
            method: method,
            queryParameters: query,
            followRedirects: false,
            responseType: ResponseType.stream,
            headers: {
              'Authorization': 'Bearer ${grant.accessToken}',
              'Accept-Encoding': 'identity',
              if (encoded != null)
                'Content-Type': 'application/json; charset=UTF-8',
              if (encoded != null) 'Content-Length': encoded.length
            });
        final response = await _transport.fetch(
            request,
            encoded == null ? null : Stream.value(encoded),
            cancellation?.whenCancel);
        final status = response.statusCode;
        if (status != 200 && status != 201) {
          await response.stream.listen((_) {}).cancel();
          _check(cancellation);
          if (status == 401 && attempt == 0) {
            rejected = grant.accessToken;
            continue;
          }
          if (status == 401) {
            throw const DriveAuthorizationException(
                DriveAuthorizationIssue.interactionRequired);
          }
          if (status == 404 && method == 'GET') return null;
          throw SaveBackupAreaException(switch (status) {
            403 => SaveBackupAreaIssue.accessDenied,
            404 => SaveBackupAreaIssue.notFound,
            429 => SaveBackupAreaIssue.quota,
            _ => SaveBackupAreaIssue.unavailable,
          });
        }
        final bytes = BytesBuilder(copy: false);
        // Subscribe even when cancellation happened during fetch: the stream
        // must have an owner which cancels the underlying native response.
        await for (final chunk in response.stream) {
          _check(cancellation);
          if (chunk.length > maxMetadataBytes ||
              bytes.length + chunk.length > maxMetadataBytes) {
            throw const SaveBackupAreaException(
                SaveBackupAreaIssue.invalidResponse);
          }
          bytes.add(chunk);
        }
        _check(cancellation);
        final data = jsonDecode(utf8.decode(bytes.takeBytes()));
        if (data is! Map<String, dynamic>) {
          throw const SaveBackupAreaException(
              SaveBackupAreaIssue.invalidResponse);
        }
        return data;
      }
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.interactionRequired);
    } on DriveAuthorizationException {
      rethrow;
    } on SaveBackupAreaException {
      rethrow;
    } catch (_) {
      throw SaveBackupAreaException(cancellation?.isCancelled == true
          ? SaveBackupAreaIssue.cancelled
          : SaveBackupAreaIssue.unavailable);
    }
  }

  void close() => _transport.close();
}
