import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('existing v41 catalogue opens metadata controls without losing jobs',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final prior = await databaseFactory.getDatabasesPath();
    final root =
        await Directory.systemTemp.createTemp('rshop-resources-migration-');
    Database? db;
    try {
      await databaseFactory.setDatabasesPath(root.path);
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      await db.insert('metadata_refresh_jobs', {
        'generation': 1,
        'provider_id': 'screenscraper',
        'collection_generation': 'retained',
        'state': 'paused',
      });
      await db.execute(
          'ALTER TABLE metadata_refresh_jobs DROP COLUMN resources_only');
      final retained = await db.query('metadata_refresh_jobs');
      await db.setVersion(41);
      await db.close();
      DatabaseService.resetForTesting();

      db = await DatabaseService().database;
      expect(await db.getVersion(), 42);
      final jobs = MetadataRefreshJobs(Future.value(db));
      expect((await jobs.latest(providerId: 'screenscraper'))?.id, 1);
      expect((await jobs.savedJobs(providerId: 'screenscraper')).single.id, 1);
      final rows = await db.query('metadata_refresh_jobs');
      expect(rows.single['resources_only'], 0);
      expect(Map.of(rows.single)..remove('resources_only'), retained.single);
    } finally {
      if (db?.isOpen == true) await db!.close();
      DatabaseService.resetForTesting();
      await databaseFactory.setDatabasesPath(prior);
      // The task-owned test directory is retained for transactional cleanup.
    }
  });
}
