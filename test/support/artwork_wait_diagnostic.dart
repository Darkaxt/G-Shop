import 'dart:collection';
import 'dart:convert';
import 'dart:developer';

import 'package:sqflite_common_ffi/src/database_factory_ffi_io.dart';
import 'package:sqflite_common_ffi/src/sqflite_import.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Opt-in, synthetic-fixture-only observation of the same FFI isolate boundary.
// No retries, sleeps, cancellations, new storage protocol or production hooks.
// Keep only 64 sanitized operation summaries, never SQL arguments/row bodies.
final _recent = ListQueue<Map<String, Object?>>();
final _pending = <int, String>{};
var _sequence = 0;

// Terminal summary. During a wait, the enabled local VM service can inspect the
// bounded static fields read-only without pausing or forcing a collection.
String artworkWaitSnapshot() => jsonEncode({
      'operations': _sequence,
      'pending': _pending.map((id, method) => MapEntry('$id', method)),
      'recent': _recent.toList(growable: false),
    });

Future<DatabaseFactory> tracedArtworkFactory() async {
  final service = await Service.getInfo();
  // ignore: avoid_print
  print('artwork diagnostic VM=${service.serverUri}');
  return buildDatabaseFactory(
      tag: 'artwork-wait-diagnostic',
      invokeMethod: (method, [arguments]) async {
        final id = ++_sequence;
        final sql = arguments is Map ? arguments['sql'] : null;
        final operation = sql is String
            ? '$method:${sql.trim().split(RegExp(r"\s+")).take(3).join(" ")}'
            : method;
        _pending[id] = operation;
        _recent.add({'id': id, 'operation': operation, 'state': 'pending'});
        if (_recent.length > 64) _recent.removeFirst();
        final current = _recent.last;
        try {
          return await ffiMethodCallhandleInIsolate(
              FfiMethodCall(method, arguments));
        } finally {
          current['state'] = 'returned';
          _pending.remove(id);
          if (id % 25000 == 0) {
            // ignore: avoid_print
            print(
                'artwork diagnostic operations=$id pending=${_pending.length}');
          }
        }
      });
}
