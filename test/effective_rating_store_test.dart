import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/effective_overall_rating.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late LibraryStore store;
  final at = DateTime.utc(2026, 10, 3);
  final artifactId = RemoteArtifactId(
      providerId: 'drive',
      sourceId: 'fixture',
      accountId: 'fixture-owner',
      providerFileId: 'file-1');
  RemoteArtifact artifact(String digest, {String name = 'Fixture.chd'}) =>
      RemoteArtifact(
          id: artifactId,
          displayName: name,
          displayPath: 'psx/$name',
          sizeBytes: 100,
          version: 'v1',
          providerChecksums: {'sha256': digest});
  final assessment = AssessedOverallScoreBasis(
      sourceId: 'igdb',
      kind: RatingKind.overallAggregate,
      scaleMinimum: 0,
      scaleMaximum: 100,
      platformIds: {'psx'},
      minimumVoteCount: 10,
      assessmentReference: 'fixture-only-reception-assessment');
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games(id INTEGER PRIMARY KEY,
      systemSlug TEXT, displayName TEXT, artifact_key TEXT, remote_artifact TEXT,
      is_folder INTEGER DEFAULT 0)''');
    store = LibraryStore(Future.value(db));
  });
  tearDown(() => db.close());

  Future<String> seed() async {
    await db.insert('games', {
      'id': 1,
      'systemSlug': 'psx',
      'displayName': 'Fixture',
      'artifact_key': artifactId.key,
      'remote_artifact': jsonEncode(artifact('a' * 64).toJson())
    });
    final editions = await db
        .transaction((txn) => LibraryStore.catalogueEditions(txn).toList());
    final edition = (await store.edition(editions.single))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'matchStatus': 'manuallyMatched',
      'providerIds': {'screenscraper': '42', 'igdb': '91'}
    }));
    await store.putEdition(EditionIdentity.fromJson({
      ...edition.toJson(),
      'tags': ['official']
    }));
    for (final provider in ['screenscraper', 'igdb']) {
      final id = provider == 'screenscraper' ? '42' : '91';
      await store.putMetadata(MetadataRecord(
          gameId: game.id,
          editionId: edition.id,
          platformId: 'psx',
          providerId: provider,
          providerGameId: id,
          retrievedAt: at,
          refreshGeneration: 1,
          matchMethod: 'verifiedProviderId',
          titles: const [
            MetadataText(text: 'Fixture')
          ],
          ratings: [
            SourcedRating.parse(
                sourceId: provider,
                sourceLabel: provider,
                providerGameId: id,
                rawValue: provider == 'screenscraper' ? 19 : 81,
                scaleMinimum: 0,
                scaleMaximum: provider == 'screenscraper' ? 20 : 100,
                voteCount: 100,
                kind: provider == 'screenscraper'
                    ? RatingKind.unknownAggregate
                    : RatingKind.overallAggregate,
                retrievedAt: at)!
          ]));
    }
    return edition.id;
  }

  test(
      'shared batched cache read supplies one exact display/rank score offline',
      () async {
    final id = await seed();
    final unassessed = (await store.effectiveRatings([id, 'missing']))[id]!;
    expect(unassessed.rating.normalizedValue, 95);
    expect(unassessed.rankingEligible, isFalse);
    final accepted = await store
        .effectiveRatings([id, 'missing'], assessedBases: [assessment]);
    expect(accepted[id]!.rating.normalizedValue, 81);
    expect(accepted[id]!.rankingEligible, isTrue);
    expect(accepted.containsKey('missing'), isTrue);
    expect(accepted['missing'], isNull);
    expect(() => accepted.clear(), throwsUnsupportedError);
    expect(
        (await store.effectiveRatings([id], assessedBases: [assessment]))[id]!
            .rating
            .toJson(),
        accepted[id]!.rating.toJson());
  });

  test(
      'unchanged catalogue seeding preserves reviewed evidence and cached score',
      () async {
    final id = await seed();
    final original = (await store.edition(id))!;
    final records = [
      (await store.metadata(id, 'screenscraper'))!,
      (await store.metadata(id, 'igdb'))!,
    ];
    // Normal review appends classification after the existing content marker.
    final reviewed = EditionIdentity.fromJson({
      ...original.toJson(),
      'evidence': [
        ...original.evidence.map((e) => e.toJson()),
        IdentityEvidence(
            source: 'manual',
            kind: 'contentClassification',
            value: jsonEncode(['official'])).toJson(),
      ],
    });
    await store.putEdition(reviewed);
    for (final record in records) {
      await store.putMetadata(record);
    }
    expect(
        (await store.effectiveRatings([id], assessedBases: [assessment]))[id]!
            .rankingEligible,
        isTrue);

    for (var refresh = 0; refresh < 2; refresh++) {
      await db
          .transaction((txn) => LibraryStore.catalogueEditions(txn).toList());
      final rating =
          (await store.effectiveRatings([id], assessedBases: [assessment]))[id];
      expect(rating, isNotNull,
          reason:
              'Unchanged source content must not invalidate a reviewed score');
      expect(rating!.rating.normalizedValue, 81);
      expect(rating.rankingEligible, isTrue);
      expect((await store.edition(id))!.toJson(), reviewed.toJson());
      expect(await store.metadata(id, 'screenscraper'), isNotNull);
      expect(await store.metadata(id, 'igdb'), isNotNull);
    }
  });

  test(
      'provider correction invalidates its score but preserves the independent owner',
      () async {
    final id = await seed();
    final edition = (await store.edition(id))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'providerIds': {'screenscraper': '43', 'igdb': '91'}
    }));
    final selected = (await store.effectiveRatings([id]))[id]!;
    expect(selected.rating.sourceId, 'igdb');
    expect(selected.rating.normalizedValue, 81);
    expect(
        (await store.effectiveRatings([id], assessedBases: [assessment]))[id]!
            .rankingEligible,
        isTrue);
    expect(await db.query('library_metadata'), hasLength(2));
  });

  test(
      'changed patch or source bytes omit cached scores rather than reusing them',
      () async {
    final id = await seed();
    final before = (await store.edition(id))!;
    await store.putEdition(
        EditionIdentity.fromJson({...before.toJson(), 'patchId': 'different'}));
    expect(
        (await store.effectiveRatings([id], assessedBases: [assessment]))[id],
        isNull);
    await store.putEdition(before);
    expect((await store.effectiveRatings([id]))[id], isNotNull);
    await db.update(
        'games', {'remote_artifact': jsonEncode(artifact('b' * 64).toJson())},
        where: 'id = 1');
    expect(
        (await store.effectiveRatings([id], assessedBases: [assessment]))[id],
        isNull);
    expect(await db.query('library_metadata'), hasLength(2));
  });

  test('pure rename keeps the score; collection removal makes it unavailable',
      () async {
    final id = await seed();
    await db.update(
        'games',
        {
          'displayName': 'Renamed',
          'remote_artifact':
              jsonEncode(artifact('a' * 64, name: 'Renamed.chd').toJson())
        },
        where: 'id = 1');
    expect(
        (await store.effectiveRatings([id]))[id]!.rating.normalizedValue, 95);
    await db.delete('games', where: 'id = 1');
    expect((await store.effectiveRatings([id]))[id], isNull);
    expect(await db.query('library_metadata'), hasLength(2));
  });

  test('newer requested generation retains old facts but makes them stale',
      () async {
    final id = await seed();
    await db.delete('library_metadata',
        where: 'provider_id = ?', whereArgs: ['screenscraper']);
    final old = (await store.metadata(id, 'igdb'))!;
    expect(
        (await store.effectiveRatings([id], assessedBases: [assessment]))[id]!
            .rankingEligible,
        isTrue);
    final jobs = MetadataRefreshJobs(Future.value(db));
    final refresh = await jobs.createFromCatalogue(providerId: 'igdb');
    final pending =
        (await store.effectiveRatings([id], assessedBases: [assessment]))[id]!;
    expect(pending.rating.toJson(), old.ratings.single.toJson());
    expect(pending.fresh, isFalse);
    expect(pending.rankingEligible, isFalse);
    await db.update('metadata_refresh_jobs',
        {'state': 'blocked', 'blocked_status': 'unavailable'},
        where: 'id = ?', whereArgs: [refresh.id]);
    expect(
        (await LibraryStore(Future.value(db))
                .effectiveRatings([id], assessedBases: [assessment]))[id]!
            .fresh,
        isFalse);
    await store.putMetadata(MetadataRecord.fromJson(
        {...old.toJson(), 'refreshGeneration': refresh.generation}));
    expect(
        (await store.effectiveRatings([id], assessedBases: [assessment]))[id]!
            .rankingEligible,
        isTrue);
  });

  test('batch is capped at 128 requested editions without a whole-library scan',
      () async {
    final id = await seed();
    final ids = [id, for (var i = 0; i < 127; i++) 'missing-$i'];
    expect(await store.effectiveRatings(ids), hasLength(128));
    await expectLater(
        store.effectiveRatings([...ids, '129th']), throwsArgumentError);
    expect(await store.effectiveRatings([]), isEmpty);
    expect(await store.effectiveRatings([id, id]), hasLength(1));
  });
}
