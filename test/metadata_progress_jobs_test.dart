import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'metadata_controls_test.dart'
    show controlsDatabase, ControlsProvider, ControlsArtworkProvider;

class _PreviewBody extends ControlsArtworkProvider {
  final List<int> body;
  _PreviewBody(this.body);
  @override
  Future<MetadataLookupResult> fetchArtwork(MetadataMedia media,
      {required Future<void> Function(List<int>) write,
      CancelToken? cancelToken}) async {
    await write(body);
    return MetadataLookupResult(
        status: MetadataLookupStatus.matched, message: 'Body fixture');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'preview refuses oversized and malformed bodies without disk publication',
      () async {
    final media = ControlsArtworkProvider().media;
    for (final body in [
      Uint8List(MetadataArtworkCache.maxBytes + 1),
      Uint8List.fromList([1, 2, 3, 4])
    ]) {
      final result = await MetadataArtworkCache.fetchPreview(
          media, _PreviewBody(body), CancelToken());
      expect(result.bytes, isNull);
      expect(result.result.status, MetadataLookupStatus.invalidResponse);
    }
  });

  test(
      'preview cancellation joins transport without undoing the committed lookup',
      () async {
    final db = await controlsDatabase();
    final jobs = MetadataRefreshJobs(Future.value(db));
    addTearDown(() async {
      await jobs.pause();
      await db.close();
    });
    final provider = ControlsArtworkProvider();
    provider.reply = (request, _) async => MetadataLookupResult(
            status: MetadataLookupStatus.needsReview,
            message: 'Candidate',
            candidates: [
              MetadataLookupCandidate(
                  providerGameId: '42',
                  platformId: request.platformId,
                  titles: const [MetadataText(text: 'Candidate')],
                  titleMatched: true,
                  evidence: 'platformAndTitle',
                  previewMedia: provider.media)
            ]);
    final started = Completer<void>();
    provider.onArtwork = (cancel) async {
      started.complete();
      await cancel!.whenCancel;
    };
    final job = await jobs.createFromCatalogue(
        providerId: 'screenscraper', cacheRowId: 1);
    final run = jobs.run(job.id, provider);
    await started.future;
    await jobs.pause();
    final paused = await run;
    expect(paused.state, 'paused');
    expect(paused.counts, {'needsReview': 1});
    expect(paused.lastProcessed!.coverBytes, isNull);
    expect(await db.query('library_metadata'), isEmpty);
    expect((await jobs.run(job.id, provider)).state, 'completed');
    expect(provider.calls, hasLength(1));
    expect(provider.artworkCalls, 1);
  });

  test(
      'image preview cannot steal exhausted quota or mark pending games complete',
      () async {
    final db = await controlsDatabase();
    final jobs = MetadataRefreshJobs(Future.value(db));
    addTearDown(() async {
      await jobs.pause();
      await db.close();
    });
    final provider = ControlsArtworkProvider();
    provider.reply = (request, _) async => MetadataLookupResult(
            status: MetadataLookupStatus.needsReview,
            message: 'Quota exhausted',
            quota: const MetadataQuota(maxRequestsPerDay: 1, requestsToday: 1),
            candidates: [
              MetadataLookupCandidate(
                  providerGameId: '42',
                  platformId: request.platformId,
                  titles: const [MetadataText(text: 'Candidate')],
                  titleMatched: true,
                  evidence: 'platformAndTitle',
                  previewMedia: provider.media)
            ]);
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final blocked = await jobs.run(job.id, provider);
    expect(blocked.state, 'blocked');
    expect(blocked.blockedStatus, 'quotaExceeded');
    expect(blocked.counts, {'needsReview': 1, 'pending': 1});
    expect(blocked.quotaObservation!.remaining, 0);
    expect(provider.calls, hasLength(1));
    expect(provider.artworkCalls, 0);
  });

  test('candidate cover is bounded display context, never accepted metadata',
      () async {
    final db = await controlsDatabase();
    final jobs = MetadataRefreshJobs(Future.value(db));
    addTearDown(() async {
      await jobs.pause();
      await db.close();
    });
    final provider = ControlsArtworkProvider();
    provider.reply = (request, _) async => MetadataLookupResult(
            status: MetadataLookupStatus.needsReview,
            message: 'Candidate fixture',
            candidates: [
              MetadataLookupCandidate(
                  providerGameId: '42',
                  platformId: request.platformId,
                  titles: const [MetadataText(text: 'Candidate')],
                  titleMatched: true,
                  evidence: 'platformAndTitle',
                  previewMedia: provider.media)
            ]);
    final job = await jobs.createFromCatalogue(
        providerId: 'screenscraper', cacheRowId: 1);
    final result = await jobs.run(job.id, provider);
    expect(result.lastProcessed!.coverBytes, isNotNull);
    expect(result.rated, 0);
    expect(result.counts, {'needsReview': 1});
    expect(await db.query('library_metadata'), isEmpty);
    expect(await db.query('metadata_artwork_cache'), isEmpty);
    expect(provider.calls, hasLength(1));
    expect(provider.artworkCalls, 1);
  });

  test('provider observation survives missing counters without invented reset',
      () async {
    final db = await controlsDatabase();
    var now = DateTime.utc(2026, 10, 6, 23, 59);
    final jobs = MetadataRefreshJobs(Future.value(db), now: () => now);
    addTearDown(() async {
      await jobs.pause();
      await db.close();
    });
    final provider = ControlsProvider();
    provider.reply = (_, __) async => MetadataLookupResult(
        status: MetadataLookupStatus.unmatched,
        message: 'Quota fixture',
        quota: const MetadataQuota(
            maxRequestsPerDay: 10000,
            requestsToday: 80,
            maxUnmatchedPerDay: 1000,
            unmatchedToday: 2));
    final first = await jobs.createFromCatalogue(
        providerId: 'screenscraper', cacheRowId: 1);
    final result = await jobs.run(first.id, provider);
    expect(result.quotaObservation!.remaining, 9920);
    expect(result.quotaObservation!.observedAt, now);
    now = now.add(const Duration(days: 1));
    provider.reply = (_, __) async => MetadataLookupResult(
        status: MetadataLookupStatus.unmatched, message: 'No counters');
    final second = await jobs.createFromCatalogue(
        providerId: 'screenscraper', cacheRowId: 2);
    final missing = await jobs.run(second.id, provider);
    expect(missing.quotaObservation!.remaining, 9920);
    expect(missing.quotaObservation!.reservedRemaining, 9919);
    expect(missing.quotaObservation!.observedAt,
        result.quotaObservation!.observedAt);
    expect(missing.lastProcessed!.title, 'Game 2');
    expect((await jobs.report(first.id)).lastProcessed, isNull);
    expect(
        (await MetadataRefreshJobs(Future.value(db)).report(second.id))
            .quotaObservation!
            .observedAt,
        result.quotaObservation!.observedAt);
    await jobs.clearQuotaObservation('screenscraper');
    expect((await jobs.report(second.id)).quotaObservation, isNull);
    final limits = (await db.query('metadata_provider_limits')).single;
    expect(limits['remaining_requests'], 9919);
    expect(limits['quota_exhausted'], 0);
    expect(jsonDecode(limits['quota_json'] as String? ?? '{}'), isEmpty);
  });
}
