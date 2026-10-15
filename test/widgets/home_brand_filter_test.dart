import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_eshop/features/home/home_view.dart';
import 'package:retro_eshop/features/settings/metadata_settings_screen.dart';
import 'package:retro_eshop/providers/metadata_providers.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/features/home/widgets/hero_carousel_item.dart';
import 'package:retro_eshop/models/config/app_config.dart';
import 'package:retro_eshop/models/config/system_config.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/providers/download_providers.dart';
import 'package:retro_eshop/providers/game_providers.dart';
import 'package:retro_eshop/services/audio_manager.dart';
import 'package:retro_eshop/services/storage_service.dart';
import 'package:retro_eshop/services/library_sync_service.dart';
import 'package:retro_eshop/providers/library_providers.dart';
import 'package:retro_eshop/core/input/input.dart';
import 'package:retro_eshop/widgets/sync_badge.dart';
import 'package:retro_eshop/providers/ra_providers.dart';
import 'package:retro_eshop/features/home/widgets/manufacturer_filter.dart';
import 'package:retro_eshop/features/home/widgets/home_grid_view.dart';
import '../helpers/pump_helpers.dart';
import '../metadata_controls_test.dart'
    show controlsDatabase, MemorySecrets, ControlsProvider;

class _SilentAudio extends AudioManager {
  @override
  Future<void> startBgm() async {}
}

class _RecordingSync extends LibrarySyncService {
  AppConfig? received;
  _RecordingSync({bool active = false}) {
    if (active) {
      state = const LibrarySyncState(
          isSyncing: true,
          totalSystems: 40,
          currentSystem: 'Nintendo GameCube',
          phase: LibrarySyncPhase.updatingGames,
          processedGames: 100,
          currentGamesTotal: 250);
    }
  }
  @override
  Future<void> syncAll(AppConfig config,
      {Duration? syncTimeout, StorageService? storageService}) async {
    received = config;
  }
}

