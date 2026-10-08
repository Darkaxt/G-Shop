@Tags(['live'])
library;

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/models/library_identity.dart';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/metadata/effective_overall_rating.dart';
import 'package:retro_eshop/services/metadata/igdb_provider.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';

/// Retain only fixed public boundary/status diagnostics, never auth payloads.
class _BoundaryTransport implements HttpClientAdapter {
  final _delegate = IOHttpClientAdapter();
  final boundaries = <String>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancel) async {
    final response = await _delegate.fetch(options, body, cancel);
    boundaries.add('${options.uri.host}:HTTP${response.statusCode}');
    if (response.statusCode != 200) {
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 8192) break;
        bytes.addAll(chunk);
      }
      final text = utf8.decode(bytes, allowMalformed: true).toLowerCase();
      boundaries.add(text.contains('cloudfront')
          ? 'cloudfront-rejection'
          : text.contains('invalid client secret')
              ? 'invalid-client-secret'
              : text.contains('invalid client id')
                  ? 'invalid-client-id'
                  : text.contains('invalid client') ||
                          text.contains('invalid_client')
                      ? 'invalid-client'
                      : text.contains('blocked')
                          ? 'request-blocked'
                          : 'unclassified-rejection');
      return ResponseBody.fromBytes(bytes, response.statusCode,
          headers: response.headers);
    }
    return response;
  }

  @override
  void close({bool force = false}) => _delegate.close(force: force);
}

