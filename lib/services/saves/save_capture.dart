import 'dart:io';

import 'package:flutter/services.dart';

import '../../models/save_emulator_coverage.dart';
import '../../models/retroarch_battery_route.dart';

class CapturedSaveFile {
  final String name, sha256;
  final File file;
  final int size;
  CapturedSaveFile(this.name, this.file, this.size, this.sha256);
}

class CapturedSaveGroup {
  final String captureId, deviceId, emulatorVersion;
  final List<CapturedSaveFile> files;
  CapturedSaveGroup(this.captureId, this.deviceId, this.emulatorVersion,
      List<CapturedSaveFile> files)
      : files = List.unmodifiable(files);
}

/// Explicit mGBA/Game Gear battery or PPSSPP published-slot capture, not a general
/// filesystem/ROM reader. Each native route uses its reviewed writer boundary.
class SaveCapture {
  static const _channel = MethodChannel('com.retro.rshop/save_capture');

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
      RetroArchBatteryRoute route = RetroArchBatteryRoute.mgba}) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(captureId) || !validName(name)) {
      throw const FormatException('Invalid save selection');
    }
    final raw =
        await _channel.invokeMapMethod<String, dynamic>('captureRetroArch', {
      'captureId': captureId,
      'name': name,
      if (route != RetroArchBatteryRoute.mgba)
        'retroArchRoute': route.platformId
    });
    return _captured(raw,
        captureId: captureId,
        allowedNames: {
          name,
          if (route.includesRtc) '${name.substring(0, name.length - 4)}.rtc'
        },
        requiredName: name,
        maxSize: route.maxBytes);
  }

  static bool validPpssppName(String name) =>
      RegExp(r'^[A-Z0-9]{9}_[0-9]\.[0-9]{2}_[0-9]{1,2}\.ppst$').hasMatch(name);

  static bool validPpssppDirectory(String path) {
    if (!RegExp(
            r'^/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/.+/PPSSPP_STATE$')
        .hasMatch(path)) {
      return false;
    }
    return path.split('/').skip(1).every((part) =>
        part.isNotEmpty &&
        part != '.' &&
        part != '..' &&
        part.toLowerCase() != 'android' &&
        !RegExp(r'[\\\x00-\x1f\x7f]').hasMatch(part));
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
      required String name}) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(captureId) ||
        !validPpssppName(name) ||
        !validPpssppDirectory(directory)) {
      throw const FormatException('Invalid PPSSPP state selection');
    }
    final raw = await _channel.invokeMapMethod<String, dynamic>('capturePpsspp',
        {'captureId': captureId, 'directory': directory, 'name': name});
    return _captured(raw,
        captureId: captureId,
        allowedNames: {name},
        requiredName: name,
        maxSize: 256 * 1024 * 1024);
  }

  CapturedSaveGroup _captured(Map<String, dynamic>? raw,
      {required String captureId,
      required Set<String> allowedNames,
      required String requiredName,
      required int maxSize}) {
    if (raw == null ||
        raw['captureId'] != captureId ||
        raw['deviceId'] is! String ||
        (raw['deviceId'] as String).isEmpty ||
        raw['emulatorVersion'] is! String ||
        (raw['emulatorVersion'] as String).isEmpty ||
        raw['files'] is! List) {
      throw const FormatException('Invalid captured group');
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
          (item['size'] as int) <= 0 ||
          (item['size'] as int) > maxSize ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(item['sha256'] as String)) {
        throw const FormatException('Invalid captured member');
      }
      files.add(CapturedSaveFile(
          member, File(path), item['size'] as int, item['sha256'] as String));
    }
    if (files.isEmpty ||
        files.length > allowedNames.length ||
        !seen.contains(requiredName)) {
      throw const FormatException('Incomplete captured group');
    }
    return CapturedSaveGroup(captureId, raw['deviceId'] as String,
        raw['emulatorVersion'] as String, files);
  }

  Future<void> cancel(String captureId) =>
      _channel.invokeMethod('cancel', {'captureId': captureId});
  Future<void> openRetroArch() => _channel.invokeMethod('openRetroArch');
  Future<void> openPpsspp() => _channel.invokeMethod('openPpsspp');
  Future<void> openPpssppAppInfo() =>
      _channel.invokeMethod('openPpssppAppInfo');

  Future<void> stageRestore(
      {required String restoreId,
      required String name,
      required int size,
      required String sha256,
      String? ppssppDirectory,
      RetroArchBatteryRoute retroArchRoute = RetroArchBatteryRoute.mgba,
      required Stream<Uint8List> bytes}) async {
    final ppsspp = ppssppDirectory != null;
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(restoreId) ||
        !(ppsspp ? validPpssppName(name) : validName(name)) ||
        (ppsspp && !validPpssppDirectory(ppssppDirectory)) ||
        (ppsspp && retroArchRoute != RetroArchBatteryRoute.mgba) ||
        size <= 0 ||
        size > (ppsspp ? 256 * 1024 * 1024 : retroArchRoute.maxBytes) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('Invalid restore selection');
    }
    await _channel.invokeMethod('beginRestore', {
      'captureId': restoreId,
      'name': name,
      'size': size,
      'sha256': sha256,
      if (ppsspp) 'ppssppDirectory': ppssppDirectory,
      if (retroArchRoute != RetroArchBatteryRoute.mgba)
        'retroArchRoute': retroArchRoute.platformId,
    });
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
}
