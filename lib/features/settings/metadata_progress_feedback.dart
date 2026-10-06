import 'dart:async';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;

import '../../l10n/app_localizations.dart';
import '../../services/metadata/metadata_provider.dart';
import '../../services/metadata/metadata_refresh_jobs.dart';
import '../../widgets/media_cover_fallback.dart';

/// A display clock, never a worker, request scheduler or cancellation lease.
class MetadataProgressFeedback extends StatefulWidget {
  final MetadataRefreshReport report;
  const MetadataProgressFeedback({super.key, required this.report});

  @override
  State<MetadataProgressFeedback> createState() =>
      _MetadataProgressFeedbackState();
}

class _MetadataProgressFeedbackState extends State<MetadataProgressFeedback> {
  Timer? _clock;
  MetadataProcessedGame? _shown;

  MetadataProcessedGame? get _latest {
    final game = widget.report.lastProcessed;
    return game?.jobId == widget.report.id &&
            game?.providerId == widget.report.providerId
        ? game
        : null;
  }

  @override
  void initState() {
    super.initState();
    _shown = _latest;
    _updateClock();
  }

  @override
  void didUpdateWidget(covariant MetadataProgressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report.id != widget.report.id ||
        oldWidget.report.providerId != widget.report.providerId ||
        widget.report.state != 'running') {
      _shown = _latest;
    }
    _updateClock();
  }

  void _updateClock() {
    if (widget.report.state != 'running') {
      _clock?.cancel();
      _clock = null;
      return;
    }
    _clock ??= Timer.periodic(const Duration(seconds: 3), (_) {
      // Only the latest pending value is retained by the widget configuration.
      if (_shown != _latest) setState(() => _shown = _latest);
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final game = _shown;
    final observation = widget.report.quotaObservation;
    final quota = observation?.quota;
    final localizations = MaterialLocalizations.of(context);
    final observed = observation?.observedAt.toLocal();
    final bytes = game?.coverBytes;
    final descriptions = game?.previewDescriptions ?? const [];
    final language = Localizations.localeOf(context).languageCode;
    final description =
        descriptions.where((v) => v.language == language).firstOrNull ??
            descriptions.where((v) => v.language == 'en').firstOrNull ??
            descriptions.where((v) => v.language == null).firstOrNull ??
            descriptions.firstOrNull;
    // Decode once at display time; stored/provider facts remain unchanged.
    // Literal markup stays plain text and cannot load media or execute HTML.
    final synopsis = description == null
        ? null
        : html
            .parseFragment(description.text
                .replaceAll('<', '&lt;')
                .replaceAll('>', '&gt;'))
            .text;
    final outcome = game == null
        ? null
        : switch (game.status) {
            MetadataLookupStatus.matched => l.metadata_matched,
            MetadataLookupStatus.needsReview => l.metadata_unverifiedCandidate,
            MetadataLookupStatus.ambiguous => l.metadata_ambiguous,
            MetadataLookupStatus.unmatched => l.metadata_unmatched,
            _ => l.metadata_failed,
          };
    return Padding(
      key: const ValueKey('metadata-progress-feedback'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (game != null) ...[
          Text(l.metadata_latestGame,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 96,
                height: 112,
                child: bytes == null
                    ? MediaCoverFallback(systemId: game.platformId)
                    : Image.memory(bytes,
                        fit: BoxFit.contain,
                        cacheWidth: 128,
                        gaplessPlayback: false,
                        errorBuilder: (_, __, ___) =>
                            MediaCoverFallback(systemId: game.platformId))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(game.title,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text('${game.platformId.toUpperCase()} · $outcome'),
                  if (game.candidateTitle != null) Text(game.candidateTitle!),
                  if (game.status == MetadataLookupStatus.needsReview)
                    Text(l.metadata_unverifiedCandidate),
                  if (description != null) ...[
                    const SizedBox(height: 8),
                    Text(synopsis ?? '',
                        maxLines: 4, overflow: TextOverflow.ellipsis),
                  ],
                ])),
          ]),
        ],
        if (widget.report.providerId == 'screenscraper') ...[
          const SizedBox(height: 8),
          Text('ScreenScraper · ${l.metadata_dailyQuota}',
              style: Theme.of(context).textTheme.titleSmall),
          Text('${l.metadata_requestsRemaining}: '
              '${observation?.remaining ?? l.metadata_quotaUnknown} / '
              '${quota?.maxRequestsPerDay ?? l.metadata_quotaUnknown}'),
          Text('${l.metadata_requestsUsed}: '
              '${quota?.requestsToday ?? l.metadata_quotaUnknown}'),
          if (quota?.maxUnmatchedPerDay != null ||
              quota?.unmatchedToday != null)
            Text('${l.metadata_failedRequestsRemaining}: '
                '${observation?.unmatchedRemaining ?? l.metadata_quotaUnknown} / '
                '${quota?.maxUnmatchedPerDay ?? l.metadata_quotaUnknown}'),
          if (observed != null)
            Text('${l.metadata_quotaObserved}: '
                '${localizations.formatFullDate(observed)} '
                '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(observed))}'),
          if (observation?.reservedRemaining != null)
            Text(
                '${l.metadata_localBudget}: ${observation!.reservedRemaining}'),
        ],
      ]),
    );
  }
}
