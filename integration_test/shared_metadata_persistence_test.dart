import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';

import '../test/support/shared_metadata_lifecycle_fixture.dart';
import '../test/support/shared_metadata_fixture_path.dart';

class _NoNetwork extends HttpOverrides {
  int clients = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    throw StateError('Lifecycle proof must not contact any network service');
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const selectedParent = String.fromEnvironment('RSHOP_SHARED_TEST_PARENT');
  final phase = PlatformDispatcher.instance.defaultRouteName.substring(1);
  testWidgets(
      'shared metadata survives the requested native lifecycle boundary',
      (_) async {
    expect(Platform.isAndroid && kDebugMode, true);
    expect((await PackageInfo.fromPlatform()).packageName,
        'com.darkaxt.rshop.sharedproof');
    expect(sharedLifecyclePhases, contains(phase));
    expect(p.normalize(selectedParent), selectedParent);
    expect(isSharedMetadataProofParent(selectedParent), true);
    final accessGranted =
        (await Permission.manageExternalStorage.status).isGranted;
    expect(accessGranted, phase != 'denied',
        reason:
            'Native permission phase must reflect the actual Android grant');
    final network = _NoNetwork();
    final old = HttpOverrides.current;
    HttpOverrides.global = network;
    try {
      binding.reportData = await verifySharedMetadataLifecycle(
          factory: databaseFactory,
          external: Directory(selectedParent),
          privateRoot: Directory(p.join(
              (await getApplicationSupportDirectory()).path,
              'shared-proof-private')),
          phase: phase);
      expect(network.clients, 0);
      binding.reportData!['network_clients'] = network.clients;
      binding.reportData!['shared_storage_permission_granted'] = accessGranted;
      binding.reportData!['native_lifecycle_requires_supervisor_evidence'] =
          true;
    } finally {
      HttpOverrides.global = old;
    }
    // Retain exact synthetic state for the next process/permission/uninstall
    // boundary. The supervisor cleans it only after final verified recovery.
  }, timeout: Timeout.none);
}
