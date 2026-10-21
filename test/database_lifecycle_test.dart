import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/services/database_service.dart';
import 'package:g_shop/services/metadata/shared_metadata_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi/src/database_factory_ffi_io.dart';
import 'package:sqflite_common_ffi/src/sqflite_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('private WAL separates readers, headless lifetime and shared journaling',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final original = databaseFactory;
    final root = await Directory.systemTemp.createTemp('rshop-db-lifetime-');
    databaseFactory = buildDatabaseFactory(
        tag: 'headless-lifetime',
        invokeMethod: (method, [arguments]) async {
          if (method == 'getDatabasesPath') return root.path;
          return ffiMethodCallHandleNoIsolate(FfiMethodCall(method, arguments));
        });
    DatabaseService.resetForTesting();
    final ui = await DatabaseService().database;
    Database? background;
    SharedMetadataStore? shared;
    try {
      expect((await ui.rawQuery('PRAGMA journal_mode')).single.values.single,
          'wal');
      shared = await SharedMetadataStore.open(Directory('${root.path}/shared'),
          factory: databaseFactory, verifyAccess: () async {});
      expect(
          (await shared.cloudIndex.rawQuery('PRAGMA journal_mode'))
              .single
              .values
              .single,
          'delete',
          reason:
              'Private reader configuration must not change shared storage');
      background = await DatabaseService.openBackgroundDatabase();
      expect(
          (await background.rawQuery('PRAGMA journal_mode'))
              .single
              .values
              .single,
          'wal');
      expect(identical(ui, background), isFalse,
          reason:
              'A recreated UI must not roll back or close a live save pass');
      final entered = Completer<void>();
      final release = Completer<void>();
      final pass = background.transaction((txn) async {
        await txn.insert('games', {
          'systemSlug': 'gba',
          'filename': 'background.gba',
          'displayName': 'Background',
          'url': ''
        });
        entered.complete();
        await release.future;
      });
      await entered.future;
      expect(await ui.query('games'), isEmpty,
          reason:
              'An independent reader sees only committed data during a writer');
      // UI teardown must not close the headless native handle mid-transaction.
      await ui.close();
      release.complete();
      await pass;
      expect((await background.query('games')).single['filename'],
          'background.gba');
    } finally {
      await shared?.close();
      await background?.close();
      await ui.close();
      DatabaseService.resetForTesting();
      databaseFactory = original;
      await root.delete(recursive: true);
    }
  });
}
