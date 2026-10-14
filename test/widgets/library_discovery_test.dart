import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/features/library/library_screen.dart';
import 'package:retro_eshop/core/widgets/animated_background.dart';
import 'package:retro_eshop/features/library/widgets/library_tabs.dart';
import 'package:retro_eshop/features/library/widgets/library_dashboard.dart';
import 'package:retro_eshop/features/game_list/widgets/filter_overlay.dart';
import 'package:retro_eshop/models/config/app_config.dart';
import 'package:retro_eshop/models/config/provider_config.dart';
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
import 'package:retro_eshop/widgets/physical_media_view.dart';
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
    SharedPreferences.setMockInitialValues(
        {'physical_media_reduced_motion': true});
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
    final container = ProviderContainer(observers: [
      metadataScopes
    ], overrides: [
      libraryDbProvider.overrideWithValue(_Database(db)),
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
          expect(card.isRemoteAvailable, card.displayName != 'Game 12',
              reason: 'Library and shelf badges must use the entry source, '
                  'not assume every cached game is downloadable');
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
        expect(find.byType(MediaCoverFallback), findsNWidgets(fallbackCount),
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
    expect(summaries.map((c) => c.summary.unknownSourceSizes), [6, 5]);
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
    expect(find.text('Best 100 · A-Z'), findsOneWidget);
    // Default browsing follows actual score changes, not the catalogue's A-Z
    // order or a fixed downloaded Top list. Fewer than 100 remains valid.
    final savedRating = (await db.query('library_metadata',
            columns: ['record_json'],
            where: 'edition_id = ?',
            whereArgs: [editions[10]]))
        .single['record_json'] as String;
    final changedRating = jsonDecode(savedRating) as Map<String, dynamic>;
    (changedRating['ratings'] as List).first['rawValue'] = 99.5;
    await store.putMetadata(MetadataRecord.fromJson(changedRating));
    container.read(gameDbChangedProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(cards().first, 'Game 10',
        reason: 'Top-first order must beat alphabetical order');
    await store.putMetadata(MetadataRecord.fromJson(jsonDecode(savedRating)));
    container.read(gameDbChangedProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(cards().first, 'Game 02');
    expect(find.byKey(const ValueKey('library-media-preview')), findsOneWidget);
    expect(find.byType(PhysicalMediaView), findsOneWidget,
        reason: 'Only the selected game gets an animated media object');
    expect(
        tester.widget<PhysicalMediaView>(find.byType(PhysicalMediaView)).format,
        PhysicalMediaFormat.disc);
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
    expect(tester.getSize(find.byType(PhysicalMediaView)).height,
        greaterThanOrEqualTo(previewHeight * 0.5),
        reason: 'The selected object must retain half the Thor preview height');
    if (factory == null) {
      tester.view.physicalSize = const Size(1920, 1080);
      await tester.pumpAndSettle();
    }
    await container.read(mediaPresentationProvider.notifier).toggleMedia();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-media-preview')), findsNothing);
    await container.read(mediaPresentationProvider.notifier).toggleMedia();
    await tester.pumpAndSettle();
    expect(metadataScopes.covers, ['ps2'],
        reason: 'Console browsing must not hash every console cover');
    expect(metadataScopes.ratings, ['ps2']);
    final evenGames = [
      for (var i = 2; i <= 12; i += 2) 'Game ${i.toString().padLeft(2, '0')}'
    ];
    await expectCards(evenGames);
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
    await tester.tap(find.text('ALL').first);
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
    await tester.tap(find.text('MANUAL').first);
    await tester.pumpAndSettle();
    await expectCards(['Game 12']);
    await tester.tap(find.text('ALL').first);
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
    await checkpoint?.call('library-unrated-browsable', tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
