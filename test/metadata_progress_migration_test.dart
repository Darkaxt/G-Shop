import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/models/game_item.dart';
import 'package:g_shop/services/database_service.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';
import 'metadata_controls_test.dart' show ControlsProvider;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('production v34 upgrade retains jobs, identities and exhausted budget',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final prior = await databaseFactory.getDatabasesPath();
    final root =
        await Directory.systemTemp.createTemp('rshop-progress-migration-');
    Database? db;
    try {
      await databaseFactory.setDatabasesPath(root.path);
      DatabaseService.resetForTesting();
      final service = DatabaseService();
      db = await service.database;
      await service.saveGames('psx', [
        const GameItem(
            filename: 'Fixture.chd',
            displayName: 'Fixture',
            url: 'https://example.invalid/Fixture.chd')
      ]);
      final jobs = MetadataRefreshJobs(Future.value(db));
      final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
      await jobs.run(job.id, ControlsProvider());
      await db.insert('metadata_provider_limits', {
        'provider_id': 'screenscraper',
        'next_allowed_at': 7654,
        'requests_per_minute': 60,
        'max_threads': 1,
        'quota_exhausted': 1,
        'remaining_requests': 0
      });
      await db.execute(
          'ALTER TABLE metadata_provider_limits DROP COLUMN quota_json');
      await db.execute(
          'ALTER TABLE metadata_provider_limits DROP COLUMN quota_observed_at');
      final retained = <String, List<Map<String, Object?>>>{};
      for (final table in [
        'games',
        'library_game_identities',
        'library_editions',
        'metadata_refresh_jobs',
        'metadata_refresh_items',
        'metadata_artwork_jobs'
      ]) {
        retained[table] = await db.query(table);
      }
      await db.setVersion(34);
      await db.close();
      DatabaseService.resetForTesting();
      db = await service.database;
      expect(await db.getVersion(), 39);
      for (final table in retained.keys) {
        expect(await db.query(table), retained[table]);
      }
      final limit = (await db.query('metadata_provider_limits')).single;
      expect(limit['remaining_requests'], 0);
      expect(limit['quota_exhausted'], 1);
      expect(limit['next_allowed_at'], 7654);
      expect(limit['requests_per_minute'], 60);
      expect(limit['quota_json'], isNull);
      expect(limit['quota_observed_at'], isNull);
      expect(
          (await MetadataRefreshJobs(Future.value(db)).report(job.id))
              .quotaObservation,
          isNull);
    } finally {
      if (db?.isOpen == true) await db!.close();
      DatabaseService.resetForTesting();
      await databaseFactory.setDatabasesPath(prior);
      expect(root.parent.path, Directory.systemTemp.absolute.path);
      expect(root.path.split(Platform.pathSeparator).last,
          startsWith('rshop-progress-migration-'));
      await root.delete(recursive: true);
    }
  });
}
