import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/library_migration_fixture.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test(
      'real v13 upgrade and reopen preserve source rows and anonymous legacy rating',
      () => verifyLibraryMigration());
  test('real v14 upgrade preserves existing identity and legacy cache rows',
      () => verifyLibraryMigration(previousVersion: 14));
  test('real v15 upgrade adds journal without losing exact cached artifacts',
      () => verifyLibraryMigration(previousVersion: 15));
  test('real v16 upgrade adds artifact lookup index and reopens intact',
      () => verifyLibraryMigration(previousVersion: 16));
  test('real v17 upgrade adds metadata jobs without changing cached games',
      () => verifyLibraryMigration(previousVersion: 17));
}
