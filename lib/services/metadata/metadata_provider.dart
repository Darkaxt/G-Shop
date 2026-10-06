import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/library_identity.dart';
import '../../models/scraped_metadata.dart';
import '../../models/system_model.dart';

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

  /// Read only the declared original ISO identity, not CHD/combined checksums.
  /// This is lookup evidence, not an integrity check or installation claim.
  /// MAME v5 layout: src/lib/util/chd.h. Unsupported layouts stay unresolved.
  static MetadataRomIdentifier? fromChdDvdHeader(
      Uint8List bytes, String containerName) {
    if (bytes.length < 140 ||
        !containerName.toLowerCase().endsWith('.chd') ||
        containerName.length <= 4 ||
        containerName.contains(RegExp(r'[/\\:\x00]')) ||
        String.fromCharCodes(bytes.sublist(0, 8)) != 'MComprHD') {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    final size = data.getUint64(32);
    final hunk = data.getUint32(56);
    if (data.getUint32(8) != 124 ||
        data.getUint32(12) != 5 ||
        data.getUint64(48) != 124 ||
        data.getUint32(60) != 2048 ||
        size <= 0 ||
        size % 2048 != 0 ||
        hunk == 0 ||
        hunk > 512 * 1024 ||
        hunk % 2048 != 0 ||
        bytes.sublist(104, 124).any((v) => v != 0) ||
        !bytes.sublist(64, 84).any((v) => v != 0) ||
        String.fromCharCodes(bytes.sublist(124, 128)) != 'DVD ') {
      return null;
    }
    return MetadataRomIdentifier(
        kind: RomIdentifierKind.rawIso,
        filename: '${containerName.substring(0, containerName.length - 4)}.iso',
        sizeBytes: size,
        sha1: bytes
            .sublist(64, 84)
            .map((v) => v.toRadixString(16).padLeft(2, '0'))
            .join());
  }

  /// Drive hashes describe the stored file. They are compatible ROM evidence
  /// only for explicitly supported, uncompressed standalone formats.
  static MetadataRomIdentifier? fromUncompressedDriveArtifact(
      RemoteArtifact artifact, String platformId) {
    const standalone = {
      '.nes',
      '.sfc',
      '.smc',
      '.z64',
      '.n64',
      '.v64',
      '.nds',
      '.gb',
      '.gbc',
      '.gba',
      '.sms',
      '.gg',
      '.md',
      '.gen',
      '.pce',
      '.lnx',
      '.ngp',
      '.ngc',
      '.a26',
      '.a52',
      '.a78',
      '.iso',
      '.gcm'
    };
    final system = SystemModel.supportedSystems
        .where((s) => s.id == platformId)
        .firstOrNull;
    final name = artifact.displayName;
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot).toLowerCase();
    if (artifact.id.providerId != 'drive' ||
        artifact.id.accountId?.isNotEmpty != true ||
        artifact.version?.isNotEmpty != true ||
        (artifact.sizeBytes ?? 0) <= 0 ||
        name.contains(RegExp(r'[/\\:\x00]')) ||
        dot < 1 ||
        !standalone.contains(extension) ||
        system?.romExtensions.contains(extension) != true) {
      return null;
    }
    final md5 = artifact.providerChecksums['md5'];
    final sha1 = artifact.providerChecksums['sha1'];
    if (md5 == null && sha1 == null) return null;
    for (final entry in {32: md5, 40: sha1}.entries) {
      final value = entry.value;
      if (value != null &&
          (!RegExp('^[0-9a-fA-F]{${entry.key}}\$').hasMatch(value) ||
              RegExp(r'^0+$').hasMatch(value))) {
        return null;
      }
    }
    return MetadataRomIdentifier(
        kind: {'.iso', '.gcm'}.contains(extension)
            ? RomIdentifierKind.rawIso
            : RomIdentifierKind.rawRom,
        filename: name,
        sizeBytes: artifact.sizeBytes!,
        md5: md5,
        sha1: sha1);
  }

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
  }) : contentTags = Set.unmodifiable(
            EditionIdentity.normalizeContentTags(contentTags).toList()..sort());

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

  /// Transient validated cover selector, not an accepted metadata record.
  final MetadataMedia? previewMedia;
  MetadataLookupCandidate(
      {required this.providerGameId,
      required this.platformId,
      required List<MetadataText> titles,
      required this.titleMatched,
      required this.evidence,
      this.previewMedia})
      : titles = List.unmodifiable(titles);
}

class MetadataLookupResult {
  final MetadataLookupStatus status;
  final MetadataRecord? record;
  final List<MetadataLookupCandidate> candidates;
  final MetadataQuota? quota;
  final Duration? retryAfter;

  /// Exact-ROM provider facts, not a title-based or default classification.
  /// The worker revalidates the request/binding before applying these facts.
  final IdentityEvidence? officialRomEvidence;

  /// Locally generated guidance only; never a raw provider response or exception.
  final String message;
  MetadataLookupResult(
      {required this.status,
      this.record,
      List<MetadataLookupCandidate> candidates = const [],
      this.quota,
      this.retryAfter,
      this.officialRomEvidence,
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
