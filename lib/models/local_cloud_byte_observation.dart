import 'library_identity.dart';
import 'transfer_record.dart';

/// Past exact-byte evidence only. Never installation ownership, a restore-format
/// certificate, a ranking snapshot, or permission to remove a file.
class DriveLocalCloudObservation {
  final RemoteArtifact artifact;
  final String destinationRoot, relativePath;
  final NativeFileIdentity localIdentity;
  final int sizeBytes;
  final Map<String, String> checksums;
  final DateTime observedAt;

  DriveLocalCloudObservation({
    required this.artifact,
    required this.destinationRoot,
    required this.relativePath,
    required this.localIdentity,
    required this.sizeBytes,
    required Map<String, String> checksums,
    required DateTime observedAt,
  })  : checksums = Map.unmodifiable(checksums),
        observedAt = observedAt.toUtc() {
    const lengths = {'md5': 32, 'sha1': 40, 'sha256': 64};
    bool validDigest(String key, String value) =>
        lengths.containsKey(key) &&
        RegExp('^[0-9a-f]{${lengths[key]}}\$').hasMatch(value);
    final expected = artifact.providerChecksums.entries
        .where((e) => lengths.containsKey(e.key))
        .toList();
    if (artifact.id.providerId != 'drive' ||
        artifact.id.accountId == null ||
        artifact.version == null ||
        artifact.version!.isEmpty ||
        artifact.canDownload != true ||
        artifact.sizeBytes != sizeBytes ||
        localIdentity.sizeBytes != sizeBytes ||
        !destinationRoot.startsWith('/') ||
        destinationRoot == '/' ||
        destinationRoot.contains('\\') ||
        destinationRoot.contains('\u0000') ||
        destinationRoot
            .split('/')
            .skip(1)
            .any((s) => s.isEmpty || s == '.' || s == '..') ||
        relativePath != artifact.displayName ||
        relativePath.isEmpty ||
        relativePath == '.' ||
        relativePath == '..' ||
        RegExp(r'[\\/\x00-\x1f<>:"|?*]').hasMatch(relativePath) ||
        checksums['sha256'] == null ||
        checksums.entries.any((e) => !validDigest(e.key, e.value)) ||
        expected.isEmpty ||
        expected.any((e) =>
            !validDigest(e.key, e.value.toLowerCase()) ||
            checksums[e.key] != e.value.toLowerCase())) {
      throw ArgumentError('Invalid local/cloud byte observation');
    }
  }

  Map<String, dynamic> toJson() => {
        'schema': 1,
        'artifact': artifact.toJson(),
        'destinationRoot': destinationRoot,
        'relativePath': relativePath,
        'localIdentity': localIdentity.toJson(),
        'sizeBytes': sizeBytes,
        'checksums': checksums,
        'observedAt': observedAt.toIso8601String(),
      };

  factory DriveLocalCloudObservation.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 1) {
      throw const FormatException('Unknown byte observation schema');
    }
    return DriveLocalCloudObservation(
      artifact: RemoteArtifact.fromJson(
          (json['artifact'] as Map).cast<String, dynamic>()),
      destinationRoot: json['destinationRoot'] as String,
      relativePath: json['relativePath'] as String,
      localIdentity: NativeFileIdentity.fromJson(
          (json['localIdentity'] as Map).cast<String, dynamic>()),
      sizeBytes: json['sizeBytes'] as int,
      checksums: (json['checksums'] as Map).cast<String, String>(),
      observedAt: DateTime.parse(json['observedAt'] as String),
    );
  }
}
