import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import '../services/socket_media_import.dart';
import 'socket_media_model.dart';

/// Independent local imports, never replacing the cartridge resource bundle.
class ConsoleModel {
  final String systemId;
  final Directory directory;
  final String generation;
  final String? romSet;
  final String? visualVariantId;
  String get hardwareId => romSet ?? visualVariantId ?? '';
  final bool canOpen;
  final bool isBox;
  final int openingDurationMs;
  ConsoleModel._(this.systemId, this.directory, this.generation,
      {this.romSet,
      this.visualVariantId,
      this.canOpen = false,
      this.isBox = false,
      this.openingDurationMs = 2000});

  // Hardware identity is the MAME set, not a game title. Crystal, Silver and
  // Panorama variants deliberately do not borrow their similarly named models.
  static const gameWatchSets = {
    'gnw_dkong',
    'gnw_dkjr',
    'gnw_zelda',
    'auslalom',
    'gnw_mariocm',
    'gnw_mmouse',
    'gnw_pchute',
    'gnw_smbn',
    'gnw_chef',
    'gnw_fire',
    'gnw_octopus',
    'gnw_dkong2',
    'gnw_mario',
    'gnw_bjack',
    'gnw_ghouse',
    'gnw_mickdon',
    'gnw_pinball',
    'gnw_bsweep',
    'gnw_gcliff',
    'gnw_lboat',
    'gnw_opanic',
    'gnw_rshower',
    'gnw_sbuster',
    'gnw_squish',
    'gnw_smb',
    'gnw_ssparky',
    'gnw_snoopyp',
    'gnw_boxing',
  };
  static const gameWatchBoxSets = {
    'gnw_ghouse',
    'gnw_dkong',
    'gnw_dkong2',
    'gnw_bjack',
    'gnw_opanic',
    'gnw_bsweep',
    'gnw_mario',
    'gnw_rshower',
  };
  static String? gameWatchSet(String filename) {
    final leaf = filename.split(RegExp(r'[/\\]')).last;
    // Exact No-Intro release aliases observed in the owner's collection. These
    // bind hardware editions explicitly, not a normalized/fuzzy game title.
    final release = gameWatchReleases[leaf];
    if (release != null) return release;
    final match = RegExp(r'^([a-z0-9_]+)\.(?:zip|7z)$').firstMatch(leaf);
    final set = match?.group(1);
    return gameWatchSets.contains(set) ? set : null;
  }

  static const gameWatchReleases = {
    'Donkey Kong (World).7z': 'gnw_dkong',
    'Donkey Kong Jr. (World) (New Wide Screen).7z': 'gnw_dkjr',
    'Zelda (World).7z': 'gnw_zelda',
    "Mario's Cement Factory (World) (New Wide Screen).7z": 'gnw_mariocm',
    'Mickey Mouse ~ Egg (World) (Wide Screen).7z': 'gnw_mmouse',
    'Parachute (World).7z': 'gnw_pchute',
    'Super Mario Bros. (World).7z': 'gnw_smbn',
    'Chef (World).7z': 'gnw_chef',
    'Fire (World) (Wide Screen).7z': 'gnw_fire',
    'Octopus (World).7z': 'gnw_octopus',
    'Donkey Kong II (World).7z': 'gnw_dkong2',
    'Mario Bros. (World).7z': 'gnw_mario',
    'Black Jack (World).7z': 'gnw_bjack',
    'Bomb Sweeper (World).7z': 'gnw_bsweep',
    'Boxing (World).7z': 'gnw_boxing',
    'Gold Cliff (World).7z': 'gnw_gcliff',
    'Green House (World).7z': 'gnw_ghouse',
    'Lifeboat (World).7z': 'gnw_lboat',
    'Mickey & Donald (World).7z': 'gnw_mickdon',
    'Oil Panic (World).7z': 'gnw_opanic',
    'Pinball (World).7z': 'gnw_pinball',
    'Rain Shower (World).7z': 'gnw_rshower',
    'Safe Buster (World).7z': 'gnw_sbuster',
    'Snoopy (World).7z': 'gnw_snoopyp',
    'Spitball Sparky (World).7z': 'gnw_ssparky',
    'Squish (World).7z': 'gnw_squish',
  };

