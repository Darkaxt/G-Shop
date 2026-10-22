import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/services/database_service.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/services/library_store.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';

void main() {
  test('production v31 upgrade preserves jobs and defaults to normal refresh',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final previousPath = await databaseFactory.getDatabasesPath();
    final root =
        await Directory.systemTemp.createTemp('rshop-match-migration-');
    Database? db;
    try {
      await databaseFactory.setDatabasesPath(root.path);
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      final store = LibraryStore(Future.value(db));
      await store.putGame(GameIdentity(
          id: 'preserved-game',
          platformId: 'psx',
          title: 'Preserved',
          providerIds: {'screenscraper': '99'},
          matchStatus: IdentityMatchStatus.manuallyMatched));
      await store.putEdition(EditionIdentity(
          id: 'preserved-edition',
          gameId: 'preserved-game',
          tags: {'official'}));
      await store.putMetadata(MetadataRecord(
          gameId: 'preserved-game',
          editionId: 'preserved-edition',
          platformId: 'psx',
          providerId: 'screenscraper',
          providerGameId: '99',
          retrievedAt: DateTime.utc(2026),
          refreshGeneration: 1,
          matchMethod: 'verifiedProviderId',
          titles: const [MetadataText(text: 'Retained facts')]));
      final job = await MetadataRefreshJobs(Future.value(db)).create(
          providerId: 'screenscraper',
          collectionGeneration: 'preserved-generation',
          editionIds: const ['preserved-edition']);
      // Reconstruct the actual v31 column layout, not a v32 database relabelled.
      await db.execute(
          'ALTER TABLE metadata_refresh_jobs DROP COLUMN is_match_review');
      final before = await db.query('metadata_refresh_jobs');
      final tables = [
        'games',
        'library_game_identities',
        'library_editions',
        'library_metadata',
        'metadata_refresh_items'
      ];
      final preserved = <String, List<Map<String, Object?>>>{};
      for (final table in tables) {
        preserved[table] = await db.query(table);
      }
      await db.setVersion(31);
      await db.close();
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      expect(await db.getVersion(), 44);
      final after = await db.query('metadata_refresh_jobs');
      expect(after, hasLength(before.length));
      for (var i = 0; i < after.length; i++) {
        final row = Map<String, Object?>.from(after[i]);
        expect(row.remove('is_match_review'), 0);
        expect(row, before[i]);
      }
      for (final table in tables) {
        expect(await db.query(table), preserved[table]);
      }
      expect((await MetadataRefreshJobs(Future.value(db)).report(job.id)).id,
          job.id);
      await db.close();
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      expect(await db.query('metadata_refresh_jobs'), after);
    } finally {
      if (db?.isOpen == true) await db!.close();
      DatabaseService.resetForTesting();
      await databaseFactory.setDatabasesPath(previousPath);
      if (!p.isWithin(Directory.systemTemp.path, root.path) ||
          !p.basename(root.path).startsWith('rshop-match-migration-')) {
        throw StateError('Unexpected migration fixture cleanup root');
      }
      await root.delete(recursive: true);
    }
  });
}
