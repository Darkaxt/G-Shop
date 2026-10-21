import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/models/game_item.dart';
import 'package:g_shop/services/database_service.dart';
import 'package:g_shop/services/library_query.dart';
import 'package:g_shop/services/library_store.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';

void main() => defineQueryInvalidationMigrationCheck();

/// The same production upgrade/reopen contract runs on Android's SQLite too.
/// Only a synthetic temporary database is opened; user bootstrap is excluded.
void defineQueryInvalidationMigrationCheck({
  DatabaseFactory? factory,
  void Function()? verified,
}) {
  setUpAll(() {
    if (factory == null) sqfliteFfiInit();
    databaseFactory = factory ?? databaseFactoryFfi;
  });
  test('v32 migration replaces faulty triggers without rewriting saved facts',
      () async {
    final previousPath = await databaseFactory.getDatabasesPath();
    final root =
        await Directory.systemTemp.createTemp('rshop-dirty-migration-');
    Database? db;
    const original = GameItem(
        filename: 'Fixture.chd',
        displayName: 'Original',
        url: 'https://example.invalid/Fixture.chd');
    try {
      await databaseFactory.setDatabasesPath(root.path);
      DatabaseService.resetForTesting();
      final service = DatabaseService();
      db = await service.database;
      await service.saveGames('psx', [original]);
      final edition = (await db.transaction(
              (txn) => LibraryStore.catalogueEditions(txn).toList()))
          .single;
      await LibraryQuery(Future.value(db))
          .replaceViewMembers('shelf:preserved', [edition]);
      await MetadataRefreshJobs(Future.value(db)).create(
          providerId: 'igdb',
          collectionGeneration: 'synthetic-generation',
          editionIds: [edition]);
      await LibraryQuery(Future.value(db)).page(filter: LibraryQueryFilter());
      // Actual v32 UPDATE body: overlapping OLD/NEW bindings insert the same
      // dirty keys using OR IGNORE, overridden by the normal cache UPSERT.
      await db.execute('DROP TRIGGER query_cache_update');
      await db
          .execute('''CREATE TRIGGER query_cache_update AFTER UPDATE ON games
        BEGIN
          INSERT OR IGNORE INTO library_query_cache_dirty VALUES (OLD.id);
          INSERT OR IGNORE INTO library_query_dirty SELECT edition_id
            FROM library_query_editions WHERE cache_row_id = OLD.id;
          INSERT OR IGNORE INTO library_query_dirty SELECT edition_id
            FROM library_query_editions WHERE legacy_row_id = OLD.id;
          INSERT OR IGNORE INTO library_query_dirty SELECT edition_id
            FROM library_query_editions WHERE platform_id = OLD.systemSlug
              AND catalogue_key = OLD.artifact_key;
          INSERT OR IGNORE INTO library_query_cache_dirty VALUES (NEW.id);
          INSERT OR IGNORE INTO library_query_dirty SELECT edition_id
            FROM library_query_editions WHERE cache_row_id = NEW.id;
          INSERT OR IGNORE INTO library_query_dirty SELECT edition_id
            FROM library_query_editions WHERE legacy_row_id = NEW.id;
          INSERT OR IGNORE INTO library_query_dirty SELECT edition_id
            FROM library_query_editions WHERE platform_id = NEW.systemSlug
              AND catalogue_key = NEW.artifact_key;
        END''');
      // Identical cache UPSERTs intentionally perform no UPDATE now. Exercise
      // the broken legacy trigger with an actual changed row, not a no-op.
      await service.saveGames('psx', [original]);
      await expectLater(
          service.saveGames('psx', [
            const GameItem(
                filename: 'Fixture.chd',
                displayName: 'Changed',
                url: 'https://example.invalid/Fixture.chd')
          ]),
          throwsA(isA<DatabaseException>()));
      await db.insert('library_query_dirty', {'edition_id': edition});
      final preserved = <String, List<Map<String, Object?>>>{};
      for (final table in [
        'games',
        'library_game_identities',
        'library_editions',
        'library_metadata',
        'metadata_refresh_jobs',
        'metadata_refresh_items',
        'library_query_views',
        'library_query_dirty',
        'library_query_cache_dirty',
      ]) {
        preserved[table] = await db.query(table);
      }
      await db.setVersion(32);
      await db.close();
      DatabaseService.resetForTesting();
      for (var reopen = 0; reopen < 2; reopen++) {
        db = await DatabaseService().database;
        expect(await db.getVersion(), 39);
        for (final entry in preserved.entries) {
          expect(await db.query(entry.key), entry.value, reason: entry.key);
        }
        await db.close();
        DatabaseService.resetForTesting();
      }
      final refreshed = DatabaseService();
      db = await refreshed.database;
      for (var i = 0; i < 2; i++) {
        await refreshed.saveGames('psx', [original]);
      }
      final page = await LibraryQuery(Future.value(db))
          .page(filter: LibraryQueryFilter());
      expect(page.items.single.editionId, edition);
      expect(await db.query('library_query_dirty'), isEmpty);
      expect(await db.query('library_query_cache_dirty'), isEmpty);
      verified?.call();
    } finally {
      if (db?.isOpen == true) await db!.close();
      DatabaseService.resetForTesting();
      await databaseFactory.setDatabasesPath(previousPath);
      if (!p.isWithin(Directory.systemTemp.path, root.path) ||
          !p.basename(root.path).startsWith('rshop-dirty-migration-')) {
        throw StateError('Unexpected migration fixture cleanup root');
      }
      await root.delete(recursive: true);
    }
  });
}
