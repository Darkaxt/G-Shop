import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/library_verified_match_grouping_fixture.dart';

void main() {
  sqfliteFfiInit();
  defineVerifiedMatchGroupingChecks(databaseFactoryFfi);
}
