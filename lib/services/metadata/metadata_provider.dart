import 'package:dio/dio.dart';

import '../../models/scraped_metadata.dart';

enum RomIdentifierKind { rawRom, rawIso, container }

class MetadataRomIdentifier {
  final RomIdentifierKind kind;
  final String filename;
  final int sizeBytes;
  final String? crc32;
  final String? md5;
  final String? sha1;
  const MetadataRomIdentifier({
    required this.kind,
    required this.filename,
    required this.sizeBytes,
    this.crc32,
    this.md5,
    this.sha1,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'filename': filename,
        'sizeBytes': sizeBytes,
        'crc32': crc32,
        'md5': md5,
        'sha1': sha1,
      };

  factory MetadataRomIdentifier.fromJson(Map<String, dynamic> json) {
    const allowedKeys = {
      'kind',
      'filename',
      'sizeBytes',
      'crc32',
      'md5',
      'sha1'
    };
    _rejectUnexpectedKeys(json, allowedKeys, 'ROM identifier');
    final kindName = _requiredString(json, 'kind', 'ROM identifier');
    final kind =
        RomIdentifierKind.values.where((value) => value.name == kindName);
    if (kind.isEmpty) {
      throw FormatException('Invalid ROM identifier kind.');
    }
    final sizeBytes = json['sizeBytes'];
    if (sizeBytes is! int || sizeBytes < 0) {
      throw FormatException('ROM identifier sizeBytes must be nonnegative.');
    }
    return MetadataRomIdentifier(
      kind: kind.single,
      filename: _requiredString(json, 'filename', 'ROM identifier'),
      sizeBytes: sizeBytes,
      crc32: _optionalString(json, 'crc32', 'ROM identifier'),
      md5: _optionalString(json, 'md5', 'ROM identifier'),
      sha1: _optionalString(json, 'sha1', 'ROM identifier'),
    );
  }
}

class MetadataLookupRequest {
  final String gameId;
  final String editionId;
  final String platformId;
  final String title;

  /// Only a previously verified/manual-corrected ID from the local identity
  /// layer belongs here. Imported provider claims are candidate evidence only.
  final String? verifiedProviderGameId;
  final String? baseProviderGameId;
  final Set<String> contentTags;
  final String? region;
  final String? language;
  final String? revision;
  final MetadataRomIdentifier? romIdentifier;
  final int refreshGeneration;

  MetadataLookupRequest({
    required this.gameId,
    required this.editionId,
    required this.platformId,
    required this.title,
    this.verifiedProviderGameId,
    this.baseProviderGameId,
    Set<String> contentTags = const {},
    this.region,
    this.language,
    this.revision,
    this.romIdentifier,
    required this.refreshGeneration,
  }) : contentTags = Set.unmodifiable(List<String>.of(contentTags)..sort());

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'editionId': editionId,
        'platformId': platformId,
        'title': title,
        'verifiedProviderGameId': verifiedProviderGameId,
        'baseProviderGameId': baseProviderGameId,
        'contentTags': contentTags.toList(),
        'region': region,
        'language': language,
        'revision': revision,
        'romIdentifier': romIdentifier?.toJson(),
        'refreshGeneration': refreshGeneration,
      };

  factory MetadataLookupRequest.fromJson(Map<String, dynamic> json) {
    const allowedKeys = {
      'gameId',
      'editionId',
      'platformId',
      'title',
      'verifiedProviderGameId',
      'baseProviderGameId',
      'contentTags',
      'region',
      'language',
      'revision',
      'romIdentifier',
      'refreshGeneration',
    };
    _rejectUnexpectedKeys(json, allowedKeys, 'metadata lookup request');
    final tags = json['contentTags'];
    if (tags is! List ||
        tags.any((tag) => tag is! String || tag.trim().isEmpty)) {
      throw FormatException(
          'Metadata lookup request contentTags must be strings.');
    }
    final tagSet = tags.cast<String>().toSet();
    if (tagSet.length != tags.length) {
      throw FormatException(
          'Metadata lookup request contentTags must be unique.');
    }
    final generation = json['refreshGeneration'];
    if (generation is! int || generation < 0) {
      throw FormatException(
          'Metadata lookup request refreshGeneration must be nonnegative.');
    }
    final identifierValue = json['romIdentifier'];
    if (identifierValue != null && identifierValue is! Map<String, dynamic>) {
      throw FormatException(
          'Metadata lookup request romIdentifier must be an object.');
    }
    return MetadataLookupRequest(
      gameId: _requiredString(json, 'gameId', 'metadata lookup request'),
      editionId: _requiredString(json, 'editionId', 'metadata lookup request'),
      platformId:
          _requiredString(json, 'platformId', 'metadata lookup request'),
      title: _requiredString(json, 'title', 'metadata lookup request'),
      verifiedProviderGameId: _optionalString(
          json, 'verifiedProviderGameId', 'metadata lookup request'),
      baseProviderGameId: _optionalString(
          json, 'baseProviderGameId', 'metadata lookup request'),
      contentTags: tagSet,
      region: _optionalString(json, 'region', 'metadata lookup request'),
      language: _optionalString(json, 'language', 'metadata lookup request'),
      revision: _optionalString(json, 'revision', 'metadata lookup request'),
      romIdentifier: identifierValue == null
          ? null
          : MetadataRomIdentifier.fromJson(identifierValue),
      refreshGeneration: generation,
    );
  }

