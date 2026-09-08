import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/library_identity.dart';
import 'drive_authorization.dart';

enum DriveApiIssue {
  invalidResponse,
  incompleteSearch,
  unavailable,
  accessDenied,
  notFound,
  quota,
  invalidPageToken,
  cancelled,
  unsupported
}

/// Only typed, sanitized errors cross the HTTP boundary. Never include a Dio
/// request, response body, file listing, or bearer token in diagnostics.
class DriveApiException implements Exception {
  final DriveApiIssue issue;
  const DriveApiException(this.issue);
  @override
  String toString() => 'Google Drive: ${issue.name}';
}

class DriveFile {
  static const folderMime = 'application/vnd.google-apps.folder';
  final String id;
  final String name;
  final String mimeType;
  final List<String> parents;
  final String? driveId;
  final bool trashed;
  final int? sizeBytes;
  final String? version;
  final DateTime? modifiedAt;
  final Map<String, String> checksums;
  final bool? canDownload;

  DriveFile(
      {required this.id,
      required this.name,
      required this.mimeType,
      required List<String> parents,
      this.driveId,
      this.trashed = false,
      this.sizeBytes,
      this.version,
      this.modifiedAt,
      Map<String, String> checksums = const {},
      this.canDownload})
      : parents = List.unmodifiable(parents),
        checksums = Map.unmodifiable(checksums);

  bool get isFolder => mimeType == folderMime && driveId == null && !trashed;
  String? get unsupportedReason {
    if (trashed) return 'trashed';
    if (driveId != null) return 'sharedDrive';
    if (mimeType == 'application/vnd.google-apps.shortcut') return 'shortcut';
    if (mimeType.startsWith('application/vnd.google-apps.') &&
        mimeType != folderMime) {
      return 'workspaceDocument';
    }
    return null;
  }

  bool get isSupportedBinary => !isFolder && unsupportedReason == null;

  factory DriveFile.fromJson(Map<String, dynamic> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw const DriveApiException(DriveApiIssue.invalidResponse);
      }
      return value;
    }

    final rawSize = json['size'];
    final size = rawSize == null ? null : int.tryParse(rawSize.toString());
    if (rawSize != null && (size == null || size < 0)) {
      throw const DriveApiException(DriveApiIssue.invalidResponse);
    }
    final modified = json['modifiedTime'] as String?;
    final at = modified == null ? null : DateTime.tryParse(modified);
    if (modified != null && at == null) {
      throw const DriveApiException(DriveApiIssue.invalidResponse);
    }
    return DriveFile(
        id: requiredString('id'),
        name: requiredString('name'),
        mimeType: requiredString('mimeType'),
        parents: (json['parents'] as List? ?? const []).cast<String>(),
        driveId: json['driveId'] as String?,
        trashed: json['trashed'] as bool? ?? false,
        sizeBytes: size,
        version: json['version'] as String?,
        modifiedAt: at,
        checksums: {
          for (final algorithm in ['md5', 'sha1', 'sha256'])
            if (json['${algorithm}Checksum'] is String)
              algorithm: json['${algorithm}Checksum'] as String,
        },
        canDownload: (json['capabilities'] as Map?)?['canDownload'] as bool?);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mimeType': mimeType,
        'parents': parents,
        if (driveId != null) 'driveId': driveId,
        'trashed': trashed,
        if (sizeBytes != null) 'size': sizeBytes.toString(),
        if (version != null) 'version': version,
        if (modifiedAt != null)
          'modifiedTime': modifiedAt!.toUtc().toIso8601String(),
        for (final hash in checksums.entries) '${hash.key}Checksum': hash.value,
        'capabilities': {if (canDownload != null) 'canDownload': canDownload},
      };

  RemoteArtifact artifact(
          {required String sourceId,
          required String accountId,
          required String displayPath}) =>
      RemoteArtifact(
          id: RemoteArtifactId(
              providerId: 'drive',
              sourceId: sourceId,
              accountId: accountId,
              providerFileId: id),
          parentId: parents.length == 1 ? parents.single : null,
          displayName: name,
          displayPath: displayPath,
          sizeBytes: sizeBytes,
          version: version,
          modifiedAt: modifiedAt,
          providerChecksums: checksums,
          canDownload: canDownload);
}

class DriveFilePage {
  final List<DriveFile> files;
  final String? nextPageToken;
  DriveFilePage({required List<DriveFile> files, this.nextPageToken})
      : files = List.unmodifiable(files);
}

abstract interface class DriveCatalogueApi {
  Future<DriveFile> getFile(String id, {CancelToken? cancelToken});
  Future<DriveFilePage> listChildren(String parentId,
      {String? pageToken, bool foldersOnly = false, CancelToken? cancelToken});
}

/// Read-only Drive v3 metadata. This type deliberately exposes no media or
/// mutation methods. Each list is a bounded page of one observed parent.
class DriveApi implements DriveCatalogueApi {
  static const maxMetadataBytes = 4 * 1024 * 1024;
  static const pageSize = 100;
  static const _fields =
      'id,name,mimeType,parents,driveId,trashed,size,version,'
      'modifiedTime,md5Checksum,sha1Checksum,sha256Checksum,capabilities(canDownload)';
  final DriveAuthorization authorization;
  final String accountId;
  final Dio _dio;

