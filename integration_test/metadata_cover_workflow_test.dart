import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../test/helpers/metadata_cover_workflow_checks.dart';
import '../test/helpers/resolved_cover_checks.dart';
import '../test/widgets/console_discovery_test.dart';
import '../test/widgets/library_discovery_test.dart';

/// Native SQLite, real file decoding, normal refresh controls and shared UI.
/// Only the provider response is synthetic; no production bootstrap or ROM IO.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final covers = ResolvedCoverChecks();
  final offline = ConsoleOfflineRequests();
  final previous = HttpOverrides.current;
  var converted = false;
  setUpAll(() async {
    expect(Platform.isAndroid && kDebugMode, isTrue);
    expect((await PackageInfo.fromPlatform()).packageName,
        'com.darkaxt.rshop.sharedproof');
    HttpOverrides.global = offline;
    await covers.setUp();
    binding.reportData = {
      'scope': 'S4 normal metadata refresh to owned cache and normal consumers',
      'production_bootstrap': false,
      'real_provider_access': false,
      'network_sockets_opened': 0,
      'rom_requests': 0,
    };
  });
  setUp(() => converted = false);
  tearDownAll(() async {
    expect(
        offline.attempts.every((u) =>
            u.host == 'raw.githubusercontent.com' &&
            u.path.startsWith('/libretro-thumbnails/') &&
            u.path.endsWith('.png')),
        isTrue);
    await covers.tearDown();
    HttpOverrides.global = previous;
  });
  Future<void> verify(String view, WidgetTester tester) async {
    await verifyMetadataCoverWorkflow(view, tester);
    if (!converted) {
      await binding.convertFlutterSurfaceToImage();
      converted = true;
    }
    await tester.pump();
    await binding.takeScreenshot('metadata-artwork-$view');
    binding.reportData![view] = true;
  }

  defineConsoleDiscoveryChecks(
      factory: databaseFactory,
      reportNetwork: (count) =>
          binding.reportData!['blocked_legacy_boxart'] = count,
      checkpoint: (name, tester) async {
        if (name == 'console-cleared-filters') await verify('console', tester);
      });
  defineLibraryDiscoveryChecks(
      factory: databaseFactory,
      checkpoint: (name, tester) async {
        if (name == 'library-top-10-scope' || name == 'library-manual-shelf') {
          await verify(name, tester);
        }
      });
}
