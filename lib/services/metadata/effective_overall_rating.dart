import '../../models/library_identity.dart';
import '../../models/scraped_metadata.dart';

enum OverallRatingOwnership { game, originalGame, project }

/// Application-owned conclusion of a recorded META-05 reception assessment.
/// This is deliberately not deserializable from provider/catalogue metadata.
/// The live benchmark establishes precedence, platform coverage, sample support
/// and any unknown-count policy; an API/imported approval flag cannot do so.
class AssessedOverallScoreBasis {
  final String sourceId;
  final RatingKind kind;
  final double scaleMinimum;
  final double scaleMaximum;
  final Set<String> platformIds;
  final int minimumVoteCount;
  final String assessmentReference;
  final String? unknownCountAssessment;

  AssessedOverallScoreBasis({
    required this.sourceId,
    required this.kind,
    required this.scaleMinimum,
    required this.scaleMaximum,
    required Set<String> platformIds,
    required this.minimumVoteCount,
    required this.assessmentReference,
    this.unknownCountAssessment,
  }) : platformIds = Set.unmodifiable(platformIds) {
    if (sourceId.trim().isEmpty ||
        (kind != RatingKind.overallAggregate &&
            kind != RatingKind.communityAggregate &&
            kind != RatingKind.unknownAggregate) ||
        !scaleMinimum.isFinite ||
        !scaleMaximum.isFinite ||
        scaleMaximum <= scaleMinimum ||
        platformIds.isEmpty ||
        platformIds.any((id) => id.trim().isEmpty) ||
        minimumVoteCount < 1 ||
        assessmentReference.trim().isEmpty ||
        (unknownCountAssessment != null &&
            unknownCountAssessment!.trim().isEmpty)) {
      throw ArgumentError('Invalid assessed overall-score basis');
    }
  }
}

/// META-05's recorded assessment, extended for N64/PSP in S7 on 2026-10-05.
/// Use the provider's actual game-level
/// community average, not its one-critic-sensitive blended total. This is a
/// confidence floor, not a confidence interval or a platform-specific critic
/// score. Unsupported scopes/unknown or small samples remain unranked.
final productionOverallScoreBases =
    List<AssessedOverallScoreBasis>.unmodifiable([
  AssessedOverallScoreBasis(
      sourceId: 'igdb',
      kind: RatingKind.communityAggregate,
      scaleMinimum: 0,
      scaleMaximum: 100,
      platformIds: {'psx', 'ps2', 'gba', 'gc', 'switch', 'n64', 'psp'},
      minimumVoteCount: 20,
      assessmentReference:
          'docs/SCORE_RECEPTION_ASSESSMENT.md#igdb-remediation-capture-and-decision'),
]);

/// Exactly one sourced score, never an average or highest-value choice. Preserve
/// provenance/raw scale/count on the same object consumed by display and ranking.
class EffectiveOverallRating {
  final SourcedRating rating;
  final OverallRatingOwnership ownership;
  final bool fresh;
  final String? assessmentReference;
  final String? unknownCountAssessment;

  const EffectiveOverallRating._(
      {required this.rating,
      required this.ownership,
      required this.fresh,
      this.assessmentReference,
      this.unknownCountAssessment});

  bool get rankingEligible => fresh && assessmentReference != null;
}

