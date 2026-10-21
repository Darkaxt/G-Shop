import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/features/library/library_screen.dart';
import 'package:g_shop/widgets/console_hud.dart';
import 'package:g_shop/core/widgets/animated_background.dart';
import 'package:g_shop/features/library/widgets/library_tabs.dart';
import 'package:g_shop/features/library/widgets/library_dashboard.dart';
import 'package:g_shop/features/game_list/widgets/filter_overlay.dart';
import 'package:g_shop/models/config/app_config.dart';
import 'package:g_shop/models/config/system_config.dart';
import 'package:g_shop/services/patch_build_store.dart';
import 'package:g_shop/services/input_debouncer.dart';
import 'package:g_shop/features/library/patch_library_screen.dart';
import '../portable_patch_recipe_test.dart' show portableFixture;
import 'package:g_shop/models/config/provider_config.dart';
import 'package:g_shop/models/custom_shelf.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/game_metadata_info.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/providers/app_providers.dart';
import 'package:g_shop/providers/game_providers.dart';
import 'package:g_shop/providers/installed_files_provider.dart';
import 'package:g_shop/providers/library_providers.dart';
import 'package:g_shop/services/database_service.dart';
import 'package:g_shop/services/device_info_service.dart';
import 'package:g_shop/services/config_storage_service.dart';
import 'package:g_shop/services/sources_notifier.dart';
import 'package:g_shop/services/library_query.dart';
import 'package:g_shop/services/library_store.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';
import 'package:g_shop/services/metadata/metadata_credentials.dart';
import 'package:g_shop/services/metadata/metadata_provider.dart';
import 'package:g_shop/providers/metadata_providers.dart';
import 'package:g_shop/providers/metadata_cloud_providers.dart';
import 'package:g_shop/services/metadata/metadata_artwork_cache.dart';
import 'package:g_shop/features/settings/metadata_settings_screen.dart';
import 'package:g_shop/services/storage_service.dart';
import 'package:g_shop/widgets/base_game_card.dart';
import 'package:g_shop/widgets/media_cover_fallback.dart';
import 'package:g_shop/widgets/physical_media_view.dart';
import 'package:g_shop/widgets/quick_menu.dart';
import 'package:g_shop/providers/preview_providers.dart';
import 'package:g_shop/services/secondary_preview.dart';
import 'package:g_shop/features/preview/dual_screen_preview_host.dart';
import '../helpers/pump_helpers.dart';
import '../metadata_controls_test.dart' show MemorySecrets, ControlsProvider;

class _Database extends DatabaseService {
  final Database db;
  _Database(this.db);
  @override
  Future<Database> get database async => db;
}

class _ImmediateInput extends InputDebouncer {
  @override
  bool canPerformAction() => true;
}

class _Config extends ConfigStorageService {
  @override
  Future<AppConfig?> loadConfig() async => AppConfig.empty;
}

class _GalleryCache extends MetadataArtworkCache {
  final Future<Map<String, List<String>>> gallery;
  Object? error;
  _GalleryCache(Database db, this.gallery)
      : super(Future.value(db), Directory.systemTemp);
  @override
  Future<Map<String, List<String>>> galleryForEdition(String editionId,
          {bool hydrate = false,
          bool hydrateBooklet = false,
          Set<String> hydrateTypes = const {}}) =>
      error == null ? gallery : Future.error(error!);
}

class _MetadataScopeObserver extends ProviderObserver {
  final covers = <String>[];
  final ratings = <String>[];

  @override
  void didAddProvider(
      ProviderBase provider, Object? value, ProviderContainer container) {
    if (provider.from == cachedMetadataCoversProvider) {
      covers.add(provider.argument as String);
    } else if (provider.from == cachedCoverRatingsProvider) {
      ratings.add(provider.argument as String);
    }
  }
}

