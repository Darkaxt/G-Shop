import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/metadata/effective_overall_rating.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
      systemSlug TEXT, displayName TEXT, artifact_key TEXT, remote_artifact TEXT,
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
    await db.insert(
        'games', {'id': n, 'systemSlug': platform, 'displayName': 'Game $n'});
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
