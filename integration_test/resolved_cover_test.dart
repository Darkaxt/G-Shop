import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../test/helpers/resolved_cover_checks.dart';
import '../test/widgets/cover_card_layout_test.dart';
import '../test/widgets/console_discovery_test.dart';
import '../test/widgets/library_discovery_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final covers = ResolvedCoverChecks();
  final offline = ConsoleOfflineRequests();
  final previous = HttpOverrides.current;
  var converted = false;
  setUpAll(() async {
    expect(Platform.isAndroid && kDebugMode, isTrue);
    expect((await PackageInfo.fromPlatform()).packageName,
        'com.darkaxt.rshop.debug');
    HttpOverrides.global = offline;
    await covers.setUp();
    binding.reportData = {
      'scope': 'S5 resolved covers in normal console/Library/shelf',
      'production_bootstrap': false,
      'real_provider_access': false,
      'network_sockets_opened': 0,
      'rom_requests': 0,
    };
  });
  setUp(() => converted = false);
  tearDownAll(() async {
    expect(
        offline.attempts.every((uri) =>
            uri.host == 'raw.githubusercontent.com' &&
            uri.path.startsWith('/libretro-thumbnails/') &&
            uri.path.endsWith('.png')),
        isTrue);
    await covers.tearDown();
    HttpOverrides.global = previous;
  });
  Future<void> verify(String view, WidgetTester tester) =>
      covers.verify(view, tester, () async {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
        }
        await tester.pump();
        await binding.takeScreenshot('resolved-cover-$view');
        final requests = HttpOverrides.current as ConsoleOfflineRequests;
        expect(requests.attempts.where((u) => u.host == 'example.invalid'),
            isEmpty,
            reason: 'The resolved cache must not fetch its cover URL');
        binding.reportData!['resolved_$view'] = true;
        binding.reportData!['resolved_cover_network_requests'] = 0;
      });
  Future<void> screenshot(String name, WidgetTester tester) async {
    if (!converted) {
      await binding.convertFlutterSurfaceToImage();
      converted = true;
    }
    await tester.pump();
    await binding.takeScreenshot('resolved-$name');
    binding.reportData![name] = true;
  }

  defineCoverCardLayoutChecks(
      native: true,
      checkpoint: screenshot,
      verified: (check) {
        expect(offline.attempts, isEmpty);
        binding.reportData![check] = true;
      });

  defineConsoleDiscoveryChecks(
      factory: databaseFactory,
      reportNetwork: (count) =>
          binding.reportData!['blocked_existing_console_boxart'] = count,
      checkpoint: (name, tester) async {
        await screenshot(name, tester);
        if (name == 'console-cleared-filters') await verify('console', tester);
      });
  defineLibraryDiscoveryChecks(
      factory: databaseFactory,
      checkpoint: (name, tester) async {
        await screenshot(name, tester);
        if (name == 'library-top-10-scope') await verify('library', tester);
        if (name == 'library-manual-shelf') await verify('shelf', tester);
      });
}