  static Future<ConsoleModel?> findGameWatch(String filename,
      {Directory? modelsDirectory, bool box = false}) async {
    final set = gameWatchSet(filename);
    if (set == null ||
        box && !gameWatchBoxSets.contains(set) ||
        modelsDirectory == null && !Platform.isAndroid) {
      return null;
    }
    final root =
        modelsDirectory ?? Directory('/storage/emulated/0/RShop/models');
    final dir = Directory(
        '${root.path}/${box ? 'boxes' : 'handhelds'}/gameandwatch/$set');
    return _gameWatchImport(dir, romSet: set, box: box);
  }

  static Future<ConsoleModel?> _gameWatchImport(Directory dir,
      {String? romSet, String? visualVariantId, bool box = false}) async {
    final manifest = File('${dir.path}/model.json');
    if (!await manifest.exists()) return null;
    if (await manifest.length() > 1024 * 1024) {
      throw const FormatException('Handheld manifest exceeds import size');
    }
    final bytes = await manifest.readAsBytes();
    final data = jsonDecode(utf8.decode(bytes)) as Map;
    final duration = data['openingDurationMs'] ?? 2000;
    if (duration is! int || duration < 50 || duration > 10000) {
      throw const FormatException('Invalid handheld animation duration');
    }
    return ConsoleModel._('gameandwatch', dir, sha256.convert(bytes).toString(),
        romSet: romSet,
        visualVariantId: visualVariantId,
        isBox: box,
        canOpen: data['canOpen'] == true,
        openingDurationMs: duration);
  }

  /// Visual group membership is explicit private import data. It never changes
  /// exact-ROM lookup, library cards, launch identity or missing-model coverage.
  static Future<List<GameWatchModelVariant>> findGameWatchVariants(
      String filename,
      {Directory? modelsDirectory}) async {
    final primary =
        await findGameWatch(filename, modelsDirectory: modelsDirectory);
    if (primary == null) return const [];
    final single = [GameWatchModelVariant(primary, null)];
    final root =
        modelsDirectory ?? Directory('/storage/emulated/0/RShop/models');
    final hardware = Directory('${root.path}/handhelds/gameandwatch');
    final index = File('${hardware.path}/variants.json');
    if (!await index.exists()) return single;
    if (await index.length() > 256 * 1024) {
      throw const FormatException(
          'Visual variant catalogue exceeds import size');
    }
    final data = jsonDecode(await index.readAsString());
    if (data is! Map || data['schemaVersion'] != 1 || data['groups'] is! List) {
      throw const FormatException('Invalid visual variant catalogue');
    }
    final declared = <String>{};
    Map? group;
    for (final entry in data['groups'] as List) {
      if (entry is! Map ||
          entry['sets'] is! List ||
          (entry['sets'] as List).isEmpty ||
          entry['models'] is! List) {
        throw const FormatException('Invalid visual variant group');
      }
      for (final set in entry['sets'] as List) {
        if (set is! String ||
            !gameWatchSets.contains(set) ||
            !declared.add(set)) {
          throw const FormatException('Ambiguous visual variant group');
        }
        if (set == primary.romSet) group = entry;
      }
    }
    if (group == null) return single;
    final variants = <GameWatchModelVariant>[];
    final paths = <String>{};
    GameWatchModelVariant? selected;
    for (final entry in group['models'] as List) {
      if (entry is! Map ||
          entry['directory'] is! String ||
          entry['label'] is! String ||
          (entry['label'] as String).trim().isEmpty ||
          (entry['label'] as String).length > 80) {
        throw const FormatException('Invalid visual variant entry');
      }
      final path = entry['directory'] as String;
      final visual = RegExp(r'^variants/([a-z0-9_-]+)$').firstMatch(path);
      if ((!gameWatchSets.contains(path) && visual == null) ||
          !paths.add(path)) {
        throw const FormatException('Invalid visual variant directory');
      }
      final model = path == primary.romSet
          ? primary
          : visual != null
              ? await _gameWatchImport(Directory('${hardware.path}/$path'),
                  visualVariantId: visual.group(1))
              : await findGameWatch('$path.zip', modelsDirectory: root);
      if (model == null) continue; // Optional, not yet imported hardware.
      final variant = GameWatchModelVariant(model, entry['label'] as String);
      if (path == primary.romSet) {
        selected = variant;
      } else {
        variants.add(variant);
      }
    }
    if (selected == null) {
      throw const FormatException('Visual group omits its exact primary');
    }
    return [selected, ...variants];
  }

