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
import 'package:retro_eshop/providers/metadata_providers.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'metadata_cloud_library_test.dart' show MemoryMetadataDrive;
import 'metadata_controls_test.dart'
    show controlsDatabase, ControlsArtworkProvider, MemorySecrets;

class _CachedFocusPublication extends _JoinedPublication {
  int foregroundPublications = 0;
  _CachedFocusPublication(super.store);
  @override
  Future<void> publishSelection(String edition, Set<String> requested) async {
    foregroundPublications++;
    throw StateError('Cached foreground joined background publication');
  }
}

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
  test('cached foreground images stay ready during background publication',
      () async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('rshop-cached-focus-');
    final db = await controlsDatabase();
    final store = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate);
    final cache = MetadataArtworkCache(Future.value(db), store.artworkRoot,
        sharedStore: store);
    final provider = ControlsArtworkProvider(includeScreenshot: true);
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        artworkCache: Future.value(cache),
        sharedStore: Future.value(store),
        catalogueChanged: () {});
    await controls.load();
    await controls.refresh(systemSlug: 'psx');
    final cached =
        await cache.artworkForEdition(provider.calls.single.editionId);
    expect(cached.cover, isNotNull,
        reason: 'Fixture has a real verified local cover');
    expect(cached.screenshots, hasLength(1));
    final cloud = _CachedFocusPublication(store);
    await cloud.open();
    final publication = cloud.sync(Future.value(db), pull: false);
    await cloud.started.future;
    DatabaseService.testDatabase = db;
    final container = ProviderContainer(overrides: [
      metadataCloudProvider
          .overrideWith((ref) => MetadataCloudController(ref)..library = cloud),
      cachedMetadataArtworkProvider.overrideWith((ref) => Future.value(cache)),
      cachedMetadataReadinessProvider
          .overrideWith((ref) async => const AsyncData(0)),
    ]);
    final selected = cloudSelectionMediaProvider(
        (platform: 'psx', selection: 'Game 1.chd', details: true));
    final mounted = container.listen(selected, (_, __) {});
    try {
      final result = await container.read(selected.future);
      expect(result, isNotNull);
      expect(await File.fromUri(Uri.parse(result!)).exists(), isTrue);
      expect(cloud.finish.isCompleted, isFalse,
          reason: 'Local readiness must not wait for the unrelated backup');
      expect(cloud.foregroundPublications, 0);
      // Corruption is not treated as a cache hit; the ordinary cloud-miss path
      // is still used rather than exposing unchecked local bytes.
      await File.fromUri(Uri.parse(result)).writeAsBytes([0]);
      container.invalidate(selected);
      expect(await container.read(selected.future), isNull);
      expect(cloud.foregroundPublications, 1);
    } finally {
      mounted.close();
      cloud.finish.complete();
      await publication;
      await container.read(metadataCloudProvider.notifier).pause();
      container.dispose();
      DatabaseService.resetForTesting();
      await controls.close();
      controls.dispose();
      await store.close();
      await db.close();
      // Retained task-owned scratch is removed through transactional cleanup.
    }
  });
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
