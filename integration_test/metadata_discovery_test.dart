import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../test/widgets/library_discovery_test.dart';

/// Native database/display and normal Library, not main.dart or user sources.
/// The network boundary rejects every request before opening a socket.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final offline = _OfflineImages();
  final previous = HttpOverrides.current;
  var surfaceConverted = false;
  setUpAll(() async {
    expect(Platform.isAndroid && kDebugMode, isTrue);
    final package = await PackageInfo.fromPlatform();
    expect(package.packageName, 'com.darkaxt.rshop.debug');
    HttpOverrides.global = offline;
    binding.reportData = {
      'scope': 'S5 native normal Library discovery; synthetic cache',
      'package': package.packageName,
      'real_provider_access': false,
      'network_sockets_opened': 0,
      'rom_requests': 0,
    };
  });
  tearDownAll(() => HttpOverrides.global = previous);
  defineLibraryDiscoveryChecks(
      factory: databaseFactory,
      checkpoint: (name, tester) async {
        if (!surfaceConverted) {
          // This SDK registers the matching surface restoration at teardown.
          await binding.convertFlutterSurfaceToImage();
          surfaceConverted = true;
        }
        await tester.pump();
        await binding.takeScreenshot(name);
        if (name == 'library-restored-filters') {
          // Existing cover fallbacks are distinct from metadata/ROM requests.
          expect(offline.attempts.every((uri) => uri.path.endsWith('.png')),
              isTrue);
          binding.reportData!.addAll({
            'normal_library': true,
            'controller_top_10': true,
            'touch_top_25_sparse_collection': true,
            'one_cross_console_cap': true,
            'scope_change': true,
            'tag_intersection_no_backfill': true,
            'score_publication_recomputes': true,
            'manual_shelf_preserved': true,
            'explicit_rating_order_focus_preserved': true,
            'filter_restart_persistence': true,
            'offline_library_shelf_media_fallbacks': true,
            'blocked_cover_attempts': offline.attempts.length,
          });
        }
      });
}

class _OfflineImages extends HttpOverrides {
  final attempts = <Uri>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _OfflineClient(attempts);
}

class _OfflineClient implements HttpClient {
  final List<Uri> attempts;
  _OfflineClient(this.attempts);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    attempts.add(url);
    return Future.error(const SocketException('Synthetic offline fixture'));
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}
