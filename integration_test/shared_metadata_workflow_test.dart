import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../test/es_de_metadata_controls_test.dart';
import '../test/support/shared_metadata_rebuild_resource_fixture.dart';
import '../test/support/shared_metadata_fixture_path.dart';

/// Android SQLite and external shared storage, synthetic provider replies only.
/// No normal-app bootstrap, accounts, owner's ES-DE layout, ROMs or preferences.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const selectedParent = String.fromEnvironment('RSHOP_SHARED_TEST_PARENT');
  final parent = Directory(selectedParent);
  var ownsParent = false;
  setUpAll(() async {
    expect(Platform.isAndroid && kDebugMode, isTrue);
    final package = await PackageInfo.fromPlatform();
    expect(package.packageName, 'com.darkaxt.rshop.sharedproof');
    // Execution must reserve a new direct volume child. Never accept a library
    // root, Android/data, internal app storage, or an existing user directory.
    expect(selectedParent, isNotEmpty);
    expect(p.normalize(parent.absolute.path), selectedParent);
    expect(isSharedMetadataProofParent(selectedParent), isTrue);
    expect(await parent.exists(), false,
        reason: 'Shared proof parent must be newly reserved for this run');
    await parent.create();
    ownsParent = true;
    binding.reportData = {
      'scope': 'S4 native shared refresh/publication/rebuild',
      'package': package.packageName,
      'version': package.version,
      'build': package.buildNumber,
      'synthetic_provider': true,
      'production_bootstrap': false,
      'rom_requests': 0,
      'owner_application_uninstalled': false,
      'external_fixture_parent': true
    };
  });
  tearDownAll(() async {
    // All helper children join their owners and remove their own exact roots.
    // Never recursively erase this parent or cleanup unrelated failed evidence.
    if (!ownsParent) return;
    expect(await parent.list().isEmpty, true);
    await parent.delete();
  });
  defineEsDeMetadataControlChecks(
      factory: databaseFactory,
      fixtureParent: parent,
      nativeBinding: true,
      report: (report) => binding.reportData!['external_workflow'] = report);
  testWidgets('native shared facts rebuild a new private query offline',
      (_) async {
    binding.reportData!['sqlite_rebuild'] =
        await verifySharedMetadataRebuildResource(databaseFactory, count: 129);
  }, timeout: Timeout.none);
}
