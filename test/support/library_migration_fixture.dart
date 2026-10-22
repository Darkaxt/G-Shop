import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:g_shop/models/game_item.dart';
import 'package:g_shop/models/game_metadata_info.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/services/database_service.dart';
import 'package:g_shop/services/library_store.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';

/// Shared by the host FFI and actual Android SQLite tests. Only the caller's
/// test-private temporary database is changed; the normal app DB is not opened.
Future<void> verifyLibraryMigration({int previousVersion = 13}) async {
  if (previousVersion < 13 || previousVersion > 24) {
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
    if (previousVersion >= 14) {
      await LibraryStore(Future.value(opened)).putGame(GameIdentity(
          id: 'existing-v14',
          platformId: 'psx',
          title: 'Pre-existing identity'));
      await LibraryStore(Future.value(opened)).putEdition(EditionIdentity(
          id: 'existing-edition', gameId: 'existing-v14', tags: {'unknown'}));
    }
    if (previousVersion >= 15) {
      await service.saveGames('psx', [
        GameItem(
            filename: 'Same.chd',
            displayName: 'Exact prior cache',
            url: 'drive-artifact:fixture',
            remoteArtifact: RemoteArtifact(
                id: RemoteArtifactId(
                    providerId: 'drive',
                    sourceId: 'source',
                    accountId: 'account',
                    providerFileId: 'file'),
                displayPath: 'Same.chd',
                displayName: 'Same.chd'))
      ]);
    }
    // Recreate the selected legacy footprint in this synthetic DB, then use
    // the production onUpgrade entry point rather than invoking its helpers.
    for (final table in [
      'migration_byte_observations',
      'library_canonical_claims',
      'metadata_artwork_items',
      'metadata_artwork_cache',
      if (previousVersion < 24) 'library_canonical_groups',
      if (previousVersion < 23) 'metadata_provider_limits',
      if (previousVersion < 21) 'transfer_replacements',
      if (previousVersion < 19) 'owned_removals',
      if (previousVersion < 18) ...[
        'metadata_refresh_items',
        'metadata_refresh_jobs',
        'metadata_provider_backoff',
      ],
      if (previousVersion == 13) ...[
        'library_metadata',
        'library_artifacts',
        'library_editions',
        'library_game_identities',
      ],
      if (previousVersion < 15) ...[
        'drive_catalogue_pages',
        'drive_catalogue_work',
        'drive_catalogue_entries',
        'drive_catalogue_state',
      ],
      if (previousVersion < 16) ...[
        'transfer_records',
        'installed_artifacts',
        'transfer_target_owners',
      ],
    ]) {
      await opened.execute('DROP TABLE IF EXISTS $table');
    }
    if (previousVersion < 17) {
      await opened.execute('DROP INDEX IF EXISTS idx_transfer_artifact');
    }
    if (previousVersion >= 18) {
      // This synthetic downgrade removes the column introduced in v18. Its
      // newer saved-history index must leave with it; a real legacy DB has neither.
      await opened.execute('DROP INDEX IF EXISTS idx_metadata_saved_jobs');
      await opened
          .execute('ALTER TABLE metadata_refresh_jobs DROP COLUMN is_artwork');
    }
    if (previousVersion >= 23) {
      await opened.execute(
          'ALTER TABLE metadata_provider_limits DROP COLUMN remaining_requests');
    }
    if (previousVersion >= 16 && previousVersion < 22) {
      await opened.execute('DROP INDEX IF EXISTS idx_transfer_bundle');
      await opened
          .execute('ALTER TABLE transfer_records DROP COLUMN bundle_owner');
    }
    // Remove the v15 cache extension too, retaining the original row IDs.
    if (previousVersion < 15) {
      await opened.execute('DROP INDEX idx_games_system_filename');
      await opened.execute('DROP INDEX idx_games_system_artifact');
      await opened.execute('ALTER TABLE games RENAME TO games_v15_fixture');
      await opened.execute('''CREATE TABLE games (
      id INTEGER PRIMARY KEY AUTOINCREMENT, systemSlug TEXT NOT NULL,
      filename TEXT NOT NULL, displayName TEXT NOT NULL, url TEXT NOT NULL,
      region TEXT, cover_url TEXT, provider_config TEXT, thumb_hash TEXT,
      has_thumbnail INTEGER NOT NULL DEFAULT 0,
      is_folder INTEGER NOT NULL DEFAULT 0, alternative_sources TEXT)''');
      await opened.execute(
          'INSERT INTO games SELECT id, systemSlug, filename, displayName, url, region, cover_url, provider_config, thumb_hash, has_thumbnail, is_folder, alternative_sources FROM games_v15_fixture');
      await opened.execute('DROP TABLE games_v15_fixture');
      await opened.execute(
          'CREATE UNIQUE INDEX idx_games_system_filename ON games(systemSlug, filename)');
    }
    await opened.setVersion(previousVersion);
    await opened.close();
    DatabaseService.resetForTesting();

    opened = await DatabaseService().database;
    expect(await opened.getVersion(), 43);
    expect(await opened.query('metadata_provider_limits'), isEmpty);
    expect(await opened.query('transfer_replacements'), isEmpty);
    expect(await opened.query('owned_removals'), isEmpty);
    expect(await opened.query('metadata_refresh_jobs'), isEmpty);
    expect(await opened.query('metadata_refresh_items'), isEmpty);
    expect(
        (await opened
                .query('games', where: 'filename=?', whereArgs: ['Old.chd']))
            .single['url'],
        'https://example.invalid/Old.chd');
    expect((await opened.query('game_metadata')).single['rating'], 99);
    expect(await opened.query('library_metadata'), isEmpty);
    expect(await opened.query('drive_catalogue_state'), isEmpty);
    final store = LibraryStore(Future.value(opened));
    if (previousVersion >= 14) {
      expect(
          (await store.game('existing-v14'))!.title, 'Pre-existing identity');
      expect(
          (await store.canonicalEditions('existing-edition'))
              .editions
              .single
              .id,
          'existing-edition');
    }
    expect(await opened.query('transfer_records'), isEmpty);
    expect(await opened.query('installed_artifacts'), isEmpty);
    expect(await opened.query('transfer_target_owners'), isEmpty);
    expect(
        await opened.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_transfer_artifact'"),
        hasLength(1));
    if (previousVersion >= 15) {
      final priorExact =
          (await opened.query('games', where: 'artifact_key IS NOT NULL'))
              .single;
      expect(priorExact['displayName'], 'Exact prior cache');
      expect(priorExact['artifact_key'], '["drive","source","account","file"]');
    }
    await store.putGame(
        GameIdentity(id: 'smoke-game', platformId: 'psx', title: 'Synthetic'));
    await store.putEdition(EditionIdentity(
        id: 'smoke-edition',
        gameId: 'smoke-game',
        tags: {'T-Eng', 'Uncensor'}));
    final refresh = await MetadataRefreshJobs(Future.value(opened)).create(
        providerId: 'screenscraper',
        collectionGeneration: 'fixture-generation',
        editionIds: ['smoke-edition']);
    // Durable state left by an exited process; no live runner exists here.
    await opened.update('metadata_refresh_jobs', {'state': 'running'},
        where: 'id = ?', whereArgs: [refresh.id]);
    await opened.insert('metadata_provider_limits', {
      'provider_id': 'screenscraper',
      'requests_per_minute': 2,
      'max_threads': 1,
      'next_allowed_at': 777,
      'quota_exhausted': 1,
    });
    await opened.close();
    DatabaseService.resetForTesting();
    opened = await DatabaseService().database;
    expect(await opened.getVersion(), 43);
    final recovered =
        await MetadataRefreshJobs(Future.value(opened)).report(refresh.id);
    expect(recovered.state, 'paused');
    expect(recovered.counts, {'pending': 1});
    expect(recovered.generation, refresh.generation);
    final quota = (await opened.query('metadata_provider_limits')).single;
    expect(quota['requests_per_minute'], 2);
    expect(quota['max_threads'], 1);
    expect(quota['next_allowed_at'], 777);
    expect(quota['quota_exhausted'], 1);
    expect(
        await opened.query('games'), hasLength(previousVersion >= 15 ? 2 : 1));
    expect(await opened.query('transfer_records'), isEmpty);
    expect(await opened.query('library_metadata'), isEmpty);
    final reopened = LibraryStore(Future.value(opened));
    expect((await reopened.game('smoke-game'))!.title, 'Synthetic');
    expect(
        (await reopened.edition('smoke-edition'))!.tags, {'T-Eng', 'Uncensor'});
    expect(
        (await reopened.canonicalEditions('smoke-edition')).editions.single.id,
        'smoke-edition');
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
