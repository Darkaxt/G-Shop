import 'library_identity.dart';

enum TransferLifecycle {
  queued,
  transferring,
  paused,
  awaitingAuthorization,
  verifying,
  publishing,
  completed,
  failed,
}

/// Durable transfer intent. The remote artifact and all path fields are an exact
/// immutable snapshot; only journal-controlled progress fields can be copied.
class TransferRecord {
  final String id;
  final RemoteArtifact artifact;
  final String destinationRoot;
  final String relativePath;
  final String stagePath;
  final int durableOffset;
  final TransferLifecycle lifecycle;
  final int revision;

  /// A bounded machine code, never raw exception text, URLs, or credentials.
  final String? errorCode;

  /// Digests computed from the complete staged bytes. Provider digests remain
  /// identified by their provider keys; `sha256` is the local streaming digest.
  final Map<String, String> verifiedChecksums;

  TransferRecord({
    required String id,
    required this.artifact,
    required String destinationRoot,
    required String relativePath,
    required String stagePath,
    this.durableOffset = 0,
    this.lifecycle = TransferLifecycle.queued,
    this.revision = 0,
    String? errorCode,
    Map<String, String> verifiedChecksums = const {},
  })  : id = _identifier(id, 'id'),
        destinationRoot = _identifier(destinationRoot, 'destinationRoot'),
        relativePath = _safeRelativePath(relativePath),
        stagePath = _identifier(stagePath, 'stagePath'),
        errorCode = _errorCode(errorCode),
        verifiedChecksums = _checksums(verifiedChecksums) {
    if (durableOffset < 0) {
      throw ArgumentError.value(
        durableOffset,
        'durableOffset',
        'Must be non-negative',
      );
    }
    final sourceSize = artifact.sizeBytes;
    if (sourceSize != null && durableOffset > sourceSize) {
      throw ArgumentError.value(
        durableOffset,
        'durableOffset',
        'Cannot exceed the artifact size',
      );
    }
    if (revision < 0) {
      throw ArgumentError.value(revision, 'revision', 'Must be non-negative');
    }
  }

  factory TransferRecord.fromJson(Map<String, dynamic> json) => TransferRecord(
        id: json['id'] as String,
        artifact: RemoteArtifact.fromJson(
          (json['artifact'] as Map).cast<String, dynamic>(),
        ),
        destinationRoot: json['destinationRoot'] as String,
        relativePath: json['relativePath'] as String,
        stagePath: json['stagePath'] as String,
        durableOffset: json['durableOffset'] as int? ?? 0,
        lifecycle: TransferLifecycle.values.byName(
          json['lifecycle'] as String? ?? TransferLifecycle.queued.name,
        ),
        revision: json['revision'] as int? ?? 0,
        errorCode: json['errorCode'] as String?,
        verifiedChecksums: _stringMap(json['verifiedChecksums']),
      );

  TransferRecord copyWith({
    int? durableOffset,
    TransferLifecycle? lifecycle,
    int? revision,
    String? errorCode,
    bool clearErrorCode = false,
    Map<String, String>? verifiedChecksums,
  }) =>
      TransferRecord(
        id: id,
        artifact: artifact,
        destinationRoot: destinationRoot,
        relativePath: relativePath,
        stagePath: stagePath,
        durableOffset: durableOffset ?? this.durableOffset,
        lifecycle: lifecycle ?? this.lifecycle,
        revision: revision ?? this.revision,
        errorCode: clearErrorCode ? null : (errorCode ?? this.errorCode),
        verifiedChecksums: verifiedChecksums ?? this.verifiedChecksums,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'artifact': artifact.toJson(),
        'destinationRoot': destinationRoot,
        'relativePath': relativePath,
        'stagePath': stagePath,
        'durableOffset': durableOffset,
        'lifecycle': lifecycle.name,
        'revision': revision,
        if (errorCode != null) 'errorCode': errorCode,
        'verifiedChecksums': verifiedChecksums,
      };
}

/// Native identity captured after publication. Size and modification time are
/// part of the identity evidence used before a future owned-file operation.
class NativeFileIdentity {
  final String volumeId;
  final String fileId;
  final int sizeBytes;
  final DateTime modifiedAt;

  NativeFileIdentity({
    required String volumeId,
    required String fileId,
    required this.sizeBytes,
    required this.modifiedAt,
  })  : volumeId = _identifier(volumeId, 'volumeId'),
        fileId = _identifier(fileId, 'fileId') {
    if (sizeBytes < 0) {
      throw ArgumentError.value(sizeBytes, 'sizeBytes', 'Must be non-negative');
    }
  }

  factory NativeFileIdentity.fromJson(Map<String, dynamic> json) =>
      NativeFileIdentity(
        volumeId: json['volumeId'] as String,
        fileId: json['fileId'] as String,
        sizeBytes: json['sizeBytes'] as int,
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'volumeId': volumeId,
        'fileId': fileId,
        'sizeBytes': sizeBytes,
        'modifiedAt': modifiedAt.toUtc().toIso8601String(),
      };
}

