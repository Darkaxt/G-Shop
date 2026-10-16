import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../drive/drive_authorization.dart';

class MetadataCloudFile {
  final String id, name, kind;
  final String? parent, digest, checksum, etag;
  final int bytes;
  final bool trashed;
  const MetadataCloudFile(
      {required this.id,
      required this.name,
      required this.kind,
      this.parent,
      this.digest,
      this.checksum,
      this.etag,
      this.bytes = 0,
      this.trashed = false});
}

/// Narrow transport for app-owned metadata. Never accepts a ROM source URL.
abstract interface class MetadataCloudRemote {
  Future<String> reserveId();
  Future<MetadataCloudFile?> get(String id);
  Future<List<MetadataCloudFile>> children(String? parent);
  Future<void> folder(String id, String? parent, String name);
  Future<void> upload(String id, String parent, String name, String kind,
      File file, String digest, int bytes,
      {String? replacesDigest});
  Future<void> download(MetadataCloudFile remote, File target);
  Future<void> relocate(MetadataCloudFile file, String parent);
  Future<void> trash(MetadataCloudFile file);
}

class DriveMetadataApi implements MetadataCloudRemote {
  final DriveAuthorization authorization;
  final String accountId;
  final Dio _http;
  static const maxRecordBytes = 8 * 1024 * 1024;
  static const _fields = 'id,name,mimeType,parents,ownedByMe,isAppAuthorized,'
      'trashed,shared,driveId,appProperties,size,sha256Checksum';
  DriveMetadataApi(
      {required this.authorization,
      required this.accountId,
      HttpClientAdapter? adapter})
      : _http = Dio(BaseOptions(
            followRedirects: false,
            validateStatus: (_) => true,
            responseType: ResponseType.stream)) {
    if (adapter != null) _http.httpClientAdapter = adapter;
  }
  void close() => _http.close();
  static void _id(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,256}$').hasMatch(id)) {
      throw const FormatException('Invalid metadata object identity');
    }
  }

  MetadataCloudFile _file(Map<String, dynamic> json,
      {bool allowTrashed = false}) {
    final props = (json['appProperties'] as Map?) ?? const {};
    final parents = json['parents'] as List? ?? const [];
    final folder = json['mimeType'] == 'application/vnd.google-apps.folder';
    if (json['ownedByMe'] != true ||
        json['isAppAuthorized'] != true ||
        (json['trashed'] != false &&
            !(allowTrashed && json['trashed'] == true)) ||
        json['shared'] != false ||
        json['driveId'] != null ||
        props['rshopMetadata'] != '1' ||
        parents.length > 1 ||
        (props['kind'] != 'root' && parents.length != 1) ||
        !{'root', 'folder', 'artwork', 'video', 'records'}
            .contains(props['kind']) ||
        folder != {'root', 'folder'}.contains(props['kind'])) {
      throw const FormatException('Not an owned R-Shop metadata object');
    }
    final id = json['id'] as String;
    _id(id);
    final bytes = folder ? 0 : int.tryParse(json['size'].toString());
    final digest = props['sha256'] as String?;
    if (bytes == null ||
        bytes < 0 ||
        (!folder && !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest ?? ''))) {
      throw const FormatException('Invalid metadata object size/digest');
    }
    return MetadataCloudFile(
        id: id,
        name: json['name'] as String,
        parent: props['kind'] == 'root' ? null : parents.single as String,
        kind: folder ? 'folder' : props['kind'] as String,
        digest: digest,
        checksum: json['sha256Checksum'] as String?,
        etag: json['_responseEtag'] as String?,
        bytes: bytes,
        trashed: json['trashed'] == true);
  }

  Future<Response<ResponseBody>?> _send(String path, String method,
      {Map<String, dynamic>? query,
      Object? Function()? body,
      String? contentType,
      int? length,
      String? ifMatch,
      bool notFound = false}) async {
    String? rejected;
    for (var attempt = 0; attempt < 2; attempt++) {
      final grant = await authorization.acquireMetadata(
          expectedAccountId: accountId, rejectedToken: rejected);
      Response<ResponseBody> response;
      try {
        response = await _http.request<ResponseBody>(
            'https://www.googleapis.com/$path',
            queryParameters: query,
            data: body?.call(),
            options: Options(method: method, headers: {
              'Authorization': 'Bearer ${grant.accessToken}',
              if (contentType != null) 'Content-Type': contentType,
              if (length != null) 'Content-Length': length,
              if (ifMatch != null) 'If-Match': ifMatch,
            }));
      } on DioException {
        throw const FileSystemException('Google Drive metadata is unavailable');
      }
      if (response.statusCode == 401 && attempt == 0) {
        await response.data?.stream.listen((_) {}).cancel();
        rejected = grant.accessToken;
        continue;
      }
      if (response.statusCode == 404 && notFound) {
        await response.data?.stream.listen((_) {}).cancel();
        return null;
      }
      if (response.statusCode != 200 && response.statusCode != 201) {
        // Provider reason codes identify permission/quota failures without
        // exposing response messages, file identities or authorization data.
        var reason = 'unknown';
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.data!.stream) {
          if (bytes.length + chunk.length > 8192) {
            bytes.clear();
            break;
          }
          bytes.add(chunk);
        }
        try {
          final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
          final error = decoded is Map ? decoded['error'] : null;
          final errors = error is Map ? error['errors'] : null;
          final code =
              errors is List && errors.isNotEmpty && errors.first is Map
                  ? (errors.first as Map)['reason']
                  : null;
          if (code is String &&
              RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,79}$').hasMatch(code)) {
            reason = code;
          }
        } on FormatException {
          // Non-JSON and oversized errors retain the status-only diagnostic.
        }
        debugPrint(
            'Metadata Drive request failed: HTTP ${response.statusCode} method=$method api=${path.contains('/v2/') ? 'v2' : 'v3'} reason=$reason');
        throw const FileSystemException('Google Drive metadata request failed');
      }
      return response;
    }
    throw const DriveAuthorizationException(
        DriveAuthorizationIssue.interactionRequired);
  }

  Future<Map<String, dynamic>?> _json(String path, String method,
      {Map<String, dynamic>? query,
      Map<String, dynamic>? body,
      String? ifMatch,
      bool notFound = false}) async {
    final response = await _send(path, method,
        query: query,
        ifMatch: ifMatch,
        notFound: notFound,
        body: body == null ? null : () => jsonEncode(body),
        contentType: body == null ? null : 'application/json');
    if (response == null) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.data!.stream) {
      if (bytes.length + chunk.length > maxRecordBytes) {
        throw const FormatException(
            'Metadata response exceeds its body budget');
      }
      bytes.add(chunk);
    }
    final result = (jsonDecode(utf8.decode(bytes.takeBytes())) as Map)
        .cast<String, dynamic>();
    result['_responseEtag'] = response.headers.value('etag');
    return result;
  }

  @override
  Future<String> reserveId() async {
    final json = await _json('drive/v3/files/generateIds', 'GET',
        query: {'count': 1, 'space': 'drive', 'type': 'files'});
    final id = (json!['ids'] as List).single as String;
    _id(id);
    return id;
  }

  @override
  Future<MetadataCloudFile?> get(String id) => _get(id);

  Future<MetadataCloudFile?> _get(String id,
      {bool allowTrashed = false}) async {
    _id(id);
    final json = await _json('drive/v3/files/$id', 'GET',
        query: {'fields': _fields}, notFound: true);
    return json == null ? null : _file(json, allowTrashed: allowTrashed);
  }

  @override
  Future<List<MetadataCloudFile>> children(String? parent) => _children(parent);

  Future<List<MetadataCloudFile>> _children(String? parent,
      {bool allVisible = false, bool includeTrashed = false}) async {
    if (parent != null) _id(parent);
    final result = <MetadataCloudFile>[];
    final pages = <String>{};
    String? page;
    do {
      final json = (await _json('drive/v3/files', 'GET', query: {
        'q': "${includeTrashed ? '' : 'trashed = false and '}"
            "${allVisible ? '' : "appProperties has { key='rshopMetadata' and value='1' } and "}"
            '${parent == null ? "appProperties has { key='kind' and value='root' }" : "'$parent' in parents"}',
        'spaces': 'drive',
        'pageSize': 100,
        'fields': 'nextPageToken,incompleteSearch,files($_fields)',
        if (page != null) 'pageToken': page,
      }))!;
      if (json['incompleteSearch'] == true || json['files'] is! List) {
        throw const FormatException('Incomplete metadata listing');
      }
      for (final item in json['files'] as List) {
        final file = _file((item as Map).cast<String, dynamic>(),
            allowTrashed: includeTrashed);
        if (file.parent != parent || result.any((v) => v.id == file.id)) {
          throw const FormatException('Changed metadata folder membership');
        }
        result.add(file);
      }
      page = json['nextPageToken'] as String?;
      if (page != null && (page.isEmpty || !pages.add(page))) {
        throw const FormatException('Invalid metadata listing continuation');
      }
    } while (page != null);
    return result;
  }

  @override
  Future<void> folder(String id, String? parent, String name) async {
    _id(id);
    if (parent != null) _id(parent);
    final existing = await get(id);
    if (existing != null) {
      if (existing.kind != 'folder' ||
          existing.parent != parent ||
          existing.name != name) {
        throw const FormatException('Metadata folder intent changed');
      }
      return;
    }
    await _json('drive/v3/files', 'POST', body: {
      'id': id,
      'name': name,
      'mimeType': 'application/vnd.google-apps.folder',
      if (parent != null) 'parents': [parent],
      'appProperties': {
        'rshopMetadata': '1',
        'kind': parent == null ? 'root' : 'folder'
      },
    });
    final created = await get(id);
    if (created?.kind != 'folder' ||
        created?.parent != parent ||
        created?.name != name) {
      throw const FormatException(
          'Metadata folder publication was not verified');
    }
  }

  @override
  Future<void> upload(String id, String parent, String name, String kind,
      File file, String digest, int bytes,
      {String? replacesDigest}) async {
    _id(id);
    _id(parent);
    final existing = await get(id);
    if (existing != null) {
      if (existing.parent != parent ||
          existing.name != name ||
          existing.kind != kind) {
        throw const FormatException('Metadata publication intent changed');
      }
      if (existing.digest == digest && existing.bytes == bytes) return;
      if (existing.digest != replacesDigest) {
        throw const FormatException('Metadata publication changed remotely');
      }
    }
    if (!{'artwork', 'video', 'records'}.contains(kind)) {
      throw const FormatException('Unsupported metadata payload');
    }
    final version = existing == null ? null : await _mutationVersion(existing);
    const boundary = 'rshop_metadata_object';
    final prefix = utf8.encode(
        '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'
        '${jsonEncode({
          if (existing == null) 'id': id,
          if (existing == null) 'name': name else 'title': name,
          if (existing == null) 'parents': [parent],
          'mimeType': {
            'artwork': 'image/png',
            'video': 'video/mp4',
            'records': 'application/json'
          }[kind],
          if (existing == null)
            'appProperties': {
              'rshopMetadata': '1',
              'kind': kind,
              'sha256': digest
            }
          else
            'properties': [
              for (final property in version!.properties)
                if (property['key'] != 'sha256' ||
                    property['visibility'] != 'PRIVATE')
                  property,
              {'key': 'sha256', 'value': digest, 'visibility': 'PRIVATE'},
            ],
        })}'
        '\r\n--$boundary\r\nContent-Type: application/octet-stream\r\n\r\n');
    final suffix = utf8.encode('\r\n--$boundary--\r\n');
    Stream<List<int>> body() async* {
      yield prefix;
      yield* file.openRead();
      yield suffix;
    }

    final response = await _send(
        existing == null
            ? 'upload/drive/v3/files'
            : 'upload/drive/v2/files/$id',
        existing == null ? 'POST' : 'PATCH',
        query: {'uploadType': 'multipart', 'fields': 'id'},
        body: body,
        contentType: 'multipart/related; boundary=$boundary',
        ifMatch: version?.etag,
        length: prefix.length + bytes + suffix.length);
    await response?.data?.stream.drain<void>();
  }

  // Drive v3 removed File.etag and does not promise an HTTP response ETag.
  // The documented v2 resource and patch endpoint retain native conditional
  // writes. Revalidate the same app-owned identity in that representation; no
  // additional OAuth scope or unguarded write fallback is introduced.
  Future<({String etag, List<Map<String, dynamic>> properties})>
      _mutationVersion(MetadataCloudFile file) async {
    final json = (await _json('drive/v2/files/${file.id}', 'GET', query: {
      'fields': 'id,title,mimeType,parents(id),ownedByMe,isAppAuthorized,'
          'labels(trashed),shared,driveId,properties,etag,fileSize',
    }))!;
    final properties = (json['properties'] as List? ?? const [])
        .map((p) => (p as Map).cast<String, dynamic>())
        .toList();
    final private = {
      for (final p in properties)
        if (p['visibility'] == 'PRIVATE') p['key']: p['value']
    };
    final parents = json['parents'] as List? ?? const [];
    final folder = json['mimeType'] == 'application/vnd.google-apps.folder';
    if (json['id'] != file.id ||
        json['title'] != file.name ||
        json['ownedByMe'] != true ||
        json['isAppAuthorized'] != true ||
        (json['labels'] as Map?)?['trashed'] != file.trashed ||
        json['shared'] != false ||
        json['driveId'] != null ||
        parents.length != 1 ||
        (parents.single as Map)['id'] != file.parent ||
        private['rshopMetadata'] != '1' ||
        private['kind'] != file.kind ||
        folder != (file.kind == 'folder') ||
        private['sha256'] != file.digest ||
        (!folder && int.tryParse('${json['fileSize']}') != file.bytes) ||
        json['etag'] is! String ||
        (json['etag'] as String).isEmpty) {
      throw const FormatException('Metadata version changed remotely');
    }
    return (etag: json['etag'] as String, properties: properties);
  }

  @override
  Future<void> download(MetadataCloudFile remote, File target) async {
    _id(remote.id);
    final response = await _send('drive/v3/files/${remote.id}', 'GET',
        query: {'alt': 'media'});
    final writer = await target.open(mode: FileMode.write);
    var received = 0;
    try {
      await for (final chunk in response!.data!.stream) {
        received += chunk.length;
        if (received > remote.bytes)
          throw const FormatException('Metadata media exceeds its receipt');
        await writer.writeFrom(chunk);
      }
      await writer.flush();
      if (received != remote.bytes)
        throw const FormatException('Metadata media is truncated');
    } finally {
      await writer.close();
    }
  }

  @override
  Future<void> relocate(MetadataCloudFile file, String parent) =>
      _relocate(file, parent);

  Future<void> _relocate(MetadataCloudFile file, String parent,
      {bool allowTrashed = false}) async {
    _id(parent);
    final current = await _get(file.id, allowTrashed: allowTrashed);
    if (current == null ||
        current.name != file.name ||
        current.kind != file.kind ||
        current.digest != file.digest ||
        current.bytes != file.bytes ||
        current.trashed != file.trashed) {
      throw const FormatException('Metadata archive changed remotely');
    }
    if (current.parent == parent) return;
    if (current.parent != file.parent) {
      throw const FormatException('Metadata archive membership changed');
    }
    final version = await _mutationVersion(current);
    final response = await _send('drive/v2/files/${file.id}', 'PATCH',
        query: {
          'addParents': parent,
          'removeParents': current.parent,
          'fields': 'id'
        },
        ifMatch: version.etag);
    await response?.data?.stream.drain<void>();
    final moved = await _get(file.id, allowTrashed: allowTrashed);
    if (moved?.parent != parent ||
        moved?.name != file.name ||
        moved?.digest != file.digest ||
        moved?.bytes != file.bytes ||
        moved?.trashed != file.trashed) {
      throw const FormatException('Metadata archive move was not verified');
    }
  }

  /// Explicit rebuild only. Trash is recoverable; never delete the metadata root.
  @override
  Future<void> trash(MetadataCloudFile file) async {
    if (file.parent == null) {
      throw const FormatException('Metadata rebuild target changed remotely');
    }
    await _trashTree(file, file.parent!, detach: false);
  }

  Future<void> _trashTree(MetadataCloudFile file, String root,
      {required bool detach}) async {
    var current = await _get(file.id, allowTrashed: true);
    if (current == null) return;
    if (current.parent == null ||
        current.parent != file.parent ||
        current.name != file.name ||
        current.kind != file.kind ||
        current.digest != file.digest ||
        current.bytes != file.bytes) {
      throw const FormatException('Metadata rebuild target changed remotely');
    }
    if (current.kind == 'folder') {
      // Trashed children retain parent membership and still trigger Drive's
      // descendant access check. Detach every verified descendant into the
      // preserved metadata root, retaining its trash state, before retiring its
      // genuinely empty parent. Normal publication never accepts trashed files.
      for (final child in await _children(current.id,
          allVisible: true, includeTrashed: true)) {
        await _trashTree(child, root, detach: true);
      }
      if ((await _children(current.id, allVisible: true, includeTrashed: true))
          .isNotEmpty) {
        throw const FormatException('Metadata rebuild is incomplete');
      }
    }
    if (detach && current.parent != root) {
      await _relocate(current, root, allowTrashed: true);
      current = (await _get(current.id, allowTrashed: true))!;
    }
    if (current.trashed) return;
    final version = await _mutationVersion(current);
    final result = await _json('drive/v2/files/${file.id}', 'PATCH',
        query: {'fields': 'id,labels(trashed)'},
        body: {
          'labels': {'trashed': true}
        },
        ifMatch: version.etag);
    if (result?['id'] != file.id ||
        (result?['labels'] as Map?)?['trashed'] != true) {
      throw const FormatException('Metadata rebuild trash was not verified');
    }
  }
}
