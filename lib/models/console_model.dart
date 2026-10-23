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
  final bool isCollectionOverview;
  final String? retailEditionId;
  final String? launchTarget;
  String get hardwareId =>
      romSet == null ? visualVariantId ?? '' : _physicalRomSet(romSet!);
  final bool canOpen;
  final bool isBox;
  final int openingDurationMs;
  final double? physicalUnitsPerMetre;
  ConsoleModel._(this.systemId, this.directory, this.generation,
      {this.romSet,
      this.visualVariantId,
      this.isCollectionOverview = false,
      this.retailEditionId,
      this.launchTarget,
      this.canOpen = false,
      this.isBox = false,
      this.openingDurationMs = 2000,
      this.physicalUnitsPerMetre});

  // ROM identity remains the exact MAME set. A documented MCU-only revision
  // may share its exterior; Crystal/Silver/Panorama designs remain separate.
  // MAME identifies Helmet as CN-07 and CN-17 as its bug-fixed MCU release.
  static String _physicalRomSet(String set) =>
      set == 'gnw_helmet' ? 'gnw_helmeto' : set;
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
    'gnw_ball',
    'gnw_bfight',
    'gnw_cgrab',
    'gnw_climber',
    'gnw_climbern',
    'gnw_dkcirc',
    'gnw_dkhockey',
    'gnw_dkjrp',
    'gnw_dkong3',
    'gnw_egg',
    'gnw_fireatk',
    'gnw_fires',
    'gnw_flagman',
    'gnw_helmet',
    'gnw_helmeto',
    'gnw_judge',
    'gnw_judgeo',
    'gnw_lion',
    'gnw_manhole',
    'gnw_manholeg',
    'gnw_mariocmt',
    'gnw_mariotj',
    'gnw_mbaway',
    'gnw_mmousep',
    'gnw_popeye',
    'gnw_popeyep',
    'gnw_stennis',
    'gnw_tbridge',
    'gnw_tfish',
    'gnw_vermin',
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
    // Shared program CRCs do not identify physical housings. Unqualified
    // Balloon Fight/Climber use their Crystal parent as explicit display policy;
    // the private visual catalogue retains available alternative editions.
    "Ball (World).7z": 'gnw_ball',
    "Balloon Fight (World).7z": 'gnw_bfight',
    "Climber (World).7z": 'gnw_climber',
    "Crab Grab (World).7z": 'gnw_cgrab',
    "Donkey Kong 3 (World).7z": 'gnw_dkong3',
    "Donkey Kong Hockey (World).7z": 'gnw_dkhockey',
    "Donkey Kong Jr. (World) (Panorama Screen).7z": 'gnw_dkjrp',
    "Fire (World) (Silver).7z": 'gnw_fires',
    "Fire Attack (World).7z": 'gnw_fireatk',
    "Flagman (World).7z": 'gnw_flagman',
    "Helmet (World).7z": 'gnw_helmeto',
    "Helmet (World) (Rev 1).7z": 'gnw_helmet',
    "Judge (World).7z": 'gnw_judgeo',
    "Judge (World) (Rev 1).7z": 'gnw_judge',
    "Lion (World).7z": 'gnw_lion',
    "Manhole (World) (Gold).7z": 'gnw_manholeg',
    "Manhole (World) (New Wide Screen).7z": 'gnw_manhole',
    "Mario the Juggler (World).7z": 'gnw_mariotj',
    "Mario's Bombs Away (World).7z": 'gnw_mbaway',
    "Mario's Cement Factory (World) (Table Top).7z": 'gnw_mariocmt',
    "Mickey Mouse ~ Donkey Kong Circus (World) (Panorama Screen).7z":
        'gnw_mmousep',
    "Popeye (World) (Panorama Screen).7z": 'gnw_popeyep',
    "Popeye (World) (Wide Screen).7z": 'gnw_popeye',
    "Snoopy Tennis (World).7z": 'gnw_stennis',
    "Tropical Fish (World).7z": 'gnw_tfish',
    "Turtle Bridge (World).7z": 'gnw_tbridge',
    "Vermin (World).7z": 'gnw_vermin',
  };

  static Future<ConsoleModel?> findGameWatch(String filename,
      {Directory? modelsDirectory, bool box = false}) async {
    final set = gameWatchSet(filename);
    if (set == null || modelsDirectory == null && !Platform.isAndroid) {
      return null;
    }
    final root =
        modelsDirectory ?? Directory('/storage/emulated/0/RShop/models');
    final dir = Directory(
        '${root.path}/${box ? 'boxes' : 'handhelds'}/gameandwatch/${_physicalRomSet(set)}');
    return _gameWatchImport(dir, romSet: set, box: box);
  }

  /// One exact primary shelf object, with a handheld only when its box is absent.
  /// Resources and lower edition previews keep their explicit resource choices.
  static Future<ConsoleModel?> findGameWatchLibrary(String filename,
          {Directory? modelsDirectory}) async =>
      await findGameWatch(filename,
          modelsDirectory: modelsDirectory, box: true) ??
      await findGameWatch(filename, modelsDirectory: modelsDirectory);

  /// Exact local packaging identity; no similarly named edition may borrow it.
  static Future<ConsoleModel?> findGameWatchBox(ConsoleModel handheld,
      {Directory? modelsDirectory}) async {
    if (handheld.systemId != 'gameandwatch' || handheld.isBox) return null;
    final root =
        modelsDirectory ?? Directory('/storage/emulated/0/RShop/models');
    final path = handheld.visualVariantId == null
        ? handheld.hardwareId
        : 'variants/${handheld.hardwareId}';
    return _gameWatchImport(Directory('${root.path}/boxes/gameandwatch/$path'),
        romSet: handheld.romSet,
        visualVariantId: handheld.visualVariantId,
        box: true);
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
    final physical = data['physicalScale'];
    final units = physical is Map ? physical['previewUnitsPerMetre'] : null;
    if (physical != null &&
        (units is! num ||
            !units.isFinite ||
            units <= 0 ||
            physical['reference'] is! String ||
            physical['estimated'] is! bool)) {
      throw const FormatException('Invalid hardware physical-unit calibration');
    }
    final duration = data['openingDurationMs'] ?? 2000;
    if (duration is! int || duration < 50 || duration > 10000) {
      throw const FormatException('Invalid handheld animation duration');
    }
    return ConsoleModel._('gameandwatch', dir, sha256.convert(bytes).toString(),
        romSet: romSet,
        visualVariantId: visualVariantId,
        isBox: box,
        canOpen: data['canOpen'] == true,
        openingDurationMs: duration,
        physicalUnitsPerMetre: (units as num?)?.toDouble());
  }

  /// Visual group membership is explicit private import data. It never changes
  /// exact-ROM lookup, library cards, launch identity or missing-model coverage.
  static Future<List<GameWatchModelVariant>> findGameWatchVariants(
      String filename,
      {Directory? modelsDirectory}) async {
    final variants = await _findGameWatchVariants(filename,
        modelsDirectory: modelsDirectory);
    return [
      for (final variant in variants)
        GameWatchModelVariant(variant.model, variant.label,
            box: await findGameWatchBox(variant.model,
                modelsDirectory: modelsDirectory))
    ];
  }

  static Future<List<GameWatchModelVariant>> _findGameWatchVariants(
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
    final bytes = await manifest.readAsBytes();
    return ConsoleModel._(systemId, dir, sha256.convert(bytes).toString(),
        isCollectionOverview: _isOverview(
            jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>));
  }

  static bool _isOverview(Map<String, dynamic> data) =>
      SocketMediaModel.isGameWatchCollection(data) ||
      data['system'] == 'nes' && data['overviewGeometry'] == true;

  static Future<ConsoleModel?> findNesConsoleVariant(String variant,
      {Directory? modelsDirectory}) async {
    if (!{'front-loader', 'top-loader', 'famicom', 'dendy'}.contains(variant)) {
      throw const FormatException('Unknown NES console body');
    }
    if (modelsDirectory == null && !Platform.isAndroid) return null;
    final root =
        modelsDirectory ?? Directory('/storage/emulated/0/RShop/models');
    final dir = Directory('${root.path}/consoles/nes/variants/$variant');
    final file = File('${dir.path}/model.json');
    if (!await file.exists()) return null;
    if (await file.length() > 1024 * 1024) {
      throw const FormatException('NES console manifest exceeds import size');
    }
    final bytes = await file.readAsBytes();
    return ConsoleModel._('nes', dir, sha256.convert(bytes).toString());
  }

  /// Launch bodies have source-bound slot/lid calibration. Collector scenes
  /// and uncalibrated reference bodies cannot enter the random launch pool.
  static Future<ConsoleModel?> findNesLaunchTarget(String target,
      {Directory? modelsDirectory}) async {
    if (!{'front-loader', 'top-loader'}.contains(target)) {
      throw const FormatException('Unknown calibrated NES launch target');
    }
    if (modelsDirectory == null && !Platform.isAndroid) return null;
    final root =
        modelsDirectory ?? Directory('/storage/emulated/0/RShop/models');
    final dir = Directory('${root.path}/consoles/nes/launch/$target');
    final file = File('${dir.path}/model.json');
    if (!await file.exists()) return null;
    if (await file.length() > 1024 * 1024) {
      throw const FormatException(
          'Launch hardware manifest exceeds import size');
    }
    final bytes = await file.readAsBytes();
    final data = jsonDecode(utf8.decode(bytes));
    if (data['launchHardware']?['target'] != 'nes-$target' ||
        data['overviewGeometry'] == true) {
      throw const FormatException('Launch hardware identity differs');
    }
    return ConsoleModel._('nes', dir, sha256.convert(bytes).toString(),
        launchTarget: target);
  }

  static Future<ConsoleModel?> findNesLaunchDisplay(
      {Directory? modelsDirectory}) async {
    if (modelsDirectory == null && !Platform.isAndroid) return null;
    final root =
        modelsDirectory ?? Directory('/storage/emulated/0/RShop/models');
    final dir = Directory('${root.path}/consoles/nes/launch/display');
    final file = File('${dir.path}/model.json');
    if (!await file.exists()) return null;
    if (await file.length() > 1024 * 1024) {
      throw const FormatException(
          'Launch display manifest exceeds import size');
    }
    final bytes = await file.readAsBytes();
    final data = jsonDecode(utf8.decode(bytes));
    if (data['launchDisplay']?['target'] != 'sony-kv1300e' ||
        data['overviewGeometry'] == true) {
      throw const FormatException('Launch display identity differs');
    }
    return ConsoleModel._('nes', dir, sha256.convert(bytes).toString());
  }

  static Future<ConsoleModel?> findNesBox(String editionId,
      {required String manifestSha256, Directory? modelsDirectory}) async {
    if (!RegExp(r'^nes-[a-f0-9]{12}$').hasMatch(editionId) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(manifestSha256)) {
      throw const FormatException('Invalid NES box reference');
    }
    if (modelsDirectory == null && !Platform.isAndroid) return null;
    final root =
        modelsDirectory ?? Directory('/storage/emulated/0/RShop/models');
    final dir = Directory('${root.path}/boxes/nes/$editionId');
    final file = File('${dir.path}/model.json');
    if (!await file.exists()) return null;
    if (await file.length() > 1024 * 1024) {
      throw const FormatException('NES box manifest exceeds import size');
    }
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != manifestSha256) {
      throw const FormatException('NES box differs from its catalogue receipt');
    }
    final data = jsonDecode(utf8.decode(bytes));
    final duration = data['openingDurationMs'];
    if (duration is! int || duration < 1 || duration > 60000) {
      throw const FormatException('Invalid NES box opening interval');
    }
    return ConsoleModel._('nes', dir, manifestSha256,
        isBox: true,
        canOpen: true,
        retailEditionId: editionId,
        openingDurationMs: duration);
  }

  /// A transparent decal shares the actual forward printed panel's positions.
  /// Its own upright UVs keep source scan/UV compensation and all hinges intact.
  static SocketMediaModel withGalleryBadges(SocketMediaModel source) {
    if (source.data['system'] != 'nes' ||
        source.data['resourceKind'] != 'box') {
      throw const FormatException('Gallery badges require a bound NES carton');
    }
    Map<String, dynamic>? front;
    List<List<double>> points = [];
    var left = 0.0,
        bottom = 0.0,
        width = 0.0,
        height = 0.0,
        area = 0.0,
        frontIndex = -1;
    for (var index = 0; index < source.surfaces.length; index++) {
      final surface = source.surfaces[index];
      if (surface['vertexCount'] != 6 ||
          surface['indexCount'] != 6 ||
          surface['material']['textures']['albedo'] == null ||
          (surface['material']['color'][3] as num) < .99) {
        continue;
      }
      final vertices = [
        for (var i = 0; i < 6; i++)
          [
            for (var axis = 0; axis < 8; axis++)
              source.mesh.getFloat32(
                  (surface['vertexOffset'] as int) + i * 32 + axis * 4,
                  Endian.little)
          ]
      ];
      if (vertices.any((p) => p[5] < .999)) {
        continue;
      }
      double low(int axis) =>
          vertices.map((p) => p[axis]).reduce((a, b) => a < b ? a : b);
      double high(int axis) =>
          vertices.map((p) => p[axis]).reduce((a, b) => a > b ? a : b);
      final w = high(0) - low(0), h = high(1) - low(1);
      if (w <= 0 || h <= 0 || high(2) - low(2) > .0001 || w * h <= area) {
        continue;
      }
      front = surface;
      points = vertices;
      left = low(0);
      bottom = low(1);
      width = w;
      height = h;
      area = w * h;
      frontIndex = index;
    }
    if (front == null) {
      throw const FormatException(
          'Forward printed carton panel is not established');
    }
    final vertexOffset = source.mesh.lengthInBytes,
        indexOffset = vertexOffset + points.length * 32;
    final mesh = ByteData(indexOffset + (front['indexCount'] as int) * 4);
    mesh.buffer.asUint8List().setRange(
        0,
        source.mesh.lengthInBytes,
        source.mesh.buffer
            .asUint8List(source.mesh.offsetInBytes, source.mesh.lengthInBytes));
    for (var i = 0; i < points.length; i++) {
      for (var axis = 0; axis < 8; axis++) {
        final value = axis == 6
            ? (points[i][0] - left) / width
            : axis == 7
                ? 1 - (points[i][1] - bottom) / height
                : points[i][axis];
        mesh.setFloat32(vertexOffset + i * 32 + axis * 4, value, Endian.little);
      }
    }
    for (var i = 0; i < front['indexCount']; i++) {
      mesh.setUint32(
          indexOffset + i * 4,
          source.mesh
              .getUint32((front['indexOffset'] as int) + i * 4, Endian.little),
          Endian.little);
    }
    final data = jsonDecode(jsonEncode(source.data)) as Map<String, dynamic>;
    data['labelAspect'] = width / height;
    data['galleryBadgeFrontSurfaceIndex'] = frontIndex;
    data['galleryBadgeSourceGeometrySha256'] = source.data['geometrySha256'];
    data['geometrySha256'] =
        sha256.convert(mesh.buffer.asUint8List()).toString();
    (data['surfaces'] as List).add({
      ...front,
      'name': 'Gallery front badges',
      'role': 'label',
      'galleryBadges': true,
      'vertexOffset': vertexOffset,
      'indexOffset': indexOffset,
      'material': {
        'color': [1.0, 1.0, 1.0, .999],
        'textures': <String, String>{},
        'sourceProperties': {'roughness': .9, 'metallic': 0.0}
      },
    });
    return SocketMediaModel.privateHardware(data, mesh,
        textureBundle: source.textureBundle!);
  }

  Future<SocketMediaModel> load({bool galleryBadges = false}) async {
    final manifest = await File('${directory.path}/model.json').readAsBytes();
    if (manifest.length > 1024 * 1024 ||
        sha256.convert(manifest).toString() != generation) {
      throw const FormatException('Console import changed during selection');
    }
    final data = jsonDecode(utf8.decode(manifest)) as Map<String, dynamic>;
    if (data['system'] != systemId ||
        retailEditionId != null &&
            (data['retailEditionId'] != retailEditionId ||
                data['resourceKind'] != 'box' ||
                data['canOpen'] != true) ||
        romSet != null && data['romSet'] != _physicalRomSet(romSet!) ||
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
    if (romSet != null && romSet != data['romSet']) {
      // Bind the selected program without rewriting or duplicating the source
      // exterior. Package artwork is shared, not a claimed revision-specific box.
      data['physicalModelRomSet'] = data['romSet'];
      data['romSet'] = romSet;
    }
    final collection = SocketMediaModel.isGameWatchCollection(data);
    if (data['selectorScene'] != null &&
        (!collection || romSet != null || visualVariantId != null)) {
      throw const FormatException('Invalid console collection identity');
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
    final nesOverview = systemId == 'nes' && data['overviewGeometry'] == true;
    if (receipts.length >
        (collection
            ? 272
            : nesOverview
                ? 128
                : 64)) {
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
    final model = SocketMediaModel.privateHardware(
        data, ByteData.sublistView(await file.readAsBytes()),
        textureBundle: _ConsoleTextures(directory, receipts));
    return galleryBadges ? withGalleryBadges(model) : model;
  }
}

class GameWatchModelVariant {
  final ConsoleModel model;
  final String? label;
  final ConsoleModel? box;
  const GameWatchModelVariant(this.model, this.label, {this.box});
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
