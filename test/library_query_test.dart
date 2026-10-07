import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_eshop/providers/library_providers.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/metadata/effective_overall_rating.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/features/game_list/logic/game_list_controller.dart';
import 'package:retro_eshop/models/config/system_config.dart';
import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'game_list_controller_test.dart'
    show FakeStorageService, waitUntilLoaded;

class _CacheDatabase extends DatabaseService {
  final Database cache;
  _CacheDatabase(this.cache);
  @override
  Future<Database> get database => Future.value(cache);
}

class _ConsoleCacheDatabase extends _CacheDatabase {
  final List<GameItem> games;
  _ConsoleCacheDatabase(super.cache, this.games);
  @override
  Future<bool> hasCache(String systemSlug) async => true;
  @override
  Future<List<GameItem>> getGames(String systemSlug) async => games;
}

class _FreshFilterStorage extends FakeStorageService {
  @override
  DateTime? getLastSyncTime(String systemId) => DateTime.now();
}

void main() {
  late Database db;
  late LibraryStore store;
  late LibraryQuery query;
  final at = DateTime.utc(2026, 10, 3);
  final basis = AssessedOverallScoreBasis(
      sourceId: 'igdb',
      kind: RatingKind.overallAggregate,
      scaleMinimum: 0,
      scaleMaximum: 100,
      platformIds: {'psx', 'snes'},
      minimumVoteCount: 10,
      assessmentReference: 'synthetic-query-assessment');
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games(id INTEGER PRIMARY KEY,
      systemSlug TEXT, displayName TEXT, filename TEXT, artifact_key TEXT, remote_artifact TEXT,
      is_folder INTEGER DEFAULT 0)''');
    await LibraryQuery.install(db);
    store = LibraryStore(Future.value(db));
    query = LibraryQuery(Future.value(db));
  });
  tearDown(() => db.close());

  Future<String> seed(int n,
      {double? score,
      String platform = 'psx',
      String? group,
      Set<String> tags = const {'official'},
      List<String> genres = const ['Action'],
      List<String> regions = const ['USA'],
      List<String> languages = const ['en'],
      int votes = 100}) async {
    await db.insert('games', {
      'id': n,
      'systemSlug': platform,
      'displayName': 'Game $n',
      'filename': 'Game $n.7z'
    });
    final id = (await db.transaction((txn) =>
            LibraryStore.catalogueEditions(txn, cacheRowId: n).toList()))
        .single;
    final edition = (await store.edition(id))!;
    final game = (await store.game(edition.gameId))!;
    final providerId = group ?? '$n';
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'matchStatus': 'manuallyMatched',
      'providerIds': {'screenscraper': providerId, 'igdb': providerId}
    }));
    await store.putEdition(EditionIdentity.fromJson({
      ...edition.toJson(),
      'tags': tags.toList(),
      'regions': regions,
      'languages': languages,
      if (tags.contains('T-Eng')) 'isTranslation': true,
      if (tags.contains('T-Eng')) 'translatedLanguages': ['en']
    }));
    if (score != null) {
      await store.putMetadata(MetadataRecord(
          gameId: game.id,
          editionId: id,
          platformId: platform,
          providerId: 'igdb',
          providerGameId: providerId,
          retrievedAt: at,
          refreshGeneration: 1,
          matchMethod: tags.contains('Hack')
              ? 'verifiedProjectId'
              : 'verifiedProviderIdGlobalGame',
          titles: [MetadataText(text: 'Game $n')],
          genres: genres
              .map((g) => MetadataGenre(
                  providerGenreId: g, names: [MetadataText(text: g)]))
              .toList(),
          ratings: [
            SourcedRating.parse(
                sourceId: 'igdb',
                sourceLabel: 'IGDB',
                providerGameId: providerId,
                rawValue: score,
                scaleMinimum: 0,
                scaleMaximum: 100,
                voteCount: votes,
                kind: RatingKind.overallAggregate,
                retrievedAt: at)!
          ]));
    }
    return id;
  }

  Future<LibraryQueryPage> read({LibraryQueryFilter? filter}) => query
      .page(filter: filter ?? LibraryQueryFilter(), assessedBases: [basis]);

  test('retention keeps an unscored member of a ranked canonical game',
      () async {
    for (var n = 1; n <= 26; n++) {
      await seed(n, score: n.toDouble());
    }
    final extraDisc = await seed(90, group: '26');
    final page =
        await query.retentionPage(platformId: 'psx', assessedBases: [basis]);
    expect(page.collectionGames, 26);
    expect(page.rankedGames, 26);
    expect(page.provisional, isFalse);
    expect(page.totalMembers, 27);
    final member = page.members.singleWhere((m) => m.editionId == extraDisc);
    expect(member.canonicalRank, 1);
    expect(page.disposition(member).name, 'keep');
    final last = page.members.singleWhere((m) => m.cacheRowId == 1);
    expect(last.canonicalRank, 26);
    expect(page.disposition(last).name, 'outsideSample');
  });

  test(
      'retention preserves unresolved games rather than treating them as bottom ranked',
      () async {
    for (var n = 1; n <= 26; n++) {
      await seed(n, score: n.toDouble());
    }
    await seed(27);
    final page =
        await query.retentionPage(platformId: 'psx', assessedBases: [basis]);
    expect(page.provisional, isTrue);
    expect(page.collectionGames, 27);
    expect(page.rankedGames, 26);
    expect(
        page
            .disposition(page.members.singleWhere((m) => m.cacheRowId == 1))
            .name,
        'preserve');
    final unresolved = page.members.singleWhere((m) => m.cacheRowId == 27);
    expect(unresolved.canonicalRank, isNull);
    expect(page.disposition(unresolved).name, 'preserve');
  });

  test(
      'retention ranks one console with bounded pages and stable canonical ties',
      () async {
    await seed(1, score: 80);
    await seed(2, score: 80);
    await seed(3, score: 99, platform: 'snes');
    final first = await query
        .retentionPage(platformId: 'psx', limit: 1, assessedBases: [basis]);
    final second = await query.retentionPage(
        platformId: 'psx', limit: 1, offset: 1, assessedBases: [basis]);
    expect(first.collectionGames, 2);
    expect(first.totalMembers, 2);
    expect(first.members.length, 1);
    expect(second.members.length, 1);
    expect(first.members.single.canonicalRank, 1);
    expect(second.members.single.canonicalRank, 2);
    expect(
        first.members.single.groupKey.compareTo(second.members.single.groupKey),
        lessThan(0));
    final empty = await query
        .retentionPage(platformId: 'psx', offset: 2, assessedBases: [basis]);
    expect(empty.members, isEmpty);
    expect(empty.totalMembers, 2);
    expect(empty.collectionGames, 2);
  });

  test('retention treats conflicting scores and low vote counts as unresolved',
      () async {
    await seed(1, group: 'same', score: 70);
    await seed(2, group: 'same', score: 90);
    await seed(3, score: 100, votes: 1);
    final page =
        await query.retentionPage(platformId: 'psx', assessedBases: [basis]);
    expect(page.collectionGames, 2);
    expect(page.rankedGames, 0);
    expect(page.provisional, isTrue);
    expect(page.members.every((m) => m.canonicalRank == null), isTrue);
    expect(page.members.every((m) => page.disposition(m).name == 'preserve'),
        isTrue);
  });

  test('retention rejects invalid scope and unbounded page requests', () async {
    for (final values in [
      {'platformId': '', 'limit': 128, 'offset': 0},
      {'platformId': 'psx', 'limit': 129, 'offset': 0},
      {'platformId': 'psx', 'limit': 0, 'offset': 0},
      {'platformId': 'psx', 'limit': 128, 'offset': -1},
    ]) {
      await expectLater(
          query.retentionPage(
              platformId: values['platformId'] as String,
              limit: values['limit'] as int,
              offset: values['offset'] as int),
          throwsArgumentError);
    }
  });

  test(
      'retention cannot claim complete coverage when an artifact binding conflicts',
      () async {
    final editionId = await seed(1, score: 90);
    final edition = (await store.edition(editionId))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'platformId': 'snes',
    }));
    final page =
        await query.retentionPage(platformId: 'psx', assessedBases: [basis]);
    expect(page.members, isEmpty);
    expect(page.collectionGames, 0);
    expect(page.unboundArtifacts, 1);
    expect(page.provisional, isTrue);
  });

  test('retention recomputes after pending refresh and removed membership',
      () async {
    await seed(1, score: 90);
    var page =
        await query.retentionPage(platformId: 'psx', assessedBases: [basis]);
    expect(page.provisional, isFalse);
    expect(page.disposition(page.members.single),
        LibraryRetentionDisposition.keep);
    await MetadataRefreshJobs(Future.value(db))
        .createFromCatalogue(providerId: 'igdb');
    page = await query.retentionPage(platformId: 'psx', assessedBases: [basis]);
    expect(page.rankedGames, 0);
    expect(page.provisional, isTrue);
    expect(page.disposition(page.members.single),
        LibraryRetentionDisposition.preserve);
    await db.delete('games', where: 'id = 1');
    page = await query.retentionPage(platformId: 'psx', assessedBases: [basis]);
    expect(page.members, isEmpty);
    expect(page.totalMembers, 0);
    expect(page.unboundArtifacts, 0);
  });

  test('cache UPSERT coalesces invalidations without rolling back refresh',
      () async {
    final id = await seed(1, score: 82);
    await read(); // Bind the cache row and consume its initial invalidations.
    for (final title in ['Renamed', 'Renamed again']) {
      await db.rawInsert('''INSERT INTO games
        (id, systemSlug, filename, displayName) VALUES (1, 'psx', 'Game 1.7z', ?)
        ON CONFLICT(id) DO UPDATE SET displayName = excluded.displayName''',
          [title]);
      expect((await db.query('games')).single['displayName'], title);
      expect(await db.query('library_query_cache_dirty'), [
        {'cache_row_id': 1}
      ]);
      expect(await db.query('library_query_dirty'), [
        {'edition_id': id}
      ]);
    }
    // An outer conflict policy also overrides OR IGNORE in edition triggers.
    await db.rawUpdate('''UPDATE OR ABORT library_editions SET
      record_json = record_json WHERE edition_id = ?''', [id]);
    expect(await db.query('library_query_dirty'), [
      {'edition_id': id}
    ]);
    final result = await read();
    expect(result.items.single.editionId, id);
    expect(result.items.single.score!.rating.normalizedValue, 82);
    expect(await db.query('library_query_dirty'), isEmpty);
    expect(await db.query('library_query_cache_dirty'), isEmpty);
  });

  test('normal details use the selected cached score, not a legacy average',
      () async {
    await seed(1, score: 82);
    await db.execute('''CREATE TABLE game_metadata(filename TEXT,
      system_slug TEXT, rating REAL, last_updated INTEGER)''');
    await db.insert('game_metadata', {
      'filename': 'Game 1.7z',
      'system_slug': 'psx',
      'rating': 99.0,
      'last_updated': 0,
    });
    final detail = await _CacheDatabase(db).getGameMetadata('Game 1.7z', 'psx');
    expect(detail?.rating, 82);
    final cover = (await query.cachedRatings([1]))[1];
    expect(detail?.overallRating?.rating.toJson(), cover?.rating.toJson());
    expect(detail?.editionId, isNotNull);
    expect(detail?.contentTags, {'official'});
  });

  test(
      'details retain exact independent tags and never borrow an unrated sibling score',
      () async {
    await seed(1, score: 93, group: 'same-game');
    await seed(2, group: 'same-game', tags: {'T-Eng', 'Undub', 'Uncensor'});
    final selected = await query.cachedMetadata('Game 2.7z', 'psx');
    expect(selected?.overallRating, isNull);
    expect(selected?.rating, isNull);
    expect(selected?.contentTags, {'T-Eng', 'Undub', 'Uncensor'});
    await seed(3, tags: {'Official', 'Hack'});
    expect((await query.cachedMetadata('Game 3.7z', 'psx'))?.contentTags,
        {'Hack', 'unknown'});
  });

  test('details separate consoles and reject duplicate selection bindings',
      () async {
    await seed(1, score: 82);
    await seed(2, score: 70, platform: 'ps2');
    await db.update('games', {'filename': 'Game 1.7z'}, where: 'id = 2');
    expect((await query.cachedMetadata('Game 1.7z', 'psx'))?.rating, 82);
    expect((await query.cachedMetadata('Game 1.7z', 'ps2'))?.rating, 70);
    await db.insert('games', {
      'id': 3,
      'systemSlug': 'psx',
      'displayName': 'Other',
      'filename': 'Game 1.7z'
    });
    final ambiguous = await query.cachedMetadata('Game 1.7z', 'psx');
    expect(ambiguous, isNotNull);
    expect(ambiguous?.editionId, isNull);
    expect(ambiguous?.rating, isNull);
    expect(ambiguous?.overallRating, isNull);
  });

  test('unresolved current details never promote anonymous legacy metadata',
      () async {
    await seed(1);
    await db.execute('''CREATE TABLE game_metadata(filename TEXT,
      system_slug TEXT, rating REAL, last_updated INTEGER)''');
    await db.insert('game_metadata', {
      'filename': 'Game 1.7z',
      'system_slug': 'psx',
      'rating': 99,
      'last_updated': 0
    });
    final database = _CacheDatabase(db);
    final selected = await database.getGameMetadata('Game 1.7z', 'psx');
    expect(selected?.cacheRowId, 1);
    expect(selected?.rating, isNull);
    expect(selected?.hasContent, true);
    expect(await database.getGameMetadata('artifact:missing', 'psx'), isNull);
  });

  test(
      'detail field provenance and requested language survive cached projection',
      () async {
    final id = await seed(1, score: 82);
    final current = (await store.metadata(id, 'igdb'))!;
    await store.putMetadata(MetadataRecord.fromJson({
      ...current.toJson(),
      'descriptions': [
        const MetadataText(text: 'English', language: 'en').toJson(),
        const MetadataText(text: 'Español', language: 'es').toJson()
      ],
      'releaseDates': [
        const MetadataText(text: '1997-01-31', region: 'jp').toJson(),
        const MetadataText(text: '1998-02-03', region: 'us').toJson()
      ],
      'fieldProvenance': {
        'description': MetadataFieldProvenance(
                providerId: 'igdb',
                providerGameId: '1',
                field: 'description',
                retrievedAt: at)
            .toJson()
      }
    }));
    final selected =
        await query.cachedMetadata('Game 1.7z', 'psx', language: 'es');
    expect(selected?.summary, 'Español');
    expect(selected?.releaseDate, '1998-02-03',
        reason: 'Release region is independent of the selected UI language');
    expect(selected?.provenance['description']?.providerId, 'igdb');
    expect(selected?.providerMatches, {'igdb': 'verifiedProviderIdGlobalGame'});
    await MetadataRefreshJobs(Future.value(db))
        .createFromCatalogue(providerId: 'igdb');
    expect(
        (await query.cachedMetadata('Game 1.7z', 'psx'))?.overallRating?.fresh,
        false);
  });

  test(
      'console Top and tags use production scores and persist without a scrape',
      () async {
    final games = <GameItem>[];
    for (var i = 1; i <= 12; i++) {
      final id = await seed(i,
          score: 100 - i.toDouble(),
          tags: i == 1 || i == 12 ? {'Hack'} : {'official'});
      final metadata = (await store.metadata(id, 'igdb'))!;
      await store.putMetadata(MetadataRecord.fromJson({
        ...metadata.toJson(),
        'ratings': metadata.ratings
            .map((r) =>
                {...r.toJson(), 'kind': RatingKind.communityAggregate.name})
            .toList()
      }));
      games.add(GameItem(
          filename: 'Game $i.7z',
          displayName: 'Game $i',
          url: 'https://example.invalid/$i'));
    }
    final storage = _FreshFilterStorage();
    final system =
        SystemModel.supportedSystems.firstWhere((s) => s.id == 'psx');
    final config = SystemConfig(
        id: system.id,
        name: system.name,
        targetFolder: '/nonexistent/psx',
        providers: [
          const ProviderConfig(
              type: ProviderType.web,
              url: 'https://example.invalid/',
              priority: 1)
        ]);
    GameListController create() => GameListController(
        system: system,
        targetFolder: config.targetFolder,
        systemConfig: config,
        databaseService: _ConsoleCacheDatabase(db, games),
        storage: storage,
        installedFilenames: {'Game 1.7z'});
    var controller = create();
    try {
      await waitUntilLoaded(controller);
      await controller.loadDiscoveryGenres();
      expect(controller.state.availableGenres, ['action']);
      controller.setTopFilter(10);
      controller.toggleTagFilter('Hack');
      await controller.discoverySettled;
      expect(controller.state.filteredGroups, hasLength(1));
      final key = controller.state.filteredGroups.single;
      expect(controller.state.filteredGroupedGames[key]!.single.filename,
          'Game 1.7z');
      expect(controller.state.installedCache[key], isTrue);
      expect(controller.state.discovery!.collectionGames, 12);
      expect(controller.state.discovery!.rankedGames, 12);
      await storage.setFavorites(['Game 12.7z']);
      controller.toggleFavoritesFilter();
      await controller.discoverySettled;
      expect(controller.state.filteredGroups, isEmpty,
          reason: 'Favorites cannot promote the rank-12 hack into Top 10');
      controller.toggleFavoritesFilter();
      await controller.discoverySettled;
      var changedDuringPublication = false;
      void changeFromListener() {
        if (!changedDuringPublication &&
            controller.state.discovery != null &&
            !controller.state.queryingDiscovery) {
          changedDuringPublication = true;
          controller.toggleGenreFilter('action');
        }
      }

      controller.addListener(changeFromListener);
      controller.refreshDiscovery();
      await controller.discoverySettled;
      controller.removeListener(changeFromListener);
      expect(controller.state.queryingDiscovery, isFalse,
          reason:
              'A publication listener may request a newer filter generation');
      expect(controller.state.filteredGroups, hasLength(1));
      controller.dispose();
      controller = create();
      await waitUntilLoaded(controller);
      await controller.discoverySettled;
      expect(controller.state.activeFilters.top, 10);
      expect(controller.state.activeFilters.selectedTags, {'Hack'});
      expect(controller.state.filteredGroups, hasLength(1));
      controller.clearFilters();
      await controller.discoverySettled;
      expect(controller.state.filteredGroups, hasLength(12));
      expect(await db.query('library_query_views'), isEmpty);
    } finally {
      controller.dispose();
    }
  });

  for (final operation in ['details', 'ratings', 'covers']) {
    test('exact $operation reads leave unrelated projection work pending',
        () async {
      await seed(1, score: 91);
      final unrelated = await seed(2, score: 73, platform: 'snes');
      final before = await db.query('library_query_dirty',
          where: 'edition_id = ?', whereArgs: [unrelated]);
      expect(before, isNotEmpty);
      switch (operation) {
        case 'details':
          expect((await query.cachedMetadata('Game 1.7z', 'psx'))?.cacheRowId, 1);
        case 'ratings':
          expect((await query.cachedRatings([1], assessedBases: [basis]))[1]
              ?.rating.normalizedValue, 91);
        case 'covers':
          final cache = MetadataArtworkCache(
              Future.value(db), Directory('D:/Temp/rshop-unused-artwork'));
          expect(await query.cachedCovers([1], cache), {1: null});
      }
      expect(await db.query('library_query_dirty',
          where: 'edition_id = ?', whereArgs: [unrelated]), before,
          reason: 'Reading a card must not rebuild unrelated rankings.');
      expect(await db.query('library_query_cache_dirty',
          where: 'cache_row_id = ?', whereArgs: [2]), isNotEmpty);
      expect(await db.query('library_query_editions',
          where: 'cache_row_id = ?', whereArgs: [2]), isEmpty);
      // Collection queries still consume all pending work and preserve ranking.
      expect((await read()).collectionGames, 2);
      expect(await db.query('library_query_cache_dirty'), isEmpty);
      expect(await db.query('library_query_dirty'), isEmpty);
    });
  }

  test('card score pages preserve each exact cached edition, not group winners',
      () async {
    final first = await seed(1, score: 91, group: 'same-game');
    final second = await seed(2, score: 91, group: 'same-game');
    await seed(3);
    final cards =
        await query.cachedRatings([1, 2, 3, 999], assessedBases: [basis]);
    expect(cards.keys, [1, 2, 3, 999]);
    final selected =
        await store.effectiveRatings([first, second], assessedBases: [basis]);
    expect(cards[1]!.rating.toJson(), selected[first]!.rating.toJson());
    expect(cards[2]!.rating.toJson(), selected[second]!.rating.toJson());
    expect(cards[3], isNull);
    expect(cards[999], isNull);
    expect((await read()).items, hasLength(2),
        reason:
            'Discovery groups canonical games; card scores retain editions.');
    await db.delete('games', where: 'id = 2');
    expect((await query.cachedRatings([2], assessedBases: [basis]))[2], isNull);
    await expectLater(query.cachedRatings(List.generate(129, (i) => i + 1)),
        throwsArgumentError);
  });

  test(
      'shared cover provider separates consoles and refreshes cached publication',
      () async {
    final first = await seed(1, score: 91);
    await seed(2, score: 70, platform: 'snes');
    await seed(3);
    await db.update('games', {'filename': 'Same.7z'}, where: 'id IN (1, 2)');
    final container = ProviderContainer(overrides: [
      libraryDbProvider.overrideWithValue(_CacheDatabase(db)),
      sharedMetadataStoreProvider.overrideWithValue(Future.value(null)),
    ]);
    final all = container.listen(cachedCoverRatingsProvider(''), (_, __) {});
    final system =
        container.listen(cachedCoverRatingsProvider('psx'), (_, __) {});
    try {
      final scores =
          await container.read(cachedCoverRatingsProvider('').future);
      final local =
          await container.read(cachedCoverRatingsProvider('psx').future);
      final psx = coverRatingKey('psx', 'Same.7z');
      final snes = coverRatingKey('snes', 'Same.7z');
      expect(scores[psx]!.rating.normalizedValue, 91);
      expect(scores[snes]!.rating.normalizedValue, 70);
      expect(local.containsKey(snes), isFalse);
      expect(local[coverRatingKey('psx', 'Game 3.7z')], isNull);
      expect(
          identical(await container.read(cachedCoverRatingsProvider('').future),
              scores),
          isTrue,
          reason:
              'Card rebuilds/scrolling reuse the same map, not database reads.');
      final cached = (await store.metadata(first, 'igdb'))!;
      await store.putMetadata(MetadataRecord.fromJson({
        ...cached.toJson(),
        'ratings':
            cached.ratings.map((r) => {...r.toJson(), 'rawValue': 88}).toList()
      }));
      container.read(gameDbChangedProvider.notifier).state++;
      final refreshed =
          await container.read(cachedCoverRatingsProvider('').future);
      expect(refreshed[psx]!.rating.normalizedValue, 88);
      expect(refreshed[snes]!.rating.normalizedValue, 70);
    } finally {
      all.close();
      system.close();
      container.dispose();
    }
  });

  test('production display and Top share supported community score, not total',
      () async {
    final supported = await seed(1, score: 70);
    final small = await seed(2, score: 100, tags: {'Hack'});
    await seed(3);
    for (final (id, value, votes) in [(supported, 90, 20), (small, 99, 2)]) {
      final cached = (await store.metadata(id, 'igdb'))!;
      await store.putMetadata(MetadataRecord.fromJson({
        ...cached.toJson(),
        'ratings': [
          ...cached.ratings.map((r) => r.toJson()),
          SourcedRating.parse(
                  sourceId: 'igdb',
                  sourceLabel: 'IGDB users',
                  providerGameId: cached.providerGameId,
                  rawValue: value,
                  scaleMinimum: 0,
                  scaleMaximum: 100,
                  voteCount: votes,
                  kind: RatingKind.communityAggregate,
                  retrievedAt: at)!
              .toJson()
        ]
      }));
    }
    final page = await query.page(filter: LibraryQueryFilter(top: 25));
    expect(page.collectionGames, 3);
    expect(page.rankedGames, 1);
    expect(page.provisional, isTrue);
    expect(page.items.single.editionId, supported);
    final selected = (await store.effectiveRatings([supported, small]));
    expect(page.items.single.score!.rating.toJson(),
        selected[supported]!.rating.toJson());
    expect(selected[supported]!.rating.normalizedValue, 90);
    expect(selected[supported]!.rating.kind, RatingKind.communityAggregate);
    expect(selected[small]!.rating.normalizedValue, 99);
    expect(selected[small]!.rankingEligible, isFalse);
    expect(
        (await query.page(filter: LibraryQueryFilter(top: 25, tags: {'Hack'})))
            .items,
        isEmpty,
        reason:
            'A low-support hack cannot fill an eligible ordinary-game Top.');
    // The same current projection is invalidated by a support-count change;
    // no new scrape or provider request is needed for the read.
    final cached = (await store.metadata(supported, 'igdb'))!;
    await store.putMetadata(MetadataRecord.fromJson({
      ...cached.toJson(),
      'ratings': cached.ratings
          .map((r) => {
                ...r.toJson(),
                if (r.kind == RatingKind.communityAggregate) 'voteCount': 19,
              })
          .toList(),
    }));
    final revised = await query.page(filter: LibraryQueryFilter(top: 25));
    expect(revised.rankedGames, 0);
    expect(revised.items, isEmpty);
  });

  test('NES SNES policy refresh ranks cached records without rescraping',
      () async {
    for (final (n, platform, votes) in [
      (1, 'nes', 20),
      (2, 'nes', 19),
      (3, 'snes', 20),
      (4, 'snes', 19),
    ]) {
      final id = await seed(n, platform: platform, score: 99);
      final cached = (await store.metadata(id, 'igdb'))!;
      await store.putMetadata(MetadataRecord.fromJson({
        ...cached.toJson(),
        'ratings': [
          ...cached.ratings.map((r) => r.toJson()),
          SourcedRating.parse(
                  sourceId: 'igdb',
                  sourceLabel: 'IGDB users',
                  providerGameId: cached.providerGameId,
                  rawValue: 80,
                  scaleMinimum: 0,
                  scaleMaximum: 100,
                  voteCount: votes,
                  kind: RatingKind.communityAggregate,
                  retrievedAt: at)!
              .toJson()
        ]
      }));
    }
    final basis = productionOverallScoreBases.single;
    final previousScope = AssessedOverallScoreBasis(
        sourceId: basis.sourceId,
        kind: basis.kind,
        scaleMinimum: basis.scaleMinimum,
        scaleMaximum: basis.scaleMaximum,
        platformIds: basis.platformIds.difference({'nes', 'snes'}),
        minimumVoteCount: basis.minimumVoteCount,
        assessmentReference: basis.assessmentReference);
    final before = await query.page(
        filter: LibraryQueryFilter(top: 25), assessedBases: [previousScope]);
    expect(before.rankedGames, 0);
    expect(before.items, isEmpty);
    final after = await query.page(filter: LibraryQueryFilter(top: 25));
    expect(after.collectionGames, 4);
    expect(after.rankedGames, 2);
    expect(after.provisional, isTrue);
    expect(after.items.map((item) => item.platformId).toSet(), {'nes', 'snes'});
    for (final item in after.items) {
      expect(item.score!.rating.normalizedValue, 80);
      expect(item.score!.rating.kind, RatingKind.communityAggregate);
      expect(item.score!.rating.voteCount, 20);
    }
    for (final platform in ['nes', 'snes']) {
      final retained = await query.retentionPage(platformId: platform);
      expect(retained.provisional, isTrue);
      expect(
          retained.members.every((member) => retained.disposition(member) !=
              LibraryRetentionDisposition.outsideSample),
          isTrue);
    }
  });

  test('ranks collection before tag search view and genre intersections',
      () async {
    final first = await seed(1, score: 95);
    final second =
        await seed(2, score: 90, tags: {'T-Eng', 'Undub', 'Uncensor'});
    await seed(3, score: 80, tags: {'T-Eng'}, genres: ['Puzzle']);
    await query.replaceViewMembers('favorites', [second]);
    final top = await read(filter: LibraryQueryFilter(top: 2));
    expect(top.items.map((i) => i.editionId), [first, second]);
    final translations =
        await read(filter: LibraryQueryFilter(top: 2, tags: {'T-Eng'}));
    expect(translations.items.map((i) => i.editionId), [second]);
    expect(translations.items.single.rank, 2);
    expect(
        (await read(filter: LibraryQueryFilter(top: 2, genres: {'Puzzle'})))
            .items,
        isEmpty);
    expect(
        (await read(filter: LibraryQueryFilter(top: 2, search: 'Game 3')))
            .items,
        isEmpty);
    expect(
        (await read(filter: LibraryQueryFilter(top: 2, viewIds: {'favorites'})))
            .items
            .single
            .rank,
        2);
    expect(translations.collectionGames, 3);
    expect(translations.rankedGames, 3);
    expect(translations.provisional, isFalse);
  });

  test(
      'tag aliases use the same cached query while unfamiliar tags stay unknown',
      () async {
    final official = await seed(1, score: 90, tags: {'OFFICIAL'});
    final modified = await seed(2, tags: {'dubbed', 'UNDUBBED', 'uncensored'});
    final unfamiliar =
        await seed(3, score: 99, tags: {'Translation', 'PEGI 18'});
    final conflicting = await seed(4, score: 98, tags: {'Official', 'Hack'});
    expect(
        (await read(filter: LibraryQueryFilter(tags: {'Official'})))
            .items
            .map((i) => i.editionId),
        [official],
        reason: 'Contradictory facts do not claim an official release.');
    expect(
        (await read(filter: LibraryQueryFilter(top: 1, tags: {' official '})))
            .items
            .map((i) => i.editionId),
        [official]);
    expect(
        (await read(
                filter: LibraryQueryFilter(
                    tags: {'Dubbed', 'undubbed', 'UNCENSORED'},
                    matchAllTags: true)))
            .items
            .map((i) => i.editionId),
        [modified]);
    final unresolved =
        await read(filter: LibraryQueryFilter(tags: {'Unknown'}));
    expect(unresolved.items.map((i) => i.editionId).toSet(),
        {unfamiliar, conflicting});
    expect(unresolved.items.map((i) => i.score), everyElement(isNull));
    expect(
        (await read(filter: LibraryQueryFilter(top: 1, tags: {'Unknown'})))
            .items,
        isEmpty);
    expect((await store.edition(unfamiliar))!.tags, {'Translation', 'PEGI 18'});
  });

  test('any/all tags are independent and AND other dimensions', () async {
    final a = await seed(1, score: 90, tags: {'T-Eng', 'Undub', 'Uncensor'});
    await seed(2,
        score: 85, tags: {'Undub'}, regions: ['Europe'], languages: ['fr']);
    await seed(3, score: 80);
    await seed(4); // Unknown is not official.
    expect(
        (await read(filter: LibraryQueryFilter(tags: {'T-Eng', 'Undub'})))
            .items,
        hasLength(2));
    expect(
        (await read(
                filter: LibraryQueryFilter(
                    tags: {'T-Eng', 'Undub', 'Uncensor'},
                    matchAllTags: true,
                    regions: {'USA'},
                    languages: {'en'})))
            .items
            .single
            .editionId,
        a);
    expect((await read(filter: LibraryQueryFilter(tags: {'unknown'}))).items,
        hasLength(0));
    final unknown = (await store.edition((await read()).items.last.editionId))!;
    await store.putEdition(
        EditionIdentity.fromJson({...unknown.toJson(), 'tags': []}));
    expect((await read(filter: LibraryQueryFilter(tags: {'unknown'}))).items,
        hasLength(1));
  });

  test('canonical region/disc grouping ties scope and exact score ownership',
      () async {
    await seed(1, score: 90, group: 'shared');
    await seed(2, score: 90, group: 'shared', regions: ['Europe']);
    await seed(3, score: 90, platform: 'snes');
    final hack = await seed(4, score: 80, tags: {'Hack'}, group: 'shared');
    final all = await read(filter: LibraryQueryFilter(top: 10));
    expect(all.collectionGames, 3);
    expect(all.items, hasLength(3));
    expect(all.items.last.editionId, hack);
    final system =
        await read(filter: LibraryQueryFilter(platformIds: {'psx'}, top: 10));
    expect(system.items, hasLength(2));
    expect(system.items.map((i) => i.groupKey),
        all.items.where((i) => i.platformId == 'psx').map((i) => i.groupKey));
    expect(
        (await read(filter: LibraryQueryFilter(top: 1, regions: {'Europe'})))
            .items
            .length,
        lessThanOrEqualTo(1));
    final repeat = await read(filter: LibraryQueryFilter(top: 10));
    expect(
        repeat.items.map((i) => i.groupKey), all.items.map((i) => i.groupKey));
    for (final item in all.items) {
      final score = (await store.effectiveRatings([item.editionId],
          assessedBases: [basis]))[item.editionId]!;
      expect(item.score!.rating.toJson(), score.rating.toJson());
    }
  });

  test(
      'sparse coverage absent assessment and provider-only records stay honest',
      () async {
    await seed(1, score: 90);
    await seed(2);
    await seed(3, score: 100, votes: 2);
    await store.putGame(
        GameIdentity(id: 'outside', platformId: 'psx', title: 'Global'));
    await store.putEdition(EditionIdentity(
        id: 'outside-edition', gameId: 'outside', tags: {'official'}));
    final result = await read(filter: LibraryQueryFilter(top: 25));
    expect(result.items, hasLength(1));
    expect(result.collectionGames, 3);
    expect(result.rankedGames, 1);
    expect(result.provisional, isTrue);
    final unapproved = await query.page(filter: LibraryQueryFilter(top: 25));
    expect(unapproved.items, isEmpty);
    expect(unapproved.rankedGames, 0);
    expect(
        (await query.page(filter: LibraryQueryFilter())).items, hasLength(3));
  });

  test('add remove score and pending refresh changes recompute without refills',
      () async {
    final a = await seed(1, score: 90);
    final b = await seed(2, score: 80);
    expect(
        (await read(filter: LibraryQueryFilter(top: 1))).items.single.editionId,
        a);
    await db.delete('games', where: 'id = 1');
    expect(
        (await read(filter: LibraryQueryFilter(top: 1))).items.single.editionId,
        b);
    final c = await seed(3, score: 95);
    expect(
        (await read(filter: LibraryQueryFilter(top: 1))).items.single.editionId,
        c);
    await MetadataRefreshJobs(Future.value(db)).create(
        providerId: 'igdb', collectionGeneration: 'next', editionIds: [c]);
    final after = await read(filter: LibraryQueryFilter(top: 1));
    expect(after.items.single.editionId, b);
    expect(after.rankedGames, 1);
    expect(after.provisional, isTrue);
    await db.update('library_metadata', {'identity_key': 'invalid'},
        where: 'edition_id = ?', whereArgs: [b]);
    expect((await read(filter: LibraryQueryFilter(top: 1))).items, isEmpty);
  });

  test('bounded pages manual view order and cache-only filter changes',
      () async {
    final a = await seed(1, score: 90);
    final b = await seed(2, score: 80);
    final c = await seed(3, score: 70);
    await query.replaceViewMembers('shelf:test', [c, a, b]);
    final first = await read(
        filter: LibraryQueryFilter(
            viewIds: {'shelf:test'}, manualViewId: 'shelf:test', limit: 2));
    expect(first.items.map((i) => i.editionId), [c, a]);
    expect(first.totalMatches, 3);
    final next = await read(
        filter: LibraryQueryFilter(
            viewIds: {'shelf:test'},
            manualViewId: 'shelf:test',
            limit: 2,
            offset: 2));
    expect(next.items.single.editionId, b);
    final snapshot = await db.query('library_query_editions');
    await read(filter: LibraryQueryFilter(tags: {'official'}, search: 'Game'));
    expect(await db.query('library_query_editions'), snapshot);
    await expectLater(
        read(filter: LibraryQueryFilter(limit: 129)), throwsArgumentError);
  });

  test('Top intersects manual shelf without silently selecting rating sort',
      () async {
    final a = await seed(1, score: 90);
    final b = await seed(2, score: 80);
    final c = await seed(3, score: 70);
    await query.replaceViewMembers('shelf:manual', [c, b, a]);
    final filter = LibraryQueryFilter(
        top: 2, viewIds: {'shelf:manual'}, manualViewId: 'shelf:manual');
    expect((await read(filter: filter)).items.map((i) => i.editionId), [b, a]);
    expect(
        (await read(
                filter: LibraryQueryFilter(
                    top: 2,
                    ratingOrder: true,
                    viewIds: {'shelf:manual'},
                    manualViewId: 'shelf:manual')))
            .items
            .map((i) => i.editionId),
        [a, b]);
  });

  test('discovery returns matching editions but counts and ranks games once',
      () async {
    final a = await seed(1, score: 90, group: 'same');
    final b = await seed(2, score: 90, group: 'same');
    await seed(3, score: 70);
    final page = await read(
        filter: LibraryQueryFilter(top: 1, includeVariants: true, limit: 1));
    final next = await read(
        filter: LibraryQueryFilter(
            top: 1, includeVariants: true, limit: 1, offset: 1));
    expect({page.items.single.editionId, next.items.single.editionId}, {a, b});
    expect(page.totalMatches, 1);
    expect(page.collectionGames, 2);
    expect(page.items.single.rank, 1);
    expect(next.items.single.rank, 1);
  });

  test(
      'shared UI discovery preserves exact variants and removes temporary view',
      () async {
    await seed(1, score: 90, group: 'same');
    await seed(2, score: 90, group: 'same');
    await seed(3, score: 70, tags: {'Hack'});
    await seed(4, score: 99, platform: 'snes');
    final keys = [
      for (var i = 1; i <= 3; i++) coverRatingKey('psx', 'Game $i.7z')
    ];
    final result = (await query.discover(
        filter: LibraryQueryFilter(platformIds: {'psx'}, top: 1),
        orderedKeys: keys,
        isCurrent: () => true,
        assessedBases: [basis]))!;
    expect(result.groups.values.single.toSet(), keys.take(2).toSet());
    expect(result.totalMatches, 1);
    expect(result.collectionGames, 2);
    expect(result.genres, ['action']);
    expect(await db.query('library_query_views'), isEmpty);
    final empty = (await query.discover(
        filter:
            LibraryQueryFilter(platformIds: {'psx'}, top: 1, tags: {'Hack'}),
        orderedKeys: keys,
        isCurrent: () => true,
        assessedBases: [basis]))!;
    expect(empty.groups, isEmpty,
        reason: 'No refill from the lower-ranked hack');
    expect(empty.collectionGames, 2);
    var calls = 0;
    expect(
        await query.discover(
            filter: LibraryQueryFilter(),
            orderedKeys: keys,
            isCurrent: () => ++calls < 2,
            assessedBases: [basis]),
        isNull);
    expect(await db.query('library_query_views'), isEmpty);
  });

  test(
      'UI view binds exact files after ranking with no title match or backfill',
      () async {
    await seed(1, score: 90);
    await seed(2, score: 80);
    await seed(3, score: 70);
    await seed(4, score: 99, platform: 'snes');
    await db.update('games', {'filename': 'Same.7z'}, where: 'id IN (3,4)');
    final bindings = await query.replaceViewCacheMembers('ui:test', [
      coverRatingKey('psx', 'Same.7z'),
      coverRatingKey('psx', 'Game 1.7z'),
      coverRatingKey('psx', 'missing.7z')
    ], platformIds: {
      'psx'
    }, assessedBases: [
      basis
    ]);
    expect(bindings, {
      1: coverRatingKey('psx', 'Game 1.7z'),
      3: coverRatingKey('psx', 'Same.7z')
    });
    final page = await read(
        filter: LibraryQueryFilter(
            platformIds: {'psx'},
            top: 2,
            viewIds: {'ui:test'},
            includeVariants: true));
    expect(page.items.map((i) => i.cacheRowId), [1]);
    expect(page.collectionGames, 3);
    expect(page.rankedGames, 3);
    await db.insert('games', {
      'id': 5,
      'systemSlug': 'psx',
      'filename': 'Same.7z',
      'displayName': 'duplicate'
    });
    final ambiguous = await query.replaceViewCacheMembers(
        'ui:test', [coverRatingKey('psx', 'Same.7z')],
        platformIds: {'psx'}, assessedBases: [basis]);
    expect(ambiguous, isEmpty);
    expect((await read(filter: LibraryQueryFilter(viewIds: {'ui:test'}))).items,
        isEmpty);
  });

  test('new unscraped cache rows belong to collection and affect coverage',
      () async {
    await seed(1, score: 90);
    await read();
    await db
        .insert('games', {'id': 2, 'systemSlug': 'psx', 'displayName': 'New'});
    final result = await read(filter: LibraryQueryFilter(top: 25));
    expect(result.collectionGames, 2);
    expect(result.rankedGames, 1);
    expect(result.provisional, isTrue);
    expect((await read()).items, hasLength(2));
    await db.update('games', {'displayName': 'Renamed'}, where: 'id = 2');
    expect(
        (await read(filter: LibraryQueryFilter(search: 'Renamed')))
            .items
            .single
            .title,
        'Renamed');
  });

  test('unrated edition cannot display an invented rank from a rated region',
      () async {
    await seed(1, score: 90, group: 'shared');
    final unrated = await seed(2, group: 'shared', regions: ['Europe']);
    final result = await read(filter: LibraryQueryFilter(regions: {'Europe'}));
    expect(result.items.single.editionId, unrated);
    expect(result.items.single.score, isNull);
    expect(result.items.single.rank, isNull);
    expect(
        (await read(filter: LibraryQueryFilter(top: 25, regions: {'Europe'})))
            .items,
        isEmpty);
  });

  test('conflicting accepted edition scores leave group unresolved', () async {
    await seed(1, score: 90, group: 'shared');
    await seed(2, score: 80, group: 'shared');
    final result = await read(filter: LibraryQueryFilter(top: 25));
    expect(result.collectionGames, 1);
    expect(result.rankedGames, 0);
    expect(result.items, isEmpty);
    expect(result.provisional, isTrue);
  });

  test('reviewed provider bridges recompute ranks without borrowing scores',
      () async {
    final a = await seed(1, score: 95);
    final b = await seed(2, score: 90);
    final c = await seed(3, score: 80);
    Future<void> assign(String id, Map<String, String> providers) async {
      final edition = (await store.edition(id))!;
      final game = (await store.game(edition.gameId))!;
      await store.putGame(GameIdentity.fromJson({
        ...game.toJson(),
        'providerIds': providers,
      }));
    }

    await assign(a, {'screenscraper': '1'});
    await assign(b, {'igdb': '2'});
    expect((await read()).collectionGames, 3);
    await assign(c, {'screenscraper': '1', 'igdb': '2'});
    final joined = await read(filter: LibraryQueryFilter(top: 25));
    expect(joined.collectionGames, 1);
    expect(joined.rankedGames, 1);
    expect(joined.items.single.editionId, b);
    expect(joined.items.single.score!.rating.normalizedValue, 90);
    final owned =
        await store.effectiveRatings([a, b, c], assessedBases: [basis]);
    expect(owned[a], isNull);
    expect(owned[c], isNull,
        reason: 'Grouping cannot transfer exact score ownership.');
    expect(owned[b]!.rating.normalizedValue, 90);
    expect((await store.canonicalEditions(b)).editions, hasLength(3));

    await assign(c, {'screenscraper': '1', 'igdb': '3'});
    final split = await read(filter: LibraryQueryFilter(top: 1));
    expect(split.collectionGames, 2);
    expect(split.rankedGames, 2);
    expect(split.items.single.editionId, b);
    expect(split.items.single.rank, 1);
    await query.replaceViewMembers('shelf:other', [a, c]);
    expect(
        (await read(
                filter: LibraryQueryFilter(top: 1, viewIds: {'shelf:other'})))
            .items,
        isEmpty,
        reason: 'Changing the view cannot refill Top 1 with the lower group.');
  });

  test('successful score publication recomputes ranks under the same policy',
      () async {
    final a = await seed(1, score: 90);
    final b = await seed(2, score: 80);
    expect(
        (await read(filter: LibraryQueryFilter(top: 1))).items.single.editionId,
        a);
    final previous = (await store.metadata(b, 'igdb'))!;
    final next = SourcedRating.parse(
        sourceId: 'igdb',
        sourceLabel: 'IGDB',
        providerGameId: previous.providerGameId,
        rawValue: 95,
        scaleMinimum: 0,
        scaleMaximum: 100,
        voteCount: 100,
        kind: RatingKind.overallAggregate,
        retrievedAt: at)!;
    await store.putMetadata(MetadataRecord.fromJson({
      ...previous.toJson(),
      'refreshGeneration': 2,
      'ratings': [next.toJson()]
    }));
    final result = await read(filter: LibraryQueryFilter(top: 1));
    expect(result.items.single.editionId, b);
    expect(result.items.single.score!.rating.normalizedValue, 95);
  });

  test('manual shelf keeps its first matching edition of a canonical game',
      () async {
    final a = await seed(1, score: 90, group: 'shared');
    final b = await seed(2, score: 90, group: 'shared');
    await query.replaceViewMembers('shelf', [a, b]);
    expect(
        (await read(
                filter: LibraryQueryFilter(
                    viewIds: {'shelf'}, manualViewId: 'shelf')))
            .items
            .single
            .editionId,
        a);
    await query.replaceViewMembers('shelf', [b, a]);
    expect(
        (await read(
                filter: LibraryQueryFilter(
                    viewIds: {'shelf'}, manualViewId: 'shelf')))
            .items
            .single
            .editionId,
        b);
  });

  test(
      'ambiguous raw match cannot publish genre facets through another consumer',
      () async {
    final id = await seed(1);
    final edition = (await store.edition(id))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(
        GameIdentity.fromJson({...game.toJson(), 'matchStatus': 'ambiguous'}));
    await store.putMetadata(MetadataRecord(
        gameId: game.id,
        editionId: id,
        platformId: 'psx',
        providerId: 'screenscraper',
        providerGameId: '1',
        retrievedAt: at,
        refreshGeneration: 1,
        matchMethod: 'rawRomHashAndSize',
        titles: [
          MetadataText(text: 'Fixture')
        ],
        genres: [
          MetadataGenre(
              providerGenreId: '1', names: [MetadataText(text: 'Puzzle')])
        ]));
    expect((await read(filter: LibraryQueryFilter(genres: {'Puzzle'}))).items,
        isEmpty);
    expect((await read()).items, hasLength(1),
        reason: 'Ambiguity cannot hide ordinary browsing.');
  });
}
