/// Provenance-bearing metadata is independent from the anonymous legacy cache.
enum RatingKind {
  criticAggregate,
  communityAggregate,
  unknownAggregate,
  overallAggregate
}

class SourcedRating {
  final String sourceId;
  final String sourceLabel;
  final String providerGameId;
  final String rawValue;
  final double originalValue;
  final double scaleMinimum;
  final double scaleMaximum;
  final int? voteCount;
  final RatingKind kind;
  final DateTime retrievedAt;

  const SourcedRating._({
    required this.sourceId,
    required this.sourceLabel,
    required this.providerGameId,
    required this.rawValue,
    required this.originalValue,
    required this.scaleMinimum,
    required this.scaleMaximum,
    required this.voteCount,
    required this.kind,
    required this.retrievedAt,
  });

  double get normalizedValue =>
      (originalValue - scaleMinimum) * 100 / (scaleMaximum - scaleMinimum);

  /// Provider data and imported JSON cannot approve a reception benchmark.
  /// Ranking requires a separate locally verified META-05 assessment in S4.
  bool get consensusValidated => false;

  static SourcedRating? parse({
    required String sourceId,
    required String sourceLabel,
    required String providerGameId,
    required Object? rawValue,
    required double scaleMinimum,
    required double scaleMaximum,
    int? voteCount,
    required RatingKind kind,
    required DateTime retrievedAt,
  }) {
    if (rawValue is! String && rawValue is! num) {
      return null;
    }
    final raw = rawValue.toString();
    final value = double.tryParse(raw.trim());
    if (sourceId.isEmpty ||
        providerGameId.isEmpty ||
        value == null ||
        !value.isFinite ||
        !scaleMinimum.isFinite ||
        !scaleMaximum.isFinite ||
        scaleMaximum <= scaleMinimum ||
        value < scaleMinimum ||
        value > scaleMaximum) {
      return null;
    }
    return SourcedRating._(
        sourceId: sourceId,
        sourceLabel: sourceLabel,
        providerGameId: providerGameId,
        rawValue: raw,
        originalValue: value,
        scaleMinimum: scaleMinimum,
        scaleMaximum: scaleMaximum,
        voteCount: voteCount != null && voteCount >= 0 ? voteCount : null,
        kind: kind,
        retrievedAt: retrievedAt.toUtc());
  }

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'sourceLabel': sourceLabel,
        'providerGameId': providerGameId,
        'rawValue': rawValue,
        'scaleMinimum': scaleMinimum,
        'scaleMaximum': scaleMaximum,
        'voteCount': voteCount,
        'kind': kind.name,
        'retrievedAt': retrievedAt.toIso8601String(),
      };

  factory SourcedRating.fromJson(Map<String, dynamic> json) =>
      parse(
        sourceId: json['sourceId'] as String,
        sourceLabel: json['sourceLabel'] as String,
        providerGameId: json['providerGameId'] as String,
        rawValue: json['rawValue'],
        scaleMinimum: (json['scaleMinimum'] as num).toDouble(),
        scaleMaximum: (json['scaleMaximum'] as num).toDouble(),
        voteCount: json['voteCount'] as int?,
        kind: RatingKind.values.firstWhere((kind) => kind.name == json['kind'],
            orElse: () => RatingKind.unknownAggregate),
        retrievedAt: DateTime.parse(json['retrievedAt'] as String),
      ) ??
      (throw const FormatException('Invalid sourced rating'));
}

class MetadataFieldProvenance {
  final String providerId;
  final String providerGameId;
  final String field;
  final DateTime retrievedAt;

  const MetadataFieldProvenance(
      {required this.providerId,
      required this.providerGameId,
      required this.field,
      required this.retrievedAt});

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'providerGameId': providerGameId,
        'field': field,
        'retrievedAt': retrievedAt.toUtc().toIso8601String()
      };

  factory MetadataFieldProvenance.fromJson(Map<String, dynamic> json) =>
      MetadataFieldProvenance(
          providerId: json['providerId'] as String,
          providerGameId: json['providerGameId'] as String,
          field: json['field'] as String,
          retrievedAt: DateTime.parse(json['retrievedAt'] as String));
}

