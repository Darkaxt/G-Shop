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

String batchBody(List<int> order,
        {Map<int, int> statuses = const {},
        Map<int, String> ids = const {},
        String boundary = 'batch_response'}) =>
    '${order.map((index) => '--$boundary\r\n'
        'Content-Type: application/http\r\n'
        'Content-ID: <response-folder-$index>\r\n\r\n'
        'HTTP/1.1 ${statuses[index] ?? 200} Status\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '${jsonEncode(file(ids[index] ?? 'id-$index', mime: DriveFile.folderMime))}\r\n').join()}'
    '--$boundary--\r\n';

ResponseBody batchResponse(String body) =>
    ResponseBody.fromString(body, 200, headers: {
      'content-type': ['multipart/mixed; boundary="batch_response"']
    });

void main() {
  test(
      'folder batch is fixed-origin metadata-only and maps reordered responses',
      () async {
    final transport = _Transport((_) => batchResponse(batchBody([1, 0])));
    final api = DriveApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter: transport);
    addTearDown(api.close);
    final folders = await api.getFolderBatch(['id-0', 'id-1']);
    expect(folders.map((folder) => folder.id), ['id-0', 'id-1']);
    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.toString(), 'https://www.googleapis.com/batch/drive/v3');
    expect(request.followRedirects, isFalse);
    expect(request.headers['Authorization'], 'Bearer secret-0');
    final body = request.data as String;
    expect(body, contains('GET /drive/v3/files/id-0?'));
    expect(body, contains('Content-ID: <folder-1>'));
    // The MIME separator's CRLF is not the nested HTTP header terminator.
    expect(body, contains('HTTP/1.1\r\n\r\n\r\n--rshop_folder_metadata'));
    expect(body,
        contains('fields=id%2Cname%2CmimeType%2Cparents%2CdriveId%2Ctrashed'));
    expect(body, isNot(contains('secret')));
    expect(body, isNot(contains('alt=media')));
    expect(body, isNot(contains('https://')));
  });

  test('batch validates exact once-only response identity and framing',
      () async {
    for (final payload in [
      batchBody([0]),
      batchBody([0, 0]),
      batchBody([0, 1, 2]),
      batchBody([0, 1], ids: {1: 'wrong-id'}),
      batchBody([0, 1]).replaceAll('--batch_response--\r\n', ''),
      batchBody([0, 1]).replaceFirst('application/http', 'text/plain'),
      batchBody([0, 1]).replaceFirst('HTTP/1.1 200 Status', 'not HTTP'),
      batchBody([0, 1]).replaceFirst(
          'Content-Type: application/json; charset=UTF-8\r\n', ''),
      'x' * (DriveApi.maxMetadataBytes + 1),
    ]) {
      final api = DriveApi(
          authorization: DriveAuthorization(_Auth()),
          accountId: 'account',
          httpClientAdapter: _Transport((_) => batchResponse(payload)));
      await expectLater(
          api.getFolderBatch(['id-0', 'id-1']),
          throwsA(isA<DriveApiException>().having(
              (error) => error.issue, 'issue', DriveApiIssue.invalidResponse)));
      api.close();
    }
  });

  test('batch request bound and cancellation never issue HTTP requests',
      () async {
    final transport = _Transport((_) => batchResponse(batchBody([0])));
    final api = DriveApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter: transport);
    addTearDown(api.close);
    for (final ids in [
      <String>[],
      [''],
      ['same', 'same'],
      [for (var index = 0; index < 101; index++) 'id-$index'],
      ['x' * 8001],
    ]) {
      await expectLater(
          api.getFolderBatch(ids), throwsA(isA<DriveApiException>()));
    }
    final cancel = CancelToken()..cancel();
    await expectLater(
        api.getFolderBatch(['id-0'], cancelToken: cancel),
        throwsA(isA<DriveApiException>()
            .having((error) => error.issue, 'issue', DriveApiIssue.cancelled)));
    expect(transport.requests, isEmpty);
  });

  test('outer or inner rejected batch token renews only once', () async {
    for (final outer in [true, false]) {
      final auth = _Auth();
      final transport = _Transport((request) =>
          request.headers['Authorization'] == 'Bearer secret-0'
              ? (outer
                  ? ResponseBody.fromString('private', 401)
                  : batchResponse(batchBody([0], statuses: {0: 401})))
              : batchResponse(batchBody([0])));
      final api = DriveApi(
          authorization: DriveAuthorization(auth),
          accountId: 'account',
          httpClientAdapter: transport);
      expect((await api.getFolderBatch(['id-0'])).single.id, 'id-0');
      expect(auth.renewals, 1);
      expect(transport.requests.length, 2);
      api.close();
    }
    final auth = _Auth();
    final transport =
        _Transport((_) => batchResponse(batchBody([0], statuses: {0: 401})));
    final api = DriveApi(
        authorization: DriveAuthorization(auth),
        accountId: 'account',
        httpClientAdapter: transport);
    addTearDown(api.close);
    await expectLater(api.getFolderBatch(['id-0']),
        throwsA(isA<DriveAuthorizationException>()));
    expect(auth.renewals, 1);
    expect(transport.requests.length, 2);
  });

  test('batch inner and outer errors stop without retries or private payloads',
      () async {
    for (final outer in [true, false]) {
      for (final entry in {
        403: DriveApiIssue.accessDenied,
        404: DriveApiIssue.notFound,
        429: DriveApiIssue.quota,
        503: DriveApiIssue.unavailable
      }.entries) {
        final transport = _Transport((_) => outer
            ? ResponseBody.fromString('private secret', entry.key)
            : batchResponse(batchBody([0], statuses: {0: entry.key})));
        final api = DriveApi(
            authorization: DriveAuthorization(_Auth()),
            accountId: 'account',
            httpClientAdapter: transport);
        await expectLater(
            api.getFolderBatch(['id-0']),
            throwsA(isA<DriveApiException>()
                .having((error) => error.issue, 'issue', entry.value)
                .having((error) => error.toString(), 'redacted',
                    isNot(contains('secret')))));
        expect(transport.requests.length, 1);
        api.close();
      }
    }
  });

  test('cancellation while batch response streams prevents returning metadata',
      () async {
    final cancel = CancelToken();
    Stream<Uint8List> stream() async* {
      yield Uint8List.fromList(utf8.encode('--batch_response\r\n'));
      cancel.cancel();
      yield Uint8List.fromList(utf8.encode('private incomplete body'));
    }

    final transport = _Transport((_) => ResponseBody(stream(), 200, headers: {
          'content-type': ['multipart/mixed; boundary=batch_response']
        }));
    final api = DriveApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter: transport);
    addTearDown(api.close);
    await expectLater(
        api.getFolderBatch(['id-0'], cancelToken: cancel),
        throwsA(isA<DriveApiException>()
            .having((error) => error.issue, 'issue', DriveApiIssue.cancelled)));
    expect(transport.requests.length, 1);
  });

  test('mixed quota and rejected token does not retry the batch', () async {
    final auth = _Auth();
    final transport = _Transport(
        (_) => batchResponse(batchBody([0, 1], statuses: {0: 401, 1: 429})));
    final api = DriveApi(
        authorization: DriveAuthorization(auth),
        accountId: 'account',
        httpClientAdapter: transport);
    addTearDown(api.close);
    await expectLater(
        api.getFolderBatch(['id-0', 'id-1']),
        throwsA(isA<DriveApiException>()
            .having((error) => error.issue, 'issue', DriveApiIssue.quota)));
    expect(auth.renewals, 0);
    expect(transport.requests.length, 1);
  });

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
