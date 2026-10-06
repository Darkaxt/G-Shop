import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/services/metadata/igdb_provider.dart';
import 'package:retro_eshop/services/metadata/screenscraper_provider.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/metadata/effective_overall_rating.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/services/metadata/shared_metadata_store.dart';
import 'package:sqflite/sqflite.dart';

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

/// Identical provider/worker ownership assertions on host and Android SQLite.
/// Credentials and wire responses are synthetic; no real token/API is requested.
void defineIgdbProviderChecks(DatabaseFactory factory) {
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
          MetadataCorroboration? corroboration,
          Set<String> tags = const {'official'}}) =>
      MetadataLookupRequest(
          gameId: 'game',
          editionId: 'edition',
          platformId: platform,
          title: 'Super Mario World',
          verifiedProviderGameId: id,
          corroboration: corroboration,
          contentTags: tags,
          refreshGeneration: 1);
  IgdbMetadataProvider provider(_Transport transport,
          {DateTime Function()? clock}) =>
      IgdbMetadataProvider(
          httpClientAdapter: transport,
          clock: clock,
          readCredentials: () async =>
              const IgdbCredentials('fixture-id', 'fixture-secret'));

  final corroboration = MetadataCorroboration(
      providerGameId: '456',
      recordHash: 'a' * 64,
      titles: ['Super Mario World'],
      releaseDate: '1990-11-21',
      region: 'jp',
      developer: 'Nintendo',
      publisher: 'Nintendo');
  final corroboratedWire = {
    ...fixture,
    'release_dates': [
      {
        'platform': 19,
        'date': DateTime.utc(1990, 11, 21).millisecondsSinceEpoch ~/ 1000,
        'date_format': {'format': 'YYYYMMDD'},
        'release_region': {'region': 'japan'}
      }
    ],
    'involved_companies': [
      {
        'company': {'name': 'Nintendo'},
        'developer': true,
        'publisher': true
      }
    ]
  };
  test('current hash-bound release facts corroborate one exact IGDB game',
      () async {
    final api = provider(_Transport([
      corroboratedWire,
      {...corroboratedWire, 'id': 124, 'name': 'Super Mario World 2'}
    ]));
    addTearDown(api.close);
    final result = await api.lookup(request(corroboration: corroboration));
    expect(result.status, MetadataLookupStatus.matched);
    expect(result.record!.providerGameId, '123');
    expect(result.record!.matchMethod, 'corroboratedOfficialRelease');
    expect(result.record!.matchEvidence, corroboration.toJson());
    expect(
        result.record!.ratings
            .singleWhere((r) => r.kind == RatingKind.communityAggregate)
            .voteCount,
        200);
    expect(
        MetadataLookupRequest.fromJson(
                request(corroboration: corroboration).toJson())
            .corroboration!
            .toJson(),
        corroboration.toJson());
  });
  test('corroboration rejects partial conflicting modified and duplicate facts',
      () async {
    for (final wire in [
      {...corroboratedWire, 'release_dates': []},
      {...corroboratedWire, 'name': 'Different release'},
      {
        ...corroboratedWire,
        'game_type': {'type': 'Mod'}
      },
      {...corroboratedWire, 'version_parent': 789},
      {
        ...corroboratedWire,
        'release_dates': [
          {
            'platform': 19,
            'date': DateTime.utc(1991, 11, 22).millisecondsSinceEpoch ~/ 1000,
            'date_format': {'format': 'YYYYMMDD'},
            'release_region': {'region': 'japan'}
          }
        ]
      },
      {
        ...corroboratedWire,
        'release_dates': [
          {
            'platform': 7,
            'date': DateTime.utc(1990, 11, 21).millisecondsSinceEpoch ~/ 1000,
            'date_format': {'format': 'YYYYMMDD'},
            'release_region': {'region': 'japan'}
          }
        ]
      },
      {
        ...corroboratedWire,
        'release_dates': [
          {
            'platform': 19,
            'date': DateTime.utc(1990, 11, 21).millisecondsSinceEpoch ~/ 1000,
            'date_format': {'format': 'YYYYMMDD'},
            'release_region': {'region': 'north_america'}
          }
        ]
      }
    ]) {
      final api = provider(_Transport([wire]));
      final result = await api.lookup(request(corroboration: corroboration));
      api.close();
      expect(result.status, isNot(MetadataLookupStatus.matched));
      expect(result.record, isNull);
    }
    final api = provider(_Transport([
      corroboratedWire,
      {...corroboratedWire, 'id': 124}
    ]));
    addTearDown(api.close);
    expect((await api.lookup(request(corroboration: corroboration))).status,
        MetadataLookupStatus.ambiguous);
    for (final tags in [
      <String>{},
      {'unknown'},
      {'Hack'},
      {'T-Eng'}
    ]) {
      expect(
          (await api.lookup(request(corroboration: corroboration, tags: tags)))
              .status,
          isNot(MetadataLookupStatus.matched));
    }
    final truncated = provider(_Transport([
      corroboratedWire,
      for (var n = 0; n < 29; n++)
        {...corroboratedWire, 'id': 124 + n, 'name': 'Other game $n'}
    ]));
    addTearDown(truncated.close);
    expect(
        (await truncated.lookup(request(corroboration: corroboration))).status,
        MetadataLookupStatus.ambiguous);
  });

  test('regional-year confidence ignores company wording and day discrepancies',
      () async {
    for (final kind in ['Main Game', 'Port', 'Bundle', 'Remake', 'Remaster']) {
      final wire = {
        ...corroboratedWire,
        'game_type': {'type': kind},
        if (kind == 'Port') 'parent_game': 789,
        'involved_companies': [],
        'release_dates': [
          {
            'platform': 19,
            'date': DateTime.utc(1990, 1, 1).millisecondsSinceEpoch ~/ 1000,
            'date_format': {'format': 'YYYY'},
            'release_region': {'region': 'japan'}
          }
        ]
      };
      final api = provider(_Transport([wire]));
      final result = await api.lookup(request(corroboration: corroboration));
      api.close();
      expect(result.status, MetadataLookupStatus.matched, reason: kind);
      expect(result.record!.providerGameId, '123',
          reason: 'Own edition record, never its parent.');
      expect(result.record!.matchEvidence, corroboration.toJson());
    }
  });

  test('saved legacy corroboration keeps its exact-fact policy', () async {
    final legacy = MetadataCorroboration.fromJson(
        {...corroboration.toJson()..remove('matchingPolicy')});
    final api = provider(_Transport([
      {...corroboratedWire, 'involved_companies': []}
    ]));
    addTearDown(api.close);
    expect((await api.lookup(request(corroboration: legacy))).record, isNull);
    expect(legacy.toJson().containsKey('matchingPolicy'), isFalse,
        reason: 'Reading an immutable old capture does not rewrite its facts.');
  });

  test('legacy capture retains its original any-exact-release rule', () async {
    final legacy = MetadataCorroboration.fromJson(
        {...corroboration.toJson()..remove('matchingPolicy')});
    final api = provider(_Transport([
      {
        ...corroboratedWire,
        'release_dates': [
          ...(corroboratedWire['release_dates'] as List),
          {
            'platform': 19,
            'date': DateTime.utc(1991).millisecondsSinceEpoch ~/ 1000,
            'date_format': {'format': 'YYYYMMDD'},
            'release_region': {'region': 'japan'}
          }
        ]
      }
    ]));
    addTearDown(api.close);
    expect((await api.lookup(request(corroboration: legacy))).status,
        MetadataLookupStatus.matched);
  });

  test('regional confidence rejects a conflicting same-region release year',
      () async {
    final api = provider(_Transport([
      {
        ...corroboratedWire,
        'release_dates': [
          ...(corroboratedWire['release_dates'] as List),
          {
            'platform': 19,
            'date': DateTime.utc(1991).millisecondsSinceEpoch ~/ 1000,
            'date_format': {'format': 'YYYY'},
            'release_region': {'region': 'japan'}
          }
        ]
      }
    ]));
    addTearDown(api.close);
    expect((await api.lookup(request(corroboration: corroboration))).record,
        isNull);
  });

  test('year-only facts round-trip without fabricating a day or companies', () {
    final facts = MetadataCorroboration(
        providerGameId: '456',
        recordHash: 'a' * 64,
        titles: ['Fixture'],
        releaseDate: '1990',
        region: 'jp',
        developer: '',
        publisher: '');
    expect(MetadataCorroboration.fromJson(facts.toJson()).toJson(),
        facts.toJson());
    expect(facts.releaseDate, '1990');
    final month = MetadataCorroboration.fromJson(
        {...facts.toJson(), 'releaseDate': '1990-11'});
    expect(month.releaseDate, '1990-11');
    expect(
        () => MetadataCorroboration.fromJson(
            {...facts.toJson(), 'releaseDate': '1990-13'}),
        throwsFormatException);
  });

  for (final changed in [false, true]) {
    test(
        'normal IGDB job ${changed ? 'rejects changed' : 'uses current'} ScreenScraper release evidence',
        () async {
      final db = await factory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await LibrarySchema.install(db);
      await MetadataRefreshJobs.install(db);
      await db.execute('''CREATE TABLE games (id INTEGER PRIMARY KEY,
        systemSlug TEXT, displayName TEXT, filename TEXT,
        is_folder INTEGER DEFAULT 0, artifact_key TEXT, remote_artifact TEXT)''');
      await LibraryQuery.install(db);
      await db.insert('games', {
        'id': 1,
        'systemSlug': 'psp',
        'displayName': 'Fixture container name',
        'filename': 'Fixture.chd'
      });
      final root =
          await Directory.systemTemp.createTemp('rshop-corroboration-');
      var shared = await SharedMetadataStore.open(root,
          factory: factory, verifyAccess: () async {});
      addTearDown(() async {
        await shared.close();
        await root.delete(recursive: true);
      });
      final jobs = MetadataRefreshJobs(Future.value(db),
          sharedStore: Future.value(shared));
      final seed = await jobs.createFromCatalogue(providerId: 'screenscraper');
      final editionId = (await jobs.reviewItems(seed.id)).isEmpty
          ? (await db.query('metadata_refresh_items',
                  where: 'job_id = ?', whereArgs: [seed.id]))
              .single['edition_id'] as String
          : throw StateError('Unexpected seed review');
      final store = LibraryStore(Future.value(db));
      final edition = (await store.edition(editionId))!;
      await store.putEdition(EditionIdentity.fromJson({
        ...edition.toJson(),
        'tags': ['official'],
        'regions': ['jp']
      }));
      final metadata = MetadataRecord(
          gameId: edition.gameId,
          editionId: editionId,
          platformId: 'psp',
          providerId: 'screenscraper',
          providerGameId: '456',
          retrievedAt: DateTime.utc(2026, 10, 6),
          refreshGeneration: 1,
          matchMethod: 'exactRegionalOfficialTitle',
          matchEvidence: {
            'matchingPolicy': 'regionalReleaseV1',
            'title': 'Super Mario World',
            'region': 'jp'
          },
          titles: [const MetadataText(text: 'Super Mario World')],
          releaseDates: [const MetadataText(text: '1990-11-21', region: 'jp')],
          developer: null,
          publisher: null,
          fieldProvenance: {
            for (final field in [
              'title',
              'releaseDate',
            ])
              field: MetadataFieldProvenance(
                  providerId: 'screenscraper',
                  providerGameId: '456',
                  field: field,
                  retrievedAt: DateTime.utc(2026, 10, 6))
          });
      await store.putMetadata(metadata);
      final snapshot = await jobs.createFromCatalogue(providerId: 'igdb');
      final wire = _Transport([
        {
          ...corroboratedWire,
          'platforms': [38],
          'release_dates': [
            {
              'platform': 38,
              'date': DateTime.utc(1990, 11, 21).millisecondsSinceEpoch ~/ 1000,
              'date_format': {'format': 'YYYYMMDD'},
              'release_region': {'region': 'japan'}
            }
          ]
        }
      ]);
      if (changed) {
        wire.beforeGames = () => store.putMetadata(MetadataRecord.fromJson({
              ...metadata.toJson(),
              'titles': [const MetadataText(text: 'Changed title').toJson()],
              'refreshGeneration': 2
            }));
      }
      final api = provider(wire);
      addTearDown(api.close);
      final report = await jobs.run(snapshot.id, api);
      expect(report.counts, {changed ? 'identityChanged' : 'matched': 1});
      final saved = await store.metadata(editionId, 'igdb');
      if (changed) {
        expect(saved, isNull);
      } else {
        expect(saved!.matchMethod, 'corroboratedOfficialRelease');
        expect(saved.matchEvidence['providerGameId'], '456');
        expect(
            (await store.effectiveRatings([editionId]))[editionId]!
                .rankingEligible,
            isTrue);
        final page = await LibraryQuery(Future.value(db))
            .page(filter: LibraryQueryFilter(top: 25));
        expect(page.items.single.editionId, editionId);
        expect(page.items.single.score!.rating.voteCount, 200);
        expect(page.provisional, isFalse);
        expect((await store.metadata(editionId, 'screenscraper'))!.toJson(),
            metadata.toJson(),
            reason: 'Corroboration does not rewrite its source.');
        await shared.close();
        shared = await SharedMetadataStore.open(root,
            factory: factory, existingOnly: true, verifyAccess: () async {});
        await db.delete('library_metadata',
            where: 'provider_id = ?', whereArgs: ['igdb']);
        expect(await shared.restore(db), 1);
        expect((await store.metadata(editionId, 'igdb'))!.toJson(),
            saved.toJson());
        final recovered = await LibraryQuery(Future.value(db))
            .page(filter: LibraryQueryFilter(top: 25));
        expect(recovered.items.single.editionId, editionId);
        expect(recovered.items.single.score!.rating.voteCount, 200);
      }
      expect(
          (wire.requests.last.data as String), contains('Super Mario World'));
      expect((wire.requests.last.data as String),
          isNot(contains('Fixture container')));
    });
  }

  test('normal two-provider workers bind regional title facts and rank offline',
      () async {
    final db = await factory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games (id INTEGER PRIMARY KEY,
      systemSlug TEXT, displayName TEXT, filename TEXT,
      is_folder INTEGER DEFAULT 0, artifact_key TEXT, remote_artifact TEXT)''');
    await LibraryQuery.install(db);
    for (var n = 1; n <= 2; n++) {
      await db.insert('games', {
        'id': n,
        'systemSlug': 'psp',
        'displayName': 'Super Mario World',
        'filename': 'Super Mario World (Japan) ($n).chd'
      });
    }
    final jobs = MetadataRefreshJobs(Future.value(db));
    final seed = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final store = LibraryStore(Future.value(db));
    final rows = await db.query('metadata_refresh_items',
        where: 'job_id = ?', whereArgs: [seed.id]);
    for (final row in rows) {
      final edition = (await store.edition(row['edition_id'] as String))!;
      await store.putEdition(EditionIdentity.fromJson({
        ...edition.toJson(),
        'tags': ['official']
      }));
    }
    final ssWire = _Transport({
      'response': {
        'jeux': [
          {
            'id': '456',
            'systeme': {'id': '61'},
            'notgame': 'false',
            'noms': [
              {'region': 'jp', 'text': 'Super Mario World'}
            ],
            'dates': [
              {'region': 'jp', 'text': '1990-11-21'}
            ],
            'synopses': [
              {'langue': 'en', 'text': 'Fixture description.'}
            ],
            'note': {'text': '18'}
          }
        ]
      }
    });
    final ss = ScreenScraperProvider(
        httpClientAdapter: ssWire,
        readDeveloperCredentials: () async =>
            const ScreenScraperDeveloperCredentials(
                developerId: 'fixture',
                developerPassword: 'fixture',
                softwareName: 'fixture'),
        readUserCredentials: () async => const ScreenScraperUserCredentials(
            username: 'fixture', password: 'fixture'));
    addTearDown(ss.close);
    final first = await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect((await jobs.run(first.id, ss)).counts, {'matched': 2});
    expect(
        (await LibraryQuery(Future.value(db))
                .page(filter: LibraryQueryFilter(top: 25)))
            .rankedGames,
        0,
        reason: 'ScreenScraper notes still cannot become reliable Top scores.');
    final wire = _Transport([
      {
        ...corroboratedWire,
        'platforms': [38],
        'involved_companies': [],
        'release_dates': [
          {
            'platform': 38,
            'date': DateTime.utc(1990, 1, 1).millisecondsSinceEpoch ~/ 1000,
            'date_format': {'format': 'YYYY'},
            'release_region': {'region': 'japan'}
          }
        ]
      }
    ]);
    final api = provider(wire);
    addTearDown(api.close);
    final second = await jobs.createFromCatalogue(providerId: 'igdb');
    expect((await jobs.run(second.id, api)).counts, {'matched': 2});
    final page = await LibraryQuery(Future.value(db))
        .page(filter: LibraryQueryFilter(top: 25));
    expect(page.collectionGames, 1);
    expect(page.rankedGames, 1);
    expect(page.items.single.score!.rating.voteCount, 200);
    final calls = wire.requests.length;
    await jobs.run(second.id, api);
    expect(wire.requests.length, calls);
  });

  test(
      'reviewed worker publication uses production community Top policy offline',
      () async {
    final db = await factory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db
        .execute('''CREATE TABLE games (id INTEGER PRIMARY KEY AUTOINCREMENT,
      systemSlug TEXT NOT NULL, displayName TEXT NOT NULL, filename TEXT,
      is_folder INTEGER NOT NULL DEFAULT 0, artifact_key TEXT, remote_artifact TEXT)''');
    await LibraryQuery.install(db);
    const titles = ['Supported fixture', 'Low vote project', 'Unrated fixture'];
    for (final title in titles) {
      await db.insert('games', {
        'systemSlug': 'psx',
        'displayName': title,
        'filename': '$title.chd'
      });
    }
    final wire = _Transport([
      {
        ...fixture,
        'name': titles[0],
        'platforms': [7],
        'rating': 90.0,
        'rating_count': 20,
        'aggregated_rating': 50.0,
        'aggregated_rating_count': 1,
        'total_rating': 70.0,
        'total_rating_count': 21,
      },
      {
        'id': 124,
        'name': titles[1],
        'platforms': [7],
        'game_type': {'type': 'Mod'},
        'rating': 100.0,
        'rating_count': 2,
        'total_rating': 100.0,
        'total_rating_count': 2,
      },
      {
        'id': 125,
        'name': titles[2],
        'platforms': [7],
        'game_type': {'type': 'Main Game'},
      }
    ]);
    final api = provider(wire);
    addTearDown(api.close);
    final jobs = MetadataRefreshJobs(Future.value(db));
    final store = LibraryStore(Future.value(db));
    final snapshot = await jobs.createFromCatalogue(providerId: 'igdb');
    expect((await jobs.run(snapshot.id, api)).counts, {'ambiguous': 3});
    final reviewItems = await jobs.reviewItems(snapshot.id);
    // Review pages use stable edition-ID order, not catalogue insertion order.
    final reviews = titles
        .map((title) => reviewItems.singleWhere((review) => review.candidates
            .any((candidate) =>
                candidate.titleMatched &&
                candidate.titles.any((text) => text.text == title))))
        .toList(growable: false);
    for (var n = 0; n < reviews.length; n++) {
      final review = reviews[n];
      final candidate = review.candidates.singleWhere(
          (c) => c.titleMatched && c.titles.any((t) => t.text == titles[n]));
      final retry = await jobs.acceptCandidate(snapshot.id,
          editionId: review.editionId,
          providerGameId: candidate.providerGameId,
          contentTags: n == 1 ? {'Hack'} : {'official'});
      expect((await jobs.run(retry.id, api)).counts, {'matched': 1});
    }
    api.close();
    final requestCount = wire.requests.length;
    final query = LibraryQuery(Future.value(db));
    final page = await query.page(filter: LibraryQueryFilter(top: 25));
    expect(page.collectionGames, 3);
    expect(page.rankedGames, 1);
    expect(page.provisional, isTrue);
    expect(page.items.single.editionId, reviews[0].editionId);
    final scores = await store.effectiveRatings(
        reviews.map((r) => r.editionId).toList(growable: false));
    final score = scores[reviews[0].editionId]!;
    expect(score.rating.kind, RatingKind.communityAggregate);
    expect(score.rating.sourceLabel, 'IGDB users');
    expect(score.rating.normalizedValue, 90);
    expect(score.rating.voteCount, 20);
    expect(page.items.single.score!.rating.toJson(), score.rating.toJson());
    expect(scores[reviews[1].editionId]!.ownership,
        OverallRatingOwnership.project);
    expect(scores[reviews[1].editionId]!.rankingEligible, isFalse);
    expect(scores[reviews[2].editionId], isNull);
    expect(
        (await query.page(filter: LibraryQueryFilter(top: 25, tags: {'Hack'})))
            .items,
        isEmpty);
    final current = (await store.metadata(reviews[0].editionId, 'igdb'))!;
    await store.putMetadata(MetadataRecord.fromJson({
      ...current.toJson(),
      'ratings': current.ratings
          .map((r) => {
                ...r.toJson(),
                if (r.kind == RatingKind.communityAggregate) 'voteCount': 19,
              })
          .toList(growable: false),
    }));
    expect(
        (await query.page(filter: LibraryQueryFilter(top: 25))).items, isEmpty);
    expect(wire.requests.length, requestCount,
        reason: 'Offline policy/query invalidation cannot contact a provider.');
  });

  test('title discovery includes multiplatform games and still requires review',
      () async {
    final transport = _Transport([
      {
        ...fixture,
        'platforms': [19, 5],
        'summary': 'Description of the provider candidate.'
      }
    ]);
    final api = provider(transport);
    addTearDown(api.close);
    final result = await api.lookup(request());
    expect(result.status, MetadataLookupStatus.needsReview);
    expect(result.record, isNull);
    expect(result.candidates.single.providerGameId, '123');
    expect(result.candidates.single.titleMatched, isTrue);
    expect(result.candidates.single.previewDescriptions.single.text,
        'Description of the provider candidate.');
    expect(transport.requests.last.data, contains('where platforms = (19);'),
        reason:
            'Scalar equality excludes originals released on other platforms.');
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

  for (final classification in [
    {'T-Eng', 'Undub', 'Uncensor'},
    {' t-en ', 'UNDUBBED', 'Uncensored'}
  ]) {
    test(
        'normal reviewed modification $classification reaches offline original-score query',
        () async {
      final db = await factory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await LibrarySchema.install(db);
      await MetadataRefreshJobs.install(db);
      await db
          .execute('''CREATE TABLE games (id INTEGER PRIMARY KEY AUTOINCREMENT,
      systemSlug TEXT NOT NULL, displayName TEXT NOT NULL, filename TEXT,
      is_folder INTEGER NOT NULL DEFAULT 0, artifact_key TEXT, remote_artifact TEXT)''');
      await LibraryQuery.install(db);
      await db.insert('games', {
        'systemSlug': 'snes',
        'displayName': 'Super Mario World translation',
        'filename': 'Super Mario World translation.sfc'
      });
      final jobs = MetadataRefreshJobs(Future.value(db));
      final wire = _Transport([fixture]);
      final api = provider(wire);
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
          contentTags: classification);
      expect(
          jsonDecode((await db.query('metadata_refresh_items',
                  where: 'job_id = ?', whereArgs: [retry.id]))
              .single['request_json'] as String)['contentTags'],
          ['T-Eng', 'Uncensor', 'Undub']);
      final completed = await jobs.run(retry.id, api);
      expect(completed.counts, {'matched': 1});
      api.close();
      final requestsBeforeOfflineRead = wire.requests.length;
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
      expect(wire.requests, hasLength(requestsBeforeOfflineRead),
          reason:
              'Offline score and tag queries do not fetch metadata or ROMs.');
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
      expect(
          (await store.metadata(review.editionId, 'igdb'))!.refreshGeneration,
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
  }

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
    final db = await factory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db
        .execute('''CREATE TABLE games (id INTEGER PRIMARY KEY AUTOINCREMENT,
      systemSlug TEXT NOT NULL, displayName TEXT NOT NULL, filename TEXT,
      is_folder INTEGER NOT NULL DEFAULT 0, artifact_key TEXT, remote_artifact TEXT)''');
    await db.insert('games', {
      'systemSlug': 'snes',
      'displayName': 'Super Mario World',
      'filename': 'Super Mario World.sfc'
    });
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