void main() {
  defineLibraryDiscoveryChecks();
  testWidgets('library search recovers after an empty result', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    sqfliteFfiInit();
    final db =
        await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games(id INTEGER PRIMARY KEY,
      systemSlug TEXT, displayName TEXT, filename TEXT, url TEXT,
      artifact_key TEXT, remote_artifact TEXT, provider_config TEXT,
      is_folder INTEGER DEFAULT 0)''');
    await LibraryQuery.install(db);
    await db.insert('games', {
      'id': 1,
      'systemSlug': 'gba',
      'displayName': 'Yoshi Topsy-Turvy',
      'filename': 'Yoshi Topsy-Turvy (USA).7z',
      'url': ''
    });
    SharedPreferences.setMockInitialValues({
      'favorites_version': 1,
      'secure_auth_migrated': true,
      'physical_media_reduced_motion': true
    });
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final container = ProviderContainer(overrides: [
      libraryDbProvider.overrideWithValue(_Database(db)),
      storageServiceProvider.overrideWithValue(storage),
      bootstrappedConfigProvider.overrideWith((ref) async => AppConfig.empty),
      installedFilesProvider.overrideWith((ref) async => InstalledFilesState()),
      selectionContinuityProvider.overrideWith((ref) async {}),
      cachedMetadataReadinessProvider
          .overrideWith((ref) async => const AsyncData(0)),
      deviceMemoryProvider.overrideWithValue(
          const DeviceMemoryInfo(totalBytes: 0, tier: MemoryTier.standard)),
      sourcesProvider
          .overrideWith((ref) => SourcesNotifier(_Config(), db: _Database(db))),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: createTestApp(const LibraryScreen(openSearch: true))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'no such game');
    await tester.pumpAndSettle();
    expect(find.byType(BaseGameCard), findsNothing);
    await tester.enterText(find.byType(TextField), 'Yoshi');
    // Bounded diagnostic pumps expose a stuck busy state without waiting on
    // the spinner's indefinitely scheduled animation.
    for (var i = 0; i < 12; i++) {
      await tester.pump();
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(BaseGameCard), findsOneWidget);
    expect(tester.widget<BaseGameCard>(find.byType(BaseGameCard)).displayName,
        'Yoshi Topsy-Turvy (USA)');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('console categories are conditional, stable and share navigation',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    sqfliteFfiInit();
    final db =
        await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    DatabaseService.testDatabase = db;
    addTearDown(DatabaseService.resetForTesting);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await PatchBuildSchema.install(db);
    await db.execute(
        'CREATE TABLE games(id INTEGER PRIMARY KEY, systemSlug TEXT, '
        'displayName TEXT, filename TEXT, url TEXT, artifact_key TEXT, '
        'remote_artifact TEXT, provider_config TEXT, is_folder INTEGER DEFAULT 0)');
    await LibraryQuery.install(db);
    final store = LibraryStore(Future.value(db));
    final seeds = [
      ('gameandwatch', 'Ball', 'official'),
      ('gba', 'Original', 'official'),
      ('psx', 'Modified', 'Hack'),
      ('gbc', 'Homebrew', 'homebrew')
    ];
    for (var i = 0; i < seeds.length; i++) {
      final (slug, title, tag) = seeds[i];
      await db.insert('games', {
        'id': i + 1,
        'systemSlug': slug,
        'displayName': title,
        'filename': '$title.7z',
        'url': ''
      });
      final id = (await db.transaction((txn) =>
              LibraryStore.catalogueEditions(txn, cacheRowId: i + 1).toList()))
          .single;
      final edition = (await store.edition(id))!;
      await store.putEdition(EditionIdentity.fromJson({
        ...edition.toJson(),
        'tags': [tag]
      }));
    }
    final recipe = portableFixture();
    await PatchBuildStore(Future.value(db)).begin(
        buildId: 'saved-build',
        recipe: recipe.recipe,
        sourceGameId: recipe.sourceGameId,
        gameTitle: recipe.gameTitle,
        gameIndexPath: recipe.gameIndexPath.value,
        providerSourceId: 'fixture',
        title: recipe.title,
        jobRoot: '/fixture/job',
        targetRoot: '/fixture/roms',
        filename: 'modified.gba');
    SharedPreferences.setMockInitialValues({
      'favorites_version': 1,
      'secure_auth_migrated': true,
      'physical_media_enabled': false,
      'physical_media_reduced_motion': true
    });
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    const config = AppConfig(systems: [
      SystemConfig(
          id: 'gba', name: 'GBA', targetFolder: '/fixture/roms', providers: [])
    ]);
    final container = ProviderContainer(overrides: [
      inputDebouncerProvider.overrideWith((_) => _ImmediateInput()),
      libraryDbProvider.overrideWithValue(_Database(db)),
      storageServiceProvider.overrideWithValue(storage),
      bootstrappedConfigProvider.overrideWith((ref) async => config),
      sharedMetadataStoreProvider.overrideWithValue(Future.value(null)),
      installedFilesProvider.overrideWith((ref) async => InstalledFilesState()),
      selectionContinuityProvider.overrideWith((ref) async {}),
      cachedMetadataReadinessProvider
          .overrideWith((ref) async => const AsyncData(0)),
      deviceMemoryProvider.overrideWithValue(
          const DeviceMemoryInfo(totalBytes: 0, tier: MemoryTier.standard)),
      sourcesProvider
          .overrideWith((ref) => SourcesNotifier(_Config(), db: _Database(db))),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: createTestApp(Builder(
            builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                // Category navigation does not verify the unavailable host GPU.
                child: const TickerMode(
                    enabled: false, child: LibraryScreen()))))));
    await tester.pumpAndSettle();
    Future<void> console(String label) async {
      final tabs = tester.widget<LibraryTabs>(
          find.byKey(const ValueKey('library-console-tabs')));
      final index = tabs.tabs.indexWhere((t) => t.label == label);
      expect(index, greaterThan(0));
      tabs.onTap!(index);
      await tester.pumpAndSettle();
    }

    List<String> categories() => tester
        .widget<LibraryTabs>(
            find.byKey(const ValueKey('library-category-tabs')))
        .tabs
        .map((t) => t.label)
        .toList();
    await tester.tap(find.byKey(const ValueKey('console-summary-psx')));
    await tester.pumpAndSettle();
    expect(categories(), ['All', 'Hacks']);
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('library-category-tabs')),
        matching: find.text('HACKS')));
    await tester.pumpAndSettle();
    await console('GAMEANDWATCH');
    expect(categories(), ['All', 'Commercial']);
    expect(
        tester
            .widget<LibraryTabs>(
                find.byKey(const ValueKey('library-category-tabs')))
            .selectedTab,
        0,
        reason: 'An unavailable previous console category resets');
    expect(find.byType(BaseGameCard), findsOneWidget);
    expect(tester.widget<BaseGameCard>(find.byType(BaseGameCard)).reducedMotion,
        isTrue,
        reason: 'The real library card receives the saved preference');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LibraryTabs>(
                find.byKey(const ValueKey('library-category-tabs')))
            .selectedTab,
        1);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LibraryTabs>(
                find.byKey(const ValueKey('library-category-tabs')))
            .selectedTab,
        0,
        reason: 'Controller wraps over only visible categories');
    await console('GBA');
    expect(categories(), ['All', 'Commercial', 'Patches']);
    await tester.tap(find.text('INSTALLED').first);
    await tester.pumpAndSettle();
    expect(find.byType(BaseGameCard), findsNothing);
    expect(categories(), ['All', 'Commercial', 'Patches'],
        reason: 'Empty status results do not hide complete-console categories');
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonY);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'no matching title');
    await tester.pumpAndSettle();
    expect(categories(), ['All', 'Commercial', 'Patches']);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonY);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('library-category-tabs')),
        matching: find.text('PATCHES')));
    while (find.byType(PatchLibraryScreen).evaluate().isEmpty) {
      await tester.pump();
    }
    final patchRoute =
        ModalRoute.of(tester.element(find.byType(PatchLibraryScreen)))!;
    // Join the navigation being tested, not the new route's model-loading
    // spinner: the host GPU is unavailable and that is separate acceptance.
    while (!patchRoute.animation!.isCompleted) {
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(find.byType(PatchLibraryScreen), findsOneWidget,
        reason: 'Dynamic index 2 opens Patches, not the omitted Hacks tab');
    Navigator.of(tester.element(find.byType(PatchLibraryScreen))).pop();
    await tester.pumpAndSettle();
    await console('GBC');
    expect(find.byKey(const ValueKey('library-category-tabs')), findsNothing,
        reason:
            'All retains homebrew without inventing Commercial/Hacks/Patches');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('dual preview uses eight covers and retains gallery focus',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 369 / 160;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    sqfliteFfiInit();
    final db =
        await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games(id INTEGER PRIMARY KEY,
      systemSlug TEXT, displayName TEXT, filename TEXT, url TEXT,
      artifact_key TEXT, remote_artifact TEXT, provider_config TEXT,
      is_folder INTEGER DEFAULT 0)''');
    await LibraryQuery.install(db);
    for (var i = 1; i <= 8; i++) {
      await db.insert('games', {
        'id': i,
        'systemSlug': 'n64',
        'displayName': 'Game $i',
        'filename': 'Game $i.z64',
        'url': ''
      });
    }
    SharedPreferences.setMockInitialValues({
      'favorites_version': 1,
      'secure_auth_migrated': true,
      'physical_media_reduced_motion': true
    });
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.setLibraryConsole('n64');
    final secondary = SecondaryPreview()..available = true;
    final snapshots = <Map<String, dynamic>>[];
    final gallery = Completer<Map<String, List<String>>>();
    final galleryCache = _GalleryCache(db, gallery.future);
    addTearDown(() {
      if (!gallery.isCompleted) gallery.complete({});
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SecondaryPreview.channel, (call) async {
      if (call.method == 'present')
        snapshots.add((call.arguments as Map).cast<String, dynamic>());
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SecondaryPreview.channel, null));
    final container = ProviderContainer(overrides: [
      secondaryPreviewProvider.overrideWith((ref) => secondary),
      libraryDbProvider.overrideWithValue(_Database(db)),
      storageServiceProvider.overrideWithValue(storage),
      bootstrappedConfigProvider.overrideWith((ref) async => AppConfig.empty),
      installedFilesProvider.overrideWith((ref) async => InstalledFilesState()),
      selectionContinuityProvider.overrideWith((ref) async {}),
      deviceMemoryProvider.overrideWithValue(
          const DeviceMemoryInfo(totalBytes: 0, tier: MemoryTier.standard)),
      sourcesProvider
          .overrideWith((ref) => SourcesNotifier(_Config(), db: _Database(db))),
      gameMetadataProvider.overrideWith((ref, params) async => GameMetadataInfo(
          filename: params.filename,
          systemSlug: params.systemSlug,
          editionId: 'fixture',
          lastUpdated: 0)),
      cloudSelectionMediaProvider.overrideWith((ref, selection) async => null),
      editionGalleryMediaProvider
          .overrideWith((ref, edition) => gallery.future),
      cachedMetadataArtworkProvider.overrideWith((ref) async => galleryCache),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: createTestApp(const LibraryScreen())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-media-preview')), findsNothing);
    final grid = tester.widget<GridView>(find.byType(GridView).first);
    expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        4);
    final cards = find.byType(BaseGameCard);
    expect(cards, findsNWidgets(8));
    final hud = tester.getRect(find.byType(ConsoleHud));
    for (final element in cards.evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(
          rect.bottom, lessThanOrEqualTo(1080 / tester.view.devicePixelRatio));
      expect(rect.overlaps(hud), isFalse,
          reason: 'Controller hints must not cover a game');
    }
    final focused = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(snapshots.last['details'], isTrue);
    expect(FocusManager.instance.primaryFocus, same(focused));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(snapshots.last['filename'], 'Game 2.z64');
    expect(snapshots.last['details'], isFalse);
    final preview = tester
        .state<DualScreenPreviewHostState>(find.byType(DualScreenPreviewHost));
    preview.actionsMenu!.children!
        .whereType<QuickMenuItem>()
        .firstWhere((item) => item.label == 'Resources')
        .onSelect!();
    await tester.pumpAndSettle();
    expect(snapshots.last['gallery'], isTrue);
    expect(snapshots.last['galleryLoading'], isTrue,
        reason: 'Acknowledge opening without exposing a fallback model');
    gallery.complete(const {
      'box-2D': ['file:///fixture/front.png']
    });
    await tester.pumpAndSettle();
    expect(snapshots.last['gallery'], isTrue);
    expect(snapshots.last['galleryLoading'], isFalse);
    expect(snapshots.last['galleryResources'], {
      'box-2D': ['file:///fixture/front.png']
    });
    galleryCache.error = StateError('Offline fixture');
    preview.actionsMenu!.children!
        .whereType<QuickMenuItem>()
        .firstWhere((item) => item.label == 'Resources')
        .onSelect!();
    await tester.pumpAndSettle();
    expect(snapshots.last['gallery'], isFalse);
    expect(snapshots.last['galleryLoading'], isFalse);
    expect(snapshots.last['details'], isTrue);
    expect(snapshots.last['notice'], contains('Resources could not load'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('library load survives selection migration invalidation',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    sqfliteFfiInit();
    final db =
        await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games(id INTEGER PRIMARY KEY,
      systemSlug TEXT, displayName TEXT, filename TEXT, url TEXT,
      artifact_key TEXT, remote_artifact TEXT, provider_config TEXT,
      is_folder INTEGER DEFAULT 0)''');
    await LibraryQuery.install(db);
    await db.insert('games', {
      'id': 1,
      'systemSlug': 'psx',
      'displayName': 'Game',
      'filename': 'Game.chd',
      'url': ''
    });
    SharedPreferences.setMockInitialValues({
      'favorites_version': 1,
      'secure_auth_migrated': true,
      'physical_media_reduced_motion': true
    });
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final firstMigration = Completer<void>();
    var migrations = 0;
    final container = ProviderContainer(overrides: [
      libraryDbProvider.overrideWithValue(_Database(db)),
      storageServiceProvider.overrideWithValue(storage),
      bootstrappedConfigProvider.overrideWith((ref) async => AppConfig.empty),
      installedFilesProvider.overrideWith((ref) async => InstalledFilesState()),
      selectionContinuityProvider.overrideWith((ref) async {
        ref.watch(gameDbChangedProvider);
        migrations++;
        if (migrations == 1) await firstMigration.future;
      }),
      deviceMemoryProvider.overrideWithValue(
          const DeviceMemoryInfo(totalBytes: 0, tier: MemoryTier.standard)),
      sourcesProvider
          .overrideWith((ref) => SourcesNotifier(_Config(), db: _Database(db))),
    ]);
    addTearDown(container.dispose);
    addTearDown(() {
      if (!firstMigration.isCompleted) firstMigration.complete();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: createTestApp(const LibraryScreen())));
    expect(find.byType(AnimatedBackground), findsOneWidget,
        reason: 'Loading and loaded content share the red library backdrop');
    while (migrations == 0) {
      await tester.pump();
    }
    // Catalogue publication can invalidate the in-flight migration. Completing
    // its old operation cannot resolve the provider's cancelled subscription.
    container.read(gameDbChangedProvider.notifier).state++;
    firstMigration.complete();
    await tester.pump();
    await tester.pump();
    expect(migrations, 2,
        reason: 'The Library must keep its awaited migration subscribed');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('console-summary-psx')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets(
      'exact copy is one library card across local/cloud changes with favorite and shelf continuity',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    sqfliteFfiInit();
    final db =
        await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games(id INTEGER PRIMARY KEY,
      systemSlug TEXT, displayName TEXT, filename TEXT, url TEXT,
      artifact_key TEXT, remote_artifact TEXT, provider_config TEXT,
      is_folder INTEGER DEFAULT 0)''');
    await LibraryQuery.install(db);
    final artifact = RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: 'source',
            accountId: 'account',
            providerFileId: 'file'),
        displayName: 'Cloud.7z',
        displayPath: 'Cloud.7z',
        version: '1',
        sizeBytes: 5,
        providerChecksums: {'md5': 'a' * 32},
        canDownload: true);
    await db.insert('games', {
      'id': 1,
      'systemSlug': 'psx',
      'displayName': 'Old',
      'filename': 'Old.7z',
      'url': ''
    });
    await db.insert('games', {
      'id': 2,
      'systemSlug': 'psx',
      'displayName': 'Cloud',
      'filename': 'Cloud.7z',
      'url': '',
      'artifact_key': artifact.id.key,
      'remote_artifact': jsonEncode(artifact.toJson()),
      'provider_config': jsonEncode(
          const ProviderConfig(type: ProviderType.drive, priority: 0)
              .toJsonWithoutAuth())
    });
    SharedPreferences.setMockInitialValues({
      'favorites_version': 1,
      'secure_auth_migrated': true,
      'physical_media_reduced_motion': true
    });
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.setLibraryConsole('psx');
    await storage.setFavorites(['Old.7z']);
    await storage.setCustomShelves([
      CustomShelf(
          id: 'manual',
          name: 'Manual',
          manualGameIds: ['Old.7z'],
          sortMode: ShelfSortMode.manual,
          createdAt: DateTime.utc(2026))
    ]);
    var local = true;
    final container = ProviderContainer(overrides: [
      libraryDbProvider.overrideWithValue(_Database(db)),
      storageServiceProvider.overrideWithValue(storage),
      bootstrappedConfigProvider.overrideWith((ref) async => AppConfig.empty),
      installedFilesProvider
          .overrideWith((ref) async => InstalledFilesState(exactBySystem: {
                'psx': [if (local) artifact]
              }, legacyAliasesBySystem: {
                'psx': {'Old.7z': artifact}
              })),
      deviceMemoryProvider.overrideWithValue(
          const DeviceMemoryInfo(totalBytes: 0, tier: MemoryTier.standard)),
      sourcesProvider
          .overrideWith((ref) => SourcesNotifier(_Config(), db: _Database(db))),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: createTestApp(const LibraryScreen())));
    await tester.pumpAndSettle();
    BaseGameCard card() =>
        tester.widget<BaseGameCard>(find.byType(BaseGameCard));
    expect(find.byType(BaseGameCard), findsOneWidget);
    expect(card().displayName, 'Cloud');
    expect(card().isInstalled, isTrue);
    expect(storage.getFavorites(), ['artifact:${artifact.id.key}']);
    expect(storage.getCustomShelves().single.manualGameIds,
        ['artifact:${artifact.id.key}']);
    local = false;
    container.invalidate(installedFilesProvider);
    await tester.pumpAndSettle();
    expect(find.byType(BaseGameCard), findsOneWidget);
    expect(card().isInstalled, isFalse);
    expect(card().isRemoteAvailable, isTrue);
    await tester.tap(find.text('FAVORITES').first);
    await tester.pumpAndSettle();
    expect(find.byType(BaseGameCard), findsOneWidget);
    await tester.ensureVisible(find.text('MANUAL').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('MANUAL').first);
    await tester.pumpAndSettle();
    expect(find.byType(BaseGameCard), findsOneWidget);
    local = true;
    container.invalidate(installedFilesProvider);
    await tester.pumpAndSettle();
    expect(find.byType(BaseGameCard), findsOneWidget);
    expect(card().isInstalled, isTrue);
    expect(await db.query('games'), hasLength(2),
        reason: 'Projection does not rewrite captured cache rows');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

/// Reuse the normal Library assertions with Android SQLite and actual display
/// metrics. Native checkpoints capture the real UI before teardown, not a
/// substitute grid or a production-data bootstrap.
void defineLibraryDiscoveryChecks({
  DatabaseFactory? factory,
  Future<void> Function(String name, WidgetTester tester)? checkpoint,
}) {
  testWidgets(
      'library Top is one scoped cap; tags intersect and shelves keep order',
      (tester) async {
    if (factory == null) {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      sqfliteFfiInit();
    }
    final db = await (factory ?? databaseFactoryFfiNoIsolate)
        .openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games(id INTEGER PRIMARY KEY,
      systemSlug TEXT, displayName TEXT, filename TEXT, url TEXT,
      artifact_key TEXT, remote_artifact TEXT, provider_config TEXT,
      is_folder INTEGER DEFAULT 0)''');
    await LibraryQuery.install(db);
    final store = LibraryStore(Future.value(db));
    final editions = <int, String>{};
    final at = DateTime.utc(2026, 10, 3);
    for (var i = 1; i <= 12; i++) {
      final platform = i.isOdd ? 'psx' : 'ps2';
      final title = 'Game ${i.toString().padLeft(2, '0')}';
      await db.insert('games', {
        'id': i,
        'systemSlug': platform,
        'displayName': title,
        'filename': '$title.7z',
        'url': 'https://example.invalid/$i',
        if (i != 12)
          'provider_config': jsonEncode(const ProviderConfig(
                  type: ProviderType.web,
                  priority: 1,
                  url: 'https://example.invalid/')
              .toJsonWithoutAuth()),
      });
      final id = (await db.transaction((txn) =>
              LibraryStore.catalogueEditions(txn, cacheRowId: i).toList()))
          .single;
      editions[i] = id;
      final edition = (await store.edition(id))!;
      final game = (await store.game(edition.gameId))!;
      await store.putGame(GameIdentity.fromJson({
        ...game.toJson(),
        'matchStatus': 'manuallyMatched',
        'providerIds': {'igdb': '$i'}
      }));
      await store.putEdition(EditionIdentity.fromJson({
        ...edition.toJson(),
        'tags': i == 1
            ? ['Hack', 'T-Eng', 'Uncensor']
            : i == 2
                ? ['Dub']
                : i == 3
                    ? ['Undub']
                    : [i == 12 ? 'Hack' : 'official']
      }));
      await store.putMetadata(MetadataRecord(
          gameId: game.id,
          editionId: id,
          platformId: platform,
          providerId: 'igdb',
          providerGameId: '$i',
          retrievedAt: at,
          refreshGeneration: 1,
          // Hack projects have their own score. Dub/Undub use the explicitly
          // labelled original-game score, not an official-release tag.
          matchMethod: i == 1 || i == 12
              ? 'verifiedProjectId'
              : 'verifiedProviderIdGlobalGame',
          titles: [
            MetadataText(text: title)
          ],
          genres: [
            MetadataGenre(
                providerGenreId: 'action',
                names: const [MetadataText(text: 'Action')])
          ],
          ratings: [
            SourcedRating.parse(
                sourceId: 'igdb',
                sourceLabel: 'IGDB',
                providerGameId: '$i',
                rawValue: 100 - i,
                scaleMinimum: 0,
                scaleMaximum: 100,
                voteCount: 100,
                kind: RatingKind.communityAggregate,
                retrievedAt: at)!
          ]));
    }
    SharedPreferences.setMockInitialValues({
      'physical_media_reduced_motion': true,
      'physical_media_enabled': true,
    });
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.setFavoritesVersion(2);
    await storage.setFavorites(['Game 02.7z', 'Game 09.7z']);
    await storage.setCustomShelves([
      CustomShelf(
          id: 'manual',
          name: 'Manual',
          manualGameIds: ['Game 09.7z', 'Game 01.7z', 'Game 12.7z'],
          sortMode: ShelfSortMode.manual,
          createdAt: at)
    ]);
    final metadataScopes = _MetadataScopeObserver();
    final igdb = ControlsProvider('igdb');
    igdb.reply = (request, _) async {
      final previous = (await store.metadata(request.editionId, 'igdb'))!;
      final updated = previous.toJson();
      updated['refreshGeneration'] = request.refreshGeneration;
      if (request.verifiedProviderGameId == '10') {
        (updated['ratings'] as List).first['rawValue'] = 99.5;
      }
      return MetadataLookupResult(
          status: MetadataLookupStatus.matched,
          record: MetadataRecord.fromJson(updated),
          message: 'Fresh fixture rating');
    };
    late ProviderContainer container;
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'igdb': igdb, 'screenscraper': ControlsProvider()},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        readRomHeader: (_, __, ___) =>
            throw StateError('Ratings must not read ROM bytes'),
        readArchiveIdentifier: (_, __, ___) =>
            throw StateError('Ratings must not read archives'),
        catalogueChanged: () =>
            container.read(gameDbChangedProvider.notifier).state++);
    await controls.load();
    container = ProviderContainer(observers: [
      metadataScopes
    ], overrides: [
      libraryDbProvider.overrideWithValue(_Database(db)),
      metadataControlsProvider.overrideWith((_) => controls),
      // Native fixtures exercise imported 3D; host Skia uses the real flat mode.
      mediaPresentationProvider.overrideWith((_) => MediaPresentationNotifier(
          storage,
          resourcesAvailable: factory != null)),
      storageServiceProvider.overrideWithValue(storage),
      bootstrappedConfigProvider.overrideWith((ref) async => AppConfig.empty),
      installedFilesProvider.overrideWith((ref) async => InstalledFilesState(
            bySystem: {
              'ps2': {'Game 02.7z'},
              'psx': {'Game 09.7z'}
            },
            all: {'Game 02.7z', 'Game 09.7z'},
          )),
      deviceMemoryProvider.overrideWithValue(
          const DeviceMemoryInfo(totalBytes: 0, tier: MemoryTier.standard)),
      sourcesProvider
          .overrideWith((ref) => SourcesNotifier(_Config(), db: _Database(db))),
    ]);
    addTearDown(container.dispose);
    addTearDown(controls.close);
    Widget app({double textScale = 1}) => UncontrolledProviderScope(
        container: container,
        child: createTestApp(Builder(
            builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: const LibraryScreen()))));
    List<String> cards() => tester
        .widgetList<BaseGameCard>(find.byType(BaseGameCard))
        .map((c) => c.displayName)
        .toList();
    List<String> firstGames(int count) => List.generate(
        count, (i) => 'Game ${(i + 1).toString().padLeft(2, '0')}');
    Future<void> tapFilter(String key) async {
      final option = find.byKey(ValueKey(key));
      final list = tester.widget<ListView>(find.descendant(
          of: find.byType(FilterOverlay), matching: find.byType(ListView)));
      final scroll = list.controller!;
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      while (option.evaluate().isEmpty &&
          scroll.position.pixels < scroll.position.maxScrollExtent) {
        final before = scroll.position.pixels;
        scroll.jumpTo((before + scroll.position.viewportDimension)
            .clamp(0, scroll.position.maxScrollExtent));
        await tester.pumpAndSettle();
        expect(scroll.position.pixels, greaterThan(before));
      }
      expect(option, findsOneWidget);
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();
    }

    Future<void> expectCards(List<String> expected) async {
      if (expected.isEmpty) {
        expect(find.text('No games match these filters'), findsOneWidget);
        expect(find.byType(BaseGameCard), findsNothing);
        return;
      }
      // A real handheld lazily mounts only visible/cache-extent children.
      // Check the actual grid membership and traverse its real scroll positions,
      // rather than treating the currently mounted widgets as the whole result.
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(grid.childrenDelegate.estimatedChildCount, expected.length);
      final scroll = grid.controller!;
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      final seen = <String>[];
      void capture() {
        for (final card
            in tester.widgetList<BaseGameCard>(find.byType(BaseGameCard))) {
          expect(card.isRemoteAvailable, false,
              reason: 'Retired Web fixtures remain browsable history without '
                  'becoming executable download sources');
          expect(card.systemId, anyOf('psx', 'ps2'));
          expect(mediaFallbackAsset(card.systemId),
              endsWith('/systematic/${card.systemId}.png'));
        }
        for (final title in cards()) {
          if (!seen.contains(title)) seen.add(title);
        }
        for (final element in find.byType(BaseGameCard).evaluate()) {
          final card = element.widget as BaseGameCard;
          expect(
              find.descendant(
                  of: find.byWidget(card),
                  matching: find.byKey(const ValueKey('cover-rating'))),
              card.overallRating == null ? findsNothing : findsOneWidget);
        }
        final fallbackCount = tester
            .widgetList<BaseGameCard>(find.byType(BaseGameCard))
            .where((card) =>
                card.cachedUrl == null ||
                Uri.tryParse(card.cachedUrl!)?.scheme != 'file')
            .length;
        expect(
            find.descendant(
                of: find.byType(BaseGameCard),
                matching: find.byType(MediaCoverFallback)),
            findsNWidgets(fallbackCount),
            reason:
                'Offline Library and shelf cards retain physical-media art');
      }

      capture();
      while (scroll.position.pixels < scroll.position.maxScrollExtent) {
        final before = scroll.position.pixels;
        final next = before + scroll.position.viewportDimension;
        scroll.jumpTo(next.clamp(0, scroll.position.maxScrollExtent));
        await tester.pumpAndSettle();
        expect(scroll.position.pixels, greaterThan(before));
        capture();
      }
      expect(seen, expected);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-dashboard')), findsOneWidget);
    expect(metadataScopes.covers, isEmpty,
        reason: 'Dashboard metrics do not consume any game artwork');
    expect(metadataScopes.ratings, isEmpty,
        reason: 'Dashboard metrics do not need collection-wide game scores');
    expect(find.byType(BaseGameCard), findsNothing);
    expect(find.byKey(const ValueKey('console-summary-psx')), findsOneWidget);
    expect(find.byKey(const ValueKey('console-summary-ps2')), findsOneWidget);
    final summaries =
        tester.widgetList<LibraryConsoleCard>(find.byType(LibraryConsoleCard));
    expect(summaries.map((c) => c.summary.entries), [6, 6]);
    // Retired Web fixtures remain cached history, not downloadable sources.
    expect(summaries.map((c) => c.summary.unknownSourceSizes), [0, 0]);
    expect(summaries.map((c) => c.summary.installed), [1, 1]);
    expect(summaries.map((c) => c.summary.favorites), [1, 1]);
    expect(
        tester.getTopLeft(find.byKey(const ValueKey('library-dashboard'))).dy,
        greaterThanOrEqualTo(tester
            .getBottomLeft(find.byKey(const ValueKey('library-header')))
            .dy));
    if (factory == null) {
      for (final size in [const Size(640, 360), const Size(1280, 720)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(app(textScale: 1.3));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('library-dashboard')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      tester.view.physicalSize = const Size(1920, 1080);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
    }
    // A console's Top includes its sixth game, not only the five left after a
    // collection-wide Top 10. Selecting the dashboard never opens the ROM dump.
    await tester.tap(find.byKey(const ValueKey('console-summary-ps2')));
    await tester.pumpAndSettle();
    expect(find.text('Best 6 · A-Z'), findsOneWidget,
        reason: 'A sparse rated collection advertises only its actual prefix');
    final categories = find.byKey(const ValueKey('library-category-tabs'));
    await tester
        .tap(find.descendant(of: categories, matching: find.text('HACKS')));
    await tester.pumpAndSettle();
    await expectCards(['Game 02', 'Game 12']);
    await tester.tap(find.text('INSTALLED').first);
    await tester.pumpAndSettle();
    await expectCards(['Game 02']);
    await tester.ensureVisible(find.descendant(
        of: find.byKey(const ValueKey('library-status-tabs')),
        matching: find.text('ALL')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('library-status-tabs')),
        matching: find.text('ALL')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.descendant(of: categories, matching: find.text('COMMERCIAL')));
    await tester.pumpAndSettle();
    await expectCards(['Game 04', 'Game 06', 'Game 08', 'Game 10']);
    await tester
        .tap(find.descendant(of: categories, matching: find.text('ALL')));
    await tester.pumpAndSettle();
    await expectCards([
      for (var i = 2; i <= 12; i += 2) 'Game ${i.toString().padLeft(2, '0')}'
    ]);
    // Default browsing follows actual score changes, not the catalogue's A-Z
    // order or a fixed downloaded Top list. Fewer than 100 remains valid.
    final savedRating = (await db.query('library_metadata',
            columns: ['record_json'],
            where: 'edition_id = ?',
            whereArgs: [editions[10]]))
        .single['record_json'] as String;
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get ratings'));
    await tester.pumpAndSettle();
    final collector = tester
        .widget<MetadataSettingsScreen>(find.byType(MetadataSettingsScreen));
    expect(collector.systemSlug, 'ps2');
    expect(collector.ratingsOnly, isTrue);
    expect(controls.state.providerId, 'igdb');
    expect(igdb.calls, isEmpty,
        reason: 'Opening the scope never starts a scrape');
    await tester.tap(find.byKey(const ValueKey('metadata-refresh')));
    await controls.pause();
    if (controls.state.report!.state != 'completed') await controls.resume();
    expect(controls.state.error, isFalse);
    expect(igdb.calls.map((call) => call.platformId).toSet(), {'ps2'});
    expect(controls.state.artworkReport, isNull);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('metadata-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('metadata-back')));
    await tester.pumpAndSettle();
    expect(cards().first, 'Game 10',
        reason: 'Top-first order must beat alphabetical order');
    await store.putMetadata(MetadataRecord.fromJson({
      ...jsonDecode(savedRating) as Map<String, dynamic>,
      'refreshGeneration': controls.state.report!.generation
    }));
    container.read(gameDbChangedProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(cards().first, 'Game 02');
    expect(find.byKey(const ValueKey('library-media-preview')), findsOneWidget);
    final selectedMedia = factory == null
        ? find.descendant(
            of: find.byKey(const ValueKey('library-media-preview')),
            matching: find.byType(MediaCoverFallback))
        : find.byType(PhysicalMediaView);
    expect(selectedMedia, findsOneWidget,
        reason: 'Only the selected game gets a physical-media preview');
    if (factory != null) {
      expect(tester.widget<PhysicalMediaView>(selectedMedia).format,
          PhysicalMediaFormat.disc);
    } else {
      expect(tester.widget<MediaCoverFallback>(selectedMedia).systemId, 'ps2');
    }
    expect(find.byTooltip('Cover view'), findsNothing,
        reason:
            'Presentation controls belong in details, not over the preview');
    if (factory == null) {
      tester.view.physicalSize = const Size(832.5, 468.3);
      await tester.pumpAndSettle();
    }
    final previewHeight = tester
        .getSize(find.byKey(const ValueKey('library-media-preview')))
        .height;
    expect(tester.getSize(selectedMedia).height,
        greaterThanOrEqualTo(previewHeight * 0.5),
        reason: 'The selected object must retain half the Thor preview height');
    if (factory == null) {
      tester.view.physicalSize = const Size(1920, 1080);
      await tester.pumpAndSettle();
    }
    if (factory != null) {
      await container.read(mediaPresentationProvider.notifier).toggleMedia();
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('library-media-preview')), findsOneWidget);
      expect(find.byType(PhysicalMediaView), findsNothing,
          reason: 'Disabling imported 3D media keeps the default flat preview');
      await container.read(mediaPresentationProvider.notifier).toggleMedia();
      await tester.pumpAndSettle();
    }
    expect(metadataScopes.covers, ['ps2'],
        reason: 'Console browsing must not hash every console cover');
    expect(metadataScopes.ratings, ['ps2']);
    final evenGames = [
      for (var i = 2; i <= 12; i += 2) 'Game ${i.toString().padLeft(2, '0')}'
    ];
    await expectCards(evenGames);
    expect(find.text('Best 6 · A-Z'), findsOneWidget);
    expect(storage.getLibraryConsole(), 'ps2');
    await tester.tap(find.byIcon(Icons.filter_alt_rounded).first);
    await tester.pumpAndSettle();
    await tapFilter('discovery-top-10');
    await expectCards(evenGames);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await expectCards(evenGames);
    await tester.tap(find.text('INSTALLED').first);
    await tester.pumpAndSettle();
    await expectCards(['Game 02']);
    await tester.tap(find.text('FAVORITES').first);
    await tester.pumpAndSettle();
    await expectCards(['Game 02']);
    await tester.ensureVisible(find.descendant(
        of: find.byKey(const ValueKey('library-status-tabs')),
        matching: find.text('ALL')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('library-status-tabs')),
        matching: find.text('ALL')));
    await tester.pumpAndSettle();
    await expectCards(evenGames);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonY);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Game 04');
    await tester.pumpAndSettle();
    await expectCards(['Game 04']);
    container.read(gameDbChangedProvider.notifier).state++;
    await tester.pumpAndSettle();
    await expectCards(['Game 04']);
    // The existing SearchOverlay uses the first B to leave text entry and the
    // second B to close search; console navigation must preserve that control.
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing,
        reason: 'B closes console-scoped search');
    await tester.ensureVisible(find.text('MANUAL').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('MANUAL').first);
    await tester.pumpAndSettle();
    await expectCards(['Game 12']);
    await tester.ensureVisible(find.descendant(
        of: find.byKey(const ValueKey('library-status-tabs')),
        matching: find.text('ALL')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('library-status-tabs')),
        matching: find.text('ALL')));
    await tester.pumpAndSettle();
    // Up enters console navigation; Left selects PS1, then Dashboard. A/Down
    // returns to content, preserving L2/R2's existing status-tab behavior.
    tester
        .widgetList<BaseGameCard>(find.byType(BaseGameCard))
        .first
        .onTapSelect!();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LibraryTabs>(
                find.byKey(const ValueKey('library-console-tabs')))
            .focused,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(storage.getLibraryConsole(), 'psx');
    await expectCards([
      for (var i = 1; i <= 11; i += 2) 'Game ${i.toString().padLeft(2, '0')}'
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-dashboard')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LibraryTabs>(
                find.byKey(const ValueKey('library-console-tabs')))
            .focused,
        isFalse);
    await tester.tap(find.byIcon(Icons.filter_alt_rounded).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('one collection-wide limit'), findsOneWidget);
    // The existing panel owns controller navigation; select Best 10 with it.
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    await expectCards(firstGames(10));
    await checkpoint?.call('library-top-10-scope', tester);
    await tapFilter('discovery-top-25');
    await expectCards(firstGames(12));
    await tapFilter('discovery-top-10');
    await tapFilter('discovery-platform-psx');
    await expectCards(
        ['Game 01', 'Game 03', 'Game 05', 'Game 07', 'Game 09', 'Game 11']);
    await tapFilter('discovery-platform-ps2');
    await expectCards(firstGames(10));
    for (final scope in ['psx', 'ps2']) {
      await tapFilter('discovery-platform-$scope');
    }
    await expectCards(firstGames(10));
    await tapFilter('discovery-tag-Hack');
    await expectCards(['Game 01']);
    for (final tag in ['T-Eng', 'Dub', 'Undub', 'Uncensor']) {
      await tapFilter('discovery-tag-$tag');
    }
    await expectCards(['Game 01', 'Game 02', 'Game 03']);
    // Query facets are canonical lowercase values; UI keys retain that value.
    await tapFilter('discovery-genre-action');
    await expectCards(['Game 01', 'Game 02', 'Game 03']);
    await checkpoint?.call('library-independent-tags-any', tester);
    await tapFilter('discovery-match');
    await expectCards([]);
    for (final tag in ['Dub', 'Undub']) {
      await tapFilter('discovery-tag-$tag');
    }
    await expectCards(['Game 01']);
    await checkpoint?.call('library-independent-tags-all', tester);
    for (final tag in ['T-Eng', 'Uncensor']) {
      await tapFilter('discovery-tag-$tag');
    }
    await tapFilter('discovery-match');
    await tapFilter('discovery-genre-action');
    expect(jsonDecode(storage.getFilters('library:all')!)['top'], 10);
    final original = (await store.metadata(editions[1]!, 'igdb'))!;
    await store.putMetadata(MetadataRecord.fromJson({
      ...original.toJson(),
      'refreshGeneration': 2,
      'ratings': original.ratings
          .map((r) => {
                ...r.toJson(),
                'rawValue': '1',
              })
          .toList()
    }));
    container.read(gameDbChangedProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(cards(), isEmpty);
    expect(find.text('No games match these filters'), findsOneWidget);
    await store.putMetadata(MetadataRecord.fromJson(
        {...original.toJson(), 'refreshGeneration': 3}));
    container.read(gameDbChangedProvider.notifier).state++;
    container.read(gameDbChangedProvider.notifier).state++;
    await tester.pumpAndSettle();
    await expectCards(['Game 01']);
    // Close the real panel, then select the real manual shelf tab.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('MANUAL').first);
    await tester.pumpAndSettle();
    await expectCards(['Game 09', 'Game 01', 'Game 12']);
    await checkpoint?.call('library-manual-shelf', tester);
    tester
        .widgetList<BaseGameCard>(find.byType(BaseGameCard))
        .singleWhere((c) => c.displayName == 'Game 09')
        .onTapSelect!();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.filter_alt_rounded).first);
    await tester.pumpAndSettle();
    await tapFilter('discovery-top-10');
    await expectCards(['Game 09', 'Game 01']);
    await tapFilter('discovery-order');
    await expectCards(['Game 01', 'Game 09']);
    expect(
        tester
            .widgetList<BaseGameCard>(find.byType(BaseGameCard))
            .singleWhere((c) => c.displayName == 'Game 09')
            .isSelected,
        isTrue);
    expect(storage.getCustomShelves().single.manualGameIds,
        ['Game 09.7z', 'Game 01.7z', 'Game 12.7z']);
    await checkpoint?.call('library-explicit-rating-order', tester);
    expect(jsonDecode(storage.getFilters('library:all')!)['tags'], ['Hack']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(await db.query('library_query_views'), isEmpty);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-dashboard')), findsOneWidget);
    // Existing global filters remain saved, but reopening the global view is
    // a dashboard until the user explicitly opens their filtered shortlist.
    await tester.tap(find.byIcon(Icons.filter_alt_rounded).first);
    await tester.pumpAndSettle();
    await expectCards(['Game 01']);
    await checkpoint?.call('library-restored-filters', tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonX);
    await tester.pumpAndSettle();
    // Unrated catalogue members stay browsable but never acquire a fabricated
    // overlay/rank, even when a sparse Top has room for them.
    final last = (await store.metadata(editions[12]!, 'igdb'))!;
    await store.putMetadata(MetadataRecord.fromJson(
        {...last.toJson(), 'refreshGeneration': 4, 'ratings': <Object>[]}));
    container.read(gameDbChangedProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-dashboard')), findsOneWidget);
    await tapFilter('discovery-top-25');
    await expectCards(firstGames(11));
    for (var i = 1; i <= 11; i++) {
      final record = (await store.metadata(editions[i]!, 'igdb'))!;
      await store.putMetadata(MetadataRecord.fromJson(
          {...record.toJson(), 'refreshGeneration': 4, 'ratings': <Object>[]}));
    }
    container.read(gameDbChangedProvider.notifier).state++;
    await tester.pumpAndSettle();
    await expectCards([]);
    await checkpoint?.call('library-unrated-top-empty', tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonX);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-dashboard')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('PS2').first);
    await tester.pumpAndSettle();
    // Console filters are independently remembered: clear its saved Top and
    // verify unrated games remain browsable without invented scores.
    await tester.tap(find.byIcon(Icons.filter_alt_rounded).first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonX);
    await tester.pumpAndSettle();
    await expectCards(evenGames);
    expect(find.text('A-Z · Needs a fresh rating'), findsOneWidget);
    await checkpoint?.call('library-unrated-browsable', tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
