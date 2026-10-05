@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
import 'package:retro_eshop/services/metadata/shared_metadata_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_eshop/providers/metadata_providers.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'metadata_controls_test.dart' show MemorySecrets;

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

  test('declared DVD CHD original identifiers match the real provider',
      () async {
    final samples = jsonDecode(values['RSHOP_LIVE_CHD_SAMPLES']!) as List;
    expect(samples.length, greaterThanOrEqualTo(2));
    final api = ScreenScraperProvider(
        readDeveloperCredentials: () async => developer,
        readUserCredentials: () async => user);
    addTearDown(api.close);
    for (final sample in samples.cast<Map<String, dynamic>>()) {
      final platform = sample['platform'] as String;
      expect({'psp', 'ps2'}, contains(platform));
      final file = File(sample['path'] as String);
      final reader = await file.open();
      late Uint8List header;
      try {
        header = await reader.read(140);
      } finally {
        await reader.close();
      }
      final raw = MetadataRomIdentifier.fromChdDvdHeader(
          header, file.uri.pathSegments.last);
      expect(raw, isNotNull);
      final result = await api.lookup(MetadataLookupRequest(
          gameId: 'live-header-$platform',
          editionId: 'live-header-edition-$platform',
          platformId: platform,
          // Deliberately not a title: the provider must match the raw identifier.
          title: 'CHD identifier verification',
          romIdentifier: raw,
          contentTags: {'official'},
          refreshGeneration: 1));
      expect(result.status, MetadataLookupStatus.matched);
      final evidence = raw!.sizeBytes > 0x7fffffff
          ? 'rawRomSha1AndCappedSize'
          : 'rawRomHashAndSize';
      expect(result.candidates.single.evidence, evidence);
      expect(result.record!.matchMethod, evidence);
      expect(result.record!.descriptions, isNotEmpty);
      expect(result.record!.media, isNotEmpty);
    }
  },
      skip: developer.isConfigured &&
              user.isConfigured &&
              values.containsKey('RSHOP_LIVE_CHD_SAMPLES')
          ? false
          : 'Live CHD evidence samples were not explicitly configured.',
      timeout: Timeout.none);

  test('normal controls live review publishes cached cover and screenshots',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final root = await Directory.systemTemp.createTemp('rshop-live-controls-');
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games(id INTEGER PRIMARY KEY,
      systemSlug TEXT, filename TEXT, displayName TEXT, is_folder INTEGER DEFAULT 0,
      artifact_key TEXT, remote_artifact TEXT)''');
    await LibraryQuery.install(db);
    await db.insert('games', {
      'id': 1,
      'systemSlug': 'snes',
      'filename': 'Super Mario World (USA).sfc',
      'displayName': 'Super Mario World'
    });
    final secrets = MemorySecrets();
    final ss = ScreenScraperCredentialStore(storage: secrets);
    await ss.saveDeveloper(developer);
    await ss.saveUser(user);
    final provider = ScreenScraperProvider(
        readDeveloperCredentials: ss.readDeveloper,
        readUserCredentials: ss.readUser);
    final shared = await SharedMetadataStore.open(root);
    final cache = MetadataArtworkCache(Future.value(db), shared.artworkRoot,
        sharedStore: shared);
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials: ss,
        igdbCredentials: IgdbCredentialStore(storage: secrets),
        artworkCache: Future.value(cache),
        sharedStore: Future.value(shared),
        catalogueChanged: () {});
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await shared.close();
      await db.close();
      expect(root.parent.path, Directory.systemTemp.absolute.path);
      expect(root.path.split(Platform.pathSeparator).last,
          startsWith('rshop-live-controls-'));
      await root.delete(recursive: true);
    });
    await controls.load();
    await controls.refresh(cacheRowId: 1);
    final review = (await controls.reviewQueue()).single;
    final exact = review.candidates.where((c) => c.titleMatched).single;
    await controls.acceptReview(review,
        providerGameId: exact.providerGameId, contentTags: {'official'});
    expect(controls.state.error, isFalse);
    expect(controls.state.report!.counts, {'matched': 1});
    final record = (await LibraryStore(Future.value(db))
        .metadata(review.editionId, 'screenscraper'))!;
    final selected = MetadataArtworkCache.displayMedia(record);
    expect(selected.any((m) => m.type == 'box-2D'), isTrue);
    expect(selected.any((m) => m.type == 'ss'), isTrue);
    expect(controls.state.artworkReport!.counts, {'matched': selected.length});
    final child = controls.state.artworkReport!.id;
    final requests = controls.state.artworkReport!.requested;
    // Normal query/decoder references, not a manually inserted game cover URL.
    final local = await cache.artworkForEdition(review.editionId);
    expect(Uri.parse(local.cover!).scheme, 'file');
    expect(local.screenshots, isNotEmpty);
    expect(
        local.screenshots.every((s) => Uri.parse(s).scheme == 'file'), isTrue);
    final covers =
        await LibraryQuery(Future.value(db)).cachedCovers([1], cache);
    expect(covers[1], local.cover);
    DatabaseService.testDatabase = db;
    addTearDown(DatabaseService.resetForTesting);
    final details = await DatabaseService().getGameMetadata(
        'Super Mario World (USA).sfc', 'snes',
        artworkCache: cache);
    expect(details!.cachedCover, local.cover);
    expect(details.screenshotUrlList, local.screenshots);
    await controls.resume();
    expect(controls.state.artworkReport!.id, child);
    expect(controls.state.artworkReport!.requested, requests);
    provider.close(); // Offline recovery must not rely on another API request.
    await db.delete('library_metadata');
    await db.delete('metadata_artwork_cache');
    await shared.close();
    final reopened = await SharedMetadataStore.open(root, existingOnly: true);
    try {
      expect(await reopened.restore(db), 1);
      final recovered = await LibraryStore(Future.value(db))
          .metadata(review.editionId, 'screenscraper');
      expect(recovered!.toJson(), record.toJson());
      final offline = MetadataArtworkCache(
          Future.value(db), reopened.artworkRoot,
          sharedStore: reopened);
      expect((await offline.artworkForEdition(review.editionId)).cover,
          local.cover);
      expect(
          (await LibraryQuery(Future.value(db)).cachedCovers([1], offline))[1],
          local.cover);
    } finally {
      await reopened.close();
    }
    expect(
        await cache.root.list().any((f) => f.path.endsWith('.part')), isFalse);
  },
      skip: developer.isConfigured && user.isConfigured
          ? false
          : 'Live credentials are not configured.',
      timeout: Timeout.none);

  test('public reception assessment capture through persistent worker',
      () async {
    // Deliberately heterogeneous public titles, not the owner's collection.
    // This captures evidence; it never approves a ranking basis. Exact offered
    // title IDs are reviewed here only for these known official test releases.
    const sample = <(String, String)>[
      ('psx', 'Final Fantasy VII'),
      ('psx', 'Metal Gear Solid'),
      ('psx', 'Castlevania: Symphony of the Night'),
      ('psx', 'Croc: Legend of the Gobbos'),
      ('psx', 'Bubsy 3D'),
      ('ps2', 'Shadow of the Colossus'),
      ('ps2', 'Gran Turismo 4'),
      ('ps2', 'The Suffering'),
      ('ps2', 'Superman Returns'),
      ('ps2', 'God of War'),
      ('gba', 'Advance Wars'),
      ('gba', 'Metroid Fusion'),
      ('gba', 'Mario & Luigi: Superstar Saga'),
      ('gba', 'Donkey Kong Country'),
      ('gba', 'Earthworm Jim'),
      ('gc', 'The Legend of Zelda: The Wind Waker'),
      ('gc', 'Resident Evil 4'),
      ('gc', "Eternal Darkness: Sanity's Requiem"),
      ('gc', 'Chibi-Robo!'),
      ('gc', 'Universal Studios Theme Parks Adventure'),
    ];
    // A separately requested diagnostic pass tests published filename-style
    // aliases for the six zero-candidate searches. It cannot silently retry or
    // rename the production catalogue, nor count aliases as additional games.
    const aliases = <(String, String)>[
      ('gba', 'Mario & Luigi - Superstar Saga'),
      ('gc', "Eternal Darkness - Sanity's Requiem"),
      ('psx', 'Croc - Legend of the Gobbos'),
      ('psx', 'Castlevania - Symphony of the Night'),
      ('gc', 'Legend of Zelda, The - The Wind Waker'),
      ('gc', 'Universal Studios Theme Park Adventure'),
    ];
    const remaining = <(String, String)>[
      ('gba', 'Mario And Luigi - Superstar Saga'),
      ('gc', 'Legend Of Zelda - The Wind Waker The'),
    ];
    final requestedSample =
        Platform.environment['RSHOP_RECEPTION_ZELDA'] == 'true'
            ? const [('gc', 'Legend of Zelda, The - The Wind Waker')]
            : Platform.environment['RSHOP_RECEPTION_REMAINING'] == 'true'
                ? remaining
                : Platform.environment['RSHOP_RECEPTION_ALIASES'] == 'true'
                    ? aliases
                    : sample;
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games (
      id INTEGER PRIMARY KEY AUTOINCREMENT, systemSlug TEXT NOT NULL,
      displayName TEXT NOT NULL, is_folder INTEGER NOT NULL DEFAULT 0,
      artifact_key TEXT, remote_artifact TEXT)''');
    await LibraryQuery.install(db);
    for (final (platform, title) in requestedSample) {
      await db.insert('games', {'systemSlug': platform, 'displayName': title});
    }
    final jobs = MetadataRefreshJobs(Future.value(db));
    final store = LibraryStore(Future.value(db));
    final provider = ScreenScraperProvider(
        readDeveloperCredentials: () async => developer,
        readUserCredentials: () async => user);
    addTearDown(provider.close);
    final job = await jobs.createFromCatalogue(providerId: provider.providerId);
    final search = await jobs.run(job.id, provider, recheckAccess: true);
    stdout.writeln('RECEPTION_SEARCH ${jsonEncode({
          'state': search.state,
          'requested': search.requested,
          'counts': search.counts,
          'blockedStatus': search.blockedStatus,
        })}');
    final reviews = await jobs.reviewItems(job.id);
    for (final review in reviews) {
      final identity = await db.rawQuery('''SELECT g.platform_id, g.title
        FROM library_editions e JOIN library_game_identities g
        ON g.game_id = e.game_id WHERE e.edition_id = ?''', [review.editionId]);
      final exact = review.candidates.where((candidate) =>
          candidate.titleMatched ||
          // Explicit public-fixture review of the US/EU title returned by the
          // earlier alias search. No article-reordering heuristic in production.
          (identity.single['platform_id'] == 'gc' &&
              identity.single['title'] ==
                  'Legend of Zelda, The - The Wind Waker' &&
              candidate.providerGameId == '4745'));
      final evidence = <String, Object?>{
        'platform': identity.single['platform_id'],
        'title': identity.single['title'],
        'searchStatus': review.status,
        'candidates': review.candidates
            .map((c) => {
                  'id': c.providerGameId,
                  'platform': c.platformId,
                  'titles': c.titles,
                  'titleMatched': c.titleMatched,
                })
            .toList(),
      };
      if (exact.length == 1) {
        final retry = await jobs.acceptCandidate(job.id,
            editionId: review.editionId,
            providerGameId: exact.single.providerGameId,
            contentTags: {'official'});
        final result = await jobs.run(retry.id, provider);
        evidence['state'] = result.state;
        evidence['counts'] = result.counts;
        evidence['blockedStatus'] = result.blockedStatus;
        final record =
            await store.metadata(review.editionId, provider.providerId);
        if (record != null) {
          expect(record.platformId, identity.single['platform_id']);
          expect(record.providerGameId, exact.single.providerGameId);
          evidence['matchMethod'] = record.matchMethod;
          evidence['retrievedAt'] = record.retrievedAt.toIso8601String();
          evidence['ratings'] = record.ratings
              .map((rating) => {
                    ...rating.toJson(),
                    'normalizedValue': rating.normalizedValue,
                  })
              .toList();
          final selected = (await store
              .effectiveRatings([review.editionId]))[review.editionId];
          expect(selected?.rankingEligible, isNot(true),
              reason: 'Capture cannot approve META-05 consensus.');
        }
        stdout.writeln('RECEPTION_ITEM ${jsonEncode(evidence)}');
        if (result.state != 'completed') break;
      } else {
        stdout.writeln('RECEPTION_ITEM ${jsonEncode(evidence)}');
      }
    }
    expect(sample.map((item) => item.$1).toSet().length, 4);
  },
      skip: developer.isConfigured &&
              user.isConfigured &&
              Platform.environment['RSHOP_RECEPTION_CAPTURE'] == 'true'
          ? false
          : 'Explicit reception capture and live credentials are required.',
      timeout: Timeout.none);

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
