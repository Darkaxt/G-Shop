import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/library_query_resource_fixture.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('bounded collection query uses the shared native verification fixture',
      () async {
    final result =
        await verifyLibraryQueryResource(databaseFactoryFfi, count: 3000);
    expect(result['ranked_games'], 3000);
  }, timeout: Timeout.none);

  test('real indexed collection ranking stays paged for 30000 cached games',
      () async {
    await verifyLibraryQueryResource(databaseFactoryFfi);
  }, timeout: Timeout.none);
}
