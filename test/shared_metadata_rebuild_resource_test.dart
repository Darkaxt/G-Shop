import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/src/database_factory_ffi_io.dart';
import 'package:sqflite_common_ffi/src/sqflite_import.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/shared_metadata_rebuild_resource_fixture.dart';

class _NoNetwork extends HttpOverrides {
  int requests = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    requests++;
    throw StateError(
        'Resource rebuild cannot contact a provider or ROM source');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  for (final count in [129, 30000]) {
    test(
        '$count durable editions rebuild the normal private query without network',
        () async {
      var maxRecordRows = 0,
          maxIdentityRows = 0,
          maxCatalogueRows = 0,
          operations = 0;
      final factory = buildDatabaseFactory(
          tag: 'shared-rebuild-$count',
          invokeMethod: (method, [arguments]) async {
            // The Thor's native SQLite has no JSON1 extension. The same real
            // rebuild must work without optional SQL JSON functions on host.
            if (arguments is Map &&
                (arguments['sql'] as String? ?? '').contains('json_extract(')) {
              throw UnsupportedError('Native SQLite has no json_extract');
            }
            // Use the same real SQLite dispatcher as databaseFactoryFfiNoIsolate.
            // Observation never manufactures responses or bypasses transactions;
            // native plugin/isolate transport proof belongs to its own entrypoint.
            final result = await ffiMethodCallHandleNoIsolate(
                FfiMethodCall(method, arguments));
            operations++;
            if (method == 'query' && arguments is Map && result is Map) {
              final sql = arguments['sql'] as String? ?? '';
              final rows = result['rows'];
              if (rows is List) {
                if (sql.contains('FROM records') &&
                    rows.length > maxRecordRows) {
                  maxRecordRows = rows.length;
                }
                if (sql.contains('FROM library_game_identities') &&
                    rows.length > maxIdentityRows) {
                  maxIdentityRows = rows.length;
                }
                if (sql.contains('FROM games') &&
                    rows.length > maxCatalogueRows) {
                  maxCatalogueRows = rows.length;
                }
              }
            }
            if (operations % 25000 == 0) {
              // ignore: avoid_print
              print(
                  'shared rebuild operations=$operations rss=${ProcessInfo.currentRss}');
            }
            return result;
          });
      final noNetwork = _NoNetwork();
      final result = await HttpOverrides.runZoned(
          () => verifySharedMetadataRebuildResource(factory, count: count),
          createHttpClient: noNetwork.createHttpClient);
      expect(result['restored'], count);
      expect(noNetwork.requests, 0);
      expect(maxRecordRows, 128);
      expect(maxIdentityRows, lessThanOrEqualTo(128));
      expect(maxCatalogueRows, lessThanOrEqualTo(128));
      // ignore: avoid_print
      print(
          'shared rebuild bounds: records=$maxRecordRows identities=$maxIdentityRows '
          'network=${noNetwork.requests} operations=$operations');
    }, timeout: Timeout.none);
  }
}
