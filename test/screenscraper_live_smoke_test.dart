@Tags(['live'])
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/metadata/effective_overall_rating.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/metadata/screenscraper_provider.dart';

/// Explicit opt-in only; secrets remain in the ignored local file or environment.
/// No provider body, credentials, media URL or private account data is printed.
Map<String, String> _credentials() {
  final values = <String, String>{};
  final file = File('.env.local');
  if (file.existsSync()) {
    for (final line in file.readAsLinesSync()) {
      final match =
          RegExp(r'^\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*)$').firstMatch(line);
      if (match == null) continue;
      var value = match.group(2)!;
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      values[match.group(1)!] = value;
    }
  }
  values.addAll(Platform.environment);
  return values;
}

void main() {
  final values = _credentials();
  final developer = ScreenScraperDeveloperCredentials(
    developerId: values['SCREENSCRAPER_DEVID'] ?? '',
    developerPassword: values['SCREENSCRAPER_DEVPASSWORD'] ?? '',
    softwareName: values['SCREENSCRAPER_SOFTNAME'] ?? '',
  );
  final user = ScreenScraperUserCredentials(
    username: values['SCREENSCRAPER_USERNAME'] ?? '',
    password: values['SCREENSCRAPER_PASSWORD'] ?? '',
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('real standalone adapter authenticates, reviews and retrieves metadata',
      () async {
    final provider = ScreenScraperProvider(
      readDeveloperCredentials: () async => developer,
      readUserCredentials: () async => user,
    );
    addTearDown(provider.close);
    final search = await provider.lookup(MetadataLookupRequest(
      gameId: 'live-proof-snes-smw',
      editionId: 'live-proof-snes-smw-official',
      platformId: 'snes',
      title: 'Super Mario World',
      contentTags: const {'official'},
      refreshGeneration: 1,
    ));
    expect(
        search.status,
        anyOf(
            MetadataLookupStatus.ambiguous, MetadataLookupStatus.needsReview));
    expect(search.record, isNull,
        reason: 'Title search cannot silently publish a rating.');
    final exact =
        search.candidates.where((candidate) => candidate.titleMatched);
    expect(exact.length, 1,
        reason:
            'This public title must have one exact SNES identity for review.');
    final result = await provider.lookup(MetadataLookupRequest(
      gameId: 'live-proof-snes-smw',
      editionId: 'live-proof-snes-smw-official',
      platformId: 'snes',
      title: 'Super Mario World',
      verifiedProviderGameId: exact.single.providerGameId,
      contentTags: const {'official'},
      refreshGeneration: 1,
    ));
    expect(result.status, MetadataLookupStatus.matched);
    final record = result.record!;
    expect(record.providerId, 'screenscraper');
    expect(record.platformId, 'snes');
    expect(record.descriptions, isNotEmpty);
    expect(record.genres, isNotEmpty);
    expect(record.releaseDates, isNotEmpty);
    expect(record.developer?.isNotEmpty, isTrue);
    expect(record.publisher?.isNotEmpty, isTrue);
    expect(record.media, isNotEmpty);
    expect(record.ratings, isNotEmpty);
    expect(record.ratings.single.scaleMaximum, 20);
    expect(record.ratings.single.consensusValidated, isFalse);
    expect(result.quota?.maxThreads, greaterThan(0));
  },
      skip: developer.isConfigured && user.isConfigured
          ? false
          : 'Live ScreenScraper credentials are not configured.',
      timeout: Timeout.none);

  test('cached catalogue to live review, retry and offline metadata cache',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games (
      id INTEGER PRIMARY KEY AUTOINCREMENT, systemSlug TEXT NOT NULL,
      displayName TEXT NOT NULL, is_folder INTEGER NOT NULL DEFAULT 0,
      artifact_key TEXT, remote_artifact TEXT)''');
    await LibraryQuery.install(db);
    await db.insert(
        'games', {'systemSlug': 'snes', 'displayName': 'Super Mario World'});
    final jobs = MetadataRefreshJobs(Future.value(db));
    final provider = ScreenScraperProvider(
        readDeveloperCredentials: () async => developer,
        readUserCredentials: () async => user);
    addTearDown(provider.close);
    final job = await jobs.createFromCatalogue(
        providerId: provider.providerId, systemSlug: 'snes');
    final first = await jobs.run(job.id, provider, recheckAccess: true);
    expect(first.rated, 0);
    final limits = (await db.query('metadata_provider_limits')).single;
    expect(limits['requests_per_minute'], greaterThan(0));
    expect(limits['quota_exhausted'], 0);
    final review = (await jobs.reviewItems(job.id)).single;
    final exact = review.candidates.where((c) => c.titleMatched);
    expect(exact.length, 1);
    final retry = await jobs.acceptCandidate(job.id,
        editionId: review.editionId,
        providerGameId: exact.single.providerGameId,
        contentTags: {'official'});
    final accepted = await jobs.run(retry.id, provider);
    expect(accepted.counts, {'matched': 1});
    expect(accepted.rated, 1);
    // No provider call participates in consumption of the persisted result.
    final cached = await LibraryStore(Future.value(db))
        .metadata(review.editionId, provider.providerId);
    expect(cached!.refreshGeneration, retry.generation);
    expect(cached.media, isNotEmpty);
    expect(cached.ratings.single.scaleMaximum, 20);
    expect(cached.ratings.single.consensusValidated, isFalse);
    // Narrow real image workflow: one cover and screenshot, through the same
    // durable worker/budget. No ROM payload or device storage is involved.
    final root = await Directory.systemTemp.createTemp('rshop-live-artwork-');
    addTearDown(() async {
      if (!root.path.startsWith(Directory.systemTemp.path) ||
          !root.path
              .split(Platform.pathSeparator)
              .last
              .startsWith('rshop-live-artwork-')) {
        throw StateError('Unexpected live fixture cleanup root');
      }
      await root.delete(recursive: true);
    });
    final selected = ['box-2D', 'ss']
        .map((type) => cached.media.firstWhere((media) => media.type == type));
    final cache = MetadataArtworkCache(Future.value(db), root);
    final images = await jobs.createArtwork(
        providerId: provider.providerId,
        collectionGeneration: job.collectionGeneration,
        editionIds: [review.editionId],
        mediaKeys: selected.map(MetadataArtworkCache.key).toSet());
    final artwork = await jobs.run(images.id, provider, artworkCache: cache);
    expect(artwork.state, 'completed');
    expect(artwork.counts, {'matched': 2});
    expect(artwork.requested, 2);
    provider.close();
    final rating = (await LibraryStore(Future.value(db))
        .effectiveRatings([review.editionId]))[review.editionId];
    expect(rating, isNotNull);
    expect(rating!.rating.toJson(), cached.ratings.single.toJson());
    expect(rating.ownership, OverallRatingOwnership.game);
    expect(rating.fresh, isTrue);
    expect(rating.rankingEligible, isFalse,
        reason:
            'A real successful lookup is not the META-05 reception assessment.');
    expect(rating.assessmentReference, isNull);
    final query = LibraryQuery(Future.value(db));
    final ordinary = await query.page(filter: LibraryQueryFilter());
    expect(ordinary.collectionGames, 1);
    expect(ordinary.items.single.score!.rating.toJson(),
        cached.ratings.single.toJson());
    expect(ordinary.items.single.rank, isNull);
    final top = await query.page(filter: LibraryQueryFilter(top: 25));
    expect(top.items, isEmpty);
    expect(top.rankedGames, 0);
    expect(top.provisional, isTrue);
    final offline = MetadataArtworkCache(Future.value(db), root);
    for (final media in selected) {
      final file =
          await offline.fileFor(review.editionId, 'screenscraper', media);
      expect(file, isNotNull);
      expect(await file!.length(), greaterThan(100));
    }
    expect(
        await root.list().any((file) => file.path.endsWith('.part')), isFalse);
    final fresh =
        await jobs.createFromCatalogue(providerId: provider.providerId);
    expect(fresh.counts, {'pending': 1},
        reason: 'Cached success cannot skip an explicit fresh scrape.');
    final retained = (await LibraryStore(Future.value(db))
        .effectiveRatings([review.editionId]))[review.editionId]!;
    expect(retained.rating.toJson(), cached.ratings.single.toJson());
    expect(retained.fresh, isFalse,
        reason:
            'An explicit newer scrape retains, but marks stale, the old score.');
    expect(retained.rankingEligible, isFalse);
    expect(
        (await query.page(filter: LibraryQueryFilter()))
            .items
            .single
            .score!
            .fresh,
        isFalse);
  },
      skip: developer.isConfigured && user.isConfigured
          ? false
          : 'Live credentials are not configured.',
      timeout: Timeout.none);
}