  DriveApi(
      {required this.authorization,
      required this.accountId,
      HttpClientAdapter? httpClientAdapter})
      : _dio = Dio(BaseOptions(
            baseUrl: 'https://www.googleapis.com/drive/v3/',
            followRedirects: false,
            responseType: ResponseType.stream,
            validateStatus: (_) => true)) {
    if (httpClientAdapter != null) _dio.httpClientAdapter = httpClientAdapter;
  }
  void close() => _dio.close();

  @override
  Future<DriveFile> getFile(String id, {CancelToken? cancelToken}) async {
    final json = await _get(
        'files/${Uri.encodeComponent(id)}', {'fields': _fields}, cancelToken);
    try {
      return DriveFile.fromJson(json);
    } on DriveApiException {
      rethrow;
    } catch (_) {
      throw const DriveApiException(DriveApiIssue.invalidResponse);
    }
  }

  @override
  Future<DriveFilePage> listChildren(String parentId,
      {String? pageToken,
      bool foldersOnly = false,
      CancelToken? cancelToken}) async {
    if (parentId.isEmpty) {
      throw const DriveApiException(DriveApiIssue.invalidResponse);
    }
    final escaped = parentId.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    final json = await _get(
        'files',
        {
          'q': "'$escaped' in parents and trashed = false"
              // Include shortcuts so the folder selector can explain unsupported entries.
              "${foldersOnly ? " and (mimeType = '${DriveFile.folderMime}' or mimeType = 'application/vnd.google-apps.shortcut')" : ''}",
          'corpora': 'user',
          'spaces': 'drive',
          'includeItemsFromAllDrives': false,
          'supportsAllDrives': false,
          'pageSize': pageSize,
          'fields': 'nextPageToken,incompleteSearch,files($_fields)',
          if (pageToken != null) 'pageToken': pageToken,
        },
        cancelToken);
    try {
      if (json['incompleteSearch'] == true) {
        throw const DriveApiException(DriveApiIssue.incompleteSearch);
      }
      final files = json['files'] as List?;
      if (files == null || files.length > pageSize) {
        throw const DriveApiException(DriveApiIssue.invalidResponse);
      }
      final token = json['nextPageToken'] as String?;
      if (token?.isEmpty == true) {
        throw const DriveApiException(DriveApiIssue.invalidResponse);
      }
      return DriveFilePage(
          files: files
              .map(
                  (e) => DriveFile.fromJson((e as Map).cast<String, dynamic>()))
              .toList(),
          nextPageToken: token);
    } on DriveApiException {
      rethrow;
    } catch (_) {
      throw const DriveApiException(DriveApiIssue.invalidResponse);
    }
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, dynamic> query,
      CancelToken? cancellation) async {
    try {
      String? rejected;
      for (var attempt = 0; attempt < 2; attempt++) {
        if (cancellation?.isCancelled == true) {
          throw const DriveApiException(DriveApiIssue.cancelled);
        }
        final grant = await authorization.acquire(
            expectedAccountId: accountId, rejectedToken: rejected);
        final response = await _dio.get<ResponseBody>(path,
            queryParameters: query,
            options: Options(
                headers: {'Authorization': 'Bearer ${grant.accessToken}'}),
            cancelToken: cancellation);
        final body = response.data;
        if (body == null) {
          throw const DriveApiException(DriveApiIssue.invalidResponse);
        }
        final status = response.statusCode;
        if (status != 200) {
          // Cancel without buffering or logging an untrusted error payload.
          await body.stream.listen((_) {}).cancel();
          if (status == 401 && attempt == 0) {
            rejected = grant.accessToken;
            continue;
          }
          if (status == 401) {
            throw const DriveAuthorizationException(
                DriveAuthorizationIssue.interactionRequired);
          }
          throw DriveApiException(switch (status) {
            403 => DriveApiIssue.accessDenied,
            404 => DriveApiIssue.notFound,
            429 => DriveApiIssue.quota,
            400 when query.containsKey('pageToken') =>
              DriveApiIssue.invalidPageToken,
            _ => DriveApiIssue.unavailable,
          });
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in body.stream) {
          if (cancellation?.isCancelled == true) {
            throw const DriveApiException(DriveApiIssue.cancelled);
          }
          if (bytes.length + chunk.length > maxMetadataBytes) {
            throw const DriveApiException(DriveApiIssue.invalidResponse);
          }
          bytes.add(chunk);
        }
        return (jsonDecode(utf8.decode(bytes.takeBytes())) as Map)
            .cast<String, dynamic>();
      }
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.interactionRequired);
    } on DriveApiException {
      rethrow;
    } on DriveAuthorizationException {
      rethrow;
    } on DioException catch (e) {
      throw DriveApiException(e.type == DioExceptionType.cancel
          ? DriveApiIssue.cancelled
          : DriveApiIssue.unavailable);
    } on FormatException {
      throw const DriveApiException(DriveApiIssue.invalidResponse);
    } on TypeError {
      throw const DriveApiException(DriveApiIssue.invalidResponse);
    }
  }
}
