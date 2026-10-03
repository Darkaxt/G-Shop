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
    await verifyMetadataArtworkResource(factory);
    if (tracing) {
      // ignore: avoid_print
      print('artwork diagnostic terminal ${artworkWaitSnapshot()}');
    }
  }, timeout: Timeout.none);
}
