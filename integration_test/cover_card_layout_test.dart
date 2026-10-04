import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../test/widgets/cover_card_layout_test.dart';
import '../test/widgets/console_discovery_test.dart';
import '../test/widgets/library_discovery_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final offline = ConsoleOfflineRequests();
  final previous = HttpOverrides.current;
  var surfaceConverted = false;
  setUpAll(() async {
    expect(Platform.isAndroid && kDebugMode, isTrue);
    final package = await PackageInfo.fromPlatform();
    expect(package.packageName, 'com.darkaxt.rshop.debug');
    HttpOverrides.global = offline;
    binding.reportData = {
      'scope':
          'S5 shared cards and normal console/Library/shelf; synthetic data',
      'package': package.packageName,
      'production_bootstrap': false,
      'real_provider_access': false,
    };
  });
  // Flutter restores its native surface in the case that converted it. Several
  // screen checkpoints share one case; reset conversion at the next real case.
  setUp(() => surfaceConverted = false);
  tearDownAll(() {
    HttpOverrides.global = previous;
    expect(offline.attempts.every((uri) => uri.path.endsWith('.png')), isTrue);
    binding.reportData!.addAll({
      'blocked_library_cover_attempts': offline.attempts.length,
      'network_sockets_opened': 0,
      'metadata_requests': 0,
      'rom_requests': 0,
    });
  });
  Future<void> screenshot(String name, WidgetTester tester) async {
    if (!surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      surfaceConverted = true;
    }
    await tester.pump();
    await binding.takeScreenshot(name);
  }

  defineCoverCardLayoutChecks(
      native: true,
      checkpoint: screenshot,
      verified: (check) {
        expect(offline.attempts, isEmpty,
            reason: 'Pure shared cards must not request any remote resource');
        binding.reportData![check] = true;
      });
  defineConsoleDiscoveryChecks(
      factory: databaseFactory,
      reportNetwork: (count) =>
          binding.reportData!['blocked_console_covers'] = count,
      checkpoint: (name, tester) async {
        await screenshot('layout-$name', tester);
        if (name == 'console-cleared-filters') {
          binding.reportData!['normal_console_filter_focus_refresh'] = true;
        }
      });
  defineLibraryDiscoveryChecks(
      factory: databaseFactory,
      checkpoint: (name, tester) async {
        await screenshot('layout-$name', tester);
        if (name == 'library-restored-filters') {
          binding.reportData![
              'normal_library_manual_shelf_and_filter_restore'] = true;
        }
      });
}
