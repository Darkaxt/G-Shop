import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';

class BundleFixtureAccount implements DriveAuthorizationDriver {
  @override
  Future<String?> authenticate({required bool interactive}) async => 'account';
  @override
  Future<String?> authorize(String accountId, List<String> scopes,
          {required bool interactive}) async =>
      'fixture';
  @override
  Future<void> clearRejectedToken(String accountId, String token) async {}
  @override
  Future<void> signOut({required bool revoke}) async {}
}

class BundleFixtureTransport implements HttpClientAdapter {
  final payloads = <String, Uint8List>{
    'playlist':
        Uint8List.fromList(utf8.encode('Disc 1.chd\nDisc 2/disc.cue\n')),
    'disc1': Uint8List.fromList([1, 2, 3]),
    'cue': Uint8List.fromList(utf8.encode(
        'FILE "track.bin" BINARY\n TRACK 01 MODE2/2352\n INDEX 01 00:00:00\n')),
    'track': Uint8List.fromList([4, 5, 6]),
  };
  late final nodes = <String, DriveFile>{
    'root-id': DriveFile(
        id: 'root-id',
        name: 'root',
        mimeType: DriveFile.folderMime,
        parents: const []),
    'disc-folder': DriveFile(
        id: 'disc-folder',
        name: 'Disc 2',
        mimeType: DriveFile.folderMime,
        parents: const ['root-id']),
    for (final item in [
      ('playlist', 'game.m3u', 'root-id'),
      ('disc1', 'Disc 1.chd', 'root-id'),
      ('cue', 'disc.cue', 'disc-folder'),
      ('track', 'track.bin', 'disc-folder')
    ])
      item.$1: DriveFile(
          id: item.$1,
          name: item.$2,
          parents: [item.$3],
          mimeType: 'application/octet-stream',
          version: '1',
          canDownload: true,
          sizeBytes: payloads[item.$1]!.length,
          checksums: {'md5': md5.convert(payloads[item.$1]!).toString()}),
  };
  final media = <String>[];
  Completer<void>? mediaEntered;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.uri.path == '/batch/drive/v3') {
      final requests = RegExp(r'GET (/drive/v3/files/[^ ]+) HTTP/1.1')
          .allMatches(options.data as String).toList();
      final response = StringBuffer();
      for (var index = 0; index < requests.length; index++) {
        final id = Uri.parse(requests[index][1]!).pathSegments.last;
        final node = nodes[id];
        response.write('--bundle_batch\r\nContent-Type: application/http\r\n'
            'Content-ID: <response-folder-$index>\r\n\r\n'
            'HTTP/1.1 ${node == null ? 404 : 200} Status\r\n'
            'Content-Type: application/json\r\n\r\n'
            '${jsonEncode(node?.toJson() ?? {})}\r\n');
      }
      response.write('--bundle_batch--\r\n');
      return ResponseBody.fromString(response.toString(), 200, headers: {
        'content-type': ['multipart/mixed; boundary=bundle_batch']
      });
    }
    final id = options.path.split('/').last;
    if (options.queryParameters['alt'] == 'media') {
      media.add(id);
      if (mediaEntered != null) {
        mediaEntered!.complete();
        await cancelFuture;
        throw DioException(
            requestOptions: options, type: DioExceptionType.cancel);
      }
      final bytes = payloads[id]!;
      return ResponseBody(Stream.value(bytes), 200, headers: {
        'content-length': ['${bytes.length}']
      });
    }
    if (options.path == 'files') {
      final parent = RegExp("'([^']+)' in parents")
          .firstMatch(options.queryParameters['q'] as String)![1];
      return ResponseBody.fromString(
          jsonEncode({
            'files': [
              for (final file in nodes.values)
                if (file.parents.contains(parent)) file.toJson()
            ]
          }),
          200);
    }
    return ResponseBody.fromString(jsonEncode(nodes[id]!.toJson()), 200);
  }

  @override
  void close({bool force = false}) {}
}
