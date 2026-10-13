import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/save_emulator_coverage.dart';
import '../../models/retroarch_battery_route.dart';
import '../../models/pcsx_save_layout.dart';
import '../../models/save_root_configuration.dart';

class CapturedSaveFile {
  final String name, sha256;
  final File file;
  final int size;
  CapturedSaveFile(this.name, this.file, this.size, this.sha256);
}

class CapturedSaveGroup {
  final String captureId, deviceId, emulatorVersion;
  final String? coreVersion;
  final List<CapturedSaveFile> files;
  final bool localWasAbsent;
  CapturedSaveGroup(this.captureId, this.deviceId, this.emulatorVersion,
      List<CapturedSaveFile> files,
      {this.localWasAbsent = false, this.coreVersion})
      : files = List.unmodifiable(files);
}

class RestoreSaveMember {
  final String name, sha256;
  final int size;
  final Stream<Uint8List> bytes;
  RestoreSaveMember(this.name, this.size, this.sha256, this.bytes);
}

/// Native, exact-ROM-bound directory observation. It contains file identities,
/// not payloads or coherence claims. Modified entries are candidates for the
/// existing capture pipeline, never timestamp-selected conflict winners.
class RomCompanionSnapshot {
  final SaveRootConfiguration? configuration;
  final String binding, directory, romName;
  final List<int> directoryIdentity;
  final Map<String, List<int>> files;
  final List<String> changedFiles;

  RomCompanionSnapshot._(
      this.binding,
      this.directory,
      this.romName,
      this.directoryIdentity,
      this.files,
      this.changedFiles,
      this.configuration);

  factory RomCompanionSnapshot.decode(Map<String, dynamic>? raw) {
    final configuration = raw?['saveRoot'] == null
        ? null
        : SaveRootConfiguration.decode(
            Map<String, dynamic>.from(raw!['saveRoot'] as Map));
    if (raw == null ||
        raw.keys.toSet().difference(const {
          'binding',
          'directory',
          'romName',
          'directoryIdentity',
          'files',
          'changed',
          'saveRoot'
        }).isNotEmpty ||
        raw.length != (configuration == null ? 6 : 7) ||
        raw['binding'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['binding'] as String) ||
        raw['directory'] is! String ||
        !(raw['directory'] as String).startsWith('/') ||
        RegExp(r'[\\\x00-\x1f\x7f]').hasMatch(raw['directory'] as String) ||
        (raw['directory'] as String)
            .split('/')
            .skip(1)
            .any((part) => part.isEmpty || part == '.' || part == '..') ||
        raw['romName'] is! String ||
        (raw['romName'] as String).startsWith('.') ||
        !SaveCapture.validPpssppSavedataMember(raw['romName'] as String) ||
        raw['directoryIdentity'] is! List ||
        (raw['directoryIdentity'] as List).length != 2 ||
        (raw['directoryIdentity'] as List).any((part) => part is! int) ||
        raw['files'] is! Map ||
        (raw['files'] as Map).length > 128 ||
        raw['changed'] is! List ||
        (raw['changed'] as List).length > 128) {
      throw const FormatException('Invalid ROM companion observation');
    }
    final name = raw['romName'] as String;
    final split = name.lastIndexOf('.');
    if (split <= 0) throw const FormatException('Invalid ROM filename');
    final files = <String, List<int>>{};
    for (final entry in (raw['files'] as Map).entries) {
      final leaf = entry.key;
      final value = entry.value;
      if (leaf is! String ||
          !(configuration?.acceptsFile(leaf) ??
              SaveCapture.validRomCompanionName(name, leaf,
                  directory: raw['directory'] as String)) ||
          value is! List ||
          value.length != 5 ||
          value.any((part) => part is! int) ||
          (value[2] as int) < 0 ||
          (value[4] as int) < 0 ||
          (value[4] as int) >= 1000000000) {
        throw const FormatException('Invalid ROM companion member');
      }
      files[leaf] = List<int>.unmodifiable(value.cast<int>());
    }
    final changed = raw['changed'] as List;
    if (changed.any((path) => path is! String || !files.containsKey(path)) ||
        changed.toSet().length != changed.length) {
      throw const FormatException('Invalid ROM companion changes');
    }
    return RomCompanionSnapshot._(
        raw['binding'] as String,
        raw['directory'] as String,
        name,
        List<int>.unmodifiable((raw['directoryIdentity'] as List).cast<int>()),
        Map<String, List<int>>.unmodifiable(files),
        List<String>.unmodifiable(changed.cast<String>()),
        configuration);
  }

  Map<String, Object> toJson() => {
        'binding': binding,
        'directory': directory,
        'romName': romName,
        'directoryIdentity': directoryIdentity,
        'files': files,
        if (configuration != null) 'saveRoot': configuration!.toJson(),
      };

  bool sameTarget(RomCompanionSnapshot other) =>
      binding == other.binding &&
      directory == other.directory &&
      romName == other.romName &&
      listEquals(directoryIdentity, other.directoryIdentity) &&
      configuration?.identity == other.configuration?.identity;
}

