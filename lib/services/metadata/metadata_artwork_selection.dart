import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../models/scraped_metadata.dart';

String metadataMediaKey(MetadataMedia media) => sha256
    .convert(utf8.encode(jsonEncode([media.toJson(), 'png-1024-v1'])))
    .toString();

List<MetadataMedia> metadataPhysicalLabels(MetadataRecord record,
    {Iterable<String> regions = const []}) {
  String normalized(String value) => switch (value.trim().toLowerCase()) {
        'usa' => 'us',
        'europe' => 'eu',
        'japan' || 'japon' => 'jp',
        'world' => 'wor',
        'france' => 'fr',
        _ => value.trim().toLowerCase()
      };
  final explicit =
      regions.map(normalized).where((v) => v.isNotEmpty && v != 'wor').toSet();
  final evidence = record.matchEvidence['region'];
  if (explicit.isEmpty && evidence is String && normalized(evidence) != 'wor') {
    explicit.add(normalized(evidence));
  }
  // Repeated selectors identify the same cached body, not another physical
  // edition. Keep distinct same-region alternatives unresolved below.
  final labelsByKey = <String, MetadataMedia>{};
  for (final media in record.media) {
    if (media.type == 'support-texture') {
      labelsByKey.putIfAbsent(metadataMediaKey(media), () => media);
    }
  }
  final labels = labelsByKey.values.toList();
  final preferred = explicit.isNotEmpty
      ? [...explicit, 'wor', '']
      : ['wor', '', 'us', 'eu', 'jp'];
  List<MetadataMedia> selected = [];
  for (final region in preferred) {
    selected =
        labels.where((m) => normalized(m.region ?? '') == region).toList();
    if (selected.isNotEmpty) break;
  }
  if (selected.isEmpty && explicit.isEmpty && labels.length == 1) {
    selected = labels;
  }
  if (selected.length <= 1) return selected;
  if (selected.every((m) => m.memberIndex != null) &&
      selected.map((m) => m.memberIndex).toSet().length == selected.length) {
    return selected;
  }
  return const [];
}
