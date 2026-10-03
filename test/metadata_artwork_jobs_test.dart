import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';

class _Artwork implements MetadataArtworkProvider {
  int calls = 0;
  List<int> bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==');
  MetadataLookupStatus status = MetadataLookupStatus.matched;
  Future<void> Function(CancelToken?)? onRequest;
  @override
  String get providerId => 'screenscraper';
  @override
  MetadataProviderCapabilities get capabilities =>
      const MetadataProviderCapabilities(
          fields: {'artwork'},
          verifiedIdLookup: true,
          rawRomLookup: false,
          titleSearch: false,
          documentedVoteCounts: false);
  @override
  void close() {}
  @override
  Future<MetadataLookupResult> lookup(MetadataLookupRequest request,
          {CancelToken? cancelToken}) async =>
      throw StateError('Artwork jobs cannot repeat game lookups');
  @override
  Future<MetadataLookupResult> fetchArtwork(MetadataMedia media,
      {required Future<void> Function(List<int>) write,
      CancelToken? cancelToken}) async {
    calls++;
    await onRequest?.call(cancelToken);
    if (status == MetadataLookupStatus.matched) await write(bytes);
    return MetadataLookupResult(status: status, message: 'Fixture image');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Directory root;
  late MetadataRefreshJobs jobs;
  late MetadataArtworkCache cache;
  late _Artwork provider;
  final media = MetadataMedia(
      type: 'box-2D',
      region: 'us',
      providerReference: ScreenScraperMediaReference(
          providerGameId: '42',
          providerPlatformId: 4,
          mediaType: 'box-2D',
          region: 'us'));
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    root = await Directory.systemTemp.createTemp('rshop-artwork-test-');
    jobs = MetadataRefreshJobs(Future.value(db));
    cache = MetadataArtworkCache(Future.value(db), root);
    provider = _Artwork();
    final store = LibraryStore(Future.value(db));
    for (final id in ['a', 'b']) {
      await store.putGame(GameIdentity(
          id: id,
          platformId: 'snes',
          title: 'Fixture',
          providerIds: {'screenscraper': '42'},
          matchStatus: IdentityMatchStatus.manuallyMatched));
      await store
          .putEdition(EditionIdentity(id: id, gameId: id, tags: {'official'}));
      await store.putMetadata(MetadataRecord(
          gameId: id,
          editionId: id,
          platformId: 'snes',
          providerId: provider.providerId,
          providerGameId: '42',
          retrievedAt: DateTime.utc(2026),
          refreshGeneration: 1,
          matchMethod: 'verifiedProviderId',
          titles: [MetadataText(text: 'Fixture')],
          media: [media]));
    }
  });
  tearDown(() async {
    await db.close();
    if (!root.path.startsWith(Directory.systemTemp.path) ||
        !root.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('rshop-artwork-test-')) {
      throw StateError('Unexpected test cleanup root');
    }
    await root.delete(recursive: true);
  });

  test('durable artwork job coalesces images and serves cache without network',
      () async {
    final job = await jobs.createArtwork(
        providerId: provider.providerId,
        collectionGeneration: 'fixture',
        editionIds: ['a', 'b']);
    expect(job.counts, {'pending': 2});
    final done = await jobs.run(job.id, provider, artworkCache: cache);
    expect(done.state, 'completed');
    expect(done.counts, {'matched': 2});
    expect(done.requested, 1);
    final file = await cache.fileFor('a', provider.providerId, media);
    expect(file, isNotNull);
    expect(await file!.readAsBytes(), provider.bytes);
    expect((await cache.fileFor('b', provider.providerId, media))!.path,
        file.path);
    expect(provider.calls, 1);
    expect(await root.list().any((f) => f.path.endsWith('.part')), isFalse);
    final repeated = await jobs.run(job.id, provider, artworkCache: cache);
    expect(repeated.requested, 1);
    expect(provider.calls, 1);
  });

  test('invalid refresh preserves usable cached artwork and removes staging',
      () async {
    final initial = await jobs.createArtwork(
        providerId: provider.providerId,
        collectionGeneration: 'first',
        editionIds: ['a']);
    await jobs.run(initial.id, provider, artworkCache: cache);
    final old = (await cache.fileFor('a', provider.providerId, media))!;
    provider.bytes = utf8.encode('<html>not an image</html>');
    final refresh = await jobs.createArtwork(
        providerId: provider.providerId,
        collectionGeneration: 'second',
        editionIds: ['a']);
    final result = await jobs.run(refresh.id, provider, artworkCache: cache);
    expect(result.counts, {'invalidResponse': 1});
    expect(
        (await cache.fileFor('a', provider.providerId, media))!.path, old.path);
    expect(await root.list().any((f) => f.path.endsWith('.part')), isFalse);
  });

  test('independent provider review preserves pending and cached artwork',
      () async {
    final job = await jobs.createArtwork(
        providerId: provider.providerId,
        collectionGeneration: 'before-other-review',
        editionIds: ['a']);
    final store = LibraryStore(Future.value(db));
    final game = (await store.game('a'))!;
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'providerIds': {...game.providerIds, 'igdb': '100'},
      'evidence': [
        ...game.evidence.map((e) => e.toJson()),
        IdentityEvidence(
            source: 'manual',
            kind: 'providerId',
            value: jsonEncode(['igdb', '100'])).toJson()
      ]
    }));
    expect((await jobs.run(job.id, provider, artworkCache: cache)).counts,
        {'matched': 1});
    expect(await cache.fileFor('a', provider.providerId, media), isNotNull);
    final changed = (await store.game('a'))!;
    await store.putGame(GameIdentity.fromJson({
      ...changed.toJson(),
      'providerIds': {'screenscraper': '42', 'igdb': '101'}
    }));
    expect(await cache.fileFor('a', provider.providerId, media), isNotNull);
    expect(provider.calls, 1,
        reason: 'offline consumption never re-fetches artwork');
    await store.putEdition(EditionIdentity(
        id: 'a', gameId: 'a', patchId: 'different-project', tags: {'Hack'}));
    expect(await cache.fileFor('a', provider.providerId, media), isNull,
        reason:
            'the owning edition still guards images from a different project');
  });

  test('CRC-valid PNG with an invalid compressed image cannot publish',
      () async {
    // Keep valid dimensions/chunk CRCs; only the IDAT zlib stream is invalid.
    final bytes = Uint8List.fromList(provider.bytes);
    final data = ByteData.sublistView(bytes);
    final length = data.getUint32(33);
    bytes.fillRange(41, 41 + length, 0);
    data.setUint32(
        41 + length, getCrc32(Uint8List.sublistView(bytes, 37, 41 + length)));
    provider.bytes = bytes;
    final job = await jobs.createArtwork(
        providerId: provider.providerId,
        collectionGeneration: 'broken-body',
        editionIds: ['a']);
    final done = await jobs.run(job.id, provider, artworkCache: cache);
    expect(done.counts, {'invalidResponse': 1});
    expect(await cache.fileFor('a', provider.providerId, media), isNull);
    expect(await root.list().isEmpty, isTrue);
  });

  test('cache rejects all appended non-image data', () async {
    final png = provider.bytes;
    provider.bytes = [...png, 10];
    final padded = await jobs.createArtwork(
        providerId: provider.providerId,
        collectionGeneration: 'padded',
        editionIds: ['a']);
    expect((await jobs.run(padded.id, provider, artworkCache: cache)).counts,
        {'invalidResponse': 1});
    provider.bytes = [...png, ...utf8.encode('<html>')];
    final appended = await jobs.createArtwork(
        providerId: provider.providerId,
        collectionGeneration: 'appended',
        editionIds: ['a']);
    expect((await jobs.run(appended.id, provider, artworkCache: cache)).counts,
        {'invalidResponse': 1});
  });

  test('cancellation joins the worker and preserves pending items for resume',
      () async {
    final entered = Completer<void>();
    final drained = Completer<void>();
    provider.onRequest = (cancel) async {
      entered.complete();
      await cancel!.whenCancel;
      drained.complete();
    };
    final job = await jobs.createArtwork(
        providerId: provider.providerId,
        collectionGeneration: 'cancel',
        editionIds: ['a', 'b']);
    final active = jobs.run(job.id, provider, artworkCache: cache);
    await entered.future;
    await jobs.pause();
    expect(drained.isCompleted, isTrue);
    expect((await active).state, 'paused');
    expect((await jobs.report(job.id)).counts, {'pending': 2});
    expect(await root.list().isEmpty, isTrue);
    provider.onRequest = null;
    final resumed = await MetadataRefreshJobs(Future.value(db))
        .run(job.id, provider, artworkCache: cache);
    expect(resumed.counts, {'matched': 2});
    expect(provider.calls, 2);
  });

  test('image request reserves the shared daily budget before metadata runs',
      () async {
    await db.insert('metadata_provider_limits', {
      'provider_id': provider.providerId,
      'next_allowed_at': 0,
      'remaining_requests': 1,
    });
    final image = await jobs.createArtwork(
        providerId: provider.providerId,
        collectionGeneration: 'last-slot',
        editionIds: ['a']);
    expect((await jobs.run(image.id, provider, artworkCache: cache)).counts,
        {'matched': 1});
    final metadata = await jobs.create(
        providerId: provider.providerId,
        collectionGeneration: 'same-provider',
        editionIds: ['a']);
    final blocked = await jobs.run(metadata.id, provider);
    expect(blocked.state, 'blocked');
    expect(blocked.blockedStatus, 'quotaExceeded');
    expect(blocked.requested, 0);
    expect(provider.calls, 1);
  });

  test('metadata replacement during a body request prevents publication',
      () async {
    provider.onRequest = (_) async {
      final store = LibraryStore(Future.value(db));
      final original = (await store.metadata('a', provider.providerId))!;
      await store.putMetadata(MetadataRecord.fromJson({
        ...original.toJson(),
        'refreshGeneration': 2,
      }));
    };
    final job = await jobs.createArtwork(
        providerId: provider.providerId,
        collectionGeneration: 'changed',
        editionIds: ['a']);
    final done = await jobs.run(job.id, provider, artworkCache: cache);
    expect(done.counts, {'identityChanged': 1});
    expect(await db.query('metadata_artwork_cache'), isEmpty);
  });

  test('resuming a committed image preserves its retrieval date without HTTP',
      () async {
    final job = await jobs.createArtwork(
        providerId: provider.providerId,
        collectionGeneration: 'resume-page',
        editionIds: ['a', 'b']);
    await jobs.run(job.id, provider, artworkCache: cache);
    final original =
        (await db.query('metadata_artwork_cache')).single['retrieved_at'];
    // Durable state after one publication page committed and another remained.
    await db.update('metadata_artwork_items', {'status': 'pending'},
        where: 'job_id = ? AND edition_id = ?', whereArgs: [job.id, 'b']);
    await db.update('metadata_refresh_jobs', {'state': 'paused'},
        where: 'id = ?', whereArgs: [job.id]);
    final restarted =
        MetadataRefreshJobs(Future.value(db), now: () => DateTime.utc(2030));
    expect((await restarted.run(job.id, provider, artworkCache: cache)).counts,
        {'matched': 2});
    expect(provider.calls, 1);
    expect((await db.query('metadata_artwork_cache')).single['retrieved_at'],
        original);
  });

  test('explicit image selection is snapshotted without changing game metadata',
      () async {
    final job = await jobs.createArtwork(
        providerId: provider.providerId,
        collectionGeneration: 'selection',
        editionIds: ['a'],
        mediaKeys: <String>{'not-a-current-selector'});
    expect(job.counts, isEmpty);
    expect(
        (await LibraryStore(Future.value(db))
                .metadata('a', provider.providerId))!
            .media,
        hasLength(1));
    expect((await jobs.run(job.id, provider, artworkCache: cache)).state,
        'completed');
    expect(provider.calls, 0);
  });

  test('disk reopen preserves artwork, pending work and provider budget',
      () async {
    final path = '${root.path}${Platform.pathSeparator}worker.sqlite';
    var disk = await databaseFactoryFfi.openDatabase(path);
    addTearDown(() async {
      if (disk.isOpen) await disk.close();
    });
    await LibrarySchema.install(disk);
    await MetadataRefreshJobs.install(disk);
    final store = LibraryStore(Future.value(disk));
    await store.putGame(GameIdentity(
        id: 'disk',
        platformId: 'snes',
        title: 'Fixture',
        providerIds: {'screenscraper': '42'},
        matchStatus: IdentityMatchStatus.manuallyMatched));
    await store.putEdition(
        EditionIdentity(id: 'disk', gameId: 'disk', tags: {'official'}));
    await store.putMetadata(MetadataRecord(
        gameId: 'disk',
        editionId: 'disk',
        platformId: 'snes',
        providerId: provider.providerId,
        providerGameId: '42',
        retrievedAt: DateTime.utc(2026),
        refreshGeneration: 1,
        matchMethod: 'verifiedProviderId',
        titles: [MetadataText(text: 'Fixture')],
        media: [media]));
    final runner = MetadataRefreshJobs(Future.value(disk));
    final imageCache = MetadataArtworkCache(Future.value(disk), root);
    final first = await runner.createArtwork(
        providerId: provider.providerId,
        collectionGeneration: 'disk',
        editionIds: ['disk']);
    await runner.run(first.id, provider, artworkCache: imageCache);
    final pending = await runner.createArtwork(
        providerId: provider.providerId,
        collectionGeneration: 'disk-fresh',
        editionIds: ['disk']);
    // Durable state of a stopped process, not a lease for a live worker.
    await disk.update('metadata_refresh_jobs', {'state': 'running'},
        where: 'id = ?', whereArgs: [pending.id]);
    await disk.insert('metadata_provider_limits', {
      'provider_id': provider.providerId,
      'next_allowed_at': 0,
      'remaining_requests': 1,
    });
    await disk.close();
    disk = await databaseFactoryFfi.openDatabase(path);
    await MetadataRefreshJobs.recoverInterrupted(disk);
    final restarted = MetadataRefreshJobs(Future.value(disk));
    final restoredCache = MetadataArtworkCache(Future.value(disk), root);
    expect(await restoredCache.fileFor('disk', provider.providerId, media),
        isNotNull);
    expect(provider.calls, 1,
        reason: 'Offline cache read cannot request an image.');
    final report = await restarted.report(pending.id);
    expect(report.kind, 'artwork');
    expect(report.state, 'paused');
    expect(report.counts, {'pending': 1});
    expect(
        (await restarted.run(pending.id, provider, artworkCache: restoredCache))
            .counts,
        {'matched': 1});
    expect(provider.calls, 2,
        reason: 'Explicit fresh work must request its image.');
    expect(
        (await disk.query('metadata_provider_limits'))
            .single['remaining_requests'],
        0);
    await disk.close();
  });
}
