import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_eshop/providers/library_providers.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/commercial_release_preference.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/metadata/effective_overall_rating.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/features/game_list/logic/game_list_controller.dart';
import 'package:retro_eshop/models/config/system_config.dart';
import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'game_list_controller_test.dart'
    show FakeStorageService, waitUntilLoaded;
import 'metadata_controls_test.dart' show ControlsProvider;

class _CacheDatabase extends DatabaseService {
  final Database cache;
  _CacheDatabase(this.cache);
  @override
  Future<Database> get database => Future.value(cache);
}

// Observe actual SQLite work without substituting database results. Android
// sends each executor call/batch commit over its native transport boundary.
class _ProjectionDatabase implements Database {
  final Database inner;
  int batches = 0;
  int standaloneWrites = 0;
  int catalogueReads = 0;
  final catalogueQueries = <({String sql, List<Object?> args})>[];
  _ProjectionDatabase(this.inner);

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction) action,
          {bool? exclusive}) =>
      inner.transaction((txn) => action(_ProjectionTransaction(txn, this)),
          exclusive: exclusive);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected projection database operation');
}

class _ProjectionTransaction implements Transaction {
  final Transaction inner;
  final _ProjectionDatabase observation;
  _ProjectionTransaction(this.inner, this.observation);

  @override
  Batch batch() {
    observation.batches++;
    return inner.batch();
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) {
    if (RegExp(r'\b(?:FROM|JOIN)\s+games\b', caseSensitive: false)
        .hasMatch(sql)) {
      observation.catalogueReads++;
      observation.catalogueQueries
          .add((sql: sql, args: List.of(arguments ?? const [])));
    }
    return inner.rawQuery(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> query(String table,
      {bool? distinct,
      List<String>? columns,
      String? where,
      List<Object?>? whereArgs,
      String? groupBy,
      String? having,
      String? orderBy,
      int? limit,
      int? offset}) {
    if (table == 'games') observation.catalogueReads++;
    return inner.query(table,
        distinct: distinct,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy,
        having: having,
        orderBy: orderBy,
        limit: limit,
        offset: offset);
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) {
    observation.standaloneWrites++;
    return inner.insert(table, values,
        nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) {
    observation.standaloneWrites++;
    return inner.delete(table, where: where, whereArgs: whereArgs);
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) {
    observation.standaloneWrites++;
    return inner.execute(sql, arguments);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected projection transaction operation');
}

class _ConsoleCacheDatabase extends _CacheDatabase {
  final List<GameItem> games;
  _ConsoleCacheDatabase(super.cache, this.games);
  @override
  Future<bool> hasCache(String systemSlug) async => true;
  @override
  Future<List<GameItem>> getGames(String systemSlug) async => games;
}

class _FreshFilterStorage extends FakeStorageService {
  @override
  DateTime? getLastSyncTime(String systemId) => DateTime.now();
}

void main() {
  late Database db;
  late LibraryStore store;
  late LibraryQuery query;
  final at = DateTime.utc(2026, 10, 3);
  final basis = AssessedOverallScoreBasis(
      sourceId: 'igdb',
      kind: RatingKind.overallAggregate,
      scaleMinimum: 0,
      scaleMaximum: 100,
      platformIds: {'psx', 'snes'},
      minimumVoteCount: 10,
      assessmentReference: 'synthetic-query-assessment');
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games(id INTEGER PRIMARY KEY,
      systemSlug TEXT, displayName TEXT, filename TEXT, artifact_key TEXT, remote_artifact TEXT,
      is_folder INTEGER DEFAULT 0)''');
    await LibraryQuery.install(db);
    store = LibraryStore(Future.value(db));
    query = LibraryQuery(Future.value(db));
  });
  tearDown(() => db.close());

  Future<String> seed(int n,
      {double? score,
      String platform = 'psx',
      String? group,
      Set<String> tags = const {'official'},
      List<String> genres = const ['Action'],
      List<String> regions = const ['USA'],
      List<String> languages = const ['en'],
      int votes = 100,
      RatingKind ratingKind = RatingKind.overallAggregate,
      bool screenScraperId = true,
      RemoteArtifact? artifact}) async {
    await db.insert('games', {
      'id': n,
      'systemSlug': platform,
      'displayName': 'Game $n',
      'filename': artifact?.displayName ?? 'Game $n.7z',
      if (artifact != null) 'artifact_key': artifact.id.key,
      if (artifact != null) 'remote_artifact': jsonEncode(artifact.toJson()),
    });
    final id = (await db.transaction((txn) =>
            LibraryStore.catalogueEditions(txn, cacheRowId: n).toList()))
        .single;
    final edition = (await store.edition(id))!;
    final game = (await store.game(edition.gameId))!;
    final providerId = group ?? '$n';
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'matchStatus': 'manuallyMatched',
      'providerIds': {
        if (screenScraperId) 'screenscraper': providerId,
        'igdb': providerId
      }
    }));
    await store.putEdition(EditionIdentity.fromJson({
      ...edition.toJson(),
      'tags': tags.toList(),
      'regions': regions,
      'languages': languages,
      if (tags.contains('T-Eng')) 'isTranslation': true,
      if (tags.contains('T-Eng')) 'translatedLanguages': ['en']
    }));
    if (score != null) {
      await store.putMetadata(MetadataRecord(
          gameId: game.id,
          editionId: id,
          platformId: platform,
          providerId: 'igdb',
          providerGameId: providerId,
          retrievedAt: at,
          refreshGeneration: 1,
          matchMethod: tags.contains('Hack')
              ? 'verifiedProjectId'
              : 'verifiedProviderIdGlobalGame',
          titles: [MetadataText(text: 'Game $n')],
          genres: genres
              .map((g) => MetadataGenre(
                  providerGenreId: g, names: [MetadataText(text: g)]))
              .toList(),
          ratings: [
            SourcedRating.parse(
                sourceId: 'igdb',
                sourceLabel: 'IGDB',
                providerGameId: providerId,
                rawValue: score,
                scaleMinimum: 0,
                scaleMaximum: 100,
                voteCount: votes,
                kind: ratingKind,
                retrievedAt: at)!
          ]));
    }
    return id;
  }

  Future<LibraryQueryPage> read({LibraryQueryFilter? filter}) => query
      .page(filter: filter ?? LibraryQueryFilter(), assessedBases: [basis]);

  test(
      'commercial preference keeps the best available region without changing ranks',
      () async {
    final usa = await seed(1, group: 'same', score: 95);
    final eur = await seed(2, group: 'same', score: 95, regions: ['Europe']);
    final jpn = await seed(3, group: 'same', score: 95, regions: ['Japan']);
    final unique = await seed(4, score: 90, regions: ['Korea']);
    final hack = await seed(5, tags: {'Hack'}, regions: ['USA']);
    final translated =
        await seed(6, group: 'same', tags: {'T-Eng'}, regions: ['USA']);
    const preference = CommercialReleasePreference();
    Future<LibraryQueryPage> selected(CommercialReleasePreference value,
            {int? top, String? search}) =>
        read(
            filter: LibraryQueryFilter(
                releasePreference: value,
                includeVariants: true,
                top: top,
                search: search));
    final page = await selected(preference);
    expect(page.items.map((e) => e.editionId).toSet(),
        {eur, unique, hack, translated});
    expect(page.rankedGames, 2);
    final top = await selected(preference, top: 1);
    expect(top.items.single.editionId, eur);
    expect(top.items.single.rank, 1);
    expect(
        (await selected(preference.move(1, -1))).items.map((e) => e.editionId),
        contains(usa));
    expect(
        (await selected(preference.move(2, -2))).items.map((e) => e.editionId),
        contains(jpn));
    expect(
        (await selected(preference.showingAll(true)))
            .items
            .map((e) => e.editionId)
            .toSet(),
        {usa, eur, jpn, unique, hack, translated});
    // Search intersects available releases, never switches to a hidden namesake
    // outside that search or invents a new score.
    expect(
        (await selected(preference, search: 'Game 1')).items.single.editionId,
        usa);
  });

  test(
      'release preference preserves same-region revisions and complete bundles',
      () async {
    final us = await seed(1, group: 'bundle');
    final eu = await seed(2, group: 'bundle', regions: ['Europe']);
    final rev = await seed(3, group: 'bundle', regions: ['Europe']);
    final original = (await store.edition(eu))!;
    final members = [
      for (var disc = 1; disc <= 2; disc++)
        EditionMember(
            artifactId: RemoteArtifactId(
                providerId: 'drive',
                sourceId: 'source',
                providerFileId: 'disc-$disc'),
            discNumber: disc)
    ];
    await store.putEdition(EditionIdentity.fromJson({
      ...original.toJson(),
      'members': members.map((e) => e.toJson()).toList()
    }));
    final revision = (await store.edition(rev))!;
    await store.putEdition(
        EditionIdentity.fromJson({...revision.toJson(), 'revision': 'Rev 1'}));
    final multi = await seed(4, group: 'multi', regions: ['USA', 'Europe']);
    await seed(5, group: 'multi', regions: ['Japan']);
    final unknown = await seed(6, group: 'ambiguous');
    final unknownEdition = (await store.edition(unknown))!;
    final unknownGame = (await store.game(unknownEdition.gameId))!;
    await store.putGame(GameIdentity.fromJson(
        {...unknownGame.toJson(), 'matchStatus': 'ambiguous'}));
    final page = await read(
        filter: LibraryQueryFilter(
            releasePreference: const CommercialReleasePreference(),
            includeVariants: true));
    expect(
        page.items.map((e) => e.editionId).toSet(), {eu, rev, multi, unknown});
    expect(page.items.map((e) => e.editionId), isNot(contains(us)));
    expect((await store.edition(eu))!.members.map((m) => m.discNumber), [1, 2]);
  });

  test(
      'release discovery does not reintroduce hidden alternatives as legacy fallback',
      () async {
    await seed(1, group: 'same', regions: ['USA'], score: 95);
    await seed(2, group: 'same', regions: ['Europe'], score: 95);
    await seed(3, group: 'unique', regions: ['Brazil']);
    final keys = [
      for (var i = 1; i <= 3; i++) coverRatingKey('psx', 'Game $i.7z')
    ];
    final result = (await query.discover(
        filter: LibraryQueryFilter(
            platformIds: {'psx'},
            releasePreference: const CommercialReleasePreference(),
            featuredTop: 100),
        orderedKeys: keys,
        isCurrent: () => true,
        assessedBases: [basis]))!;
    expect(result.groups.values.expand((e) => e), [keys[1], keys[2]]);
    expect(result.boundKeys, keys.toSet());
    expect(result.featuredRanks.values, [1]);
    expect(result.totalMatches, 2);
    expect(await db.query('library_query_views'), isEmpty);
  });

  test(
      'provider-verified canonical releases do not require manual game assignment',
      () async {
    final usa = await seed(1, regions: ['USA']);
    final eur = await seed(2, regions: ['Europe']);
    for (final id in [usa, eur]) {
      final edition = (await store.edition(id))!;
      final game = (await store.game(edition.gameId))!;
      await store.putGame(GameIdentity.fromJson({
        ...game.toJson(),
        'matchStatus': 'unmatched',
        'providerIds': <String, String>{}
      }));
      await store.putMetadata(MetadataRecord(
          gameId: game.id,
          editionId: id,
          platformId: 'psx',
          providerId: 'screenscraper',
          providerGameId: 'verified-same-game',
          titles: [MetadataText(text: 'Verified game')],
          retrievedAt: at,
          refreshGeneration: 1,
          matchMethod: 'rawRomHashAndSize'));
    }
    final page = await read(
        filter: LibraryQueryFilter(
            releasePreference: const CommercialReleasePreference(),
            includeVariants: true));
    expect(page.collectionGames, 1);
    expect(page.items.single.editionId, eur);
  });

  test('Top 25 collector snapshots canonical ranked membership and coverage',
      () async {
    final expected = <String>{};
    for (var n = 1; n <= 31; n++) {
      final id = await seed(n,
          score: 100 - n.toDouble(), ratingKind: RatingKind.communityAggregate);
      if (n <= 25) expected.add(id);
    }
    final alternate = await seed(100,
        group: '1', score: 99, ratingKind: RatingKind.communityAggregate);
    await seed(101); // No alphabetical filling.
    await seed(102,
        score: 100, votes: 1, ratingKind: RatingKind.communityAggregate);
    expected.add(await seed(201,
        platform: 'snes',
        score: 91,
        ratingKind: RatingKind.communityAggregate));
    expected.add(await seed(202,
        platform: 'snes',
        score: 89,
        ratingKind: RatingKind.communityAggregate));
    await seed(301, platform: 'gb');
    await seed(401,
        platform: 'gg', score: 99, ratingKind: RatingKind.communityAggregate);
    final jobs = MetadataRefreshJobs(Future.value(db));
    expect(
        () =>
            jobs.createFromCatalogue(providerId: 'igdb', top25PerSystem: true),
        throwsArgumentError);
    expect(
        () => jobs.createFromCatalogue(
            providerId: 'screenscraper', top25PerSystem: true, cacheRowId: 1),
        throwsArgumentError);
    final job = await jobs.createFromCatalogue(
        providerId: 'screenscraper',
        systemSlugs: const ['psx', 'snes', 'gb', 'gg'],
        top25PerSystem: true);
    final rows = await db.query('metadata_refresh_items',
        where: 'job_id=?', whereArgs: [job.id]);
    final selected = rows.map((row) => row['edition_id'] as String).toSet();
    // The tied alternate edition may be chosen deterministically, but never both.
    expect(selected.length, 27);
    expect(selected.intersection(expected).length, greaterThanOrEqualTo(26));
    expect(selected.difference(expected), everyElement(equals(alternate)));
    expect(job.selectionCoverage['psx'],
        {'selected': 25, 'eligible': 31, 'collection': 33});
    expect(job.selectionCoverage['snes'],
        {'selected': 2, 'eligible': 2, 'collection': 2});
    expect(job.selectionCoverage['gb'],
        {'selected': 0, 'eligible': 0, 'collection': 1});
    expect(job.selectionCoverage['gg'],
        {'selected': 0, 'eligible': 0, 'collection': 1});
    expect(job.top25PerSystem, isTrue);
    await seed(500, score: 100, ratingKind: RatingKind.communityAggregate);
    final restored = await MetadataRefreshJobs(Future.value(db)).report(job.id);
    expect(restored.selectionCoverage, job.selectionCoverage);
    expect(
        (await db.query('metadata_refresh_items',
                where: 'job_id=?', whereArgs: [job.id]))
            .map((row) => row['edition_id'])
            .toSet(),
        selected);

    await seed(501,
        platform: 'n64',
        score: 95,
        ratingKind: RatingKind.communityAggregate,
        screenScraperId: false,
        artifact: RemoteArtifact(
            id: RemoteArtifactId(
                providerId: 'drive',
                sourceId: 'fixture',
                accountId: 'fixture',
                providerFileId: 'sample'),
            displayPath: 'sample.7z',
            displayName: 'sample.7z',
            version: '1',
            sizeBytes: 100,
            canDownload: true));
    var romReads = 0;
    final bounded = MetadataRefreshJobs(Future.value(db),
        readRomHeader: (_, __, ___) async {
      romReads++;
      return null;
    }, readArchiveIdentifier: (_, __, ___) async {
      romReads++;
      return null;
    });
    final sample = await bounded.createFromCatalogue(
        providerId: 'screenscraper', systemSlug: 'n64', top25PerSystem: true);
    expect(sample.selectionCoverage['n64']!['selected'], 1);
    final provider = ControlsProvider();
    final progress = <bool>[];
    await bounded.run(sample.id, provider,
        onProgress: (value) => progress.add(value.top25PerSystem));
    expect(provider.calls, hasLength(1));
    expect(progress, isNotEmpty);
    expect(progress, everyElement(isTrue));
    final retry = await bounded.retryUnresolved(sample.id);
    expect(retry.top25PerSystem, isTrue);
    expect(retry.selectionCoverage, sample.selectionCoverage);
    await bounded.run(retry.id, provider);
    expect(provider.calls, hasLength(2));
    expect(romReads, 0,
        reason:
            'The artwork pass must not fetch any ROM data, including on retry');
  });

  test('Top 25 media collection snapshots one release per ranked game',
      () async {
    final ids = <String>[];
    for (var n = 1; n <= 27; n++) {
      ids.add(await seed(n,
          platform: 'gba',
          score: 100 - n.toDouble(),
          ratingKind: RatingKind.communityAggregate));
    }
    ids.add(await seed(100,
        platform: 'gba',
        group: '1',
        score: 99,
        regions: ['Europe'],
        ratingKind: RatingKind.communityAggregate));
    for (final id in ids) {
      final edition = (await store.edition(id))!;
      final game = (await store.game(edition.gameId))!;
      final providerId = game.providerIds['screenscraper']!;
      await store.putMetadata(MetadataRecord(
          gameId: game.id,
          editionId: id,
          platformId: 'gba',
          providerId: 'screenscraper',
          providerGameId: providerId,
          retrievedAt: at,
          refreshGeneration: 1,
          matchMethod: 'verifiedProviderId',
          titles: [
            MetadataText(text: game.title)
          ],
          media: [
            MetadataMedia(
                type: 'box-2D',
                region: 'us',
                providerReference: ScreenScraperMediaReference(
                    providerGameId: providerId,
                    providerPlatformId: 12,
                    mediaType: 'box-2D',
                    region: 'us'))
          ]));
    }
    final job = await MetadataRefreshJobs(Future.value(db))
        .createResourcesFromCatalogue(
            providerId: 'screenscraper',
            systemSlug: 'gba',
            top25PerSystem: true);
    final items = await db.query('metadata_artwork_items',
        where: 'job_id=?', whereArgs: [job.id]);
    expect(items.map((r) => r['edition_id']).toSet(), hasLength(25));
    expect(job.resourcesOnly, isTrue);
    expect(job.top25PerSystem, isTrue);
    expect(job.selectionCoverage['gba'],
        {'selected': 25, 'eligible': 27, 'collection': 27});
    expect(
        (await MetadataRefreshJobs(Future.value(db)).report(job.id))
            .selectionCoverage,
        job.selectionCoverage);
  });

  test('resource-only snapshot never creates unmatched catalogue identities',
      () async {
    final current = await seed(1, platform: 'gba');
    final removed = await seed(2, platform: 'gba');
    final other = await seed(3, platform: 'snes');
    for (final id in [current, removed, other]) {
      final edition = (await store.edition(id))!;
      final game = (await store.game(edition.gameId))!;
      final providerId = game.providerIds['screenscraper']!;
      await store.putMetadata(MetadataRecord(
          gameId: game.id,
          editionId: id,
          platformId: game.platformId!,
          providerId: 'screenscraper',
          providerGameId: providerId,
          retrievedAt: at,
          refreshGeneration: 1,
          matchMethod: 'verifiedProviderId',
          titles: [
            MetadataText(text: game.title)
          ],
          media: [
            MetadataMedia(
                type: 'box-2D',
                region: 'us',
                providerReference: ScreenScraperMediaReference(
                    providerGameId: providerId,
                    providerPlatformId: game.platformId == 'gba' ? 12 : 4,
                    mediaType: 'box-2D',
                    region: 'us'))
          ]));
    }
    await db.delete('games', where: 'id=?', whereArgs: [2]);
    await db.insert('games', {
      'id': 4,
      'systemSlug': 'gba',
      'displayName': 'Never matched',
      'filename': 'Never matched.gba'
    });
    final before = await db.query('library_editions', orderBy: 'edition_id');
    final job = await MetadataRefreshJobs(Future.value(db))
        .createResourcesFromCatalogue(
            providerId: 'screenscraper', systemSlugs: ['gba']);
    expect(
        (await db.query('metadata_artwork_items',
                where: 'job_id=?', whereArgs: [job.id]))
            .map((row) => row['edition_id'])
            .toSet(),
        {current});
    expect(await db.query('library_editions', orderBy: 'edition_id'), before,
        reason:
            'Collecting existing media must not capture/rematch the catalogue');
    expect(job.resourcesOnly, isTrue);
  });

  test('cartridge compatibility follows only the current exact cached edition',
      () async {
    final id = await seed(1, platform: 'gbc');
    await seed(2, platform: 'gbc');
    final edition = (await store.edition(id))!;
    final evidence = IdentityEvidence(
        source: 'driveLocalArchive',
        kind: 'rawRomIdentifier',
        value: jsonEncode({
          'kind': 'rawRom',
          'filename': 'Actual member.gbc',
          'sizeBytes': 32768,
          'md5': '0123456789abcdef0123456789abcdef',
          'gbcDualMode': 'no'
        }));
    await store.putEdition(EditionIdentity.fromJson({
      ...edition.toJson(),
      'evidence': [
        ...edition.evidence.map((e) => e.toJson()),
        evidence.toJson()
      ]
    }));
    final detail = await query.cachedMetadata('Game 1.7z', 'gbc');
    expect(detail?.gbcDualMode, 'no');
    expect(
        detail
            ?.withArtwork(null, const [], supportTexture: 'file:///label.png')
            .gbcDualMode,
        'no');
    expect(
        (await query.cachedMetadata('Game 2.7z', 'gbc'))?.gbcDualMode, isNull);
    await store.putEdition(EditionIdentity.fromJson({
      ...edition.toJson(),
      'evidence': [
        evidence.toJson(),
        IdentityEvidence(
                source: 'catalogue',
                kind: 'artifactContent',
                value: 'replacement')
            .toJson()
      ]
    }));
    expect(
        (await query.cachedMetadata('Game 1.7z', 'gbc'))?.gbcDualMode, isNull);
  });

  test('policy rebuild batches projection writes per bounded edition page',
      () async {
    for (var n = 1; n <= 129; n++) {
      await seed(n);
    }
    await query.page(filter: LibraryQueryFilter(), assessedBases: [basis]);
    final observed = _ProjectionDatabase(db);
    final changedPolicy = AssessedOverallScoreBasis(
        sourceId: basis.sourceId,
        kind: basis.kind,
        scaleMinimum: basis.scaleMinimum,
        scaleMaximum: basis.scaleMaximum,
        platformIds: basis.platformIds,
        minimumVoteCount: basis.minimumVoteCount,
        assessmentReference: 'new-assessed-policy');
    final page = await LibraryQuery(Future.value(observed)).page(
        filter: LibraryQueryFilter(limit: 128), assessedBases: [changedPolicy]);
    expect(page.collectionGames, 129);
    expect(page.totalMatches, 129);
    expect(page.items, hasLength(128));
    expect(page.provisional, isTrue);
    expect(await db.query('library_query_dirty'), isEmpty);
    expect(observed.batches, lessThanOrEqualTo(2),
        reason: '129 editions require two bounded write batches, not 129.');
    expect(observed.standaloneWrites, lessThanOrEqualTo(2),
        reason: 'Only policy invalidation writes cross the bridge separately.');
    expect(observed.catalogueReads, lessThanOrEqualTo(8),
        reason:
            'Exact catalogue checks must use bounded pages, not per-edition reads.');
  });

  test('batched catalogue bindings preserve exact single-identity rejection',
      () async {
    RemoteArtifact remote(int n,
            {String account = 'account', String version = '1'}) =>
        RemoteArtifact(
            id: RemoteArtifactId(
                providerId: 'drive',
                sourceId: 'source',
                accountId: account,
                providerFileId: '$n'),
            displayName: 'Game $n.7z',
            displayPath: 'Game $n.7z',
            sizeBytes: 5,
            version: version);
    final ids = <String>[];
    for (var n = 1; n <= 11; n++) {
      ids.add(await seed(n, artifact: n <= 4 || n == 11 ? null : remote(n)));
    }
    await store.putGame(
        GameIdentity(id: 'explicit', title: 'Explicit', platformId: 'psx'));
    await store.putEdition(
        EditionIdentity(id: 'explicit-edition', gameId: 'explicit'));
    final rows = await db.rawQuery('''SELECT e.edition_id,
      g.record_json AS game_json, e.record_json AS edition_json
      FROM library_editions e JOIN library_game_identities g ON g.game_id = e.game_id
      ORDER BY e.edition_id''');
    Map<String, Object?> rowFor(String id) =>
        rows.singleWhere((r) => r['edition_id'] == id);
    // Capture identities first, then change their current catalogue bindings.
    await db.delete('games', where: 'id = 2');
    await db.update('games', {'is_folder': 1}, where: 'id = 3');
    await db.update('games', {'systemSlug': 'snes'}, where: 'id = 4');
    await db.update('games',
        {'remote_artifact': jsonEncode(remote(6, version: '2').toJson())},
        where: 'id = 6');
    await db.update('games',
        {'remote_artifact': jsonEncode(remote(7, account: 'other').toJson())},
        where: 'id = 7');
    await db.update('games', {'remote_artifact': null}, where: 'id = 8');
    await db.update('games', {'artifact_key': 'other-key'}, where: 'id = 9');
    await db.insert('games', {
      'id': 20,
      'systemSlug': 'psx',
      'displayName': 'Duplicate',
      'artifact_key': remote(10).id.key,
      'remote_artifact': jsonEncode(remote(10).toJson())
    });
    await db.update('games', {'artifact_key': 'now-an-artifact'},
        where: 'id = 11');
    final captured = <Map<String, Object?>>[...rows];
    final expected = <String, bool>{
      for (var n = 1; n <= 11; n++) ids[n - 1]: n == 1 || n == 5,
      'explicit-edition': true
    };
    void altered(String id,
        {List<IdentityEvidence>? gameEvidence,
        List<IdentityEvidence>? editionEvidence}) {
      final original = rowFor(ids[4]);
      final game =
          GameIdentity.fromJson(jsonDecode(original['game_json'] as String));
      final edition = EditionIdentity.fromJson(
          jsonDecode(original['edition_json'] as String));
      captured.add({
        'game_json': jsonEncode({
          ...game.toJson(),
          if (gameEvidence != null)
            'evidence': gameEvidence.map((e) => e.toJson()).toList()
        }),
        'edition_json': jsonEncode({
          ...edition.toJson(),
          'id': id,
          if (editionEvidence != null)
            'evidence': editionEvidence.map((e) => e.toJson()).toList()
        })
      });
      expected[id] = false;
    }

    final game = GameIdentity.fromJson(
        jsonDecode(rowFor(ids[4])['game_json'] as String));
    final edition = EditionIdentity.fromJson(
        jsonDecode(rowFor(ids[4])['edition_json'] as String));
    altered('multiple-keys', gameEvidence: [
      ...game.evidence,
      IdentityEvidence(
          source: 'catalogue', kind: 'artifactIdentity', value: 'other')
    ]);
    altered('multiple-systems', gameEvidence: [
      ...game.evidence,
      IdentityEvidence(source: 'catalogue', kind: 'system', value: 'snes')
    ]);
    altered('missing-marker',
        editionEvidence: edition.evidence
            .where((e) => e.kind != 'artifactContent')
            .toList());
    altered('multiple-markers', editionEvidence: [
      ...edition.evidence,
      IdentityEvidence(
          source: 'catalogue', kind: 'artifactContent', value: 'other')
    ]);
    altered('invalid-legacy', gameEvidence: [
      IdentityEvidence(source: 'catalogue', kind: 'system', value: 'psx'),
      IdentityEvidence(
          source: 'catalogue',
          kind: 'artifactIdentity',
          value: 'legacy-cache-row:invalid')
    ]);
    final bindings = await db.transaction((txn) async {
      final result = await LibraryStore.readCatalogueBindings(txn, captured);
      for (final row in captured) {
        final id =
            EditionIdentity.fromJson(jsonDecode(row['edition_json'] as String))
                .id;
        expect(result[id]!.current, expected[id], reason: id);
        expect(result[id]!.current,
            await LibraryStore.isCurrentCatalogueIdentity(txn, row),
            reason: id);
      }
      return result;
    });
    expect(bindings[ids[4]]!.cacheRow, {'id': 5, 'displayName': 'Game 5'});
    expect(bindings[ids[5]]!.cacheRow, {'id': 6, 'displayName': 'Game 6'},
        reason:
            'A changed byte binding retains its display title, not its score.');
    expect(bindings[ids[9]]!.cacheRow, isNull);
    expect(bindings['explicit-edition']!.cacheRow, isNull);
    await expectLater(
        LibraryStore.readCatalogueBindings(
            db, List.filled(129, captured.first)),
        throwsArgumentError);
    await expectLater(
        LibraryStore.readCatalogueBindings(
            db, [captured.first, captured.first]),
        throwsArgumentError);
    expect(await LibraryStore.readCatalogueBindings(db, []), isEmpty);
  });

  test('bounded binding production SQL uses exact legacy and artifact indexes',
      () async {
    await db.execute('CREATE UNIQUE INDEX idx_games_system_artifact ON games '
        '(systemSlug, artifact_key) WHERE artifact_key IS NOT NULL');
    await seed(1);
    await seed(2,
        artifact: RemoteArtifact(
            id: RemoteArtifactId(
                providerId: 'drive',
                sourceId: 'source',
                accountId: 'account',
                providerFileId: 'file'),
            displayName: 'Game 2.7z',
            displayPath: 'Game 2.7z',
            version: '1'));
    final identities = await db.rawQuery('''SELECT g.record_json AS game_json,
      e.record_json AS edition_json FROM library_editions e
      JOIN library_game_identities g ON g.game_id = e.game_id''');
    final observed = _ProjectionDatabase(db);
    final bindings = await observed.transaction(
        (txn) => LibraryStore.readCatalogueBindings(txn, identities));
    expect(bindings.values.map((b) => b.current), everyElement(isTrue));
    expect(observed.catalogueReads, 2);
    final plans = <String>[];
    for (final request in observed.catalogueQueries) {
      final rows =
          await db.rawQuery('EXPLAIN QUERY PLAN ${request.sql}', request.args);
      plans.add(rows.map((r) => r['detail']).join('\n'));
    }
    expect(plans, hasLength(2));
    expect(plans[0], contains('SEARCH g USING INTEGER PRIMARY KEY'));
    expect(
        plans[1], contains('SEARCH g USING INDEX idx_games_system_artifact'));
    expect(plans.join('\n'), isNot(contains('SCAN g')));
  });

  test('failed projection page preserves the previous complete snapshot',
      () async {
    for (var n = 1; n <= 129; n++) {
      await seed(n);
    }
    await read();
    final snapshot = <String, List<Map<String, Object?>>>{};
    for (final table in [
      'library_query_policy',
      'library_query_editions',
      'library_query_facets',
      'library_query_dirty'
    ]) {
      snapshot[table] = await db.query(table);
    }
    // Edition IDs are hashes, not insertion order. Target the actual second
    // page, so this regression proves rollback of an already-written first page.
    final secondPageCacheRow = (await db.rawQuery('''SELECT cache_row_id
      FROM library_query_editions ORDER BY edition_id LIMIT 1 OFFSET 128'''))
        .single['cache_row_id'] as int;
    await db.execute('''CREATE TRIGGER projection_failure
      BEFORE INSERT ON library_query_editions
      WHEN NEW.cache_row_id = $secondPageCacheRow
      BEGIN SELECT RAISE(ABORT, 'synthetic_projection_failure'); END''');
    final changedPolicy = AssessedOverallScoreBasis(
        sourceId: basis.sourceId,
        kind: basis.kind,
        scaleMinimum: basis.scaleMinimum,
        scaleMaximum: basis.scaleMaximum,
        platformIds: basis.platformIds,
        minimumVoteCount: basis.minimumVoteCount,
        assessmentReference: 'new-assessed-policy');
    await expectLater(
        query
            .page(filter: LibraryQueryFilter(), assessedBases: [changedPolicy]),
        throwsA(isA<DatabaseException>()));
    for (final entry in snapshot.entries) {
      expect(await db.query(entry.key), entry.value, reason: entry.key);
    }
    await db.execute('DROP TRIGGER projection_failure');
    expect(
        (await query.page(
                filter: LibraryQueryFilter(), assessedBases: [changedPolicy]))
            .collectionGames,
        129);
    expect(await db.query('library_query_dirty'), isEmpty);
  });

  test('retention keeps an unscored member of a ranked canonical game',
      () async {
    for (var n = 1; n <= 26; n++) {
      await seed(n, score: n.toDouble());
    }
    final extraDisc = await seed(90, group: '26');
    final page =
        await query.retentionPage(platformId: 'psx', assessedBases: [basis]);
    expect(page.collectionGames, 26);
    expect(page.rankedGames, 26);
    expect(page.provisional, isFalse);
    expect(page.totalMembers, 27);
    final member = page.members.singleWhere((m) => m.editionId == extraDisc);
    expect(member.canonicalRank, 1);
    expect(page.disposition(member).name, 'keep');
    final last = page.members.singleWhere((m) => m.cacheRowId == 1);
    expect(last.canonicalRank, 26);
    expect(page.disposition(last).name, 'outsideSample');
  });

  test('exact artifact retention shares current canonical ranking and coverage',
      () async {
    RemoteArtifact remote(int n,
            {String source = 'source', String version = '1'}) =>
        RemoteArtifact(
            id: RemoteArtifactId(
                providerId: 'drive',
                sourceId: source,
                accountId: 'account',
                providerFileId: '$n'),
            displayName: 'Game $n.7z',
            displayPath: 'Game $n.7z',
            version: version,
            sizeBytes: 5,
            canDownload: true);
    for (var n = 1; n <= 26; n++) {
      await seed(n, score: n.toDouble(), artifact: remote(n));
    }
    final page = await query.retentionForArtifact(
        platformId: 'psx', artifact: remote(1), assessedBases: [basis]);
    expect(page.collectionGames, 26);
    expect(page.rankedGames, 26);
    expect(page.totalMembers, 26);
    expect(page.members.single.cacheRowId, 1);
    expect(page.members.single.canonicalRank, 26);
    expect(page.disposition(page.members.single).name, 'outsideSample');
    for (final mismatch in [
      remote(1, version: '2'),
      remote(1, source: 'other')
    ]) {
      final unmatched = await query.retentionForArtifact(
          platformId: 'psx', artifact: mismatch, assessedBases: [basis]);
      expect(unmatched.members, isEmpty);
    }
    final otherPlatform = await query.retentionForArtifact(
        platformId: 'snes', artifact: remote(1), assessedBases: [basis]);
    expect(otherPlatform.members, isEmpty);
    await seed(27, artifact: remote(27));
    final provisional = await query.retentionForArtifact(
        platformId: 'psx', artifact: remote(1), assessedBases: [basis]);
    expect(provisional.provisional, isTrue);
    expect(provisional.disposition(provisional.members.single).name,
        'outsideSample');
  });

  test('exact artifact review rejects namesakes and duplicate bindings',
      () async {
    final artifact = RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: 'source',
            accountId: 'account',
            providerFileId: 'file'),
        displayName: 'Game 1.7z',
        displayPath: 'Game 1.7z',
        version: '1');
    await seed(1, score: 91);
    expect(
        (await query.retentionForArtifact(
                platformId: 'psx', artifact: artifact, assessedBases: [basis]))
            .members,
        isEmpty,
        reason: 'A legacy filename is not a remote identity.');
    await seed(2, score: 82, artifact: artifact);
    expect(
        (await query.retentionForArtifact(
                platformId: 'psx', artifact: artifact, assessedBases: [basis]))
            .members
            .single
            .cacheRowId,
        2);
    await seed(3, score: 82, artifact: artifact);
    expect(
        (await query.retentionForArtifact(
                platformId: 'psx', artifact: artifact, assessedBases: [basis]))
            .members,
        isEmpty);
  });

  test(
      'retention permits unrated cloud-only candidates without inventing ranks',
      () async {
    for (var n = 1; n <= 26; n++) {
      await seed(n, score: n.toDouble());
    }
    await seed(27);
    final page =
        await query.retentionPage(platformId: 'psx', assessedBases: [basis]);
    expect(page.provisional, isTrue);
    expect(page.collectionGames, 27);
    expect(page.rankedGames, 26);
    expect(
        page
            .disposition(page.members.singleWhere((m) => m.cacheRowId == 1))
            .name,
        'outsideSample');
    final unresolved = page.members.singleWhere((m) => m.cacheRowId == 27);
    expect(unresolved.canonicalRank, isNull);
    expect(page.disposition(unresolved).name, 'outsideSample');
    final retained = page.members.singleWhere((m) => m.cacheRowId == 26);
    expect(retained.canonicalRank, 1);
    expect(page.disposition(retained).name, 'keep');
  });

  test(
      'retention ranks one console with bounded pages and stable canonical ties',
      () async {
    await seed(1, score: 80);
    await seed(2, score: 80);
    await seed(3, score: 99, platform: 'snes');
    final first = await query
        .retentionPage(platformId: 'psx', limit: 1, assessedBases: [basis]);
    final second = await query.retentionPage(
        platformId: 'psx', limit: 1, offset: 1, assessedBases: [basis]);
    expect(first.collectionGames, 2);
    expect(first.totalMembers, 2);
    expect(first.members.length, 1);
    expect(second.members.length, 1);
    expect(first.members.single.canonicalRank, 1);
    expect(second.members.single.canonicalRank, 2);
    expect(
        first.members.single.groupKey.compareTo(second.members.single.groupKey),
        lessThan(0));
    final empty = await query
        .retentionPage(platformId: 'psx', offset: 2, assessedBases: [basis]);
    expect(empty.members, isEmpty);
    expect(empty.totalMembers, 2);
    expect(empty.collectionGames, 2);
  });

  test(
      'retention leaves conflicting and low-vote scores unranked but cloud-only',
      () async {
    await seed(1, group: 'same', score: 70);
    await seed(2, group: 'same', score: 90);
    await seed(3, score: 100, votes: 1);
    final page =
        await query.retentionPage(platformId: 'psx', assessedBases: [basis]);
    expect(page.collectionGames, 2);
    expect(page.rankedGames, 0);
    expect(page.provisional, isTrue);
    expect(page.members.every((m) => m.canonicalRank == null), isTrue);
    expect(
        page.members.every((m) => page.disposition(m).name == 'outsideSample'),
        isTrue);
  });

  test('retention rejects invalid scope and unbounded page requests', () async {
    for (final values in [
      {'platformId': '', 'limit': 128, 'offset': 0},
      {'platformId': 'psx', 'limit': 129, 'offset': 0},
      {'platformId': 'psx', 'limit': 0, 'offset': 0},
      {'platformId': 'psx', 'limit': 128, 'offset': -1},
    ]) {
      await expectLater(
          query.retentionPage(
              platformId: values['platformId'] as String,
              limit: values['limit'] as int,
              offset: values['offset'] as int),
          throwsArgumentError);
    }
  });

  test(
      'retention cannot claim complete coverage when an artifact binding conflicts',
      () async {
    final editionId = await seed(1, score: 90);
    final edition = (await store.edition(editionId))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'platformId': 'snes',
    }));
    final page =
        await query.retentionPage(platformId: 'psx', assessedBases: [basis]);
    expect(page.members, isEmpty);
    expect(page.collectionGames, 0);
    expect(page.unboundArtifacts, 1);
    expect(page.provisional, isTrue);
  });

  test('retention recomputes after pending refresh and removed membership',
      () async {
    await seed(1, score: 90);
    var page =
        await query.retentionPage(platformId: 'psx', assessedBases: [basis]);
    expect(page.provisional, isFalse);
    expect(page.disposition(page.members.single),
        LibraryRetentionDisposition.keep);
    await MetadataRefreshJobs(Future.value(db))
        .createFromCatalogue(providerId: 'igdb');
    page = await query.retentionPage(platformId: 'psx', assessedBases: [basis]);
    expect(page.rankedGames, 0);
    expect(page.provisional, isTrue);
    expect(page.disposition(page.members.single),
        LibraryRetentionDisposition.outsideSample);
    await db.delete('games', where: 'id = 1');
    page = await query.retentionPage(platformId: 'psx', assessedBases: [basis]);
    expect(page.members, isEmpty);
    expect(page.totalMembers, 0);
    expect(page.unboundArtifacts, 0);
  });

  test('unbound identity does not veto other exact cloud-only candidates',
      () async {
    await seed(1, score: 90);
    final unrated = await seed(2);
    final uncertain = await seed(3);
    final edition = (await store.edition(uncertain))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'platformId': 'snes',
    }));
    final page =
        await query.retentionPage(platformId: 'psx', assessedBases: [basis]);
    expect(page.unboundArtifacts, 1);
    expect(page.members.any((m) => m.editionId == uncertain), isFalse);
    expect(page.disposition(page.members.singleWhere((m) => m.cacheRowId == 1)),
        LibraryRetentionDisposition.keep);
    final candidate = page.members.singleWhere((m) => m.editionId == unrated);
    expect(candidate.canonicalRank, isNull);
    expect(
        page.disposition(candidate), LibraryRetentionDisposition.outsideSample);
    expect(
        () => page.disposition(LibraryRetentionMember(
            editionId: uncertain,
            gameId: game.id,
            groupKey: 'uncertain',
            cacheRowId: 3,
            canonicalRank: null)),
        throwsArgumentError);
  });

  test('cache UPSERT coalesces invalidations without rolling back refresh',
      () async {
    final id = await seed(1, score: 82);
    await read(); // Bind the cache row and consume its initial invalidations.
    for (final title in ['Renamed', 'Renamed again']) {
      await db.rawInsert('''INSERT INTO games
        (id, systemSlug, filename, displayName) VALUES (1, 'psx', 'Game 1.7z', ?)
        ON CONFLICT(id) DO UPDATE SET displayName = excluded.displayName''',
          [title]);
      expect((await db.query('games')).single['displayName'], title);
      expect(await db.query('library_query_cache_dirty'), [
        {'cache_row_id': 1}
      ]);
      expect(await db.query('library_query_dirty'), [
        {'edition_id': id}
      ]);
    }
    // An outer conflict policy also overrides OR IGNORE in edition triggers.
    await db.rawUpdate('''UPDATE OR ABORT library_editions SET
      record_json = record_json WHERE edition_id = ?''', [id]);
    expect(await db.query('library_query_dirty'), [
      {'edition_id': id}
    ]);
    final result = await read();
    expect(result.items.single.editionId, id);
    expect(result.items.single.score!.rating.normalizedValue, 82);
    expect(await db.query('library_query_dirty'), isEmpty);
    expect(await db.query('library_query_cache_dirty'), isEmpty);
  });

  test('normal details use the selected cached score, not a legacy average',
      () async {
    await seed(1, score: 82);
    await db.execute('''CREATE TABLE game_metadata(filename TEXT,
      system_slug TEXT, rating REAL, last_updated INTEGER)''');
    await db.insert('game_metadata', {
      'filename': 'Game 1.7z',
      'system_slug': 'psx',
      'rating': 99.0,
      'last_updated': 0,
    });
    final detail = await _CacheDatabase(db).getGameMetadata('Game 1.7z', 'psx');
    expect(detail?.rating, 82);
    final cover = (await query.cachedRatings([1]))[1];
    expect(detail?.overallRating?.rating.toJson(), cover?.rating.toJson());
    expect(detail?.editionId, isNotNull);
    expect(detail?.contentTags, {'official'});
  });

  test(
      'details retain exact independent tags and never borrow an unrated sibling score',
      () async {
    await seed(1, score: 93, group: 'same-game');
    await seed(2, group: 'same-game', tags: {'T-Eng', 'Undub', 'Uncensor'});
    final selected = await query.cachedMetadata('Game 2.7z', 'psx');
    expect(selected?.overallRating, isNull);
    expect(selected?.rating, isNull);
    expect(selected?.contentTags, {'T-Eng', 'Undub', 'Uncensor'});
    await seed(3, tags: {'Official', 'Hack'});
    expect((await query.cachedMetadata('Game 3.7z', 'psx'))?.contentTags,
        {'Hack', 'unknown'});
  });

  test('details separate consoles and reject duplicate selection bindings',
      () async {
    await seed(1, score: 82);
    await seed(2, score: 70, platform: 'ps2');
    await db.update('games', {'filename': 'Game 1.7z'}, where: 'id = 2');
    expect((await query.cachedMetadata('Game 1.7z', 'psx'))?.rating, 82);
    expect((await query.cachedMetadata('Game 1.7z', 'ps2'))?.rating, 70);
    await db.insert('games', {
      'id': 3,
      'systemSlug': 'psx',
      'displayName': 'Other',
      'filename': 'Game 1.7z'
    });
    final ambiguous = await query.cachedMetadata('Game 1.7z', 'psx');
    expect(ambiguous, isNotNull);
    expect(ambiguous?.editionId, isNull);
    expect(ambiguous?.rating, isNull);
    expect(ambiguous?.overallRating, isNull);
  });

  test('unresolved current details never promote anonymous legacy metadata',
      () async {
    await seed(1);
    await db.execute('''CREATE TABLE game_metadata(filename TEXT,
      system_slug TEXT, rating REAL, last_updated INTEGER)''');
    await db.insert('game_metadata', {
      'filename': 'Game 1.7z',
      'system_slug': 'psx',
      'rating': 99,
      'last_updated': 0
    });
    final database = _CacheDatabase(db);
    final selected = await database.getGameMetadata('Game 1.7z', 'psx');
    expect(selected?.cacheRowId, 1);
    expect(selected?.rating, isNull);
    expect(selected?.hasContent, true);
    expect(await database.getGameMetadata('artifact:missing', 'psx'), isNull);
  });

  test(
      'detail field provenance and requested language survive cached projection',
      () async {
    final id = await seed(1, score: 82);
    final current = (await store.metadata(id, 'igdb'))!;
    await store.putMetadata(MetadataRecord.fromJson({
      ...current.toJson(),
      'descriptions': [
        const MetadataText(text: 'English', language: 'en').toJson(),
        const MetadataText(text: 'Español', language: 'es').toJson()
      ],
      'releaseDates': [
        const MetadataText(text: '1997-01-31', region: 'jp').toJson(),
        const MetadataText(text: '1998-02-03', region: 'us').toJson()
      ],
      'fieldProvenance': {
        'description': MetadataFieldProvenance(
                providerId: 'igdb',
                providerGameId: '1',
                field: 'description',
                retrievedAt: at)
            .toJson()
      }
    }));
    final selected =
        await query.cachedMetadata('Game 1.7z', 'psx', language: 'es');
    expect(selected?.summary, 'Español');
    expect(selected?.releaseDate, '1998-02-03',
        reason: 'Release region is independent of the selected UI language');
    expect(selected?.provenance['description']?.providerId, 'igdb');
    expect(selected?.providerMatches, {'igdb': 'verifiedProviderIdGlobalGame'});
    await MetadataRefreshJobs(Future.value(db))
        .createFromCatalogue(providerId: 'igdb');
    expect(
        (await query.cachedMetadata('Game 1.7z', 'psx'))?.overallRating?.fresh,
        false);
  });

  test(
      'console Top and tags use production scores and persist without a scrape',
      () async {
    final games = <GameItem>[];
    for (var i = 1; i <= 12; i++) {
      final id = await seed(i,
          score: 100 - i.toDouble(),
          tags: i == 1 || i == 12 ? {'Hack'} : {'official'});
      final metadata = (await store.metadata(id, 'igdb'))!;
      await store.putMetadata(MetadataRecord.fromJson({
        ...metadata.toJson(),
        'ratings': metadata.ratings
            .map((r) =>
                {...r.toJson(), 'kind': RatingKind.communityAggregate.name})
            .toList()
      }));
      games.add(GameItem(
          filename: 'Game $i.7z',
          displayName: 'Game $i',
          url: 'https://example.invalid/$i'));
    }
    final storage = _FreshFilterStorage();
    final system =
        SystemModel.supportedSystems.firstWhere((s) => s.id == 'psx');
    final config = SystemConfig(
        id: system.id,
        name: system.name,
        targetFolder: '/nonexistent/psx',
        providers: [
          const ProviderConfig(
              type: ProviderType.web,
              url: 'https://example.invalid/',
              priority: 1)
        ]);
    GameListController create() => GameListController(
        system: system,
        targetFolder: config.targetFolder,
        systemConfig: config,
        databaseService: _ConsoleCacheDatabase(db, games),
        storage: storage,
        installedFilenames: {'Game 1.7z'});
    var controller = create();
    try {
      await waitUntilLoaded(controller);
      await controller.loadDiscoveryGenres();
      expect(controller.state.availableGenres, ['action']);
      controller.setTopFilter(10);
      controller.toggleTagFilter('Hack');
      await controller.discoverySettled;
      expect(controller.state.filteredGroups, hasLength(1));
      final key = controller.state.filteredGroups.single;
      expect(controller.state.filteredGroupedGames[key]!.single.filename,
          'Game 1.7z');
      expect(controller.state.installedCache[key], isTrue);
      expect(controller.state.discovery!.collectionGames, 12);
      expect(controller.state.discovery!.rankedGames, 12);
      await storage.setFavorites(['Game 12.7z']);
      controller.toggleFavoritesFilter();
      await controller.discoverySettled;
      expect(controller.state.filteredGroups, isEmpty,
          reason: 'Favorites cannot promote the rank-12 hack into Top 10');
      controller.toggleFavoritesFilter();
      await controller.discoverySettled;
      var changedDuringPublication = false;
      void changeFromListener() {
        if (!changedDuringPublication &&
            controller.state.discovery != null &&
            !controller.state.queryingDiscovery) {
          changedDuringPublication = true;
          controller.toggleGenreFilter('action');
        }
      }

      controller.addListener(changeFromListener);
      controller.refreshDiscovery();
      await controller.discoverySettled;
      controller.removeListener(changeFromListener);
      expect(controller.state.queryingDiscovery, isFalse,
          reason:
              'A publication listener may request a newer filter generation');
      expect(controller.state.filteredGroups, hasLength(1));
      controller.dispose();
      controller = create();
      await waitUntilLoaded(controller);
      await controller.discoverySettled;
      expect(controller.state.activeFilters.top, 10);
      expect(controller.state.activeFilters.selectedTags, {'Hack'});
      expect(controller.state.filteredGroups, hasLength(1));
      controller.clearFilters();
      await controller.discoverySettled;
      expect(controller.state.filteredGroups, hasLength(12));
      expect(await db.query('library_query_views'), isEmpty);
    } finally {
      controller.dispose();
    }
  });

  for (final operation in ['details', 'ratings', 'covers']) {
    test('exact $operation reads leave unrelated projection work pending',
        () async {
      await seed(1, score: 91);
      final unrelated = await seed(2, score: 73, platform: 'snes');
      final before = await db.query('library_query_dirty',
          where: 'edition_id = ?', whereArgs: [unrelated]);
      expect(before, isNotEmpty);
      switch (operation) {
        case 'details':
          expect(
              (await query.cachedMetadata('Game 1.7z', 'psx'))?.cacheRowId, 1);
        case 'ratings':
          expect(
              (await query.cachedRatings([1], assessedBases: [basis]))[1]
                  ?.rating
                  .normalizedValue,
              91);
        case 'covers':
          final cache = MetadataArtworkCache(
              Future.value(db), Directory('D:/Temp/rshop-unused-artwork'));
          expect(await query.cachedCovers([1], cache), {1: null});
      }
      expect(
          await db.query('library_query_dirty',
              where: 'edition_id = ?', whereArgs: [unrelated]),
          before,
          reason: 'Reading a card must not rebuild unrelated rankings.');
      expect(
          await db.query('library_query_cache_dirty',
              where: 'cache_row_id = ?', whereArgs: [2]),
          isNotEmpty);
      expect(
          await db.query('library_query_editions',
              where: 'cache_row_id = ?', whereArgs: [2]),
          isEmpty);
      // Collection queries still consume all pending work and preserve ranking.
      expect((await read()).collectionGames, 2);
      expect(await db.query('library_query_cache_dirty'), isEmpty);
      expect(await db.query('library_query_dirty'), isEmpty);
    });
  }

  test('card score pages preserve each exact cached edition, not group winners',
      () async {
    final first = await seed(1, score: 91, group: 'same-game');
    final second = await seed(2, score: 91, group: 'same-game');
    await seed(3);
    final cards =
        await query.cachedRatings([1, 2, 3, 999], assessedBases: [basis]);
    expect(cards.keys, [1, 2, 3, 999]);
    final selected =
        await store.effectiveRatings([first, second], assessedBases: [basis]);
    expect(cards[1]!.rating.toJson(), selected[first]!.rating.toJson());
    expect(cards[2]!.rating.toJson(), selected[second]!.rating.toJson());
    expect(cards[3], isNull);
    expect(cards[999], isNull);
    expect((await read()).items, hasLength(2),
        reason:
            'Discovery groups canonical games; card scores retain editions.');
    await db.delete('games', where: 'id = 2');
    expect((await query.cachedRatings([2], assessedBases: [basis]))[2], isNull);
    await expectLater(query.cachedRatings(List.generate(129, (i) => i + 1)),
        throwsArgumentError);
  });

  test(
      'shared cover provider separates consoles and refreshes cached publication',
      () async {
    final first = await seed(1, score: 91);
    await seed(2, score: 70, platform: 'snes');
    await seed(3);
    await db.update('games', {'filename': 'Same.7z'}, where: 'id IN (1, 2)');
    final container = ProviderContainer(overrides: [
      libraryDbProvider.overrideWithValue(_CacheDatabase(db)),
      sharedMetadataStoreProvider.overrideWithValue(Future.value(null)),
    ]);
    final all = container.listen(cachedCoverRatingsProvider(''), (_, __) {});
    final system =
        container.listen(cachedCoverRatingsProvider('psx'), (_, __) {});
    try {
      final scores =
          await container.read(cachedCoverRatingsProvider('').future);
      final local =
          await container.read(cachedCoverRatingsProvider('psx').future);
      final psx = coverRatingKey('psx', 'Same.7z');
      final snes = coverRatingKey('snes', 'Same.7z');
      expect(scores[psx]!.rating.normalizedValue, 91);
      expect(scores[snes]!.rating.normalizedValue, 70);
      expect(local.containsKey(snes), isFalse);
      expect(local[coverRatingKey('psx', 'Game 3.7z')], isNull);
      expect(
          identical(await container.read(cachedCoverRatingsProvider('').future),
              scores),
          isTrue,
          reason:
              'Card rebuilds/scrolling reuse the same map, not database reads.');
      final cached = (await store.metadata(first, 'igdb'))!;
      await store.putMetadata(MetadataRecord.fromJson({
        ...cached.toJson(),
        'ratings':
            cached.ratings.map((r) => {...r.toJson(), 'rawValue': 88}).toList()
      }));
      container.read(gameDbChangedProvider.notifier).state++;
      final refreshed =
          await container.read(cachedCoverRatingsProvider('').future);
      expect(refreshed[psx]!.rating.normalizedValue, 88);
      expect(refreshed[snes]!.rating.normalizedValue, 70);
    } finally {
      all.close();
      system.close();
      container.dispose();
    }
  });

  test('production display and Top share supported community score, not total',
      () async {
    final supported = await seed(1, score: 70);
    final small = await seed(2, score: 100, tags: {'Hack'});
    await seed(3);
    for (final (id, value, votes) in [(supported, 90, 20), (small, 99, 2)]) {
      final cached = (await store.metadata(id, 'igdb'))!;
      await store.putMetadata(MetadataRecord.fromJson({
        ...cached.toJson(),
        'ratings': [
          ...cached.ratings.map((r) => r.toJson()),
          SourcedRating.parse(
                  sourceId: 'igdb',
                  sourceLabel: 'IGDB users',
                  providerGameId: cached.providerGameId,
                  rawValue: value,
                  scaleMinimum: 0,
                  scaleMaximum: 100,
                  voteCount: votes,
                  kind: RatingKind.communityAggregate,
                  retrievedAt: at)!
              .toJson()
        ]
      }));
    }
    final page = await query.page(filter: LibraryQueryFilter(top: 25));
    expect(page.collectionGames, 3);
    expect(page.rankedGames, 1);
    expect(page.provisional, isTrue);
    expect(page.items.single.editionId, supported);
    final selected = (await store.effectiveRatings([supported, small]));
    expect(page.items.single.score!.rating.toJson(),
        selected[supported]!.rating.toJson());
    expect(selected[supported]!.rating.normalizedValue, 90);
    expect(selected[supported]!.rating.kind, RatingKind.communityAggregate);
    expect(selected[small]!.rating.normalizedValue, 99);
    expect(selected[small]!.rankingEligible, isFalse);
    expect(
        (await query.page(filter: LibraryQueryFilter(top: 25, tags: {'Hack'})))
            .items,
        isEmpty,
        reason:
            'A low-support hack cannot fill an eligible ordinary-game Top.');
    // The same current projection is invalidated by a support-count change;
    // no new scrape or provider request is needed for the read.
    final cached = (await store.metadata(supported, 'igdb'))!;
    await store.putMetadata(MetadataRecord.fromJson({
      ...cached.toJson(),
      'ratings': cached.ratings
          .map((r) => {
                ...r.toJson(),
                if (r.kind == RatingKind.communityAggregate) 'voteCount': 19,
              })
          .toList(),
    }));
    final revised = await query.page(filter: LibraryQueryFilter(top: 25));
    expect(revised.rankedGames, 0);
    expect(revised.items, isEmpty);
  });

  test('S7 assessed scope refresh ranks cached records without rescraping',
      () async {
    for (final (n, platform, votes) in [
      (1, 'nes', 20),
      (2, 'nes', 19),
      (3, 'snes', 20),
      (4, 'snes', 19),
      (5, 'wii', 20),
      (6, 'wii', 19),
      (7, 'wiiu', 20),
      (8, 'wiiu', 19),
    ]) {
      final id = await seed(n, platform: platform, score: 99);
      final cached = (await store.metadata(id, 'igdb'))!;
      await store.putMetadata(MetadataRecord.fromJson({
        ...cached.toJson(),
        'ratings': [
          ...cached.ratings.map((r) => r.toJson()),
          SourcedRating.parse(
                  sourceId: 'igdb',
                  sourceLabel: 'IGDB users',
                  providerGameId: cached.providerGameId,
                  rawValue: 80,
                  scaleMinimum: 0,
                  scaleMaximum: 100,
                  voteCount: votes,
                  kind: RatingKind.communityAggregate,
                  retrievedAt: at)!
              .toJson()
        ]
      }));
    }
    final basis = productionOverallScoreBases.single;
    final previousScope = AssessedOverallScoreBasis(
        sourceId: basis.sourceId,
        kind: basis.kind,
        scaleMinimum: basis.scaleMinimum,
        scaleMaximum: basis.scaleMaximum,
        platformIds:
            basis.platformIds.difference({'nes', 'snes', 'wii', 'wiiu'}),
        minimumVoteCount: basis.minimumVoteCount,
        assessmentReference: basis.assessmentReference);
    final before = await query.page(
        filter: LibraryQueryFilter(top: 25), assessedBases: [previousScope]);
    expect(before.rankedGames, 0);
    expect(before.items, isEmpty);
    final after = await query.page(filter: LibraryQueryFilter(top: 25));
    expect(after.collectionGames, 8);
    expect(after.rankedGames, 4);
    expect(after.provisional, isTrue);
    expect(after.items.map((item) => item.platformId).toSet(),
        {'nes', 'snes', 'wii', 'wiiu'});
    for (final item in after.items) {
      expect(item.score!.rating.normalizedValue, 80);
      expect(item.score!.rating.kind, RatingKind.communityAggregate);
      expect(item.score!.rating.voteCount, 20);
    }
    for (final platform in ['nes', 'snes', 'wii', 'wiiu']) {
      final retained = await query.retentionPage(platformId: platform);
      expect(retained.provisional, isTrue);
      for (final member in retained.members) {
        expect(
            retained.disposition(member),
            member.canonicalRank == null
                ? LibraryRetentionDisposition.outsideSample
                : LibraryRetentionDisposition.keep);
      }
    }
  });

  test('ranks collection before tag search view and genre intersections',
      () async {
    final first = await seed(1, score: 95);
    final second =
        await seed(2, score: 90, tags: {'T-Eng', 'Undub', 'Uncensor'});
    await seed(3, score: 80, tags: {'T-Eng'}, genres: ['Puzzle']);
    await query.replaceViewMembers('favorites', [second]);
    final top = await read(filter: LibraryQueryFilter(top: 2));
    expect(top.items.map((i) => i.editionId), [first, second]);
    final translations =
        await read(filter: LibraryQueryFilter(top: 2, tags: {'T-Eng'}));
    expect(translations.items.map((i) => i.editionId), [second]);
    expect(translations.items.single.rank, 2);
    expect(
        (await read(filter: LibraryQueryFilter(top: 2, genres: {'Puzzle'})))
            .items,
        isEmpty);
    expect(
        (await read(filter: LibraryQueryFilter(top: 2, search: 'Game 3')))
            .items,
        isEmpty);
    expect(
        (await read(filter: LibraryQueryFilter(top: 2, viewIds: {'favorites'})))
            .items
            .single
            .rank,
        2);
    expect(translations.collectionGames, 3);
    expect(translations.rankedGames, 3);
    expect(translations.provisional, isFalse);
  });

  test(
      'tag aliases use the same cached query while unfamiliar tags stay unknown',
      () async {
    final official = await seed(1, score: 90, tags: {'OFFICIAL'});
    final modified = await seed(2, tags: {'dubbed', 'UNDUBBED', 'uncensored'});
    final unfamiliar =
        await seed(3, score: 99, tags: {'Translation', 'PEGI 18'});
    final conflicting = await seed(4, score: 98, tags: {'Official', 'Hack'});
    expect(
        (await read(filter: LibraryQueryFilter(tags: {'Official'})))
            .items
            .map((i) => i.editionId),
        [official],
        reason: 'Contradictory facts do not claim an official release.');
    expect(
        (await read(filter: LibraryQueryFilter(top: 1, tags: {' official '})))
            .items
            .map((i) => i.editionId),
        [official]);
    expect(
        (await read(
                filter: LibraryQueryFilter(
                    tags: {'Dubbed', 'undubbed', 'UNCENSORED'},
                    matchAllTags: true)))
            .items
            .map((i) => i.editionId),
        [modified]);
    final unresolved =
        await read(filter: LibraryQueryFilter(tags: {'Unknown'}));
    expect(unresolved.items.map((i) => i.editionId).toSet(),
        {unfamiliar, conflicting});
    expect(unresolved.items.map((i) => i.score), everyElement(isNull));
    expect(
        (await read(filter: LibraryQueryFilter(top: 1, tags: {'Unknown'})))
            .items,
        isEmpty);
    expect((await store.edition(unfamiliar))!.tags, {'Translation', 'PEGI 18'});
  });

  test('any/all tags are independent and AND other dimensions', () async {
    final a = await seed(1, score: 90, tags: {'T-Eng', 'Undub', 'Uncensor'});
    await seed(2,
        score: 85, tags: {'Undub'}, regions: ['Europe'], languages: ['fr']);
    await seed(3, score: 80);
    await seed(4); // Unknown is not official.
    expect(
        (await read(filter: LibraryQueryFilter(tags: {'T-Eng', 'Undub'})))
            .items,
        hasLength(2));
    expect(
        (await read(
                filter: LibraryQueryFilter(
                    tags: {'T-Eng', 'Undub', 'Uncensor'},
                    matchAllTags: true,
                    regions: {'USA'},
                    languages: {'en'})))
            .items
            .single
            .editionId,
        a);
    expect((await read(filter: LibraryQueryFilter(tags: {'unknown'}))).items,
        hasLength(0));
    final unknown = (await store.edition((await read()).items.last.editionId))!;
    await store.putEdition(
        EditionIdentity.fromJson({...unknown.toJson(), 'tags': []}));
    expect((await read(filter: LibraryQueryFilter(tags: {'unknown'}))).items,
        hasLength(1));
  });

  test('canonical region/disc grouping ties scope and exact score ownership',
      () async {
    await seed(1, score: 90, group: 'shared');
    await seed(2, score: 90, group: 'shared', regions: ['Europe']);
    await seed(3, score: 90, platform: 'snes');
    final hack = await seed(4, score: 80, tags: {'Hack'}, group: 'shared');
    final all = await read(filter: LibraryQueryFilter(top: 10));
    expect(all.collectionGames, 3);
    expect(all.items, hasLength(3));
    expect(all.items.last.editionId, hack);
    final system =
        await read(filter: LibraryQueryFilter(platformIds: {'psx'}, top: 10));
    expect(system.items, hasLength(2));
    expect(system.items.map((i) => i.groupKey),
        all.items.where((i) => i.platformId == 'psx').map((i) => i.groupKey));
    expect(
        (await read(filter: LibraryQueryFilter(top: 1, regions: {'Europe'})))
            .items
            .length,
        lessThanOrEqualTo(1));
    final repeat = await read(filter: LibraryQueryFilter(top: 10));
    expect(
        repeat.items.map((i) => i.groupKey), all.items.map((i) => i.groupKey));
    for (final item in all.items) {
      final score = (await store.effectiveRatings([item.editionId],
          assessedBases: [basis]))[item.editionId]!;
      expect(item.score!.rating.toJson(), score.rating.toJson());
    }
  });

  test(
      'collection categories intersect tags and Top without borrowing identity',
      () async {
    final official = await seed(1, score: 90, tags: {'official'});
    final translated = await seed(2, score: 80, tags: {'T-Eng'});
    await seed(3, tags: {'homebrew'});
    await seed(4, tags: {'demo'});
    final unknown = await seed(5, tags: {});
    expect(
        (await read(filter: LibraryQueryFilter(category: 'commercial')))
            .items
            .map((item) => item.editionId),
        [official]);
    expect(
        (await read(
                filter: LibraryQueryFilter(category: 'hacks', tags: {'T-Eng'})))
            .items
            .map((item) => item.editionId),
        [translated]);
    expect(
        (await read(filter: LibraryQueryFilter(category: 'hacks', top: 1)))
            .items,
        isEmpty);
    expect((await read()).items, hasLength(5),
        reason: 'All retains unknown, demo and homebrew');
    final edition = (await store.edition(unknown))!;
    final game = (await store.game(edition.gameId))!;
    final before = LibraryStore.metadataIdentity({
      'game_json': jsonEncode(game.toJson()),
      'edition_json': jsonEncode(edition.toJson())
    }, providerId: 'igdb');
    final located = EditionIdentity.fromJson(
        {...edition.toJson(), 'collectionCategory': 'commercial'});
    await store.putEdition(located);
    expect(
        LibraryStore.metadataIdentity({
          'game_json': jsonEncode(game.toJson()),
          'edition_json': jsonEncode(located.toJson())
        }, providerId: 'igdb'),
        before,
        reason:
            'Source layout category is not a ROM or metadata identity change');
    expect(
        (await read(filter: LibraryQueryFilter(category: 'commercial'))).items,
        hasLength(2));
    expect(located.tags, isEmpty,
        reason:
            'Commercial navigation must not invent an official-release fact');
  });

  test(
      'sparse coverage absent assessment and provider-only records stay honest',
      () async {
    await seed(1, score: 90);
    await seed(2);
    await seed(3, score: 100, votes: 2);
    await store.putGame(
        GameIdentity(id: 'outside', platformId: 'psx', title: 'Global'));
    await store.putEdition(EditionIdentity(
        id: 'outside-edition', gameId: 'outside', tags: {'official'}));
    final result = await read(filter: LibraryQueryFilter(top: 25));
    expect(result.items, hasLength(1));
    expect(result.collectionGames, 3);
    expect(result.rankedGames, 1);
    expect(result.provisional, isTrue);
    final unapproved = await query.page(filter: LibraryQueryFilter(top: 25));
    expect(unapproved.items, isEmpty);
    expect(unapproved.rankedGames, 0);
    expect(
        (await query.page(filter: LibraryQueryFilter())).items, hasLength(3));
  });

  test('pre-category projection rebuilds on normal query without a new scrape',
      () async {
    final edition = await seed(1, score: 90);
    await read();
    final facts = await db.query('library_metadata');
    // Exact fingerprint shape used by production before category facets existed.
    final oldFingerprint = sha256
        .convert(utf8.encode(jsonEncode([
          [
            basis.sourceId,
            basis.kind.name,
            basis.scaleMinimum,
            basis.scaleMaximum,
            basis.platformIds.toList()..sort(),
            basis.minimumVoteCount,
            basis.assessmentReference,
            basis.unknownCountAssessment
          ]
        ])))
        .toString();
    await db.update('library_query_policy', {'fingerprint': oldFingerprint});
    await db.delete('library_query_facets',
        where: 'dimension=?', whereArgs: ['category']);
    await db.delete('library_query_dirty');
    await db.delete('library_query_cache_dirty');
    final result =
        await read(filter: LibraryQueryFilter(category: 'commercial'));
    expect(result.items.map((item) => item.editionId), [edition]);
    expect(result.items.single.score!.rating.normalizedValue, 90);
    expect(await db.query('library_metadata'), facts);
    expect(await db.query('library_query_dirty'), isEmpty);
    expect(await db.query('library_query_cache_dirty'), isEmpty);
  });

  test('add remove score and pending refresh changes recompute without refills',
      () async {
    final a = await seed(1, score: 90);
    final b = await seed(2, score: 80);
    expect(
        (await read(filter: LibraryQueryFilter(top: 1))).items.single.editionId,
        a);
    await db.delete('games', where: 'id = 1');
    expect(
        (await read(filter: LibraryQueryFilter(top: 1))).items.single.editionId,
        b);
    final c = await seed(3, score: 95);
    expect(
        (await read(filter: LibraryQueryFilter(top: 1))).items.single.editionId,
        c);
    await MetadataRefreshJobs(Future.value(db)).create(
        providerId: 'igdb', collectionGeneration: 'next', editionIds: [c]);
    final after = await read(filter: LibraryQueryFilter(top: 1));
    expect(after.items.single.editionId, b);
    expect(after.rankedGames, 1);
    expect(after.provisional, isTrue);
    await db.update('library_metadata', {'identity_key': 'invalid'},
        where: 'edition_id = ?', whereArgs: [b]);
    expect((await read(filter: LibraryQueryFilter(top: 1))).items, isEmpty);
  });

  test('bounded pages manual view order and cache-only filter changes',
      () async {
    final a = await seed(1, score: 90);
    final b = await seed(2, score: 80);
    final c = await seed(3, score: 70);
    await query.replaceViewMembers('shelf:test', [c, a, b]);
    final first = await read(
        filter: LibraryQueryFilter(
            viewIds: {'shelf:test'}, manualViewId: 'shelf:test', limit: 2));
    expect(first.items.map((i) => i.editionId), [c, a]);
    expect(first.totalMatches, 3);
    final next = await read(
        filter: LibraryQueryFilter(
            viewIds: {'shelf:test'},
            manualViewId: 'shelf:test',
            limit: 2,
            offset: 2));
    expect(next.items.single.editionId, b);
    final snapshot = await db.query('library_query_editions');
    await read(filter: LibraryQueryFilter(tags: {'official'}, search: 'Game'));
    expect(await db.query('library_query_editions'), snapshot);
    await expectLater(
        read(filter: LibraryQueryFilter(limit: 129)), throwsArgumentError);
  });

  test('Top intersects manual shelf without silently selecting rating sort',
      () async {
    final a = await seed(1, score: 90);
    final b = await seed(2, score: 80);
    final c = await seed(3, score: 70);
    await query.replaceViewMembers('shelf:manual', [c, b, a]);
    final filter = LibraryQueryFilter(
        top: 2, viewIds: {'shelf:manual'}, manualViewId: 'shelf:manual');
    expect((await read(filter: filter)).items.map((i) => i.editionId), [b, a]);
    expect(
        (await read(
                filter: LibraryQueryFilter(
                    top: 2,
                    ratingOrder: true,
                    viewIds: {'shelf:manual'},
                    manualViewId: 'shelf:manual')))
            .items
            .map((i) => i.editionId),
        [a, b]);
  });

  test('discovery returns matching editions but counts and ranks games once',
      () async {
    final a = await seed(1, score: 90, group: 'same');
    final b = await seed(2, score: 90, group: 'same');
    await seed(3, score: 70);
    final page = await read(
        filter: LibraryQueryFilter(top: 1, includeVariants: true, limit: 1));
    final next = await read(
        filter: LibraryQueryFilter(
            top: 1, includeVariants: true, limit: 1, offset: 1));
    expect({page.items.single.editionId, next.items.single.editionId}, {a, b});
    expect(page.totalMatches, 1);
    expect(page.collectionGames, 2);
    expect(page.items.single.rank, 1);
    expect(next.items.single.rank, 1);
  });

  test(
      'shared UI discovery preserves exact variants and removes temporary view',
      () async {
    await seed(1, score: 90, group: 'same');
    await seed(2, score: 90, group: 'same');
    await seed(3, score: 70, tags: {'Hack'});
    await seed(4, score: 99, platform: 'snes');
    final keys = [
      for (var i = 1; i <= 3; i++) coverRatingKey('psx', 'Game $i.7z')
    ];
    final result = (await query.discover(
        filter: LibraryQueryFilter(platformIds: {'psx'}, top: 1),
        orderedKeys: keys,
        isCurrent: () => true,
        assessedBases: [basis]))!;
    expect(result.groups.values.single.toSet(), keys.take(2).toSet());
    expect(result.totalMatches, 1);
    expect(result.collectionGames, 2);
    expect(result.genres, ['action']);
    expect(await db.query('library_query_views'), isEmpty);
    final empty = (await query.discover(
        filter:
            LibraryQueryFilter(platformIds: {'psx'}, top: 1, tags: {'Hack'}),
        orderedKeys: keys,
        isCurrent: () => true,
        assessedBases: [basis]))!;
    expect(empty.groups, isEmpty,
        reason: 'No refill from the lower-ranked hack');
    expect(empty.collectionGames, 2);
    var calls = 0;
    expect(
        await query.discover(
            filter: LibraryQueryFilter(),
            orderedKeys: keys,
            isCurrent: () => ++calls < 2,
            assessedBases: [basis]),
        isNull);
    expect(await db.query('library_query_views'), isEmpty);
  });

  test(
      'featured ranking is a prefix, not a Top filter; remainder stays alphabetical',
      () async {
    await seed(1, score: 80);
    await seed(2, score: 95);
    await seed(3, score: 85);
    await seed(4, score: 90);
    await seed(5);
    final featured = await query.page(
        filter: LibraryQueryFilter(platformIds: {'psx'}, featuredTop: 2),
        assessedBases: [basis]);
    expect(featured.items.map((i) => i.cacheRowId).toList(), [2, 4, 1, 3, 5]);
    expect(featured.totalMatches, 5);
    final fewer = await query.page(
        filter: LibraryQueryFilter(platformIds: {'psx'}, featuredTop: 100),
        assessedBases: [basis]);
    expect(fewer.items.map((i) => i.cacheRowId).toList(), [2, 4, 3, 1, 5]);
    expect(fewer.rankedGames, 4);
    final keys = [
      for (var i = 1; i <= 5; i++) coverRatingKey('psx', 'Game $i.7z')
    ];
    final discovery = (await query.discover(
        filter: LibraryQueryFilter(platformIds: {'psx'}, featuredTop: 2),
        orderedKeys: keys,
        preserveOrder: true,
        isCurrent: () => true,
        assessedBases: [basis]))!;
    expect(discovery.groups.values.map((v) => v.first).toList(),
        [keys[1], keys[3], keys[0], keys[2], keys[4]]);
  });

  test(
      'UI view binds exact files after ranking with no title match or backfill',
      () async {
    await seed(1, score: 90);
    await seed(2, score: 80);
    await seed(3, score: 70);
    await seed(4, score: 99, platform: 'snes');
    await db.update('games', {'filename': 'Same.7z'}, where: 'id IN (3,4)');
    final bindings = await query.replaceViewCacheMembers('ui:test', [
      coverRatingKey('psx', 'Same.7z'),
      coverRatingKey('psx', 'Game 1.7z'),
      coverRatingKey('psx', 'missing.7z')
    ], platformIds: {
      'psx'
    }, assessedBases: [
      basis
    ]);
    expect(bindings, {
      1: coverRatingKey('psx', 'Game 1.7z'),
      3: coverRatingKey('psx', 'Same.7z')
    });
    final page = await read(
        filter: LibraryQueryFilter(
            platformIds: {'psx'},
            top: 2,
            viewIds: {'ui:test'},
            includeVariants: true));
    expect(page.items.map((i) => i.cacheRowId), [1]);
    expect(page.collectionGames, 3);
    expect(page.rankedGames, 3);
    await db.insert('games', {
      'id': 5,
      'systemSlug': 'psx',
      'filename': 'Same.7z',
      'displayName': 'duplicate'
    });
    final ambiguous = await query.replaceViewCacheMembers(
        'ui:test', [coverRatingKey('psx', 'Same.7z')],
        platformIds: {'psx'}, assessedBases: [basis]);
    expect(ambiguous, isEmpty);
    expect((await read(filter: LibraryQueryFilter(viewIds: {'ui:test'}))).items,
        isEmpty);
  });

  test('new unscraped cache rows belong to collection and affect coverage',
      () async {
    await seed(1, score: 90);
    await read();
    await db
        .insert('games', {'id': 2, 'systemSlug': 'psx', 'displayName': 'New'});
    final result = await read(filter: LibraryQueryFilter(top: 25));
    expect(result.collectionGames, 2);
    expect(result.rankedGames, 1);
    expect(result.provisional, isTrue);
    expect((await read()).items, hasLength(2));
    await db.update('games', {'displayName': 'Renamed'}, where: 'id = 2');
    expect(
        (await read(filter: LibraryQueryFilter(search: 'Renamed')))
            .items
            .single
            .title,
        'Renamed');
  });

  test('unrated edition cannot display an invented rank from a rated region',
      () async {
    await seed(1, score: 90, group: 'shared');
    final unrated = await seed(2, group: 'shared', regions: ['Europe']);
    final result = await read(filter: LibraryQueryFilter(regions: {'Europe'}));
    expect(result.items.single.editionId, unrated);
    expect(result.items.single.score, isNull);
    expect(result.items.single.rank, isNull);
    expect(
        (await read(filter: LibraryQueryFilter(top: 25, regions: {'Europe'})))
            .items,
        isEmpty);
  });

  test('conflicting accepted edition scores leave group unresolved', () async {
    await seed(1, score: 90, group: 'shared');
    await seed(2, score: 80, group: 'shared');
    final result = await read(filter: LibraryQueryFilter(top: 25));
    expect(result.collectionGames, 1);
    expect(result.rankedGames, 0);
    expect(result.items, isEmpty);
    expect(result.provisional, isTrue);
  });

  test('reviewed provider bridges recompute ranks without borrowing scores',
      () async {
    final a = await seed(1, score: 95);
    final b = await seed(2, score: 90);
    final c = await seed(3, score: 80);
    Future<void> assign(String id, Map<String, String> providers) async {
      final edition = (await store.edition(id))!;
      final game = (await store.game(edition.gameId))!;
      await store.putGame(GameIdentity.fromJson({
        ...game.toJson(),
        'providerIds': providers,
      }));
    }

    await assign(a, {'screenscraper': '1'});
    await assign(b, {'igdb': '2'});
    expect((await read()).collectionGames, 3);
    await assign(c, {'screenscraper': '1', 'igdb': '2'});
    final joined = await read(filter: LibraryQueryFilter(top: 25));
    expect(joined.collectionGames, 1);
    expect(joined.rankedGames, 1);
    expect(joined.items.single.editionId, b);
    expect(joined.items.single.score!.rating.normalizedValue, 90);
    final owned =
        await store.effectiveRatings([a, b, c], assessedBases: [basis]);
    expect(owned[a], isNull);
    expect(owned[c], isNull,
        reason: 'Grouping cannot transfer exact score ownership.');
    expect(owned[b]!.rating.normalizedValue, 90);
    expect((await store.canonicalEditions(b)).editions, hasLength(3));

    await assign(c, {'screenscraper': '1', 'igdb': '3'});
    final split = await read(filter: LibraryQueryFilter(top: 1));
    expect(split.collectionGames, 2);
    expect(split.rankedGames, 2);
    expect(split.items.single.editionId, b);
    expect(split.items.single.rank, 1);
    await query.replaceViewMembers('shelf:other', [a, c]);
    expect(
        (await read(
                filter: LibraryQueryFilter(top: 1, viewIds: {'shelf:other'})))
            .items,
        isEmpty,
        reason: 'Changing the view cannot refill Top 1 with the lower group.');
  });

  test('successful score publication recomputes ranks under the same policy',
      () async {
    final a = await seed(1, score: 90);
    final b = await seed(2, score: 80);
    expect(
        (await read(filter: LibraryQueryFilter(top: 1))).items.single.editionId,
        a);
    final previous = (await store.metadata(b, 'igdb'))!;
    final next = SourcedRating.parse(
        sourceId: 'igdb',
        sourceLabel: 'IGDB',
        providerGameId: previous.providerGameId,
        rawValue: 95,
        scaleMinimum: 0,
        scaleMaximum: 100,
        voteCount: 100,
        kind: RatingKind.overallAggregate,
        retrievedAt: at)!;
    await store.putMetadata(MetadataRecord.fromJson({
      ...previous.toJson(),
      'refreshGeneration': 2,
      'ratings': [next.toJson()]
    }));
    final result = await read(filter: LibraryQueryFilter(top: 1));
    expect(result.items.single.editionId, b);
    expect(result.items.single.score!.rating.normalizedValue, 95);
  });

  test('manual shelf keeps its first matching edition of a canonical game',
      () async {
    final a = await seed(1, score: 90, group: 'shared');
    final b = await seed(2, score: 90, group: 'shared');
    await query.replaceViewMembers('shelf', [a, b]);
    expect(
        (await read(
                filter: LibraryQueryFilter(
                    viewIds: {'shelf'}, manualViewId: 'shelf')))
            .items
            .single
            .editionId,
        a);
    await query.replaceViewMembers('shelf', [b, a]);
    expect(
        (await read(
                filter: LibraryQueryFilter(
                    viewIds: {'shelf'}, manualViewId: 'shelf')))
            .items
            .single
            .editionId,
        b);
  });

  test(
      'ambiguous raw match cannot publish genre facets through another consumer',
      () async {
    final id = await seed(1);
    final edition = (await store.edition(id))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(
        GameIdentity.fromJson({...game.toJson(), 'matchStatus': 'ambiguous'}));
    await store.putMetadata(MetadataRecord(
        gameId: game.id,
        editionId: id,
        platformId: 'psx',
        providerId: 'screenscraper',
        providerGameId: '1',
        retrievedAt: at,
        refreshGeneration: 1,
        matchMethod: 'rawRomHashAndSize',
        titles: [
          MetadataText(text: 'Fixture')
        ],
        genres: [
          MetadataGenre(
              providerGenreId: '1', names: [MetadataText(text: 'Puzzle')])
        ]));
    expect((await read(filter: LibraryQueryFilter(genres: {'Puzzle'}))).items,
        isEmpty);
    expect((await read()).items, hasLength(1),
        reason: 'Ambiguity cannot hide ordinary browsing.');
  });
}
