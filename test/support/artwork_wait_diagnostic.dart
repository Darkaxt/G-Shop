import 'dart:collection';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';

import 'package:sqflite_common_ffi/src/database_factory_ffi_io.dart';
import 'package:sqflite_common_ffi/src/sqflite_import.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Opt-in, synthetic-fixture-only observation of the same FFI isolate boundary.
// No retries, sleeps, cancellations, new storage protocol or production hooks.
// Keep only 64 sanitized operation summaries, never SQL arguments/row bodies.
final _recent = ListQueue<Map<String, Object?>>();
final _pending = <int, String>{};
var _sequence = 0;
int? _artworkWorkId;

// Terminal summary. During a wait, the enabled local VM service can inspect the
// bounded static fields read-only without pausing or forcing a collection.
String artworkWaitSnapshot() => jsonEncode({
      'operations': _sequence,
      'artworkWorkId': _artworkWorkId,
      'pending': _pending.map((id, method) => MapEntry('$id', method)),
      'recent': _recent.toList(growable: false),
    });

// A read-only loopback observer works with the original VM-service-disabled
// tester configuration. Requests do not pause execution, collect garbage,
// contact a provider, alter the database or decide completion/cancellation.
Future<HttpServer> startArtworkWaitObserver() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.method != 'GET' || request.uri.path != '/') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
    } else {
      request.response.headers.contentType = ContentType.json;
      request.response.write(artworkWaitSnapshot());
    }
    await request.response.close();
  });
  return server;
}

class TracedArtworkCache extends MetadataArtworkCache {
  TracedArtworkCache(super.database, super.root);

  @override
  Future<({MetadataLookupResult result, MetadataArtworkBlob? blob})> download(
      MetadataMedia media,
      MetadataArtworkProvider provider,
      int workId,
      CancelToken cancel) async {
    _artworkWorkId = workId;
    try {
      return await super.download(media, provider, workId, cancel);
    } finally {
      _artworkWorkId = null;
    }
  }
}

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
