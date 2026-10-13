import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../services/saves/save_capture.dart';
import 'save_backup_manifest.dart';

/// One exact game's filesystem selection. The existing backup engine owns IO,
/// watching, ancestry and rollback; this is data, not another emulator adapter.
class SaveRootConfiguration {
  static String storageKey(String artifactKey) =>
      'save_root_configuration_v1_${sha256.convert(utf8.encode(artifactKey))}';
  final String directory, emulator, core, format;
  final SaveBackupKind kind;
  final List<String> files, folders, requiredFiles;
  final List<String> runtimeFiles;
  final String? resourceId;
  final String? profile;
  SaveRootConfiguration._(
      this.directory,
      this.emulator,
      this.core,
      this.kind,
      this.format,
      this.files,
      this.folders,
      this.requiredFiles,
      this.runtimeFiles,
      this.resourceId,
      this.profile);

  factory SaveRootConfiguration.decode(Map<String, dynamic> row,
      {String? romName}) {
    const keys = {
      'schema',
      'directory',
      'emulator',
      'core',
      'kind',
      'format',
      'files',
      'folders',
      'required'
    };
    final baseKeys = row.keys.toSet()
      ..removeAll({'runtimeFiles', 'resourceId', 'profile'});
    if (baseKeys.length != keys.length ||
        !baseKeys.every(keys.contains) ||
        row['schema'] != 1 ||
        ['directory', 'emulator', 'core', 'kind', 'format']
            .any((k) => row[k] is! String) ||
        !RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$')
            .hasMatch(row['emulator']) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(row['core']) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(row['format']) ||
        !SaveBackupKind.values.any((kind) => kind.name == row['kind'])) {
      throw const FormatException('Invalid save folder mapping');
    }
    String expand(String value) {
      if (value.contains('{romStem}')) {
        if (romName == null ||
            romName.lastIndexOf('.') <= 0 ||
            !SaveCapture.validPpssppSavedataMember(romName)) {
          throw const FormatException('A ROM is required for this mapping');
        }
        value = value.replaceAll(
            '{romStem}', romName.substring(0, romName.lastIndexOf('.')));
      }
      if (value.contains('{') || value.contains('}')) {
        throw const FormatException('Unknown mapping placeholder');
      }
      return value;
    }

    final directory = expand(row['directory']);
    final resourceId = row['resourceId'];
    final profile = row['profile'];
    final standard = switch (profile) {
      'nether-cards-v1' => row['emulator'] == 'xyz.aethersx2.android' &&
          row['core'] == 'pcsx2' &&
          resourceId == 'memory-cards' &&
          row['format'] == 'ps2-shared-memory-cards-v1',
      'flycast-shared-vmus-v1' => row['emulator'] == 'com.flycast.emulator' &&
          row['core'] == 'flycast' &&
          resourceId == 'vmu-cards' &&
          row['format'] == 'dreamcast-vmu-v1',
      'dolphin-gci-cards-v1' =>
        row['emulator'] == 'org.dolphinemu.dolphinemu' &&
            row['core'] == 'dolphin' &&
            resourceId == 'gc-memory-cards' &&
            row['format'] == 'gamecube-gci-cards-v1',
      'azahar-title-save-v1' =>
        row['emulator'] == 'io.github.lime3ds.android' &&
            row['core'] == 'azahar' &&
            resourceId == null &&
            row['format'] == 'azahar-title-save-v1',
      'cemu-title-save-v1' => row['emulator'] == 'info.cemu.cemu' &&
          row['core'] == 'cemu' &&
          resourceId == null &&
          row['format'] == 'cemu-title-save-v1',
      _ => false,
    };
    if (profile != null && (!standard || row['kind'] != 'save')) {
      throw const FormatException('Invalid standard save profile');
    }
    if (resourceId != null &&
        (resourceId is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(resourceId) ||
            row['kind'] != 'save' ||
            jsonEncode(row).contains('{romStem}'))) {
      throw const FormatException('Invalid shared save resource');
    }
    final emulator = row['emulator'] as String;
    final private = '/data/user/0/$emulator/files';
    final legacy = '/data/data/$emulator/files';
    if (!(SaveCapture.validRomCompanionDirectory(directory) ||
            (directory == private ||
                    directory.startsWith('$private/') ||
                    directory == legacy ||
                    directory.startsWith('$legacy/')) &&
                directory.split('/').skip(1).every(
                    (part) => SaveCapture.validPpssppSavedataMember(part))) ||
        directory.length > 4096) {
      throw const FormatException('Invalid save folder');
    }
    List<String> paths(String key, {bool binary = false}) {
      final values = row[key];
      if (values is! List ||
          values.length > 128 ||
          values.any((v) => v is! String)) {
        throw const FormatException('Invalid mapped files');
      }
      final expanded = values.cast<String>().map(expand).toList();
      if (expanded.toSet().length != expanded.length ||
          expanded.any((v) => !_safe(v, binary: binary))) {
        throw const FormatException('Invalid mapped file path');
      }
      return List.unmodifiable(expanded);
    }

    final files = paths('files', binary: true);
    final folders = paths('folders');
    final required = paths('required', binary: true);
    final runtime = row['runtimeFiles'] ?? <String>[];
    if (runtime is! List ||
        runtime.length > 16 ||
        runtime.toSet().length != runtime.length ||
        runtime.any((value) =>
            value is! String ||
            value.length > 4096 ||
            !value.endsWith('.so') ||
            !(SaveCapture.validRomCompanionDirectory(value) ||
                ['/data/user/0/$emulator/', '/data/data/$emulator/']
                    .any(value.startsWith)) ||
            !value
                .split('/')
                .skip(1)
                .every(SaveCapture.validPpssppSavedataMember)) ||
        emulator == 'com.retroarch.aarch64' &&
            row['kind'] != 'save' &&
            runtime.isEmpty) {
      throw const FormatException(
          'The core library is required for this mapping');
    }
    if (files.isEmpty && folders.isEmpty ||
        files.length + folders.length > 128 ||
        required.any((v) => !files.contains(v)) ||
        jsonEncode(row).length > 32768) {
      throw const FormatException('Invalid save group');
    }
    return SaveRootConfiguration._(
        directory,
        emulator,
        row['core'],
        SaveBackupKind.values.byName(row['kind']),
        row['format'],
        files,
        folders,
        required,
        List<String>.unmodifiable(runtime.cast<String>()),
        resourceId as String?,
        profile as String?);
  }

