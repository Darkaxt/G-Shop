import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/metadata/effective_overall_rating.dart';

void main() {
  final at = DateTime.utc(2026, 10, 3);
  final game = GameIdentity(
      id: 'g',
      platformId: 'psx',
      title: 'Fixture',
      providerIds: {'screenscraper': '42', 'igdb': '91', 'romm': '7'},
      matchStatus: IdentityMatchStatus.manuallyMatched);
  final official = EditionIdentity(id: 'e', gameId: 'g', tags: {'official'});

  MetadataRecord record(String provider, double value,
      {int? votes,
      RatingKind? kind,
      int generation = 1,
      String method = 'verifiedProviderId',
      String? providerGameId}) {
    final id = providerGameId ?? game.providerIds[provider]!;
    return MetadataRecord(
        gameId: 'g',
        editionId: 'e',
        platformId: 'psx',
        providerId: provider,
        providerGameId: id,
        retrievedAt: at,
        refreshGeneration: generation,
        matchMethod: method,
        titles: const [
          MetadataText(text: 'Fixture')
        ],
        ratings: [
          SourcedRating.parse(
              sourceId: provider,
              sourceLabel: provider,
              providerGameId: id,
              rawValue: value,
              scaleMinimum: 0,
              scaleMaximum: provider == 'screenscraper' ? 20 : 100,
              voteCount: votes,
              kind: kind ??
                  (provider == 'screenscraper'
                      ? RatingKind.unknownAggregate
                      : RatingKind.overallAggregate),
              retrievedAt: at)!
        ]);
  }

  // This explicit synthetic assessment exercises semantics, NOT live reception
  // acceptance. These overrides are distinct from the recorded production basis.
  AssessedOverallScoreBasis basis(String provider,
          {String? unknownCountAssessment,
          Set<String> platforms = const {'psx'}}) =>
      AssessedOverallScoreBasis(
          sourceId: provider,
          kind: provider == 'screenscraper'
              ? RatingKind.unknownAggregate
              : RatingKind.overallAggregate,
          scaleMinimum: 0,
          scaleMaximum: provider == 'screenscraper' ? 20 : 100,
          platformIds: platforms,
          minimumVoteCount: 10,
          assessmentReference: 'fixture-only-reception-assessment',
          unknownCountAssessment: unknownCountAssessment);

  EffectiveOverallRating? select(List<MetadataRecord> records,
          {List<AssessedOverallScoreBasis> assessed = const [],
          EditionIdentity? edition,
          GameIdentity? identity,
          GameIdentity? baseGame}) =>
      selectEffectiveOverallRating(
          game: identity ?? game,
          edition: edition ?? official,
          records: records,
          assessedBases: assessed,
          baseGame: baseGame);

  test('ordinary display is sourced but Top is disabled without assessment',
      () {
    final selected = select([record('screenscraper', 17, votes: 500)])!;
    expect(selected.rating.normalizedValue, 85);
    expect(selected.rating.voteCount, 500);
    expect(selected.rankingEligible, isFalse);
    expect(selected.assessmentReference, isNull);
    expect(selected.ownership, OverallRatingOwnership.game);
  });

  test('deterministic display precedence never picks the highest score', () {
    final records = [
      record('igdb', 99, votes: 100),
      record('screenscraper', 15)
    ];
    expect(select(records)!.rating.normalizedValue, 75);
    expect(select(records.reversed.toList())!.rating.normalizedValue, 75);
    expect(select([records.first])!.rating.sourceId, 'igdb');
  });

  test(
      'a current fallback is preferred over a retained legacy-generation score',
      () {
    final selected = select([
      record('screenscraper', 20, generation: 0),
      record('igdb', 81, votes: 100)
    ])!;
    expect(selected.rating.sourceId, 'igdb');
    expect(selected.fresh, isTrue);
    expect(selected.rankingEligible, isFalse);
  });

  test('conflicting edition and game provider IDs are not an override', () {
    final edition = EditionIdentity(
        id: 'e',
        gameId: 'g',
        tags: {'official'},
        providerIds: {'igdb': 'different'});
    expect(
        select([record('igdb', 99, providerGameId: 'different')],
            edition: edition),
        isNull);
  });

  test('verified compatible raw-ROM match can display without a manual ID', () {
    final rawGame = GameIdentity(id: 'g', title: 'Fixture', platformId: 'psx');
    final selected = select(
        [record('screenscraper', 17, method: 'rawRomHashAndSize')],
        identity: rawGame)!;
    expect(selected.rating.normalizedValue, 85);
    expect(selected.rankingEligible, isFalse);
    expect(select([record('screenscraper', 17)], identity: rawGame), isNull);
  });

  test('capped provider size keeps exact SHA-1 advisory ownership, not Top',
      () {
    final rawGame = GameIdentity(id: 'g', title: 'Fixture', platformId: 'psx');
    final records = [
      record('screenscraper', 17, method: 'rawRomSha1AndCappedSize')
    ];
    final selected = select(records, identity: rawGame)!;
    expect(selected.rating.normalizedValue, 85);
    expect(selected.ownership, OverallRatingOwnership.game);
    expect(selected.rankingEligible, isFalse);
    expect(
        select(records,
            identity: rawGame,
            edition: EditionIdentity(id: 'e', gameId: 'g', tags: {'unknown'})),
        isNull);
    expect(
        select(records,
            identity: rawGame,
            edition: EditionIdentity(id: 'e', gameId: 'g', tags: {'Hack'})),
        isNull);
  });

  test('accepted sourced overall drives both display and ranking', () {
    final selected = select(
        [record('screenscraper', 19), record('igdb', 81, votes: 100)],
        assessed: [basis('igdb')])!;
    expect(selected.rating.normalizedValue, 81);
    expect(selected.rankingEligible, isTrue);
    expect(selected.assessmentReference, 'fixture-only-reception-assessment');
  });

  test('assessed source precedence is fixed, not magnitude or input order', () {
    final selected = select([
      record('igdb', 99, votes: 100),
      record('screenscraper', 15, votes: 100)
    ], assessed: [
      basis('screenscraper'),
      basis('igdb')
    ])!;
    expect(selected.rating.sourceId, 'screenscraper');
    expect(selected.rating.normalizedValue, 75);
  });

  test('low-vote extreme remains visible but cannot masquerade as consensus',
      () {
    final selected =
        select([record('igdb', 100, votes: 2)], assessed: [basis('igdb')])!;
    expect(selected.rating.normalizedValue, 100);
    expect(selected.rating.voteCount, 2);
    expect(selected.rankingEligible, isFalse);
  });

  test('acceptance does not extend to an unassessed score scale', () {
    final differentlyScaled = MetadataRecord.fromJson({
      ...record('igdb', 17, votes: 100).toJson(),
      'ratings': [
        {
          ...record('igdb', 17, votes: 100).ratings.single.toJson(),
          'scaleMaximum': 20
        }
      ]
    });
    final selected = select([differentlyScaled], assessed: [basis('igdb')])!;
    expect(selected.rating.normalizedValue, 85);
    expect(selected.rankingEligible, isFalse);
  });

  test('unknown count requires explicit scoped confidence assessment', () {
    final records = [record('screenscraper', 17)];
    expect(select(records, assessed: [basis('screenscraper')])!.rankingEligible,
        isFalse);
    final selected = select(records, assessed: [
      basis('screenscraper',
          unknownCountAssessment: 'fixture documented independent support')
    ])!;
    expect(selected.rating.voteCount, isNull);
    expect(selected.rankingEligible, isTrue);
    expect(selected.unknownCountAssessment, isNotNull);
    expect(
        select(records, assessed: [
          basis('screenscraper',
              platforms: {'ps2'},
              unknownCountAssessment: 'fixture independent support')
        ])!
            .rankingEligible,
        isFalse);
  });

  test('critic/community components never substitute for overall', () {
    for (final kind in [
      RatingKind.criticAggregate,
      RatingKind.communityAggregate
    ]) {
      expect(select([record('igdb', 100, votes: 100, kind: kind)]), isNull);
    }
  });

  test('assessed community game score is selected, not the blended maximum',
      () {
    final community =
        record('igdb', 90.5, votes: 1712, kind: RatingKind.communityAggregate);
    final combined = MetadataRecord.fromJson({
      ...community.toJson(),
      'ratings': [
        record('igdb', 85.25, votes: 1713).ratings.single.toJson(),
        record('igdb', 80, votes: 1, kind: RatingKind.criticAggregate)
            .ratings
            .single
            .toJson(),
        community.ratings.single.toJson(),
      ]
    });
    final assessment = AssessedOverallScoreBasis(
        sourceId: 'igdb',
        kind: RatingKind.communityAggregate,
        scaleMinimum: 0,
        scaleMaximum: 100,
        platformIds: {'psx'},
        minimumVoteCount: 20,
        assessmentReference: 'fixture-explicit-community-assessment');
    final selected = select([combined], assessed: [assessment])!;
    expect(selected.rating.kind, RatingKind.communityAggregate);
    expect(selected.rating.normalizedValue, 90.5);
    expect(selected.rating.voteCount, 1712);
    expect(selected.rankingEligible, isTrue);
    // No assessment means no implicit component substitution.
    expect(select([combined])!.rating.normalizedValue, 85.25);
    for (final votes in [null, 2, 19]) {
      final lowSupport = record('igdb', 100,
          votes: votes, kind: RatingKind.communityAggregate);
      expect(select([lowSupport], assessed: [assessment])?.rankingEligible,
          isNot(true));
    }
  });

  test('production community basis enforces support scope and freshness', () {
    for (final votes in [null, 2, 19, 20]) {
      final score =
          record('igdb', 99, votes: votes, kind: RatingKind.communityAggregate);
      final selected = select([score], assessed: productionOverallScoreBases)!;
      expect(selected.rating.normalizedValue, 99);
      expect(selected.rating.kind, RatingKind.communityAggregate);
      expect(selected.rating.voteCount, votes);
      expect(selected.rankingEligible, votes == 20);
      final stale = selectEffectiveOverallRating(
          game: game,
          edition: official,
          records: [score],
          assessedBases: productionOverallScoreBases,
          staleProviderIds: {'igdb'})!;
      expect(stale.rating.toJson(), score.ratings.single.toJson());
      expect(stale.fresh, isFalse);
      expect(stale.rankingEligible, isFalse);
    }
    final unsupported =
        record('igdb', 99, votes: 100, kind: RatingKind.communityAggregate);
    expect(
        select([
          MetadataRecord.fromJson(
              {...unsupported.toJson(), 'platformId': 'saturn'})
        ],
            identity: GameIdentity.fromJson(
                {...game.toJson(), 'platformId': 'saturn'}),
            assessed: productionOverallScoreBases),
        isNull);
  });

  test('imported approval and stale generations do not grant ranking', () {
    final original = record('igdb', 80, votes: 100);
    final imported = MetadataRecord.fromJson({
      ...original.toJson(),
      'ratings': [
        {
          ...original.ratings.single.toJson(),
          'consensusValidated': true,
          'eligibleForRanking': true
        }
      ]
    });
    expect(select([imported])!.rankingEligible, isFalse);
    final stale = select([record('igdb', 80, votes: 100, generation: 0)],
        assessed: [basis('igdb')])!;
    expect(stale.fresh, isFalse);
    expect(stale.rankingEligible, isFalse);
  });

  test('S7 assessed consoles retain the community support boundary', () {
    for (final platform in [
      'n64',
      'psp',
      'gb',
      'gbc',
      'nes',
      'snes',
      'wii',
      'wiiu'
    ]) {
      final scopedGame =
          GameIdentity.fromJson({...game.toJson(), 'platformId': platform});
      for (final votes in [null, 10, 19, 20]) {
        final scopedRecord = MetadataRecord.fromJson({
          ...record('igdb', 81,
                  votes: votes, kind: RatingKind.communityAggregate)
              .toJson(),
          'platformId': platform,
        });
        final selected = selectEffectiveOverallRating(
            game: scopedGame,
            edition: official,
            records: [scopedRecord],
            assessedBases: productionOverallScoreBases);
        expect(selected?.rankingEligible == true, votes == 20,
            reason: '$platform with $votes community votes');
        if (selected != null) {
          expect(
              selected.rating.toJson(), scopedRecord.ratings.single.toJson());
        }
      }
    }
    // Sparse Game Gear samples do not establish a newly assessed scope.
    final unassessedGame =
        GameIdentity.fromJson({...game.toJson(), 'platformId': 'gamegear'});
    final unassessedRecord = MetadataRecord.fromJson({
      ...record('igdb', 81, votes: 100, kind: RatingKind.communityAggregate)
          .toJson(),
      'platformId': 'gamegear',
    });
    expect(
        selectEffectiveOverallRating(
                game: unassessedGame,
                edition: official,
                records: [unassessedRecord],
                assessedBases: productionOverallScoreBases)
            ?.rankingEligible,
        isNot(true));
  });

  test(
      'ordinary English is not a translation; real combined tags label original',
      () {
    expect(
        select([record('igdb', 80)])!.ownership, OverallRatingOwnership.game);
    final translated = EditionIdentity(
        id: 'e',
        gameId: 'g',
        tags: {'T-Eng', 'Undub', 'Uncensor'},
        isTranslation: true,
        translatedLanguages: ['en'],
        patchId: 'patch-1');
    final selected = select(
        [record('igdb', 80, method: 'verifiedProviderIdGlobalGame')],
        edition: translated)!;
    expect(selected.ownership, OverallRatingOwnership.originalGame);
    expect(select([record('screenscraper', 20)], edition: translated), isNull);
  });

  test('unknown or contradictory classification cannot acquire an overlay', () {
    for (final edition in [
      EditionIdentity(id: 'e', gameId: 'g'),
      EditionIdentity(id: 'e', gameId: 'g', tags: {'unknown'}),
      EditionIdentity(id: 'e', gameId: 'g', tags: {'official', 'T-Eng'}),
      EditionIdentity(
          id: 'e',
          gameId: 'g',
          tags: {'T-Eng'},
          isTranslation: false,
          translatedLanguages: ['en'])
    ]) {
      expect(
          select([record('igdb', 100, method: 'verifiedProviderIdGlobalGame')],
              edition: edition),
          isNull);
    }
  });

  test(
      'explicit base relation labels original score only on known modifications',
      () {
    final related =
        GameIdentity.fromJson({...game.toJson(), 'baseGameId': 'base'});
    final base = GameIdentity(
        id: 'base',
        title: 'Original',
        platformId: 'psx',
        providerIds: {'igdb': '91'},
        matchStatus: IdentityMatchStatus.matched);
    final edition = EditionIdentity(
        id: 'e',
        gameId: 'g',
        tags: {'T-Eng', 'Undub', 'Uncensor'},
        isTranslation: true,
        translatedLanguages: ['en'],
        patchId: 'translation');
    final original = record('igdb', 80, method: 'verifiedProviderIdGlobalGame');
    final score =
        select([original], identity: related, edition: edition, baseGame: base);
    expect(score, isNotNull);
    expect(score!.ownership, OverallRatingOwnership.originalGame);
    expect(score.rankingEligible, isFalse);
    for (final wrongBase in [
      null,
      GameIdentity.fromJson({...base.toJson(), 'platformId': 'ps2'}),
      GameIdentity.fromJson({...base.toJson(), 'matchStatus': 'unmatched'}),
      GameIdentity.fromJson({
        ...base.toJson(),
        'providerIds': {'igdb': 'other'}
      })
    ]) {
      expect(
          select([original],
              identity: related, edition: edition, baseGame: wrongBase),
          isNull);
    }
    expect(select([original], identity: related, baseGame: base), isNull,
        reason:
            'An original-game link cannot make an official edition a patch.');
  });

  test('hack may use its verified project rating, never its base rating', () {
    final hack = EditionIdentity(id: 'e', gameId: 'g', tags: {'Hack'});
    expect(select([record('igdb', 99)], edition: hack), isNull);
    final selected = select(
        [record('igdb', 80, votes: 100, method: 'verifiedProjectId')],
        edition: hack,
        assessed: [basis('igdb')])!;
    expect(selected.ownership, OverallRatingOwnership.project);
    expect(selected.rankingEligible, isTrue);
    expect(
        select([record('igdb', 80, method: 'verifiedProjectId')],
            edition: EditionIdentity(
                id: 'e', gameId: 'g', tags: {'official', 'Hack'})),
        isNull);
    final related =
        GameIdentity.fromJson({...game.toJson(), 'baseGameId': 'base'});
    final base = GameIdentity(
        id: 'base',
        title: 'Original',
        platformId: 'psx',
        providerIds: {'igdb': '91'},
        matchStatus: IdentityMatchStatus.matched);
    expect(
        select([record('igdb', 99, method: 'verifiedProjectId')],
            identity: related, edition: hack, baseGame: base),
        isNull);
  });

  test(
      'wrong owner, platform, candidate match, or conflicting score is omitted',
      () {
    final score = record('igdb', 80);
    for (final altered in [
      {...score.toJson(), 'gameId': 'other'},
      {...score.toJson(), 'editionId': 'other'},
      {...score.toJson(), 'platformId': 'ps2'},
      {...score.toJson(), 'providerGameId': 'other'},
      {...score.toJson(), 'matchMethod': 'platformAndTitle'},
      {
        ...score.toJson(),
        'ratings': [
          score.ratings.single.toJson(),
          {...score.ratings.single.toJson(), 'rawValue': '90'}
        ]
      },
    ]) {
      expect(select([MetadataRecord.fromJson(altered)]), isNull);
    }
    expect(
        select([score],
            identity: GameIdentity.fromJson(
                {...game.toJson(), 'matchStatus': 'ambiguous'})),
        isNull);
  });

  test('assessment cannot promote components or accept unsupported vote policy',
      () {
    expect(
        () => AssessedOverallScoreBasis(
            sourceId: 'igdb',
            kind: RatingKind.criticAggregate,
            scaleMinimum: 0,
            scaleMaximum: 100,
            platformIds: {'psx'},
            minimumVoteCount: 10,
            assessmentReference: 'fixture'),
        throwsArgumentError);
    expect(
        () => AssessedOverallScoreBasis(
            sourceId: 'igdb',
            kind: RatingKind.overallAggregate,
            scaleMinimum: 0,
            scaleMaximum: 100,
            platformIds: {'psx'},
            minimumVoteCount: 0,
            assessmentReference: 'fixture'),
        throwsArgumentError);
  });
}
