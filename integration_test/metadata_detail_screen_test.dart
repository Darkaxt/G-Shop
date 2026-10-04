import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../test/widgets/console_discovery_test.dart'
    show ConsoleOfflineRequests;
import '../test/widgets/metadata_detail_screen_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final offline = ConsoleOfflineRequests();
  final previous = HttpOverrides.current;
  var converted = false;
  setUpAll(() async {
    expect(Platform.isAndroid && kDebugMode, isTrue);
    final package = await PackageInfo.fromPlatform();
    expect(package.packageName, 'com.darkaxt.rshop.debug');
    HttpOverrides.global = offline;
    binding.reportData = {
      'scope': 'S5 normal details/provenance/error/exact-game controls',
      'package': package.packageName,
      'production_bootstrap': false,
      'real_provider_access': false,
    };
  });
  tearDownAll(() {
    HttpOverrides.global = previous;
    expect(offline.attempts.every((uri) => uri.path.endsWith('.png')), isTrue);
    binding.reportData!.addAll({
      'blocked_cover_attempts': offline.attempts.length,
      'network_sockets_opened': 0,
      'rom_requests': 0,
    });
  });
  defineMetadataDetailScreenChecks(
      factory: databaseFactory,
      native: true,
      checkpoint: (name, tester) async {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
        }
        await tester.pump();
        await binding.takeScreenshot(name);
        binding.reportData![name] = true;
      });
}
