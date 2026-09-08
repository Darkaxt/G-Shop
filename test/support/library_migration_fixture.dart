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
Future<void> verifyLibraryV13Migration() async {
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
    // Remove only additive tables in this synthetic DB to recreate its v13
    // footprint, then exercise the production onUpgrade entry point.
    for (final table in [
      'library_metadata',
      'library_artifacts',
      'library_editions',
      'library_game_identities'
    ]) {
      await opened.execute('DROP TABLE $table');
    }
    await opened.setVersion(13);
    await opened.close();
    DatabaseService.resetForTesting();

    opened = await DatabaseService().database;
    expect(await opened.getVersion(), 14);
    expect((await opened.query('games')).single['url'],
        'https://example.invalid/Old.chd');
    expect((await opened.query('game_metadata')).single['rating'], 99);
    expect(await opened.query('library_metadata'), isEmpty);
    final store = LibraryStore(Future.value(opened));
    await store.putGame(
        GameIdentity(id: 'smoke-game', platformId: 'psx', title: 'Synthetic'));
    await store.putEdition(EditionIdentity(
        id: 'smoke-edition',
        gameId: 'smoke-game',
        tags: {'T-Eng', 'Uncensor'}));
    await opened.close();
    DatabaseService.resetForTesting();
    opened = await DatabaseService().database;
    expect(await opened.getVersion(), 14);
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
