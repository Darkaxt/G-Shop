import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';
import 'package:retro_eshop/services/saves/drive_save_backup_area.dart';
import 'package:retro_eshop/services/saves/save_backup_setup.dart';

class _Driver implements DriveAuthorizationDriver {
  int consents = 0;
  Completer<String?>? consent;
  final started = Completer<void>();
  @override
  Future<String?> authenticate({required bool interactive}) async => 'account';
  @override
  Future<String?> authorize(String accountId, List<String> scopes,
      {required bool interactive}) async {
    if (interactive) {
      consents++;
      if (!started.isCompleted) started.complete();
      if (consent != null) return consent!.future;
    }
    return 'private-token';
  }

  @override
  Future<void> clearRejectedToken(String accountId, String token) async {}
  @override
  Future<void> signOut({required bool revoke}) async {}
}

class _FailingPreferences extends InMemorySharedPreferencesStore {
  _FailingPreferences() : super.empty();
  bool reject = true;
  @override
  Future<bool> setValue(String type, String key, Object value) async =>
      reject ? false : await super.setValue(type, key, value);
}

class _Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool exists = false, failCreateResponse = false;
  String? reserved;
  final SharedPreferences prefs;
  _Transport(this.prefs);
  Map<String, Object> get area => {
        'id': 'reserved-id',
        'mimeType': 'application/vnd.google-apps.folder',
        'ownedByMe': true,
        'isAppAuthorized': true,
        'trashed': false,
        'shared': false,
        'appProperties': {'rshopSaveBackup': '1', 'kind': 'area'},
      };
  @override
  Future<ResponseBody> fetch(RequestOptions request, Stream<Uint8List>? data,
      Future<void>? cancelFuture) async {
    requests.add(request);
    if (request.uri.path.endsWith('/generateIds')) {
      reserved = 'reserved-id';
      return ResponseBody.fromString('{"ids":["reserved-id"]}', 200);
    }
    if (request.method == 'POST') {
      // The app must acknowledge its durable intent before any remote mutation.
      expect(prefs.getString(SaveBackupSetup.storageKey('client', 'account')),
          contains('reserved-id'));
      exists = true;
      if (failCreateResponse) throw StateError('commit response lost');
    }
    if (request.uri.path.endsWith('/reserved-id') || request.method == 'POST') {
      return ResponseBody.fromString(
          jsonEncode(exists ? area : {}), exists ? 200 : 404);
    }
    return ResponseBody.fromString(
        jsonEncode({
          'files': exists ? [area] : [],
          'incompleteSearch': false
        }),
        200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('explicit setup persists pending identity then verified readiness',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final driver = _Driver();
    final auth = DriveAuthorization(driver);
    final transport = _Transport(prefs);
    final setup = SaveBackupSetup(
        accountId: 'account',
        clientId: 'client',
        preferences: prefs,
        authorization: auth,
        api: DriveSaveBackupAreaApi(
            authorization: auth, accountId: 'account', transport: transport));
    addTearDown(setup.dispose);
    await setup.load();
    expect(setup.ready, isFalse);
    expect(transport.requests, isEmpty);
    await setup.prepare();
    expect(setup.ready, isTrue);
    expect(setup.areaId, 'reserved-id');
    expect(setup.issue, isNull);
    expect(driver.consents, 1);
    expect(prefs.getString(SaveBackupSetup.storageKey('client', 'account')),
        contains('"ready":true'));
  });

  test(
      'every explicit retry acknowledges durable intent before remote creation',
      () async {
    final original = SharedPreferencesStorePlatform.instance;
    addTearDown(() => SharedPreferencesStorePlatform.instance = original);
    final store = _FailingPreferences();
    SharedPreferencesStorePlatform.instance = store;
    final prefs = await SharedPreferences.getInstance();
    final auth = DriveAuthorization(_Driver());
    final transport = _Transport(prefs);
    SaveBackupSetup createSetup() => SaveBackupSetup(
        accountId: 'account',
        clientId: 'client',
        preferences: prefs,
        authorization: auth,
        api: DriveSaveBackupAreaApi(
            authorization: auth, accountId: 'account', transport: transport));
    final first = createSetup();
    await first.prepare();
    expect(first.issue, 'setupUnavailable');
    expect(await store.getAll(), isEmpty);
    expect(transport.requests.where((r) => r.method == 'POST'), isEmpty);
    await first.prepare();
    expect(first.ready, isFalse);
    expect(await store.getAll(), isEmpty);
    expect(transport.requests.where((r) => r.method == 'POST'), isEmpty);
    first.dispose();

    // SharedPreferences optimistically caches even a rejected write. A new
    // controller must not mistake that cached ID for acknowledged persistence.
    final recreated = createSetup();
    addTearDown(recreated.dispose);
    await recreated.prepare();
    expect(recreated.ready, isFalse);
    expect(await store.getAll(), isEmpty);
    expect(transport.requests.where((r) => r.method == 'POST'), isEmpty);

    store.reject = false;
    await recreated.prepare();
    expect(recreated.ready, isTrue);
    expect(recreated.issue, isNull);
    expect(transport.requests.where((r) => r.method == 'POST'), hasLength(1));
    expect((await store.getAll()).values.single, contains('"ready":true'));
    expect(transport.requests.where((r) => r.uri.path.endsWith('/generateIds')),
        hasLength(1));
  });

  test(
      'interrupted area response replays saved identity after process recreation',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final auth = DriveAuthorization(_Driver());
    final transport = _Transport(prefs)..failCreateResponse = true;
    final first = SaveBackupSetup(
        accountId: 'account',
        clientId: 'client',
        preferences: prefs,
        authorization: auth,
        api: DriveSaveBackupAreaApi(
            authorization: auth, accountId: 'account', transport: transport));
    await first.load();
    await first.prepare();
    expect(first.ready, isFalse);
    expect(first.areaId, 'reserved-id');
    expect(first.issue, isNotNull);
    first.dispose();
    final secondTransport = _Transport(prefs)..exists = true;
    final second = SaveBackupSetup(
        accountId: 'account',
        clientId: 'client',
        preferences: prefs,
        authorization: auth,
        api: DriveSaveBackupAreaApi(
            authorization: auth,
            accountId: 'account',
            transport: secondTransport));
    addTearDown(second.dispose);
    await second.load();
    expect(second.areaId, 'reserved-id');
    await second.prepare();
    expect(second.ready, isTrue);
    expect(secondTransport.requests.every((r) => r.method == 'GET'), isTrue);
  });

  test('double activation joins one setup operation', () async {
    final prefs = await SharedPreferences.getInstance();
    final driver = _Driver()..consent = Completer<String?>();
    final auth = DriveAuthorization(driver);
    final transport = _Transport(prefs);
    final setup = SaveBackupSetup(
        accountId: 'account',
        clientId: 'client',
        preferences: prefs,
        authorization: auth,
        api: DriveSaveBackupAreaApi(
            authorization: auth, accountId: 'account', transport: transport));
    addTearDown(setup.dispose);
    await setup.load();
    final one = setup.prepare();
    await driver.started.future;
    final two = setup.prepare();
    expect(setup.busy, isTrue);
    driver.consent!.complete('token');
    await Future.wait([one, two]);
    expect(driver.consents, 1);
    expect(transport.requests.where((r) => r.method == 'POST'), hasLength(1));
  });

  test('cancelled setup never creates an area after consent resolves',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final driver = _Driver()..consent = Completer<String?>();
    final auth = DriveAuthorization(driver);
    final transport = _Transport(prefs);
    final setup = SaveBackupSetup(
        accountId: 'account',
        clientId: 'client',
        preferences: prefs,
        authorization: auth,
        api: DriveSaveBackupAreaApi(
            authorization: auth, accountId: 'account', transport: transport));
    addTearDown(setup.dispose);
    await setup.load();
    final operation = setup.prepare();
    await driver.started.future;
    setup.cancel();
    driver.consent!.complete('token');
    await operation;
    expect(setup.ready, isFalse);
    expect(transport.requests, isEmpty);
    expect(prefs.getKeys(), isEmpty);
  });

  test('setup references are isolated by exact account and OAuth client',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SaveBackupSetup.storageKey('client', 'account'),
        '{"areaId":"reserved-id","ready":true}');
    final auth = DriveAuthorization(_Driver());
    final transport = _Transport(prefs);
    for (final binding in [('client', 'different'), ('different', 'account')]) {
      final setup = SaveBackupSetup(
          accountId: binding.$2,
          clientId: binding.$1,
          preferences: prefs,
          authorization: auth,
          api: DriveSaveBackupAreaApi(
              authorization: auth,
              accountId: binding.$2,
              transport: transport));
      await setup.load();
      expect(setup.ready, isFalse);
      expect(setup.areaId, isNull);
      setup.dispose();
    }
    expect(prefs.getKeys(), hasLength(1));
    expect(transport.requests, isEmpty);
  });
}
