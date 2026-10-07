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

/// Adoption records an existing exact public file; no stage or rename occurred.
enum PublicationMethod { rename, copy, adopt }

/// Immutable flattened dependency graph. Paths include the exclusive bundle
/// namespace; every member keeps its original emulator-relative filename.
class TransferBundleMember {
  final String transferId;
  final RemoteArtifact artifact;
  final String relativePath;
  TransferBundleMember(
      {required this.transferId,
      required this.artifact,
      required String relativePath})
      : relativePath = _safeRelativePath(relativePath);
  factory TransferBundleMember.fromJson(Map<String, dynamic> json) =>
      TransferBundleMember(
          transferId: json['transferId'] as String,
          artifact: RemoteArtifact.fromJson(
              (json['artifact'] as Map).cast<String, dynamic>()),
          relativePath: json['relativePath'] as String);
  Map<String, dynamic> toJson() => {
        'transferId': transferId,
        'artifact': artifact.toJson(),
        'relativePath': relativePath
      };
}

/// A durable publication intent, persisted before touching the public target.
/// The verified source remains owned until the installation transaction commits.
class TransferPublication {
  final PublicationMethod method;
  final NativeFileIdentity sourceIdentity;
  final NativeFileIdentity? destinationIdentity;
  final bool confirmed;

  const TransferPublication({
    required this.method,
    required this.sourceIdentity,
    this.destinationIdentity,
    this.confirmed = false,
  });

  int get copiedOffset => destinationIdentity?.sizeBytes ?? 0;

  factory TransferPublication.fromJson(Map<String, dynamic> json) =>
      TransferPublication(
        method: PublicationMethod.values.byName(json['method'] as String),
        sourceIdentity: NativeFileIdentity.fromJson(
          (json['sourceIdentity'] as Map).cast<String, dynamic>(),
        ),
        destinationIdentity: json['destinationIdentity'] == null
            ? null
            : NativeFileIdentity.fromJson(
                (json['destinationIdentity'] as Map).cast<String, dynamic>(),
              ),
        confirmed: json['confirmed'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'method': method.name,
        'sourceIdentity': sourceIdentity.toJson(),
        if (destinationIdentity != null)
          'destinationIdentity': destinationIdentity!.toJson(),
        'confirmed': confirmed,
      };
}

/// Durable transfer intent. The remote artifact and all path fields are an exact
/// immutable snapshot; only journal-controlled progress fields can be copied.
class TransferRecord {
  static bool supportsArchiveMapping(String path, String? platform) {
    final lower = path.toLowerCase();
    return (platform == 'gamegear' && lower.endsWith('.zip')) ||
        (const {'gb', 'gbc', 'gba', 'nes'}.contains(platform) && lower.endsWith('.7z')) ||
        (platform == 'n64' && (lower.endsWith('.7z') || lower.endsWith('.zip')));
  }

  final String id;
  final RemoteArtifact artifact;
  final String destinationRoot;
  final String relativePath;
  final String stagePath;
  /// Immutable explicit mapping for the supported archive route, not inferred
  /// from an archive suffix or retroactively applied to legacy records.
  final String? archivePlatformId;

  /// Immutable previous owner. Replacement publishes to a distinct path before
  /// this exact installation can be retired; it never overwrites the old target.
  final InstalledArtifact? replacesInstallation;
  final String? bundleOwner;
  final List<TransferBundleMember> bundleMembers;
  final int durableOffset;
  final TransferLifecycle lifecycle;
  final int revision;

  /// Identity captured from the flushed native descriptor at durableOffset.
  /// Null is retained for readable legacy records, not treated as ownership.
  final NativeFileIdentity? stageIdentity;
  final TransferPublication? publication;

  /// Post-commit private copy retirement, independent of installed-file truth.
  /// Completed copy + exact stage identity is the durable retirement intent.
  final bool stageRetired;
  final String? stageRetirementIssue;

  /// A bounded machine code, never raw exception text, URLs, or credentials.
  final String? errorCode;

  /// Digests computed from complete staged bytes, or the existing public file
  /// during explicit adoption. Provider digests remain
  /// identified by their provider keys; `sha256` is the local streaming digest.
  final Map<String, String> verifiedChecksums;

