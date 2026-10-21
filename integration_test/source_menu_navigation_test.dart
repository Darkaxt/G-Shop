import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../test/widgets/drive_only_setup_test.dart';

class _NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Source menu fixture forbids real network access');
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final offline = _NoNetwork();
  HttpOverrides? previous;
  setUpAll(() async {
    expect(Platform.isAndroid && kDebugMode, isTrue);
    final package = await PackageInfo.fromPlatform();
    expect(package.packageName, 'com.darkaxt.rshop.debug');
    previous = HttpOverrides.current;
    HttpOverrides.global = offline;
    binding.reportData = {
      'scope': 'S5 normal Sources menus; synthetic config/preferences',
      'package': package.packageName,
      'production_bootstrap': false,
      'real_provider_access': false,
    };
  });
  tearDownAll(() {
    HttpOverrides.global = previous;
    expect(offline.attempts, 0);
    binding.reportData!['http_client_attempts'] = offline.attempts;
  });
  defineDriveOnlySetupChecks(
      native: true,
      verified: (check) => binding.reportData![check] = true,
      checkpoint: (name, tester) async {
        // There is one screenshot per test. Flutter reverts the native surface
        // in that test's teardown, so conversion belongs to each case.
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await binding.takeScreenshot(name);
      });
}
