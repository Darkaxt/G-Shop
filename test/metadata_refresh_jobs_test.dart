import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Provider implements MetadataProvider {
  final calls = <MetadataLookupRequest>[];
  Future<MetadataLookupResult> Function(MetadataLookupRequest, CancelToken?)?
      reply;
  @override
  String get providerId => 'screenscraper';
  @override
  MetadataProviderCapabilities get capabilities =>
      const MetadataProviderCapabilities(
          fields: {'titles', 'ratings'},
          verifiedIdLookup: true,
          rawRomLookup: true,
          titleSearch: true,
          documentedVoteCounts: false);
  @override
  Future<MetadataLookupResult> lookup(MetadataLookupRequest request,
      {CancelToken? cancelToken}) async {
    calls.add(request);
    if (reply == null) return _matched(request);
    return await reply!(request, cancelToken);
  }

  @override
  void close() {}
}

MetadataLookupResult _matched(MetadataLookupRequest request,
        {MetadataQuota? quota}) =>
    MetadataLookupResult(
        status: MetadataLookupStatus.matched,
        message: 'Matched',
        quota: quota,
        record: MetadataRecord(
            gameId: request.gameId,
            editionId: request.editionId,
            platformId: request.platformId,
            providerId: 'screenscraper',
            providerGameId: request.verifiedProviderGameId ?? '42',
            retrievedAt: DateTime.utc(2026, 9, 9),
            refreshGeneration: request.refreshGeneration,
            matchMethod: 'verifiedProviderId',
            titles: [
              MetadataText(text: request.title)
            ],
            ratings: [
              SourcedRating.parse(
                  sourceId: 'screenscraper',
                  sourceLabel: 'ScreenScraper',
                  providerGameId: request.verifiedProviderGameId ?? '42',
                  rawValue: '17',
                  scaleMinimum: 0,
                  scaleMaximum: 20,
                  kind: RatingKind.unknownAggregate,
                  retrievedAt: DateTime.utc(2026, 9, 9))!
            ]));

