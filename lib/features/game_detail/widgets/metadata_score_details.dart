import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/metadata/effective_overall_rating.dart';

/// The same identity-bound score used by the cover and collection query.
/// Compact details retain the full explanation in their accessible tooltip.
class MetadataScoreDetails extends StatelessWidget {
  final EffectiveOverallRating score;
  final bool compact;
  const MetadataScoreDetails(
      {super.key, required this.score, this.compact = false});

  String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final rating = score.rating;
    final ownership = switch (score.ownership) {
      OverallRatingOwnership.game => l.metadata_gameScore,
      OverallRatingOwnership.originalGame => l.metadata_originalGame,
      OverallRatingOwnership.project => l.metadata_projectScore,
    };
    final states = [
      ownership,
      if (!score.fresh) l.metadata_staleScore,
      if (score.fresh && !score.rankingEligible) l.metadata_advisoryScore
    ];
    final explanation = l.metadata_scoreDetails(
        rating.sourceLabel,
        _number(rating.normalizedValue),
        rating.rawValue,
        _number(rating.scaleMinimum),
        _number(rating.scaleMaximum),
        rating.voteCount?.toString() ?? l.metadata_unknownCount,
        rating.retrievedAt.toIso8601String().split('T').first);
    final label = '$explanation ${states.join(' · ')}';
    return Semantics(
        label: label,
        child: ExcludeSemantics(
            child: Tooltip(
          message: label,
          child: Text(
            compact
                ? '${rating.sourceLabel} ${_number(rating.normalizedValue)}/100 · ${states.join(' · ')}'
                : label,
            key: const ValueKey('metadata-score-details'),
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: compact ? 11 : 13,
                height: 1.4),
          ),
        )));
  }
}
