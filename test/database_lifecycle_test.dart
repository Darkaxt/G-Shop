import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi/src/database_factory_ffi_io.dart';
import 'package:sqflite_common_ffi/src/sqflite_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('headless database has an independent lifetime from the UI handle',
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
    try {
      background = await DatabaseService.openBackgroundDatabase();
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
      // UI teardown must not close the headless native handle mid-transaction.
      await ui.close();
      release.complete();
      await pass;
      expect((await background.query('games')).single['filename'],
          'background.gba');
    } finally {
      await background?.close();
      await ui.close();
      DatabaseService.resetForTesting();
      databaseFactory = original;
      await root.delete(recursive: true);
    }
  });
}
