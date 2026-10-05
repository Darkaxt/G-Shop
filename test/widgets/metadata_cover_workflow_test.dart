import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../helpers/metadata_cover_workflow_checks.dart';
import '../helpers/resolved_cover_checks.dart';
import 'console_discovery_test.dart';
import 'library_discovery_test.dart';

void main() {
  // SQLite and FileImage use real OS completion. Keep all producers and UI
  // consumers in the same real clock instead of crossing FakeAsync lock queues.
  LiveTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  final previousPaths = PathProviderPlatform.instance;
  final previousHttp = HttpOverrides.current;
  final offline = ConsoleOfflineRequests();
  final covers = ResolvedCoverChecks();
  setUpAll(() async {
    PathProviderPlatform.instance = _HostPaths();
    HttpOverrides.global = offline;
    await covers.setUp();
  });
  tearDownAll(() async {
    await covers.tearDown();
    PathProviderPlatform.instance = previousPaths;
    HttpOverrides.global = previousHttp;
  });
  defineConsoleDiscoveryChecks(checkpoint: (name, tester) async {
    if (name == 'console-cleared-filters') {
      await verifyMetadataCoverWorkflow('console', tester);
    }
  });
  defineLibraryDiscoveryChecks(checkpoint: (name, tester) async {
    if (name == 'library-top-10-scope' || name == 'library-manual-shelf') {
      await verifyMetadataCoverWorkflow(name, tester);
    }
  });
}

class _HostPaths extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
  @override
  Future<String?> getApplicationSupportPath() async =>
      Platform.environment['RSHOP_TEST_FONT_CACHE'];
}
