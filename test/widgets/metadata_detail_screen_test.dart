import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/features/game_detail/game_detail_screen.dart';
import 'package:retro_eshop/core/theme/app_theme.dart';
import 'package:retro_eshop/l10n/app_localizations.dart';
import 'package:retro_eshop/models/config/app_config.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/game_metadata_info.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/providers/game_providers.dart';
import 'package:retro_eshop/providers/library_providers.dart';
import 'package:retro_eshop/providers/metadata_providers.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/services/storage_service.dart';
import 'package:retro_eshop/services/input_debouncer.dart';
import '../metadata_controls_test.dart' show MemorySecrets, ControlsProvider;

class _Database extends DatabaseService {
  final Database db;
  final ready = Completer<void>();
  bool fail = false;
  _Database(this.db);

  @override
  Future<Database> get database async => db;

  @override
  Future<GameMetadataInfo?> getGameMetadata(String filename, String systemSlug,
      {String language = 'en', MetadataArtworkCache? artworkCache}) async {
    await ready.future;
    if (fail) throw StateError('Synthetic cache read failure');
    return super.getGameMetadata(filename, systemSlug,
        language: language, artworkCache: artworkCache);
  }
}

/// Host frames run faster than a human's input cadence. The owning debounce
/// uses real DateTime (not Flutter's fake clock); this fixture checks routing,
/// not that independent cooldown contract. Native proof retains real debounce.
class _HostInput extends InputDebouncer {
  @override
  bool canPerformAction() => true;
}

void main() {
  // The normal reader now joins shared-cache readiness and real filesystem IO.
  // Keep its futures and UI in one real clock, as in the Android fixture.
  LiveTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  final previousPaths = PathProviderPlatform.instance;
  final previousFontFetching = GoogleFonts.config.allowRuntimeFetching;
  setUpAll(() async {
    final support = Platform.environment['RSHOP_TEST_FONT_CACHE'];
    if (support == null || !await Directory(support).exists()) {
      throw StateError('RSHOP_TEST_FONT_CACHE must identify the existing font cache');
    }
    PathProviderPlatform.instance = _DetailHostPaths(support);
    GoogleFonts.config.allowRuntimeFetching = false;
    AppTheme.darkTheme;
    await GoogleFonts.pendingFonts();
  });
  tearDownAll(() {
    PathProviderPlatform.instance = previousPaths;
    GoogleFonts.config.allowRuntimeFetching = previousFontFetching;
  });
  defineMetadataDetailScreenChecks();
}

