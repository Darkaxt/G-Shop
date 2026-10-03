import 'dart:convert';

/// Identifies a provider object independently of its current name or version.
///
/// [sourceId] identifies the configured source and [accountId] the provider's
/// stable account identifier, when that provider has accounts. Neither contains
/// a credential. Provider IDs are opaque and are never case-folded or cleaned.
class RemoteArtifactId {
  final String providerId;
  final String sourceId;
  final String? accountId;
  final String providerFileId;

  RemoteArtifactId({
    required String providerId,
    required String sourceId,
    String? accountId,
    required String providerFileId,
  })  : providerId = _identifier(providerId, 'providerId'),
        sourceId = _identifier(sourceId, 'sourceId'),
        accountId = _optionalIdentifier(accountId, 'accountId'),
        providerFileId = _identifier(providerFileId, 'providerFileId');

  /// JSON tuple encoding prevents delimiter collisions between opaque IDs.
  String get key =>
      jsonEncode([providerId, sourceId, accountId, providerFileId]);

  factory RemoteArtifactId.fromJson(Map<String, dynamic> json) =>
      RemoteArtifactId(
        providerId: json['providerId'] as String,
        sourceId: json['sourceId'] as String,
        accountId: json['accountId'] as String?,
        providerFileId: json['providerFileId'] as String,
      );

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'sourceId': sourceId,
        if (accountId != null) 'accountId': accountId,
        'providerFileId': providerFileId,
      };

  @override
  bool operator ==(Object other) =>
      other is RemoteArtifactId &&
      providerId == other.providerId &&
      sourceId == other.sourceId &&
      accountId == other.accountId &&
      providerFileId == other.providerFileId;

  @override
  int get hashCode =>
      Object.hash(providerId, sourceId, accountId, providerFileId);
}

/// One catalogue snapshot of a remote binary, with no transfer or install state.
class RemoteArtifact {
  final RemoteArtifactId id;
  final String? parentId;
  final String displayPath;
  final String displayName;
  final int? sizeBytes;
  final DateTime? modifiedAt;
  final String? version;

  /// Hashes of the exact provider file bytes, which may be a CHD/ZIP/container.
  /// These must never be promoted implicitly to [EditionMember.rawRomChecksums].
  final Map<String, String> providerChecksums;

  /// Null means the provider has not established download capability.
  final bool? canDownload;

  RemoteArtifact({
    required this.id,
    this.parentId,
    required this.displayPath,
    required this.displayName,
    this.sizeBytes,
    this.modifiedAt,
    this.version,
    Map<String, String> providerChecksums = const {},
    this.canDownload,
  }) : providerChecksums = Map.unmodifiable(providerChecksums) {
    if (sizeBytes != null && sizeBytes! < 0) {
      throw ArgumentError.value(sizeBytes, 'sizeBytes', 'Must be non-negative');
    }
  }

  factory RemoteArtifact.fromJson(Map<String, dynamic> json) => RemoteArtifact(
        id: RemoteArtifactId.fromJson(json['id'] as Map<String, dynamic>),
        parentId: json['parentId'] as String?,
        displayPath: json['displayPath'] as String,
        displayName: json['displayName'] as String,
        sizeBytes: json['sizeBytes'] as int?,
        modifiedAt: json['modifiedAt'] == null
            ? null
            : DateTime.parse(json['modifiedAt'] as String),
        version: json['version'] as String?,
        providerChecksums: _stringMap(json['providerChecksums']),
        canDownload: json['canDownload'] as bool?,
      );

  Map<String, dynamic> toJson() => {
        'id': id.toJson(),
        if (parentId != null) 'parentId': parentId,
        'displayPath': displayPath,
        'displayName': displayName,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (modifiedAt != null)
          'modifiedAt': modifiedAt!.toUtc().toIso8601String(),
        if (version != null) 'version': version,
        'providerChecksums': providerChecksums,
        if (canDownload != null) 'canDownload': canDownload,
      };
}

enum IdentityMatchStatus { unmatched, ambiguous, matched, manuallyMatched }

/// Source-attributed matching or classification evidence, not a rating.
///
/// [kind] describes the actual evidence, such as provider ID, release, patch,
/// raw-ROM checksum, or manual correction. Unknown confidence remains null.
class IdentityEvidence {
  final String source;
  final String kind;
  final String value;
  final double? confidence;

