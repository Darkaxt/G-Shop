import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/metadata/effective_overall_rating.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test('production v27 upgrade and cold reopen preserve facts and query views',
      () async {
    final original = await databaseFactory.getDatabasesPath();
    final root =
        await Directory.systemTemp.createTemp('rshop-query-migration-');
    Database? db;
    try {
      await databaseFactory.setDatabasesPath(root.path);
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      expect(p.isWithin(root.path, db.path), isTrue);
      // Build actual pre-query v27 schema without the new projection or triggers.
      for (final trigger in await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'query_%'")) {
        final name = trigger['name'] as String;
        expect(RegExp(r'^query_[a-z_]+$').hasMatch(name), isTrue);
        await db.execute('DROP TRIGGER $name');
      }
      for (final table in [
        'library_query_editions',
        'library_query_facets',
        'library_query_dirty',
        'library_query_cache_dirty',
        'library_query_policy',
        'library_query_views'
      ]) {
        await db.execute('DROP TABLE IF EXISTS $table');
      }
      await db.insert('games', {
        'id': 1,
        'systemSlug': 'psx',
        'filename': 'Fixture.chd',
        'displayName': 'Fixture',
        'url': 'https://example.invalid/Fixture.chd'
      });
      final store = LibraryStore(Future.value(db));
      final id = (await db.transaction(
              (txn) => LibraryStore.catalogueEditions(txn).toList()))
          .single;
      final edition = (await store.edition(id))!;
      final game = (await store.game(edition.gameId))!;
      await store.putGame(GameIdentity.fromJson({
        ...game.toJson(),
        'providerIds': {'igdb': '91'},
        'matchStatus': 'manuallyMatched'
      }));
      await store.putEdition(EditionIdentity.fromJson({
        ...edition.toJson(),
        'tags': ['official']
      }));
      final at = DateTime.utc(2026, 10, 3);
      await store.putMetadata(MetadataRecord(
          gameId: game.id,
          editionId: id,
          platformId: 'psx',
          providerId: 'igdb',
          providerGameId: '91',
          retrievedAt: at,
          refreshGeneration: 1,
          matchMethod: 'verifiedProviderIdGlobalGame',
          titles: [
            MetadataText(text: 'Fixture')
          ],
          ratings: [
            SourcedRating.parse(
                sourceId: 'igdb',
                sourceLabel: 'IGDB',
                providerGameId: '91',
                rawValue: 85,
                scaleMinimum: 0,
                scaleMaximum: 100,
                voteCount: 100,
                kind: RatingKind.overallAggregate,
                retrievedAt: at)!
          ]));
      final before = await db.query('library_metadata');
      final filesBefore = await db.query('games');
      await db.setVersion(27);
      await db.close();
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      expect(await db.getVersion(), 28);
      expect(await db.query('library_metadata'), before);
      expect(await db.query('games'), filesBefore);
      final basis = AssessedOverallScoreBasis(
          sourceId: 'igdb',
          kind: RatingKind.overallAggregate,
          scaleMinimum: 0,
          scaleMaximum: 100,
          platformIds: {'psx'},
          minimumVoteCount: 10,
          assessmentReference: 'synthetic-migration-assessment');
      var query = LibraryQuery(Future.value(db));
      await query.replaceViewMembers('shelf:fixture', [id]);
      var result = await query.page(
          filter: LibraryQueryFilter(top: 25, viewIds: {'shelf:fixture'}),
          assessedBases: [basis]);
      expect(result.items.single.editionId, id);
      expect(result.items.single.rank, 1);
      final projection = await db.query('library_query_editions');
      await db.close();
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      query = LibraryQuery(Future.value(db));
      result = await query.page(
          filter: LibraryQueryFilter(top: 25, viewIds: {'shelf:fixture'}),
          assessedBases: [basis]);
      expect(result.items.single.editionId, id);
      expect(await db.query('library_query_editions'), projection);
      expect(await db.query('library_metadata'), before);
      // Dirty state is durable, not an in-memory subscription lost on restart.
      await db.delete('games', where: 'id = 1');
      await db.close();
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      result = await LibraryQuery(Future.value(db))
          .page(filter: LibraryQueryFilter(top: 25), assessedBases: [basis]);
      expect(result.collectionGames, 0);
      expect(result.items, isEmpty);
      expect(await db.query('library_metadata'), before);
    } finally {
      await db?.close();
      DatabaseService.resetForTesting();
      await databaseFactory.setDatabasesPath(original);
      if (!p.isWithin(Directory.systemTemp.path, root.path) ||
          !p.basename(root.path).startsWith('rshop-query-migration-')) {
        throw StateError('Unexpected fixture cleanup root');
      }
      await root.delete(recursive: true);
    }
  });
}
