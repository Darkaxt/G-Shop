import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/metadata/igdb_provider.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final Object games;
  int gameStatus = 200;
  int tokenStatus = 200;
  _Transport(this.games);
  @override
  Future<ResponseBody> fetch(RequestOptions request, Stream<Uint8List>? body,
      Future<void>? cancel) async {
    requests.add(request);
    final token = request.uri.host == 'id.twitch.tv';
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
    final transport = _Transport([fixture])..tokenStatus = 403;
    final api = provider(transport);
    addTearDown(api.close);
    final jobs = MetadataRefreshJobs(Future.value(db));
    final snapshot = await jobs.createFromCatalogue(providerId: api.providerId);
    final blocked = await jobs.run(snapshot.id, api);
    expect(blocked.state, 'blocked');
    expect(blocked.counts, {'pending': 1});
    expect(await db.query('library_metadata'), isEmpty);
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
    final calls = transport.requests.length;
    await jobs.run(retry.id, api);
    expect(transport.requests.length, calls,
        reason: 'Completed work cannot repeat HTTP on resume.');
  });
}