class _DetailHostPaths extends PathProviderPlatform {
  final String support;
  _DetailHostPaths(this.support);
  @override
  Future<String?> getApplicationSupportPath() async => support;
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

/// The normal detail screen/provider/cache path, reused with Android SQLite.
/// No production bootstrap, credentials, provider account or ROM is involved.
void defineMetadataDetailScreenChecks({
  DatabaseFactory? factory,
  bool native = false,
  Future<void> Function(String name, WidgetTester tester)? checkpoint,
}) {
  for (final size in [
    if (native) null,
    if (!native) ...[
      const Size(1920, 1080),
      const Size(1280, 720),
      const Size(720, 1280)
    ],
  ]) {
    testWidgets(
        'normal details show exact cached score and retry a failed read ($size)',
        (tester) async {
      if (size != null) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      if (factory == null) sqfliteFfiInit();
      final db = await (factory ?? databaseFactoryFfiNoIsolate)
          .openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await LibrarySchema.install(db);
      await MetadataRefreshJobs.install(db);
      await db.execute('''CREATE TABLE games(id INTEGER PRIMARY KEY,
      systemSlug TEXT, displayName TEXT, filename TEXT, url TEXT,
      artifact_key TEXT, remote_artifact TEXT, is_folder INTEGER DEFAULT 0)''');
      await LibraryQuery.install(db);
      await db.insert('games', {
        'id': 1,
        'systemSlug': 'psx',
        'displayName': 'Game',
        'filename': 'Game.7z',
        'url': 'https://example.invalid/game'
      });
      final store = LibraryStore(Future.value(db));
      final editionId = (await db.transaction((txn) =>
              LibraryStore.catalogueEditions(txn, cacheRowId: 1).toList()))
          .single;
      final edition = (await store.edition(editionId))!;
      final gameIdentity = (await store.game(edition.gameId))!;
      await store.putGame(GameIdentity.fromJson({
        ...gameIdentity.toJson(),
        'matchStatus': 'manuallyMatched',
        'providerIds': {'igdb': '1'}
      }));
      await store.putEdition(EditionIdentity.fromJson({
        ...edition.toJson(),
        'tags': ['official']
      }));
      final at = DateTime.utc(2026, 10, 3);
      await store.putMetadata(MetadataRecord(
          gameId: gameIdentity.id,
          editionId: editionId,
          platformId: 'psx',
          providerId: 'igdb',
          providerGameId: '1',
          retrievedAt: at,
          refreshGeneration: 1,
          matchMethod: 'verifiedProviderIdGlobalGame',
          titles: const [
            MetadataText(text: 'Game')
          ],
          descriptions: const [
            MetadataText(text: 'Cached description')
          ],
          fieldProvenance: {
            'description': MetadataFieldProvenance(
                providerId: 'igdb',
                providerGameId: '1',
                field: 'description',
                retrievedAt: at)
          },
          ratings: [
            SourcedRating.parse(
                sourceId: 'igdb',
                sourceLabel: 'IGDB users',
                providerGameId: '1',
                rawValue: 89,
                scaleMinimum: 0,
                scaleMaximum: 100,
                voteCount: 100,
                kind: RatingKind.communityAggregate,
                retrievedAt: at)!
          ]));
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final database = _Database(db);
      final secrets = MemorySecrets();
      final controls = MetadataControlsController(
          database: Future.value(db),
          providers: {
            'screenscraper': ControlsProvider(),
            'igdb': ControlsProvider('igdb')
          },
          screenScraperCredentials:
              ScreenScraperCredentialStore(storage: secrets),
          igdbCredentials: IgdbCredentialStore(storage: secrets),
          catalogueChanged: () {});
      await controls.load();
      final container = ProviderContainer(overrides: [
        if (!native) inputDebouncerProvider.overrideWith((_) => _HostInput()),
        libraryDbProvider.overrideWithValue(database),
        // This fixture has no image bodies. Keep its real empty artwork index
        // isolated instead of opening the host's normal application directory.
        metadataArtworkCacheProvider.overrideWithValue(Future.value(
            MetadataArtworkCache(Future.value(db),
                Directory(native
                    ? '/data/local/tmp/rshop-detail-no-artwork'
                    : 'D:/Temp/rshop-detail-no-artwork')))),
        storageServiceProvider.overrideWithValue(storage),
        bootstrappedConfigProvider.overrideWith((ref) async => AppConfig.empty),
        metadataControlsProvider.overrideWith((_) => controls),
      ]);
      addTearDown(container.dispose);
      final game = GameItem(
          filename: 'Game.7z',
          displayName: 'Game',
          url: 'https://example.invalid/game');
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: AppTheme.darkTheme,
              localizationsDelegates: L.localizationsDelegates,
              supportedLocales: L.supportedLocales,
              home: Scaffold(
                  body: GameDetailScreen(
                      game: game,
                      variants: [game],
                      system: SystemModel.supportedSystems
                          .firstWhere((s) => s.id == 'psx'),
                      targetFolder: native
                          ? '/data/local/tmp/rshop-no-installed-ROM'
                          : 'D:/Temp/rshop-no-installed-ROM')))));
      final cachedMetadata = gameMetadataProvider(
          (filename: game.selectionKey, systemSlug: 'psx'));
      Future<void> finishCacheRead({bool failed = false}) async {
        // Join cache IO before settling frames; animation completion is not
        // a metadata-read signal on either the host or Android.
        final operation = container.read(cachedMetadata.future);
        if (failed) {
          await expectLater(operation, throwsStateError);
        } else {
          await operation;
        }
        await tester.pumpAndSettle();
      }

      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      database.ready.complete();
      await finishCacheRead();
      expect(find.textContaining('IGDB users 89/100'), findsOneWidget);
      expect(find.textContaining('Avg Rating'), findsNothing);
      await checkpoint?.call('detail-cached-score', tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Game Info'));
      await tester.pumpAndSettle();
      expect(find.textContaining('IGDB users: 89/100'), findsOneWidget);
      expect(find.textContaining('100'), findsWidgets);
      expect(find.textContaining('igdb #1'), findsOneWidget);
      expect(find.text('Official releases'), findsOneWidget);
      await checkpoint?.call('detail-score-provenance', tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      database.fail = true;
      container.read(gameDbChangedProvider.notifier).state++;
      await finishCacheRead(failed: true);
      expect(
          find.text(
              'Cached metadata is unavailable. ROM actions remain available.'),
          findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await checkpoint?.call('detail-cache-error', tester);
      database.fail = false;
      await tester.tap(find.text('Retry'));
      await finishCacheRead();
      expect(find.textContaining('IGDB users 89/100'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
      await tester.pumpAndSettle();
      expect(find.text('Game metadata'), findsOneWidget,
          reason: 'Retry -> Start must open metadata actions; '
              'focus=${FocusManager.instance.primaryFocus}, '
              'priority=${container.read(overlayPriorityProvider)}');
      await tester.tap(find.text('Game metadata'));
      await tester.pumpAndSettle();
      expect(find.text('Selected game: Game'), findsOneWidget);
      expect(find.byKey(const ValueKey('metadata-scope')), findsNothing);
      await checkpoint?.call('detail-exact-game-controls', tester);
      final refresh = find.byKey(const ValueKey('metadata-refresh'));
      await tester.ensureVisible(refresh);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(refresh).onPressed, isNotNull);
      final completed = Completer<void>();
      final removeListener = controls.addListener((state) {
        if (!state.busy &&
            state.report?.state == 'completed' &&
            !completed.isCompleted) {
          completed.complete();
        }
      });
      try {
        // Wait for the actual durable job transition. Pausing immediately after
        // a tap changes the workflow and frame settling does not join SQLite IO.
        await tester.tap(refresh);
        expect(controls.state.busy, isTrue,
            reason: 'The visible refresh button must start the owning job');
        await completed.future;
      } finally {
        removeListener();
      }
      await tester.pumpAndSettle();
      expect(controls.state.report!.counts, {'unmatched': 1});
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await controls.close();
      expect(tester.takeException(), isNull);
    });
  }
}