/// Exact manifest ownership created only by an atomic journal completion.
class InstalledArtifact {
  final String id;
  final String transferId;
  final RemoteArtifact artifact;
  final String destinationRoot;
  final String relativePath;
  final int sizeBytes;
  final Map<String, String> verifiedChecksums;
  final NativeFileIdentity fileIdentity;
  final String? gameId;
  final String? editionId;

  InstalledArtifact({
    required String id,
    required String transferId,
    required this.artifact,
    required String destinationRoot,
    required String relativePath,
    required this.sizeBytes,
    required Map<String, String> verifiedChecksums,
    required this.fileIdentity,
    String? gameId,
    String? editionId,
  })  : id = _identifier(id, 'id'),
        transferId = _identifier(transferId, 'transferId'),
        destinationRoot = _identifier(destinationRoot, 'destinationRoot'),
        relativePath = _safeRelativePath(relativePath),
        verifiedChecksums = _checksums(verifiedChecksums),
        gameId = _optionalIdentifier(gameId, 'gameId'),
        editionId = _optionalIdentifier(editionId, 'editionId') {
    if (sizeBytes < 0) {
      throw ArgumentError.value(sizeBytes, 'sizeBytes', 'Must be non-negative');
    }
    if (verifiedChecksums.isEmpty) {
      throw ArgumentError.value(
        verifiedChecksums,
        'verifiedChecksums',
        'An installation requires verified bytes',
      );
    }
    if (fileIdentity.sizeBytes != sizeBytes) {
      throw ArgumentError('Native identity size must match installation size');
    }
    final sourceSize = artifact.sizeBytes;
    if (sourceSize != null && sourceSize != sizeBytes) {
      throw ArgumentError('Installation size must match the artifact snapshot');
    }
  }

  factory InstalledArtifact.fromJson(Map<String, dynamic> json) =>
      InstalledArtifact(
        id: json['id'] as String,
        transferId: json['transferId'] as String,
        artifact: RemoteArtifact.fromJson(
          (json['artifact'] as Map).cast<String, dynamic>(),
        ),
        destinationRoot: json['destinationRoot'] as String,
        relativePath: json['relativePath'] as String,
        sizeBytes: json['sizeBytes'] as int,
        verifiedChecksums: _stringMap(json['verifiedChecksums']),
        fileIdentity: NativeFileIdentity.fromJson(
          (json['fileIdentity'] as Map).cast<String, dynamic>(),
        ),
        gameId: json['gameId'] as String?,
        editionId: json['editionId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'transferId': transferId,
        'artifact': artifact.toJson(),
        'destinationRoot': destinationRoot,
        'relativePath': relativePath,
        'sizeBytes': sizeBytes,
        'verifiedChecksums': verifiedChecksums,
        'fileIdentity': fileIdentity.toJson(),
        if (gameId != null) 'gameId': gameId,
        if (editionId != null) 'editionId': editionId,
      };
}

String _identifier(String value, String name) {
  if (value.trim().isEmpty || value.contains('\u0000')) {
    throw ArgumentError.value(value, name, 'Must be a non-empty safe value');
  }
  return value;
}

String? _optionalIdentifier(String? value, String name) =>
    value == null ? null : _identifier(value, name);

String _safeRelativePath(String value) {
  _identifier(value, 'relativePath');
  if (value.startsWith('/') ||
      value.startsWith('\\') ||
      value.contains('\\') ||
      RegExp(r'^[A-Za-z]:').hasMatch(value)) {
    throw ArgumentError.value(value, 'relativePath', 'Must be relative');
  }
  final parts = value.split('/');
  if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw ArgumentError.value(
      value,
      'relativePath',
      'Must not contain empty, current, or parent segments',
    );
  }
  return value;
}

String? _errorCode(String? value) {
  if (value == null) return null;
  if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'errorCode',
      'Must be a bounded sanitized machine code',
    );
  }
  return value;
}

Map<String, String> _checksums(Map<String, String> input) {
  const digestHexLengths = {'md5': 32, 'sha1': 40, 'sha256': 64};
  final copy = <String, String>{};
  for (final entry in input.entries) {
    final key = entry.key;
    final value = entry.value;
    final supportedLength = digestHexLengths[key];
    if (!RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(key) ||
        value.trim().isEmpty ||
        value != value.trim() ||
        value.length > 256 ||
        RegExp(r'[\s\u0000]').hasMatch(value) ||
        (supportedLength != null &&
            !RegExp('^[0-9a-fA-F]{$supportedLength}\$').hasMatch(value))) {
      throw ArgumentError.value(
          input, 'checksums', 'Contains an unsafe digest');
    }
    copy[key] = value;
  }
  return Map.unmodifiable(copy);
}

Map<String, String> _stringMap(Object? value) =>
    (value as Map? ?? const {}).cast<String, String>();
