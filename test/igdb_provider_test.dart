import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/igdb_provider_fixture.dart';

void main() {
  sqfliteFfiInit();
  defineIgdbProviderChecks(databaseFactoryFfi);
}
