import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/providers/library_providers.dart';
import 'package:retro_eshop/providers/metadata_cloud_providers.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:retro_eshop/services/metadata/metadata_cloud_library.dart';
import 'package:retro_eshop/services/metadata/shared_metadata_store.dart';
import 'metadata_cloud_library_test.dart' show MemoryMetadataDrive;

class _JoinedPublication extends MetadataCloudLibrary {
  final started = Completer<void>(), finish = Completer<void>();
  bool closed = false;
  _JoinedPublication(SharedMetadataStore store)
      : super(
            store: store,
            remote: MemoryMetadataDrive(),
            accountId: 'a',
            rootId: 'r');
  @override
  Future<void> sync(Future<Database> projection, {bool pull = true}) async {
    started.complete();
    await finish.future;
  }

  @override
  Future<int> cachedBytes() async => 0;
  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('packaging pause joins publication and resume admits the next backup',
      () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('rshop-cloud-pause-');
    final store = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate);
    DatabaseService.testDatabase = store.cloudIndex;
    SharedPreferences.setMockInitialValues({
      metadataCloudSettingsKey: jsonEncode({
        'enabled': true,
        'account': 'a',
        'client': 'c',
        'root': 'r',
        'source': 's'
      })
    });
    final first = _JoinedPublication(store);
    final container = ProviderContainer(overrides: [
      metadataCloudProvider
          .overrideWith((ref) => MetadataCloudController(ref)..library = first)
    ]);
    final controller = container.read(metadataCloudProvider.notifier);
    try {
      await controller.ready;
      await first.started.future;
      expect(controller.state.busy, isTrue);
      final paused = controller.pause();
      first.finish.complete();
      await paused;
      expect(first.closed, isTrue);
      expect(controller.state.busy, isFalse);
      final next = _JoinedPublication(store);
      controller.library = next;
      final complete = Completer<void>();
      final remove = controller.addListener((state) {
        if (!state.busy &&
            state.message == 'Metadata is backed up in Drive' &&
            !complete.isCompleted) {
          complete.complete();
        }
      }, fireImmediately: false);
      try {
        controller.resume();
        await next.started.future;
        next.finish.complete();
        await complete.future;
      } finally {
        remove();
      }
    } finally {
      container.dispose();
      DatabaseService.resetForTesting();
      await store.close();
      // Retained task-owned scratch is removed through transactional cleanup.
    }
  });
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
