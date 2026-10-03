import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/metadata_artwork_resource_fixture.dart';
import 'support/artwork_wait_diagnostic.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  test('artwork wait observation is read-only and works without VM service',
      () async {
    final server = await startArtworkWaitObserver();
    // Flutter deliberately replaces ordinary HttpClient in widget fixtures.
    // Only this loopback observer contract needs the real client, never a ROM
    // or metadata provider transport; keep the global override unchanged.
    final client = _LoopbackHttpOverrides().createHttpClient(null);
    try {
      final uri = Uri.parse('http://127.0.0.1:${server.port}/');
      final get = await client.getUrl(uri);
      final response = await get.close();
      expect(response.statusCode, HttpStatus.ok);
      final snapshot = jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, dynamic>;
      expect(snapshot['pending'], isEmpty);
      expect(snapshot['artworkWorkId'], isNull);
      final post = await client.postUrl(uri);
      final rejected = await post.close();
      expect(rejected.statusCode, HttpStatus.methodNotAllowed);
      await rejected.drain<void>();
      expect(artworkWaitSnapshot(), jsonEncode(snapshot));
    } finally {
      client.close();
      await server.close();
    }
  }, timeout: Timeout.none);
  test('12000 repeated native artwork publications isolate the cache boundary',
      () async {
    final root = await Directory.systemTemp.createTemp('rshop-artwork-decode-');
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final cache = MetadataArtworkCache(Future.value(db), root);
    final provider = SyntheticArtworkProvider();
    final watch = Stopwatch()..start();
    final rssBefore = ProcessInfo.currentRss;
    try {
      for (var n = 1; n <= 12000; n++) {
        final media = MetadataMedia(
            type: 'box-2D',
            region: 'us',
            providerReference: ScreenScraperMediaReference(
                providerGameId: '$n',
                providerPlatformId: 4,
                mediaType: 'box-2D',
                region: 'us'));
        final result = await cache.download(media, provider, n, CancelToken());
        expect(result.result.status, MetadataLookupStatus.matched,
            reason: '$n');
        expect(result.blob, isNotNull, reason: '$n');
        expect(result.blob!.length,
            n == 1 ? provider.large.length : provider.small.length);
        if (n % 1000 == 0) {
          // Diagnostic progress only, never a lifecycle deadline or retry.
          // ignore: avoid_print
          print('native cache publications=$n rss=${ProcessInfo.currentRss}');
        }
      }
      expect(provider.calls, 12000);
      expect(provider.active, 0);
      expect(provider.peakActive, 1);
      expect(provider.maxChunk, lessThanOrEqualTo(65536));
      final files = await root.list().toList();
      expect(files, hasLength(2));
      expect(files.every((file) => file.path.endsWith('.png')), isTrue);
      // ignore: avoid_print
      print('native cache 12000: totalMs=${watch.elapsedMilliseconds} '
          'rssBefore=$rssBefore rssAfter=${ProcessInfo.currentRss} '
          'maxRss=${ProcessInfo.maxRss}');
    } finally {
      provider.close();
      await db.close();
      if (!p.isWithin(Directory.systemTemp.path, root.path) ||
          !p.basename(root.path).startsWith('rshop-artwork-decode-')) {
        throw StateError('Unexpected decode fixture root');
      }
      await root.delete(recursive: true);
    }
  }, timeout: Timeout.none);

  test('bounded artwork worker uses the shared native verification fixture',
      () async {
    final result =
        await verifyMetadataArtworkResource(databaseFactoryFfi, count: 256);
    expect(result['requested'], 256);
  }, timeout: Timeout.none);

  test('30000 distinct games keep artwork snapshot work and cache bounded',
      () async {
    final tracing =
        Platform.environment['RSHOP_ARTWORK_WAIT_DIAGNOSTIC'] == 'true';
    final factory = tracing ? await tracedArtworkFactory() : databaseFactoryFfi;
    final observer = tracing ? await startArtworkWaitObserver() : null;
    if (observer != null) {
      // ignore: avoid_print
      print('artwork diagnostic observer=http://127.0.0.1:${observer.port}/');
    }
    try {
      await verifyMetadataArtworkResource(factory,
          cacheFactory: tracing ? TracedArtworkCache.new : null);
      if (tracing) {
        // ignore: avoid_print
        print('artwork diagnostic terminal ${artworkWaitSnapshot()}');
      }
    } finally {
      await observer?.close();
    }
  }, timeout: Timeout.none);
}

class _LoopbackHttpOverrides extends HttpOverrides {}
