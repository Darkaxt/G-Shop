import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/services/database_service.dart';
import 'package:g_shop/services/drive/drive_catalogue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('v36 upgrade indexes pending traversal without altering checkpoints',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final prior = await databaseFactory.getDatabasesPath();
    final root =
        await Directory.systemTemp.createTemp('rshop-drive-work-migration-');
    Database? db;
    try {
      await databaseFactory.setDatabasesPath(root.path);
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      await db.execute('DROP INDEX drive_catalogue_pending_work');
      await db.insert('drive_catalogue_state', {
        'scope': 'scope',
        'active': 1,
        'pending': 2,
        'next_generation': 3,
      });
      for (final generation in [1, 2]) {
        await db.insert('drive_catalogue_entries', {
          'scope': 'scope',
          'generation': generation,
          'file_id': 'folder',
          'parent_id': 'root',
          'display_path': 'folder',
          'is_folder': 1,
          'record_json': '{}',
        });
      }
      await db.insert('drive_catalogue_work', {
        'scope': 'scope',
        'generation': 2,
        'file_id': 'folder',
        'page_token': 'resume-page',
        'done': 0,
      });
      await db.insert('drive_catalogue_pages', {
        'scope': 'scope',
        'generation': 2,
        'file_id': 'folder',
        'page_token': 'previous-page',
      });
      final preserved = <String, List<Map<String, Object?>>>{};
      for (final table in [
        'drive_catalogue_state',
        'drive_catalogue_entries',
        'drive_catalogue_work',
        'drive_catalogue_pages',
        'games',
        'library_editions',
      ]) {
        preserved[table] = await db.query(table);
      }
      await db.setVersion(36);
      await db.close();
      DatabaseService.resetForTesting();
      db = await DatabaseService().database;
      expect(await db.getVersion(), 43);
      expect(
          await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='index' AND name='drive_catalogue_pending_work'"),
          hasLength(1));
      for (final entry in preserved.entries) {
        expect(await db.query(entry.key), entry.value, reason: entry.key);
      }
      await DriveCatalogueSchema.install(db); // Additive and idempotent.
      for (final entry in preserved.entries) {
        expect(await db.query(entry.key), entry.value, reason: entry.key);
      }
    } finally {
      if (db?.isOpen == true) await db!.close();
      DatabaseService.resetForTesting();
      await databaseFactory.setDatabasesPath(prior);
      expect(root.parent.path, Directory.systemTemp.absolute.path);
      expect(root.path.split(Platform.pathSeparator).last,
          startsWith('rshop-drive-work-migration-'));
      await root.delete(recursive: true);
    }
  });
}