/// The provider's region/language remains attached to each localized field.
class MetadataText {
  final String text;
  final String? language;
  final String? region;
  const MetadataText({required this.text, this.language, this.region});
  Map<String, dynamic> toJson() =>
      {'text': text, 'language': language, 'region': region};
  factory MetadataText.fromJson(Map<String, dynamic> json) => MetadataText(
      text: json['text'] as String,
      language: json['language'] as String?,
      region: json['region'] as String?);
}

/// A release belongs to an edition's region, not its UI language. Conflicting
/// regional facts are unresolved; a provider's unqualified global date is only
/// a fallback when there is no exact regional response. Preserve partial
/// precision for display rather than inventing the first day of a year/month.
String? selectEditionReleaseDate(List<MetadataText> dates,
    {required List<String> regions}) {
  String region(String value) {
    final normalized = value.trim().toLowerCase();
    return const {
          'usa': 'us',
          'europe': 'eu',
          'japan': 'jp',
          'world': 'wor'
        }[normalized] ??
        normalized;
  }

  bool valid(String text) {
    final match =
        RegExp(r'^(\d{4})(?:-(\d{2})(?:-(\d{2})(?:T.+)?)?)?$').firstMatch(text);
    if (match == null || int.parse(match[1]!) < 1) return false;
    final month = match[2] == null ? 1 : int.parse(match[2]!);
    final day = match[3] == null ? 1 : int.parse(match[3]!);
    final date = DateTime.utc(int.parse(match[1]!), month, day);
    if (date.year != int.parse(match[1]!) ||
        date.month != month ||
        date.day != day) {
      return false;
    }
    return !text.contains('T') || DateTime.tryParse(text) != null;
  }

  final wanted = regions.map(region).toSet();
  final exact = dates
      .where((value) =>
          value.region != null && wanted.contains(region(value.region!)))
      .toList();
  final candidates = exact.isNotEmpty
      ? exact
      : dates.where(
          (value) => value.region == null || value.region!.trim().isEmpty);
  final values = candidates.map((value) => value.text.trim()).toSet();
  return values.length == 1 && valid(values.single) ? values.single : null;
}

class MetadataGenre {
  final String providerGenreId;
  final List<MetadataText> names;
  MetadataGenre(
      {required this.providerGenreId, required List<MetadataText> names})
      : names = List.unmodifiable(names);
  Map<String, dynamic> toJson() => {
        'providerGenreId': providerGenreId,
        'names': names.map((value) => value.toJson()).toList()
      };
  factory MetadataGenre.fromJson(Map<String, dynamic> json) => MetadataGenre(
      providerGenreId: json['providerGenreId'] as String,
      names: _records(json['names'], MetadataText.fromJson));
}

/// A credential-free selector for the fixed ScreenScraper game-image endpoint.
/// The S4 media resolver supplies current credentials at request time. This is
/// neither an authenticated URL nor permission to fetch an arbitrary endpoint.
class ScreenScraperMediaReference {
  final String providerGameId;
  final int providerPlatformId;
  final String mediaType;
  final String? region;

  /// ScreenScraper appends disc/page numbers to the region in a media selector.
  final int? memberIndex;

  /// Current API support selectors use `(eu)[1]`; older selectors use `(eu1)`.
  /// Preserve the returned wire form without changing legacy cache identities.
  final bool bracketedMemberIndex;

