import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/services/metadata/metadata_artwork_cache.dart';
import 'package:g_shop/services/metadata/shared_metadata_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi/src/database_factory_ffi_io.dart';
import 'package:sqflite_common_ffi/src/sqflite_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cloud packets preserve ordered media rows with bounded indexed reads',
      () async {
    sqfliteFfiInit();
    var observe = false;
    final artworkReads = <List<Object?>>[];
    final responseReads = <List<Object?>>[];
    final factory = buildDatabaseFactory(
        tag: 'bounded-cloud-packets',
        invokeMethod: (method, [arguments]) async {
          if (observe && method == 'query' && arguments is Map) {
            final sql = arguments['sql'] as String? ?? '';
            final binds = List<Object?>.from(arguments['arguments'] as List);
            if (sql.contains('FROM metadata_artwork_cache')) {
              artworkReads.add(binds);
            }
            if (sql.contains('FROM artwork_responses')) {
              responseReads.add(binds);
            }
          }
          return ffiMethodCallHandleNoIsolate(FfiMethodCall(method, arguments));
        });
    final root = await Directory.systemTemp.createTemp('gshop-cloud-packets-');
    final shared = await SharedMetadataStore.open(root, factory: factory);
    addTearDown(() async {
      await shared.close();
      await root.delete(recursive: true);
    });
    final db = shared.cloudIndex;
    final media = List.generate(
        257,
        (i) => MetadataMedia(
            type: 'box-front', url: 'https://example.com/box-$i.png'));
    // Reverse insertion makes an unordered IN-query result observably different
    // from the existing media-key iteration order. Some keys have no local body.
    for (var i = media.length - 1; i >= 0; i--) {
      final key = MetadataArtworkCache.key(media[i]);
      if (i % 7 != 0) {
        await db.insert('metadata_artwork_cache', {
          'media_key': key,
          'filename': '$key.png',
          'byte_length': i + 1,
          'retrieved_at': '2026-10-24T00:00:00.000Z',
        });
      }
      for (final (provider, generation) in [
        ('screenscraper', 3),
        ('screenscraper', 2),
        ('launchbox', 3),
      ]) {
        await db.insert('artwork_responses', {
          'provider_id': provider,
          'generation': generation,
          'media_key': key,
          'filename': '$provider-$generation-$key.png',
          'byte_length': i + 1,
          'retrieved_at': '2026-10-24T00:00:00.000Z',
        });
      }
    }
    for (var i = 0; i < 130; i++) {
      final game = GameIdentity(
          id: 'game-$i', platformId: i == 1 ? 'gba' : 'nes', title: 'Game $i');
      final edition = EditionIdentity(id: 'edition-$i', gameId: game.id);
      final record = MetadataRecord(
          gameId: game.id,
          editionId: edition.id,
          platformId: game.platformId!,
          providerId: 'screenscraper',
          providerGameId: '$i',
          retrievedAt: DateTime.utc(2026, 10, 24),
          refreshGeneration: 3,
          matchMethod: 'platformAndTitle',
          titles: [MetadataText(text: 'Game $i')],
          media: i == 0
              ? [...media, media.first]
              : i == 1
                  ? media.take(17).toList()
                  : []);
      await db.insert('records', {
        'edition_id': edition.id,
        'provider_id': record.providerId,
        'identity_key': 'identity-$i',
        'generation': 3,
        'platform_id': game.platformId,
        'game_json': jsonEncode(game.toJson()),
        'edition_json': jsonEncode(edition.toJson()),
        'artifacts_json': '[]',
        'record_json': jsonEncode(record.toJson()),
      });
    }
    final expected = await _legacyPackets(db);
    observe = true;
    final actual = await shared.cloudPackets().toList();
    observe = false;
    expect(jsonEncode(actual), jsonEncode(expected),
        reason: 'Export bytes, record pages, platform groups, missing bodies, '
            'duplicate references and provider generations must be unchanged');
    expect(artworkReads.length, 4);
    expect(responseReads.length, 4);
    expect(artworkReads.map((v) => v.length), [128, 128, 1, 17]);
    expect(responseReads.map((v) => v.length), [130, 130, 3, 19]);
    artworkReads.clear();
    responseReads.clear();
    final scopedExpected = await _legacyPackets(db, editionId: 'edition-0');
    observe = true;
    final scoped = await shared.cloudPackets(editionId: 'edition-0').toList();
    observe = false;
    expect(jsonEncode(scoped), jsonEncode(scopedExpected));
    expect(artworkReads.length, 3);
    expect(responseReads.length, 3);
  });
}

// The original per-key export contract is intentionally retained as an oracle.
// It checks byte compatibility rather than restating the new batching logic.
Future<List<Map<String, dynamic>>> _legacyPackets(Database db,
    {String? editionId}) async {
  final packets = <Map<String, dynamic>>[];
  var cursor = 0;
  while (true) {
    final page = await db.rawQuery(
        'SELECT rowid AS cursor, * FROM records WHERE rowid > ? '
        '${editionId == null ? '' : 'AND edition_id = ? '}ORDER BY rowid LIMIT 128',
        [cursor, if (editionId != null) editionId]);
    final groups = <String, Map<String, dynamic>>{};
    for (final row in page) {
      final game =
          GameIdentity.fromJson(jsonDecode(row['game_json'] as String));
      final record =
          MetadataRecord.fromJson(jsonDecode(row['record_json'] as String));
      final edition =
          EditionIdentity.fromJson(jsonDecode(row['edition_json'] as String));
      final packet = groups.putIfAbsent(
          game.platformId!,
          () => {
                'version': 1,
                'platform': game.platformId,
                'records': <Map<String, Object?>>[],
                'bindings': <Map<String, Object?>>[],
                'artwork': <Map<String, Object?>>[],
                'responses': <Map<String, Object?>>[],
              });
      (packet['records'] as List).add({...row}
        ..remove('cursor')
        ..remove('platform_id'));
      (packet['bindings'] as List).addAll(await db.query('identity_bindings',
          where: 'game_id = ? OR game_id = ?',
          whereArgs: [game.id, game.baseGameId ?? game.id]));
      final keys = {
        for (final media in [
          ...record.media,
          ...MetadataArtworkCache.displayMedia(record,
              regions: edition.regions, includePhysicalLabel: true)
        ])
          MetadataArtworkCache.key(media)
      };
      for (final key in keys) {
        (packet['artwork'] as List).addAll(await db.query(
            'metadata_artwork_cache',
            where: 'media_key = ?',
            whereArgs: [key]));
        (packet['responses'] as List).addAll(await db.query('artwork_responses',
            where: 'provider_id = ? AND generation = ? AND media_key = ?',
            whereArgs: [record.providerId, record.refreshGeneration, key]));
      }
    }
    packets.addAll(groups.values);
    if (page.length < 128) return packets;
    cursor = page.last['cursor'] as int;
  }
}
