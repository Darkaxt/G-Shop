import 'package:xml/xml.dart';
import '../../models/scraped_metadata.dart';
import 'effective_overall_rating.dart';

/// Only provider facts, never launcher settings, paths, credentials or ownership.
const _scrapedFields = {
  'name',
  'desc',
  'rating',
  'releasedate',
  'developer',
  'publisher',
  'genre',
  'players',
};

String _romPath(String input) {
  final value = input.startsWith('./') ? input.substring(2) : input;
  final parts = value.split('/');
  if (value.isEmpty ||
      value.contains(RegExp(r'[:\\\x00-\x1f]')) ||
      parts.any((p) => p.isEmpty || p == '.' || p == '..')) {
    throw const FormatException('An explicit relative ROM mapping is required');
  }
  return './$value';
}

Map<String, String> _fields(Map<String, String> fields) {
  if (!_scrapedFields.containsAll(fields.keys)) {
    throw const FormatException('Unsupported ES-DE scraped field');
  }
  final rating = fields['rating'];
  if (rating != null) {
    final value = double.tryParse(rating);
    if (value == null || !value.isFinite || value < 0 || value > 1) {
      throw const FormatException('ES-DE rating must be between zero and one');
    }
  }
  return Map.unmodifiable(fields);
}

class EsDeMetadataUpdate {
  final String editionId;
  final String relativeRomPath;
  final Map<String, String> fields;
  EsDeMetadataUpdate(
      {required this.editionId,
      required String relativeRomPath,
      required Map<String, String> fields})
      : relativeRomPath = _romPath(relativeRomPath),
        fields = _fields(fields) {
    if (editionId.trim().isEmpty) {
      throw const FormatException('An exact edition is required');
    }
  }
}

/// The last values this integration wrote, not a claim over all gamelist fields.
class EsDeFieldOwnership {
  final String editionId;
  final Map<String, String> fields;
  EsDeFieldOwnership(
      {required this.editionId, required Map<String, String> fields})
      : fields = _fields(fields) {
    if (editionId.trim().isEmpty) {
      throw const FormatException('An exact edition is required');
    }
  }
  Map<String, dynamic> toJson() => {'editionId': editionId, 'fields': fields};
  factory EsDeFieldOwnership.fromJson(Map<String, dynamic> json) =>
      EsDeFieldOwnership(
          editionId: json['editionId'] as String,
          fields: Map<String, String>.from(json['fields'] as Map));
}

class EsDeMetadataConflict {
  final String relativeRomPath;
  final String reason;
  final String? field;
  const EsDeMetadataConflict(this.relativeRomPath, this.reason, [this.field]);
}

class EsDeMetadataProjection {
  /// A bare gamelist number has no original-game label. Keep that richer score
  /// in G-Shop instead of attributing it to translation/audio-patch quality.
  static String? rating(EffectiveOverallRating? overall) =>
      overall?.rankingEligible == true &&
              overall!.ownership != OverallRatingOwnership.originalGame
          ? (overall.rating.normalizedValue / 100).toString()
          : null;

  /// ES-DE stores date-only metadata in its basic timestamp format. An unknown
  /// month/day is not a January-first release. Midnight is format padding, not
  /// an assertion about the release's hour.
  static String? releaseDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}(?:T.+)?$').hasMatch(value) ||
        selectEditionReleaseDate([MetadataText(text: value)],
                regions: const []) ==
            null) {
      return null;
    }
    return '${value.substring(0, 10).replaceAll('-', '')}T000000';
  }

  final String xml;
  final Map<String, EsDeFieldOwnership> ownership;
  final List<EsDeMetadataConflict> conflicts;
  EsDeMetadataProjection._(this.xml, Map<String, EsDeFieldOwnership> ownership,
      List<EsDeMetadataConflict> conflicts)
      : ownership = Map.unmodifiable(ownership),
        conflicts = List.unmodifiable(conflicts);

  /// Pure projection: no filesystem, scraping, install discovery or ROM access.
  /// Caller supplies verified edition/path mappings and coordinates publication
  /// with ES-DE's writer. This result alone is not a completed sync operation.
  static EsDeMetadataProjection merge(
      String? existing, Iterable<EsDeMetadataUpdate> updates,
      {Map<String, EsDeFieldOwnership> previousOwnership = const {}}) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(existing ?? '<gameList/>');
      if (document.rootElement.name.qualified != 'gameList') {
        throw const FormatException('Invalid ES-DE gamelist root');
      }
    } on XmlException {
      throw const FormatException('Invalid ES-DE gamelist XML');
    }
    final root = document.rootElement;
    final ownership = <String, EsDeFieldOwnership>{};
    for (final entry in previousOwnership.entries) {
      final path = _romPath(entry.key);
      if (ownership.containsKey(path)) {
        throw const FormatException('Ambiguous saved ES-DE path ownership');
      }
      ownership[path] = entry.value;
    }
    final games = <String, List<XmlElement>>{};
    final malformedPaths = <String>{};
    for (final game in root.findElements('game')) {
      final paths = game.findElements('path').toList();
      if (paths.length != 1) {
        for (final path in paths) {
          try {
            malformedPaths.add(_romPath(path.innerText));
          } on FormatException {
            // Preserve malformed legacy entries without guessing their mapping.
          }
        }
        continue;
      }
      try {
        games.putIfAbsent(_romPath(paths.single.innerText), () => []).add(game);
      } on FormatException {
        // Unrelated legacy entries remain intact, never guessed into a mapping.
      }
    }
    final requested = <String, List<EsDeMetadataUpdate>>{};
    for (final update in updates) {
      requested.putIfAbsent(update.relativeRomPath, () => []).add(update);
    }
    final conflicts = <EsDeMetadataConflict>[];
    var changed = false;
    for (final entry in requested.entries) {
      final path = entry.key;
      final candidates = games[path] ?? const <XmlElement>[];
      if (entry.value.length != 1 ||
          candidates.length > 1 ||
          malformedPaths.contains(path)) {
        conflicts.add(EsDeMetadataConflict(path, 'ambiguousPath'));
        continue;
      }
      final update = entry.value.single;
      final before = ownership[path];
      if (before != null && before.editionId != update.editionId) {
        conflicts.add(EsDeMetadataConflict(path, 'editionChanged'));
        continue;
      }
      final game =
          candidates.isEmpty ? XmlElement(XmlName('game')) : candidates.single;
      if (candidates.isEmpty) {
        game.children.add(XmlElement(XmlName('path'), [], [XmlText(path)]));
        root.children.add(game);
        changed = true;
      }
      final owned = Map<String, String>.from(before?.fields ?? const {});
      for (final field in update.fields.entries) {
        final elements = game.findElements(field.key).toList();
        final current = elements.isEmpty ? null : elements.first.innerText;
        if (elements.length > 1 ||
            (current != null &&
                current.isNotEmpty &&
                current != before?.fields[field.key])) {
          conflicts.add(EsDeMetadataConflict(path, 'manualField', field.key));
          continue;
        }
        if (current != field.value) {
          final replacement =
              XmlElement(XmlName(field.key), [], [XmlText(field.value)]);
          if (elements.isEmpty) {
            game.children.add(replacement);
          } else {
            game.children[game.children.indexOf(elements.single)] = replacement;
          }
          changed = true;
        }
        owned[field.key] = field.value;
      }
      if (owned.isNotEmpty) {
        ownership[path] =
            EsDeFieldOwnership(editionId: update.editionId, fields: owned);
      }
    }
    return EsDeMetadataProjection._(
        changed || existing == null ? document.toXmlString() : existing,
        ownership,
        conflicts);
  }
}
