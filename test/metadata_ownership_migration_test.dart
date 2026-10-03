import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
      'production v25 upgrade retains current owner bindings and rejects stale evidence',
      () async {
    final previousPath = await databaseFactory.getDatabasesPath();
    final temporary =
        await Directory.systemTemp.createTemp('rshop-owner-migration-');
    Database? db;
    try {
      await databaseFactory.setDatabasesPath(temporary.path);
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      final store = LibraryStore(Future.value(db));
      final media = MetadataMedia(
          type: 'box-2D',
          region: 'us',
          providerReference: ScreenScraperMediaReference(
              providerGameId: '42',
              providerPlatformId: 4,
              mediaType: 'box-2D',
              region: 'us'));
      final oldKeys = <String, String>{};
      for (var i = 0; i < 130; i++) {
        final id = 'edition-${i.toString().padLeft(3, '0')}';
        final game = GameIdentity(
            id: id,
            platformId: 'snes',
            title: 'Synthetic',
            providerIds: {'screenscraper': '42'},
            matchStatus: IdentityMatchStatus.manuallyMatched);
        final edition = EditionIdentity(id: id, gameId: id, tags: {'official'});
        await store.putGame(game);
        await store.putEdition(edition);
        await store.putMetadata(MetadataRecord(
            gameId: id,
            editionId: id,
            platformId: 'snes',
            providerId: 'screenscraper',
            providerGameId: '42',
            retrievedAt: DateTime.utc(2026),
            refreshGeneration: 1,
            matchMethod: 'verifiedProviderId',
            titles: const [MetadataText(text: 'Synthetic')],
            media: [media]));
        oldKeys[id] = LibraryStore.metadataIdentity({
          'game_json': jsonEncode(game.toJson()),
          'edition_json': jsonEncode(edition.toJson())
        });
      }
      final jobs = MetadataRefreshJobs(Future.value(db));
      final metadata = await jobs.create(
          providerId: 'screenscraper',
          collectionGeneration: 'old',
          editionIds: oldKeys.keys);
      final artwork = await jobs.createArtwork(
          providerId: 'screenscraper',
          collectionGeneration: 'old',
          editionIds: oldKeys.keys);
      // Reproduce v25 keys, not a migrated fixture that merely happens to reopen.
      for (final entry in oldKeys.entries) {
        for (final table in [
          'library_metadata',
          'metadata_refresh_items',
          'metadata_artwork_items'
        ]) {
          await db.update(table, {'identity_key': entry.value},
              where: 'edition_id = ?', whereArgs: [entry.key]);
        }
      }
      final staleGame = (await store.game('edition-008'))!;
      await store.putGame(
          GameIdentity.fromJson({...staleGame.toJson(), 'platformId': 'psx'}));
      final tables = [
        'library_metadata',
        'metadata_refresh_items',
        'metadata_artwork_items'
      ];
      final before = <List<Map<String, Object?>>>[];
      for (final table in tables) {
        before.add(await db.query(table, orderBy: 'edition_id'));
      }
      await db.update('metadata_refresh_jobs', {'state': 'running'},
          where: 'id = ?', whereArgs: [metadata.id]);
      await db.insert('metadata_provider_limits', {
        'provider_id': 'screenscraper',
        'requests_per_minute': 2,
        'max_threads': 1,
        'next_allowed_at': 777,
        'remaining_requests': 10,
        'quota_exhausted': 0
      });
      await db.setVersion(25);
      await db.close();
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      expect(await db.getVersion(), 28);
      final reopened = LibraryStore(Future.value(db));
      for (final id in oldKeys.keys) {
        final cached = await reopened.metadata(id, 'screenscraper');
        expect(cached != null, id != 'edition-008');
        if (cached != null) {
          expect(cached.refreshGeneration, 1);
          expect(cached.retrievedAt, DateTime.utc(2026));
        }
      }
      for (var table = 0; table < tables.length; table++) {
        final after = await db.query(tables[table], orderBy: 'edition_id');
        expect(after, hasLength(130));
        for (var i = 0; i < 130; i++) {
          final old = Map<String, Object?>.from(before[table][i]);
          final current = Map<String, Object?>.from(after[i]);
          if (i == 8) {
            expect(current['identity_key'], old['identity_key'],
                reason: 'stale bindings cannot be promoted');
          } else {
            expect(current['identity_key'], isNot(old['identity_key']));
          }
          old.remove('identity_key');
          current.remove('identity_key');
          expect(current, old,
              reason: 'migration changes only verified owner bindings');
        }
      }
      final recovered = MetadataRefreshJobs(Future.value(db));
      expect((await recovered.report(metadata.id)).state, 'paused');
      expect((await recovered.report(metadata.id)).counts, {'pending': 130});
      expect((await recovered.report(artwork.id)).counts, {'pending': 130});
      expect(
          (await db.query('metadata_provider_limits'))
              .single['remaining_requests'],
          10);
      final game = (await reopened.game('edition-000'))!;
      await reopened.putGame(GameIdentity.fromJson({
        ...game.toJson(),
        'providerIds': {...game.providerIds, 'igdb': '100'},
        'evidence': [
          IdentityEvidence(
              source: 'manual',
              kind: 'providerId',
              value: jsonEncode(['igdb', '100'])).toJson()
        ]
      }));
      expect(
          await reopened.metadata('edition-000', 'screenscraper'), isNotNull);
      // An additional reopen must not migrate the new keys twice.
      await db.close();
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      expect(
          await LibraryStore(Future.value(db))
              .metadata('edition-000', 'screenscraper'),
          isNotNull);
      expect(
          await LibraryStore(Future.value(db))
              .metadata('edition-008', 'screenscraper'),
          isNull);
    } finally {
      if (db?.isOpen == true) await db!.close();
      DatabaseService.resetForTesting();
      await databaseFactory.setDatabasesPath(previousPath);
      if (!p.isWithin(Directory.systemTemp.path, temporary.path) ||
          !p.basename(temporary.path).startsWith('rshop-owner-migration-')) {
        throw StateError('Unexpected migration fixture cleanup root');
      }
      await temporary.delete(recursive: true);
    }
  });
}