  IdentityEvidence({
    required String source,
    required String kind,
    required String value,
    this.confidence,
  })  : source = _identifier(source, 'source'),
        kind = _identifier(kind, 'kind'),
        value = _identifier(value, 'value') {
    if (confidence != null &&
        (!confidence!.isFinite || confidence! < 0 || confidence! > 1)) {
      throw ArgumentError.value(
          confidence, 'confidence', 'Must be within 0..1');
    }
  }

  factory IdentityEvidence.fromJson(Map<String, dynamic> json) =>
      IdentityEvidence(
        source: json['source'] as String,
        kind: json['kind'] as String,
        value: json['value'] as String,
        confidence: (json['confidence'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'source': source,
        'kind': kind,
        'value': value,
        if (confidence != null) 'confidence': confidence,
      };
}

/// A game or modification project with an explicitly assigned stable identity.
///
/// Callers retain [id] across renames, format conversion, and metadata refresh.
/// Titles, provider candidate IDs, and [baseGameId] never merge records or imply
/// score ownership. An unknown platform remains null for review.
class GameIdentity {
  final String id;
  final String? platformId;
  final String title;

  /// Keys are provider namespaces; values are their opaque game/project IDs.
  final Map<String, String> providerIds;
  final String? baseGameId;
  final IdentityMatchStatus matchStatus;
  final List<IdentityEvidence> evidence;

  GameIdentity({
    required String id,
    String? platformId,
    required this.title,
    Map<String, String> providerIds = const {},
    String? baseGameId,
    this.matchStatus = IdentityMatchStatus.unmatched,
    List<IdentityEvidence> evidence = const [],
  })  : id = _identifier(id, 'id'),
        platformId = _optionalIdentifier(platformId, 'platformId'),
        providerIds = Map.unmodifiable(providerIds),
        baseGameId = _optionalIdentifier(baseGameId, 'baseGameId'),
        evidence = List.unmodifiable(evidence);

  factory GameIdentity.fromJson(Map<String, dynamic> json) => GameIdentity(
        id: json['id'] as String,
        platformId: json['platformId'] as String?,
        title: json['title'] as String,
        providerIds: _stringMap(json['providerIds']),
        baseGameId: json['baseGameId'] as String?,
        matchStatus: IdentityMatchStatus.values.byName(
          json['matchStatus'] as String? ?? IdentityMatchStatus.unmatched.name,
        ),
        evidence: _evidenceList(json['evidence']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (platformId != null) 'platformId': platformId,
        'title': title,
        'providerIds': providerIds,
        if (baseGameId != null) 'baseGameId': baseGameId,
        'matchStatus': matchStatus.name,
        'evidence': evidence.map((item) => item.toJson()).toList(),
      };
}

/// An exact file member of an edition or bundle, optionally a numbered disc.
class EditionMember {
  final RemoteArtifactId artifactId;
  final int? discNumber;
  final String? label;
  final bool requiredForLaunch;

  /// Known raw-ROM hashes from compatible, explicitly verified ROM evidence.
  /// The remote file's provider checksum alone cannot establish these values.
  final Map<String, String> rawRomChecksums;

  EditionMember({
    required this.artifactId,
    this.discNumber,
    this.label,
    this.requiredForLaunch = true,
    Map<String, String> rawRomChecksums = const {},
  }) : rawRomChecksums = Map.unmodifiable(rawRomChecksums) {
    if (discNumber != null && discNumber! < 1) {
      throw ArgumentError.value(discNumber, 'discNumber', 'Must be positive');
    }
  }

  factory EditionMember.fromJson(Map<String, dynamic> json) => EditionMember(
        artifactId: RemoteArtifactId.fromJson(
          json['artifactId'] as Map<String, dynamic>,
        ),
        discNumber: json['discNumber'] as int?,
        label: json['label'] as String?,
        requiredForLaunch: json['requiredForLaunch'] as bool? ?? true,
        rawRomChecksums: _stringMap(json['rawRomChecksums']),
      );

  Map<String, dynamic> toJson() => {
        'artifactId': artifactId.toJson(),
        if (discNumber != null) 'discNumber': discNumber,
        if (label != null) 'label': label,
        'requiredForLaunch': requiredForLaunch,
        'rawRomChecksums': rawRomChecksums,
      };
}

/// A release/revision/patch selected under an explicit [gameId].
///
/// Separate editions may share the game ID. Distinct hack projects have their
/// own game IDs. No relationship is inferred from titles, regions, or tags.
class EditionIdentity {
  static const knownContentTags = {
    'official',
    'Hack',
    'T-Eng',
    'Dub',
    'Undub',
    'Uncensor',
    'homebrew',
    'demo',
    'unknown'
  };
  static const _contentTagAliases = {
    'official': 'official',
    'hack': 'Hack',
    't-eng': 'T-Eng',
    't-en': 'T-Eng',
    'dub': 'Dub',
    'dubbed': 'Dub',
    'undub': 'Undub',
    'undubbed': 'Undub',
    'uncensor': 'Uncensor',
    'uncensored': 'Uncensor',
    'homebrew': 'homebrew',
    'demo': 'demo',
    'unknown': 'unknown'
  };

  /// Interpret known spellings only. Unfamiliar facts remain verbatim; neither
  /// language nor translation status is inferred from normalization.
  static Set<String> normalizeContentTags(Iterable<String> tags) =>
      Set.unmodifiable(tags
          .map((tag) => _contentTagAliases[tag.trim().toLowerCase()] ?? tag));

  final String id;
  final String gameId;
  final Map<String, String> providerIds;
  final String? releaseId;
  final List<String> regions;
  final List<String> languages;
  final String? revision;
  final String? patchId;

  /// Independent canonical tags such as Hack, T-Eng, Dub, Undub and Uncensor.
  /// Empty means unclassified, not an unmodified official release. Classification
  /// provenance belongs in [evidence]; unfamiliar tags are preserved.
  final Set<String> tags;
  final bool? isTranslation;
  final List<String> translatedLanguages;
  final List<EditionMember> members;
  final List<IdentityEvidence> evidence;

  EditionIdentity({
    required String id,
    required String gameId,
    Map<String, String> providerIds = const {},
    this.releaseId,
    List<String> regions = const [],
    List<String> languages = const [],
    this.revision,
    this.patchId,
    Set<String> tags = const {},
    this.isTranslation,
    List<String> translatedLanguages = const [],
    List<EditionMember> members = const [],
    List<IdentityEvidence> evidence = const [],
  })  : id = _identifier(id, 'id'),
        gameId = _identifier(gameId, 'gameId'),
        providerIds = Map.unmodifiable(providerIds),
        regions = List.unmodifiable(regions),
        languages = List.unmodifiable(languages),
        tags = normalizeContentTags(tags),
        translatedLanguages = List.unmodifiable(translatedLanguages),
        members = List.unmodifiable(members),
        evidence = List.unmodifiable(evidence);

  factory EditionIdentity.fromJson(Map<String, dynamic> json) =>
      EditionIdentity(
        id: json['id'] as String,
        gameId: json['gameId'] as String,
        providerIds: _stringMap(json['providerIds']),
        releaseId: json['releaseId'] as String?,
        regions: _strings(json['regions']),
        languages: _strings(json['languages']),
        revision: json['revision'] as String?,
        patchId: json['patchId'] as String?,
        tags: _strings(json['tags']).toSet(),
        isTranslation: json['isTranslation'] as bool?,
        translatedLanguages: _strings(json['translatedLanguages']),
        members: (json['members'] as List? ?? const [])
            .map((item) => EditionMember.fromJson(item as Map<String, dynamic>))
            .toList(),
        evidence: _evidenceList(json['evidence']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'gameId': gameId,
        'providerIds': providerIds,
        if (releaseId != null) 'releaseId': releaseId,
        'regions': regions,
        'languages': languages,
        if (revision != null) 'revision': revision,
        if (patchId != null) 'patchId': patchId,
        'tags': tags.toList()..sort(),
        if (isTranslation != null) 'isTranslation': isTranslation,
        'translatedLanguages': translatedLanguages,
        'members': members.map((item) => item.toJson()).toList(),
        'evidence': evidence.map((item) => item.toJson()).toList(),
      };
}

String _identifier(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty');
  }
  return value;
}

String? _optionalIdentifier(String? value, String name) =>
    value == null ? null : _identifier(value, name);

Map<String, String> _stringMap(Object? value) =>
    (value as Map? ?? const {}).cast<String, String>();

List<String> _strings(Object? value) =>
    (value as List? ?? const []).cast<String>();

List<IdentityEvidence> _evidenceList(Object? value) =>
    (value as List? ?? const [])
        .map((item) => IdentityEvidence.fromJson(item as Map<String, dynamic>))
        .toList();
