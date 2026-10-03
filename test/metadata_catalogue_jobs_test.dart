import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';

class _ReviewProvider implements MetadataProvider {
  int calls = 0;
  Future<void> Function()? beforeResult;
  @override
  String get providerId => 'screenscraper';
  @override
  MetadataProviderCapabilities get capabilities =>
      const MetadataProviderCapabilities(
          fields: {},
          verifiedIdLookup: true,
          rawRomLookup: false,
          titleSearch: true,
          documentedVoteCounts: false);
  @override
  void close() {}
  @override
  Future<MetadataLookupResult> lookup(MetadataLookupRequest request,
      {CancelToken? cancelToken}) async {
    calls++;
    await beforeResult?.call();
    return MetadataLookupResult(
        status: MetadataLookupStatus.needsReview,
        message: 'Review required',
        candidates: [
          MetadataLookupCandidate(
              providerGameId: '42',
              platformId: request.platformId,
              titles: [MetadataText(text: request.title)],
              titleMatched: true,
              evidence: 'platformAndTitle')
        ]);
  }
}

void main() {
  late Database db;
  late MetadataRefreshJobs jobs;
  late LibraryStore store;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games (
      id INTEGER PRIMARY KEY AUTOINCREMENT, systemSlug TEXT NOT NULL,
      filename TEXT NOT NULL, displayName TEXT NOT NULL,
      is_folder INTEGER NOT NULL DEFAULT 0, artifact_key TEXT,
      remote_artifact TEXT)''');
    jobs = MetadataRefreshJobs(Future.value(db));
    store = LibraryStore(Future.value(db));
  });
  tearDown(() => db.close());

  Future<int> cache(String system, String name,
          {RemoteArtifact? artifact, bool folder = false}) =>
      db.insert('games', {
        'systemSlug': system,
        'filename': name,
        'displayName': name.split(' (').first.split('.').first,
        'is_folder': folder ? 1 : 0,
        'artifact_key': artifact?.id.key,
        'remote_artifact':
            artifact == null ? null : jsonEncode(artifact.toJson()),
      });

  RemoteArtifact remote(String file,
          {String account = 'account',
          String version = '1',
          String checksum = 'a'}) =>
      RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: 'source',
            accountId: account,
            providerFileId: file),
        displayPath: 'Super Mario World (USA).zip',
        displayName: 'Super Mario World (USA).zip',
        version: version,
        sizeBytes: 100,
        providerChecksums: {'md5': checksum * 32},
      );

  Future<List<Map<String, Object?>>> items(int job) =>
      db.query('metadata_refresh_items',
          where: 'job_id = ?', whereArgs: [job], orderBy: 'edition_id');

  test(
      'cached catalogue snapshots all games, excludes folders and scopes systems',
      () async {
    await cache('snes', 'Super Mario World (USA).zip',
        artifact: remote('file'));
    await cache('nes', 'Super Mario Bros.nes');
    await cache('nes', 'Folder', folder: true);
    final full = await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect(full.counts, {'pending': 2});
    final scoped = await jobs.createFromCatalogue(
        providerId: 'screenscraper', systemSlug: 'snes');
    final request =
        jsonDecode((await items(scoped.id)).single['request_json'] as String);
    expect(scoped.counts, {'pending': 1});
    expect(request['platformId'], 'snes');
    expect(request['romIdentifier'], isNull,
        reason: 'ZIP checksums are not raw-ROM identifiers.');
    expect(request['contentTags'], isEmpty,
        reason: 'Official release classification requires evidence.');
    expect(request['verifiedProviderGameId'], isNull);
    await cache('gba', 'Added later.gba');
    expect((await items(full.id)).length, 2,
        reason: 'Published job membership is immutable.');
  });

  test('exact artifact rename and cache reinsertion preserve reviewed identity',
      () async {
    final id = await cache('snes', 'Original.zip', artifact: remote('file'));
    final first = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await items(first.id)).single['edition_id'] as String;
    final edition = (await store.edition(editionId))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'title': 'Corrected title',
      'providerIds': {'screenscraper': '42'},
      'matchStatus': 'manuallyMatched'
    }));
    await store.putEdition(EditionIdentity.fromJson({
      ...edition.toJson(),
      'tags': ['official']
    }));
    await db.delete('games', where: 'id = ?', whereArgs: [id]);
    await cache('snes', 'Renamed.zip', artifact: remote('file', version: '2'));
    final refreshed =
        await jobs.createFromCatalogue(providerId: 'screenscraper');
    final next = (await items(refreshed.id)).single;
    expect(next['edition_id'], editionId);
    final request = jsonDecode(next['request_json'] as String);
    expect(request['verifiedProviderGameId'], '42');
    expect(request['title'], 'Corrected title');
    expect(request['contentTags'], ['official']);
  });

  test('same names in other accounts cannot share a game or edition', () async {
    await cache('snes', 'Same.zip', artifact: remote('file', account: 'one'));
    await cache('snes', 'Same.zip', artifact: remote('file', account: 'two'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final records = await items(job.id);
    expect(records.map((row) => row['edition_id']).toSet().length, 2);
    expect((await db.query('library_game_identities')).length, 2);
  });

  test(
      'changed remote bytes require renewed review without deleting correction evidence',
      () async {
    final id = await cache('snes', 'Game.zip', artifact: remote('file'));
    final first = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await items(first.id)).single['edition_id'] as String;
    final edition = (await store.edition(editionId))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'providerIds': {'screenscraper': '42'},
      'matchStatus': 'manuallyMatched'
    }));
    await db.update(
        'games',
        {
          'remote_artifact':
              jsonEncode(remote('file', version: '2', checksum: 'b').toJson())
        },
        where: 'id = ?',
        whereArgs: [id]);
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final request =
        jsonDecode((await items(job.id)).single['request_json'] as String);
    expect(request['verifiedProviderGameId'], isNull);
    expect((await store.game(game.id))!.providerIds, {'screenscraper': '42'});
  });

  test(
      'reviewed candidate and independent tags persist atomically with retry snapshot',
      () async {
    await cache('snes', 'Super Mario World.zip', artifact: remote('file'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, _ReviewProvider());
    final review = (await jobs.reviewItems(job.id)).single;
    expect(review.status, 'needsReview');
    expect(review.candidates.single.providerGameId, '42');
    final retry = await jobs.acceptCandidate(job.id,
        editionId: review.editionId,
        providerGameId: '42',
        contentTags: {'T-Eng', 'Undub', 'Uncensor'});
    expect(retry.generation, greaterThan(job.generation));
    expect(retry.counts, {'pending': 1});
    final request =
        jsonDecode((await items(retry.id)).single['request_json'] as String);
    expect(request['verifiedProviderGameId'], '42');
    expect(request['contentTags'], ['T-Eng', 'Uncensor', 'Undub']);
    expect((await store.edition(review.editionId))!.isTranslation, isTrue);
    expect(
        (await store.edition(review.editionId))!.translatedLanguages, ['en']);
    final refresh = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final persisted =
        jsonDecode((await items(refresh.id)).single['request_json'] as String);
    expect(persisted['verifiedProviderGameId'], '42');
    expect(persisted['contentTags'], request['contentTags']);
    expect(await store.metadata(review.editionId, 'screenscraper'), isNull);
  });

  test(
      'reviewed tag aliases persist canonical classification and retry evidence',
      () async {
    await cache('snes', 'Fixture.zip', artifact: remote('file'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, _ReviewProvider());
    final review = (await jobs.reviewItems(job.id)).single;
    final retry = await jobs.acceptCandidate(job.id,
        editionId: review.editionId,
        providerGameId: '42',
        contentTags: {' T-En ', 'undubbed', 'UNCENSORED'});
    final request =
        jsonDecode((await items(retry.id)).single['request_json'] as String);
    expect(request['contentTags'], ['T-Eng', 'Uncensor', 'Undub']);
    final edition = (await store.edition(review.editionId))!;
    expect(edition.isTranslation, isTrue);
    expect(edition.translatedLanguages, ['en']);
    expect(
        jsonDecode(edition.evidence
            .singleWhere((e) => e.kind == 'contentClassification')
            .value),
        request['contentTags']);
    final refreshed =
        await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect(
        jsonDecode((await items(refreshed.id)).single['request_json']
            as String)['contentTags'],
        request['contentTags']);
    expect(await store.metadata(review.editionId, 'screenscraper'), isNull);
  });

  test(
      'catalogue review groups verified conversions without confusing changed bytes',
      () async {
    final firstRow = await cache('snes', 'Game.zip', artifact: remote('zip'));
    await cache('snes', 'Game.sfc', artifact: remote('raw'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, _ReviewProvider());
    final reviews = await jobs.reviewItems(job.id);
    expect(reviews, hasLength(2));
    for (final review in reviews) {
      await jobs.acceptCandidate(job.id,
          editionId: review.editionId,
          providerGameId: '42',
          contentTags: {'official'});
    }
    final anchor = reviews.first.editionId;
    expect((await store.canonicalEditions(anchor)).editions, hasLength(2));
    await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect((await store.canonicalEditions(anchor)).editions, hasLength(2),
        reason: 'Re-scraping retains reviewed grouping and exact members.');

    await db.update('games',
        {'remote_artifact': jsonEncode(remote('zip', checksum: 'b').toJson())},
        where: 'id = ?', whereArgs: [firstRow]);
    final unchanged =
        reviews.singleWhere((r) => r.editionId != anchor).editionId;
    // Either selected anchor can be the changed artifact. The unchanged exact
    // member remains browsable; the changed object's prior binding is rejected.
    final ids = <String>{};
    for (final id in [anchor, unchanged]) {
      ids.addAll((await store.canonicalEditions(id)).editions.map((e) => e.id));
    }
    expect(ids, hasLength(1));
    await jobs.createFromCatalogue(providerId: 'screenscraper');
    for (final review in reviews) {
      expect((await store.canonicalEditions(review.editionId)).editions,
          hasLength(1),
          reason: 'Changed bytes return to their unmatched group.');
    }
  });

  test(
      'unoffered candidate and conflicting official tags roll back review and retry',
      () async {
    await cache('snes', 'Game.zip', artifact: remote('file'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, _ReviewProvider());
    final review = (await jobs.reviewItems(job.id)).single;
    for (final input in [
      ('999', <String>{'official'}),
      ('42', <String>{'official', 'Hack'}),
    ]) {
      await expectLater(
          jobs.acceptCandidate(job.id,
              editionId: review.editionId,
              providerGameId: input.$1,
              contentTags: input.$2),
          throwsStateError);
    }
    expect((await db.query('metadata_refresh_jobs')).length, 1);
    final edition = (await store.edition(review.editionId))!;
    expect((await store.game(edition.gameId))!.providerIds, isEmpty);
  });

  test('removed or changed catalogue objects cannot finish an old lookup',
      () async {
    for (final duringLookup in [false, true]) {
      await db.delete('games');
      final id = await cache('snes', 'Game.zip', artifact: remote('file'));
      final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
      final provider = _ReviewProvider();
      Future<void> change() async => db.update(
          'games',
          {
            'remote_artifact':
                jsonEncode(remote('file', checksum: 'b').toJson())
          },
          where: 'id = ?',
          whereArgs: [id]);
      if (duringLookup) {
        provider.beforeResult = change;
      } else {
        await change();
      }
      final result = await jobs.run(job.id, provider);
      expect(result.counts, {'identityChanged': 1});
      expect(provider.calls, duringLookup ? 1 : 0);
      expect(await jobs.reviewItems(job.id), isEmpty);
    }
  });

  test('cached result stays usable after rename but cannot rate changed bytes',
      () async {
    final id = await cache('snes', 'Game.zip', artifact: remote('file'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await items(job.id)).single['edition_id'] as String;
    final edition = (await store.edition(editionId))!;
    await store.putMetadata(MetadataRecord(
        gameId: edition.gameId,
        editionId: editionId,
        platformId: 'snes',
        providerId: 'screenscraper',
        providerGameId: '42',
        retrievedAt: DateTime.utc(2026),
        refreshGeneration: job.generation,
        matchMethod: 'verifiedProviderId',
        titles: const [MetadataText(text: 'Example')]));
    await db.update(
        'games',
        {
          'displayName': 'Renamed',
          'remote_artifact': jsonEncode(remote('file', version: '2').toJson())
        },
        where: 'id = ?',
        whereArgs: [id]);
    expect(await store.metadata(editionId, 'screenscraper'), isNotNull);
    await db.update('games',
        {'remote_artifact': jsonEncode(remote('file', checksum: 'b').toJson())},
        where: 'id = ?', whereArgs: [id]);
    expect(await store.metadata(editionId, 'screenscraper'), isNull);
    expect(await db.query('library_metadata'), hasLength(1),
        reason: 'Prior evidence is retained, not erased.');
  });

  test(
      'official review clears translation flags instead of labelling English as T-Eng',
      () async {
    await cache('snes', 'Game.zip', artifact: remote('file'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, _ReviewProvider());
    final review = (await jobs.reviewItems(job.id)).single;
    await jobs.acceptCandidate(job.id,
        editionId: review.editionId,
        providerGameId: '42',
        contentTags: {'official'});
    final edition = (await store.edition(review.editionId))!;
    expect(edition.tags, {'official'});
    expect(edition.isTranslation, isFalse);
    expect(edition.translatedLanguages, isEmpty);
  });
}