void main() {
  late Database db;
  late LibraryStore library;
  late MetadataRefreshJobs jobs;
  late _Provider provider;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    library = LibraryStore(Future.value(db));
    jobs = MetadataRefreshJobs(Future.value(db));
    provider = _Provider();
  });
  tearDown(() async {
    await jobs.pause();
    await db.close();
  });

  Future<void> seed(String editionId,
      {String gameId = 'g1', String? platform = 'psx'}) async {
    await library.putGame(GameIdentity(
        id: gameId,
        title: 'Example $gameId',
        platformId: platform,
        providerIds: const {'screenscraper': '42'},
        matchStatus: IdentityMatchStatus.manuallyMatched));
    await library.putEdition(EditionIdentity(id: editionId, gameId: gameId));
  }

  test(
      'fresh snapshot coalesces equal requests and never imports legacy scores',
      () async {
    await db.execute('CREATE TABLE game_metadata (filename TEXT, rating REAL)');
    await db.insert('game_metadata', {'filename': 'Old.chd', 'rating': 100});
    await seed('e1');
    await seed('e2');
    final first = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'collection-1',
        editionIds: ['e1', 'e2', 'e1']);
    final result = await jobs.run(first.id, provider);
    expect(result.state, 'completed');
    expect(result.requested, 1);
    expect(result.counts, {'matched': 2});
    expect(result.rated, 2);
    expect(provider.calls, hasLength(1));
    expect((await library.metadata('e2', 'screenscraper'))!.editionId, 'e2');
    expect((await db.query('game_metadata')).single['rating'], 100);
    final second = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'collection-1',
        editionIds: ['e1', 'e2']);
    expect(second.generation, greaterThan(first.generation));
    await jobs.run(second.id, provider);
    expect(provider.calls, hasLength(2),
        reason: 'full re-scrape must not skip current cache');
  });

  test(
      'snapshot membership is fixed and an unknown platform has an explicit outcome',
      () async {
    await seed('e1');
    await seed('unknown', gameId: 'unknown', platform: null);
    final job = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'catalogue-before-change',
        editionIds: ['e1', 'unknown']);
    await seed('added-later', gameId: 'new');
    final result = await jobs.run(job.id, provider);
    expect(result.collectionGeneration, 'catalogue-before-change');
    expect(result.counts, {'matched': 1, 'unsupportedPlatform': 1});
    expect(provider.calls, hasLength(1));
  });

  test('pause joins current lookup and resume does not repeat committed items',
      () async {
    await seed('a', gameId: 'a');
    await seed('b', gameId: 'b');
    final secondStarted = Completer<void>();
    final release = Completer<void>();
    provider.reply = (request, token) async {
      if (request.editionId == 'b') {
        secondStarted.complete();
        await release.future;
      }
      return _matched(request);
    };
    final job = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'v1',
        editionIds: ['a', 'b']);
    final run = jobs.run(job.id, provider);
    await secondStarted.future;
    var joined = false;
    final pause = jobs.pause().then((_) => joined = true);
    await Future<void>.value();
    expect(joined, isFalse);
    release.complete();
    await pause;
    expect((await run).state, 'paused');
    expect(await library.metadata('b', 'screenscraper'), isNull);
    provider.reply = null;
    jobs = MetadataRefreshJobs(Future.value(db));
    final resumed = await jobs.run(job.id, provider);
    expect(resumed.counts, {'matched': 2});
    expect(provider.calls.map((r) => r.editionId), ['a', 'b', 'b']);
  });

  test('quota pauses pending work without invalidating already cached data',
      () async {
    await seed('a', gameId: 'a');
    await seed('b', gameId: 'b');
    provider.reply = (request, _) async => _matched(request,
        quota: const MetadataQuota(requestsToday: 10, maxRequestsPerDay: 10));
    final job = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'v1',
        editionIds: ['a', 'b']);
    final blocked = await jobs.run(job.id, provider);
    expect(blocked.state, 'blocked');
    expect(blocked.blockedStatus, 'quotaExceeded');
    expect(blocked.counts, {'matched': 1, 'pending': 1});
    expect(provider.calls, hasLength(1));
    expect(await library.metadata('a', 'screenscraper'), isNotNull);
  });

  test(
      'a correction during lookup is preserved and cannot acquire the old score',
      () async {
    await seed('e1');
    provider.reply = (request, _) async {
      await library.putEdition(EditionIdentity(
          id: 'e1',
          gameId: 'g1',
          tags: {'Hack'},
          patchId: 'different-project'));
      return _matched(request);
    };
    final job = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'v1',
        editionIds: ['e1']);
    final result = await jobs.run(job.id, provider);
    expect(result.counts, {'identityChanged': 1});
    expect(await library.metadata('e1', 'screenscraper'), isNull);
    expect((await library.edition('e1'))!.patchId, 'different-project');
  });

  test('retry-after survives a runner restart without provider polling',
      () async {
    await seed('a');
    var now = DateTime.utc(2026, 9, 9);
    jobs = MetadataRefreshJobs(Future.value(db), now: () => now);
    provider.reply = (request, token) async => MetadataLookupResult(
        status: MetadataLookupStatus.throttled,
        message: 'Slow down',
        retryAfter: const Duration(seconds: 90));
    final job = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'v1',
        editionIds: ['a']);
    expect((await jobs.run(job.id, provider)).blockedStatus, 'throttled');
    jobs = MetadataRefreshJobs(Future.value(db), now: () => now);
    expect((await jobs.run(job.id, provider)).state, 'blocked');
    expect(provider.calls, hasLength(1));
    now = now.add(const Duration(seconds: 90));
    provider.reply = null;
    expect((await jobs.run(job.id, provider)).state, 'completed');
    expect(provider.calls, hasLength(2));
  });

  test('one worker holds the database claim until its lookup is joined',
      () async {
    await seed('a');
    final first = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'v1',
        editionIds: ['a']);
    final second = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'v1',
        editionIds: ['a']);
    final started = Completer<void>();
    final release = Completer<void>();
    provider.reply = (request, _) async {
      started.complete();
      await release.future;
      return _matched(request);
    };
    final running = jobs.run(first.id, provider);
    await started.future;
    try {
      await expectLater(
          MetadataRefreshJobs(Future.value(db)).run(second.id, provider),
          throwsA(isA<DatabaseException>()));
      expect(provider.calls, hasLength(1));
    } finally {
      release.complete();
      await running;
    }
  });

  test('metadata and completion rollback together on a storage failure',
      () async {
    await seed('a');
    final job = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'v1',
        editionIds: ['a']);
    await db.execute(
        '''CREATE TRIGGER reject_refresh BEFORE UPDATE ON metadata_refresh_items
      WHEN NEW.status = 'matched' BEGIN SELECT RAISE(ABORT, 'fixture'); END''');
    await expectLater(
        jobs.run(job.id, provider), throwsA(isA<DatabaseException>()));
    expect(await library.metadata('a', 'screenscraper'), isNull);
    expect((await jobs.report(job.id)).counts, {'pending': 1});
    expect((await jobs.report(job.id)).state, 'paused');
    await db.execute('DROP TRIGGER reject_refresh');
    expect((await jobs.run(job.id, provider)).counts, {'matched': 1});
  });

  test('older generation cannot overwrite a newer committed score', () async {
    await seed('a');
    final old = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'v1',
        editionIds: ['a']);
    final newer = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'v1',
        editionIds: ['a']);
    await jobs.run(newer.id, provider);
    expect((await jobs.run(old.id, provider)).counts, {'superseded': 1});
    expect((await library.metadata('a', 'screenscraper'))!.refreshGeneration,
        newer.generation);
  });

  test('wrong identity from a provider is an explicit invalid response',
      () async {
    await seed('a');
    provider.reply = (request, _) async => _matched(
        MetadataLookupRequest.fromJson(
            {...request.toJson(), 'gameId': 'wrong-game'}));
    final job = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'v1',
        editionIds: ['a']);
    expect((await jobs.run(job.id, provider)).counts, {'invalidResponse': 1});
    expect(await library.metadata('a', 'screenscraper'), isNull);
  });

  test('auth and offline failures retain a cached result and pending work',
      () async {
    await seed('a');
    final first = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'v1',
        editionIds: ['a']);
    await jobs.run(first.id, provider);
    for (final status in [
      MetadataLookupStatus.setupRequired,
      MetadataLookupStatus.authenticationRequired,
      MetadataLookupStatus.unavailable
    ]) {
      provider.reply = (request, token) async =>
          MetadataLookupResult(status: status, message: 'Paused');
      final next = await jobs.create(
          providerId: provider.providerId,
          collectionGeneration: 'v1',
          editionIds: ['a']);
      final report = await jobs.run(next.id, provider);
      expect(report.blockedStatus, status.name);
      expect(report.counts, {'pending': 1});
      expect((await library.metadata('a', 'screenscraper'))!.refreshGeneration,
          first.generation);
    }
  });

  test('provider-wide retry-after cannot be bypassed with a new job', () async {
    await seed('a');
    final now = DateTime.utc(2026, 9, 9);
    jobs = MetadataRefreshJobs(Future.value(db), now: () => now);
    provider.reply = (request, token) async => MetadataLookupResult(
        status: MetadataLookupStatus.throttled,
        message: 'Wait',
        retryAfter: const Duration(seconds: 90));
    final first = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'v1',
        editionIds: ['a']);
    await jobs.run(first.id, provider);
    final second = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'v2',
        editionIds: ['a']);
    await jobs.run(second.id, provider);
    expect(provider.calls, hasLength(1));
  });

  test('wrong verified provider ID and field provenance are invalid outcomes',
      () async {
    await seed('a');
    for (final badField in [false, true]) {
      provider.reply = (request, token) async {
        final good = _matched(request).record!;
        return MetadataLookupResult(
            status: MetadataLookupStatus.matched,
            message: 'Matched',
            record: MetadataRecord.fromJson({
              ...good.toJson(),
              if (!badField) 'providerGameId': 'incorrect',
              if (badField)
                'fieldProvenance': {
                  'titles': MetadataFieldProvenance(
                          providerId: 'unrelated',
                          providerGameId: 'different',
                          field: 'titles',
                          retrievedAt: DateTime.utc(2026))
                      .toJson()
                },
            }));
      };
      final job = await jobs.create(
          providerId: provider.providerId,
          collectionGeneration: 'v1',
          editionIds: ['a']);
      expect((await jobs.run(job.id, provider)).counts, {'invalidResponse': 1});
      expect(await library.metadata('a', 'screenscraper'), isNull);
    }
  });

  test('base-game response cannot rate a separately identified hack', () async {
    await seed('base');
    await library.putGame(GameIdentity(
        id: 'hack',
        title: 'Different project',
        platformId: 'psx',
        baseGameId: 'g1'));
    await library.putEdition(
        EditionIdentity(id: 'hack', gameId: 'hack', tags: {'Hack'}));
    final job = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'v1',
        editionIds: ['hack']);
    final result = await jobs.run(job.id, provider);
    expect(result.counts, {'invalidResponse': 1});
    expect(result.rated, 0);
    expect(await library.metadata('hack', 'screenscraper'), isNull);
  });

  test('pause while waiting for a database commit prevents a late result',
      () async {
    await seed('a');
    final locked = Completer<void>();
    final release = Completer<void>();
    Future<void>? holding;
    provider.reply = (request, token) async {
      holding = db.transaction((txn) async {
        locked.complete();
        await release.future;
      });
      await locked.future;
      return _matched(request);
    };
    final job = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'v1',
        editionIds: ['a']);
    final running = jobs.run(job.id, provider);
    await locked.future;
    final pausing = jobs.pause();
    release.complete();
    await holding;
    await pausing;
    expect((await running).state, 'paused');
    expect(await library.metadata('a', 'screenscraper'), isNull);
  });

  test('30000-edition snapshot coalesces and commits in bounded pages',
      () async {
    await seed('e00000');
    final before = ProcessInfo.currentRss;
    final elapsed = Stopwatch()..start();
    for (var start = 1; start < 30000; start += 128) {
      final batch = db.batch();
      for (var index = start; index < start + 128 && index < 30000; index++) {
        final edition = EditionIdentity(
            id: 'e${index.toString().padLeft(5, '0')}', gameId: 'g1');
        batch.insert('library_editions', {
          'edition_id': edition.id,
          'game_id': edition.gameId,
          'record_json': jsonEncode(edition.toJson())
        });
      }
      await batch.commit(noResult: true);
    }
    Iterable<String> editions() sync* {
      for (var index = 0; index < 30000; index++) {
        yield 'e${index.toString().padLeft(5, '0')}';
      }
    }

    final job = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'large-fixture',
        editionIds: editions());
    final result = await jobs.run(job.id, provider);
    expect(result.counts, {'matched': 30000});
    expect(result.requested, 1);
    expect(provider.calls, hasLength(1));
    expect(result.rated, 30000);
    final plan = await db.rawQuery('''EXPLAIN QUERY PLAN SELECT edition_id
      FROM metadata_refresh_items WHERE job_id = ? AND status = ?
      ORDER BY edition_id LIMIT 128''', [job.id, 'pending']);
    expect(plan.toString(), contains('idx_metadata_refresh_pending'));
    // Resource observation, not a timing-dependent correctness gate.
    // ignore: avoid_print
    print('metadata-30000: ${elapsed.elapsedMilliseconds}ms; '
        'RSS before=$before after=${ProcessInfo.currentRss} peak=${ProcessInfo.maxRss}; requests=1; page=128');
  }, timeout: Timeout.none);
}