/// Current emulator configuration, not a guessed game/save association. A
/// ROM-relative setting needs the actual launched ROM's parent before resolving
/// its destination; the protected fallback is not silently substituted.
class MelonSaveSettings {
  final String? directory;
  final String extension;
  final bool savesBesideRom;
  MelonSaveSettings._(Map<String, dynamic>? row)
      : directory = row?['directory'] as String?,
        extension = row?['extension'] as String? ?? '',
        savesBesideRom = row?['mode'] == 'rom' {
    if (row == null ||
        !const {'rom', 'custom'}.contains(row['mode']) ||
        !const {'sav', 'srm'}.contains(extension) ||
        (savesBesideRom
            ? directory != null
            : directory == null ||
                !SaveCapture.validMelonDirectory(directory!))) {
      throw const FormatException('Invalid MelonDualDS save settings');
    }
  }
}

/// Explicit mGBA/Sega cartridge battery or PPSSPP published-slot capture, not a general
/// filesystem/ROM reader. Each native route uses its reviewed writer boundary.
class SaveCapture {
  static const _channel = MethodChannel('com.retro.rshop/save_capture');
  static bool validRomCompanionDirectory(String path) =>
      RegExp(r'^/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/.+$')
          .hasMatch(path) &&
      !RegExp(r'[\\\x00-\x1f\x7f]').hasMatch(path) &&
      path
          .split('/')
          .skip(1)
          .every((part) => part.isNotEmpty && part != '.' && part != '..');

  static bool validRomCompanionPath(String path) =>
      path.length <= 1024 &&
      path.split('/').length <= 16 &&
      path.split('/').every(
          (part) => validPpssppSavedataMember(part) && !part.startsWith('.'));
  static bool isolatedRomCompanionDirectory(String romName, String directory) =>
      romName.lastIndexOf('.') > 0 &&
      directory.split('/').last ==
          romName.substring(0, romName.lastIndexOf('.'));
  static bool validRomCompanionName(String romName, String name,
      {String? directory}) {
    final split = romName.lastIndexOf('.');
    if (split <= 0 || !validRomCompanionPath(name) || name == romName) {
      return false;
    }
    final stem = romName.substring(0, split);
    final isolated =
        directory != null && isolatedRomCompanionDirectory(romName, directory);
    final parts = name.split('/');
    if (!isolated &&
        (parts.length == 1
            ? !name.startsWith('$stem.')
            : parts.first != stem && !parts.first.startsWith('$stem.'))) {
      return false;
    }
    final leaf = parts.last;
    final suffix =
        (leaf.startsWith('$stem.') ? leaf.substring(stem.length + 1) : leaf)
            .toLowerCase();
    if (const {
      '7z',
      'zip',
      'rar',
      'gba',
      'gb',
      'gbc',
      'nes',
      'sfc',
      'smc',
      'n64',
      'z64',
      'v64',
      'nds',
      '3ds',
      'cia',
      'iso',
      'cso',
      'chd',
      'cue',
      'bin',
      'img',
      'pbp',
      'rvz',
      'gcm',
      'wbfs',
      'wua',
      'wad',
      'xci',
      'nsp',
      'sms',
      'gg',
      'md',
      'gen',
      'rom',
      'bios',
      'cfg',
      'ini',
      'conf',
      'config',
      'key',
      'pem',
      'p12',
      'pfx',
      'jks',
      'tmp',
      'part',
      'lock'
    }.contains(suffix.split('.').last)) {
      return false;
    }
    const excluded = {
      'credential',
      'credentials',
      'password',
      'passwords',
      'token',
      'tokens',
      'secret',
      'secrets',
      'bios',
      'settings',
      'config',
      'auth'
    };
    return !suffix.split(RegExp(r'[.\-_ ]')).any(excluded.contains) &&
        (isolated ||
            parts.length == 1 ||
            parts.first == stem ||
            !parts.first
                .substring(stem.length + 1)
                .toLowerCase()
                .split(RegExp(r'[.\-_ ]'))
                .any(excluded.contains)) &&
        !(parts.length == 1
                ? const Iterable<String>.empty()
                : isolated
                    ? parts.take(parts.length - 1)
                    : parts.skip(1).take(parts.length - 2))
            .any((part) => part
                .toLowerCase()
                .split(RegExp(r'[.\-_ ]'))
                .any(excluded.contains));
  }

  Future<RomCompanionSnapshot> reviewRomCompanions(
      {required Map<String, Object> grant,
      RomCompanionSnapshot? before}) async {
    final keys = grant.keys.toSet()..remove('saveRoot');
    final configured = grant['saveRoot'] == null
        ? null
        : SaveRootConfiguration.decode(
            Map<String, dynamic>.from(grant['saveRoot'] as Map));
    final owned = setEquals(keys, {'installationId', 'filename'}) &&
        grant['installationId'] is String &&
        (grant['installationId'] as String).trim().isNotEmpty;
    final observed =
        setEquals(keys, {'observationId', 'platformId', 'filename'}) &&
            grant['observationId'] is int &&
            (grant['observationId'] as int) > 0 &&
            grant['platformId'] is String &&
            (grant['platformId'] as String).isNotEmpty;
    final filename = grant['filename'];
    if (!(owned || observed) ||
        filename is! String ||
        filename.length > 4096 ||
        filename.split('/').any((part) => !validPpssppSavedataMember(part))) {
      throw const FormatException('Invalid ROM companion grant');
    }
    final result = RomCompanionSnapshot.decode(await _channel
        .invokeMapMethod<String, dynamic>('romCompanionSnapshot',
            {...grant, if (before != null) 'before': before.toJson()}));
    if (result.romName != filename.split('/').last ||
        configured?.identity != result.configuration?.identity ||
        configured != null && configured.directory != result.directory ||
        (before != null && !result.sameTarget(before))) {
      throw const FormatException('Changed ROM companion target');
    }
    if (before != null) {
      final changed = result.files.keys
          .where((path) => !listEquals(result.files[path], before.files[path]))
          .toSet();
      if (!setEquals(changed, result.changedFiles.toSet())) {
        throw const FormatException('Incomplete ROM companion changes');
      }
    } else if (result.changedFiles.isNotEmpty) {
      throw const FormatException('Unbound ROM companion changes');
    }
    return result;
  }

