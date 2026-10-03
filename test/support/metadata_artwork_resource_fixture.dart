import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:sqflite/sqflite.dart';

// Real PNG structure and native decoding, not just a large MIME-labelled body.
Uint8List _largePng() {
  final random = Random(731);
  final raw = Uint8List(1000 * 4001);
  for (var row = 0; row < 1000; row++) {
    for (var column = 1; column < 4001; column++) {
      raw[row * 4001 + column] = random.nextInt(256);
    }
  }
  final result = BytesBuilder(copy: false)..add(base64Decode('iVBORw0KGgo='));
  void chunk(String name, List<int> data) {
    final payload = Uint8List(4 + data.length)
      ..setRange(0, 4, ascii.encode(name))
      ..setRange(4, 4 + data.length, data);
    result
      ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
      ..add(payload)
      ..add(
          (ByteData(4)..setUint32(0, getCrc32(payload))).buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, 1000)
    ..setUint32(4, 1000)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibEncoder().convert(raw));
  chunk('IEND', const []);
  return result.takeBytes();
}

class SyntheticArtworkProvider implements MetadataArtworkProvider {
  final Uint8List large = _largePng();
  final Uint8List small = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==');
  int calls = 0, maxChunk = 0, active = 0, peakActive = 0;
  bool closed = false;
  @override
  String get providerId => 'screenscraper';
  @override
  MetadataProviderCapabilities get capabilities =>
      const MetadataProviderCapabilities(
          fields: {'artwork'},
          verifiedIdLookup: true,
          rawRomLookup: false,
          titleSearch: false,
          documentedVoteCounts: false);
  @override
  void close() => closed = true;
  @override
  Future<MetadataLookupResult> lookup(MetadataLookupRequest request,
          {CancelToken? cancelToken}) async =>
      throw StateError('Artwork cannot perform game or ROM lookups');
  @override
  Future<MetadataLookupResult> fetchArtwork(MetadataMedia media,
      {required Future<void> Function(List<int>) write,
      CancelToken? cancelToken}) async {
    if (closed) throw StateError('Closed provider was contacted offline');
    calls++;
    if (calls % 1000 == 0) {
      // Diagnostic progress, never a lifecycle deadline.
      // ignore: avoid_print
      print('artwork requests=$calls rss=${ProcessInfo.currentRss}');
    }
    active++;
    peakActive = max(peakActive, active);
    try {
      final bytes = calls == 1 ? large : small;
      for (var offset = 0; offset < bytes.length; offset += 65536) {
        final end = min(offset + 65536, bytes.length);
        maxChunk = max(maxChunk, end - offset);
        await write(Uint8List.sublistView(bytes, offset, end));
      }
      return MetadataLookupResult(
          status: MetadataLookupStatus.matched,
          message: 'Synthetic artwork transport');
    } finally {
      active--;
    }
  }
}

