import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../../models/save_backup_manifest.dart';
import '../drive/drive_authorization.dart';
import 'drive_save_backup_area.dart';

enum SaveBackupGenerationIssue {
  invalidBinding,
  changedCapture,
  invalidResponse,
  unownedObject,
  digestMismatch,
  cancelled,
  notFound,
  accessDenied,
  quota,
  unavailable,
}

class SaveBackupGenerationException implements Exception {
  final SaveBackupGenerationIssue issue;
  const SaveBackupGenerationException(this.issue);
  @override
  String toString() => 'Save backup generation: ${issue.name}';
}

/// Immutable save-only uploads. Reserved identities and captured private files
/// must be durably recorded by the job BEFORE calling publish. This boundary
/// never updates/deletes an existing object, shares it, or touches ROM sources.
/// A lost write response is resolved by verifying the same ID on explicit resume.
class DriveSaveBackupGenerationApi {
  static const _fields =
      'id,mimeType,parents,ownedByMe,isAppAuthorized,trashed,'
      'shared,driveId,appProperties,size,headRevisionId';
  final DriveAuthorization authorization;
  final String accountId;
  final HttpClientAdapter _transport;
  late final DriveSaveBackupAreaApi _areas = DriveSaveBackupAreaApi(
      authorization: authorization,
      accountId: accountId,
      transport: _transport);

  DriveSaveBackupGenerationApi(
      {required this.authorization,
      required this.accountId,
      HttpClientAdapter? transport})
      : _transport = transport ?? IOHttpClientAdapter();

  Future<SaveBackupManifest> loadGeneration(
          {required String areaId,
          required String generationId,
          required SaveBackupBinding target,
          CancelToken? cancellation}) =>
      _loadGeneration(
          areaId: areaId,
          generationId: generationId,
          target: target,
          cancellation: cancellation);

