import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../models/library_identity.dart';
import 'drive_api.dart';
import 'drive_media.dart';

/// Source-side verification evidence is separate from an installed-state claim.
class DriveVerification {
  final RemoteArtifact expected;
  final Map<String, String> checksums;
  DriveVerification(this.expected) : checksums = _trustedChecksums(expected) {
    if (expected.id.providerId != 'drive' ||
        expected.id.accountId?.isNotEmpty != true ||
        expected.parentId?.isNotEmpty != true ||
        expected.version?.isNotEmpty != true ||
        expected.sizeBytes == null ||
        expected.canDownload != true) {
      throw const DriveTransferException(DriveTransferIssue.invalidSource);
    }
  }

  static const _algorithms = {'md5': md5, 'sha1': sha1, 'sha256': sha256};
  static const _digestHexLengths = {'md5': 32, 'sha1': 40, 'sha256': 64};

  static Map<String, String> _trustedChecksums(RemoteArtifact artifact) {
    final result = <String, String>{};
    for (final entry in _algorithms.entries) {
      final checksum = artifact.providerChecksums[entry.key];
      if (checksum == null) continue;
      if (!RegExp('^[0-9a-fA-F]{${_digestHexLengths[entry.key]}}\$')
          .hasMatch(checksum)) {
        throw const DriveTransferException(DriveTransferIssue.invalidSource);
      }
      result[entry.key] = checksum.toLowerCase();
    }
    if (result.isEmpty) {
      throw const DriveTransferException(DriveTransferIssue.missingChecksum);
    }
    return Map.unmodifiable(result);
  }

  void requireCurrent(DriveFile current) {
    if (!current.isSupportedBinary ||
        current.id != expected.id.providerFileId ||
        current.parents.length != 1 ||
        current.parents.single != expected.parentId ||
        current.canDownload != true ||
        current.version != expected.version ||
        current.sizeBytes != expected.sizeBytes ||
        (expected.modifiedAt != null &&
            current.modifiedAt != expected.modifiedAt) ||
        checksums.entries.any((hash) =>
            current.checksums[hash.key]?.toLowerCase() != hash.value)) {
      // Fixed field names/booleans only: snapshot failures must be diagnosable
      // without exposing accounts, file IDs, paths, hashes or credentials.
      debugPrint('Drive snapshot mismatch: '
          'binary=${!current.isSupportedBinary} '
          'identity=${current.id != expected.id.providerFileId} '
          'parent=${current.parents.length != 1 || current.parents.single != expected.parentId} '
          'download=${current.canDownload != true} '
          'version=${current.version != expected.version} '
          'size=${current.sizeBytes != expected.sizeBytes} '
          'modified=${expected.modifiedAt != null && current.modifiedAt != expected.modifiedAt} '
          'checksums=${checksums.entries.where((hash) => current.checksums[hash.key]?.toLowerCase() != hash.value).map((hash) => hash.key).join(",")}');
      throw const DriveTransferException(DriveTransferIssue.sourceChanged);
    }
  }

  /// Index content is unchanged, but Drive may advance its metadata version.
  /// This never permits a changed byte contract, name, identity or parent.
  RemoteArtifact requirePatchIndexMetadataRevision(DriveFile current) {
    if (!{'index.json', 'game.json'}.contains(expected.displayName) ||
        current.name != expected.displayName) {
      throw const DriveTransferException(DriveTransferIssue.sourceChanged);
    }
    if (current.version == expected.version) {
      requireCurrent(current);
      return expected;
    }
    final before = BigInt.tryParse(expected.version ?? '');
    final after = BigInt.tryParse(current.version ?? '');
    if (before == null || after == null || after <= before) {
      throw const DriveTransferException(DriveTransferIssue.sourceChanged);
    }
    final updated = RemoteArtifact(
        id: expected.id,
        parentId: expected.parentId,
        displayPath: expected.displayPath,
        displayName: expected.displayName,
        sizeBytes: expected.sizeBytes,
        modifiedAt: expected.modifiedAt,
        version: current.version,
        providerChecksums: expected.providerChecksums,
        canDownload: expected.canDownload);
    DriveVerification(updated).requireCurrent(current);
    return updated;
  }

  Future<Map<String, String>> verifyBytes(Stream<Uint8List> bytes,
      {required CancelToken cancellation}) async {
    final results = {
      for (final algorithm in {...checksums.keys, 'sha256'})
        algorithm: _DigestSink(),
    };
    final sinks = {
      for (final entry in results.entries)
        entry.key: _algorithms[entry.key]!.startChunkedConversion(entry.value),
    };
    var count = 0;
    void checkCancellation() {
      if (cancellation.isCancelled) {
        throw const DriveTransferException(DriveTransferIssue.cancelled);
      }
    }

    try {
      checkCancellation();
      await for (final chunk in bytes) {
        checkCancellation();
        if (chunk.length > DriveMediaApi.maxChunkBytes ||
            count + chunk.length > expected.sizeBytes!) {
          throw const DriveTransferException(
              DriveTransferIssue.invalidResponse);
        }
        count += chunk.length;
        for (final sink in sinks.values) {
          sink.add(chunk);
        }
      }
      checkCancellation();
      if (count != expected.sizeBytes) {
        throw const DriveTransferException(DriveTransferIssue.truncated);
      }
    } on DriveTransferException {
      rethrow;
    } catch (_) {
      throw DriveTransferException(cancellation.isCancelled
          ? DriveTransferIssue.cancelled
          : DriveTransferIssue.unavailable);
    } finally {
      for (final sink in sinks.values) {
        sink.close();
      }
    }
    final actual = {
      for (final entry in results.entries)
        entry.key: entry.value.value!.toString(),
    };
    if (checksums.entries.any((entry) => actual[entry.key] != entry.value)) {
      throw const DriveTransferException(DriveTransferIssue.checksumMismatch);
    }
    return Map.unmodifiable(actual);
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
