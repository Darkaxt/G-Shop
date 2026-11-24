// Windows catalogue publisher (CATALOGUE-READONLY-01). Run through
// `flutter test tool/publish_catalogue_test.dart` with GSHOP_STORE and
// GSHOP_CATALOGUE set; see scripts/README.md.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/services/metadata/catalogue_publisher.dart';
import 'package:g_shop/services/metadata/shared_metadata_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final storePath = env['GSHOP_STORE'], cataloguePath = env['GSHOP_CATALOGUE'];
  test('publish catalogue', () async {
    sqfliteFfiInit();
    final store = await SharedMetadataStore.open(Directory(storePath!),
        factory: databaseFactoryFfiNoIsolate,
        existingOnly: true,
        verifyAccess: () async {});
    try {
      final platforms = env['GSHOP_PLATFORMS']
          ?.split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();
      final publisher = CataloguePublisher(
          store: store,
          catalogue: Directory(cataloguePath!),
          platforms: platforms == null || platforms.isEmpty ? null : platforms,
          dryRun: env['GSHOP_DRY_RUN'] == '1',
          log: print);
      final summary = await publisher.publish();
      for (final m in summary.missing) {
        print('missing local body: $m');
      }
      print('SUMMARY ${publisher.dryRun ? '(dry run) ' : ''}$summary');
      if (env['GSHOP_SUMMARY'] case final path? when path.isNotEmpty) {
        await File(path).writeAsString(
            const JsonEncoder.withIndent('  ').convert(summary.toJson()));
      }
    } finally {
      await store.close();
    }
  },
      skip: storePath == null || cataloguePath == null
          ? 'Set GSHOP_STORE and GSHOP_CATALOGUE'
          : false,
      timeout: Timeout.none);
}