  Future<CapturedSaveGroup> captureRomCompanions(
      {required String captureId,
      required Map<String, Object> grant,
      required RomCompanionSnapshot snapshot,
      required Set<String> members,
      required String emulatorPackage,
      bool restoreBaseline = false}) async {
    final keys = grant.keys.toSet()..remove('saveRoot');
    final owned = setEquals(keys, {'installationId', 'filename'}) &&
        grant['installationId'] is String &&
        (grant['installationId'] as String).trim().isNotEmpty;
    final observed =
        setEquals(keys, {'observationId', 'platformId', 'filename'}) &&
            grant['observationId'] is int &&
            (grant['observationId'] as int) > 0 &&
            grant['platformId'] is String &&
            (grant['platformId'] as String).isNotEmpty;
    final filename = grant['filename'];
    if (!(owned || observed) ||
        filename is! String ||
        filename.length > 4096 ||
        filename.split('/').any((part) => !validPpssppSavedataMember(part)) ||
        filename.split('/').last != snapshot.romName ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(captureId) ||
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$')
            .hasMatch(emulatorPackage) ||
        members.isEmpty && !restoreBaseline ||
        members.length > 128 ||
        utf8.encode(jsonEncode(members.toList())).length > 32768 ||
        members.any((name) =>
            !(snapshot.configuration?.acceptsFile(name) ??
                validRomCompanionName(snapshot.romName, name,
                    directory: snapshot.directory)) ||
            !restoreBaseline && !snapshot.files.containsKey(name))) {
      throw const FormatException('Invalid ROM companion capture');
    }
    if (snapshot.configuration != null &&
        !restoreBaseline &&
        (!snapshot.configuration!.completeGroup(members) ||
            !setEquals(members, snapshot.files.keys.toSet()))) {
      throw const FormatException('Incomplete save group');
    }
    final names = members.toList()..sort();
    final raw = await _channel
        .invokeMapMethod<String, dynamic>('captureRomCompanions', {
      ...grant,
      'captureId': captureId,
      'binding': snapshot.binding,
      'members': names,
      'emulatorPackage': emulatorPackage,
      if (restoreBaseline) 'restoreBaseline': true,
    });
    final present = raw?['files'];
    final group = _captured(raw,
        captureId: captureId,
        allowedNames: members,
        requiredName: restoreBaseline &&
                present is List &&
                present.isNotEmpty &&
                present.first is Map
            ? (present.first as Map)['name'] as String? ?? ''
            : names.firstOrNull ?? '',
        maxSize: 512 * 1024 * 1024,
        restoreBaseline: restoreBaseline,
        allowEmptyFiles: true);
    if ((!restoreBaseline &&
            !setEquals(
                group.files.map((file) => file.name).toSet(), members)) ||
        group.files.fold<int>(0, (total, member) => total + member.size) >
            512 * 1024 * 1024) {
      throw const FormatException('Incomplete ROM companion capture');
    }
    return group;
  }

  /// On-demand, read-only package/provider metadata. No file scan or grant.
  Future<List<SaveEmulatorCoverage>> installedEmulators() async =>
      SaveEmulatorCoverage.decode(await _channel.invokeListMethod<dynamic>(
          'installedSaveEmulators',
          {'packages': SaveEmulatorCoverage.knownPackages.keys.toList()}));

  static bool validName(String name) =>
      name.length > 4 &&
      name.length <= 255 &&
      name.endsWith('.srm') &&
      !RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(name);

  Future<List<String>> retroArchNames() async {
    final result = await _channel.invokeListMethod<String>('retroArchNames');
    if (result == null ||
        result.length > 4096 ||
        result.toSet().length != result.length ||
        !result.every(validName)) {
      throw const FormatException('Invalid save selection');
    }
    return List.unmodifiable(result);
  }

