import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/services/metadata/screenscraper_provider.dart';
import 'package:retro_eshop/services/metadata/igdb_provider.dart';

class _Wire implements HttpClientAdapter {
  final Object response;
  final requests = <RequestOptions>[];
  _Wire(this.response);
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(
        jsonEncode(options.uri.host == 'id.twitch.tv'
            ? {
                'access_token': 'fixture-token',
                'expires_in': 3600,
                'token_type': 'bearer'
              }
            : response),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Database db;
  late LibraryStore store;
  final at = DateTime.utc(2026, 10, 3);
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await LibrarySchema.install(db);
    store = LibraryStore(Future.value(db));
  });
  tearDown(() => db.close());

  Future<void> seed(String id,
      {String platform = 'snes',
      String? providerId,
      Set<String> tags = const {'official'},
      String? base}) async {
    await store.putGame(GameIdentity(
        id: 'game:$id',
        platformId: platform,
        title: id,
        baseGameId: base,
        providerIds: providerId == null ? {} : {'igdb': providerId},
        matchStatus: providerId == null
            ? IdentityMatchStatus.unmatched
            : IdentityMatchStatus.manuallyMatched));
    await store.putEdition(EditionIdentity(
        id: id,
        gameId: 'game:$id',
        tags: tags,
        patchId: tags.contains('Hack') ? 'patch:$id' : null));
  }

  MetadataRecord matched(String id,
          {String provider = 'screenscraper',
          String providerId = '42',
          String platform = 'snes',
          String method = 'rawRomHashAndSize',
          int generation = 1}) =>
      MetadataRecord(
          gameId: 'game:$id',
          editionId: id,
          platformId: platform,
          providerId: provider,
          providerGameId: providerId,
          retrievedAt: at,
          refreshGeneration: generation,
          matchMethod: method,
          titles: [MetadataText(text: id)]);

  Future<String> key(String id) async =>
      (await db.query('library_canonical_groups',
              where: 'edition_id = ?', whereArgs: [id]))
          .single['group_key'] as String;

  Future<List<String>> catalogue() async {
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games (id INTEGER PRIMARY KEY,
      systemSlug TEXT, displayName TEXT, artifact_key TEXT, remote_artifact TEXT,
      is_folder INTEGER DEFAULT 0)''');
    await LibraryQuery.install(db);
    for (final n in [1, 2]) {
      await db.insert('games',
          {'id': n, 'systemSlug': 'snes', 'displayName': 'Fixture $n'});
    }
    return db
        .transaction((txn) => LibraryStore.catalogueEditions(txn).toList());
  }

  test(
      'normal raw lookup worker publishes one canonical game with exact editions',
      () async {
    final ids = await catalogue();
    final identifier = MetadataRomIdentifier(
        kind: RomIdentifierKind.rawRom,
        filename: 'Fixture.sfc',
        sizeBytes: 1024,
        sha1: 'a' * 40);
    for (final id in ids) {
      final edition = (await store.edition(id))!;
      await store.putEdition(EditionIdentity.fromJson({
        ...edition.toJson(),
        'tags': ['official'],
        'evidence': [
          ...edition.evidence.map((e) => e.toJson()),
          IdentityEvidence(
                  source: 'manual',
                  kind: 'rawRomIdentifier',
                  value: jsonEncode(identifier.toJson()))
              .toJson()
        ]
      }));
    }
    final jobs = MetadataRefreshJobs(Future.value(db));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final requests = await db.query('metadata_refresh_items',
        where: 'job_id = ?', whereArgs: [job.id]);
    expect(
        requests.map(
            (r) => jsonDecode(r['request_json'] as String)['romIdentifier']),
        everyElement(identifier.toJson()));
    final wire = _Wire({
      'response': {
        'jeu': {
          'id': '42',
          'systeme': {'id': '4'},
          'noms': [
            {'region': 'us', 'text': 'Fixture'}
          ],
          'note': {'text': '17'},
          'rom': {
            'romfilename': 'Fixture.sfc',
            'romsize': '1024',
            'romsha1': 'a' * 40,
            'hack': '0',
            'trad': '0'
          }
        }
      }
    });
    final api = ScreenScraperProvider(
        httpClientAdapter: wire,
        readDeveloperCredentials: () async =>
            const ScreenScraperDeveloperCredentials(
                developerId: 'fixture-dev',
                developerPassword: 'fixture-secret',
                softwareName: 'fixture'),
        readUserCredentials: () async => const ScreenScraperUserCredentials(
            username: 'fixture-user', password: 'fixture-secret'));
    addTearDown(api.close);
    final result = await jobs.run(job.id, api);
    expect(result.state, 'completed');
    expect(result.counts, {'matched': 2});
    expect(wire.requests, hasLength(2));
    expect(wire.requests.map((r) => r.uri.path),
        everyElement('/api2/jeuInfos.php'));
    expect(await key(ids.first), await key(ids.last));
    final page =
        await LibraryQuery(Future.value(db)).page(filter: LibraryQueryFilter());
    expect(page.collectionGames, 1);
    expect(page.items.single.score!.rating.normalizedValue, 85);
    expect(page.items.single.rank, isNull,
        reason: 'A raw identity match does not approve reception consensus.');
    expect((await store.canonicalEditions(ids.first)).editions, hasLength(2));
  });

  test('reviewed raw revision survives worker rejection and fresh re-scrape',
      () async {
    final ids = await catalogue();
    final raw = MetadataRomIdentifier(
        kind: RomIdentifierKind.rawRom,
        filename: 'Fixture (Rev 1).sfc',
        sizeBytes: 1024,
        crc32: 'ABCDEF12',
        md5: 'a' * 32,
        sha1: 'b' * 40);
    final originals = <String, String>{};
    for (final id in ids) {
      final edition = (await store.edition(id))!;
      final game = (await store.game(edition.gameId))!;
      await store.putGame(GameIdentity.fromJson({
        ...game.toJson(),
        'providerIds': {'screenscraper': '42'},
        'matchStatus': 'manuallyMatched'
      }));
      final reviewed = EditionIdentity.fromJson({
        ...edition.toJson(),
        'tags': ['official'],
        'regions': ['USA'],
        'languages': ['en'],
        'revision': 'Rev 1',
        'providerIds': {'screenscraper': '42'},
        'evidence': [
          ...edition.evidence.map((e) => e.toJson()),
          IdentityEvidence(
                  source: 'manual',
                  kind: 'rawRomIdentifier',
                  value: jsonEncode(raw.toJson()))
              .toJson()
        ]
      });
      await store.putEdition(reviewed);
      originals[id] = jsonEncode(reviewed.toJson());
    }
    Map<String, dynamic> gameResponse() => {
          'id': '42',
          'systeme': {'id': '4'},
          'noms': [
            {'region': 'us', 'text': 'Fixture'}
          ],
          'note': {'text': '17'},
          'rom': {
            'romfilename': raw.filename,
            'romsize': '1024',
            'romcrc': raw.crc32,
            'rommd5': raw.md5,
            'romsha1': raw.sha1,
            'romregions': 'us',
            'romlangues': 'en',
            'hack': '0',
            'trad': '0'
          }
        };
    final jobs = MetadataRefreshJobs(Future.value(db));
    final wires = <_Wire>[];
    Future<MetadataRefreshReport> refresh(Map<String, dynamic> game) async {
      final wire = _Wire({
        'response': {'jeu': game}
      });
      wires.add(wire);
      final api = ScreenScraperProvider(
          httpClientAdapter: wire,
          readDeveloperCredentials: () async =>
              const ScreenScraperDeveloperCredentials(
                  developerId: 'fixture-dev',
                  developerPassword: 'fixture-secret',
                  softwareName: 'fixture'),
          readUserCredentials: () async => const ScreenScraperUserCredentials(
              username: 'fixture-user', password: 'fixture-secret'));
      addTearDown(api.close);
      final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
      final snapshots = await db.query('metadata_refresh_items',
          where: 'job_id = ?', whereArgs: [job.id]);
      for (final row in snapshots) {
        final request = jsonDecode(row['request_json'] as String) as Map;
        expect(request['verifiedProviderGameId'], '42');
        expect(request['revision'], 'Rev 1');
        expect(request['romIdentifier'], raw.toJson());
      }
      final result = await jobs.run(job.id, api);
      expect(result.state, 'completed');
      expect(wire.requests, hasLength(2));
      for (final request in wire.requests) {
        expect(request.uri.path, '/api2/jeuInfos.php');
        expect(request.queryParameters.containsKey('gameid'), isFalse);
        expect(request.queryParameters['crc'], raw.crc32);
        expect(request.queryParameters['md5'], raw.md5);
        expect(request.queryParameters['sha1'], raw.sha1);
      }
      return result;
    }

    for (final field in [
      'id',
      'systeme',
      'romsize',
      'romcrc',
      'rommd5',
      'romsha1',
      'romregions',
      'romlangues'
    ]) {
      final game = gameResponse();
      if (field == 'id') {
        game[field] = '99';
      } else if (field == 'systeme') {
        game[field] = {'id': '1'};
      } else {
        (game['rom'] as Map)[field] = switch (field) {
          'romsize' => '2048',
          'romcrc' => '11111111',
          'rommd5' => 'c' * 32,
          'romsha1' => 'd' * 40,
          'romregions' => 'jp',
          _ => 'ja'
        };
      }
      expect((await refresh(game)).counts, {'unmatched': 2}, reason: field);
      expect(await db.query('library_metadata'), isEmpty, reason: field);
    }
    for (var pass = 0; pass < 2; pass++) {
      expect((await refresh(gameResponse())).counts, {'matched': 2});
      for (final id in ids) {
        final edition = (await store.edition(id))!;
        expect(jsonEncode(edition.toJson()), originals[id]);
        expect((await store.game(edition.gameId))!.providerIds,
            {'screenscraper': '42'});
      }
      final records = await db.query('library_metadata');
      expect(records, hasLength(2));
      expect(
          records.map(
              (row) => jsonDecode(row['record_json'] as String)['matchMethod']),
          everyElement('rawRomHashAndSize'));
    }
    final beforeRead = wires.fold<int>(0, (n, w) => n + w.requests.length);
    final page =
        await LibraryQuery(Future.value(db)).page(filter: LibraryQueryFilter());
    expect(page.collectionGames, 1);
    expect(page.items.single.score!.rating.normalizedValue, 85);
    expect(page.items.single.rank, isNull);
    final editions = (await store.canonicalEditions(ids.first)).editions;
    expect(editions.map((e) => e.id).toSet(), ids.toSet());
    expect(editions.map((e) => e.revision), everyElement('Rev 1'));
    expect(wires.fold<int>(0, (n, w) => n + w.requests.length), beforeRead,
        reason: 'Offline reads must not request metadata or ROM bodies.');
  });

  test('ambiguous raw evidence cannot choose a hash or promote file checksums',
      () async {
    final ids = await catalogue();
    final edition = (await store.edition(ids.first))!;
    await store.putEdition(EditionIdentity.fromJson({
      ...edition.toJson(),
      'tags': ['official'],
      'evidence': [
        for (final digest in ['a', 'b'])
          IdentityEvidence(
                  source: 'manual',
                  kind: 'rawRomIdentifier',
                  value: jsonEncode(MetadataRomIdentifier(
                          kind: RomIdentifierKind.rawRom,
                          filename: 'Fixture.sfc',
                          sizeBytes: 1024,
                          sha1: digest * 40)
                      .toJson()))
              .toJson()
      ]
    }));
    final job = await MetadataRefreshJobs(Future.value(db))
        .createFromCatalogue(providerId: 'screenscraper');
    final rows = await db.query('metadata_refresh_items',
        where: 'job_id = ?', whereArgs: [job.id]);
    expect(
        rows.map(
            (r) => jsonDecode(r['request_json'] as String)['romIdentifier']),
        everyElement(isNull));
    expect(await db.query('library_metadata'), isEmpty);
  });

  test('malformed explicit raw evidence remains unverified title discovery',
      () async {
    final ids = await catalogue();
    for (var index = 0; index < ids.length; index++) {
      final edition = (await store.edition(ids[index]))!;
      await store.putEdition(EditionIdentity.fromJson({
        ...edition.toJson(),
        'evidence': [
          IdentityEvidence(
                  source: 'manual',
                  kind: 'rawRomIdentifier',
                  value: index == 0
                      ? 'not json'
                      : '{"kind":"rawRom","filename":"Fixture.sfc","sizeBytes":-1}')
              .toJson()
        ]
      }));
    }
    final job = await MetadataRefreshJobs(Future.value(db))
        .createFromCatalogue(providerId: 'screenscraper');
    final rows = await db.query('metadata_refresh_items',
        where: 'job_id = ?', whereArgs: [job.id]);
    expect(
        rows.map(
            (r) => jsonDecode(r['request_json'] as String)['romIdentifier']),
        everyElement(isNull));
    expect(await db.query('library_metadata'), isEmpty);
  });

  test(
      'normal IGDB project worker groups patches without borrowing original scores',
      () async {
    final ids = await catalogue();
    for (final id in ids) {
      final edition = (await store.edition(id))!;
      final game = (await store.game(edition.gameId))!;
      await store.putGame(GameIdentity.fromJson({
        ...game.toJson(),
        'title': 'Fixture Project',
        'providerIds': {'igdb': '99'},
        'matchStatus': 'manuallyMatched'
      }));
      await store.putEdition(EditionIdentity.fromJson({
        ...edition.toJson(),
        'tags': ['Hack'],
        'patchId': 'patch:$id'
      }));
    }
    final wire = _Wire([
      {
        'id': 99,
        'name': 'Fixture Project',
        'platforms': [19],
        'game_type': {'type': 'Mod'},
        'total_rating': 81,
        'total_rating_count': 20
      }
    ]);
    final api = IgdbMetadataProvider(
        httpClientAdapter: wire,
        readCredentials: () async =>
            const IgdbCredentials('fixture-id', 'fixture-secret'));
    addTearDown(api.close);
    final jobs = MetadataRefreshJobs(Future.value(db));
    final job = await jobs.createFromCatalogue(providerId: 'igdb');
    final result = await jobs.run(job.id, api);
    expect(result.state, 'completed');
    expect(result.counts, {'matched': 2});
    expect(await key(ids.first), await key(ids.last));
    final page = await LibraryQuery(Future.value(db))
        .page(filter: LibraryQueryFilter(tags: {'Hack'}));
    expect(page.collectionGames, 1);
    expect(page.items.single.score!.rating.normalizedValue, 81);
    expect(page.items.single.score!.ownership.name, 'project');
    expect(page.items.single.rank, isNull);
    expect(
        (await store.canonicalEditions(ids.first))
            .editions
            .map((e) => e.patchId)
            .toSet(),
        hasLength(2));
  });

  test('verified raw-ROM metadata joins renamed releases without assigning IDs',
      () async {
    await seed('raw-original');
    await seed('raw-renamed');
    await store.putMetadata(matched('raw-original'));
    await store.putMetadata(matched('raw-renamed'));
    expect(await key('raw-original'), await key('raw-renamed'));
    expect((await store.game('game:raw-original'))!.providerIds, isEmpty);
    expect(
        (await store.canonicalEditions('raw-original')).editions, hasLength(2));
  });

  test('raw match correction removes the bridge without discarding evidence',
      () async {
    for (final id in ['one', 'two']) {
      await seed(id);
      await store.putMetadata(matched(id));
    }
    expect(await key('one'), await key('two'));
    await store.putMetadata(matched('two', providerId: '43', generation: 2));
    expect(await key('one'), isNot(await key('two')));
    expect(
        (await store.metadata('one', 'screenscraper'))!.providerGameId, '42');
    expect(
        (await store.metadata('two', 'screenscraper'))!.providerGameId, '43');
    expect(await db.query('library_editions'), hasLength(2));
  });

  test('a raw match keeps explicit unscraped disc members in the same game',
      () async {
    await seed('disc-one');
    await store.putEdition(EditionIdentity(
        id: 'disc-two', gameId: 'game:disc-one', tags: {'official'}));
    await store.putMetadata(matched('disc-one'));
    expect(await key('disc-one'), await key('disc-two'));
  });

  test('verified modification project variants group separately from originals',
      () async {
    await seed('ordinary', providerId: '99');
    for (final id in ['project-a', 'project-b']) {
      await seed(id, providerId: '99', tags: {'Hack'});
      await store.putMetadata(matched(id,
          provider: 'igdb', providerId: '99', method: 'verifiedProjectId'));
    }
    expect(await key('project-a'), await key('project-b'));
    expect(await key('project-a'), isNot(await key('ordinary')));
    expect((await store.edition('project-a'))!.patchId, 'patch:project-a');
    expect((await store.edition('project-b'))!.patchId, 'patch:project-b');
  });

  test('changing linked base invalidates dependent project assertions',
      () async {
    await seed('base', providerId: '100');
    for (final id in ['project-a', 'project-b']) {
      await seed(id, providerId: '99', tags: {'Hack'}, base: 'game:base');
      await store.putMetadata(matched(id,
          provider: 'igdb', providerId: '99', method: 'verifiedProjectId'));
    }
    expect(await key('project-a'), await key('project-b'));
    await store.putGame(GameIdentity(
        id: 'game:base',
        platformId: 'snes',
        title: 'Corrected original',
        providerIds: {'igdb': '99'},
        matchStatus: IdentityMatchStatus.manuallyMatched));
    expect(await key('project-a'), isNot(await key('project-b')));
    expect(await db.query('library_metadata'), hasLength(2));
  });

  test('candidate container unknown wrong-platform and base matches stay apart',
      () async {
    await seed('valid');
    await store.putMetadata(matched('valid'));
    await seed('container');
    await store.putMetadata(matched('container', method: 'containerHash'));
    await seed('title');
    await store.putMetadata(matched('title', method: 'platformAndTitle'));
    await seed('unknown', tags: {});
    await store.putMetadata(matched('unknown'));
    await seed('hack', tags: {'Hack'});
    await store.putMetadata(matched('hack'));
    await seed('other-platform', platform: 'gba');
    await store.putMetadata(matched('other-platform', platform: 'gba'));
    final distinct = <String>{};
    for (final id in [
      'valid',
      'container',
      'title',
      'unknown',
      'hack',
      'other-platform'
    ]) {
      distinct.add(await key(id));
    }
    expect(distinct, hasLength(6));
  });

  test('stale metadata binding cannot restore a cleared raw grouping assertion',
      () async {
    for (final id in ['one', 'two']) {
      await seed(id);
      await store.putMetadata(matched(id));
    }
    expect(await key('one'), await key('two'));
    final edition = (await store.edition('two'))!;
    await store.putEdition(EditionIdentity.fromJson(
        {...edition.toJson(), 'revision': 'corrected release'}));
    expect(await key('one'), isNot(await key('two')));
    expect(await store.metadata('two', 'screenscraper'), isNull);
    await db.transaction(LibraryStore.indexCanonicalGroups);
    expect(await key('one'), isNot(await key('two')));
    expect(
        jsonDecode((await db.query('library_metadata',
                where: 'edition_id = ?', whereArgs: ['two']))
            .single['record_json'] as String)['providerGameId'],
        '42');
  });
}
