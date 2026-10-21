import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/services/library_store.dart';
import 'package:g_shop/services/metadata/metadata_provider.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Provider implements MetadataAccessProvider {
  final List<DateTime> starts = [];
  final DateTime Function() now;
  final int limit;
  final MetadataQuota? firstQuota;
  int accessChecks = 0;
  MetadataQuota? accessQuota;
  _Provider(this.now, {this.limit = 2, this.firstQuota});
  @override
  String get providerId => 'screenscraper';
  @override
  MetadataProviderCapabilities get capabilities =>
      const MetadataProviderCapabilities(
          fields: {},
          verifiedIdLookup: true,
          rawRomLookup: true,
          titleSearch: true,
          documentedVoteCounts: false);
  @override
  Future<MetadataLookupResult> lookup(MetadataLookupRequest request,
      {CancelToken? cancelToken}) async {
    starts.add(now());
    return MetadataLookupResult(
        status: MetadataLookupStatus.unmatched,
        message: 'Not found',
        quota: starts.length == 1
            ? firstQuota ?? MetadataQuota(maxRequestsPerMinute: limit)
            : null);
  }

  @override
  void close() {}
  @override
  Future<MetadataLookupResult> checkAccess({CancelToken? cancelToken}) async {
    accessChecks++;
    return MetadataLookupResult(
        status: MetadataLookupStatus.matched,
        message: 'Access checked',
        quota: accessQuota);
  }
}

class _ProtocolTimer implements Timer {
  final Duration duration;
  final void Function() callback;
  bool active = true;
  _ProtocolTimer(this.duration, this.callback);
  void fire() {
    if (!active) return;
    active = false;
    callback();
  }

  @override
  void cancel() => active = false;
  @override
  bool get isActive => active;
  @override
  int get tick => active ? 0 : 1;
}