  ScreenScraperMediaReference(
      {required this.providerGameId,
      required this.providerPlatformId,
      required this.mediaType,
      this.region,
      this.memberIndex,
      this.bracketedMemberIndex = false}) {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(providerGameId) ||
        providerPlatformId <= 0 ||
        !RegExp(r'^[a-zA-Z0-9]+(?:-[a-zA-Z0-9]+)*$').hasMatch(mediaType) ||
        (region != null && !RegExp(r'^[a-z]{2,3}$').hasMatch(region!)) ||
        (memberIndex != null && (memberIndex! < 1 || region == null)) ||
        (bracketedMemberIndex && memberIndex == null)) {
      throw const FormatException('Invalid ScreenScraper media reference');
    }
  }

  String get providerId => 'screenscraper';
  String get mediaSelector => region == null
      ? mediaType
      : '$mediaType($region${bracketedMemberIndex ? '' : memberIndex ?? ''})'
          '${bracketedMemberIndex ? '[$memberIndex]' : ''}';

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'providerGameId': providerGameId,
        'providerPlatformId': providerPlatformId,
        'mediaType': mediaType,
        'region': region,
        'memberIndex': memberIndex,
        if (bracketedMemberIndex) 'bracketedMemberIndex': true,
      };

  factory ScreenScraperMediaReference.fromJson(Map<String, dynamic> json) {
    if (json['providerId'] != 'screenscraper') {
      throw const FormatException('Unsupported metadata media reference');
    }
    return ScreenScraperMediaReference(
        providerGameId: json['providerGameId'] as String,
        providerPlatformId: json['providerPlatformId'] as int,
        mediaType: json['mediaType'] as String,
        region: json['region'] as String?,
        memberIndex: json['memberIndex'] as int?,
        bracketedMemberIndex: json['bracketedMemberIndex'] as bool? ?? false);
  }
}

/// Classified local preparation, never an arbitrary on-device file path.
/// Normalized bytes are bound by digest; source/edition evidence stays with them.
class ImportedArtworkReference {
  final String sourceId, assetId, sourceUrl, sha256;
  final String? sourceSha256;
  final List<int>? panel;
  final int rotationDegrees;
  final String? sourceRegion, reconstruction;
  final List<String>? sourceLanguages;
  final Map<String, dynamic>? colourCorrection;
  ImportedArtworkReference(
      {required this.sourceId,
      required this.assetId,
      required this.sourceUrl,
      required this.sha256,
      this.sourceSha256,
      this.sourceRegion,
      this.reconstruction,
      Map<String, dynamic>? colourCorrection,
      List<String>? sourceLanguages,
      List<int>? panel,
      this.rotationDegrees = 0})
      : colourCorrection = colourCorrection == null
            ? null
            : Map.unmodifiable(colourCorrection),
        panel = panel == null ? null : List.unmodifiable(panel),
        sourceLanguages = sourceLanguages == null
            ? null
            : List.unmodifiable(sourceLanguages) {
    if (!_validColourCorrection(colourCorrection) ||
        !{0, 90, 180, 270}.contains(rotationDegrees) ||
        sourceRegion != null &&
            !RegExp(r'^[a-z]{2,3}$').hasMatch(sourceRegion!) ||
        sourceLanguages != null &&
            (sourceLanguages.isEmpty ||
                sourceLanguages
                    .any((l) => !RegExp(r'^[a-z]{2,3}$').hasMatch(l))) ||
        reconstruction != null &&
            (sourceRegion == null ||
                !{'regionalPackaging', 'composite'}.contains(reconstruction)) ||
        !{'launchbox', 'nintandbox', 'screenscraper'}.contains(sourceId) ||
        assetId.isEmpty ||
        assetId.length > 1024 ||
        !MetadataMedia.isSafeDirectUrl(sourceUrl) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
        sourceSha256 != null &&
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceSha256!) ||
        panel != null &&
            (panel.length != 4 ||
                panel.any((v) => v < 0) ||
                panel[2] == 0 ||
                panel[3] == 0)) {
      throw const FormatException('Invalid imported artwork provenance');
    }
  }
  static bool _validColourCorrection(Map<String, dynamic>? value) {
    if (value == null) return true;
    final matrix = value['matrix'];
    final before = value['errorBefore'], after = value['errorAfter'];
    return value['method'] == 'rgb-affine-v1' &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch('${value['referenceSha256']}') &&
        {'screenscraper', 'nintandbox', 'launchbox'}
            .contains(value['referenceSourceId']) &&
        matrix is List &&
        matrix.length == 4 &&
        matrix.every((row) =>
            row is List &&
            row.length == 3 &&
            row.every((n) => n is num && n.isFinite && n.abs() <= 8)) &&
        before is num &&
        before.isFinite &&
        before > 0 &&
        before <= 2 &&
        after is num &&
        after.isFinite &&
        after >= 0 &&
        after <= before * .8;
  }

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'assetId': assetId,
        'sourceUrl': sourceUrl,
        'sha256': sha256,
        if (sourceSha256 != null) 'sourceSha256': sourceSha256,
        if (panel != null) 'panel': panel,
        if (rotationDegrees != 0) 'rotationDegrees': rotationDegrees,
        if (sourceRegion != null) 'sourceRegion': sourceRegion,
        if (reconstruction != null) 'reconstruction': reconstruction,
        if (sourceLanguages != null) 'sourceLanguages': sourceLanguages,
        if (colourCorrection != null) 'colourCorrection': colourCorrection,
      };
  factory ImportedArtworkReference.fromJson(Map<String, dynamic> json) =>
      ImportedArtworkReference(
          sourceId: json['sourceId'] as String,
          assetId: json['assetId'] as String,
          sourceUrl: json['sourceUrl'] as String,
          sha256: json['sha256'] as String,
          sourceSha256: json['sourceSha256'] as String?,
          sourceRegion: json['sourceRegion'] as String?,
          reconstruction: json['reconstruction'] as String?,
          colourCorrection:
              (json['colourCorrection'] as Map?)?.cast<String, dynamic>(),
          sourceLanguages: (json['sourceLanguages'] as List?)?.cast<String>(),
          panel: (json['panel'] as List?)?.cast<int>(),
          rotationDegrees: json['rotationDegrees'] as int? ?? 0);
}

