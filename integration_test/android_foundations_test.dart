import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';
import 'package:retro_eshop/services/drive/google_drive_sign_in.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';

import '../test/support/library_migration_fixture.dart';

/// No production app bootstrap, source scan, account UI or ROM access. These
/// tests run the real registered plugins using synthetic app-private fixtures.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    expect(Platform.isAndroid, isTrue);
    expect(kDebugMode, isTrue);
    final package = await PackageInfo.fromPlatform();
    // Fail before writing fixtures if anyone builds for upstream/release IDs.
    expect(package.packageName, 'com.darkaxt.rshop.debug');
    binding.reportData = {
      'package': package.packageName,
      'version': package.version,
      'build': package.buildNumber,
      'scope': 'synthetic Android foundations; no account or ROM access',
    };
  });

  testWidgets('isolated debug package renders on the native Flutter activity',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('R-Shop native foundation checks')),
      ),
    ));
    expect(find.text('R-Shop native foundation checks'), findsOneWidget);
  });

  testWidgets('native SQLite v13 migration and reopen retain legacy identities',
      (_) async {
    await verifyLibraryV13Migration();
    binding.reportData!['native_sqlite_migration'] = 'passed';
  });

  testWidgets('Android secure storage retains and removes separate credentials',
      (_) async {
    // Use a separate preferences file and key namespace, never the normal
    // provider keys. Values below are synthetic, not usable API credentials.
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(
        sharedPreferencesName: 'rshop_s1_smoke',
        preferencesKeyPrefix: 'rshop_s1_smoke_',
      ),
    );
    ScreenScraperCredentialStore openStore() => ScreenScraperCredentialStore(
        storage: FlutterMetadataSecretStorage(storage: storage));
    final store = openStore();
    const developer = ScreenScraperDeveloperCredentials(
        developerId: 'synthetic-developer',
        developerPassword: 'synthetic-developer-password',
        softwareName: 'RShopNativeFixture');
    const user = ScreenScraperUserCredentials(
        username: 'synthetic-user', password: 'synthetic-user-password');
    try {
      await store.saveDeveloper(developer);
      await store.saveUser(user);
      final reopened = openStore();
      expect((await reopened.readDeveloper())!.developerPassword,
          developer.developerPassword);
      expect((await reopened.readUser())!.password, user.password);
      await reopened.removeUser();
      expect(await store.readUser(), isNull);
      expect((await store.readDeveloper())!.developerId, developer.developerId);
      await reopened.removeDeveloper();
      expect(await store.readDeveloper(), isNull);
    } finally {
      // No deleteAll: only remove the synthetic provider fixture's exact keys.
      await store.removeUser();
      await store.removeDeveloper();
    }
    binding.reportData!['native_secure_storage_roundtrip'] = 'passed';
  });

  testWidgets('native Google plugin initializes without account interaction',
      (_) async {
    // With no client ID, Android init queries its local resource configuration
    // over Pigeon. This proves plugin registration, NOT working OAuth consent.
    await GoogleSignIn.instance.initialize();
    await expectLater(
        GoogleDriveSignIn(serverClientId: '').authenticate(interactive: false),
        throwsA(isA<DriveAuthorizationException>().having(
            (error) => error.issue,
            'issue',
            DriveAuthorizationIssue.setupRequired)));
    binding.reportData!['native_google_plugin_init'] = 'passed';
    binding.reportData!['google_authorization'] = 'not tested: setup required';
  });
}