  TransferRecord({
    required String id,
    required this.artifact,
    required String destinationRoot,
    required String relativePath,
    required String stagePath,
    this.archivePlatformId,
    this.replacesInstallation,
    this.bundleOwner,
    List<TransferBundleMember> bundleMembers = const [],
    this.durableOffset = 0,
    this.lifecycle = TransferLifecycle.queued,
    this.revision = 0,
    this.stageIdentity,
    this.publication,
    this.stageRetired = false,
    String? stageRetirementIssue,
    String? errorCode,
    Map<String, String> verifiedChecksums = const {},
  })  : id = _identifier(id, 'id'),
        destinationRoot = _identifier(destinationRoot, 'destinationRoot'),
        relativePath = _safeRelativePath(relativePath),
        stagePath = _identifier(stagePath, 'stagePath'),
        errorCode = _errorCode(errorCode),
        stageRetirementIssue = _errorCode(stageRetirementIssue),
        verifiedChecksums = _checksums(verifiedChecksums),
        bundleMembers = List.unmodifiable(bundleMembers) {
    if (archivePlatformId != null &&
        (!supportsArchiveMapping(relativePath, archivePlatformId) ||
            bundleOwner != null || bundleMembers.isNotEmpty)) {
      throw ArgumentError('Unsupported archive mapping');
    }
    if (bundleMembers.isNotEmpty && bundleOwner != null) {
      throw ArgumentError('A member cannot own a nested bundle');
    }
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
        archivePlatformId: json['archivePlatformId'] as String?,
        bundleOwner: json['bundleOwner'] as String?,
        bundleMembers: [
          for (final member in json['bundleMembers'] as List? ?? const [])
            TransferBundleMember.fromJson(
                (member as Map).cast<String, dynamic>())
        ],
        replacesInstallation: json['replacesInstallation'] == null
            ? null
            : InstalledArtifact.fromJson(
                (json['replacesInstallation'] as Map).cast<String, dynamic>()),
        durableOffset: json['durableOffset'] as int? ?? 0,
        lifecycle: TransferLifecycle.values.byName(
          json['lifecycle'] as String? ?? TransferLifecycle.queued.name,
        ),
        revision: json['revision'] as int? ?? 0,
        stageIdentity: json['stageIdentity'] == null
            ? null
            : NativeFileIdentity.fromJson(
                (json['stageIdentity'] as Map).cast<String, dynamic>(),
              ),
        publication: json['publication'] == null
            ? null
            : TransferPublication.fromJson(
                (json['publication'] as Map).cast<String, dynamic>(),
              ),
        errorCode: json['errorCode'] as String?,
        stageRetired: json['stageRetired'] as bool? ?? false,
        stageRetirementIssue: json['stageRetirementIssue'] as String?,
        verifiedChecksums: _stringMap(json['verifiedChecksums']),
      );

  TransferRecord copyWith({
    int? durableOffset,
    TransferLifecycle? lifecycle,
    int? revision,
    NativeFileIdentity? stageIdentity,
    TransferPublication? publication,
    bool? stageRetired,
    String? stageRetirementIssue,
    bool clearStageRetirementIssue = false,
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
        archivePlatformId: archivePlatformId,
        replacesInstallation: replacesInstallation,
        bundleOwner: bundleOwner,
        bundleMembers: bundleMembers,
        durableOffset: durableOffset ?? this.durableOffset,
        lifecycle: lifecycle ?? this.lifecycle,
        revision: revision ?? this.revision,
        stageIdentity: stageIdentity ?? this.stageIdentity,
        publication: publication ?? this.publication,
        stageRetired: stageRetired ?? this.stageRetired,
        stageRetirementIssue: clearStageRetirementIssue
            ? null
            : stageRetirementIssue ?? this.stageRetirementIssue,
        errorCode: clearErrorCode ? null : (errorCode ?? this.errorCode),
        verifiedChecksums: verifiedChecksums ?? this.verifiedChecksums,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'artifact': artifact.toJson(),
        'destinationRoot': destinationRoot,
        'relativePath': relativePath,
        'stagePath': stagePath,
        if (archivePlatformId != null) 'archivePlatformId': archivePlatformId,
        if (bundleOwner != null) 'bundleOwner': bundleOwner,
        if (bundleMembers.isNotEmpty)
          'bundleMembers': [
            for (final member in bundleMembers) member.toJson()
          ],
        if (replacesInstallation != null)
          'replacesInstallation': replacesInstallation!.toJson(),
        'durableOffset': durableOffset,
        'lifecycle': lifecycle.name,
        'revision': revision,
        if (stageIdentity != null) 'stageIdentity': stageIdentity!.toJson(),
        if (publication != null) 'publication': publication!.toJson(),
        if (stageRetired) 'stageRetired': true,
        if (stageRetirementIssue != null)
          'stageRetirementIssue': stageRetirementIssue,
        if (errorCode != null) 'errorCode': errorCode,
        'verifiedChecksums': verifiedChecksums,
      };
}

/// Native identity captured from an owned descriptor. Size and modification
/// time are evidence revalidated before later writes, publication or removal.
class NativeFileIdentity {
  final String volumeId;
  final String fileId;
  final int sizeBytes;
  final DateTime modifiedAt;

