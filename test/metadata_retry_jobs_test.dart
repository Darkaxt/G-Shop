import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';

class _Provider implements MetadataProvider {
  final calls = <MetadataLookupRequest>[];
  bool repaired = false;
  bool reviewOnly = false;
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
    calls.add(request);
    if (reviewOnly) {
      return MetadataLookupResult(
          status: MetadataLookupStatus.needsReview,
          message: 'Review changed identity');
    }
    if (!repaired && request.title != 'Successful') {
      return MetadataLookupResult(
          status: request.title == 'Unmatched'
              ? MetadataLookupStatus.unmatched
              : MetadataLookupStatus.invalidResponse,
          message: 'Unresolved');
    }
    return MetadataLookupResult(
        status: MetadataLookupStatus.matched,
        message: 'Matched',
        record: MetadataRecord(
            gameId: request.gameId,
            editionId: request.editionId,
            platformId: request.platformId,
            providerId: providerId,
            providerGameId: request.verifiedProviderGameId ?? '42',
            retrievedAt: DateTime.utc(2026),
            refreshGeneration: request.refreshGeneration,
            matchMethod: 'verifiedProviderId',
            titles: [MetadataText(text: request.title)]));
  }
}

void main() {
  late Database db;
  late LibraryStore store;
  late MetadataRefreshJobs jobs;
  late _Provider provider;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db
        .execute('''CREATE TABLE games (id INTEGER PRIMARY KEY AUTOINCREMENT,
      systemSlug TEXT NOT NULL, displayName TEXT NOT NULL, filename TEXT,
      is_folder INTEGER NOT NULL DEFAULT 0, artifact_key TEXT, remote_artifact TEXT)''');
    store = LibraryStore(Future.value(db));
    jobs = MetadataRefreshJobs(Future.value(db));
    provider = _Provider();
    for (final name in ['Successful', 'Unmatched', 'Failed']) {
      await db.insert('games', {
        'systemSlug': 'snes', 'displayName': name, 'filename': '$name.sfc'
      });
    }
  });
  tearDown(() async {
    await jobs.pause();
    await db.close();
  });

  test(
      'explicit retry snapshots only failed and unmatched items in a new generation',
      () async {
    final original =
        await jobs.createFromCatalogue(providerId: provider.providerId);
    final completed = await jobs.run(original.id, provider);
    expect(
        completed.counts, {'matched': 1, 'unmatched': 1, 'invalidResponse': 1});
    final successful = (await db.query('library_metadata')).single;
    provider.repaired = true;
    final retry = await jobs.retryUnresolved(original.id);
    expect(retry.generation, greaterThan(original.generation));
    expect(retry.collectionGeneration, original.collectionGeneration);
    expect(retry.counts, {'pending': 2});
    final result = await jobs.run(retry.id, provider);
    expect(result.counts, {'matched': 2});
    expect(result.requested, 2);
    expect(provider.calls.where((request) => request.title == 'Successful'),
        hasLength(1));
    expect((await jobs.report(original.id)).counts, completed.counts);
    expect(
        (await db.query('library_metadata',
                where: 'edition_id = ?', whereArgs: [successful['edition_id']]))
            .single['generation_id'],
        original.generation);
  });

  test(
      'retry captures corrected identity and reports removed members explicitly',
      () async {
    final original =
        await jobs.createFromCatalogue(providerId: provider.providerId);
    await jobs.run(original.id, provider);
    final rows = await db.query('metadata_refresh_items',
        where: 'job_id = ? AND status = ?',
        whereArgs: [original.id, 'unmatched']);
    final edition = (await store.edition(rows.single['edition_id'] as String))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'title': 'Corrected',
      'providerIds': {'screenscraper': '99'},
      'matchStatus': 'manuallyMatched'
    }));
    await db.delete('games', where: 'displayName = ?', whereArgs: ['Failed']);
    provider.repaired = true;
    final retry = await jobs.retryUnresolved(original.id);
    expect(retry.counts, {'pending': 1, 'identityChanged': 1});
    final result = await jobs.run(retry.id, provider);
    expect(result.counts, {'matched': 1, 'identityChanged': 1});
    expect(provider.calls.last.title, 'Corrected');
    expect(provider.calls.last.verifiedProviderGameId, '99');
  });

  test('an explicit unmatched-only retry does not repeat other failures',
      () async {
    final original =
        await jobs.createFromCatalogue(providerId: provider.providerId);
    await jobs.run(original.id, provider);
    final retry =
        await jobs.retryUnresolved(original.id, statuses: {'unmatched'});
    expect(retry.counts, {'pending': 1});
    provider.repaired = true;
    await jobs.run(retry.id, provider);
    expect(provider.calls.last.title, 'Unmatched');
    await expectLater(jobs.retryUnresolved(original.id, statuses: {'matched'}),
        throwsArgumentError);
  });

  test(
      'retry refreshes changed exact bytes without discarding the prior correction',
      () async {
    await db.delete('games');
    RemoteArtifact artifact(String checksum) => RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: 'source',
            accountId: 'account',
            providerFileId: 'file'),
        displayPath: 'Game.zip',
        displayName: 'Game.zip',
        sizeBytes: 100,
        providerChecksums: {'md5': checksum * 32});
    await db.insert('games', {
      'systemSlug': 'snes',
      'displayName': 'Unmatched',
      'artifact_key': artifact('a').id.key,
      'remote_artifact': jsonEncode(artifact('a').toJson())
    });
    final original =
        await jobs.createFromCatalogue(providerId: provider.providerId);
    await jobs.run(original.id, provider);
    final editionId = (await db.query('metadata_refresh_items'))
        .single['edition_id'] as String;
    final edition = (await store.edition(editionId))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'providerIds': {'screenscraper': '99'},
      'matchStatus': 'manuallyMatched'
    }));
    await db.update(
        'games', {'remote_artifact': jsonEncode(artifact('b').toJson())});
    provider.reviewOnly = true;
    final retry = await jobs.retryUnresolved(original.id);
    expect(retry.counts, {'pending': 1});
    final result = await jobs.run(retry.id, provider);
    expect(result.counts, {'needsReview': 1});
    expect(provider.calls.last.verifiedProviderGameId, isNull);
    expect((await store.game(game.id))!.providerIds, {'screenscraper': '99'});
    expect(await db.query('library_metadata'), isEmpty);
  });
}