Map<String, String> _configuration() {
  final values = <String, String>{};
  final file = File('.env.local');
  if (file.existsSync()) {
    for (final line in file.readAsLinesSync()) {
      final match =
          RegExp(r'^\s*(IGDB_CLIENT_ID|IGDB_CLIENT_SECRET)\s*=\s*(.*)$')
              .firstMatch(line);
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
  return {...values, ...Platform.environment};
}

void main() {
  const liveGameTitle = 'Super Mario World';
  final configuration = _configuration();
  final credentials = IgdbCredentials(configuration['IGDB_CLIENT_ID'] ?? '',
      configuration['IGDB_CLIENT_SECRET'] ?? '');
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('current ScreenScraper cohort reaches IGDB through the normal worker',
      () async {
    final cohort = jsonDecode(
        await File(Platform.environment['RSHOP_CORROBORATION_FIXTURE']!)
            .readAsString()) as List;
    expect(cohort.length, inInclusiveRange(2, 16));
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games (id INTEGER PRIMARY KEY,
      systemSlug TEXT, displayName TEXT, filename TEXT,
      is_folder INTEGER DEFAULT 0, artifact_key TEXT, remote_artifact TEXT)''');
    await LibraryQuery.install(db);
    for (var n = 0; n < cohort.length; n++) {
      final metadata = MetadataRecord.fromJson(cohort[n]['metadata']);
      await db.insert('games', {
        'id': n + 1,
        'systemSlug': metadata.platformId,
        'displayName': 'Synthetic cohort item $n',
        'filename': 'Cohort$n.chd'
      });
    }
    final jobs = MetadataRefreshJobs(Future.value(db));
    await jobs.createFromCatalogue(providerId: 'screenscraper');
    final store = LibraryStore(Future.value(db));
    for (var n = 0; n < cohort.length; n++) {
      final editionId =
          (await LibraryStore.cachedCatalogueEditionId(db, n + 1))!;
      final edition = (await store.edition(editionId))!;
      await store.putEdition(EditionIdentity.fromJson({
        ...edition.toJson(),
        'tags': cohort[n]['tags'],
        'regions': cohort[n]['regions']
      }));
      await store.putMetadata(MetadataRecord.fromJson({
        ...cohort[n]['metadata'] as Map<String, dynamic>,
        'gameId': edition.gameId,
        'editionId': editionId
      }));
    }
    final api = IgdbMetadataProvider(readCredentials: () async => credentials);
    addTearDown(api.close);
    final job = await jobs.createFromCatalogue(providerId: 'igdb');
    final report = await jobs.run(job.id, api);
    expect(report.state, 'completed');
    expect(report.counts['matched'] ?? 0, greaterThan(0));
    expect(report.counts['identityChanged'] ?? 0, 0);
    final page = await LibraryQuery(Future.value(db))
        .page(filter: LibraryQueryFilter(top: 25));
    final records = (await db.query('library_metadata',
            where: 'provider_id = ?', whereArgs: ['igdb']))
        .map((row) =>
            MetadataRecord.fromJson(jsonDecode(row['record_json'] as String)))
        .toList();
    expect(records.length, report.counts['matched']);
    final adequatelySupported = records
        .where((r) => r.ratings.any((rating) =>
            rating.kind == RatingKind.communityAggregate &&
            (rating.voteCount ?? 0) >= 20))
        .length;
    expect(page.rankedGames, lessThanOrEqualTo(adequatelySupported));
    if (adequatelySupported == 0) expect(page.rankedGames, 0);
    for (final record in records) {
      expect(record.matchMethod, 'corroboratedOfficialRelease');
      expect(record.matchEvidence['recordHash'], hasLength(64));
    }
    for (final item in page.items) {
      expect(item.score!.rating.sourceId, 'igdb');
      expect(item.score!.rating.kind, RatingKind.communityAggregate);
      expect(item.score!.rating.voteCount!, greaterThanOrEqualTo(20));
      final record = (await store.metadata(item.editionId, 'igdb'))!;
      expect(record.matchMethod, 'corroboratedOfficialRelease');
      expect(record.matchEvidence['recordHash'], hasLength(64));
    }
    stdout.writeln('IGDB_CORROBORATION_COHORT ${jsonEncode({
          'items': cohort.length,
          'state': report.state,
          'outcomes': report.counts,
          'canonicalGames': page.collectionGames,
          'rankedGames': page.rankedGames,
          'adequatelySupportedRecords': adequatelySupported,
          'provisional': page.provisional
        })}');
  },
      skip: credentials.isConfigured &&
              Platform.environment.containsKey('RSHOP_CORROBORATION_FIXTURE')
          ? false
          : 'A bounded current cohort and legitimate credentials must be explicitly provided.',
      timeout: Timeout.none);

  test('public IGDB reception assessment through persistent worker', () async {
    // Public benchmark releases, never the owner's private collection. Candidate
    // review is literal-title based and remains separate from score approval.
    const sample = <(String, String, Set<String>)>[
      ('psx', 'Final Fantasy VII', {'official'}),
      ('psx', 'Metal Gear Solid', {'official'}),
      ('psx', 'Castlevania: Symphony of the Night', {'official'}),
      ('psx', 'Croc: Legend of the Gobbos', {'official'}),
      ('psx', 'Bubsy 3D', {'official'}),
      ('ps2', 'Shadow of the Colossus', {'official'}),
      ('ps2', 'Gran Turismo 4', {'official'}),
      ('ps2', 'The Suffering', {'official'}),
      ('ps2', 'Superman Returns', {'official'}),
      ('ps2', 'God of War', {'official'}),
      ('gba', 'Advance Wars', {'official'}),
      ('gba', 'Metroid Fusion', {'official'}),
      ('gba', 'Mario & Luigi: Superstar Saga', {'official'}),
      ('gba', 'Donkey Kong Country', {'official'}),
      ('gba', 'Earthworm Jim', {'official'}),
      ('gc', 'The Legend of Zelda: The Wind Waker', {'official'}),
      ('gc', 'Resident Evil 4', {'official'}),
      ('gc', "Eternal Darkness: Sanity's Requiem", {'official'}),
      ('gc', 'Chibi-Robo!', {'official'}),
      ('gc', 'Universal Studios Theme Parks Adventure', {'official'}),
      ('switch', 'The Legend of Zelda: Breath of the Wild', {'official'}),
      ('switch', 'Super Mario Odyssey', {'official'}),
      ('switch', '1-2-Switch', {'official'}),
      ('switch', 'Balan Wonderworld', {'official'}),
      // S7's newly mapped collection scopes: capture actual reception without
      // implicitly approving a platform or borrowing a different port's score.
      ('n64', 'Super Mario 64', {'official'}),
      ('n64', 'The Legend of Zelda: Ocarina of Time', {'official'}),
      ('n64', 'Banjo-Kazooie', {'official'}),
      ('n64', 'Quest 64', {'official'}),
      ('n64', 'Superman: The New Superman Adventures', {'official'}),
      ('psp', 'God of War: Chains of Olympus', {'official'}),
      ('psp', 'Lumines', {'official'}),
      ('psp', 'Metal Gear Solid: Peace Walker', {'official'}),
      ('psp', 'The 3rd Birthday', {'official'}),
      ('psp', 'Dragonball Evolution: The Game', {'official'}),
      ('gamegear', 'Sonic the Hedgehog', {'official'}),
      ('gamegear', 'Shinobi', {'official'}),
      ('gamegear', 'Streets of Rage', {'official'}),
      ('gamegear', 'Sonic the Hedgehog: Triple Trouble', {'official'}),
      ('gamegear', 'Super Columns', {'official'}),
      // GB/GBC are now part of the normal already-local identification slice.
      // This captures coverage only; it cannot approve their ranking policy.
      ('gb', 'Super Mario Land 2: 6 Golden Coins', {'official'}),
      ('gb', "The Legend of Zelda: Link's Awakening", {'official'}),
      ('gb', 'Metroid II: Return of Samus', {'official'}),
      ('gb', "Kirby's Dream Land", {'official'}),
      ('gb', 'Batman Forever', {'official'}),
      ('gbc', 'Pokémon Crystal Version', {'official'}),
      ('gbc', 'The Legend of Zelda: Oracle of Ages', {'official'}),
      ('gbc', 'Wario Land 3', {'official'}),
      ('gbc', 'Perfect Dark', {'official'}),
      ('gbc', 'The Grinch', {'official'}),
      // S7's now-restorable NES/SNES scopes. Capture actual high/middle/low
      // reception before any production score-policy extension; explicit
      // benchmark review never becomes automatic library classification.
      ('nes', 'Super Mario Bros. 3', {'official'}),
      ('nes', 'Mega Man 2', {'official'}),
      ('nes', "Castlevania II: Simon's Quest", {'official'}),
      ('nes', 'Dr. Jekyll and Mr. Hyde', {'official'}),
      ('nes', 'Action 52', {'official'}),
      ('snes', 'Super Mario World', {'official'}),
      ('snes', 'Chrono Trigger', {'official'}),
      ('snes', "Super Ghouls'n Ghosts", {'official'}),
      ('snes', 'Shaq-Fu', {'official'}),
      ('snes', 'Super James Pond', {'official'}),
      // Public reception fixtures for S7 recovery scopes. Capture/review alone
      // cannot approve production ranking, library identity or SD removal.
      ('wii', 'Super Mario Galaxy', {'official'}),
      ('wii', 'The Legend of Zelda: Skyward Sword', {'official'}),
      ('wii', 'Wii Sports', {'official'}),
      ('wii', 'Red Steel', {'official'}),
      ('wii', 'Ninjabread Man', {'official'}),
      ('wiiu', 'Super Mario 3D World', {'official'}),
      ('wiiu', 'Mario Kart 8', {'official'}),
      ('wiiu', 'Xenoblade Chronicles X', {'official'}),
      ('wiiu', "Devil's Third", {'official'}),
      ('wiiu', 'Sonic Boom: Rise of Lyric', {'official'}),
      ('snes', 'Chrono Trigger: Crimson Echoes', {'Hack'}),
      ('gba', 'Pokémon Unbound', {'Hack'}),
    ];
    final requestedTitles =
        Platform.environment['RSHOP_RECEPTION_TITLE']?.split('|').toSet();
    final requestedSample = requestedTitles == null
        ? sample
        : sample.where((s) => requestedTitles.contains(s.$2)).toList();
    expect(requestedSample, isNotEmpty,
        reason: 'Diagnostic capture is limited to the public benchmark.');
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games (
      id INTEGER PRIMARY KEY AUTOINCREMENT, systemSlug TEXT NOT NULL,
      displayName TEXT NOT NULL, filename TEXT NOT NULL,
      is_folder INTEGER NOT NULL DEFAULT 0,
      artifact_key TEXT, remote_artifact TEXT)''');
    await LibraryQuery.install(db);
    for (final (index, (platform, title, _)) in requestedSample.indexed) {
      await db.insert('games', {
        'systemSlug': platform,
        'displayName': title,
        'filename': 'Benchmark$index.rom',
      });
    }
    final jobs = MetadataRefreshJobs(Future.value(db));
    final store = LibraryStore(Future.value(db));
    final transport = _BoundaryTransport();
    final provider = IgdbMetadataProvider(
        httpClientAdapter: transport, readCredentials: () async => credentials);
    addTearDown(provider.close);
    final job = await jobs.createFromCatalogue(providerId: provider.providerId);
    final search = await jobs.run(job.id, provider);
    expect(search.state, 'completed',
        reason: 'Capture stopped at ${search.blockedStatus}; '
            '${transport.boundaries}');
    expect(search.rated, 0);
    final reviews = await jobs.reviewItems(job.id);
    expect(reviews.length, requestedSample.length);
    for (final review in reviews) {
      final identity = await db.rawQuery('''SELECT g.platform_id, g.title
        FROM library_editions e JOIN library_game_identities g
        ON g.game_id = e.game_id WHERE e.edition_id = ?''', [review.editionId]);
      final platform = identity.single['platform_id'] as String;
      final title = identity.single['title'] as String;
      final tags =
          sample.singleWhere((s) => s.$1 == platform && s.$2 == title).$3;
      final exact = review.candidates.where((candidate) =>
          candidate.titleMatched &&
          candidate.titles.any((t) => t.text == title) &&
          // Explicit public-fixture review of the original 1997 release.
          // Search also offers International and another same-named entry;
          // this ID is not a production matching rule or score override.
          (title != 'Final Fantasy VII' || candidate.providerGameId == '427'));
      final evidence = <String, Object?>{
        'platform': platform,
        'title': title,
        'tags': tags.toList(),
        'searchStatus': review.status,
        'candidates': review.candidates
            .map((c) => {
                  'id': c.providerGameId,
                  'titles': c.titles.map((t) => t.text).toList(),
                  'titleMatched': c.titleMatched,
                })
            .toList(),
      };
      if (exact.length == 1) {
        final retry = await jobs.acceptCandidate(job.id,
            editionId: review.editionId,
            providerGameId: exact.single.providerGameId,
            contentTags: tags);
        final result = await jobs.run(retry.id, provider);
        evidence['state'] = result.state;
        evidence['counts'] = result.counts;
        expect(result.state, 'completed',
            reason: 'Capture stopped at ${result.blockedStatus}; '
                '${transport.boundaries}');
        final record = await store.metadata(review.editionId, 'igdb');
        if (record != null) {
          expect(record.platformId, platform);
          expect(record.providerGameId, exact.single.providerGameId);
          evidence['id'] = record.providerGameId;
          evidence['matchMethod'] = record.matchMethod;
          evidence['retrievedAt'] = record.retrievedAt.toIso8601String();
          evidence['ratings'] = record.ratings.map((r) => r.toJson()).toList();
          expect(record.ratings.every((r) => !r.consensusValidated), isTrue);
          final selected = (await store.effectiveRatings([review.editionId],
              assessedBases: const []))[review.editionId];
          expect(selected?.rankingEligible, isNot(true),
              reason: 'Live capture cannot approve a ranking basis.');
        }
      }
      stdout.writeln('IGDB_RECEPTION_ITEM ${jsonEncode(evidence)}');
    }
    provider.close();
    // Real cached records, production assessment and indexed query, with the
    // network adapter already closed. A small/unknown sample is never zeroed.
    final query = LibraryQuery(Future.value(db));
    final ordinary = await query.page(filter: LibraryQueryFilter());
    expect(ordinary.collectionGames, requestedSample.length);
    for (final item in ordinary.items) {
      final selected =
          (await store.effectiveRatings([item.editionId]))[item.editionId];
      expect(item.score?.rating.toJson(), selected?.rating.toJson());
      expect(item.score?.rankingEligible, selected?.rankingEligible);
      if (selected?.rankingEligible == true) {
        expect(selected!.rating.kind.name, 'communityAggregate');
        expect(selected.rating.voteCount, greaterThanOrEqualTo(20));
        expect(productionOverallScoreBases.single.platformIds,
            contains(item.platformId));
      }
    }
    final top = await query.page(filter: LibraryQueryFilter(top: 25));
    expect(
        top.items.map((i) => i.editionId).toSet(),
        ordinary.items
            .where((i) => i.rank != null && i.rank! <= 25)
            .map((i) => i.editionId)
            .toSet());
    expect(top.provisional, ordinary.rankedGames < ordinary.collectionGames);
    stdout.writeln('IGDB_RECEPTION_QUERY ${jsonEncode({
          'collectionGames': ordinary.collectionGames,
          'rankedGames': ordinary.rankedGames,
          'topMatches': top.totalMatches,
          'provisional': top.provisional,
          'offline': true,
        })}');
    expect(sample.map((s) => s.$1).toSet().length, greaterThanOrEqualTo(4));
  },
      skip: credentials.isConfigured &&
              Platform.environment['RSHOP_RECEPTION_CAPTURE'] == 'true'
          ? false
          : 'Explicit capture and live IGDB credentials are required.',
      timeout: Timeout.none);

  test(
      'real IGDB catalogue review, sourced scores and offline SQLite consumption',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games (
      id INTEGER PRIMARY KEY AUTOINCREMENT, systemSlug TEXT NOT NULL,
      displayName TEXT NOT NULL, filename TEXT NOT NULL,
      is_folder INTEGER NOT NULL DEFAULT 0,
      artifact_key TEXT, remote_artifact TEXT)''');
    await db.insert('games', {
      'systemSlug': 'snes',
      'displayName': liveGameTitle,
      'filename': 'Benchmark.sfc',
    });
    final jobs = MetadataRefreshJobs(Future.value(db));
    final transport = _BoundaryTransport();
    final provider = IgdbMetadataProvider(
        httpClientAdapter: transport, readCredentials: () async => credentials);
    addTearDown(provider.close);
    final job = await jobs.createFromCatalogue(providerId: provider.providerId);
    final first = await jobs.run(job.id, provider);
    expect(first.state, 'completed',
        reason:
            'Provider boundary: ${first.blockedStatus}; ${transport.boundaries}');
    expect(first.rated, 0);
    final review = (await jobs.reviewItems(job.id)).single;
    // Review the actual public title, not punctuation-stripped equivalence:
    // Super "Mario" World is a distinct hack, not Super Mario World.
    final exact = review.candidates.where((c) =>
        c.titleMatched && c.titles.any((title) => title.text == liveGameTitle));
    expect(exact.length, 1,
        reason:
            'A platform/title candidate needs an explicit review identity.');
    final retry = await jobs.acceptCandidate(job.id,
        editionId: review.editionId,
        providerGameId: exact.single.providerGameId,
        contentTags: {'official'});
    final accepted = await jobs.run(retry.id, provider);
    expect(accepted.counts, {'matched': 1},
        reason: 'Reviewed public IGDB game ${exact.single.providerGameId}; '
            'boundary ${transport.boundaries}');
    expect(accepted.rated, 1);
    provider.close();
    final cached =
        await LibraryStore(Future.value(db)).metadata(review.editionId, 'igdb');
    expect(cached, isNotNull);
    final overall =
        cached!.ratings.firstWhere((r) => r.sourceLabel == 'IGDB overall');
    final critics =
        cached.ratings.firstWhere((r) => r.sourceLabel == 'IGDB critics');
    final users =
        cached.ratings.firstWhere((r) => r.sourceLabel == 'IGDB users');
    expect(overall.voteCount, greaterThan(0));
    expect(critics.voteCount, greaterThan(0));
    expect(users.voteCount, greaterThan(0));
    expect(cached.ratings.every((r) => !r.consensusValidated), isTrue);
    expect(
        (await db.query('metadata_provider_limits'))
            .single['requests_per_minute'],
        240);
  },
      skip: credentials.isConfigured
          ? false
          : 'Live IGDB credentials are not configured.',
      timeout: Timeout.none);
}
