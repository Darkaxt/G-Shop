import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/services/drive/drive_authorization.dart';
import 'package:g_shop/services/saves/drive_save_backup_area.dart';

class _Auth implements DriveAuthorizationDriver {
  final scopes = <List<String>>[];
  int rejected = 0;
  @override
  Future<String?> authenticate({required bool interactive}) async => 'account';
  @override
  Future<String?> authorize(String accountId, List<String> scopes,
      {required bool interactive}) async {
    this.scopes.add(scopes);
    return 'private-$rejected';
  }

  @override
  Future<void> clearRejectedToken(String accountId, String token) async {
    rejected++;
  }

  @override
  Future<void> signOut({required bool revoke}) async {}
}

class _Transport implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions, Stream<Uint8List>?)
      respond;
  final requests = <RequestOptions>[];
  _Transport(this.respond);
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return respond(options, requestStream);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _area(String id) => {
      'id': id,
      'name': 'G-Shop Save Backups',
      'mimeType': 'application/vnd.google-apps.folder',
      'ownedByMe': true,
      'isAppAuthorized': true,
      'trashed': false,
      'shared': false,
      'appProperties': {'rshopSaveBackup': '1', 'kind': 'area'},
    };

ResponseBody _json(Object data, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(data), status);

void main() {
  test('private app-created area is discovered without matching folder names',
      () async {
    final driver = _Auth();
    final transport = _Transport((request, _) async {
      expect(request.method, 'GET');
      expect(request.uri.origin, 'https://www.googleapis.com');
      expect(request.followRedirects, isFalse);
      expect(request.queryParameters['q'], contains('appProperties'));
      expect(request.queryParameters['q'], isNot(contains('name =')));
      return _json({
        'files': [_area('backup-id')],
        'incompleteSearch': false
      });
    });
    final api = DriveSaveBackupAreaApi(
        authorization: DriveAuthorization(driver),
        accountId: 'account',
        transport: transport);
    addTearDown(api.close);
    expect((await api.discover()).single.id, 'backup-id');
    expect(driver.scopes.single, [DriveAuthorization.backupFileScope]);
  });

  test('reserved area creation reuses exact ID and never updates a collision',
      () async {
    final transport = _Transport((request, stream) async {
      if (request.method == 'GET') return _json({}, 404);
      expect(request.method, 'POST');
      expect(request.uri.path, '/drive/v3/files');
      final bytes = await stream!.fold<List<int>>([], (a, b) => a..addAll(b));
      final body = jsonDecode(utf8.decode(bytes)) as Map;
      expect(body['id'], 'reserved-id');
      expect(body['parents'], ['root']);
      expect(body['appProperties'], {'rshopSaveBackup': '1', 'kind': 'area'});
      return _json(_area('reserved-id'));
    });
    final api = DriveSaveBackupAreaApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        transport: transport);
    addTearDown(api.close);
    expect((await api.createReservedArea('reserved-id')).id, 'reserved-id');
    expect(transport.requests.map((r) => r.method), ['GET', 'POST']);
  });

  test('ambiguous creation is recoverable by the same reserved identity',
      () async {
    var created = false;
    final transport = _Transport((request, _) async {
      if (request.method == 'GET') {
        return created ? _json(_area('reserved-id')) : _json({}, 404);
      }
      created = true;
      throw StateError('simulated disconnect after server commit');
    });
    final api = DriveSaveBackupAreaApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        transport: transport);
    addTearDown(api.close);
    await expectLater(api.createReservedArea('reserved-id'),
        throwsA(isA<SaveBackupAreaException>()));
    expect((await api.createReservedArea('reserved-id')).id, 'reserved-id');
    expect(transport.requests.where((r) => r.method == 'POST'), hasLength(1));
  });

  test(
      'folder grant/name cannot authorize old, foreign, shared or wrong objects',
      () async {
    for (final change in [
      {'ownedByMe': false},
      {'isAppAuthorized': false},
      {'shared': true},
      {'trashed': true},
      {'appProperties': <String, String>{}},
      {'mimeType': 'application/octet-stream'},
      {'driveId': 'shared-drive'},
      {'id': 'different-id'},
    ]) {
      final transport = _Transport(
          (_, __) async => _json({..._area('reserved-id'), ...change}));
      final api = DriveSaveBackupAreaApi(
          authorization: DriveAuthorization(_Auth()),
          accountId: 'account',
          transport: transport);
      await expectLater(api.createReservedArea('reserved-id'),
          throwsA(isA<SaveBackupAreaException>()));
      expect(transport.requests.every((r) => r.method == 'GET'), isTrue);
      api.close();
    }
  });

  test('reauthorization is silent, bounded and never retries a non-auth write',
      () async {
    final driver = _Auth();
    final transport = _Transport((request, _) async =>
        request.headers['Authorization'] == 'Bearer private-0'
            ? _json({}, 401)
            : _json({'files': [], 'incompleteSearch': false}));
    final api = DriveSaveBackupAreaApi(
        authorization: DriveAuthorization(driver),
        accountId: 'account',
        transport: transport);
    addTearDown(api.close);
    expect(await api.discover(), isEmpty);
    expect(driver.rejected, 1);
    expect(transport.requests, hasLength(2));
  });

  test('cancelled and malformed responses cannot establish a backup area',
      () async {
    for (final data in [
      {
        'files': [_area('x')],
        'incompleteSearch': true
      },
      {
        'files': [_area('x')],
        'nextPageToken': 'cycle'
      },
      {'files': List.generate(101, (i) => _area('id-$i'))},
    ]) {
      final transport = _Transport((_, __) async => _json(data));
      final api = DriveSaveBackupAreaApi(
          authorization: DriveAuthorization(_Auth()),
          accountId: 'account',
          transport: transport);
      await expectLater(
          api.discover(), throwsA(isA<SaveBackupAreaException>()));
      api.close();
    }
    final transport = _Transport((_, __) async => _json(_area('x')));
    final api = DriveSaveBackupAreaApi(
        authorization: DriveAuthorization(_Auth()),
        accountId: 'account',
        transport: transport);
    final cancellation = CancelToken()..cancel();
    await expectLater(api.createReservedArea('x', cancellation: cancellation),
        throwsA(isA<SaveBackupAreaException>()));
    expect(transport.requests, isEmpty);
    api.close();
  });
}
