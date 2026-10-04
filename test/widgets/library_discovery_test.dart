import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/features/library/library_screen.dart';
import 'package:retro_eshop/features/game_list/widgets/filter_overlay.dart';
import 'package:retro_eshop/models/config/app_config.dart';
import 'package:retro_eshop/models/custom_shelf.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/providers/game_providers.dart';
import 'package:retro_eshop/providers/installed_files_provider.dart';
import 'package:retro_eshop/providers/library_providers.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/device_info_service.dart';
import 'package:retro_eshop/services/config_storage_service.dart';
import 'package:retro_eshop/services/sources_notifier.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/services/storage_service.dart';
import 'package:retro_eshop/widgets/base_game_card.dart';
import 'package:retro_eshop/widgets/media_cover_fallback.dart';
import '../helpers/pump_helpers.dart';

class _Database extends DatabaseService {
  final Database db;
  _Database(this.db);
  @override
  Future<Database> get database async => db;
}

class _Config extends ConfigStorageService {
  @override
  Future<AppConfig?> loadConfig() async => AppConfig.empty;
}

void main() {
  defineLibraryDiscoveryChecks();
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
      artifact_key TEXT, remote_artifact TEXT, is_folder INTEGER DEFAULT 0)''');
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
        'url': 'https://example.invalid/$i'
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
        'tags': [i == 1 || i == 12 ? 'Hack' : 'official']
      }));
      await store.putMetadata(MetadataRecord(
          gameId: game.id,
          editionId: id,
          platformId: platform,
          providerId: 'igdb',
          providerGameId: '$i',
          retrievedAt: at,
          refreshGeneration: 1,
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
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.setCustomShelves([
      CustomShelf(
          id: 'manual',
          name: 'Manual',
          manualGameIds: ['Game 09.7z', 'Game 01.7z', 'Game 12.7z'],
          sortMode: ShelfSortMode.manual,
          createdAt: at)
    ]);
    final container = ProviderContainer(overrides: [
      libraryDbProvider.overrideWithValue(_Database(db)),
      storageServiceProvider.overrideWithValue(storage),
      bootstrappedConfigProvider.overrideWith((ref) async => AppConfig.empty),
      installedFilesProvider
          .overrideWith((ref) async => const InstalledFilesState()),
      deviceMemoryProvider.overrideWithValue(
          const DeviceMemoryInfo(totalBytes: 0, tier: MemoryTier.standard)),
      sourcesProvider
          .overrideWith((ref) => SourcesNotifier(_Config(), db: _Database(db))),
    ]);
    addTearDown(container.dispose);
    Widget app() => UncontrolledProviderScope(
        container: container, child: createTestApp(const LibraryScreen()));
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
          expect(card.systemId, anyOf('psx', 'ps2'));
          expect(mediaFallbackAsset(card.systemId),
              endsWith('/systematic/${card.systemId}.png'));
        }
        for (final title in cards()) {
          if (!seen.contains(title)) seen.add(title);
        }
        expect(find.byKey(const ValueKey('cover-rating')),
            findsNWidgets(cards().length));
        expect(find.byType(MediaCoverFallback), findsNWidgets(cards().length),
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
    await container.read(cachedCoverRatingsProvider('').future);
    await tester.pumpAndSettle();
    await expectCards(firstGames(12));
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
    await expectCards(['Game 01']);
    await checkpoint?.call('library-restored-filters', tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
