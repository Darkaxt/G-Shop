import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/services/drive/drive_authorization.dart';
import 'package:g_shop/services/drive/drive_media.dart';

class _Auth implements DriveAuthorizationDriver {
  int renewals = 0;
  bool interactiveUsed = false;
  String account = 'account';
  @override
  Future<String?> authenticate({required bool interactive}) async {
    interactiveUsed |= interactive;
    return account;
  }

  @override
  Future<String?> authorize(String accountId, List<String> scopes,
      {required bool interactive}) async {
    interactiveUsed |= interactive;
    expect(scopes, [DriveAuthorization.readOnlyScope]);
    return 'fixture-token-$renewals';
  }

  @override
  Future<void> clearRejectedToken(String accountId, String token) async {
    renewals++;
  }

  @override
  Future<void> signOut({required bool revoke}) async {}
}

class _Transport implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  _Transport(this.respond);
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return await respond(options);
  }

  @override
  void close({bool force = false}) {}
}

RemoteArtifact artifact({int size = 5, String account = 'account'}) =>
    RemoteArtifact(
      id: RemoteArtifactId(
          providerId: 'drive',
          sourceId: 'source',
          accountId: account,
          providerFileId: 'opaque/id'),
      parentId: 'folder',
      displayName: 'fixture.chd',
      displayPath: 'psx/fixture.chd',
      sizeBytes: size,
      version: '1',
      canDownload: true,
      providerChecksums: {'md5': '0123456789abcdef0123456789abcdef'},
    );

Matcher issue(DriveTransferIssue value) =>
    isA<DriveTransferException>().having((e) => e.issue, 'issue', value);

