import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

enum SaveBackupKind { save, state }

enum SaveBackupRelation { identical, localChanged, cloudChanged, conflict }

void _text(String value) {
  if (value.isEmpty ||
      value.length > 512 ||
      value.trim() != value ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw const FormatException('Invalid save binding');
  }
}

void _id(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(value)) {
    throw const FormatException('Invalid backup object identity');
  }
}

void _digest(String value) {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw const FormatException('Invalid save digest');
  }
}

Map<String, dynamic> _object(Object? value, Set<String> keys) {
  if (value is! Map<String, dynamic> ||
      value.length != keys.length ||
      !value.keys.every(keys.contains)) {
    throw const FormatException('Invalid backup fields');
  }
  return value;
}

/// An explicit reviewed association, not a filename/title match.
class SaveBackupEdition {
  final String gameId;
  final String editionId;

  SaveBackupEdition({required this.gameId, required this.editionId}) {
    _text(gameId);
    _text(editionId);
  }

  String get key => jsonEncode([gameId, editionId]);
  Map<String, Object> toJson() => {'gameId': gameId, 'editionId': editionId};

  factory SaveBackupEdition.fromJson(Object? raw) {
    final data = _object(raw, {'gameId', 'editionId'});
    return SaveBackupEdition(
        gameId: data['gameId'] as String,
        editionId: data['editionId'] as String);
  }
}

class SaveBackupBinding {
  final String accountId;
  final String deviceId;
  final String emulatorPackage;
  final String emulatorVersion;
  final String coreId;
  final String coreVersion;
  final String platformId;
  final List<SaveBackupEdition> editions;
  final SaveBackupKind kind;
  final String formatId;

  SaveBackupBinding(
      {required this.accountId,
      required this.deviceId,
      required this.emulatorPackage,
      required this.emulatorVersion,
      required this.coreId,
      required this.coreVersion,
      required this.platformId,
      required List<SaveBackupEdition> editions,
      required this.kind,
      required this.formatId})
      : editions = List.unmodifiable(
            [...editions]..sort((a, b) => a.key.compareTo(b.key))) {
    for (final value in [
      accountId,
      deviceId,
      emulatorPackage,
      emulatorVersion,
      coreId,
      coreVersion,
      platformId,
      formatId
    ]) {
      _text(value);
    }
    if (editions.isEmpty ||
        editions.length > 256 ||
        editions.map((e) => e.editionId).toSet().length != editions.length) {
      throw const FormatException('Invalid reviewed save group');
    }
  }

  String get key => jsonEncode(toJson());
  String get _editionsKey => jsonEncode(editions.map((e) => e.key).toList());

  /// Origin device is recorded, but explicit cross-device restore is allowed.
  /// Battery-save portability still requires the exact reviewed format ID.
  String? restoreIssue(SaveBackupBinding target) {
    if (accountId != target.accountId) return 'accountMismatch';
    if (platformId != target.platformId ||
        _editionsKey != target._editionsKey) {
      return 'editionMismatch';
    }
    if (kind != target.kind || formatId != target.formatId) {
      return 'formatMismatch';
    }
    if (kind == SaveBackupKind.state &&
        (emulatorPackage != target.emulatorPackage ||
            emulatorVersion != target.emulatorVersion ||
            coreId != target.coreId ||
            coreVersion != target.coreVersion)) {
      return 'stateCompatibility';
    }
    return null;
  }

  Map<String, Object> toJson() => {
        'accountId': accountId,
        'deviceId': deviceId,
        'emulatorPackage': emulatorPackage,
        'emulatorVersion': emulatorVersion,
        'coreId': coreId,
        'coreVersion': coreVersion,
        'platformId': platformId,
        'editions': editions.map((e) => e.toJson()).toList(),
        'kind': kind.name,
        'formatId': formatId,
      };

  factory SaveBackupBinding.fromJson(Object? raw) {
    final data = _object(raw, {
      'accountId',
      'deviceId',
      'emulatorPackage',
      'emulatorVersion',
      'coreId',
      'coreVersion',
      'platformId',
      'editions',
      'kind',
      'formatId'
    });
    return SaveBackupBinding(
        accountId: data['accountId'] as String,
        deviceId: data['deviceId'] as String,
        emulatorPackage: data['emulatorPackage'] as String,
        emulatorVersion: data['emulatorVersion'] as String,
        coreId: data['coreId'] as String,
        coreVersion: data['coreVersion'] as String,
        platformId: data['platformId'] as String,
        editions:
            (data['editions'] as List).map(SaveBackupEdition.fromJson).toList(),
        kind: SaveBackupKind.values.byName(data['kind'] as String),
        formatId: data['formatId'] as String);
  }
}

class SaveBackupMember {
  final String relativePath;
  final String cloudFileId;
  final int sizeBytes;
  final String sha256;

