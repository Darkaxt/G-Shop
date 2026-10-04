import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import '../test/widgets/metadata_match_correction_test.dart';

/// Normal exact-game settings/review, synthetic provider and Android SQLite.
/// No user database bootstrap, provider account, ROM or socket access.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final previous = HttpOverrides.current;
  var converted = false;
  setUpAll(() async {
    expect(Platform.isAndroid && kDebugMode, isTrue);
    final package = await PackageInfo.fromPlatform();
    expect(package.packageName, 'com.darkaxt.rshop.debug');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    HttpOverrides.global = _NoNetwork();
    binding.reportData = {
      'scope': 'S5 exact-game wrong-match correction; synthetic cache',
      'package': package.packageName,
      'real_provider_access': false,
      'rom_requests': 0,
      'network_sockets_opened': 0,
    };
  });
  tearDownAll(() => HttpOverrides.global = previous);
  defineMetadataMatchCorrectionChecks(
      factory: databaseFactory,
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

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Network forbidden in synthetic correction fixture');
}
