import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/services/library_store.dart';

void main() {
  late Database db;
  late LibraryStore store;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    store = LibraryStore(Future.value(db));
  });
  tearDown(() => db.close());

  test('additive schema retains legacy rows and never imports anonymous scores',
      () async {
    await db.execute('CREATE TABLE game_metadata(filename TEXT, rating REAL)');
    await db
        .insert('game_metadata', {'filename': 'Legacy.chd', 'rating': 99.0});
    await db.transaction(LibrarySchema.install);
    await db.transaction(LibrarySchema.install);
    expect((await db.query('game_metadata')).single['rating'], 99.0);
    expect(await db.query('library_metadata'), isEmpty);
    expect(await db.query('library_game_identities'), isEmpty);
  });

  test('rename updates remote metadata without duplicating file identity',
      () async {
    await db.transaction(LibrarySchema.install);
    final id = RemoteArtifactId(
        providerId: 'drive',
        sourceId: 's1',
        accountId: 'a1',
        providerFileId: 'f1');
    await store.putArtifact(RemoteArtifact(
        id: id,
        displayName: 'Old.chd',
        displayPath: 'psx/Old.chd',
        sizeBytes: 10,
        version: '1'));
    await store.putArtifact(RemoteArtifact(
        id: id,
        displayName: 'New.chd',
        displayPath: 'psx/New.chd',
        sizeBytes: 10,
        version: '2'));
    expect(await db.query('library_artifacts'), hasLength(1));
    expect((await store.artifact(id))!.displayName, 'New.chd');
  });

  test('same filename in separate accounts remains separate', () async {
    await db.transaction(LibrarySchema.install);
    for (final account in ['a1', 'a2']) {
      await store.putArtifact(RemoteArtifact(
          id: RemoteArtifactId(
              providerId: 'drive',
              sourceId: 's1',
              accountId: account,
              providerFileId: 'f1'),
          displayName: 'Same.chd',
          displayPath: 'psx/Same.chd',
          sizeBytes: 10));
    }
    expect(await db.query('library_artifacts'), hasLength(2));
  });

  test('game and edition identity survive storage independent of residency',
      () async {
    await db.transaction(LibrarySchema.install);
    final game = GameIdentity(id: 'g1', platformId: 'psx', title: 'Example');
    final edition =
        EditionIdentity(id: 'e1', gameId: 'g1', tags: {'T-Eng', 'Uncensor'});
    await store.putGame(game);
    await store.putEdition(edition);
    expect((await store.game('g1'))!.toJson(), game.toJson());
    expect((await store.edition('e1'))!.toJson(), edition.toJson());
    expect(await db.query('library_metadata'), isEmpty);
  });

  test('an edition cannot silently move to an unrelated canonical game',
      () async {
    await db.transaction(LibrarySchema.install);
    await store
        .putGame(GameIdentity(id: 'g1', platformId: 'psx', title: 'First'));
    await store
        .putGame(GameIdentity(id: 'g2', platformId: 'psx', title: 'Second'));
    await store.putEdition(EditionIdentity(id: 'e1', gameId: 'g1'));
    await expectLater(store.putEdition(EditionIdentity(id: 'e1', gameId: 'g2')),
        throwsStateError);
    expect((await store.edition('e1'))!.gameId, 'g1');
  });

  test('orphan edition is rejected instead of silently inventing a game',
      () async {
    await db.transaction(LibrarySchema.install);
    await expectLater(
        store.putEdition(EditionIdentity(id: 'e1', gameId: 'missing')),
        throwsStateError);
    expect(await store.edition('e1'), isNull);
  });

  test('metadata cannot override an explicitly assigned provider identity',
      () async {
    await db.transaction(LibrarySchema.install);
    await store.putGame(GameIdentity(
        id: 'g1',
        platformId: 'psx',
        title: 'Example',
        providerIds: {'screenscraper': '42'},
        matchStatus: IdentityMatchStatus.manuallyMatched));
    await store.putEdition(EditionIdentity(id: 'e1', gameId: 'g1'));
    MetadataRecord record(String providerGameId) => MetadataRecord(
        gameId: 'g1',
        editionId: 'e1',
        platformId: 'psx',
        providerId: 'screenscraper',
        providerGameId: providerGameId,
        retrievedAt: DateTime.utc(2026, 9, 8),
        refreshGeneration: 1,
        matchMethod: 'verifiedProviderId',
        titles: const [MetadataText(text: 'Example')]);
    await expectLater(store.putMetadata(record('43')), throwsStateError);
    expect(await store.metadata('e1', 'screenscraper'), isNull);
    await store.putMetadata(record('42'));
    expect((await store.metadata('e1', 'screenscraper'))!.providerGameId, '42');
  });

  test('fresh provenance persists but stale generation cannot replace it',
      () async {
    await db.transaction(LibrarySchema.install);
    await store
        .putGame(GameIdentity(id: 'g1', platformId: 'psx', title: 'Example'));
    await store.putEdition(EditionIdentity(id: 'e1', gameId: 'g1'));
    MetadataRecord record(int generation, {String gameId = 'g1'}) =>
        MetadataRecord(
            gameId: gameId,
            editionId: 'e1',
            platformId: 'psx',
            providerId: 'screenscraper',
            providerGameId: '42',
            retrievedAt: DateTime.utc(2026, 9, 8),
            refreshGeneration: generation,
            matchMethod: 'verifiedProviderId',
            titles: const [
              MetadataText(text: 'Example')
            ],
            ratings: [
              SourcedRating.parse(
                  sourceId: 'screenscraper',
                  sourceLabel: 'ScreenScraper',
                  providerGameId: '42',
                  rawValue: '17',
                  scaleMinimum: 0,
                  scaleMaximum: 20,
                  kind: RatingKind.unknownAggregate,
                  retrievedAt: DateTime.utc(2026, 9, 8))!
            ]);
    await store.putMetadata(record(2));
    await expectLater(store.putMetadata(record(1)), throwsStateError);
    await expectLater(
        store.putMetadata(record(3, gameId: 'wrong')), throwsStateError);
    final restored = await store.metadata('e1', 'screenscraper');
    expect(restored!.refreshGeneration, 2);
    expect(restored.ratings.single.normalizedValue, 85);
    expect(restored.ratings.single.consensusValidated, isFalse);
    await store
        .putGame(GameIdentity(id: 'g1', platformId: 'psx', title: 'Renamed'));
    expect(await store.metadata('e1', 'screenscraper'), isNotNull);
    await store.putEdition(EditionIdentity(
        id: 'e1', gameId: 'g1', tags: {'Hack'}, patchId: 'different-project'));
    expect(await store.metadata('e1', 'screenscraper'), isNull,
        reason: 'an identity correction cannot lend the old score to a patch');
    expect(await db.query('library_metadata'), hasLength(1),
        reason: 'invalidate the binding without discarding cached evidence');
    await store.putEdition(EditionIdentity(id: 'e1', gameId: 'g1'));
    await store
        .putGame(GameIdentity(id: 'g1', platformId: 'snes', title: 'Example'));
    expect(await store.metadata('e1', 'screenscraper'), isNull,
        reason: 'a platform correction cannot retain the old platform score');
  });

  test('independent provider review preserves existing owned metadata',
      () async {
    await LibrarySchema.install(db);
    final game = GameIdentity(
        id: 'g1',
        platformId: 'psx',
        title: 'Example',
        providerIds: {'screenscraper': '42'},
        matchStatus: IdentityMatchStatus.manuallyMatched,
        evidence: [
          IdentityEvidence(
              source: 'manual',
              kind: 'providerId',
              value: jsonEncode(['screenscraper', '42']))
        ]);
    await store.putGame(game);
    await store.putEdition(
        EditionIdentity(id: 'e1', gameId: 'g1', tags: {'official'}));
    await store.putMetadata(MetadataRecord(
        gameId: 'g1',
        editionId: 'e1',
        platformId: 'psx',
        providerId: 'screenscraper',
        providerGameId: '42',
        retrievedAt: DateTime.utc(2026, 10, 3),
        refreshGeneration: 1,
        matchMethod: 'verifiedProviderId',
        titles: const [MetadataText(text: 'Example')]));
    final reviewed = GameIdentity.fromJson({
      ...game.toJson(),
      'providerIds': {'igdb': '100', 'screenscraper': '42'},
      'evidence': [
        ...game.evidence.map((e) => e.toJson()),
        IdentityEvidence(
            source: 'manual',
            kind: 'providerId',
            value: jsonEncode(['igdb', '100'])).toJson()
      ]
    });
    await store.putGame(reviewed);
    expect(await store.metadata('e1', 'screenscraper'), isNotNull,
        reason:
            'a second independently reviewed source must not erase the first');
    await store.putGame(GameIdentity.fromJson({
      ...reviewed.toJson(),
      'providerIds': {'igdb': '100', 'screenscraper': '43'}
    }));
    expect(await store.metadata('e1', 'screenscraper'), isNull,
        reason: 'the owning provider match still controls its score');
    expect(await db.query('library_metadata'), hasLength(1));
  });

  test('provider-scoped bindings retain every non-provider identity boundary',
      () {
    final game = GameIdentity(
        id: 'g',
        platformId: 'psx',
        title: 'Example',
        providerIds: {'screenscraper': '42'},
        matchStatus: IdentityMatchStatus.manuallyMatched);
    final edition = EditionIdentity(id: 'e', gameId: 'g', tags: {'official'});
    String binding(GameIdentity g, EditionIdentity e) =>
        LibraryStore.metadataIdentity({
          'game_json': jsonEncode(g.toJson()),
          'edition_json': jsonEncode(e.toJson())
        }, providerId: 'screenscraper');
    final initial = binding(game, edition);
    for (final change in [
      {'platformId': 'snes'},
      {'baseGameId': 'different-base'},
      {'matchStatus': 'unmatched'},
      {
        'providerIds': {'screenscraper': '43'}
      },
      {
        'evidence': [
          IdentityEvidence(
                  source: 'manual', kind: 'providerId', value: 'not-valid-json')
              .toJson()
        ]
      },
      {
        'evidence': [
          IdentityEvidence(
                  source: 'igdb',
                  kind: 'rawRomChecksum',
                  value: 'different-raw-rom')
              .toJson()
        ]
      }
    ]) {
      expect(
          binding(
              GameIdentity.fromJson({...game.toJson(), ...change}), edition),
          isNot(initial),
          reason: '$change must not be discarded as unrelated');
    }
    for (final change in [
      {'releaseId': 'another-release'},
      {'revision': '2'},
      {'patchId': 'patch'},
      {
        'tags': ['Hack']
      },
      {
        'regions': ['jp']
      },
      {
        'languages': ['ja']
      },
      {
        'providerIds': {'screenscraper': 'another-release'}
      },
      {
        'members': [
          EditionMember(
              artifactId: RemoteArtifactId(
                  providerId: 'drive',
                  sourceId: 'source',
                  providerFileId: 'replacement'),
              rawRomChecksums: {'md5': 'different-bytes'}).toJson()
        ]
      }
    ]) {
      expect(
          binding(
              game, EditionIdentity.fromJson({...edition.toJson(), ...change})),
          isNot(initial),
          reason: '$change still defines exact edition ownership');
    }
  });
}
