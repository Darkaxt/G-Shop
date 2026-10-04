import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../helpers/resolved_cover_checks.dart';
import 'console_discovery_test.dart';
import 'library_discovery_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    expect(
        offline.attempts.every((uri) =>
            uri.host == 'raw.githubusercontent.com' &&
            uri.path.startsWith('/libretro-thumbnails/') &&
            uri.path.endsWith('.png')),
        isTrue);
    await covers.tearDown();
    PathProviderPlatform.instance = previousPaths;
    HttpOverrides.global = previousHttp;
  });
  defineConsoleDiscoveryChecks(checkpoint: (name, tester) async {
    if (name == 'console-cleared-filters') {
      await covers.verify('console', tester, () async {});
    }
  });
  defineLibraryDiscoveryChecks(checkpoint: (name, tester) async {
    if (name == 'library-top-10-scope') {
      await covers.verify('library', tester, () async {});
    }
    if (name == 'library-manual-shelf') {
      await covers.verify('shelf', tester, () async {});
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