  SaveBackupMember(
      {required this.relativePath,
      required this.cloudFileId,
      required this.sizeBytes,
      required this.sha256}) {
    if (relativePath.isEmpty ||
        relativePath.length > 1024 ||
        RegExp(r'[\\:\x00-\x1f\x7f]').hasMatch(relativePath) ||
        relativePath.split('/').any((part) =>
            part.isEmpty ||
            part == '.' ||
            part == '..' ||
            part.endsWith('.') ||
            part.endsWith(' ')) ||
        sizeBytes <= 0) {
      throw const FormatException('Invalid save member');
    }
    _id(cloudFileId);
    _digest(sha256);
  }

  Map<String, Object> toJson() => {
        'relativePath': relativePath,
        'cloudFileId': cloudFileId,
        'sizeBytes': sizeBytes,
        'sha256': sha256
      };

  factory SaveBackupMember.fromJson(Object? raw) {
    final data =
        _object(raw, {'relativePath', 'cloudFileId', 'sizeBytes', 'sha256'});
    return SaveBackupMember(
        relativePath: data['relativePath'] as String,
        cloudFileId: data['cloudFileId'] as String,
        sizeBytes: data['sizeBytes'] as int,
        sha256: data['sha256'] as String);
  }
}

/// The sole publication object for a complete, byte-verified save generation.
/// Payload objects alone never establish a recoverable generation.
class SaveBackupManifest {
  static const maxEncodedBytes = 1024 * 1024;
  final String generationId;
  final SaveBackupBinding binding;
  final List<String> parentGenerationIds;
  final DateTime createdAt;
  final List<SaveBackupMember> members;

  SaveBackupManifest(
      {required this.generationId,
      required this.binding,
      required List<String> parentGenerationIds,
      required this.createdAt,
      required List<SaveBackupMember> members})
      : parentGenerationIds =
            List.unmodifiable([...parentGenerationIds]..sort()),
        members = List.unmodifiable([...members]
          ..sort((a, b) => a.relativePath.compareTo(b.relativePath))) {
    _id(generationId);
    for (final parent in parentGenerationIds) {
      _id(parent);
    }
    if (!createdAt.isUtc ||
        parentGenerationIds.length > 256 ||
        parentGenerationIds.contains(generationId) ||
        parentGenerationIds.toSet().length != parentGenerationIds.length ||
        members.isEmpty ||
        members.length > 4096 ||
        members.any((member) => member.cloudFileId == generationId) ||
        members.map((m) => m.relativePath.toLowerCase()).toSet().length !=
            members.length ||
        members.map((m) => m.cloudFileId).toSet().length != members.length) {
      throw const FormatException('Invalid complete save generation');
    }
  }

  /// Excludes upload IDs and clocks: identical re-uploaded bytes are unchanged.
  String get contentDigest => sha256
      .convert(utf8.encode(jsonEncode(members
          .map((m) => [m.relativePath, m.sizeBytes, m.sha256])
          .toList())))
      .toString();

  Uint8List encode() {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({
      'schema': 1,
      'generationId': generationId,
      'binding': binding.toJson(),
      'parentGenerationIds': parentGenerationIds,
      'createdAt': createdAt.toIso8601String(),
      'members': members.map((m) => m.toJson()).toList(),
      'contentDigest': contentDigest,
    })));
    if (bytes.length > maxEncodedBytes) {
      throw const FormatException('Save manifest too large');
    }
    return bytes;
  }

  factory SaveBackupManifest.decode(List<int> bytes) {
    if (bytes.length > maxEncodedBytes) {
      throw const FormatException('Save manifest too large');
    }
    try {
      final data = _object(jsonDecode(utf8.decode(bytes)), {
        'schema',
        'generationId',
        'binding',
        'parentGenerationIds',
        'createdAt',
        'members',
        'contentDigest'
      });
      if (data['schema'] != 1) {
        throw const FormatException('Unknown save schema');
      }
      final result = SaveBackupManifest(
          generationId: data['generationId'] as String,
          binding: SaveBackupBinding.fromJson(data['binding']),
          parentGenerationIds:
              (data['parentGenerationIds'] as List).cast<String>(),
          createdAt: DateTime.parse(data['createdAt'] as String),
          members: (data['members'] as List)
              .map(SaveBackupMember.fromJson)
              .toList());
      if (result.contentDigest != data['contentDigest']) {
        throw const FormatException('Altered save group digest');
      }
      return result;
    } catch (_) {
      throw const FormatException('Invalid save manifest');
    }
  }
}

/// Callers must establish that base belongs to the validated binding/ancestry.
/// A result is a conflict classification, never authorization to overwrite.
SaveBackupRelation reconcileSaveBackup(
    {required String local, required String cloud, String? base}) {
  _digest(local);
  _digest(cloud);
  if (base != null) _digest(base);
  if (local == cloud) return SaveBackupRelation.identical;
  if (local == base) return SaveBackupRelation.cloudChanged;
  if (cloud == base) return SaveBackupRelation.localChanged;
  return SaveBackupRelation.conflict;
}