  static bool _safe(String path, {bool binary = false}) {
    if (!SaveCapture.validRomCompanionPath(path)) return false;
    return path.split('/').every((part) => SaveCapture.validRomCompanionName(
        'scope.rom',
        'scope.${binary && part.toLowerCase().endsWith('.bin') ? '${part.substring(0, part.length - 4)}.sav' : part}'));
  }

  bool acceptsFile(String path) =>
      _safe(path,
          binary: files.contains(path) ||
              const {'azahar-title-save-v1', 'cemu-title-save-v1'}
                  .contains(profile)) &&
      (files.contains(path) ||
          folders.any((folder) => path.startsWith('$folder/')));
  bool acceptsDirectory(String path) =>
      _safe(path) &&
      (folders.any((folder) =>
              folder == path ||
              folder.startsWith('$path/') ||
              path.startsWith('$folder/')) ||
          files.any((file) => file.startsWith('$path/')));
  bool completeGroup(Set<String> present) =>
      present.isEmpty || requiredFiles.every(present.contains);
  Map<String, Object> toJson() => {
        'schema': 1,
        'directory': directory,
        'emulator': emulator,
        'core': core,
        'kind': kind.name,
        'format': format,
        'files': files,
        'folders': folders,
        'required': requiredFiles,
        if (runtimeFiles.isNotEmpty) 'runtimeFiles': runtimeFiles,
        if (resourceId != null) 'resourceId': resourceId!,
        if (profile != null) 'profile': profile!,
      };
  String get identity => jsonEncode(toJson());
  String? get logicalRomName =>
      resourceId == null ? null : 'shared-$resourceId.save';
  String? get sharedResourceKey => resourceId == null
      ? null
      : sha256.convert(utf8.encode(identity)).toString();
}
