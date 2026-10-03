import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test(
      'real v26 upgrade indexes exact refresh ownership without changing facts',
      () async {
    final originalPath = await databaseFactory.getDatabasesPath();
    final root =
        await Directory.systemTemp.createTemp('rshop-rating-migration-');
    Database? db;
    try {
      await databaseFactory.setDatabasesPath(root.path);
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      expect(p.isWithin(root.path, db.path), isTrue);
      final store = LibraryStore(Future.value(db));
      await store.putGame(GameIdentity(
          id: 'fixture-game',
          platformId: 'psx',
          title: 'Fixture',
          providerIds: {'igdb': '91'},
          matchStatus: IdentityMatchStatus.manuallyMatched));
      await store.putEdition(EditionIdentity(
          id: 'fixture-edition', gameId: 'fixture-game', tags: {'official'}));
      final at = DateTime.utc(2026, 10, 3);
      final record = MetadataRecord(
          gameId: 'fixture-game',
          editionId: 'fixture-edition',
          platformId: 'psx',
          providerId: 'igdb',
          providerGameId: '91',
          retrievedAt: at,
          refreshGeneration: 1,
          matchMethod: 'verifiedProviderIdGlobalGame',
          titles: const [
            MetadataText(text: 'Fixture')
          ],
          ratings: [
            SourcedRating.parse(
                sourceId: 'igdb',
                sourceLabel: 'IGDB',
                providerGameId: '91',
                rawValue: '81',
                scaleMinimum: 0,
                scaleMaximum: 100,
                voteCount: 100,
                kind: RatingKind.overallAggregate,
                retrievedAt: at)!
          ]);
      await store.putMetadata(record);
      final job = await MetadataRefreshJobs(Future.value(db)).create(
          providerId: 'igdb',
          collectionGeneration: 'fixture-current',
          editionIds: ['fixture-edition']);
      final metadataBefore = await db.query('library_metadata');
      final itemsBefore = await db.query('metadata_refresh_items');
      await db.update('metadata_refresh_jobs', {'state': 'running'},
          where: 'id = ?', whereArgs: [job.id]);
      await db.execute('DROP INDEX idx_metadata_refresh_edition');
      await db.setVersion(26);
      await db.close();
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      expect(await db.getVersion(), 27);
      expect(await db.query('library_metadata'), metadataBefore);
      expect(await db.query('metadata_refresh_items'), itemsBefore);
      final jobs = await db.query('metadata_refresh_jobs');
      expect(jobs.single['state'], 'paused');
      expect(jobs.single['generation'], job.generation);
      final plan = await db.rawQuery('''EXPLAIN QUERY PLAN SELECT 1
        FROM metadata_refresh_items i JOIN metadata_refresh_jobs j ON j.id = i.job_id
        WHERE i.edition_id = ? AND i.identity_key = ? AND j.provider_id = ?
          AND j.is_artwork = 0 AND j.generation > ?''',
          ['fixture-edition', itemsBefore.single['identity_key'], 'igdb', 1]);
      expect(
          plan.any((row) => (row['detail'] as String)
              .contains('idx_metadata_refresh_edition')),
          isTrue);
      final result = (await LibraryStore(Future.value(db))
          .effectiveRatings(['fixture-edition']))['fixture-edition']!;
      expect(result.rating.toJson(), record.ratings.single.toJson());
      expect(result.fresh, isFalse);
      expect(result.rankingEligible, isFalse);
      await db.close();
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      expect(await db.query('library_metadata'), metadataBefore);
      expect(
          (await LibraryStore(Future.value(db))
                  .effectiveRatings(['fixture-edition']))['fixture-edition']!
              .fresh,
          isFalse);
    } finally {
      await db?.close();
      DatabaseService.resetForTesting();
      await databaseFactory.setDatabasesPath(originalPath);
      if (!p.isWithin(Directory.systemTemp.path, root.path) ||
          !p.basename(root.path).startsWith('rshop-rating-migration-')) {
        throw StateError('Unexpected fixture cleanup root');
      }
      await root.delete(recursive: true);
    }
  });
}