/// [records] must be current identity-bound cache records, not arbitrary search
/// results. LibraryStore enforces that boundary before calling this selector.
/// Assessed bases are in benchmark-established precedence order; unassessed
/// scores can be displayed but cannot establish any ranked position.
EffectiveOverallRating? selectEffectiveOverallRating({
  required GameIdentity game,
  required EditionIdentity edition,
  required Iterable<MetadataRecord> records,
  GameIdentity? baseGame,
  List<AssessedOverallScoreBasis> assessedBases = const [],
  Set<String> staleProviderIds = const {},
}) {
  if (edition.gameId != game.id ||
      game.platformId == null ||
      game.matchStatus == IdentityMatchStatus.ambiguous) {
    return null;
  }
  final candidates = <({
    MetadataRecord record,
    SourcedRating rating,
    OverallRatingOwnership ownership
  })>[];
  for (final record in records) {
    if (record.gameId != game.id ||
        record.editionId != edition.id ||
        record.platformId != game.platformId ||
        record.refreshGeneration < 0 ||
        record.providerId.trim().isEmpty ||
        record.providerGameId.trim().isEmpty) {
      continue;
    }
    final ownership = metadataOverallOwnership(game, edition, record, baseGame);
    if (ownership == null) continue;
    final relevant = record.ratings
        .where((rating) =>
            rating.sourceId == record.providerId &&
            rating.providerGameId == record.providerGameId &&
            rating.sourceLabel.trim().isNotEmpty &&
            (rating.kind == RatingKind.overallAggregate ||
                (record.providerId == 'screenscraper' &&
                    rating.kind == RatingKind.unknownAggregate) ||
                assessedBases.any((basis) =>
                    basis.sourceId == record.providerId &&
                    basis.kind == rating.kind &&
                    basis.platformIds.contains(game.platformId) &&
                    basis.scaleMinimum == rating.scaleMinimum &&
                    basis.scaleMaximum == rating.scaleMaximum)))
        .toList();
    // A conflicting pair is an unresolved provider response, not permission to
    // choose whichever value is largest (or happened to arrive first).
    for (final rating in relevant) {
      if (relevant.where((r) => r.kind == rating.kind).length != 1) continue;
      candidates.add((record: record, rating: rating, ownership: ownership));
    }
  }

  for (final basis in assessedBases) {
    if (!basis.platformIds.contains(game.platformId)) continue;
    final matching = candidates
        .where((candidate) =>
            candidate.record.providerId == basis.sourceId &&
            candidate.record.refreshGeneration > 0 &&
            !staleProviderIds.contains(candidate.record.providerId) &&
            candidate.rating.kind == basis.kind &&
            candidate.rating.scaleMinimum == basis.scaleMinimum &&
            candidate.rating.scaleMaximum == basis.scaleMaximum)
        .toList();
    if (matching.length != 1) continue;
    final selected = matching.single;
    final count = selected.rating.voteCount;
    if (count == null
        ? basis.unknownCountAssessment == null
        : count < basis.minimumVoteCount) {
      continue;
    }
    return EffectiveOverallRating._(
        rating: selected.rating,
        ownership: selected.ownership,
        fresh: true,
        assessmentReference: basis.assessmentReference,
        unknownCountAssessment:
            count == null ? basis.unknownCountAssessment : null);
  }

  // Candidate-source order is display-only until a recorded assessment supplies
  // accepted precedence. A community average is not an implicit substitute:
  // only the explicit scoped assessment can select it, retaining its real kind.
  for (final fresh in [true, false]) {
    for (final source in ['screenscraper', 'igdb', 'romm']) {
      final matching = candidates
          .where((candidate) =>
              candidate.record.providerId == source &&
              (candidate.record.refreshGeneration > 0 &&
                      !staleProviderIds
                          .contains(candidate.record.providerId)) ==
                  fresh)
          .toList();
      final assessed = matching
          .where((candidate) => assessedBases.any((b) =>
              b.sourceId == source &&
              b.platformIds.contains(game.platformId) &&
              b.kind == candidate.rating.kind &&
              b.scaleMinimum == candidate.rating.scaleMinimum &&
              b.scaleMaximum == candidate.rating.scaleMaximum))
          .toList();
      final display = assessed.isNotEmpty
          ? assessed
          : matching
              .where((c) =>
                  c.rating.kind == RatingKind.overallAggregate ||
                  (source == 'screenscraper' &&
                      c.rating.kind == RatingKind.unknownAggregate))
              .toList();
      if (display.length != 1) continue;
      final selected = display.single;
      return EffectiveOverallRating._(
          rating: selected.rating, ownership: selected.ownership, fresh: fresh);
    }
  }
  return null;
}

/// Verified field ownership, also used for query facets without a rating.
OverallRatingOwnership? metadataOverallOwnership(GameIdentity game,
    EditionIdentity edition, MetadataRecord record, GameIdentity? baseGame) {
  if (game.matchStatus == IdentityMatchStatus.ambiguous ||
      edition.gameId != game.id ||
      record.gameId != game.id ||
      record.editionId != edition.id ||
      game.platformId == null ||
      record.platformId != game.platformId) {
    return null;
  }
  final assigned = game.providerIds[record.providerId];
  final editionAssigned = edition.providerIds[record.providerId];
  if ((assigned != null && assigned != record.providerGameId) ||
      (editionAssigned != null && editionAssigned != record.providerGameId)) {
    return null;
  }
  final verified = game.matchStatus == IdentityMatchStatus.matched ||
      game.matchStatus == IdentityMatchStatus.manuallyMatched;
  final byId = verified && assigned == record.providerGameId;
  if (game.baseGameId != null &&
      (baseGame == null ||
          baseGame.id != game.baseGameId ||
          baseGame.platformId != game.platformId)) {
    return null;
  }
  final project =
      edition.tags.contains('Hack') || edition.tags.contains('homebrew');
  if (project) {
    return !edition.tags.contains('official') &&
            !edition.tags.contains('unknown') &&
            byId &&
            baseGame?.providerIds[record.providerId] != record.providerGameId &&
            record.providerId == 'igdb' &&
            record.matchMethod == 'verifiedProjectId'
        ? OverallRatingOwnership.project
        : null;
  }
  final official = edition.tags.length == 1 &&
      edition.tags.contains('official') &&
      edition.isTranslation != true;
  if (official && game.baseGameId == null) {
    if ((byId &&
            (record.matchMethod == 'verifiedProviderId' ||
                record.matchMethod == 'verifiedProviderIdGlobalGame')) ||
        (record.providerId == 'screenscraper' &&
            record.matchMethod == 'rawRomHashAndSize')) {
      return OverallRatingOwnership.game;
    }
    return null;
  }
  const originalModifications = {'T-Eng', 'Dub', 'Undub', 'Uncensor'};
  final knownModification = edition.tags.isNotEmpty &&
      originalModifications.containsAll(edition.tags) &&
      (!edition.tags.contains('T-Eng') ||
          (edition.isTranslation == true &&
              edition.translatedLanguages.contains('en'))) &&
      (edition.isTranslation != true || edition.tags.contains('T-Eng'));
  // IGDB explicitly supplies a verified global-game score, not patch quality.
  // ScreenScraper currently returns modified editions for review, not scores.
  return knownModification &&
          byId &&
          (game.baseGameId == null ||
              ((baseGame!.matchStatus == IdentityMatchStatus.matched ||
                      baseGame.matchStatus ==
                          IdentityMatchStatus.manuallyMatched) &&
                  baseGame.providerIds[record.providerId] ==
                      record.providerGameId)) &&
          record.providerId == 'igdb' &&
          record.matchMethod == 'verifiedProviderIdGlobalGame'
      ? OverallRatingOwnership.originalGame
      : null;
}
