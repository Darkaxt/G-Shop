import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/core/theme/app_theme.dart';
import 'package:retro_eshop/features/game_list/game_list_screen.dart';
import 'package:retro_eshop/features/game_list/widgets/filter_overlay.dart';
import 'package:retro_eshop/features/game_list/widgets/game_grid.dart';
import 'package:retro_eshop/l10n/app_localizations.dart';
import 'package:retro_eshop/models/config/app_config.dart';
import 'package:retro_eshop/models/config/drive_source_config.dart';
import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/models/config/system_config.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/providers/game_providers.dart';
import 'package:retro_eshop/providers/installed_files_provider.dart';
import 'package:retro_eshop/providers/library_providers.dart';
import 'package:retro_eshop/providers/metadata_cloud_providers.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/config_storage_service.dart';
import 'package:retro_eshop/services/device_info_service.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';
import 'package:retro_eshop/services/drive/drive_catalogue.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/services/providers/drive_provider.dart';
import 'package:retro_eshop/services/storage_service.dart';
import 'package:retro_eshop/services/sources_notifier.dart';
import 'package:retro_eshop/widgets/base_game_card.dart';
import 'package:retro_eshop/widgets/media_cover_fallback.dart';

void main() => defineConsoleDiscoveryChecks();

class _Config extends ConfigStorageService {
  final AppConfig config;
  _Config(this.config);
  @override
  Future<AppConfig?> loadConfig() async => config;
}