void main() {
  late Database db;
  late DateTime now;
  late _Provider provider;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    now = DateTime.utc(2026, 10, 3);
    provider = _Provider(() => now);
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    final store = LibraryStore(Future.value(db));
    for (final id in ['a', 'b', 'c']) {
      await store.putGame(GameIdentity(id: id, platformId: 'snes', title: id));
      await store.putEdition(EditionIdentity(id: id, gameId: id));
    }
  });
  tearDown(() async => db.close());

  Future<MetadataRefreshReport> create(
          MetadataRefreshJobs jobs, List<String> ids) =>
      jobs.create(
          providerId: provider.providerId,
          collectionGeneration: 'collection',
          editionIds: ids);

  test('provider rate survives new jobs even when later replies omit quota',
      () async {
    final jobs = MetadataRefreshJobs(Future.value(db), now: () => now);
    final first = await create(jobs, ['a']);
    await jobs.run(first.id, provider);
    // Advance to the provider slot explicitly. A restarted runner must retain it.
    now = now.add(const Duration(seconds: 30));
    final restarted = MetadataRefreshJobs(Future.value(db), now: () => now);
    final second = await create(restarted, ['b']);
    await restarted.run(second.id, provider);
    final budget = (await db.query('metadata_provider_limits')).single;
    expect(budget['requests_per_minute'], 2);
    expect(budget['next_allowed_at'],
        now.add(const Duration(seconds: 30)).millisecondsSinceEpoch);
    expect(provider.starts, [DateTime.utc(2026, 10, 3), now]);
  });

  test('declared zero budget prevents every later job from making requests',
      () async {
    provider = _Provider(() => now, limit: 0);
    final jobs = MetadataRefreshJobs(Future.value(db), now: () => now);
    final first = await create(jobs, ['a', 'b']);
    final stopped = await jobs.run(first.id, provider);
    expect(stopped.blockedStatus, 'quotaExceeded');
    expect(stopped.counts, {'unmatched': 1, 'pending': 1});
    final restarted = MetadataRefreshJobs(Future.value(db), now: () => now);
    final second = await create(restarted, ['c']);
    expect((await restarted.run(second.id, provider)).blockedStatus,
        'quotaExceeded');
    expect(provider.starts, hasLength(1));
  });

  test('daily exhaustion is provider-wide even after a completed one-item job',
      () async {
    provider = _Provider(() => now,
        firstQuota: const MetadataQuota(
            requestsToday: 100,
            maxRequestsPerDay: 100,
            unmatchedToday: 10,
            maxUnmatchedPerDay: 100));
    final jobs = MetadataRefreshJobs(Future.value(db), now: () => now);
    final first = await create(jobs, ['a']);
    expect((await jobs.run(first.id, provider)).state, 'completed');
    final restarted = MetadataRefreshJobs(Future.value(db), now: () => now);
    final second = await create(restarted, ['b']);
    final blocked = await restarted.run(second.id, provider);
    expect(blocked.state, 'blocked');
    expect(blocked.blockedStatus, 'quotaExceeded');
    expect(blocked.requested, 0);
    expect(provider.starts, hasLength(1));
  });

  test('a reported zero thread allowance does not start another lookup',
      () async {
    provider =
        _Provider(() => now, firstQuota: const MetadataQuota(maxThreads: 0));
    final jobs = MetadataRefreshJobs(Future.value(db), now: () => now);
    final job = await create(jobs, ['a', 'b']);
    final stopped = await jobs.run(job.id, provider);
    expect(stopped.blockedStatus, 'quotaExceeded');
    expect(provider.starts, hasLength(1));
  });

  test(
      'explicit access recheck recovers exhausted work without repeating success',
      () async {
    provider = _Provider(() => now,
        firstQuota: const MetadataQuota(
            requestsToday: 100,
            maxRequestsPerDay: 100,
            unmatchedToday: 10,
            maxUnmatchedPerDay: 100));
    final jobs = MetadataRefreshJobs(Future.value(db), now: () => now);
    final first = await create(jobs, ['a', 'b']);
    await jobs.run(first.id, provider);
    provider.accessQuota = const MetadataQuota(
        requestsToday: 1,
        maxRequestsPerDay: 100,
        unmatchedToday: 0,
        maxUnmatchedPerDay: 100);
    final recovered = await jobs.run(first.id, provider, recheckAccess: true);
    expect(recovered.state, 'completed');
    expect(recovered.counts, {'unmatched': 2});
    expect(recovered.requested, 2, reason: 'Status probe is not a game lookup');
    expect(provider.accessChecks, 1);
    expect(provider.starts, hasLength(2));
  });

  test('an incomplete access response cannot erase recorded daily exhaustion',
      () async {
    provider = _Provider(() => now,
        firstQuota:
            const MetadataQuota(unmatchedToday: 10, maxUnmatchedPerDay: 10));
    final jobs = MetadataRefreshJobs(Future.value(db), now: () => now);
    final first = await create(jobs, ['a', 'b']);
    await jobs.run(first.id, provider);
    provider.accessQuota =
        const MetadataQuota(requestsToday: 1, maxRequestsPerDay: 100);
    final stillBlocked =
        await jobs.run(first.id, provider, recheckAccess: true);
    expect(stillBlocked.state, 'blocked');
    expect(stillBlocked.blockedStatus, 'quotaExceeded');
    expect(provider.accessChecks, 1);
    expect(provider.starts, hasLength(1));
  });

  test('protocol wait retains worker ownership and cancellation joins it',
      () async {
    final waiting = Completer<_ProtocolTimer>();
    final jobs = MetadataRefreshJobs(Future.value(db),
        now: () => now,
        schedule: (duration, callback) {
          final timer = _ProtocolTimer(duration, callback);
          waiting.complete(timer);
          return timer;
        });
    final first = await create(jobs, ['a', 'b']);
    final active = jobs.run(first.id, provider);
    final timer = await waiting.future;
    expect(timer.duration, const Duration(seconds: 30));
    expect(provider.starts, hasLength(1));
    final duringWait = await jobs.report(first.id);
    expect(duringWait.state, 'running');
    expect(duringWait.blockedStatus, 'throttled');
    expect(duringWait.notBefore, now.add(const Duration(seconds: 30)));
    final other = MetadataRefreshJobs(Future.value(db), now: () => now);
    final competing = await create(other, ['c']);
    await expectLater(
        other.run(competing.id, provider), throwsA(isA<DatabaseException>()));
    await jobs.pause();
    expect((await active).state, 'paused');
    expect(timer.isActive, isFalse);
    timer.fire();
    expect(provider.starts, hasLength(1));
    // Cancellation retains the provider slot; a new runner cannot bypass it.
    final resumedWait = Completer<_ProtocolTimer>();
    final restarted = MetadataRefreshJobs(Future.value(db),
        now: () => now,
        schedule: (duration, callback) {
          final timer = _ProtocolTimer(duration, callback);
          resumedWait.complete(timer);
          return timer;
        });
    final resumed = restarted.run(first.id, provider);
    final resumedTimer = await resumedWait.future;
    expect(resumedTimer.duration, const Duration(seconds: 30));
    now = now.add(resumedTimer.duration);
    resumedTimer.fire();
    final completed = await resumed;
    expect(completed.state, 'completed');
    expect(completed.counts, {'unmatched': 2});
    expect(provider.starts, [DateTime.utc(2026, 10, 3), now]);
  });

  test('source identity is rechecked after the protocol wait', () async {
    final waiting = Completer<_ProtocolTimer>();
    final jobs = MetadataRefreshJobs(Future.value(db),
        now: () => now,
        schedule: (duration, callback) {
          final timer = _ProtocolTimer(duration, callback);
          waiting.complete(timer);
          return timer;
        });
    final job = await create(jobs, ['a', 'b']);
    final active = jobs.run(job.id, provider);
    final timer = await waiting.future;
    await db
        .delete('library_editions', where: 'edition_id = ?', whereArgs: ['b']);
    now = now.add(timer.duration);
    timer.fire();
    final result = await active;
    expect(result.counts, {'unmatched': 1, 'identityChanged': 1});
    expect(result.state, 'completed');
    expect(provider.starts, hasLength(1));
  });
}