  /// Full native subsecond value; DateTime alone truncates filesystem nanoseconds.
  final int modifiedNanoseconds;

  NativeFileIdentity({
    required String volumeId,
    required String fileId,
    required this.sizeBytes,
    required this.modifiedAt,
    int? modifiedNanoseconds,
  })  : volumeId = _identifier(volumeId, 'volumeId'),
        fileId = _identifier(fileId, 'fileId'),
        modifiedNanoseconds = modifiedNanoseconds ??
            (modifiedAt.microsecondsSinceEpoch % 1000000) * 1000 {
    if (sizeBytes < 0) {
      throw ArgumentError.value(sizeBytes, 'sizeBytes', 'Must be non-negative');
    }
    if (this.modifiedNanoseconds < 0 ||
        this.modifiedNanoseconds >= 1000000000 ||
        this.modifiedNanoseconds ~/ 1000 !=
            modifiedAt.microsecondsSinceEpoch % 1000000) {
      throw ArgumentError('Native timestamp must match its display timestamp');
    }
  }

  factory NativeFileIdentity.fromJson(Map<String, dynamic> json) =>
      NativeFileIdentity(
        volumeId: json['volumeId'] as String,
        fileId: json['fileId'] as String,
        sizeBytes: json['sizeBytes'] as int,
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
        modifiedNanoseconds: json['modifiedNanoseconds'] as int?,
      );

  bool sameObject(NativeFileIdentity other) =>
      volumeId == other.volumeId && fileId == other.fileId;

  bool matches(NativeFileIdentity other) =>
      sameObject(other) &&
      sizeBytes == other.sizeBytes &&
      modifiedAt.isAtSameMomentAs(other.modifiedAt) &&
      modifiedNanoseconds == other.modifiedNanoseconds;

  Map<String, dynamic> toJson() => {
        'volumeId': volumeId,
        'fileId': fileId,
        'sizeBytes': sizeBytes,
        'modifiedAt': modifiedAt.toUtc().toIso8601String(),
        'modifiedNanoseconds': modifiedNanoseconds,
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
  final List<InstalledArtifact> dependencies;

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
    List<InstalledArtifact> dependencies = const [],
  })  : id = _identifier(id, 'id'),
        transferId = _identifier(transferId, 'transferId'),
        destinationRoot = _identifier(destinationRoot, 'destinationRoot'),
        relativePath = _safeRelativePath(relativePath),
        verifiedChecksums = _checksums(verifiedChecksums),
        gameId = _optionalIdentifier(gameId, 'gameId'),
        editionId = _optionalIdentifier(editionId, 'editionId'),
        dependencies = List.unmodifiable(dependencies) {
    if (dependencies.any((member) =>
        member.dependencies.isNotEmpty ||
        member.id == id ||
        member.destinationRoot != destinationRoot)) {
      throw ArgumentError(
          'Bundle dependencies must be flat exact owned members');
    }
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
        dependencies: [
          for (final member in json['dependencies'] as List? ?? const [])
            InstalledArtifact.fromJson((member as Map).cast<String, dynamic>())
        ],
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
        if (dependencies.isNotEmpty)
          'dependencies': [for (final member in dependencies) member.toJson()],
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
