import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/game_metadata_info.dart';
import 'package:retro_eshop/services/database_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test(
      'real v13 upgrade and reopen preserve source rows and anonymous legacy rating',
      () async {
    final previousPath = await databaseFactory.getDatabasesPath();
    final temporary = await Directory.systemTemp.createTemp('rshop-migration-');
    Database? opened;
    try {
      await databaseFactory.setDatabasesPath(temporary.path);
      DatabaseService.resetForTesting();
      final service = DatabaseService();
      opened = await service.database;
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
      // Restore the exact unchanged legacy schema footprint: all new tables are
      // additive. This is a private fixture database, never an app/user database.
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
      await opened.close();
      DatabaseService.resetForTesting();
      opened = await DatabaseService().database;
      expect(await opened.getVersion(), 14);
      expect(await opened.query('games'), hasLength(1));
      expect(await opened.query('library_metadata'), isEmpty);
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
  });
}
