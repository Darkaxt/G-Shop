import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/providers/library_providers.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:retro_eshop/services/metadata/shared_metadata_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cloud browsing leaves media reads to mounted cards, not console scans',
      () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('rshop-cloud-readers-');
    final store = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate);
    store.cloudManaged = true;
    final cache = MetadataArtworkCache(
        Future.value(store.cloudIndex), store.artworkRoot,
        sharedStore: store);
    final container = ProviderContainer(overrides: [
      cachedMetadataArtworkProvider.overrideWith((ref) => Future.value(cache)),
      cachedMetadataReadinessProvider
          .overrideWith((ref) async => const AsyncData(0)),
      libraryDbProvider.overrideWith((ref) =>
          throw StateError('Whole-console projection access is not allowed')),
    ]);
    addTearDown(() async {
      container.dispose();
      await store.close();
      // Retained task-owned scratch is removed through transactional cleanup.
    });
    expect(await container.read(cachedMetadataCoversProvider('gba').future),
        isEmpty);
  });
}