  MetadataLookupRequest withRefreshGeneration(int generation) {
    if (generation < 0) {
      throw ArgumentError.value(
          generation, 'generation', 'must be nonnegative');
    }
    return MetadataLookupRequest.fromJson(
        {...toJson(), 'refreshGeneration': generation});
  }
}

String _requiredString(Map<String, dynamic> json, String key, String subject) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$subject $key must be a nonempty string.');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key, String subject) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException(
        '$subject $key must be a nonempty string when present.');
  }
  return value;
}

void _rejectUnexpectedKeys(
    Map<String, dynamic> json, Set<String> allowedKeys, String subject) {
  if (json.keys.any((key) => !allowedKeys.contains(key))) {
    throw FormatException('$subject contains unsupported persisted fields.');
  }
}

enum MetadataLookupStatus {
  matched,
  needsReview,
  ambiguous,
  unmatched,
  unsupportedPlatform,
  invalidRequest,
  setupRequired,
  authenticationRequired,
  developerAccessRequired,
  quotaExceeded,
  throttled,
  unavailable,
  invalidResponse,
  cancelled,
}

class MetadataProviderCapabilities {
  final Set<String> fields;
  final bool verifiedIdLookup;
  final bool rawRomLookup;
  final bool titleSearch;
  final bool documentedVoteCounts;
  final int defaultConcurrency;
  const MetadataProviderCapabilities(
      {required this.fields,
      required this.verifiedIdLookup,
      required this.rawRomLookup,
      required this.titleSearch,
      required this.documentedVoteCounts,
      this.defaultConcurrency = 1});
}

class MetadataQuota {
  final int? maxThreads;
  final int? requestsToday;
  final int? maxRequestsPerDay;
  final int? maxRequestsPerMinute;
  final int? unmatchedToday;
  final int? maxUnmatchedPerDay;
  const MetadataQuota(
      {this.maxThreads,
      this.requestsToday,
      this.maxRequestsPerDay,
      this.maxRequestsPerMinute,
      this.unmatchedToday,
      this.maxUnmatchedPerDay});
}

/// Review candidates contain identity evidence, never a publishable rating.
class MetadataLookupCandidate {
  final String providerGameId;
  final String platformId;
  final List<MetadataText> titles;
  final bool titleMatched;
  final String evidence;
  MetadataLookupCandidate(
      {required this.providerGameId,
      required this.platformId,
      required List<MetadataText> titles,
      required this.titleMatched,
      required this.evidence})
      : titles = List.unmodifiable(titles);
}

class MetadataLookupResult {
  final MetadataLookupStatus status;
  final MetadataRecord? record;
  final List<MetadataLookupCandidate> candidates;
  final MetadataQuota? quota;
  final Duration? retryAfter;

  /// Locally generated guidance only; never a raw provider response or exception.
  final String message;
  MetadataLookupResult(
      {required this.status,
      this.record,
      List<MetadataLookupCandidate> candidates = const [],
      this.quota,
      this.retryAfter,
      required this.message})
      : candidates = List.unmodifiable(candidates);
  @override
  String toString() => 'MetadataLookupResult(${status.name})';
}

abstract interface class MetadataProvider {
  String get providerId;
  MetadataProviderCapabilities get capabilities;
  Future<MetadataLookupResult> lookup(MetadataLookupRequest request,
      {CancelToken? cancelToken});
  void close();
}

/// Explicit connection/quotas checks are distinct from game lookups. A user may
/// recheck provider access without discarding cached metadata or retrying a ROM.
abstract interface class MetadataAccessProvider implements MetadataProvider {
  Future<MetadataLookupResult> checkAccess({CancelToken? cancelToken});
}

/// Image bodies are explicit worker requests, never authenticated cover URLs.
/// The caller owns bounded staging and validates the image before publication.
abstract interface class MetadataArtworkProvider implements MetadataProvider {
  Future<MetadataLookupResult> fetchArtwork(MetadataMedia media,
      {required Future<void> Function(List<int>) write,
      CancelToken? cancelToken});
}