  static Future<ConsoleModel?> find(String systemId,
      {Directory? modelsDirectory}) async {
    if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(systemId)) {
      throw const FormatException('Invalid console model system');
    }
    if (modelsDirectory == null && !Platform.isAndroid) return null;
    final root =
        modelsDirectory ?? Directory('/storage/emulated/0/RShop/models');
    final dir = Directory('${root.path}/consoles/$systemId');
    final manifest = File('${dir.path}/model.json');
    if (!await manifest.exists()) return null;
    if (await manifest.length() > 1024 * 1024) {
      throw const FormatException('Console manifest exceeds import size');
    }
    return ConsoleModel._(
        systemId, dir, sha256.convert(await manifest.readAsBytes()).toString());
  }

  Future<SocketMediaModel> load() async {
    final manifest = await File('${directory.path}/model.json').readAsBytes();
    if (manifest.length > 1024 * 1024 ||
        sha256.convert(manifest).toString() != generation) {
      throw const FormatException('Console import changed during selection');
    }
    final data = jsonDecode(utf8.decode(manifest)) as Map<String, dynamic>;
    if (data['system'] != systemId ||
        romSet != null && data['romSet'] != romSet ||
        visualVariantId != null &&
            (data['visualVariantId'] != visualVariantId ||
                data['romSet'] != null) ||
        (romSet != null || visualVariantId != null) &&
            (data['resourceKind'] ?? 'handheld') !=
                (isBox ? 'box' : 'handheld') ||
        data['motionKind'] != 'hardware' ||
        data['sourceWidth'] is! num ||
        !(data['sourceWidth'] as num).isFinite ||
        (data['sourceWidth'] as num) <= 0 ||
        data['bounds'] is! List ||
        (data['bounds'] as List).length != 3 ||
        (data['bounds'] as List)
            .any((v) => v is! num || !v.isFinite || v <= 0)) {
      throw const FormatException(
          'Invalid console model dimensions or identity');
    }
    final receipts = (data['textureFiles'] as Map).cast<String, String>();
    final centers = data['poseCenters'];
    if (centers != null) {
      if (centers is! List ||
          centers.length < 2 ||
          centers.length > 1024 ||
          centers.any((row) =>
              row is! List ||
              row.length != 4 ||
              row.any((v) => v is! num || !v.isFinite)) ||
          centers.first[0] != 0 ||
          centers.last[0] != 1) {
        throw const FormatException('Invalid hardware pose centres');
      }
      for (var i = 1; i < centers.length; i++) {
        if ((centers[i][0] as num) <= (centers[i - 1][0] as num)) {
          throw const FormatException('Hardware pose centres must be ordered');
        }
      }
    }
    if (receipts.isEmpty || receipts.length > 64) {
      throw const FormatException('Invalid console texture inventory');
    }
    for (final entry in receipts.entries) {
      SocketMediaDirectoryBundle.checkName(entry.key);
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.value)) {
        throw const FormatException('Invalid console texture checksum');
      }
    }
    for (final surface in data['surfaces'] as List) {
      for (final name in (surface['material']['textures'] as Map).values) {
        if (!receipts.containsKey(name)) {
          throw const FormatException('Console texture lacks a checksum');
        }
      }
    }
    final file = File('${directory.path}/model.mesh');
    if (await file.length() > 20 * 1024 * 1024) {
      throw const FormatException('Console mesh exceeds import size');
    }
    return SocketMediaModel.privateHardware(
        data, ByteData.sublistView(await file.readAsBytes()),
        textureBundle: _ConsoleTextures(directory, receipts));
  }
}

class GameWatchModelVariant {
  final ConsoleModel model;
  final String? label;
  const GameWatchModelVariant(this.model, this.label);
}

class _ConsoleTextures extends SocketMediaDirectoryBundle {
  final Map<String, String> receipts;
  _ConsoleTextures(super.directory, this.receipts);
  @override
  Future<ByteData> load(String key) async {
    if (!key.startsWith(SocketMediaModel.assetRoot)) {
      throw const FormatException('Invalid console texture namespace');
    }
    final name = key.substring(SocketMediaModel.assetRoot.length);
    SocketMediaDirectoryBundle.checkName(name);
    if (!receipts.containsKey(name) ||
        await File('${directory.path}/$name').length() > 20 * 1024 * 1024) {
      throw const FormatException('Invalid console texture file');
    }
    final bytes = await super.load(key);
    if (sha256
            .convert(bytes.buffer
                .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes))
            .toString() !=
        receipts[name]) {
      throw const FormatException('Console texture checksum mismatch');
    }
    return bytes;
  }
}
