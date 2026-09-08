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
  const MetadataRomIdentifier(
      {required this.kind,
      required this.filename,
      required this.sizeBytes,
      this.crc32,
      this.md5,
      this.sha1});
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

  MetadataLookupRequest(
      {required this.gameId,
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
      required this.refreshGeneration})
      : contentTags = Set.unmodifiable(contentTags);
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
