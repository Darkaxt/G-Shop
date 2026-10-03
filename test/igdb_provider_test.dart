import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/services/metadata/igdb_provider.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/metadata/effective_overall_rating.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final Object games;
  int gameStatus = 200;
  int tokenStatus = 200;
  Future<void> Function()? beforeGames;
  _Transport(this.games);
  @override
  Future<ResponseBody> fetch(RequestOptions request, Stream<Uint8List>? body,
      Future<void>? cancel) async {
    requests.add(request);
    final token = request.uri.host == 'id.twitch.tv';
    if (!token) await beforeGames?.call();
    return ResponseBody.fromString(
        jsonEncode(token
            ? {
                'access_token': 'fixture-token',
                'expires_in': 3600,
                'token_type': 'bearer'
              }
            : games),
        token ? tokenStatus : gameStatus,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          if (gameStatus == 429) 'retry-after': ['2']
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  final fixture = {
    'id': 123,
    'name': 'Super Mario World',
    'platforms': [19],
    'game_type': {'type': 'Main Game'},
    'rating': 89.0,
    'rating_count': 200,
    'aggregated_rating': 94.0,
    'aggregated_rating_count': 12,
    'total_rating': 91.5,
    'total_rating_count': 212
  };
  MetadataLookupRequest request(
          {String? id,
          String platform = 'snes',
          Set<String> tags = const {'official'}}) =>
      MetadataLookupRequest(
          gameId: 'game',
          editionId: 'edition',
          platformId: platform,
          title: 'Super Mario World',
          verifiedProviderGameId: id,
          contentTags: tags,
          refreshGeneration: 1);
  IgdbMetadataProvider provider(_Transport transport,
          {DateTime Function()? clock}) =>
      IgdbMetadataProvider(
          httpClientAdapter: transport,
          clock: clock,
          readCredentials: () async =>
              const IgdbCredentials('fixture-id', 'fixture-secret'));

  test('title discovery needs review and cannot publish an extreme score',
      () async {
    final transport = _Transport([fixture]);
    final api = provider(transport);
    addTearDown(api.close);
    final result = await api.lookup(request());
    expect(result.status, MetadataLookupStatus.needsReview);
    expect(result.record, isNull);
    expect(result.candidates.single.providerGameId, '123');
    expect(result.candidates.single.titleMatched, isTrue);
  });

  test(
      'verified lookup preserves externally defined total and independent counts',
      () async {
    final transport = _Transport([fixture]);
    final api = provider(transport);
    addTearDown(api.close);
    final result = await api.lookup(request(id: '123'));
    expect(result.status, MetadataLookupStatus.matched);
    final ratings = result.record!.ratings;
    expect(ratings.map((r) => r.sourceLabel),
        ['IGDB overall', 'IGDB critics', 'IGDB users']);
    expect(ratings.map((r) => r.originalValue), [91.5, 94.0, 89.0]);
    expect(ratings.map((r) => r.voteCount), [212, 12, 200]);
    expect(ratings.map((r) => r.kind), [
      RatingKind.overallAggregate,
      RatingKind.criticAggregate,
      RatingKind.communityAggregate
    ]);
    expect(ratings.every((r) => !r.consensusValidated), isTrue);
    expect(result.quota!.maxRequestsPerMinute, 240);
    final token = transport.requests.first;
    expect(token.uri.toString(), 'https://id.twitch.tv/oauth2/token');
    expect(token.queryParameters, isEmpty);
    expect(token.data['grant_type'], 'client_credentials');
    final lookup = transport.requests.last;
    expect(lookup.uri.toString(), 'https://api.igdb.com/v4/games');
    expect(lookup.headers['Client-ID'], 'fixture-id');
    expect(lookup.headers['Authorization'], 'Bearer fixture-token');
    expect(lookup.followRedirects, isFalse);
    expect(lookup.data, contains('where id = 123'));
    expect(
        jsonEncode(result.record!.toJson()), isNot(contains('fixture-secret')));
  });

  test('wrong platform and base IDs on hacks cannot transfer scores', () async {
    final api = provider(_Transport([fixture]));
    addTearDown(api.close);
    expect((await api.lookup(request(id: '123', platform: 'psx'))).status,
        MetadataLookupStatus.unmatched);
    final hack = await api.lookup(request(id: '123', tags: {'Hack'}));
    expect(hack.status, MetadataLookupStatus.needsReview);
    expect(hack.record, isNull);
  });

  test('reviewed original-game modifications can retrieve labelled facts',
      () async {
    final api = provider(_Transport([fixture]));
    addTearDown(api.close);
    for (final tags in [
      {'T-Eng'},
      {'Dub'},
      {'Undub'},
      {'Uncensor'},
      {'T-Eng', 'Undub', 'Uncensor'}
    ]) {
      final result = await api.lookup(request(id: '123', tags: tags));
      expect(result.status, MetadataLookupStatus.matched);
      expect(result.record!.matchMethod, 'verifiedProviderIdGlobalGame');
      expect(result.record!.ratings.first.normalizedValue, 91.5);
    }
    for (final tags in [
      {'unknown'},
      {'official', 'T-Eng'},
      {'Hack', 'T-Eng'},
      {'demo'}
    ]) {
      expect((await api.lookup(request(id: '123', tags: tags))).record, isNull);
    }
    final modApi = provider(_Transport([
      {
        ...fixture,
        'game_type': {'type': 'Mod'}
      }
    ]));
    addTearDown(modApi.close);
    expect((await modApi.lookup(request(id: '123', tags: {'T-Eng'}))).record,
        isNull,
        reason: 'A mod/project score is not the original-game score.');
  });

  test('normal reviewed modification reaches offline original-score query',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db
        .execute('''CREATE TABLE games (id INTEGER PRIMARY KEY AUTOINCREMENT,
      systemSlug TEXT NOT NULL, displayName TEXT NOT NULL,
      is_folder INTEGER NOT NULL DEFAULT 0, artifact_key TEXT, remote_artifact TEXT)''');
    await LibraryQuery.install(db);
    await db.insert('games',
        {'systemSlug': 'snes', 'displayName': 'Super Mario World translation'});
    final jobs = MetadataRefreshJobs(Future.value(db));
    final api = provider(_Transport([fixture]));
    addTearDown(api.close);
    final store = LibraryStore(Future.value(db));
    final seed = await jobs.createFromCatalogue(providerId: 'igdb');
    final editionId = (await db.query('metadata_refresh_items',
            where: 'job_id = ?', whereArgs: [seed.id]))
        .single['edition_id'] as String;
    final edition = (await store.edition(editionId))!;
    final identity = (await store.game(edition.gameId))!;
    await store.putGame(GameIdentity(
        id: 'base',
        platformId: 'snes',
        title: 'Super Mario World',
        providerIds: {'igdb': '123'},
        matchStatus: IdentityMatchStatus.manuallyMatched));
    await store.putGame(
        GameIdentity.fromJson({...identity.toJson(), 'baseGameId': 'base'}));
    final first = await jobs.createFromCatalogue(providerId: 'igdb');
    await jobs.run(first.id, api);
    final review = (await jobs.reviewItems(first.id)).single;
    final retry = await jobs.acceptCandidate(first.id,
        editionId: review.editionId,
        providerGameId: '123',
        contentTags: {'T-Eng', 'Undub', 'Uncensor'});
    final completed = await jobs.run(retry.id, api);
    expect(completed.counts, {'matched': 1});
    api.close();
    final score =
        (await store.effectiveRatings([review.editionId]))[review.editionId]!;
    expect(score.ownership, OverallRatingOwnership.originalGame);
    expect(score.rankingEligible, isFalse);
    final result = await LibraryQuery(Future.value(db)).page(
        filter: LibraryQueryFilter(
            tags: {'T-Eng', 'Undub', 'Uncensor'}, matchAllTags: true));
    expect(result.items.single.editionId, review.editionId);
    expect(result.items.single.score!.ownership,
        OverallRatingOwnership.originalGame);
    expect(result.items.single.rank, isNull);
    // Changing the explicitly linked base invalidates ownership, not the patch
    // identity or cached evidence. Dirty projections must reflect that change.
    await store.putGame(GameIdentity(
        id: 'base',
        platformId: 'snes',
        title: 'Other base',
        providerIds: {'igdb': '999'},
        matchStatus: IdentityMatchStatus.manuallyMatched));
    expect(
        (await LibraryQuery(Future.value(db))
                .page(filter: LibraryQueryFilter()))
            .items
            .single
            .score,
        isNull);
    expect(await store.metadata(review.editionId, 'igdb'), isNotNull);
    await store.putGame(GameIdentity(
        id: 'base',
        platformId: 'snes',
        title: 'Super Mario World',
        providerIds: {'igdb': '123'},
        matchStatus: IdentityMatchStatus.manuallyMatched));
    final refresh = await jobs.createFromCatalogue(providerId: 'igdb');
    expect(refresh.counts, {'pending': 1});
    expect(
        (await LibraryQuery(Future.value(db))
                .page(filter: LibraryQueryFilter()))
            .items
            .single
            .score!
            .fresh,
        isFalse);
    final changingBase = _Transport([fixture])
      ..beforeGames = () => store.putGame(GameIdentity(
          id: 'base',
          platformId: 'snes',
          title: 'Changed while retrieving facts',
          providerIds: {'igdb': '999'},
          matchStatus: IdentityMatchStatus.manuallyMatched));
    final refreshedApi = provider(changingBase);
    addTearDown(refreshedApi.close);
    final rejected = await jobs.run(refresh.id, refreshedApi);
    expect(rejected.counts, {'invalidResponse': 1});
    expect((await store.metadata(review.editionId, 'igdb'))!.refreshGeneration,
        retry.id,
        reason:
            'A changed base cannot publish the returned original-game facts.');
    expect(
        (await LibraryQuery(Future.value(db))
                .page(filter: LibraryQueryFilter()))
            .items
            .single
            .score,
        isNull);
  });

  test('missing counts stay unknown and missing total is not computed locally',
      () async {
    final api = provider(_Transport([
      {...fixture}
        ..remove('total_rating')
        ..remove('rating_count')
        ..remove('aggregated_rating_count')
    ]));
    addTearDown(api.close);
    final ratings = (await api.lookup(request(id: '123'))).record!.ratings;
    expect(ratings.map((r) => r.sourceLabel), ['IGDB critics', 'IGDB users']);
    expect(ratings.every((r) => r.voteCount == null), isTrue);
  });

  test('token expiry renews before next lookup without repeating game requests',
      () async {
    var now = DateTime.utc(2026);
    final transport = _Transport([fixture]);
    final api = provider(transport, clock: () => now);
    addTearDown(api.close);
    await api.lookup(request(id: '123'));
    await api.lookup(request(id: '123'));
    now = now.add(const Duration(hours: 1));
    await api.lookup(request(id: '123'));
    expect(transport.requests.where((r) => r.uri.host == 'id.twitch.tv').length,
        2);
    expect(transport.requests.where((r) => r.uri.host == 'api.igdb.com').length,
        3);
  });

  test('throttling is typed and retains protocol retry-after', () async {
    final transport = _Transport([])..gameStatus = 429;
    final api = provider(transport);
    addTearDown(api.close);
    final result = await api.lookup(request());
    expect(result.status, MetadataLookupStatus.throttled);
    expect(result.retryAfter, const Duration(seconds: 2));
    expect(result.toString(), isNot(contains('fixture-token')));
  });

  test('authentication rejection never attempts the game endpoint', () async {
    final transport = _Transport([])..tokenStatus = 403;
    final api = provider(transport);
    addTearDown(api.close);
    final result = await api.lookup(request());
    expect(result.status, MetadataLookupStatus.authenticationRequired);
    expect(transport.requests.length, 1);
    expect(result.record, isNull);
    expect(result.message, isNot(contains('fixture-secret')));
  });

  test('missing credentials and unsupported systems make no HTTP requests',
      () async {
    final transport = _Transport([]);
    final api = IgdbMetadataProvider(
        httpClientAdapter: transport, readCredentials: () async => null);
    addTearDown(api.close);
    expect((await api.lookup(request())).status,
        MetadataLookupStatus.setupRequired);
    expect((await api.lookup(request(platform: 'unmapped'))).status,
        MetadataLookupStatus.unsupportedPlatform);
    expect(transport.requests, isEmpty);
  });

  test('oversized provider response is rejected without cached metadata',
      () async {
    final api = provider(_Transport([
      {...fixture, 'summary': 'x' * (4 * 1024 * 1024 + 1)}
    ]));
    addTearDown(api.close);
    final result = await api.lookup(request(id: '123'));
    expect(result.status, MetadataLookupStatus.invalidResponse);
    expect(result.record, isNull);
  });

  test('project-specific mod score cannot be replaced by a base-game score',
      () async {
    final api = provider(_Transport([
      {
        ...fixture,
        'game_type': {'type': 'Mod'},
        'total_rating_count': 2
      }
    ]));
    addTearDown(api.close);
    final result = await api.lookup(request(id: '123', tags: {'Hack'}));
    expect(result.status, MetadataLookupStatus.matched);
    expect(result.record!.matchMethod, 'verifiedProjectId');
    expect(result.record!.ratings.first.voteCount, 2);
    expect(result.record!.ratings.first.consensusValidated, isFalse);
  });

  test(
      'normal persistent jobs recover access, review identity and cache sourced scores',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db
        .execute('''CREATE TABLE games (id INTEGER PRIMARY KEY AUTOINCREMENT,
      systemSlug TEXT NOT NULL, displayName TEXT NOT NULL,
      is_folder INTEGER NOT NULL DEFAULT 0, artifact_key TEXT, remote_artifact TEXT)''');
    await db.insert(
        'games', {'systemSlug': 'snes', 'displayName': 'Super Mario World'});
    final jobs = MetadataRefreshJobs(Future.value(db));
    final original =
        await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await db.query('metadata_refresh_items',
            where: 'job_id = ?', whereArgs: [original.id]))
        .single['edition_id'] as String;
    final store = LibraryStore(Future.value(db));
    final edition = (await store.edition(editionId))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'providerIds': {'screenscraper': '42'},
      'matchStatus': 'manuallyMatched',
      'evidence': [
        ...game.evidence.map((e) => e.toJson()),
        IdentityEvidence(
            source: 'manual',
            kind: 'providerId',
            value: jsonEncode(['screenscraper', '42'])).toJson()
      ]
    }));
    await store.putEdition(EditionIdentity.fromJson({
      ...edition.toJson(),
      'tags': ['official'],
      'isTranslation': false,
      'translatedLanguages': <String>[],
      'evidence': [
        ...edition.evidence.map((e) => e.toJson()),
        IdentityEvidence(
            source: 'manual',
            kind: 'contentClassification',
            value: jsonEncode(['official'])).toJson()
      ]
    }));
    await store.putMetadata(MetadataRecord(
        gameId: game.id,
        editionId: editionId,
        platformId: 'snes',
        providerId: 'screenscraper',
        providerGameId: '42',
        retrievedAt: DateTime.utc(2026),
        refreshGeneration: 1,
        matchMethod: 'verifiedProviderId',
        titles: const [MetadataText(text: 'Super Mario World')]));
    final transport = _Transport([fixture])..tokenStatus = 403;
    final api = provider(transport);
    addTearDown(api.close);
    final snapshot = await jobs.createFromCatalogue(providerId: api.providerId);
    final blocked = await jobs.run(snapshot.id, api);
    expect(blocked.state, 'blocked');
    expect(blocked.counts, {'pending': 1});
    expect(await store.metadata(editionId, 'screenscraper'), isNotNull);
    transport.tokenStatus = 200;
    final resumed = await jobs.run(snapshot.id, api);
    expect(resumed.state, 'completed');
    expect(resumed.counts, {'needsReview': 1});
    final review = (await jobs.reviewItems(snapshot.id)).single;
    final retry = await jobs.acceptCandidate(snapshot.id,
        editionId: review.editionId,
        providerGameId: review.candidates.single.providerGameId,
        contentTags: {'official'});
    final accepted = await jobs.run(retry.id, api);
    expect(accepted.counts, {'matched': 1});
    expect(accepted.rated, 1);
    api.close();
    final cached = await LibraryStore(Future.value(db))
        .metadata(review.editionId, api.providerId);
    expect(cached!.ratings.first.normalizedValue, 91.5);
    expect(cached.ratings.first.voteCount, 212);
    expect(cached.ratings.first.consensusValidated, isFalse);
    expect(await store.metadata(editionId, 'screenscraper'), isNotNull,
        reason: 'normal IGDB review cannot invalidate another verified source');
    final calls = transport.requests.length;
    await jobs.run(retry.id, api);
    expect(transport.requests.length, calls,
        reason: 'Completed work cannot repeat HTTP on resume.');
  });
}