/// Normal console screen/controller/provider/cache/query/card path. Only platform
/// preferences and the catalogue's external file listing are synthetic. Native
/// callers supply Android SQLite and actual display metrics; no user bootstrap.
void defineConsoleDiscoveryChecks({
  DatabaseFactory? factory,
  Future<void> Function(String name, WidgetTester tester)? checkpoint,
  void Function(int blockedCoverAttempts)? reportNetwork,
}) {
  testWidgets(
      'console Top, tags and covers share cache-only discovery semantics',
      (tester) async {
    if (factory == null) {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      sqfliteFfiInit();
    }
    final offline = ConsoleOfflineRequests();
    final previous = HttpOverrides.current;
    HttpOverrides.global = offline;
    addTearDown(() => HttpOverrides.global = previous);
    final db = await (factory ?? databaseFactoryFfiNoIsolate)
        .openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    DatabaseService.testDatabase = db;
    addTearDown(DatabaseService.resetForTesting);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await DriveCatalogueSchema.install(db);
    await db.execute('''CREATE TABLE games(id INTEGER PRIMARY KEY AUTOINCREMENT,
      systemSlug TEXT NOT NULL, filename TEXT NOT NULL, displayName TEXT NOT NULL,
      url TEXT NOT NULL, region TEXT, cover_url TEXT, provider_config TEXT,
      thumb_hash TEXT, has_thumbnail INTEGER NOT NULL DEFAULT 0,
      is_folder INTEGER NOT NULL DEFAULT 0, alternative_sources TEXT,
      artifact_key TEXT, remote_artifact TEXT)''');
    await db.execute('''CREATE UNIQUE INDEX games_legacy ON games(systemSlug,
      filename) WHERE artifact_key IS NULL''');
    await db.execute('''CREATE UNIQUE INDEX games_artifact ON games(systemSlug,
      artifact_key) WHERE artifact_key IS NOT NULL''');
    await LibraryQuery.install(db);
    const provider = ProviderConfig(
      type: ProviderType.drive,
      priority: 1,
      sourceId: 'synthetic-source',
      drive: DriveSourceConfig(
          accountId: 'synthetic-account',
          rootFolderId: 'synthetic-root',
          serverClientId: 'synthetic-client'),
      path: 'synthetic-root',
    );
    final system =
        SystemModel.supportedSystems.singleWhere((s) => s.id == 'psx');
    final config = SystemConfig(
        id: system.id,
        name: system.name,
        targetFolder: 'synthetic/psx',
        providers: const [provider]);
    final appConfig = AppConfig(systems: [config]);
    final scope = DriveCatalogue.scopeKey(
        'synthetic-source', 'synthetic-account', 'synthetic-root');
    await db.insert('drive_catalogue_state', {
      'scope': scope,
      'active': 1,
      'next_generation': 2,
    });
    final files = [
      DriveFile(
          id: 'synthetic-root',
          name: 'Synthetic PS1',
          mimeType: DriveFile.folderMime,
          parents: ['my-drive']),
      for (var i = 1; i <= 12; i++)
        DriveFile(
            id: 'file-$i',
            name: 'Game ${i.toString().padLeft(2, '0')}.chd',
            mimeType: 'application/octet-stream',
            parents: ['synthetic-root'],
            sizeBytes: 100,
            version: '1'),
    ];
    for (final file in files) {
      await db.insert('drive_catalogue_entries', {
        'scope': scope,
        'generation': 1,
        'file_id': file.id,
        'parent_id': file.parents.single,
        'display_path': file.name,
        'is_folder': file.isFolder ? 1 : 0,
        'record_json': jsonEncode(file.toJson()),
      });
    }
    final service = DatabaseService();
    await service.saveGames(
        'psx', await DriveProvider(provider).fetchGames(config));
    // Higher-scored games on another console must not consume this console's cap.
    await db.insert('games', {
      'systemSlug': 'ps2',
      'displayName': 'Other console',
      'filename': 'Other.chd',
      'url': 'https://example.invalid/other'
    });
    final store = LibraryStore(Future.value(db));
    final editions = <int, String>{};
    final at = DateTime.utc(2026, 10, 4);
    for (final row in await db.query('games', orderBy: 'id')) {
      final cacheRowId = row['id'] as int;
      final platform = row['systemSlug'] as String;
      final i = platform == 'psx'
          ? int.parse((row['displayName'] as String).split(' ').last)
          : 13;
      final id = (await db.transaction((txn) =>
              LibraryStore.catalogueEditions(txn, cacheRowId: cacheRowId)
                  .toList()))
          .single;
      editions[i] = id;
      final edition = (await store.edition(id))!;
      final game = (await store.game(edition.gameId))!;
      await store.putGame(GameIdentity.fromJson({
        ...game.toJson(),
        'matchStatus': 'manuallyMatched',
        'providerIds': {'igdb': '$i'}
      }));
      final tags = i == 1 || i == 12
          ? ['T-Eng', 'Undub', 'Uncensor']
          : i == 2
              ? ['Undub']
              : ['official'];
      await store.putEdition(EditionIdentity.fromJson({
        ...edition.toJson(),
        'tags': tags,
        'isTranslation': tags.contains('T-Eng'),
        'translatedLanguages': tags.contains('T-Eng') ? ['en'] : <String>[],
      }));
      await store.putMetadata(MetadataRecord(
          gameId: game.id,
          editionId: id,
          platformId: platform,
          providerId: 'igdb',
          providerGameId: '$i',
          retrievedAt: at,
          refreshGeneration: 1,
          matchMethod: 'verifiedProviderIdGlobalGame',
          titles: [
            MetadataText(text: row['displayName'] as String)
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
                rawValue: platform == 'ps2' ? 100 : 100 - i,
                scaleMinimum: 0,
                scaleMaximum: 100,
                voteCount: 100,
                kind: RatingKind.communityAggregate,
                retrievedAt: at)!
          ]));
    }
    // The normal screen performs the same cached provider refresh on reopening.
    // Exercise the real upsert after identities/projections have been bound;
    // otherwise its swallowed background error could hide a failed refresh.
    final query = LibraryQuery(Future.value(db));
    await query.page(filter: LibraryQueryFilter());
    await service.saveGames(
        'psx', await DriveProvider(provider).fetchGames(config));
    await service.saveGames(
        'psx', await DriveProvider(provider).fetchGames(config));
    expect(await service.getGames('psx'), hasLength(12));
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.setStartHintShown();
    await storage.setGridColumns(system.name, 4);
    final container = ProviderContainer(overrides: [
      // This cache-only fixture has no configured cloud metadata library. Its
      // local covers/ratings below remain real; cloud hydration is separate QA.
      cloudSelectionMediaProvider.overrideWith((ref, selection) async => null),
      storageServiceProvider.overrideWithValue(storage),
      libraryDbProvider.overrideWithValue(service),
      bootstrappedConfigProvider.overrideWith((ref) async => appConfig),
      installedFilesProvider.overrideWith((ref) async => InstalledFilesState()),
      deviceMemoryProvider.overrideWithValue(
          const DeviceMemoryInfo(totalBytes: 0, tier: MemoryTier.standard)),
      sourcesProvider.overrideWith(
          (ref) => SourcesNotifier(_Config(appConfig), db: service)),
    ]);
    addTearDown(container.dispose);
    await container.read(bootstrappedConfigProvider.future);
    await container.read(installedFilesProvider.future);
    final retainedPreviewOwner = Object();
    Widget app() => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: AppTheme.darkTheme,
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            home: GameListScreen(
                retainedPreviewOwner: retainedPreviewOwner,
                system: system,
                targetFolder: config.targetFolder)));
    List<String> firstGames(int n) =>
        List.generate(n, (i) => 'Game ${(i + 1).toString().padLeft(2, '0')}');
    Future<void> expectGames(List<String> expected) async {
      if (expected.isEmpty) {
        expect(find.text('No games match current filters'), findsOneWidget);
        expect(find.byType(BaseGameCard), findsNothing);
        return;
      }
      final grid = tester.widget<GameGrid>(find.byType(GameGrid));
      expect(
          grid.filteredGroups
              .map((g) => grid.groupedGames[g]!.first.displayName),
          expected);
      final scroll = grid.scrollController;
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      final seen = <String>{};
      void capture() {
        final cards =
            tester.widgetList<BaseGameCard>(find.byType(BaseGameCard));
        for (final card in cards) {
          expect(card.systemId, 'psx');
          expect(card.isRemoteAvailable, isTrue,
              reason: 'Drive catalogue games expose their download source');
          expect(card.overallRating, isNotNull, reason: card.displayName);
          seen.add(card.displayName);
        }
        expect(find.byType(MediaCoverFallback), findsNWidgets(cards.length));
        expect(find.byKey(const ValueKey('cover-rating')),
            findsNWidgets(cards.length));
      }

      capture();
      while (scroll.position.pixels < scroll.position.maxScrollExtent) {
        final before = scroll.position.pixels;
        scroll.jumpTo((before + scroll.position.viewportDimension)
            .clamp(0, scroll.position.maxScrollExtent));
        await tester.pumpAndSettle();
        expect(scroll.position.pixels, greaterThan(before));
        capture();
      }
      expect(seen, expected.toSet());
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
    }

    Future<void> openFilters() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.filter_list_rounded).first);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilterOverlay>(find.byType(FilterOverlay))
              .discoveryScope,
          system.name);
      expect(find.textContaining('one collection-wide limit'), findsNothing);
    }

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

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await container.read(cachedCoverRatingsProvider('psx').future);
    await tester.pumpAndSettle();
    await expectGames(firstGames(12));
    await openFilters();
    // The real filter panel owns normal controller navigation and activation.
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    await expectGames(firstGames(10));
    await checkpoint?.call('console-top-10', tester);
    await tapFilter('discovery-top-25');
    await expectGames(firstGames(12));
    await tapFilter('discovery-top-10');
    await tapFilter('discovery-tag-T-Eng');
    await tapFilter('discovery-tag-Undub');
    await expectGames(['Game 01', 'Game 02']);
    await tapFilter('discovery-match');
    await tapFilter('discovery-tag-Uncensor');
    await expectGames(['Game 01']);
    await checkpoint?.call('console-tags-all', tester);
    final original = (await store.metadata(editions[1]!, 'igdb'))!;
    await store.putMetadata(MetadataRecord.fromJson({
      ...original.toJson(),
      'refreshGeneration': 2,
      'ratings':
          original.ratings.map((r) => {...r.toJson(), 'rawValue': '1'}).toList()
    }));
    container.read(gameDbChangedProvider.notifier).state++;
    await tester.pumpAndSettle();
    await expectGames([]);
    // The lower-ranked tagged Game 12 is not backfilled into the Top.
    await store.putMetadata(MetadataRecord.fromJson(
        {...original.toJson(), 'refreshGeneration': 3}));
    container.read(gameDbChangedProvider.notifier).state++;
    await tester.pumpAndSettle();
    await expectGames(['Game 01']);
    expect(jsonDecode(storage.getFilters('psx')!)['top'], 10);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await container.read(cachedCoverRatingsProvider('psx').future);
    await tester.pumpAndSettle();
    await expectGames(['Game 01']);
    await checkpoint?.call('console-restored-filters', tester);
    await openFilters();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonX);
    await tester.pumpAndSettle();
    await expectGames(firstGames(12));
    expect(storage.getFilters('psx'), isNull);
    expect(storage.getFilters('ps2'), isNull);
    expect(storage.getFilters('library:all'), isNull);
    // Select a visible identity, then change score order through the normal
    // controls and publication signal. Focus must stay on that same game.
    tester
        .widgetList<BaseGameCard>(find.byType(BaseGameCard))
        .singleWhere((card) => card.displayName == 'Game 02')
        .onTapSelect!();
    await tester.pumpAndSettle();
    await tapFilter('discovery-order');
    final third = (await store.metadata(editions[3]!, 'igdb'))!;
    await store.putMetadata(MetadataRecord.fromJson({
      ...third.toJson(),
      'refreshGeneration': 2,
      'ratings':
          third.ratings.map((r) => {...r.toJson(), 'rawValue': '100'}).toList()
    }));
    container.read(gameDbChangedProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<BaseGameCard>(find.byType(BaseGameCard))
            .singleWhere((card) => card.displayName == 'Game 02')
            .isSelected,
        isTrue);
    await expectGames(
        ['Game 03', 'Game 01', 'Game 02', ...firstGames(12).skip(3)]);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await tester.pumpAndSettle();
    expect(tester.widget<GameGrid>(find.byType(GameGrid)).crossAxisCount, 3);
    await expectGames(
        ['Game 03', 'Game 01', 'Game 02', ...firstGames(12).skip(3)]);
    expect(
        offline.attempts.every((uri) =>
            uri.scheme == 'https' &&
            uri.host == 'raw.githubusercontent.com' &&
            uri.path.startsWith('/libretro-thumbnails/Sony_-_PlayStation/') &&
            uri.path.endsWith('.png')),
        isTrue,
        reason: 'Only existing boxart requests may reach the blocked boundary; '
            'no metadata, Drive or ROM requests are allowed');
    reportNetwork?.call(offline.attempts.length);
    if (factory != null) {
      // Android uses real I/O. The entire normal-screen interaction above must
      // have committed its cached refresh, not merely painted existing rows.
      expect(storage.getLastSyncTime('psx'), isNotNull);
    }
    await checkpoint?.call('console-cleared-filters', tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

class ConsoleOfflineRequests extends HttpOverrides {
  final attempts = <Uri>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _OfflineClient(attempts);
}

class _OfflineClient implements HttpClient {
  final List<Uri> attempts;
  _OfflineClient(this.attempts);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    attempts.add(url);
    return Future.error(
        const SocketException('Synthetic offline console fixture'));
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}