  Future<CapturedSaveGroup> captureRetroArch(
      {required String captureId,
      required String name,
      RetroArchBatteryRoute route = RetroArchBatteryRoute.mgba,
      bool restoreBaseline = false}) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(captureId) || !validName(name)) {
      throw const FormatException('Invalid save selection');
    }
    final raw =
        await _channel.invokeMapMethod<String, dynamic>('captureRetroArch', {
      'captureId': captureId,
      'name': name,
      if (restoreBaseline) 'restoreBaseline': true,
      if (route != RetroArchBatteryRoute.mgba)
        'retroArchRoute': route.platformId
    });
    final group = _captured(raw,
        captureId: captureId,
        allowedNames: {
          name,
          if (route.includesRtc) '${name.substring(0, name.length - 4)}.rtc'
        },
        requiredName: name,
        maxSize: route.maxBytes,
        restoreBaseline: restoreBaseline);
    if (group.files.any((file) => !route.acceptsSize(file.size))) {
      throw const FormatException('Invalid cartridge save size');
    }
    return group;
  }

  Future<CapturedSaveGroup> capturePcsx(
      {required String captureId,
      required Map<String, Object> grant,
      required PcsxSaveLayout layout,
      required PcsxSaveCard card,
      bool restoreBaseline = false}) async {
    final selection = _pcsxArguments(grant, layout, card);
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(captureId)) {
      throw const FormatException('Invalid PlayStation capture');
    }
    final raw = await _channel.invokeMapMethod<String, dynamic>('capturePcsx', {
      'captureId': captureId,
      ...selection,
      if (restoreBaseline) 'restoreBaseline': true,
    });
    final group = _captured(raw,
        captureId: captureId,
        allowedNames: {card.name!},
        requiredName: card.name!,
        maxSize: 131072,
        restoreBaseline: restoreBaseline);
    if (group.files.any((file) => file.size != 131072)) {
      throw const FormatException('Incomplete PlayStation memory card');
    }
    return group;
  }

  Map<String, Object> _pcsxArguments(
      Map<String, Object> grant, PcsxSaveLayout layout, PcsxSaveCard card) {
    final owned = grant.keys.toSet().length == 2 &&
        grant.keys.toSet().containsAll({'installationId', 'filename'}) &&
        grant['installationId'] is String &&
        (grant['installationId'] as String).isNotEmpty;
    final observed = grant.keys.toSet().length == 3 &&
        grant.keys
            .toSet()
            .containsAll({'observationId', 'platformId', 'filename'}) &&
        grant['observationId'] is int &&
        (grant['observationId'] as int) > 0 &&
        grant['platformId'] == 'psx';
    if (!(owned || observed) ||
        grant['filename'] is! String ||
        !(grant['filename'] as String).toLowerCase().endsWith('.chd') ||
        !layout.cards.contains(card) ||
        card.name == null ||
        !const {'libretro', 'shared'}.contains(card.mode)) {
      throw const FormatException('Invalid PlayStation card selection');
    }
    return {
      ...grant,
      'directory': layout.directory,
      'slot': card.slot,
      'mode': card.mode,
      'name': card.name!,
    };
  }

  static bool validPpssppName(String name) =>
      RegExp(r'^[A-Z0-9]{9}_[0-9]\.[0-9]{2}_[0-9]{1,2}\.ppst$').hasMatch(name);

  static bool validPpssppSavedataMember(String name) =>
      name.isNotEmpty &&
      name.length <= 255 &&
      name != '.' &&
      name != '..' &&
      !name.startsWith('.rshop-') &&
      !name.endsWith('.') &&
      !name.endsWith(' ') &&
      !RegExp(r'[/\\:\x00-\x1f\x7f]').hasMatch(name);

  static bool validPpssppSavedataParent(String path) {
    if (!RegExp(
            r'^/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/(.+/)?[Pp][Ss][Pp]/SAVEDATA$')
        .hasMatch(path)) {
      return false;
    }
    final parts = path.split('/').skip(1);
    final protected = RegExp(
            r'^/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/Android/data/org\.ppsspp\.ppsspp/files(/.*)?/[Pp][Ss][Pp]/SAVEDATA$')
        .hasMatch(path);
    return parts.every((part) =>
            part.isNotEmpty &&
            part != '.' &&
            part != '..' &&
            !RegExp(r'[\\\x00-\x1f\x7f]').hasMatch(part)) &&
        (protected || parts.every((part) => part.toLowerCase() != 'android'));
  }

  static bool validPpssppSavedataDirectory(String path) {
    final split = path.lastIndexOf('/');
    return split > 0 &&
        validPpssppSavedataParent(path.substring(0, split)) &&
        validPpssppSavedataMember(path.substring(split + 1));
  }

  Future<String> ppssppSavedataParent() async {
    final states = await ppssppSaveDirectory();
    final parent =
        '${states.substring(0, states.length - '/PPSSPP_STATE'.length)}/SAVEDATA';
    if (!validPpssppSavedataParent(parent)) {
      throw const FormatException('Invalid PPSSPP save folder');
    }
    return parent;
  }

  Future<List<String>> ppssppSavedataFolders(String parent) async {
    if (!validPpssppSavedataParent(parent)) {
      throw const FormatException('Invalid PPSSPP save folder');
    }
    final names = await _channel.invokeListMethod<String>(
        'ppssppSavedataFolders', {'directory': parent});
    if (names == null ||
        names.length > 4096 ||
        names.toSet().length != names.length ||
        !names.every(validPpssppSavedataMember)) {
      throw const FormatException('Invalid PPSSPP save folders');
    }
    return List.unmodifiable(names);
  }

  Future<CapturedSaveGroup> capturePpssppSavedata(
      {required String captureId,
      required String directory,
      bool restoreBaseline = false}) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(captureId) ||
        !validPpssppSavedataDirectory(directory)) {
      throw const FormatException('Invalid PPSSPP save selection');
    }
    final raw = await _channel
        .invokeMapMethod<String, dynamic>('capturePpssppSavedata', {
      'captureId': captureId,
      'directory': directory,
      if (restoreBaseline) 'restoreBaseline': true,
    });
    final members = raw?['files'];
    if (members is! List || members.length > 128) {
      throw const FormatException('Invalid PPSSPP save group');
    }
    final names = <String>[];
    for (final member in members) {
      if (member is! Map ||
          member['name'] is! String ||
          !validPpssppSavedataMember(member['name'] as String)) {
        throw const FormatException('Invalid PPSSPP save member');
      }
      names.add(member['name'] as String);
    }
    final group = _captured(raw,
        captureId: captureId,
        allowedNames: names.toSet(),
        requiredName: names.firstOrNull ?? '',
        maxSize: 512 * 1024 * 1024,
        restoreBaseline: restoreBaseline,
        allowEmptyFiles: true);
    if (group.files.fold<int>(0, (total, member) => total + member.size) >
        512 * 1024 * 1024) {
      throw const FormatException('Invalid PPSSPP save group size');
    }
    return group;
  }

  /// Resolve the installed emulator's Memory Stick choice; never search guessed
  /// folders or change emulator settings. Native code reads only that setting.
  Future<String> ppssppSaveDirectory() async {
    final row =
        await _channel.invokeMapMethod<String, dynamic>('ppssppSaveSettings');
    final directory = row?['directory'];
    if (row == null ||
        row.length != 1 ||
        directory is! String ||
        !validPpssppDirectory(directory)) {
      throw const FormatException('Invalid PPSSPP save settings');
    }
    return directory;
  }

  static bool validPpssppDirectory(String path) {
    if (!RegExp(
            r'^/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/.+/PPSSPP_STATE$')
        .hasMatch(path)) {
      return false;
    }
    final parts = path.split('/').skip(1);
    final protected = RegExp(
            r'^/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/Android/data/org\.ppsspp\.ppsspp/files/.+/PPSSPP_STATE$')
        .hasMatch(path);
    return parts.every((part) =>
            part.isNotEmpty &&
            part != '.' &&
            part != '..' &&
            !RegExp(r'[\\\x00-\x1f\x7f]').hasMatch(part)) &&
        (protected || parts.every((part) => part.toLowerCase() != 'android'));
  }

  Future<List<String>> ppssppNames(String directory) async {
    if (!validPpssppDirectory(directory)) {
      throw const FormatException('Invalid PPSSPP mapping');
    }
    final names = await _channel
        .invokeListMethod<String>('ppssppNames', {'directory': directory});
    if (names == null ||
        names.length > 4096 ||
        names.toSet().length != names.length ||
        !names.every(validPpssppName)) {
      throw const FormatException('Invalid PPSSPP selection');
    }
    return List.unmodifiable(names);
  }

  /// Pins and verifies a selected completed PPSSPP state slot. Temporary and
  /// undo slots are excluded; game association remains explicitly reviewed.
  Future<CapturedSaveGroup> capturePpsspp(
          {required String captureId,
          required String directory,
          required String name,
          bool restoreBaseline = false}) =>
      _capturePpssppFile(
          captureId: captureId,
          directory: directory,
          name: name,
          restoreBaseline: restoreBaseline,
          companion: false);

  static bool validPpssppCompanionName(String name) =>
      RegExp(r'^[A-Z0-9]{9}_[0-9]\.[0-9]{2}_[0-9]{1,2}\.jpg$').hasMatch(name);

  static String ppssppScreenshotName(String state) {
    if (!validPpssppName(state)) {
      throw const FormatException('Invalid PPSSPP state slot');
    }
    return '${state.substring(0, state.length - 5)}.jpg';
  }

  Future<CapturedSaveGroup> capturePpssppCompanion(
          {required String captureId,
          required String directory,
          required String name,
          bool restoreBaseline = false}) =>
      _capturePpssppFile(
          captureId: captureId,
          directory: directory,
          name: name,
          restoreBaseline: restoreBaseline,
          companion: true);

  Future<CapturedSaveGroup> _capturePpssppFile(
      {required String captureId,
      required String directory,
      required String name,
      required bool restoreBaseline,
      required bool companion}) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(captureId) ||
        !(companion ? validPpssppCompanionName(name) : validPpssppName(name)) ||
        !validPpssppDirectory(directory)) {
      throw const FormatException('Invalid PPSSPP state selection');
    }
    final raw = await _channel.invokeMapMethod<String, dynamic>(
        companion ? 'capturePpssppCompanion' : 'capturePpsspp', {
      'captureId': captureId,
      'directory': directory,
      'name': name,
      if (restoreBaseline) 'restoreBaseline': true
    });
    return _captured(raw,
        captureId: captureId,
        allowedNames: {name},
        requiredName: name,
        maxSize: 256 * 1024 * 1024,
        restoreBaseline: restoreBaseline);
  }

  static bool validMelonName(String name) =>
      name.length > 4 &&
      name.length <= 255 &&
      (name.endsWith('.sav') || name.endsWith('.srm')) &&
      !RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(name);

  static const melonStandardDirectory =
      '/storage/emulated/0/Android/data/me.magnum.melondualds/files/saves';

  Future<MelonSaveSettings> melonSaveSettings() async => MelonSaveSettings._(
      await _channel.invokeMapMethod<String, dynamic>('melonSaveSettings'));

  static bool validMelonDirectory(String path) =>
      path == melonStandardDirectory ||
      RegExp(r'^/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/.+$')
              .hasMatch(path) &&
          path.split('/').skip(1).every((part) =>
              part.isNotEmpty &&
              part != '.' &&
              part != '..' &&
              part.toLowerCase() != 'android' &&
              !RegExp(r'[\\\x00-\x1f\x7f]').hasMatch(part));

  Future<List<String>> melonNames(String directory) async {
    if (!validMelonDirectory(directory)) {
      throw const FormatException('Invalid MelonDualDS folder');
    }
    final names = await _channel
        .invokeListMethod<String>('melonNames', {'directory': directory});
    if (names == null ||
        names.length > 4096 ||
        names.toSet().length != names.length ||
        !names.every(validMelonName)) {
      throw const FormatException('Invalid MelonDualDS selection');
    }
    return List.unmodifiable(names);
  }

  Future<CapturedSaveGroup> captureMelon(
      {required String captureId,
      required String directory,
      required String name,
      bool restoreBaseline = false}) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(captureId) ||
        !validMelonDirectory(directory) ||
        !validMelonName(name)) {
      throw const FormatException('Invalid MelonDualDS save selection');
    }
    final raw =
        await _channel.invokeMapMethod<String, dynamic>('captureMelon', {
      'captureId': captureId,
      'directory': directory,
      'name': name,
      if (restoreBaseline) 'restoreBaseline': true
    });
    return _captured(raw,
        captureId: captureId,
        allowedNames: {name},
        requiredName: name,
        maxSize: 64 * 1024 * 1024,
        restoreBaseline: restoreBaseline);
  }

  CapturedSaveGroup _captured(Map<String, dynamic>? raw,
      {required String captureId,
      required Set<String> allowedNames,
      required String requiredName,
      required int maxSize,
      bool restoreBaseline = false,
      bool allowEmptyFiles = false}) {
    if (raw == null ||
        raw['captureId'] != captureId ||
        raw['deviceId'] is! String ||
        (raw['deviceId'] as String).isEmpty ||
        raw['emulatorVersion'] is! String ||
        (raw['emulatorVersion'] as String).isEmpty ||
        raw['files'] is! List) {
      throw const FormatException('Invalid captured group');
    }
    if (raw['coreVersion'] != null &&
        (raw['coreVersion'] is! String ||
            (raw['coreVersion'] as String).isEmpty ||
            (raw['coreVersion'] as String).length > 512 ||
            RegExp(r'[\x00-\x1f\x7f]')
                .hasMatch(raw['coreVersion'] as String))) {
      throw const FormatException('Invalid captured runtime');
    }
    final files = <CapturedSaveFile>[];
    final seen = <String>{};
    final paths = <String>{};
    for (final item in raw['files'] as List) {
      if (item is! Map ||
          item['name'] is! String ||
          item['path'] is! String ||
          item['size'] is! int ||
          item['sha256'] is! String) {
        throw const FormatException('Invalid captured member');
      }
      final member = item['name'] as String;
      final path = item['path'] as String;
      if (!allowedNames.contains(member) ||
          !seen.add(member) ||
          !paths.add(path) ||
          !path.startsWith('/') ||
          path.split('/').contains('..') ||
          (item['size'] as int) < (allowEmptyFiles ? 0 : 1) ||
          (item['size'] as int) > maxSize ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(item['sha256'] as String)) {
        throw const FormatException('Invalid captured member');
      }
      files.add(CapturedSaveFile(
          member, File(path), item['size'] as int, item['sha256'] as String));
    }
    final absent = raw['localWasAbsent'] == true;
    if (absent && (!restoreBaseline || files.isNotEmpty)) {
      throw const FormatException('Invalid absence receipt');
    }
    if ((!absent && files.isEmpty) ||
        files.length > allowedNames.length ||
        (!absent && !seen.contains(requiredName))) {
      throw const FormatException('Incomplete captured group');
    }
    return CapturedSaveGroup(captureId, raw['deviceId'] as String,
        raw['emulatorVersion'] as String, files,
        localWasAbsent: absent, coreVersion: raw['coreVersion'] as String?);
  }

  Future<void> cancel(String captureId) =>
      _channel.invokeMethod('cancel', {'captureId': captureId});

  /// Only after a durable journal intent proves this private copy redundant.
  Future<void> retireCapture(String captureId) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(captureId)) {
      throw const FormatException('Invalid capture retirement');
    }
    await _channel
        .invokeMethod<void>('retireCapture', {'captureId': captureId});
  }

  Future<void> openRetroArch() => _channel.invokeMethod('openRetroArch');
  Future<void> openPpsspp() => _channel.invokeMethod('openPpsspp');
  Future<void> openPpssppAppInfo() =>
      _channel.invokeMethod('openPpssppAppInfo');
  Future<void> openMelon() => _channel.invokeMethod('openMelon');
  Future<void> openMelonAppInfo() => _channel.invokeMethod('openMelonAppInfo');

  Future<void> stageRestore(
      {required String restoreId,
      required String name,
      required int size,
      required String sha256,
      String? ppssppDirectory,
      bool ppssppCompanion = false,
      String? melonDirectory,
      RetroArchBatteryRoute retroArchRoute = RetroArchBatteryRoute.mgba,
      required Stream<Uint8List> bytes}) async {
    final ppsspp = ppssppDirectory != null;
    final melon = melonDirectory != null;
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(restoreId) ||
        (ppssppCompanion && !ppsspp) ||
        (ppsspp && melon) ||
        !(melon
            ? validMelonName(name)
            : ppsspp
                ? (ppssppCompanion
                    ? validPpssppCompanionName(name)
                    : validPpssppName(name))
                : validName(name)) ||
        (melon && !validMelonDirectory(melonDirectory)) ||
        (ppsspp && !validPpssppDirectory(ppssppDirectory)) ||
        ((ppsspp || melon) && retroArchRoute != RetroArchBatteryRoute.mgba) ||
        (!ppsspp && !melon && !retroArchRoute.acceptsSize(size)) ||
        size <= 0 ||
        size >
            (melon
                ? 64 * 1024 * 1024
                : ppsspp
                    ? 256 * 1024 * 1024
                    : retroArchRoute.maxBytes) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('Invalid restore selection');
    }
    await _channel.invokeMethod('beginRestore', {
      'captureId': restoreId,
      'name': name,
      'size': size,
      'sha256': sha256,
      if (ppsspp) 'ppssppDirectory': ppssppDirectory,
      if (ppssppCompanion) 'ppssppCompanion': true,
      if (melon) 'melonDirectory': melonDirectory,
      if (retroArchRoute != RetroArchBatteryRoute.mgba)
        'retroArchRoute': retroArchRoute.platformId,
    });
    await _streamRestore(restoreId, size, bytes);
  }

  Future<void> stagePcsxRestore(
      {required String restoreId,
      required Map<String, Object> grant,
      required PcsxSaveLayout layout,
      required PcsxSaveCard card,
      required int size,
      required String sha256,
      required Stream<Uint8List> bytes}) async {
    final selection = _pcsxArguments(grant, layout, card);
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(restoreId) ||
        size != 131072 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('Invalid PlayStation restore');
    }
    await _channel.invokeMethod('beginPcsxRestore', {
      'captureId': restoreId,
      ...selection,
      'size': size,
      'sha256': sha256,
    });
    await _streamRestore(restoreId, size, bytes);
  }

  Future<void> _streamRestore(
      String restoreId, int size, Stream<Uint8List> bytes) async {
    var offset = 0;
    await for (final chunk in bytes) {
      if (offset + chunk.length > size) {
        throw const FormatException('Invalid restore length');
      }
      for (var begin = 0; begin < chunk.length; begin += 65536) {
        final end = begin + 65536 < chunk.length ? begin + 65536 : chunk.length;
        final part = Uint8List.sublistView(chunk, begin, end);
        final next = await _channel.invokeMethod<int>('appendRestore',
            {'captureId': restoreId, 'offset': offset, 'bytes': part});
        if (next != offset + part.length) {
          throw const FormatException('Invalid restore acknowledgement');
        }
        offset = next!;
      }
    }
    // Transport checks its digest/revision after its last yielded chunk. Only
    // normal EOF can authorize sealing; full byte count alone is insufficient.
    if (offset != size) throw const FormatException('Incomplete restore');
    await _channel.invokeMethod('sealRestore', {'captureId': restoreId});
  }

  Future<void> publishRestore(
      {required String restoreId, required String rollbackCaptureId}) async {
    if (![restoreId, rollbackCaptureId]
            .every((id) => RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) ||
        restoreId == rollbackCaptureId) {
      throw const FormatException('Invalid restore publication');
    }
    await _channel.invokeMethod('publishRestore',
        {'captureId': restoreId, 'rollbackCaptureId': rollbackCaptureId});
  }

  Future<void> publishPcsxRestore(
      {required String restoreId,
      required String rollbackCaptureId,
      required Map<String, Object> grant,
      required PcsxSaveLayout layout,
      required PcsxSaveCard card}) async {
    final selection = _pcsxArguments(grant, layout, card);
    if (![restoreId, rollbackCaptureId]
            .every((id) => RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) ||
        restoreId == rollbackCaptureId) {
      throw const FormatException('Invalid PlayStation publication');
    }
    await _channel.invokeMethod('publishPcsxRestore', {
      'captureId': restoreId,
      'rollbackCaptureId': rollbackCaptureId,
      ...selection,
    });
  }

  /// SRAM and its paired clock file are sealed together before either
  /// public file changes. Native journals retain per-file atomic receipts so
  /// interrupted group publication can resume without discarding rollback bytes.
  Future<void> stageRetroArchGroupRestore(
      {required String restoreId,
      required String name,
      RetroArchBatteryRoute route = RetroArchBatteryRoute.mgba,
      required List<RestoreSaveMember> members}) async {
    if (!validName(name) || !route.includesRtc) {
      throw const FormatException('Invalid related save group');
    }
    final allowed = {name, '${name.substring(0, name.length - 4)}.rtc'};
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(restoreId) ||
        members.length != 2 ||
        members.map((m) => m.name).toSet().length != 2 ||
        members.any((m) =>
            !allowed.contains(m.name) ||
            m.size <= 0 ||
            !route.acceptsSize(m.size) ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(m.sha256))) {
      throw const FormatException('Invalid related save group');
    }
    await _stageGroupRestore(
        restoreId: restoreId,
        name: name,
        members: members,
        retroArchRoute: route);
  }

  Future<void> stagePpssppSavedataRestore(
      {required String restoreId,
      required String directory,
      required List<RestoreSaveMember> members}) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(restoreId) ||
        !validPpssppSavedataDirectory(directory) ||
        members.isEmpty ||
        members.length > 128 ||
        members.map((member) => member.name).toSet().length != members.length ||
        members.any((member) =>
            !validPpssppSavedataMember(member.name) ||
            member.size < 0 ||
            member.size > 512 * 1024 * 1024 ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(member.sha256) ||
            (member.size == 0 &&
                member.sha256 !=
                    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')) ||
        members.fold<int>(0, (size, member) => size + member.size) >
            512 * 1024 * 1024) {
      throw const FormatException('Invalid PPSSPP restore folder');
    }
    await _stageGroupRestore(
        restoreId: restoreId,
        name: directory.substring(directory.lastIndexOf('/') + 1),
        members: members,
        ppssppSavedataDirectory: directory);
  }

  Future<void> stageRomCompanionRestore(
      {required String restoreId,
      required Map<String, Object> grant,
      required RomCompanionSnapshot snapshot,
      required String emulatorPackage,
      Map<String, String>? expectedRuntime,
      required List<RestoreSaveMember> members}) async {
    final keys = grant.keys.toSet()..remove('saveRoot');
    final owned = setEquals(keys, {'installationId', 'filename'}) &&
        grant['installationId'] is String &&
        (grant['installationId'] as String).trim().isNotEmpty;
    final observed =
        setEquals(keys, {'observationId', 'platformId', 'filename'}) &&
            grant['observationId'] is int &&
            (grant['observationId'] as int) > 0 &&
            grant['platformId'] is String &&
            (grant['platformId'] as String).isNotEmpty;
    final filename = grant['filename'];
    if (!(owned || observed) ||
        filename is! String ||
        filename.length > 4096 ||
        filename.split('/').any((part) => !validPpssppSavedataMember(part)) ||
        filename.split('/').last != snapshot.romName ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(restoreId) ||
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$')
            .hasMatch(emulatorPackage) ||
        members.isEmpty ||
        members.length > 128 ||
        utf8
                .encode(
                    jsonEncode(members.map((member) => member.name).toList()))
                .length >
            32768 ||
        members.map((member) => member.name).toSet().length != members.length ||
        members.any((member) =>
            !(snapshot.configuration?.acceptsFile(member.name) ??
                validRomCompanionName(snapshot.romName, member.name,
                    directory: snapshot.directory)) ||
            member.size < 0 ||
            member.size > 512 * 1024 * 1024 ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(member.sha256) ||
            (member.size == 0 &&
                member.sha256 !=
                    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')) ||
        members.fold<int>(0, (size, member) => size + member.size) >
            512 * 1024 * 1024) {
      throw const FormatException('Invalid ROM companion restoration');
    }
    await _stageGroupRestore(
        restoreId: restoreId,
        name: snapshot.romName,
        members: members,
        romCompanion: {
          ...grant,
          'binding': snapshot.binding,
          'emulatorPackage': emulatorPackage,
          if (expectedRuntime != null) 'expectedRuntime': expectedRuntime,
        });
  }

  Future<void> _stageGroupRestore(
      {required String restoreId,
      required String name,
      required List<RestoreSaveMember> members,
      RetroArchBatteryRoute retroArchRoute = RetroArchBatteryRoute.mgba,
      String? ppssppSavedataDirectory,
      Map<String, Object>? romCompanion}) async {
    final ordered = members.toList()..sort((a, b) => a.name.compareTo(b.name));
    await _channel.invokeMethod('beginRestoreGroup', {
      'captureId': restoreId,
      'name': name,
      if (romCompanion != null) ...romCompanion,
      if (retroArchRoute != RetroArchBatteryRoute.mgba)
        'retroArchRoute': retroArchRoute.platformId,
      if (ppssppSavedataDirectory != null)
        'ppssppSavedataDirectory': ppssppSavedataDirectory,
      'members': ordered
          .map((m) => {'name': m.name, 'size': m.size, 'sha256': m.sha256})
          .toList(),
    });
    for (var index = 0; index < ordered.length; index++) {
      final member = ordered[index];
      var offset = 0;
      await for (final chunk in member.bytes) {
        if (offset + chunk.length > member.size) {
          throw const FormatException('Invalid group member length');
        }
        for (var begin = 0; begin < chunk.length; begin += 65536) {
          final end = (begin + 65536).clamp(0, chunk.length);
          final part = Uint8List.sublistView(chunk, begin, end);
          final next = await _channel.invokeMethod<int>('appendRestoreGroup', {
            'captureId': restoreId,
            'member': index,
            'offset': offset,
            'bytes': part,
          });
          if (next != offset + part.length) {
            throw const FormatException(
                'Invalid group restore acknowledgement');
          }
          offset = next!;
        }
      }
      if (offset != member.size) {
        throw const FormatException('Incomplete group restore');
      }
    }
    await _channel.invokeMethod('sealRestoreGroup', {'captureId': restoreId});
  }

  Future<void> publishRestoreGroup(
      {required String restoreId, required String rollbackCaptureId}) async {
    if (![restoreId, rollbackCaptureId]
            .every((id) => RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) ||
        restoreId == rollbackCaptureId) {
      throw const FormatException('Invalid group publication');
    }
    await _channel.invokeMethod('publishRestoreGroup', {
      'captureId': restoreId,
      'rollbackCaptureId': rollbackCaptureId,
    });
  }
}
