import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/models/game_item.dart';
import 'package:g_shop/providers/metadata_providers.dart';
import 'package:g_shop/services/database_service.dart';
import 'package:g_shop/services/metadata/metadata_artwork_cache.dart';
import 'package:g_shop/services/metadata/metadata_credentials.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';
import 'metadata_controls_test.dart'
    show ControlsArtworkProvider, MemorySecrets;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'production v33 upgrade preserves facts/jobs and links completed metadata on resume',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final previousPath = await databaseFactory.getDatabasesPath();
    final root =
        await Directory.systemTemp.createTemp('rshop-artwork-link-migration-');
    Database? db;
    MetadataControlsController? controls;
    try {
      await databaseFactory.setDatabasesPath(root.path);
      DatabaseService.resetForTesting();
      final service = DatabaseService();
      db = await service.database;
      await service.saveGames('psx', [
        const GameItem(
            filename: 'Game.chd',
            displayName: 'Game',
            url: 'https://example.invalid/Game.chd')
      ]);
      final provider = ControlsArtworkProvider();
      var jobs = MetadataRefreshJobs(Future.value(db));
      final parent =
          await jobs.createFromCatalogue(providerId: 'screenscraper');
      expect((await jobs.run(parent.id, provider)).counts, {'matched': 1});
      await db.execute('DROP TABLE metadata_artwork_jobs');
      final retained = <String, List<Map<String, Object?>>>{};
      for (final table in [
        'games',
        'library_game_identities',
        'library_editions',
        'library_metadata',
        'metadata_refresh_jobs',
        'metadata_refresh_items'
      ]) {
        retained[table] = await db.query(table);
      }
      await db.setVersion(33);
      await db.close();
      DatabaseService.resetForTesting();
      db = await service.database;
      expect(await db.getVersion(), 43);
      for (final table in retained.keys) {
        expect(await db.query(table), retained[table]);
      }
      expect(await db.query('metadata_artwork_jobs'), isEmpty);
      controls = MetadataControlsController(
          database: Future.value(db),
          providers: {'screenscraper': provider},
          screenScraperCredentials:
              ScreenScraperCredentialStore(storage: MemorySecrets()),
          igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
          artworkCache: Future.value(MetadataArtworkCache(
              Future.value(db), Directory('${root.path}/artwork'))),
          catalogueChanged: () {});
      await controls.load();
      await controls.resume();
      expect(controls.state.report!.id, parent.id);
      expect(controls.state.artworkReport!.counts, {'matched': 1});
      expect(provider.calls, hasLength(1),
          reason: 'Upgrade does not repeat completed metadata');
      final child = controls.state.artworkReport!.id;
      await controls.close();
      controls.dispose();
      controls = null;
      await db.close();
      DatabaseService.resetForTesting();
      db = await service.database;
      jobs = MetadataRefreshJobs(Future.value(db));
      expect((await jobs.artworkForMetadata(parent.id))!.id, child);
      expect((await jobs.ensureArtworkForMetadata(parent.id)).id, child);
    } finally {
      if (controls != null) {
        await controls.close();
        controls.dispose();
      }
      if (db?.isOpen == true) await db!.close();
      DatabaseService.resetForTesting();
      await databaseFactory.setDatabasesPath(previousPath);
      expect(root.parent.path, Directory.systemTemp.absolute.path);
      expect(root.path.split(Platform.pathSeparator).last,
          startsWith('rshop-artwork-link-migration-'));
      await root.delete(recursive: true);
    }
  });
}
