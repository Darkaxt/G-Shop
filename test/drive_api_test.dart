import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';

class _Auth implements DriveAuthorizationDriver {
  int renewals = 0;
  @override
  Future<String?> authenticate({required bool interactive}) async => 'account';
  @override
  Future<String?> authorize(String accountId, List<String> scopes,
          {required bool interactive}) async =>
      'secret-$renewals';
  @override
  Future<void> clearRejectedToken(String accountId, String token) async {
    renewals++;
  }

  @override
  Future<void> signOut({required bool revoke}) async {}
}

class _Transport implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  _Transport(this.respond);
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> file(String id,
        {String mime = 'application/octet-stream'}) =>
    {
      'id': id,
      'name': 'Same.chd',
      'mimeType': mime,
      'parents': ['folder'],
      'size': '42',
      'version': '9',
      'trashed': false,
      'md5Checksum': '0123456789abcdef0123456789abcdef',
      'capabilities': {'canDownload': true},
    };

void main() {
  test('metadata-only fixed-origin GET and explicit paginated parent query',
      () async {
    final transport = _Transport((_) => ResponseBody.fromString(
        jsonEncode({
          'files': [file('one')],
          'nextPageToken': 'next'
        }),
        200));
    final api = DriveApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter: transport);
    addTearDown(api.close);
    final page = await api.listChildren("fo'lder\\id", pageToken: 'opaque');
    expect(page.files.single.id, 'one');
    expect(page.nextPageToken, 'next');
    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.origin, 'https://www.googleapis.com');
    expect(request.uri.path, '/drive/v3/files');
    expect(request.queryParameters['q'],
        "'fo\\'lder\\\\id' in parents and trashed = false");
    expect(request.queryParameters['pageToken'], 'opaque');
    expect(request.queryParameters['pageSize'], 100);
    expect(request.queryParameters['alt'], isNull);
    expect(request.followRedirects, isFalse);
    expect(request.headers['Authorization'], 'Bearer secret-0');
  });

  test('one rejected-token renewal, never implicit interactive authorization',
      () async {
    final auth = _Auth();
    final transport = _Transport((request) =>
        request.headers['Authorization'] == 'Bearer secret-0'
            ? ResponseBody.fromString('private error', 401)
            : ResponseBody.fromString(jsonEncode(file('one')), 200));
    final api = DriveApi(
        authorization: DriveAuthorization(auth),
        accountId: 'account',
        httpClientAdapter: transport);
    addTearDown(api.close);
    expect((await api.getFile('one')).sizeBytes, 42);
    expect(auth.renewals, 1);
    expect(transport.requests.length, 2);
  });

  test('forbidden and redirected errors never expose response or credentials',
      () async {
    for (final code in [301, 403, 404, 429, 500]) {
      final transport =
          _Transport((_) => ResponseBody.fromString('private secret-0', code));
      final api = DriveApi(
          authorization: DriveAuthorization(_Auth()),
          accountId: 'account',
          httpClientAdapter: transport);
      await expectLater(
          api.getFile('one'),
          throwsA(isA<DriveApiException>().having(
              (e) => e.toString(), 'redaction', isNot(contains('secret')))));
      expect(transport.requests.length, 1);
      api.close();
    }
  });

  test('incomplete search, malformed page, and oversized metadata fail closed',
      () async {
    for (final payload in [
      jsonEncode({'files': [], 'incompleteSearch': true}),
      jsonEncode({
        'files': [file('one')..remove('id')]
      }),
      'x' * (DriveApi.maxMetadataBytes + 1),
    ]) {
      final api = DriveApi(
          authorization: DriveAuthorization(_Auth()),
          accountId: 'account',
          httpClientAdapter:
              _Transport((_) => ResponseBody.fromString(payload, 200)));
      await expectLater(
          api.listChildren('folder'), throwsA(isA<DriveApiException>()));
      api.close();
    }
  });

  test('shortcuts, workspace documents and Shared Drive entries are explicit',
      () {
    expect(DriveFile.fromJson(file('one')).isSupportedBinary, isTrue);
    for (final entry in [
      file('shortcut', mime: 'application/vnd.google-apps.shortcut'),
      file('doc', mime: 'application/vnd.google-apps.document'),
      file('shared')..['driveId'] = 'shared-drive',
    ]) {
      final parsed = DriveFile.fromJson(entry);
      expect(parsed.isSupportedBinary, isFalse);
      expect(parsed.unsupportedReason, isNotNull);
    }
  });
}
