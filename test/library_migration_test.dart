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
}