/// Identical production job/cache checks for host FFI and Android SQLite.
/// All transports are synthetic; never scans an account, catalogue or ROM.
Future<Map<String, Object?>> verifyMetadataArtworkResource(
    DatabaseFactory factory,
    {int count = 30000}) async {
  if (count < 2) {
    throw ArgumentError.value(count, 'count', 'At least two games');
  }

  final root = await Directory.systemTemp.createTemp('rshop-artwork-resource-');
  Database? db;
  final provider = SyntheticArtworkProvider();
  final watch = Stopwatch()..start();
  final rssBefore = ProcessInfo.currentRss;
  MetadataMedia media(int n) => MetadataMedia(
      type: 'box-2D',
      region: 'us',
      providerReference: ScreenScraperMediaReference(
          providerGameId: '$n',
          providerPlatformId: 4,
          mediaType: 'box-2D',
          region: 'us'));
  try {
    db = await factory.openDatabase(p.join(root.path, 'fixture.db'));
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.transaction((txn) async {
      for (var start = 1; start <= count; start += 128) {
        final batch = txn.batch();
        for (var n = start; n < start + 128 && n <= count; n++) {
          final id = '$n'.padLeft(5, '0');
          final game = GameIdentity(
              id: id,
              platformId: 'snes',
              title: 'Game $n',
              providerIds: {'screenscraper': '$n'},
              matchStatus: IdentityMatchStatus.manuallyMatched);
          final edition =
              EditionIdentity(id: id, gameId: id, tags: {'official'});
          final record = MetadataRecord(
              gameId: id,
              editionId: id,
              platformId: 'snes',
              providerId: provider.providerId,
              providerGameId: '$n',
              retrievedAt: DateTime.utc(2026, 10, 3),
              refreshGeneration: 1,
              matchMethod: 'verifiedProviderId',
              titles: [MetadataText(text: game.title)],
              descriptions: [MetadataText(text: 'x' * 256)],
              media: [media(n)]);
          batch.insert('library_game_identities', {
            'game_id': id,
            'platform_id': 'snes',
            'title': game.title,
            'match_status': game.matchStatus.name,
            'record_json': jsonEncode(game.toJson())
          });
          batch.insert('library_editions', {
            'edition_id': id,
            'game_id': id,
            'record_json': jsonEncode(edition.toJson())
          });
          batch.insert('library_metadata', {
            'edition_id': id,
            'provider_id': provider.providerId,
            'provider_game_id': '$n',
            'generation_id': 1,
            'retrieved_at': record.retrievedAt.toIso8601String(),
            'identity_key': LibraryStore.metadataIdentity({
              'game_json': jsonEncode(game.toJson()),
              'edition_json': jsonEncode(edition.toJson())
            }, providerId: provider.providerId),
            'record_json': jsonEncode(record.toJson())
          });
        }
        await batch.commit(noResult: true);
      }
    });
    Iterable<String> editions() sync* {
      for (var n = 1; n <= count; n++) {
        yield '$n'.padLeft(5, '0');
      }
    }

    final jobs = MetadataRefreshJobs(Future.value(db));
    final cache = MetadataArtworkCache(
        Future.value(db), Directory(p.join(root.path, 'images')));
    final snapshot = await jobs.createArtwork(
        providerId: provider.providerId,
        collectionGeneration: 'synthetic-resource',
        editionIds: editions());
    expect(snapshot.counts, {'pending': count});
    final captureMs = watch.elapsedMilliseconds;
    // ignore: avoid_print
    print('artwork snapshot captured: $captureMs ms, root=${root.path}');
    expect(provider.large.length, greaterThan(3900000));
    expect(provider.large.length,
        lessThanOrEqualTo(MetadataArtworkCache.maxBytes));
    final done = await jobs.run(snapshot.id, provider, artworkCache: cache);
    expect(done.state, 'completed');
    expect(done.counts, {'matched': count});
    expect(done.requested, count);
    expect(provider.calls, count);
    expect(provider.peakActive, 1);
    expect(provider.maxChunk, lessThanOrEqualTo(65536));
    expect(provider.active, 0);
    expect(await cache.root.list().length, 2,
        reason:
            'Content addressed bodies deduplicate without losing selectors.');
    final files = await cache.root.list().toList();
    expect(files.every((f) => f.path.endsWith('.png')), isTrue);
    expect(
        await cache.fileFor('00001', provider.providerId, media(1)), isNotNull);
    final originalJob = snapshot.id;
    await db.close();
    db = null;
    provider.close();
    db = await factory.openDatabase(p.join(root.path, 'fixture.db'));
    final reopened = MetadataRefreshJobs(Future.value(db));
    final offlineCache = MetadataArtworkCache(Future.value(db), cache.root);
    expect((await reopened.report(originalJob)).counts, {'matched': count});
    for (final n in [1, count ~/ 2, count]) {
      final file = await offlineCache.fileFor(
          '$n'.padLeft(5, '0'), provider.providerId, media(n));
      expect(file, isNotNull);
      expect(await file!.length(),
          n == 1 ? provider.large.length : provider.small.length);
    }
    expect(
        (await reopened.run(originalJob, provider, artworkCache: offlineCache))
            .requested,
        count);
    expect(provider.calls, count,
        reason: 'Completed/offline reads perform no transport.');
    // Diagnostic only, never a completion deadline or cancellation condition.
    // ignore: avoid_print
    print(
        'artwork $count distinct: pid=$pid captureMs=$captureMs totalMs=${watch.elapsedMilliseconds} '
        'rssBefore=$rssBefore rssAfter=${ProcessInfo.currentRss} maxRss=${ProcessInfo.maxRss} '
        'largestPng=${provider.large.length} maxChunk=${provider.maxChunk} peakActive=${provider.peakActive}');
    return {
      'games': count,
      'requested': done.requested,
      'capture_ms': captureMs,
      'total_ms': watch.elapsedMilliseconds,
      'rss_before': rssBefore,
      'rss_after': ProcessInfo.currentRss,
      'max_rss': ProcessInfo.maxRss,
      'largest_png': provider.large.length,
      'max_chunk': provider.maxChunk,
      'peak_active': provider.peakActive,
      'offline_requests': 0,
    };
  } finally {
    provider.close();
    await db?.close();
    if (!p.isWithin(Directory.systemTemp.path, root.path) ||
        !p.basename(root.path).startsWith('rshop-artwork-resource-')) {
      throw StateError('Unexpected resource fixture root');
    }
    await root.delete(recursive: true);
  }
}