void main() {
  test('explicit finite range reads only the requested prefix', () async {
    final transport = _Transport((_) => ResponseBody.fromBytes([1, 2], 206,
        headers: {
          'content-range': ['bytes 0-1/5'],
          'content-length': ['2']
        }));
    final api = DriveMediaApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter: transport);
    addTearDown(api.close);
    final response = await api.open(artifact(),
        offset: 0, endInclusive: 1, cancelToken: CancelToken());
    expect(await response.bytes.expand((c) => c).toList(), [1, 2]);
    expect(response.total, 5);
    expect(response.length, 2);
    expect(transport.requests.single.headers['Range'], 'bytes=0-1');
  });

  test('ignored finite range is cancelled before buffering a whole ROM',
      () async {
    var received = false;
    var discarded = false;
    final stream = StreamController<Uint8List>(onListen: () {
      received = true;
    }, onCancel: () {
      discarded = true;
    });
    final api = DriveMediaApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter:
            _Transport((_) => ResponseBody(stream.stream, 200, headers: {
                  'content-length': ['5']
                })));
    addTearDown(() async {
      api.close();
      await stream.close();
    });
    await expectLater(
        api.open(artifact(),
            offset: 0, endInclusive: 1, cancelToken: CancelToken()),
        throwsA(issue(DriveTransferIssue.invalidRange)));
    expect(received, true,
        reason: 'subscription exists only to cancel the response');
    expect(discarded, true);
  });
  for (final range in ['bytes 0-4/5', 'bytes 1-2/5', 'bytes 0-1/6']) {
    test('finite prefix rejects mismatched range $range', () async {
      final api = DriveMediaApi(
          authorization: DriveAuthorization(_Auth()),
          accountId: 'account',
          httpClientAdapter:
              _Transport((_) => ResponseBody.fromBytes([1, 2], 206,
                  headers: {
                    'content-range': [range]
                  })));
      addTearDown(api.close);
      await expectLater(
          api.open(artifact(),
              offset: 0, endInclusive: 1, cancelToken: CancelToken()),
          throwsA(issue(DriveTransferIssue.invalidRange)));
    });
  }
  test('finite prefix rejects a truncated body without content length',
      () async {
    final api = DriveMediaApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter: _Transport((_) => ResponseBody.fromBytes([1], 206,
            headers: {
              'content-range': ['bytes 0-1/5']
            })));
    addTearDown(api.close);
    final response = await api.open(artifact(),
        offset: 0, endInclusive: 1, cancelToken: CancelToken());
    await expectLater(
        response.bytes.toList(), throwsA(issue(DriveTransferIssue.truncated)));
  });

  test('payload stays lazy and consumer cancellation reaches the source stream',
      () async {
    var listened = false;
    final cancelled = Completer<void>();
    final input = StreamController<Uint8List>(onListen: () {
      listened = true;
    }, onCancel: () {
      cancelled.complete();
    });
    final token = CancelToken();
    final api = DriveMediaApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter: _Transport((_) => ResponseBody(input.stream, 200)));
    addTearDown(() {
      token.cancel();
      api.close();
      input.close();
    });
    final response = await api.open(artifact(), offset: 0, cancelToken: token);
    expect(listened, isFalse,
        reason: 'Headers must not start buffering ROM data');
    final first = response.bytes.first;
    input.add(Uint8List.fromList([1, 2]));
    expect(await first, [1, 2]);
    await cancelled.future;
    expect(cancelled.isCompleted, true);
  });
  test('slow consumer pauses the original response stream', () async {
    final received = Completer<void>();
    final input = StreamController<Uint8List>();
    final token = CancelToken();
    final api = DriveMediaApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter: _Transport((_) => ResponseBody(input.stream, 200)));
    addTearDown(() {
      token.cancel();
      api.close();
      input.close();
    });
    final response = await api.open(artifact(), offset: 0, cancelToken: token);
    late StreamSubscription<Uint8List> subscription;
    subscription = response.bytes.listen((_) {
      subscription.pause();
      received.complete();
    });
    input.add(Uint8List.fromList([1, 2]));
    await received.future;
    expect(input.isPaused, true,
        reason: 'Writer backpressure must reach native input');
    await subscription.cancel();
  });
  test('fresh binary is a fixed-origin authorized GET, not an export or URL',
      () async {
    final transport =
        _Transport((_) => ResponseBody.fromBytes([1, 2, 3, 4, 5], 200,
            headers: {
              'content-length': ['5']
            }));
    final api = DriveMediaApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter: transport);
    addTearDown(api.close);
    final response =
        await api.open(artifact(), offset: 0, cancelToken: CancelToken());
    expect(await response.bytes.expand((chunk) => chunk).toList(),
        [1, 2, 3, 4, 5]);
    expect(response.offset, 0);
    expect(response.total, 5);
    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.origin, 'https://www.googleapis.com');
    expect(request.uri.path, '/drive/v3/files/opaque%2Fid');
    expect(request.queryParameters, {'alt': 'media'});
    expect(request.followRedirects, false);
    expect(request.headers['Authorization'], 'Bearer fixture-token-0');
    expect(request.headers['Accept-Encoding'], 'identity');
  });

  test('resume appends only an exact remaining 206 range', () async {
    final transport = _Transport((_) => ResponseBody.fromBytes([4, 5], 206,
        headers: {
          'content-range': ['bytes 3-4/5'],
          'content-length': ['2']
        }));
    final api = DriveMediaApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter: transport);
    addTearDown(api.close);
    final response =
        await api.open(artifact(), offset: 3, cancelToken: CancelToken());
    expect(await response.bytes.expand((chunk) => chunk).toList(), [4, 5]);
    expect(response.offset, 3);
    expect(response.length, 2);
    expect(transport.requests.single.headers['Range'], 'bytes=3-');
  });

  for (final range in [
    'bytes 2-4/5',
    'bytes 3-4/6',
    'bytes 3-8/5',
    'bytes 3-3/5',
    'bytes 3-4/*',
    'private invalid range'
  ]) {
    test('rejects inconsistent resumed range: $range', () async {
      final api = DriveMediaApi(
          authorization: DriveAuthorization(_Auth()),
          accountId: 'account',
          httpClientAdapter:
              _Transport((_) => ResponseBody.fromBytes([4, 5], 206,
                  headers: {
                    'content-range': [range]
                  })));
      addTearDown(api.close);
      await expectLater(
          api.open(artifact(), offset: 3, cancelToken: CancelToken()),
          throwsA(issue(DriveTransferIssue.invalidRange)));
    });
  }

  test(
      'ignored range requires an explicit restart, never yields old plus new bytes',
      () async {
    final api = DriveMediaApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter:
            _Transport((_) => ResponseBody.fromBytes([1, 2, 3, 4, 5], 200)));
    addTearDown(api.close);
    await expectLater(
        api.open(artifact(), offset: 3, cancelToken: CancelToken()),
        throwsA(issue(DriveTransferIssue.restartRequired)));
  });

  test('416 at exact local length only permits later local verification',
      () async {
    final api = DriveMediaApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter: _Transport(
            (_) => ResponseBody.fromString('private error body', 416, headers: {
                  'content-range': ['bytes */5']
                })));
    addTearDown(api.close);
    final response =
        await api.open(artifact(), offset: 5, cancelToken: CancelToken());
    expect(await response.bytes.toList(), isEmpty);
    await expectLater(
        api.open(artifact(), offset: 3, cancelToken: CancelToken()),
        throwsA(issue(DriveTransferIssue.invalidRange)));
  });

  test('premature EOF and excess bytes never look like a successful stream',
      () async {
    for (final size in [4, 6]) {
      final api = DriveMediaApi(
          authorization: DriveAuthorization(_Auth()),
          accountId: 'account',
          httpClientAdapter: _Transport(
              (_) => ResponseBody.fromBytes(List.filled(size, 1), 200)));
      final response =
          await api.open(artifact(), offset: 0, cancelToken: CancelToken());
      await expectLater(
          response.bytes.drain<void>(),
          throwsA(issue(size == 4
              ? DriveTransferIssue.truncated
              : DriveTransferIssue.invalidResponse)));
      api.close();
    }
  });

  test('encoding and contradictory declared lengths are rejected before bytes',
      () async {
    for (final headers in [
      {
        'content-encoding': ['gzip']
      },
      {
        'content-length': ['4']
      },
      {
        'content-length': ['-1']
      },
      {
        'content-range': ['bytes 0-4/5']
      },
      {
        'content-length': ['5', 'private conflicting value']
      },
    ]) {
      final api = DriveMediaApi(
          authorization: DriveAuthorization(_Auth()),
          accountId: 'account',
          httpClientAdapter: _Transport((_) =>
              ResponseBody.fromBytes([1, 2, 3, 4, 5], 200, headers: headers)));
      await expectLater(
          api.open(artifact(), offset: 0, cancelToken: CancelToken()),
          throwsA(isA<DriveTransferException>().having(
              (e) => e.toString(), 'redacted', isNot(contains('private')))));
      api.close();
    }
  });

  test('401 renews only once and never requests interactive authorization',
      () async {
    final auth = _Auth();
    final transport =
        _Transport((_) => ResponseBody.fromString('private', 401));
    final api = DriveMediaApi(
        authorization: DriveAuthorization(auth),
        accountId: 'account',
        httpClientAdapter: transport);
    addTearDown(api.close);
    await expectLater(
        api.open(artifact(), offset: 0, cancelToken: CancelToken()),
        throwsA(isA<DriveAuthorizationException>()));
    expect(transport.requests.length, 2);
    expect(auth.renewals, 1);
    expect(auth.interactiveUsed, false);
  });

  test('wrong account and cancellation prevent any request', () async {
    final transport =
        _Transport((_) => throw StateError('must not be reached'));
    final auth = _Auth()..account = 'other-account';
    final api = DriveMediaApi(
        authorization: DriveAuthorization(auth),
        accountId: 'account',
        httpClientAdapter: transport);
    addTearDown(api.close);
    await expectLater(
        api.open(artifact(account: 'wrong'),
            offset: 0, cancelToken: CancelToken()),
        throwsA(issue(DriveTransferIssue.invalidSource)));
    await expectLater(
        api.open(artifact(), offset: 0, cancelToken: CancelToken()),
        throwsA(isA<DriveAuthorizationException>()));
    await expectLater(
        api.open(artifact(), offset: 0, cancelToken: CancelToken()..cancel()),
        throwsA(issue(DriveTransferIssue.cancelled)));
    expect(transport.requests, isEmpty);
  });

  test('native request abort is cancellation even before response headers',
      () async {
    final fetching = Completer<void>();
    final token = CancelToken();
    final api = DriveMediaApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter: _Transport((_) async {
          fetching.complete();
          await token.whenCancel;
          throw const HttpException('private request aborted');
        }));
    addTearDown(api.close);
    final result = expectLater(
        api.open(artifact(), offset: 0, cancelToken: token),
        throwsA(issue(DriveTransferIssue.cancelled)));
    await fetching.future;
    token.cancel();
    await result;
  });

  test('native IO failures are unavailable without exposing exception text',
      () async {
    final api = DriveMediaApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter: _Transport((_) {
          throw const HttpException('private request failed');
        }));
    addTearDown(api.close);
    await expectLater(
        api.open(artifact(), offset: 0, cancelToken: CancelToken()),
        throwsA(issue(DriveTransferIssue.unavailable)));
  });

  test('transport and stream exceptions never leak private request information',
      () async {
    for (final status in [302, 403, 404, 429, 500]) {
      final api = DriveMediaApi(
          authorization: DriveAuthorization(_Auth()),
          accountId: 'account',
          httpClientAdapter: _Transport((_) =>
              ResponseBody.fromString('fixture-token-0 private', status)));
      await expectLater(
          api.open(artifact(), offset: 0, cancelToken: CancelToken()),
          throwsA(isA<DriveTransferException>().having(
              (e) => e.toString(), 'redacted', isNot(contains('private')))));
      api.close();
    }
    final api = DriveMediaApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter: _Transport((_) => ResponseBody(
            Stream.error(StateError('private fixture-token-0')), 200)));
    addTearDown(api.close);
    final response =
        await api.open(artifact(), offset: 0, cancelToken: CancelToken());
    await expectLater(response.bytes.drain<void>(),
        throwsA(issue(DriveTransferIssue.unavailable)));
  });

  test('oversized transport chunks fail closed without building a whole file',
      () async {
    final size = DriveMediaApi.maxChunkBytes + 1;
    final api = DriveMediaApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        httpClientAdapter:
            _Transport((_) => ResponseBody.fromBytes(Uint8List(size), 200)));
    addTearDown(api.close);
    final response = await api.open(artifact(size: size),
        offset: 0, cancelToken: CancelToken());
    await expectLater(response.bytes.drain<void>(),
        throwsA(issue(DriveTransferIssue.invalidResponse)));
  });
}
