import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../test/widgets/console_discovery_test.dart';
import '../test/library_query_invalidation_migration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var surfaceConverted = false;
  setUpAll(() async {
    expect(Platform.isAndroid && kDebugMode, isTrue);
    final package = await PackageInfo.fromPlatform();
    expect(package.packageName, 'com.darkaxt.rshop.debug');
    binding.reportData = {
      'scope': 'S5 native normal console discovery; synthetic Drive snapshot',
      'package': package.packageName,
      'real_provider_access': false,
    };
  });
  defineConsoleDiscoveryChecks(
      factory: databaseFactory,
      reportNetwork: (attempts) => binding.reportData!.addAll({
            'blocked_cover_attempts': attempts,
            'network_sockets_opened': 0,
            'metadata_requests': 0,
            'rom_requests': 0,
          }),
      checkpoint: (name, tester) async {
        if (!surfaceConverted) {
          await binding.convertFlutterSurfaceToImage();
          surfaceConverted = true;
        }
        await tester.pump();
        await binding.takeScreenshot(name);
        if (name == 'console-cleared-filters') {
          binding.reportData!.addAll({
            'normal_console_screen': true,
            'android_sqlite': true,
            'controller_top_10': true,
            'touch_top_25_sparse_scope': true,
            'other_console_excluded': true,
            'independent_tag_any_all': true,
            'no_backfill_after_score_publication': true,
            'filter_restart_persistence': true,
            'controller_clear_filters': true,
            'score_reorder_identity_focus_preserved': true,
            'controller_large_grid': true,
            'cached_overlays_and_systematic_media': true,
            'repeated_cached_drive_refresh': true,
            'production_bootstrap': false,
          });
        }
      });
  defineQueryInvalidationMigrationCheck(
      factory: databaseFactory,
      verified: () =>
          binding.reportData!['production_v32_upgrade_reopen'] = true);
}
