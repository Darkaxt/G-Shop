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

/// Read-only transport for the published shop catalogue (spec revision 186).
/// Never writes Drive and never accepts a ROM source URL.
abstract interface class MetadataCloudRemote {
  /// The single catalogue root folder in My Drive, or null when absent.
  Future<MetadataCloudFile?> findRoot();
  Future<MetadataCloudFile?> get(String id);
  Future<List<MetadataCloudFile>> children(String parent);
  Future<void> download(MetadataCloudFile remote, File target);
}

class DriveMetadataApi implements MetadataCloudRemote {
  final DriveAuthorization authorization;
  final String accountId;
  final Dio _http;
  static const maxRecordBytes = 8 * 1024 * 1024;
  static const _fields = 'id,name,mimeType,parents,trashed,size,sha256Checksum';
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

  /// Catalogue objects are trusted by content, not by who wrote them:
  /// Windows publishes through Google Drive for desktop. Folders carry no
  /// digest; files use Drive's own SHA-256. Unknown types are ignored.
  MetadataCloudFile? _file(Map<String, dynamic> json) {
    final id = json['id'] as String;
    _id(id);
    final name = json['name'] as String;
    final parents = json['parents'] as List? ?? const [];
    final folder = json['mimeType'] == 'application/vnd.google-apps.folder';
    final extension = name.contains('.') ? name.split('.').last : '';
    final kind = folder
        ? 'folder'
        : const {
            'png': 'artwork',
            'mp4': 'video',
            'json': 'records'
          }[extension.toLowerCase()];
    if (kind == null || parents.length > 1) return null;
    final bytes = folder ? 0 : int.tryParse('${json['size']}');
    final digest = folder ? null : json['sha256Checksum'] as String?;
    if (bytes == null ||
        bytes < 0 ||
        (!folder && !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest ?? ''))) {
      return null; // Not yet uploaded completely; leave it absent.
    }
    return MetadataCloudFile(
        id: id,
        name: name,
        parent: parents.isEmpty ? null : parents.single as String,
        kind: kind,
        digest: digest,
        checksum: digest,
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
      // The catalogue is read with the existing read-only Drive grant.
      final grant = await authorization.acquire(
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

  static const rootNames = {'G-Shop Metadata', 'R-Shop Metadata'};

  @override
  Future<MetadataCloudFile?> findRoot() async {
    final roots = await _list("'root' in parents and mimeType = "
        "'application/vnd.google-apps.folder' and trashed = false and "
        "(${rootNames.map((n) => "name = '$n'").join(' or ')})");
    if (roots.length > 1) {
      throw const FormatException('More than one catalogue root folder');
    }
    return roots.firstOrNull;
  }

  @override
  Future<MetadataCloudFile?> get(String id) async {
    _id(id);
    final json = await _json('drive/v3/files/$id', 'GET',
        query: {'fields': _fields}, notFound: true);
    return json == null ? null : _file(json);
  }

  @override
  Future<List<MetadataCloudFile>> children(String parent) async {
    _id(parent);
    final result = await _list("trashed = false and '$parent' in parents");
    if (result.any((f) => f.parent != parent)) {
      throw const FormatException('Changed catalogue folder membership');
    }
    return result;
  }

  Future<List<MetadataCloudFile>> _list(String q) async {
    final result = <MetadataCloudFile>[];
    final pages = <String>{};
    String? page;
    do {
      final json = (await _json('drive/v3/files', 'GET', query: {
        'q': q,
        'spaces': 'drive',
        'pageSize': 1000,
        'fields': 'nextPageToken,incompleteSearch,files($_fields)',
        if (page != null) 'pageToken': page,
      }))!;
      if (json['incompleteSearch'] == true || json['files'] is! List) {
        throw const FormatException('Incomplete catalogue listing');
      }
      for (final item in json['files'] as List) {
        final file = _file((item as Map).cast<String, dynamic>());
        if (file != null && !result.any((v) => v.id == file.id)) {
          result.add(file);
        }
      }
      page = json['nextPageToken'] as String?;
      if (page != null && (page.isEmpty || !pages.add(page))) {
        throw const FormatException('Invalid catalogue listing continuation');
      }
    } while (page != null);
    return result;
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

}
