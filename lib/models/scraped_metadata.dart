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

  ScreenScraperMediaReference(
      {required this.providerGameId,
      required this.providerPlatformId,
      required this.mediaType,
      this.region,
      this.memberIndex}) {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(providerGameId) ||
        providerPlatformId <= 0 ||
        !RegExp(r'^[a-zA-Z0-9]+(?:-[a-zA-Z0-9]+)*$').hasMatch(mediaType) ||
        (region != null && !RegExp(r'^[a-z]{2,3}$').hasMatch(region!)) ||
        (memberIndex != null && (memberIndex! < 1 || region == null))) {
      throw const FormatException('Invalid ScreenScraper media reference');
    }
  }

  String get providerId => 'screenscraper';
  String get mediaSelector =>
      region == null ? mediaType : '$mediaType($region${memberIndex ?? ''})';

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'providerGameId': providerGameId,
        'providerPlatformId': providerPlatformId,
        'mediaType': mediaType,
        'region': region,
        'memberIndex': memberIndex
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
        memberIndex: json['memberIndex'] as int?);
  }
}

class MetadataMedia {
  final String type;
  final String? url;
  final String? region;
  final int? memberIndex;
  final ScreenScraperMediaReference? providerReference;

  MetadataMedia(
      {required this.type,
      this.url,
      this.region,
      this.memberIndex,
      this.providerReference}) {
    if ((url == null) == (providerReference == null) ||
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
          'providerReference': providerReference!.toJson()
      };
  factory MetadataMedia.fromJson(Map<String, dynamic> json) => MetadataMedia(
      type: json['type'] as String,
      url: json['url'] as String?,
      region: json['region'] as String?,
      memberIndex: json['memberIndex'] as int?,
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
    required List<MetadataText> titles,
    List<MetadataText> descriptions = const [],
    List<MetadataText> releaseDates = const [],
    this.developer,
    this.publisher,
    List<MetadataGenre> genres = const [],
    List<MetadataMedia> media = const [],
    List<SourcedRating> ratings = const [],
    Map<String, MetadataFieldProvenance> fieldProvenance = const {},
  })  : titles = List.unmodifiable(titles),
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