class MetadataMedia {
  final String type;
  final String? url;
  final String? region;
  final int? memberIndex;
  final ScreenScraperMediaReference? providerReference;
  final ImportedArtworkReference? importReference;

  MetadataMedia(
      {required this.type,
      this.url,
      this.region,
      this.memberIndex,
      this.providerReference,
      this.importReference}) {
    if ([url, providerReference, importReference]
                .where((v) => v != null)
                .length !=
            1 ||
        (url != null && !isSafeDirectUrl(url!)) ||
        (providerReference != null &&
            (providerReference!.mediaType != type ||
                providerReference!.region != region ||
                providerReference!.memberIndex != memberIndex))) {
      throw const FormatException('Invalid metadata media location');
    }
  }

  /// Exported/cached direct URLs cannot contain account/application credentials.
  /// Authenticated ScreenScraper API images must use [providerReference].
  static bool isSafeDirectUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.host == 'api.screenscraper.fr' ||
        ((uri.host == 'screenscraper.fr' ||
                uri.host.endsWith('.screenscraper.fr')) &&
            uri.path.startsWith('/api2/'))) {
      return false;
    }
    return !uri.queryParameters.keys.any((key) => RegExp(
            r'password|secret|token|^ssid$|^devid$|^key$|api.?key',
            caseSensitive: false)
        .hasMatch(key));
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (url != null) 'url': url,
        'region': region,
        if (memberIndex != null) 'memberIndex': memberIndex,
        if (providerReference != null)
          'providerReference': providerReference!.toJson(),
        if (importReference != null)
          'importReference': importReference!.toJson()
      };
  factory MetadataMedia.fromJson(Map<String, dynamic> json) => MetadataMedia(
      type: json['type'] as String,
      url: json['url'] as String?,
      region: json['region'] as String?,
      memberIndex: json['memberIndex'] as int?,
      importReference: json['importReference'] == null
          ? null
          : ImportedArtworkReference.fromJson(
              json['importReference'] as Map<String, dynamic>),
      providerReference: json['providerReference'] == null
          ? null
          : ScreenScraperMediaReference.fromJson(
              json['providerReference'] as Map<String, dynamic>));
}

