import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:retro_eshop/models/config/drive_source_config.dart';
import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';
import 'package:retro_eshop/services/drive/drive_catalogue.dart';
import 'package:retro_eshop/services/drive/drive_runtime.dart';

class _Driver implements DriveAuthorizationDriver {
  final signedOut = Completer<void>();
  final finishSignOut = Completer<void>();
  bool? revoked;
  @override
  Future<String?> authenticate({required bool interactive}) async => 'account';
  @override
  Future<String?> authorize(String accountId, List<String> scopes,
          {required bool interactive}) async =>
      'synthetic-token';
  @override
  Future<void> clearRejectedToken(String accountId, String token) async {}
  @override
  Future<void> signOut({required bool revoke}) async {
    revoked = revoke;
    signedOut.complete();
    await finishSignOut.future;
  }
}

class _Catalogue extends DriveCatalogue {
  final started = Completer<void>();
  final cancelled = Completer<void>();
  final finishRefresh = Completer<void>();
  bool exited = false;
  _Catalogue() : super(Completer<Database>().future);

  @override
  Future<void> refresh(
      {required String sourceId,
      required String accountId,
      required String rootFolderId,
      required DriveCatalogueApi api,
      bool restart = false,
      CancelToken? cancelToken}) async {
    started.complete();
    await cancelToken!.whenCancel;
    cancelled.complete();
    await finishRefresh.future;
    exited = true;
    throw const DriveCatalogueException('cancelled');
  }
}

void main() {
  const config = ProviderConfig(
      type: ProviderType.drive,
      priority: 1,
      sourceId: 'source',
      drive: DriveSourceConfig(
          accountId: 'account',
          rootFolderId: 'folder',
          serverClientId: 'public-client'));

  for (final revoke in [false, true]) {
    test(
        'disconnect revoke=$revoke waits for cancelled refresh and native exit',
        () async {
      final driver = _Driver();
      final catalogue = _Catalogue();
      final runtime = DriveRuntime(
          catalogue: catalogue,
          createAuthorization: (_) => DriveAuthorization(driver));
      final refresh = expectLater(
          runtime.refreshConfig(config),
          throwsA(isA<DriveCatalogueException>()
              .having((e) => e.code, 'code', 'cancelled')));
      await catalogue.started.future;

      var disconnected = false;
      final disconnect = runtime.disconnect(revoke: revoke).then((_) {
        disconnected = true;
      });
      await catalogue.cancelled.future;
      await driver.signedOut.future;
      expect(driver.revoked, revoke);
      expect(disconnected, isFalse);
      expect(() => runtime.authorizationFor('public-client'),
          throwsA(isA<DriveAuthorizationException>()));
      await expectLater(runtime.refreshConfig(config),
          throwsA(isA<DriveAuthorizationException>()));

      driver.finishSignOut.complete();
      expect(disconnected, isFalse);
      catalogue.finishRefresh.complete();
      await refresh;
      await disconnect;
      expect(catalogue.exited, isTrue);
      expect(disconnected, isTrue);
      expect(
          runtime.authorizationFor('public-client'), isA<DriveAuthorization>());
      expect(config.drive!.rootFolderId, 'folder');
    });
  }

  test('disconnect before setup requires no database or native initialization',
      () async {
    final runtime = DriveRuntime(
        createAuthorization: (_) => throw StateError('not expected'));
    await runtime.disconnect();
  });
}