  /// Discover immutable publication objects, not payloads or a clock-selected
  /// "latest" pointer. Read every page and verify ownership and manifest bytes.
  /// Battery saves can originate on another device; compatibility decides scope.
  Future<List<SaveBackupManifest>> discoverGenerations(
      {required String areaId,
      required SaveBackupBinding target,
      CancelToken? cancellation}) async {
    if (target.accountId != accountId ||
        !RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(areaId)) {
      throw const SaveBackupGenerationException(
          SaveBackupGenerationIssue.invalidBinding);
    }
    await _areas.verifyArea(areaId, cancellation: cancellation);
    final result = <SaveBackupManifest>[];
    final ids = <String>{};
    final pages = <String>{};
    String? page;
    do {
      final response = await _send(
          Uri.https('www.googleapis.com', '/drive/v3/files', {
            'q': "'$areaId' in parents and trashed = false and "
                "appProperties has { key='rshopSaveBackup' and value='1' } and "
                "appProperties has { key='kind' and value='generation' }",
            'spaces': 'drive',
            'pageSize': '100',
            'fields': 'nextPageToken,incompleteSearch,files(id)',
            if (page != null) 'pageToken': page,
          }),
          'GET',
          cancellation: cancellation);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response!.stream) {
        _check(cancellation);
        if (bytes.length + chunk.length >
            DriveSaveBackupAreaApi.maxMetadataBytes) {
          throw const SaveBackupGenerationException(
              SaveBackupGenerationIssue.invalidResponse);
        }
        bytes.add(chunk);
      }
      final data = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (data is! Map<String, dynamic> ||
          data['incompleteSearch'] == true ||
          data['files'] is! List) {
        throw const SaveBackupGenerationException(
            SaveBackupGenerationIssue.invalidResponse);
      }
      for (final item in data['files'] as List) {
        if (item is! Map ||
            item['id'] is! String ||
            !ids.add(item['id'] as String)) {
          throw const SaveBackupGenerationException(
              SaveBackupGenerationIssue.invalidResponse);
        }
        final manifest = await _loadGeneration(
            areaId: areaId,
            generationId: item['id'] as String,
            cancellation: cancellation);
        if (manifest.binding.restoreIssue(target) == null) result.add(manifest);
      }
      final next = data['nextPageToken'];
      if (next != null &&
          (next is! String || next.isEmpty || !pages.add(next))) {
        throw const SaveBackupGenerationException(
            SaveBackupGenerationIssue.invalidResponse);
      }
      page = next as String?;
    } while (page != null);
    _check(cancellation);
    return List.unmodifiable(result);
  }

  Future<SaveBackupManifest> _loadGeneration(
      {required String areaId,
      required String generationId,
      SaveBackupBinding? target,
      CancelToken? cancellation}) async {
    try {
      if ((target != null && target.accountId != accountId) ||
          !RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(generationId)) {
        throw const SaveBackupGenerationException(
            SaveBackupGenerationIssue.invalidBinding);
      }
      await _areas.verifyArea(areaId, cancellation: cancellation);
      final data = await _metadata(generationId, cancellation);
      final size = int.tryParse('${data?['size']}');
      final properties = data?['appProperties'];
      if (size == null ||
          size <= 0 ||
          size > SaveBackupManifest.maxEncodedBytes ||
          properties is! Map ||
          properties['sha256'] is! String ||
          properties['binding'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(properties['sha256'] as String) ||
          !RegExp(r'^[a-f0-9]{64}$')
              .hasMatch(properties['binding'] as String)) {
        throw const SaveBackupGenerationException(
            SaveBackupGenerationIssue.invalidResponse);
      }
      final expected = {
        'rshopSaveBackup': '1',
        'kind': 'generation',
        'generationId': generationId,
        'sha256': properties['sha256'] as String,
        'binding': properties['binding'] as String
      };
      _requireObject(data, generationId, areaId, size, expected);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in _objectBytes(
          id: generationId,
          areaId: areaId,
          size: size,
          properties: expected,
          cancellation: cancellation)) {
        bytes.add(chunk);
      }
      final result = SaveBackupManifest.decode(bytes.takeBytes());
      if (result.generationId != generationId ||
          result.binding.accountId != accountId ||
          (target != null && result.binding.restoreIssue(target) != null) ||
          expected['binding'] !=
              sha256.convert(utf8.encode(result.binding.key)).toString()) {
        throw const SaveBackupGenerationException(
            SaveBackupGenerationIssue.invalidBinding);
      }
      return result;
    } on DriveAuthorizationException {
      rethrow;
    } on SaveBackupGenerationException {
      rethrow;
    } catch (_) {
      throw SaveBackupGenerationException(cancellation?.isCancelled == true
          ? SaveBackupGenerationIssue.cancelled
          : SaveBackupGenerationIssue.unavailable);
    }
  }

  /// Stream into a private restore stage only. Bytes are NOT trusted until normal
  /// EOF: digest, complete length and unchanged content revision are checked before
  /// the stream completes. Cancellation/early unsubscribe cannot authorize local
  /// publication. Destination grants/atomic group rollback belong to native restore.
  Stream<Uint8List> memberBytes(
      {required String areaId,
      required SaveBackupManifest generation,
      required String memberId,
      CancelToken? cancellation}) async* {
    try {
      final matches =
          generation.members.where((m) => m.cloudFileId == memberId);
      if (generation.binding.accountId != accountId || matches.length != 1) {
        throw const SaveBackupGenerationException(
            SaveBackupGenerationIssue.invalidBinding);
      }
      final member = matches.single;
      await _areas.verifyArea(areaId, cancellation: cancellation);
      yield* _objectBytes(
          id: memberId,
          areaId: areaId,
          size: member.sizeBytes,
          properties: _properties('payload', generation.generationId,
              member.sha256, generation.binding),
          cancellation: cancellation);
    } on DriveAuthorizationException {
      rethrow;
    } on SaveBackupGenerationException {
      rethrow;
    } catch (_) {
      throw SaveBackupGenerationException(cancellation?.isCancelled == true
          ? SaveBackupGenerationIssue.cancelled
          : SaveBackupGenerationIssue.unavailable);
    }
  }

  void _check(CancelToken? cancellation) {
    if (cancellation?.isCancelled == true) {
      throw const SaveBackupGenerationException(
          SaveBackupGenerationIssue.cancelled);
    }
  }

  Future<void> publish(
      {required String areaId,
      required SaveBackupManifest generation,
      required Map<String, File> captures,
      CancelToken? cancellation}) async {
    try {
      final ids = generation.members.map((m) => m.cloudFileId).toSet();
      if (generation.binding.accountId != accountId ||
          ids.contains(generation.generationId) ||
          ids.contains(areaId) ||
          areaId == generation.generationId ||
          captures.length != ids.length ||
          !captures.keys.every(ids.contains)) {
        throw const SaveBackupGenerationException(
            SaveBackupGenerationIssue.invalidBinding);
      }
      final manifestBytes = generation.encode();
      final capturedFiles = Map<String, File>.unmodifiable(captures);
      _check(cancellation);
      await _areas.verifyArea(areaId, cancellation: cancellation);
      // Validate the whole captured group before the first remote write. This is
      // not a quiescence claim about the emulator's source files: native capture
      // must establish that boundary before constructing these immutable stages.
      for (final member in generation.members) {
        final file = capturedFiles[member.cloudFileId]!;
        if (await FileSystemEntity.type(file.path, followLinks: false) !=
                FileSystemEntityType.file ||
            await file.length() != member.sizeBytes ||
            await _hash(file.openRead(), member.sizeBytes, cancellation) !=
                member.sha256) {
          throw const SaveBackupGenerationException(
              SaveBackupGenerationIssue.changedCapture);
        }
      }
      for (final member in generation.members) {
        await _publishObject(
            areaId: areaId,
            generationId: generation.generationId,
            id: member.cloudFileId,
            kind: 'payload',
            size: member.sizeBytes,
            digest: member.sha256,
            binding: generation.binding,
            open: () => _captureStream(
                capturedFiles[member.cloudFileId]!, member, cancellation),
            cancellation: cancellation);
      }
      // This is the commit point. Payloads alone are not discoverable backups.
      // No manifest is uploaded unless every remote member passed a full readback.
      await _publishObject(
          areaId: areaId,
          generationId: generation.generationId,
          id: generation.generationId,
          kind: 'generation',
          size: manifestBytes.length,
          digest: sha256.convert(manifestBytes).toString(),
          binding: generation.binding,
          open: () => _bytesStream(manifestBytes),
          cancellation: cancellation);
    } on DriveAuthorizationException {
      rethrow;
    } on SaveBackupGenerationException {
      rethrow;
    } on SaveBackupAreaException catch (error) {
      throw SaveBackupGenerationException(switch (error.issue) {
        SaveBackupAreaIssue.cancelled => SaveBackupGenerationIssue.cancelled,
        SaveBackupAreaIssue.accessDenied =>
          SaveBackupGenerationIssue.accessDenied,
        SaveBackupAreaIssue.quota => SaveBackupGenerationIssue.quota,
        _ => SaveBackupGenerationIssue.unownedObject,
      });
    } catch (_) {
      throw SaveBackupGenerationException(cancellation?.isCancelled == true
          ? SaveBackupGenerationIssue.cancelled
          : SaveBackupGenerationIssue.unavailable);
    }
  }

  Map<String, String> _properties(String kind, String generationId,
          String digest, SaveBackupBinding binding) =>
      {
        'rshopSaveBackup': '1',
        'kind': kind,
        'generationId': generationId,
        'sha256': digest,
        'binding': sha256.convert(utf8.encode(binding.key)).toString(),
      };

  Future<void> _publishObject(
      {required String areaId,
      required String generationId,
      required String id,
      required String kind,
      required int size,
      required String digest,
      required SaveBackupBinding binding,
      required Stream<Uint8List> Function() open,
      CancelToken? cancellation}) async {
    final properties = _properties(kind, generationId, digest, binding);
    final existing = await _metadata(id, cancellation);
    if (existing == null) {
      final body = Uint8List.fromList(utf8.encode(jsonEncode({
        'id': id,
        'name': '$kind-$id',
        'mimeType': 'application/octet-stream',
        'parents': [areaId],
        'appProperties': properties,
      })));
      final response = await _send(
          Uri.https('www.googleapis.com', '/upload/drive/v3/files',
              {'uploadType': 'resumable', 'fields': _fields}),
          'POST',
          open: () => Stream.value(body),
          length: body.length,
          headers: {
            'Content-Type': 'application/json; charset=UTF-8',
            'X-Upload-Content-Type': 'application/octet-stream',
            'X-Upload-Content-Length': '$size'
          },
          cancellation: cancellation);
      final locations = response!.headers['location'];
      await response.stream.listen((_) {}).cancel();
      if (locations == null || locations.length != 1) {
        throw const SaveBackupGenerationException(
            SaveBackupGenerationIssue.invalidResponse);
      }
      final session = Uri.tryParse(locations.single);
      if (session == null ||
          session.scheme != 'https' ||
          session.host != 'www.googleapis.com' ||
          session.port != 443 ||
          session.userInfo.isNotEmpty ||
          session.fragment.isNotEmpty ||
          session.path != '/upload/drive/v3/files' ||
          session.queryParameters['uploadType'] != 'resumable' ||
          session.queryParameters['upload_id']?.isNotEmpty != true) {
        throw const SaveBackupGenerationException(
            SaveBackupGenerationIssue.invalidResponse);
      }
      final uploaded = await _send(session, 'PUT',
          open: open,
          length: size,
          headers: {'Content-Type': 'application/octet-stream'},
          cancellation: cancellation);
      // The final media response isn't trusted as proof; independently GET both
      // exact metadata and bytes below. Release its stream even on cancellation.
      await uploaded!.stream.listen((_) {}).cancel();
    }
    await _objectBytes(
            id: id,
            areaId: areaId,
            size: size,
            properties: properties,
            cancellation: cancellation)
        .drain<void>();
  }

  Stream<Uint8List> _objectBytes(
      {required String id,
      required String areaId,
      required int size,
      required Map<String, String> properties,
      CancelToken? cancellation}) async* {
    final current = await _metadata(id, cancellation);
    _requireObject(current, id, areaId, size, properties);
    final media = await _send(
        Uri.https(
            'www.googleapis.com', '/drive/v3/files/$id', {'alt': 'media'}),
        'GET',
        cancellation: cancellation);
    final result = _SaveDigestSink();
    final sink = sha256.startChunkedConversion(result);
    var count = 0;
    try {
      await for (final chunk in media!.stream) {
        _check(cancellation);
        count += chunk.length;
        if (count > size) {
          if (kDebugMode) {
            debugPrint(
                'RShopSaveReadback: excess_length expected=$size observed=$count');
          }
          throw const SaveBackupGenerationException(
              SaveBackupGenerationIssue.digestMismatch);
        }
        sink.add(chunk);
        for (var offset = 0; offset < chunk.length; offset += 65536) {
          final end =
              offset + 65536 < chunk.length ? offset + 65536 : chunk.length;
          yield Uint8List.sublistView(chunk, offset, end);
        }
      }
    } finally {
      sink.close();
    }
    _check(cancellation);
    if (count != size || result.value.toString() != properties['sha256']) {
      if (kDebugMode) {
        debugPrint(
            'RShopSaveReadback: content_check expected=$size observed=$count '
            'digest_equal=${result.value.toString() == properties['sha256']}');
      }
      throw const SaveBackupGenerationException(
          SaveBackupGenerationIssue.digestMismatch);
    }
    final after = await _metadata(id, cancellation);
    _requireObject(after, id, areaId, size, properties);
    // Drive's general version includes invisible metadata changes. The binary
    // head revision identifies content, so metadata-only changes cannot make a
    // fully hashed read look corrupt. Ownership/binding are rechecked above.
    if (after!['headRevisionId'] != current!['headRevisionId']) {
      if (kDebugMode) debugPrint('RShopSaveReadback: content_revision_changed');
      throw const SaveBackupGenerationException(
          SaveBackupGenerationIssue.digestMismatch);
    }
  }

  void _requireObject(Map<String, dynamic>? data, String id, String areaId,
      int size, Map<String, String> properties) {
    final parents = data?['parents'];
    final markers = data?['appProperties'];
    final mime = data?['mimeType'];
    // Drive can classify opaque save bytes despite an octet-stream upload.
    // Its MIME label is not a content/ownership identity. Require a regular
    // byte-backed object, then verify its exact size, digest and head revision.
    // Google-native objects (including folders/shortcuts) are never save media.
    final binary = mime is String &&
        mime.isNotEmpty &&
        !mime.toLowerCase().startsWith('application/vnd.google-apps.');
    if (data == null ||
        data['id'] != id ||
        data['ownedByMe'] != true ||
        data['isAppAuthorized'] != true ||
        data['trashed'] != false ||
        data['shared'] != false ||
        data['driveId'] != null ||
        !binary ||
        parents is! List ||
        parents.length != 1 ||
        parents.single != areaId ||
        markers is! Map ||
        properties.entries.any((e) => markers[e.key] != e.value) ||
        data['size'] != '$size' ||
        data['headRevisionId'] is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,256}$')
            .hasMatch(data['headRevisionId'] as String)) {
      if (kDebugMode) {
        // Predicate results only: never log account/file IDs, tokens, paths,
        // app-property values or response bodies from the private backup area.
        final mimeLabel = mime is String &&
                RegExp(r'^[a-z][a-z0-9.+-]{0,63}/[a-z][a-z0-9.+-]{0,63}$')
                    .hasMatch(mime)
            ? mime
            : 'invalid';
        debugPrint('RShopSaveReadback: metadata_check '
            'present=${data != null} id_equal=${data?['id'] == id} '
            'owner=${data?['ownedByMe'] == true} '
            'authorized=${data?['isAppAuthorized'] == true} '
            'not_trashed=${data?['trashed'] == false} '
            'not_shared=${data?['shared'] == false} '
            'individual_drive=${data?['driveId'] == null} '
            'binary=$binary '
            'observed_mime=$mimeLabel '
            'manifest=${properties['kind'] == 'generation'} '
            'parent_equal=${parents is List && parents.length == 1 && parents.single == areaId} '
            'markers_equal=${markers is Map && properties.entries.every((e) => markers[e.key] == e.value)} '
            'size_equal=${data?['size'] == '$size'} '
            'revision_valid=${data?['headRevisionId'] is String && RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(data!['headRevisionId'] as String)}');
      }
      throw const SaveBackupGenerationException(
          SaveBackupGenerationIssue.unownedObject);
    }
  }

  Future<Map<String, dynamic>?> _metadata(
      String id, CancelToken? cancellation) async {
    final response = await _send(
        Uri.https(
            'www.googleapis.com', '/drive/v3/files/$id', {'fields': _fields}),
        'GET',
        allowMissing: true,
        cancellation: cancellation);
    if (response == null) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      _check(cancellation);
      if (bytes.length + chunk.length >
          DriveSaveBackupAreaApi.maxMetadataBytes) {
        throw const SaveBackupGenerationException(
            SaveBackupGenerationIssue.invalidResponse);
      }
      bytes.add(chunk);
    }
    _check(cancellation);
    final data = jsonDecode(utf8.decode(bytes.takeBytes()));
    if (data is! Map<String, dynamic>) {
      throw const SaveBackupGenerationException(
          SaveBackupGenerationIssue.invalidResponse);
    }
    return data;
  }

  Future<ResponseBody?> _send(Uri uri, String method,
      {Stream<Uint8List> Function()? open,
      int? length,
      Map<String, Object> headers = const {},
      bool allowMissing = false,
      CancelToken? cancellation}) async {
    String? rejected;
    for (var attempt = 0; attempt < 2; attempt++) {
      _check(cancellation);
      final grant = await authorization.acquireBackup(
          expectedAccountId: accountId, rejectedToken: rejected);
      _check(cancellation);
      final response = await _transport.fetch(
          RequestOptions(
              path: uri.toString(),
              method: method,
              followRedirects: false,
              responseType: ResponseType.stream,
              headers: {
                'Authorization': 'Bearer ${grant.accessToken}',
                'Accept-Encoding': 'identity',
                if (length != null) 'Content-Length': length,
                ...headers
              }),
          open?.call(),
          cancellation?.whenCancel);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return response;
      }
      await response.stream.listen((_) {}).cancel();
      _check(cancellation);
      if (response.statusCode == 401 && attempt == 0) {
        rejected = grant.accessToken;
        continue;
      }
      if (response.statusCode == 401) {
        throw const DriveAuthorizationException(
            DriveAuthorizationIssue.interactionRequired);
      }
      if (response.statusCode == 404 && allowMissing && method == 'GET') {
        return null;
      }
      throw SaveBackupGenerationException(switch (response.statusCode) {
        403 => SaveBackupGenerationIssue.accessDenied,
        404 => SaveBackupGenerationIssue.notFound,
        429 => SaveBackupGenerationIssue.quota,
        _ => SaveBackupGenerationIssue.unavailable,
      });
    }
    throw const SaveBackupGenerationException(
        SaveBackupGenerationIssue.unavailable);
  }

  Stream<Uint8List> _captureStream(
      File file, SaveBackupMember member, CancelToken? cancellation) async* {
    final result = _SaveDigestSink();
    final digest = sha256.startChunkedConversion(result);
    var count = 0;
    try {
      await for (final chunk in file.openRead()) {
        _check(cancellation);
        count += chunk.length;
        if (count > member.sizeBytes) {
          throw const SaveBackupGenerationException(
              SaveBackupGenerationIssue.changedCapture);
        }
        digest.add(chunk);
        // Do not depend on the platform File stream's chosen chunk size.
        for (var offset = 0; offset < chunk.length; offset += 65536) {
          final end =
              offset + 65536 < chunk.length ? offset + 65536 : chunk.length;
          yield Uint8List.fromList(chunk.sublist(offset, end));
        }
      }
    } finally {
      digest.close();
    }
    _check(cancellation);
    if (count != member.sizeBytes || result.value.toString() != member.sha256) {
      throw const SaveBackupGenerationException(
          SaveBackupGenerationIssue.changedCapture);
    }
  }

  Stream<Uint8List> _bytesStream(Uint8List bytes) async* {
    for (var offset = 0; offset < bytes.length; offset += 65536) {
      final end = offset + 65536 < bytes.length ? offset + 65536 : bytes.length;
      yield Uint8List.sublistView(bytes, offset, end);
    }
  }

  Future<String> _hash(
      Stream<List<int>> stream, int expected, CancelToken? cancellation) async {
    final result = _SaveDigestSink();
    final sink = sha256.startChunkedConversion(result);
    var count = 0;
    try {
      await for (final chunk in stream) {
        _check(cancellation);
        count += chunk.length;
        if (count > expected) {
          throw const SaveBackupGenerationException(
              SaveBackupGenerationIssue.digestMismatch);
        }
        sink.add(chunk);
      }
    } finally {
      sink.close();
    }
    _check(cancellation);
    if (count != expected) {
      throw const SaveBackupGenerationException(
          SaveBackupGenerationIssue.digestMismatch);
    }
    return result.value.toString();
  }

  void close() => _areas.close();
}

class _SaveDigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