class MetadataRecord {
  final String gameId;
  final String editionId;
  final String platformId;
  final String providerId;
  final String providerGameId;
  final DateTime retrievedAt;
  final int refreshGeneration;
  final String matchMethod;
  final Map<String, dynamic> matchEvidence;
  final List<MetadataText> titles;
  final List<MetadataText> descriptions;
  final List<MetadataText> releaseDates;
  final String? developer;
  final String? publisher;
  final List<MetadataGenre> genres;
  final List<MetadataMedia> media;
  final List<SourcedRating> ratings;
  final Map<String, MetadataFieldProvenance> fieldProvenance;

  MetadataRecord({
    required this.gameId,
    required this.editionId,
    required this.platformId,
    required this.providerId,
    required this.providerGameId,
    required this.retrievedAt,
    required this.refreshGeneration,
    required this.matchMethod,
    Map<String, dynamic> matchEvidence = const {},
    required List<MetadataText> titles,
    List<MetadataText> descriptions = const [],
    List<MetadataText> releaseDates = const [],
    this.developer,
    this.publisher,
    List<MetadataGenre> genres = const [],
    List<MetadataMedia> media = const [],
    List<SourcedRating> ratings = const [],
    Map<String, MetadataFieldProvenance> fieldProvenance = const {},
  })  : matchEvidence = Map.unmodifiable(matchEvidence),
        titles = List.unmodifiable(titles),
        descriptions = List.unmodifiable(descriptions),
        releaseDates = List.unmodifiable(releaseDates),
        genres = List.unmodifiable(genres),
        media = List.unmodifiable(media),
        ratings = List.unmodifiable(ratings),
        fieldProvenance = Map.unmodifiable(fieldProvenance);

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'editionId': editionId,
        'platformId': platformId,
        'providerId': providerId,
        'providerGameId': providerGameId,
        'retrievedAt': retrievedAt.toUtc().toIso8601String(),
        'refreshGeneration': refreshGeneration,
        'matchMethod': matchMethod,
        if (matchEvidence.isNotEmpty) 'matchEvidence': matchEvidence,
        'titles': titles.map((value) => value.toJson()).toList(),
        'descriptions': descriptions.map((value) => value.toJson()).toList(),
        'releaseDates': releaseDates.map((value) => value.toJson()).toList(),
        'developer': developer,
        'publisher': publisher,
        'genres': genres.map((value) => value.toJson()).toList(),
        'media': media.map((value) => value.toJson()).toList(),
        'ratings': ratings.map((value) => value.toJson()).toList(),
        'fieldProvenance':
            fieldProvenance.map((key, value) => MapEntry(key, value.toJson())),
      };

  /// This reconstructs cached facts, not match or ranking authorization.
  factory MetadataRecord.fromJson(Map<String, dynamic> json) => MetadataRecord(
        gameId: json['gameId'] as String,
        editionId: json['editionId'] as String,
        platformId: json['platformId'] as String,
        providerId: json['providerId'] as String,
        providerGameId: json['providerGameId'] as String,
        retrievedAt: DateTime.parse(json['retrievedAt'] as String),
        refreshGeneration: json['refreshGeneration'] as int,
        matchMethod: json['matchMethod'] as String,
        matchEvidence:
            json['matchEvidence'] as Map<String, dynamic>? ?? const {},
        titles: _records(json['titles'], MetadataText.fromJson),
        descriptions: _records(json['descriptions'], MetadataText.fromJson),
        releaseDates: _records(json['releaseDates'], MetadataText.fromJson),
        developer: json['developer'] as String?,
        publisher: json['publisher'] as String?,
        genres: _records(json['genres'], MetadataGenre.fromJson),
        media: _records(json['media'], MetadataMedia.fromJson),
        ratings: _records(json['ratings'], SourcedRating.fromJson),
        fieldProvenance: (json['fieldProvenance'] as Map<String, dynamic>).map(
            (key, value) => MapEntry(
                key,
                MetadataFieldProvenance.fromJson(
                    value as Map<String, dynamic>))),
      );
}

List<T> _records<T>(Object? input, T Function(Map<String, dynamic>) parse) =>
    (input as List).map((item) => parse(item as Map<String, dynamic>)).toList();
