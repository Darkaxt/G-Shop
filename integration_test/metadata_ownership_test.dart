import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../test/support/igdb_provider_fixture.dart';
import '../test/support/library_verified_match_grouping_fixture.dart';

/// Real native SQLite/production adapters, synthetic wire and private fixtures.
/// Normal sources, accounts, library and installed ROMs are never opened.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    expect(Platform.isAndroid, isTrue);
    expect(kDebugMode, isTrue);
    final package = await PackageInfo.fromPlatform();
    expect(package.packageName, 'com.darkaxt.rshop.debug');
    binding.reportData = {
      'package': package.packageName,
      'version': package.version,
      'build': package.buildNumber,
      'scope':
          'S4 native metadata adapters/jobs/identity/query; synthetic wire',
      'real_provider_access': false,
      'rom_requests': 0,
    };
  });

  testWidgets('isolated metadata ownership fixture renders', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Text('S4 metadata ownership verification'))));
    expect(find.text('S4 metadata ownership verification'), findsOneWidget);
  });

  group('Native ScreenScraper raw-release and project ownership', () {
    defineVerifiedMatchGroupingChecks(databaseFactory);
  });
  group('Native reviewed IGDB ownership and offline query', () {
    defineIgdbProviderChecks(databaseFactory);
  });
}
