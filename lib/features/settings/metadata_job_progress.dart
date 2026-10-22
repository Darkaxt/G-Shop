import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../services/metadata/metadata_refresh_jobs.dart';

/// Progress through one committed item snapshot, not API requests or coverage.
class MetadataJobProgress extends StatelessWidget {
  final MetadataRefreshReport report;
  const MetadataJobProgress({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final total = report.counts.values.fold(0, (sum, count) => sum + count);
    final pending = report.counts['pending'] ?? 0;
    final processed = total - pending;
    final value = total == 0 ? 0.0 : processed / total;
    // Do not round an unfinished job up to 100%.
    final percent = total == 0 ? 0.0 : (processed * 1000 ~/ total) / 10;
    final numbers = MaterialLocalizations.of(context);
    final text = total == 0
        ? l.metadata_noJobItems
        : l.metadata_itemProgress(
            numbers.formatDecimal(processed),
            numbers.formatDecimal(total),
            NumberFormat('0.#', Localizations.localeOf(context).toString())
                .format(percent),
            numbers.formatDecimal(pending));
    final phase =
        report.kind == 'artwork' ? l.metadata_artwork : l.metadata_scraping;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('$phase · $text', key: const ValueKey('metadata-item-progress')),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              key: const ValueKey('metadata-item-progress-bar'),
              value: value,
              semanticsLabel: '$phase · $text'),
        ]));
  }
}
