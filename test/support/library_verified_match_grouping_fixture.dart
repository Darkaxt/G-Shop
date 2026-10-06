import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/services/metadata/screenscraper_provider.dart';
import 'package:retro_eshop/services/metadata/igdb_provider.dart';
import 'package:retro_eshop/services/metadata/shared_metadata_store.dart';

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

/// Exercise real adapters, persistent jobs and cached queries using the caller's
/// SQLite factory. All transport responses and in-memory catalogues are synthetic.
void defineVerifiedMatchGroupingChecks(DatabaseFactory factory) {
  late Database db;
  late LibraryStore store;
  final at = DateTime.utc(2026, 10, 3);
  setUp(() async {
    db = await factory.openDatabase(inMemoryDatabasePath);
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

  Future<List<String>> catalogue(
      {String platform = 'snes',
      bool rawDrive = false,
      bool chd = false}) async {
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games (id INTEGER PRIMARY KEY,
      systemSlug TEXT, displayName TEXT, artifact_key TEXT, remote_artifact TEXT,
      is_folder INTEGER DEFAULT 0)''');
    await LibraryQuery.install(db);
    for (final n in [1, 2]) {
      final artifact = RemoteArtifact(
          id: RemoteArtifactId(
              providerId: 'drive',
              sourceId: 'fixture-source',
              accountId: 'fixture-account',
              providerFileId: 'file-$n'),
          parentId: 'fixture-folder',
          canDownload: true,
          displayPath: 'Fixture $n.${chd ? 'chd' : 'sfc'}',
          displayName: 'Fixture $n.${chd ? 'chd' : 'sfc'}',
          version: '1',
          sizeBytes: 1024,
          providerChecksums: {'sha1': 'a' * 40});
      await db.insert('games', {
        'id': n,
        'systemSlug': platform,
        'displayName': 'Fixture $n',
        if (rawDrive) 'artifact_key': artifact.id.key,
        if (rawDrive) 'remote_artifact': jsonEncode(artifact.toJson())
      });
    }
    return db
        .transaction((txn) => LibraryStore.catalogueEditions(txn).toList());
  }

  Uint8List dvdHeader() {
    final bytes = Uint8List(140)..setRange(0, 8, 'MComprHD'.codeUnits);
    final data = ByteData.sublistView(bytes);
    data.setUint32(8, 124);
    data.setUint32(12, 5);
    data.setUint64(32, 1121026048);
    data.setUint64(48, 124);
    data.setUint32(56, 4096);
    data.setUint32(60, 2048);
    bytes.setRange(64, 84, List.filled(20, 0xaa));
    bytes.setRange(124, 128, 'DVD '.codeUnits);
    return bytes;
  }

  (_Wire, ScreenScraperProvider) chdProvider() {
    final wire = _Wire({
      'response': {
        'jeu': {
          'id': '42',
          'systeme': {'id': '61'},
          'notgame': false,
          'noms': [
            {'region': 'us', 'text': 'Fixture'}
          ],
          'synopsis': [
            {'langue': 'en', 'text': 'Fresh DVD description'}
          ],
          'rom': {
            'romsize': '1121026048',
            'romsha1': 'a' * 40,
            'romregions': 'us',
            'romlangues': 'en',
            'hack': '0',
            'trad': '0',
            'demo': '0',
            'unl': '0',
            'beta': '0'
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
    return (wire, api);
  }

  test(
      'normal jobs automatically bind current CHD header evidence and reuse it',
      () async {
    final ids = await catalogue(platform: 'psp', rawDrive: true, chd: true);
    final initial = await db.query('library_editions');
    final root = await Directory.systemTemp.createTemp('rshop-auto-header-');
    var shared = await SharedMetadataStore.open(root,
        factory: factory, verifyAccess: () async {});
    addTearDown(() async {
      await shared.close();
      await root.delete(recursive: true);
    });
    var reads = 0;
    final jobs =
        MetadataRefreshJobs(Future.value(db), sharedStore: Future.value(shared),
            readRomHeader: (artifact, platform, cancel) async {
      reads++;
      expect(platform, 'psp');
      expect(artifact.version, '1');
      return dvdHeader();
    });
    final (wire, api) = chdProvider();
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect((await jobs.run(job.id, api)).counts, {'matched': 2});
    expect(reads, 2);
    for (final id in ids) {
      final edition = (await store.edition(id))!;
      expect(edition.tags, {'official'});
      expect(
          edition.evidence.where(
              (e) => e.source == 'driveHeader' && e.kind == 'rawRomIdentifier'),
          hasLength(1));
      final source =
          edition.evidence.singleWhere((e) => e.kind == 'rawRomHeaderSource');
      expect(jsonDecode(source.value)['version'], '1');
      expect(jsonDecode(source.value)['bytesRead'], 140);
      expect(
          (await store.metadata(id, 'screenscraper'))!.descriptions.single.text,
          'Fresh DVD description');
    }
    expect(wire.requests.every((r) => r.queryParameters['sha1'] == 'a' * 40),
        isTrue);
    await db.transaction((txn) => LibraryStore.catalogueEditions(txn).toList());
    final restarted = MetadataRefreshJobs(Future.value(db),
        readRomHeader: (_, __, ___) async {
      fail('current persisted header must not be read again');
    });
    final next =
        await restarted.createFromCatalogue(providerId: 'screenscraper');
    expect((await restarted.run(next.id, api)).counts, {'matched': 2});
    expect(reads, 2);
    expect(await key(ids.first), await key(ids.last));
    await shared.close();
    shared = await SharedMetadataStore.open(root,
        factory: factory, existingOnly: true, verifyAccess: () async {});
    await db.delete('library_metadata');
    for (final row in initial) {
      await store.putEdition(
          EditionIdentity.fromJson(jsonDecode(row['record_json'] as String)));
    }
    expect(await shared.restore(db), 2,
        reason:
            'shared recovery restores generated header binding without another read');
    expect(
        (await store.edition(ids.first))!
            .evidence
            .where((e) => e.kind == 'rawRomIdentifier'),
        hasLength(1));
    expect(await store.metadata(ids.first, 'screenscraper'), isNotNull);
  });

  test('CHD header changed during read cannot publish evidence or metadata',
      () async {
    final ids = await catalogue(platform: 'psp', rawDrive: true, chd: true);
    final jobs = MetadataRefreshJobs(Future.value(db),
        readRomHeader: (artifact, _, __) async {
      final rows = await db.query('games',
          where: 'artifact_key = ?', whereArgs: [artifact.id.key]);
      final changed = RemoteArtifact.fromJson({
        ...artifact.toJson(),
        'version': '2',
        'providerChecksums': {'sha1': 'b' * 40}
      });
      await db.update(
          'games', {'remote_artifact': jsonEncode(changed.toJson())},
          where: 'id = ?', whereArgs: [rows.single['id']]);
      await db
          .transaction((txn) => LibraryStore.catalogueEditions(txn).toList());
      return dvdHeader();
    });
    final (wire, api) = chdProvider();
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect((await jobs.run(job.id, api)).counts, {'identityChanged': 2});
    expect(wire.requests, isEmpty);
    for (final id in ids) {
      expect(
          (await store.edition(id))!
              .evidence
              .where((e) => e.source == 'driveHeader'),
          isEmpty);
      expect(await store.metadata(id, 'screenscraper'), isNull);
    }
  });

  test('replacement CHD bytes retire generated evidence and get a fresh header',
      () async {
    final ids = await catalogue(platform: 'psp', rawDrive: true, chd: true);
    var reads = 0;
    final jobs = MetadataRefreshJobs(Future.value(db),
        readRomHeader: (artifact, _, __) async {
      reads++;
      return dvdHeader()
        ..fillRange(64, 84, artifact.version == '1' ? 0xaa : 0xbb);
    });
    final (wire, api) = chdProvider();
    var job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, api);
    final row = (await db.query('games', where: 'id = 1')).single;
    final artifact =
        RemoteArtifact.fromJson(jsonDecode(row['remote_artifact'] as String));
    await db.update(
        'games',
        {
          'remote_artifact': jsonEncode({
            ...artifact.toJson(),
            'version': '2',
            'providerChecksums': {'sha1': 'c' * 40}
          })
        },
        where: 'id = 1');
    await db.transaction((txn) => LibraryStore.catalogueEditions(txn).toList());
    expect(await store.metadata(ids.first, 'screenscraper'), isNull);
    job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, api);
    expect(reads, 3,
        reason: 'only the replaced artifact needs another bounded read');
    final edition = (await store.edition(ids.first))!;
    expect(
        jsonDecode(edition.evidence
            .singleWhere((e) => e.kind == 'rawRomIdentifier')
            .value)['sha1'],
        'b' * 40);
    expect(edition.evidence.where((e) => e.kind == 'previousRawRomIdentifier'),
        hasLength(1));
    expect(wire.requests.any((r) => r.queryParameters['sha1'] == 'b' * 40),
        isTrue);
    expect(await store.metadata(ids.first, 'screenscraper'), isNull,
        reason: 'old provider hash cannot identify the replacement');
  });

  for (final manual in ['unknown', 'raw']) {
    test('automatic CHD reads preserve manual $manual evidence', () async {
      final ids = await catalogue(platform: 'psp', rawDrive: true, chd: true);
      for (final id in ids) {
        final edition = (await store.edition(id))!;
        await store.putEdition(EditionIdentity.fromJson({
          ...edition.toJson(),
          'tags': ['unknown'],
          'evidence': [
            ...edition.evidence.map((e) => e.toJson()),
            IdentityEvidence(
                    source: 'manual',
                    kind: manual == 'raw'
                        ? 'rawRomIdentifier'
                        : 'contentClassification',
                    value: manual == 'raw' ? '{}' : 'unknown')
                .toJson()
          ]
        }));
      }
      final jobs = MetadataRefreshJobs(Future.value(db),
          readRomHeader: (_, __, ___) async {
        fail('must not override explicit manual evidence');
      });
      final (wire, api) = chdProvider();
      final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
      await jobs.run(job.id, api);
      expect(wire.requests.every((r) => r.queryParameters['sha1'] == null),
          isTrue);
      for (final id in ids) {
        expect(
            (await store.edition(id))!
                .evidence
                .where((e) => e.source == 'driveHeader'),
            isEmpty);
        expect(await store.metadata(id, 'screenscraper'), isNull);
      }
    });
  }

  test(
      'cancelled CHD header leaves pending job resumable without provider lookup',
      () async {
    await catalogue(platform: 'psp', rawDrive: true, chd: true);
    final jobs = MetadataRefreshJobs(Future.value(db),
        readRomHeader: (_, __, cancel) async {
      cancel.cancel();
      return dvdHeader();
    });
    final (wire, api) = chdProvider();
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final report = await jobs.run(job.id, api);
    expect(report.state, 'paused');
    expect(report.counts, {'pending': 2});
    expect(wire.requests, isEmpty);
    final resumed = MetadataRefreshJobs(Future.value(db),
        readRomHeader: (_, __, ___) async => dvdHeader());
    expect((await resumed.run(job.id, api)).counts, {'matched': 2});
  });

  test(
      'unsupported CHD layout stays review-only with no invented raw identifier',
      () async {
    final ids = await catalogue(platform: 'psp', rawDrive: true, chd: true);
    final jobs = MetadataRefreshJobs(Future.value(db),
        readRomHeader: (_, __, ___) async =>
            dvdHeader()..setRange(124, 128, 'CHT2'.codeUnits));
    final (wire, api) = chdProvider();
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, api);
    expect(
        wire.requests.every((r) => r.queryParameters['sha1'] == null), isTrue);
    for (final id in ids) {
      expect(
          (await store.edition(id))!
              .evidence
              .where((e) => e.source == 'driveHeader'),
          isEmpty);
      expect(await store.metadata(id, 'screenscraper'), isNull);
    }
  });

  test(
      'automatic Drive raw match persists classification and current metadata atomically',
      () async {
    final ids = await catalogue(rawDrive: true);
    final initial = await db.query('library_editions');
    final root = await Directory.systemTemp.createTemp('rshop-auto-identity-');
    var shared = await SharedMetadataStore.open(root,
        factory: factory, verifyAccess: () async {});
    addTearDown(() async {
      await shared.close();
      await root.delete(recursive: true);
    });
    final jobs = MetadataRefreshJobs(Future.value(db),
        sharedStore: Future.value(shared));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final wire = _Wire({
      'response': {
        'jeu': {
          'id': '42',
          'systeme': {'id': '4'},
          'notgame': false,
          'noms': [
            {'region': 'us', 'text': 'Fixture'}
          ],
          'synopsis': [
            {'langue': 'en', 'text': 'Fresh description'}
          ],
          'note': {'text': '17'},
          'rom': {
            'romsize': '1024',
            'romsha1': 'a' * 40,
            'romregions': 'us',
            'romlangues': 'en',
            'hack': '0',
            'trad': '0',
            'demo': '0',
            'unl': '0',
            'beta': '0'
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
    final report = await jobs.run(job.id, api);
    expect(report.counts, {'matched': 2});
    for (final id in ids) {
      final edition = (await store.edition(id))!;
      expect(edition.tags, {'official'});
      expect(edition.regions, ['us']);
      expect(edition.languages, ['en']);
      expect(edition.evidence.where((e) => e.kind == 'exactRomOfficialRelease'),
          hasLength(1));
      expect(
          (await store.metadata(id, 'screenscraper'))!.descriptions.single.text,
          'Fresh description');
      final saved = (await db.query('metadata_refresh_items',
              where: 'job_id = ? AND edition_id = ?', whereArgs: [job.id, id]))
          .single;
      final identity = (await db.rawQuery(
              '''SELECT g.record_json AS game_json, e.record_json AS edition_json
        FROM library_editions e JOIN library_game_identities g ON g.game_id=e.game_id
        WHERE e.edition_id=?''', [id]))
          .single;
      expect(saved['identity_key'],
          LibraryStore.metadataIdentity(identity, providerId: 'screenscraper'));
    }
    expect(await key(ids.first), await key(ids.last));
    await db.transaction((txn) => LibraryStore.catalogueEditions(txn).toList());
    expect(await store.metadata(ids.first, 'screenscraper'), isNotNull,
        reason: 'unchanged catalogue retains exact binding');
    final page =
        await LibraryQuery(Future.value(db)).page(filter: LibraryQueryFilter());
    expect(page.collectionGames, 1);
    expect(page.items.single.score!.rating.normalizedValue, 85);
    expect(page.items.single.rank, isNull);
    expect(wire.requests, hasLength(2),
        reason: 'metadata calls only; zero ROM-body requests');
    await shared.close();
    shared = await SharedMetadataStore.open(root,
        factory: factory, existingOnly: true, verifyAccess: () async {});
    await db.delete('library_metadata');
    for (final row in initial) {
      await store.putEdition(
          EditionIdentity.fromJson(jsonDecode(row['record_json'] as String)));
    }
    expect(await shared.restore(db), 2,
        reason:
            'durable cache restores the automatic identity with no repeated lookup');
    expect((await store.edition(ids.first))!.tags, {'official'});
    expect(await store.metadata(ids.first, 'screenscraper'), isNotNull);
    final row = (await db.query('games', where: 'id = 1')).single;
    final original =
        jsonDecode(row['remote_artifact'] as String) as Map<String, dynamic>;
    await db.update(
        'games',
        {
          'remote_artifact': jsonEncode({
            ...original,
            'displayName': 'Renamed.sfc',
            'displayPath': 'Renamed.sfc',
            'version': '2'
          })
        },
        where: 'id = 1');
    await db.transaction((txn) => LibraryStore.catalogueEditions(txn).toList());
    expect((await store.edition(ids.first))!.tags, {'official'});
    expect(await store.metadata(ids.first, 'screenscraper'), isNotNull);
    await db.update(
        'games',
        {
          'remote_artifact': jsonEncode({
            ...original,
            'providerChecksums': {'sha1': 'b' * 40},
            'version': '3'
          })
        },
        where: 'id = 1');
    await db.transaction((txn) => LibraryStore.catalogueEditions(txn).toList());
    final changed = (await store.edition(ids.first))!;
    expect(changed.tags, isEmpty,
        reason: 'a replacement blob cannot inherit official classification');
    expect(changed.isTranslation, isNull);
    expect(changed.regions, isEmpty);
    expect(changed.languages, isEmpty);
    expect(changed.evidence.where((e) => e.kind == 'exactRomOfficialRelease'),
        isEmpty);
    expect(
        changed.evidence
            .where((e) => e.kind == 'previousExactRomOfficialRelease'),
        hasLength(1));
    expect(await store.metadata(ids.first, 'screenscraper'), isNull);
    expect((await store.edition(ids.last))!.tags, {'official'});
  });

  test(
      'automatic raw classification preserves manual unknown and patch ownership',
      () async {
    final ids = await catalogue(rawDrive: true);
    final first = (await store.edition(ids.first))!;
    await store.putEdition(EditionIdentity.fromJson({
      ...first.toJson(),
      'tags': ['unknown'],
      'evidence': [
        ...first.evidence.map((e) => e.toJson()),
        IdentityEvidence(
                source: 'manual',
                kind: 'contentClassification',
                value: '["unknown"]')
            .toJson()
      ]
    }));
    final second = (await store.edition(ids.last))!;
    await store.putEdition(EditionIdentity.fromJson(
        {...second.toJson(), 'patchId': 'fixture-patch'}));
    final before = await db.query('library_editions');
    final jobs = MetadataRefreshJobs(Future.value(db));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final wire = _Wire({
      'response': {
        'jeu': {
          'id': '42',
          'systeme': {'id': '4'},
          'notgame': false,
          'noms': [
            {'region': 'us', 'text': 'Fixture'}
          ],
          'rom': {
            'romsize': '1024',
            'romsha1': 'a' * 40,
            'hack': '0',
            'trad': '0',
            'demo': '0',
            'unl': '0',
            'beta': '0'
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
    expect((await jobs.run(job.id, api)).counts, {'needsReview': 2});
    expect(await db.query('library_editions'), before);
    expect(await db.query('library_metadata'), isEmpty);
    expect(await key(ids.first), isNot(await key(ids.last)));
  });

  for (final capped in [false, true]) {
    test(
        'normal raw lookup worker publishes one canonical game with exact editions${capped ? ' and capped size' : ''}',
        () async {
      final ids = await catalogue(platform: capped ? 'ps2' : 'snes');
      final identifier = MetadataRomIdentifier(
          kind: capped ? RomIdentifierKind.rawIso : RomIdentifierKind.rawRom,
          filename: capped ? 'Fixture.iso' : 'Fixture.sfc',
          sizeBytes: capped ? 4440719360 : 1024,
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
            'systeme': {'id': capped ? '58' : '4'},
            'noms': [
              {'region': 'us', 'text': 'Fixture'}
            ],
            'note': {'text': '17'},
            'rom': {
              'romfilename': identifier.filename,
              'romsize': capped ? '2147483647' : '1024',
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
      final page = await LibraryQuery(Future.value(db))
          .page(filter: LibraryQueryFilter());
      expect(page.collectionGames, 1);
      expect(page.items.single.score!.rating.normalizedValue, 85);
      expect(page.items.single.rank, isNull,
          reason: 'A raw identity match does not approve reception consensus.');
      expect((await store.canonicalEditions(ids.first)).editions, hasLength(2));
      expect((await store.metadata(ids.first, 'screenscraper'))!.matchMethod,
          capped ? 'rawRomSha1AndCappedSize' : 'rawRomHashAndSize');
    });
  }

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