void main() {
  testWidgets(
      'home scraping scopes use the collector without automatic requests',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final systems = SystemModel.supportedSystems
        .where((s) => ['nes', 'snes', 'psp'].contains(s.id))
        .toList();
    final config = AppConfig(systems: [
      for (final s in systems)
        SystemConfig(
            id: s.id,
            name: s.name,
            targetFolder: '/${s.id}',
            providers: const [],
            autoSync: false)
    ]);
    final db = (await tester.runAsync(controlsDatabase))!;
    final provider = ControlsProvider();
    final controls = (await tester.runAsync(() async {
      await db.update('games', {'systemSlug': 'nes'}, where: 'id = 1');
      await db.update('games', {'systemSlug': 'snes'}, where: 'id = 2');
      await db.insert('games', {
        'id': 3,
        'systemSlug': 'psp',
        'displayName': 'Game 3',
        'filename': 'Game 3.iso',
        'url': 'https://example.invalid/3'
      });
      final controls = MetadataControlsController(
          database: Future.value(db),
          providers: {'screenscraper': provider},
          screenScraperCredentials:
              ScreenScraperCredentialStore(storage: MemorySecrets()),
          igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
          catalogueChanged: () {});
      await controls.load();
      return controls;
    }))!;
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      visibleSystemsProvider.overrideWith((ref) async => systems),
      bootstrappedConfigProvider.overrideWith((ref) async => config),
      librarySyncServiceProvider.overrideWith((ref) => _RecordingSync()),
      hasQueueItemsProvider.overrideWithValue(false),
      audioManagerProvider.overrideWithValue(_SilentAudio()),
      systemSourceCountsProvider.overrideWith((ref) async => {}),
      metadataControlsProvider.overrideWith((_) => controls),
    ]);
    addTearDown(() async {
      await tester.runAsync(controls.close);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      container.dispose();
      await tester.runAsync(db.close);
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: createTestApp(const HomeView())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('brand-Nintendo')));
    await tester.pumpAndSettle();
    for (final scope in [
      'Scrape this console',
      'Scrape Nintendo',
      'Scrape all'
    ]) {
      final before = provider.calls.length;
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Sync'), findsOneWidget);
      expect(find.text('Scrape Nintendo'), findsNothing);
      await tester.tap(find.text('Scrape'));
      await tester.pumpAndSettle();
      expect(find.text('Scrape this console'), findsOneWidget);
      expect(find.text('Scrape Nintendo'), findsOneWidget);
      expect(find.text('Scrape all'), findsOneWidget);
      await tester.tap(find.text(scope));
      await tester.pumpAndSettle();
      expect(find.byType(MetadataSettingsScreen), findsOneWidget);
      expect(provider.calls.length, before);
      final route = tester
          .widget<MetadataSettingsScreen>(find.byType(MetadataSettingsScreen));
      expect(route.openCollector, isTrue);
      expect(route.systemSlug, scope == 'Scrape this console' ? 'nes' : null);
      expect(route.systemSlugs,
          scope == 'Scrape Nintendo' ? ['nes', 'snes'] : null);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('metadata-refresh')));
        await controls.pause();
        if (controls.state.report!.state != 'completed') {
          await controls.resume();
        }
      });
      await tester.pumpAndSettle();
      expect(controls.state.error, isFalse);
      expect(
          provider.calls.skip(before).map((call) => call.platformId).toSet(),
          scope == 'Scrape this console'
              ? {'nes'}
              : scope == 'Scrape Nintendo'
                  ? {'nes', 'snes'}
                  : {'nes', 'snes', 'psp'});
      await tester.tap(find.byKey(const ValueKey('metadata-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('metadata-back')));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(320, 568), const Size(832, 468)]) {
    testWidgets(
        'grid filters preserve selection and avoid the sync popup at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'home_layout': true});
      FlutterSecureStorage.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final systems = SystemModel.supportedSystems
          .where((s) => ['nes', 'snes', 'psp', 'megadrive'].contains(s.id))
          .toList();
      final captureKey = GlobalKey();
      await tester.pumpWidget(createTestAppWithProviders(
          RepaintBoundary(
              key: captureKey,
              child: const Stack(children: [HomeView(), SyncBadge()])),
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            visibleSystemsProvider.overrideWith((ref) async => systems),
            bootstrappedConfigProvider
                .overrideWith((ref) async => AppConfig.empty),
            librarySyncServiceProvider
                .overrideWith((ref) => _RecordingSync(active: true)),
            raEnabledProvider.overrideWithValue(false),
            systemSourceCountsProvider.overrideWith((ref) async => {}),
            hasQueueItemsProvider.overrideWithValue(false),
            audioManagerProvider.overrideWithValue(_SilentAudio()),
          ]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final strip =
          tester.getRect(find.byKey(const ValueKey('manufacturer-filter')));
      final popup =
          tester.getRect(find.byKey(const ValueKey('console-game-progress')));
      expect(strip.overlaps(popup), isFalse);
      await tester.ensureVisible(find.byKey(const ValueKey('brand-Nintendo')));
      await tester.tap(find.byKey(const ValueKey('brand-Nintendo')));
      await tester.pump(const Duration(milliseconds: 400));
      var grid = tester.widget<HomeGridView>(find.byType(HomeGridView));
      expect(grid.systems.map((s) => s.id), ['nes', 'snes']);
      expect(grid.systems[grid.selectedIndex].id, 'nes');
      final evidenceRoot = Platform.environment['RSHOP_UI_EVIDENCE_ROOT'];
      if (evidenceRoot != null) {
        await tester.runAsync(() async {
          for (final brand in ['Nintendo', 'Sega', 'Sony']) {
            await precacheImage(
                AssetImage(
                    'assets/brand_logos/${manufacturerLogos[brand]}.png'),
                tester.element(find.byType(ManufacturerFilter)));
          }
        });
        await tester.pump();
        await tester.runAsync(() async {
          final boundary = captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final frame = await boundary.toImage(pixelRatio: 1);
          final data = await frame.toByteData(format: ui.ImageByteFormat.png);
          await Directory(evidenceRoot).create(recursive: true);
          await File(
                  '$evidenceRoot/brands-${size.width.toInt()}x${size.height.toInt()}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          frame.dispose();
        });
      }
      await tester.ensureVisible(find.text('Nintendo · 1990'));
      await tester.tap(find.text('Nintendo · 1990'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.byKey(const ValueKey('brand-All')));
      await tester.tap(find.byKey(const ValueKey('brand-All')));
      await tester.pump(const Duration(milliseconds: 400));
      grid = tester.widget<HomeGridView>(find.byType(HomeGridView));
      expect(grid.systems, hasLength(4));
      expect(grid.systems[grid.selectedIndex].id, 'snes');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
  testWidgets('brand logos filter carousel and All restores consoles',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final systems = SystemModel.supportedSystems
        .where((s) => ['nes', 'psp', 'megadrive'].contains(s.id))
        .toList();
    final config = AppConfig(systems: [
      for (final s in systems)
        SystemConfig(
            id: s.id,
            name: s.name,
            targetFolder: '/${s.id}',
            providers: const [],
            autoSync: false)
    ]);
    final sync = _RecordingSync();
    await tester
        .pumpWidget(createTestAppWithProviders(const HomeView(), overrides: [
      storageServiceProvider.overrideWithValue(storage),
      visibleSystemsProvider.overrideWith((ref) async => systems),
      bootstrappedConfigProvider.overrideWith((ref) async => config),
      librarySyncServiceProvider.overrideWith((ref) => sync),
      hasQueueItemsProvider.overrideWithValue(false),
      audioManagerProvider.overrideWithValue(_SilentAudio()),
      systemSourceCountsProvider.overrideWith((ref) async => {}),
    ]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('manufacturer-filter')), findsOneWidget);
    expect(find.byKey(const ValueKey('brand-Sega')), findsOneWidget);
    expect(find.byKey(const ValueKey('brand-Microsoft')), findsNothing);
    final homeFocus = tester
        .widgetList<Focus>(find.byType(Focus))
        .map((focus) => focus.focusNode)
        .whereType<FocusNode>()
        .firstWhere((node) => node.debugLabel == 'Screen_home');
    homeFocus.requestFocus();
    await tester.pump();
    final filterContext = tester.element(find.byType(ManufacturerFilter));
    Actions.invoke(filterContext, const NavigateIntent(GridDirection.up));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.nearestScope?.debugLabel,
        'Manufacturer filter');
    Actions.invoke(filterContext, const NavigateIntent(GridDirection.right));
    await tester.pump();
    Actions.invoke(filterContext, const ConfirmIntent());
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ManufacturerFilter>(find.byType(ManufacturerFilter))
            .selected,
        'Nintendo');
    Actions.invoke(filterContext, const NavigateIntent(GridDirection.down));
    await tester.pump();
    expect(homeFocus.hasPrimaryFocus, isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('brand-Sega')));
    await tester.tap(find.byKey(const ValueKey('brand-Sega')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<HeroCarouselItem>(find.byType(HeroCarouselItem))
            .every((item) => item.system.manufacturer == 'Sega'),
        isTrue);
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync'));
    await tester.pumpAndSettle();
    expect(find.text('Sync Sega'), findsOneWidget);
    await tester.tap(find.text('Sync Sega'));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(sync.received?.systems.map((s) => s.id), ['megadrive']);
    expect(config.systems, hasLength(3));
    await tester.ensureVisible(find.byKey(const ValueKey('brand-All')));
    await tester.tap(find.byKey(const ValueKey('brand-All')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ManufacturerFilter>(find.byType(ManufacturerFilter))
            .selected,
        isNull);
    expect(
        tester
            .widgetList<HeroCarouselItem>(find.byType(HeroCarouselItem))
            .any((item) => item.system.manufacturer != 'Sega'),
        isTrue);
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync'));
    await tester.pumpAndSettle();
    expect(find.text('Sync Sega'), findsNothing);
    expect(find.text('Sync All'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Scrape'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
