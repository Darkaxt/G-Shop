import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/features/library/library_screen.dart';
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
  testWidgets(
      'library Top is one scoped cap; tags intersect and shelves keep order',
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
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(cards(), hasLength(12));
    await tester.tap(find.byIcon(Icons.filter_alt_rounded).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('one collection-wide limit'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('discovery-top-10')));
    await tester.pumpAndSettle();
    expect(cards(), hasLength(10));
    await tester.tap(find.byKey(const ValueKey('discovery-platform-psx')));
    await tester.pumpAndSettle();
    expect(cards(),
        ['Game 01', 'Game 03', 'Game 05', 'Game 07', 'Game 09', 'Game 11']);
    await tester.tap(find.byKey(const ValueKey('discovery-platform-ps2')));
    await tester.pumpAndSettle();
    expect(cards(), hasLength(10));
    for (final scope in ['psx', 'ps2']) {
      await tester.tap(find.byKey(ValueKey('discovery-platform-$scope')));
      await tester.pumpAndSettle();
    }
    expect(cards(), hasLength(10));
    await tester
        .ensureVisible(find.byKey(const ValueKey('discovery-tag-Hack')));
    await tester.tap(find.byKey(const ValueKey('discovery-tag-Hack')));
    await tester.pumpAndSettle();
    expect(cards(), ['Game 01']);
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
    expect(cards(), ['Game 01']);
    // Close the real panel, then select the real manual shelf tab.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('MANUAL').first);
    await tester.pumpAndSettle();
    expect(cards(), ['Game 09', 'Game 01', 'Game 12']);
    tester
        .widgetList<BaseGameCard>(find.byType(BaseGameCard))
        .singleWhere((c) => c.displayName == 'Game 09')
        .onTapSelect!();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.filter_alt_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('discovery-top-10')));
    await tester.pumpAndSettle();
    expect(cards(), ['Game 09', 'Game 01']);
    await tester.tap(find.byKey(const ValueKey('discovery-order')));
    await tester.pumpAndSettle();
    expect(cards(), ['Game 01', 'Game 09']);
    expect(
        tester
            .widgetList<BaseGameCard>(find.byType(BaseGameCard))
            .singleWhere((c) => c.displayName == 'Game 09')
            .isSelected,
        isTrue);
    expect(storage.getCustomShelves().single.manualGameIds,
        ['Game 09.7z', 'Game 01.7z', 'Game 12.7z']);
    expect(jsonDecode(storage.getFilters('library:all')!)['tags'], ['Hack']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(await db.query('library_query_views'), isEmpty);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(cards(), ['Game 01']);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
