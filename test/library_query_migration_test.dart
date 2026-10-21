import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/services/database_service.dart';
import 'package:g_shop/services/library_store.dart';
import 'package:g_shop/services/library_query.dart';
import 'package:g_shop/services/metadata/effective_overall_rating.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test('production v30 upgrade reinterprets aliases without rewriting evidence',
      () async {
    final original = await databaseFactory.getDatabasesPath();
    final root =
        await Directory.systemTemp.createTemp('rshop-query-migration-');
    Database? db;
    try {
      await databaseFactory.setDatabasesPath(root.path);
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
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
      // Write actual historical JSON directly; do not seed through the new model.
      await db.update(
          'library_editions',
          {
            'record_json': jsonEncode({
              ...edition.toJson(),
              'tags': [' OFFICIAL ']
            })
          },
          where: 'edition_id = ?',
          whereArgs: [id]);
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
          titles: const [
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
      await MetadataRefreshJobs(Future.value(db))
          .createFromCatalogue(providerId: 'screenscraper');
      expect(await store.metadata(id, 'igdb'), isNotNull,
          reason: 'Catalogue capture must preserve the original binding.');
      final basis = AssessedOverallScoreBasis(
          sourceId: 'igdb',
          kind: RatingKind.overallAggregate,
          scaleMinimum: 0,
          scaleMaximum: 100,
          platformIds: {'psx'},
          minimumVoteCount: 10,
          assessmentReference: 'synthetic-alias-assessment');
      final query = LibraryQuery(Future.value(db));
      await query.replaceViewMembers('shelf:fixture', [id]);
      await query.page(filter: LibraryQueryFilter(), assessedBases: [basis]);
      // v30 had raw spellings in its facets and no eligible alias-owned score.
      await db.update('library_query_facets', {'value': ' official '},
          where: 'edition_id = ? AND dimension = ?', whereArgs: [id, 'tag']);
      await db.update(
          'library_query_editions', {'score': null, 'rating_eligible': 0});
      await db.delete('library_query_dirty');
      final preserved = <String, List<Map<String, Object?>>>{};
      for (final table in [
        'games',
        'library_game_identities',
        'library_editions',
        'library_metadata',
        'metadata_refresh_jobs',
        'metadata_refresh_items',
        'library_query_views'
      ]) {
        preserved[table] = await db.query(table);
      }
      await db.setVersion(30);
      await db.close();
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      for (var reopen = 0; reopen < 2; reopen++) {
        final currentDb = db!;
        final result = await LibraryQuery(Future.value(currentDb)).page(
            filter: LibraryQueryFilter(
                top: 1, tags: {'official'}, viewIds: {'shelf:fixture'}),
            assessedBases: [basis]);
        expect(result.items.map((i) => i.editionId), [id]);
        expect(result.items.single.score!.rating.normalizedValue, 85);
        expect(await currentDb.getVersion(), 39);
        expect((await LibraryStore(Future.value(currentDb)).edition(id))!.tags,
            {'official'});
        expect(await LibraryStore(Future.value(currentDb)).metadata(id, 'igdb'),
            isNotNull);
        for (final entry in preserved.entries) {
          expect(await currentDb.query(entry.key), entry.value,
              reason: entry.key);
        }
        if (reopen == 0) {
          await currentDb.close();
          DatabaseService.resetForTesting();
          db = await DatabaseService().database;
        }
      }
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
  test('production v29 upgrade backfills raw/project matches and exact facts',
      () async {
    final original = await databaseFactory.getDatabasesPath();
    final root =
        await Directory.systemTemp.createTemp('rshop-query-migration-');
    Database? db;
    try {
      await databaseFactory.setDatabasesPath(root.path);
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      final store = LibraryStore(Future.value(db));
      final at = DateTime.utc(2026, 10, 3);
      for (final n in [1, 2]) {
        await db.insert('games', {
          'id': n,
          'systemSlug': 'snes',
          'filename': 'Fixture$n.sfc',
          'displayName': 'Fixture $n',
          'url': 'https://example.invalid/$n'
        });
        await store.putGame(GameIdentity(
            id: 'game:$n', platformId: 'snes', title: 'Fixture $n'));
        await store.putEdition(EditionIdentity(
            id: 'edition:$n', gameId: 'game:$n', tags: {'official'}));
        await store.putMetadata(MetadataRecord(
            gameId: 'game:$n',
            editionId: 'edition:$n',
            platformId: 'snes',
            providerId: 'screenscraper',
            providerGameId: '42',
            retrievedAt: at,
            refreshGeneration: 1,
            matchMethod: 'rawRomHashAndSize',
            titles: [MetadataText(text: 'Fixture $n')]));
      }
      await store.putGame(GameIdentity(
          id: 'base',
          platformId: 'snes',
          title: 'Base',
          providerIds: {'igdb': '100'},
          matchStatus: IdentityMatchStatus.manuallyMatched));
      for (final n in [3, 4]) {
        await store.putGame(GameIdentity(
            id: 'game:$n',
            platformId: 'snes',
            title: 'Project',
            providerIds: {'igdb': '99'},
            baseGameId: 'base',
            matchStatus: IdentityMatchStatus.manuallyMatched));
        await store.putEdition(EditionIdentity(
            id: 'edition:$n',
            gameId: 'game:$n',
            tags: {'Hack'},
            patchId: 'patch:$n'));
        await store.putMetadata(MetadataRecord(
            gameId: 'game:$n',
            editionId: 'edition:$n',
            platformId: 'snes',
            providerId: 'igdb',
            providerGameId: '99',
            retrievedAt: at,
            refreshGeneration: 1,
            matchMethod: 'verifiedProjectId',
            titles: const [MetadataText(text: 'Project')]));
      }
      await LibraryQuery(Future.value(db))
          .replaceViewMembers('shelf:fixture', ['edition:1', 'edition:2']);
      final factsBefore = await db.query('library_metadata');
      final editionsBefore = await db.query('library_editions');
      final filesBefore = await db.query('games');
      final viewsBefore = await db.query('library_query_views');
      // Recreate the actual v29 projection, which did not include raw matches.
      await db.delete('library_canonical_claims');
      for (final n in [1, 2, 3, 4]) {
        await db.insert('library_canonical_claims', {
          'edition_id': 'edition:$n',
          'claim_key': jsonEncode(['game', 'game:$n'])
        });
        await db.update(
            'library_canonical_groups',
            {
              'group_key': jsonEncode(['game', 'game:$n'])
            },
            where: 'edition_id = ?',
            whereArgs: ['edition:$n']);
      }
      await db.execute('DROP INDEX idx_library_canonical_base');
      await db.execute(
          'ALTER TABLE library_canonical_groups DROP COLUMN base_game_id');
      await db.setVersion(29);
      await db.close();
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      expect(await db.getVersion(), 39);
      expect(await db.query('library_metadata'), factsBefore);
      expect(await db.query('library_editions'), editionsBefore);
      expect(await db.query('games'), filesBefore);
      expect(await db.query('library_query_views'), viewsBefore);
      expect(
          (await LibraryStore(Future.value(db)).canonicalEditions('edition:1'))
              .editions
              .map((e) => e.id),
          ['edition:1', 'edition:2']);
      await db.close();
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      expect(
          (await LibraryStore(Future.value(db)).canonicalEditions('edition:2'))
              .editions,
          hasLength(2));
      expect(
          (await LibraryStore(Future.value(db)).canonicalEditions('edition:3'))
              .editions
              .map((e) => e.id),
          ['edition:3', 'edition:4']);
      await LibraryStore(Future.value(db)).putGame(GameIdentity(
          id: 'base',
          platformId: 'snes',
          title: 'Corrected base',
          providerIds: {'igdb': '99'},
          matchStatus: IdentityMatchStatus.manuallyMatched));
      expect(
          (await LibraryStore(Future.value(db)).canonicalEditions('edition:3'))
              .editions,
          hasLength(1));
      expect(await db.query('library_metadata'), factsBefore);
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
      expect(await db.getVersion(), 39);
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
      // Recreate v28's missing alias projection and old game-only IGDB group.
      // Upgrade must preserve existing scores/views and backfill real aliases.
      final viewsBefore = await db.query('library_query_views');
      await db.execute('DROP TABLE library_canonical_claims');
      await db.update(
          'library_canonical_groups', {'group_key': '["game","${game.id}"]'},
          where: 'edition_id = ?', whereArgs: [id]);
      await db.setVersion(28);
      await db.close();
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      expect(await db.getVersion(), 39);
      expect(await db.query('library_canonical_claims'), hasLength(1));
      expect(await db.query('library_query_views'), viewsBefore);
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
