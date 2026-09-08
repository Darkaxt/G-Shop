import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/game_metadata_info.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/library_store.dart';

/// Shared by the host FFI and actual Android SQLite tests. Only the caller's
/// test-private temporary database is changed; the normal app DB is not opened.
Future<void> verifyLibraryMigration({int previousVersion = 13}) async {
  if (previousVersion != 13 && previousVersion != 14) {
    throw ArgumentError.value(previousVersion, 'previousVersion');
  }
  final previousPath = await databaseFactory.getDatabasesPath();
  final temporary = await Directory.systemTemp.createTemp('rshop-migration-');
  Database? opened;
  try {
    await databaseFactory.setDatabasesPath(temporary.path);
    DatabaseService.resetForTesting();
    final service = DatabaseService();
    opened = await service.database;
    expect(p.isWithin(temporary.path, opened.path), isTrue);
    await service.saveGames('psx', [
      const GameItem(
          filename: 'Old.chd',
          displayName: 'Old',
          url: 'https://example.invalid/Old.chd')
    ]);
    await service.saveGameMetadata('psx', [
      const GameMetadataInfo(
          filename: 'Old.chd', systemSlug: 'psx', rating: 99, lastUpdated: 1)
    ]);
    if (previousVersion == 14) {
      await LibraryStore(Future.value(opened)).putGame(GameIdentity(
          id: 'existing-v14', platformId: 'psx', title: 'Pre-existing identity'));
    }
    // Recreate the selected legacy footprint in this synthetic DB, then use
    // the production onUpgrade entry point rather than invoking its helpers.
    for (final table in [
      if (previousVersion == 13) ...[
        'library_metadata',
        'library_artifacts',
        'library_editions',
        'library_game_identities',
      ],
      'drive_catalogue_pages',
      'drive_catalogue_work',
      'drive_catalogue_entries',
      'drive_catalogue_state',
    ]) {
      await opened.execute('DROP TABLE $table');
    }
    // Remove the v15 cache extension too, retaining the original row IDs.
    await opened.execute('DROP INDEX idx_games_system_filename');
    await opened.execute('DROP INDEX idx_games_system_artifact');
    await opened.execute('ALTER TABLE games RENAME TO games_v15_fixture');
    await opened.execute('''CREATE TABLE games (
      id INTEGER PRIMARY KEY AUTOINCREMENT, systemSlug TEXT NOT NULL,
      filename TEXT NOT NULL, displayName TEXT NOT NULL, url TEXT NOT NULL,
      region TEXT, cover_url TEXT, provider_config TEXT, thumb_hash TEXT,
      has_thumbnail INTEGER NOT NULL DEFAULT 0,
      is_folder INTEGER NOT NULL DEFAULT 0, alternative_sources TEXT)''');
    await opened.execute('INSERT INTO games SELECT id, systemSlug, filename, displayName, url, region, cover_url, provider_config, thumb_hash, has_thumbnail, is_folder, alternative_sources FROM games_v15_fixture');
    await opened.execute('DROP TABLE games_v15_fixture');
    await opened.execute('CREATE UNIQUE INDEX idx_games_system_filename ON games(systemSlug, filename)');
    await opened.setVersion(previousVersion);
    await opened.close();
    DatabaseService.resetForTesting();

    opened = await DatabaseService().database;
    expect(await opened.getVersion(), 15);
    expect((await opened.query('games')).single['url'],
        'https://example.invalid/Old.chd');
    expect((await opened.query('game_metadata')).single['rating'], 99);
    expect(await opened.query('library_metadata'), isEmpty);
    expect(await opened.query('drive_catalogue_state'), isEmpty);
    final store = LibraryStore(Future.value(opened));
    if (previousVersion == 14) {
      expect((await store.game('existing-v14'))!.title, 'Pre-existing identity');
    }
    await store.putGame(
        GameIdentity(id: 'smoke-game', platformId: 'psx', title: 'Synthetic'));
    await store.putEdition(EditionIdentity(
        id: 'smoke-edition',
        gameId: 'smoke-game',
        tags: {'T-Eng', 'Uncensor'}));
    await opened.close();
    DatabaseService.resetForTesting();
    opened = await DatabaseService().database;
    expect(await opened.getVersion(), 15);
    expect(await opened.query('games'), hasLength(1));
    expect(await opened.query('library_metadata'), isEmpty);
    final reopened = LibraryStore(Future.value(opened));
    expect((await reopened.game('smoke-game'))!.title, 'Synthetic');
    expect(
        (await reopened.edition('smoke-edition'))!.tags, {'T-Eng', 'Uncensor'});
  } finally {
    if (opened?.isOpen == true) await opened!.close();
    DatabaseService.resetForTesting();
    await databaseFactory.setDatabasesPath(previousPath);
    if (!p.isWithin(Directory.systemTemp.path, temporary.path) ||
        !p.basename(temporary.path).startsWith('rshop-migration-')) {
      throw StateError('Unexpected test cleanup path');
    }
    await temporary.delete(recursive: true);
  }
}
