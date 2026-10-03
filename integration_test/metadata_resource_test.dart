import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../test/support/library_query_resource_fixture.dart';
import '../test/support/metadata_artwork_resource_fixture.dart';

/// Real Android SQLite, filesystem and image decoder; synthetic transport only.
/// Does not bootstrap production sources, authorize accounts or read SD ROMs.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    expect(Platform.isAndroid, isTrue);
    expect(kDebugMode, isTrue);
    final package = await PackageInfo.fromPlatform();
    expect(package.packageName, 'com.darkaxt.rshop.debug',
        reason: 'Only the isolated debug package may create these fixtures');
    binding.reportData = {
      'package': package.packageName,
      'version': package.version,
      'build': package.buildNumber,
      'scope':
          'S4 synthetic native 30000-game query/artwork; no account or ROM IO',
    };
  });

  testWidgets('native indexed collection query stays bounded for 30000 games',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Text('S4 native indexed-query verification'))));
    binding.reportData!['native_query'] =
        await verifyLibraryQueryResource(databaseFactory);
  }, timeout: Timeout.none);

  testWidgets('native persistent artwork job completes and reopens offline',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Text('S4 native artwork verification'))));
    binding.reportData!['native_artwork'] =
        await verifyMetadataArtworkResource(databaseFactory);
  }, timeout: Timeout.none);
}
