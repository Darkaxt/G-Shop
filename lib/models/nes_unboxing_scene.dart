import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'console_model.dart';
import 'game_watch_unboxing_scene.dart';
import 'nes_cartridge_model.dart';
import 'socket_media_model.dart';

/// One selected reference printing, shell and optional sleeve in a shared
/// depth buffer. ROM identity never becomes a claim about an owned retail SKU.
class NesUnboxingScene {
  final ConsoleModel box;
  final String style;
  final Directory? modelsDirectory;
  const NesUnboxingScene(this.box, this.style, {this.modelsDirectory});
  String get identity => '${box.generation}:$style';
  bool get hasSleeve => usesSleeve(style);
  static bool usesSleeve(String style) =>
      RegExp(r'^nintendo-[35]-(?:gray|gold|white)$').hasMatch(style);
  int get durationMs =>
      box.openingDurationMs +
      (hasSleeve ? 5300 : 4100) +
      (box.hasFoamSpacer ? 1900 : 0);

  Future<SocketMediaModel> load() async {
    if (!box.isBox || box.systemId != 'nes') {
      throw const FormatException(
          'NES unboxing requires a selected NES carton');
    }
    final carton = await box.load();
    final cartridge =
        await NesCartridgeModel.load(style, modelsDirectory: modelsDirectory);
    final sleeve = hasSleeve
        ? await NesCartridgeModel.load('dust-sleeve',
            modelsDirectory: modelsDirectory)
        : null;
    if (cartridge == null || hasSleeve && sleeve == null) {
      throw const FormatException('Selected NES unboxing contents are absent');
    }
    final cb = GameWatchUnboxingScene.bounds(cartridge, 0);
    final bb = GameWatchUnboxingScene.bounds(carton, 0);
    final bc = SocketMediaModel.poseCenter(carton.data, 0);
    final profile = carton.data['nesStandardCarton'] as Map?;
    final foamBounds = profile == null
        ? null
        : GameWatchUnboxingScene.bounds(carton, 0,
            nodes: {profile['foamNode'] as String});
    // Portrait and landscape reconstructions have different opening ends.
    // Inspect their root flap pivots instead of crossing a closed wall.
    final pivots = [
      for (final s in carton.surfaces)
        if ((s['openingHinges'] as List).isNotEmpty)
          ((s['openingHinges'] as List).first['pivot'] as List).cast<num>()
    ];
    final ends = <List<int>>[];
    for (final axis in [0, 1]) {
      for (final sign in [-1, 1]) {
        final edge = bb[sign > 0 ? 1 : 0][axis] + bc[axis];
        if (pivots.isNotEmpty &&
            pivots.every((p) => (p[axis] - edge).abs() < .08)) {
          ends.add([axis, sign]);
        }
      }
    }
    if (ends.length != 1) {
      throw const FormatException('NES carton needs a reviewed opening end');
    }
    List<double> extent(List<List<double>> b) =>
        [for (var a = 0; a < 3; a++) b[1][a] - b[0][a]];
    final cartSize = extent(cb);
    final sleeveBounds =
        sleeve == null ? null : GameWatchUnboxingScene.bounds(sleeve, 0);
    final sleeveScale = [1.0, 1.0, 1.0];
    if (sleeveBounds != null) {
      final size = extent(sleeveBounds);
      sleeveScale[0] = sleeveScale[1] = cartSize[0] * 1.04 / size[0];
      // The flexible donor sleeve was made for a thinner donor shell. Preserve
      // its front proportions and fit its depth to the selected actual shell.
      sleeveScale[2] = cartSize[2] * 1.12 / size[2];
    }
    final packSize = [
      for (var a = 0; a < 3; a++)
        math.max(
            cartSize[a],
            sleeveBounds == null
                ? 0.0
                : (sleeveBounds[1][a] - sleeveBounds[0][a]) * sleeveScale[a])
    ];
    var seat = double.infinity;
    for (var a = 0; a < 3; a++) {
      seat = math.min(seat, (bb[1][a] - bb[0][a]) * .86 / packSize[a]);
    }
    var seatY = 0.0, physicalUnits = 0.0;
    if (profile != null) {
      physicalUnits = (profile['previewUnitsPerMetre'] as num).toDouble();
      final ledger =
          (cartridge.data['sourceReference'] as Map?)?['modelLedger'] as Map?;
      final dimensions = ledger?['nominal_dimensions_mm'] as List?;
      if (!physicalUnits.isFinite ||
          physicalUnits <= 0 ||
          ledger?['units'] != 'metres' ||
          dimensions == null ||
          dimensions.length != 3 ||
          !dimensions.every((v) => v is num && v.isFinite && v > 0) ||
          foamBounds!.expand((v) => v).any((v) => !v.isFinite)) {
        throw const FormatException(
            'Standard NES carton needs measured or declared physical contents');
      }
      seat = (dimensions[0] as num) / 1000 * physicalUnits / cartSize[0];
      final packLow = [
        for (var a = 0; a < 3; a++)
          math.min(
              cb[0][a],
              sleeveBounds == null
                  ? cb[0][a]
                  : sleeveBounds[0][a] * sleeveScale[a])
      ];
      seatY = foamBounds[1][1] + .0006 * physicalUnits - packLow[1] * seat;
      final interior = (profile['interiorBounds'] as List).cast<List>();
      for (var a = 0; a < 3; a++) {
        final offset = a == 1 ? seatY : 0.0;
        final min = (interior[0][a] as num) - bc[a],
            max = (interior[1][a] as num) - bc[a];
        if (packLow[a] * seat + offset < min ||
            packLow[a] * seat + packSize[a] * seat + offset > max) {
          throw const FormatException(
              'Physical NES contents do not fit the supplied carton');
        }
      }
    }
    final openedBounds = (carton.data['bounds'] as List).cast<num>();
    final envelope = [
      for (final sign in [-1, 1])
        [for (var a = 0; a < 3; a++) sign * openedBounds[a] / 2 - bc[a]]
    ];
    final axis = ends.single[0], sign = ends.single[1];
    final exit = List.filled(3, 0.0);
    exit[axis] = envelope[sign > 0 ? 1 : 0][axis] +
        sign * (packSize[axis] * seat / 2 + .08);
    final lift = sleeveBounds == null
        ? 0.0
        : (sleeveBounds[1][1] * sleeveScale[1] - cb[0][1]) * seat + .08;
    final payload = BytesBuilder(copy: false),
        surfaces = <Map<String, dynamic>>[];
    final bundles = <String, AssetBundle>{};
    final parts = [
      ('box', carton),
      ('cartridge', cartridge),
      if (sleeve != null) ('sleeve', sleeve)
    ];
    for (final (part, model) in parts) {
      final offset = payload.length;
      payload.add(model.mesh.buffer
          .asUint8List(model.mesh.offsetInBytes, model.mesh.lengthInBytes));
      for (final original in model.surfaces) {
        final s = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
        s['vertexOffset'] = (s['vertexOffset'] as int) + offset;
        s['indexOffset'] = (s['indexOffset'] as int) + offset;
        s['nesPart'] =
            part == 'box' && profile != null && s['node'] == profile['foamNode']
                ? 'foam'
                : part;
        // A plain sleeve avoids inferring Nintendo-printed packaging for every
        // licensed third-party game. The original branded reference is retained.
        if (part == 'sleeve') {
          (s['material']['textures'] as Map).remove('albedo');
          s['material']['color'] = [.035, .035, .035, 1.0];
        }
        final maps = s['material']['textures'] as Map;
        for (final role in maps.keys.toList()) {
          final name = maps[role] as String, key = '$part/$name';
          maps[role] = key;
          bundles[key] = model.textureBundle!;
        }
        surfaces.add(s);
      }
    }
    final bytes = payload.takeBytes();
    final sources = [for (final (_, m) in parts) m.data['sourceReference']];
    return SocketMediaModel.privateHardware({
      'name': 'nes-reference-unboxing-v1',
      'system': 'nes',
      'privateImport': true,
      'hardwareGeometry': true,
      'nesUnboxing': true,
      'motionKind': 'hardware',
      'sourceWidth': 4.0,
      'bounds': [4.0, 4.0, 3.0],
      'labelAspect': cartridge.labelAspect,
      'cartridgeFrameWidth': cartridge.sourceWidth,
      'cartridgeFrameHeight': cartridge.height,
      'cartridgeClosedSize': cartSize,
      'frontSign': 1,
      'cartridgeStyle': style,
      'retailEditionId': box.retailEditionId,
      'hasSleeve': hasSleeve,
      'hasFoam': foamBounds != null,
      'physicalUnitsPerMetre': physicalUnits,
      'seatYOffset': seatY,
      if (foamBounds != null)
        'foamExitY': envelope[1][1] - foamBounds[0][1] + .08,
      if (foamBounds != null) 'foamRestY': bb[0][1] - .25 - foamBounds[0][1],
      'sleevePrint': 'plain reference',
      'boxOpeningMs': box.openingDurationMs,
      'sequenceDurationMs': durationMs,
      'seatScale': seat,
      'exitOffset': exit,
      'exitAxis': [axis, sign],
      'sleeveLift': lift,
      'sleeveScale': sleeveScale,
      'boxCenter': [bc.x, bc.y, bc.z],
      'cartridgeData': {'poseCenters': cartridge.data['poseCenters']},
      'partBounds': {
        'box': [
          for (final sign in [-1, 1])
            [for (final v in openedBounds) sign * v / 2]
        ],
        'cartridge': [
          for (final sign in [-1, 1])
            [
              for (final v in (cartridge.data['bounds'] as List).cast<num>())
                sign * v / 2
            ]
        ],
        if (sleeveBounds != null) 'sleeve': sleeveBounds,
        if (foamBounds != null)
          'foam': [
            for (final b in foamBounds)
              [for (var a = 0; a < 3; a++) b[a] + bc[a]]
          ]
      },
      'cartridgeGeometrySha256': cartridge.data['geometrySha256'],
      'boxGeometrySha256': carton.data['geometrySha256'],
      'geometrySha256': sha256.convert(bytes).toString(),
      'sourceReference': {
        'author': 'Owner-imported NES carton, cartridge and sleeve',
        'url': 'local:nes-unboxing/$identity',
        'licence': 'local-import-only',
        'sha256': sha256.convert(utf8.encode(jsonEncode(sources))).toString(),
        'sources': sources
      },
      'surfaces': surfaces,
    }, ByteData.sublistView(bytes), textureBundle: _NesSceneTextures(bundles));
  }

  static double phase(double t, double start, double end) =>
      GameWatchUnboxingScene.phase(t, start, end);
  static double seconds(SocketMediaModel m, double t) =>
      t * (m.data['sequenceDurationMs'] as num) / 1000;
  static double boxOpening(SocketMediaModel m, double t) =>
      phase(seconds(m, t), 0, (m.data['boxOpeningMs'] as num) / 1000);

  static vm.Matrix4 partTransform(
      SocketMediaModel m, String part, SocketMediaPose p) {
    final d = m.data, s = seconds(m, p.unboxing);
    final opened = (d['boxOpeningMs'] as num) / 1000;
    final extract = phase(s, opened, opened + 1.2);
    final forward = phase(s, opened + 1.2, opened + 1.9);
    final sleeved = d['hasSleeve'] == true;
    final unsleeve = sleeved ? phase(s, opened + 1.9, opened + 3.1) : 0.0;
    final cartCleared = opened + (sleeved ? 3.1 : 1.9);
    final hasFoam = d['hasFoam'] == true;
    final cleared = cartCleared + (hasFoam ? 1.9 : 0.0);
    final separate = phase(s, cleared, cleared + .6);
    final settle = phase(s, cleared + .6, cleared + 2.2);
    final seat = (d['seatScale'] as num).toDouble();
    final matrix = vm.Matrix4.identity();
    if (part == 'box') {
      final c = (d['boxCenter'] as List).cast<num>();
      return matrix
        ..translateByDouble(-.75 * separate, -.25 * settle, -.45 * separate, 1)
        ..translateByDouble(
            -c[0].toDouble(), -c[1].toDouble(), -c[2].toDouble(), 1);
    }
    if (part == 'foam') {
      final c = (d['boxCenter'] as List).cast<num>();
      final lift = phase(s, cartCleared, cartCleared + 1.2);
      final forward = phase(s, cartCleared + 1.2, cartCleared + 1.9);
      return matrix
        ..translateByDouble(
            1.7 * separate,
            (d['foamExitY'] as num) * lift * (1 - settle) +
                (d['foamRestY'] as num) * settle,
            .90 * forward,
            1)
        ..translateByDouble(
            -c[0].toDouble(), -c[1].toDouble(), -c[2].toDouble(), 1);
    }
    final cart = part == 'cartridge';
    final center = cart
        ? SocketMediaModel.poseCenter(
            Map<String, dynamic>.from(d['cartridgeData'] as Map), p.opening)
        : vm.Vector3.zero();
    if (p.inspectedPart == 'cartridge') {
      return matrix..translateByDouble(-center.x, -center.y, -center.z, 1);
    }
    final exit = (d['exitOffset'] as List).cast<num>();
    final y = ((d['seatYOffset'] as num?) ?? 0) +
        exit[1] * extract +
        (cart ? (d['sleeveLift'] as num) * unsleeve : 0);
    final targetY = cart ? -.3 : -.35;
    matrix
      ..translateByDouble(
          exit[0] * extract * (1 - separate) + (cart ? .55 : 1.35) * separate,
          y * (1 - settle) + targetY * settle,
          .60 * forward + (cart ? .25 : -.25) * separate,
          1)
      ..scaleByDouble(seat, seat, seat, 1);
    if (!cart) {
      final scale = (d['sleeveScale'] as List).cast<num>();
      matrix.scaleByDouble(
          scale[0].toDouble(), scale[1].toDouble(), scale[2].toDouble(), 1);
    }
    return matrix..translateByDouble(-center.x, -center.y, -center.z, 1);
  }

  static vm.Matrix4 _basis(SocketMediaPose p) => vm.Matrix4.identity()
    ..translateByDouble(0, p.y, p.z, 1)
    ..rotateY(p.ry)
    ..rotateX(p.rx)
    ..rotateZ(p.rz)
    ..scaleByDouble(p.scaleX, p.scaleY, p.scaleZ, 1);
  static List<vm.Vector3> _corners(SocketMediaModel m, SocketMediaPose p) {
    final points = <vm.Vector3>[], base = _basis(p);
    for (final entry in (m.data['partBounds'] as Map).entries) {
      if (p.inspectedPart != null && entry.key != p.inspectedPart) continue;
      final b = (entry.value as List).cast<List>();
      final transform = base * partTransform(m, entry.key as String, p);
      for (final x in [0, 1]) {
        for (final y in [0, 1]) {
          for (final z in [0, 1]) {
            points.add(transform.transformed3(vm.Vector3(
                (b[x][0] as num).toDouble(),
                (b[y][1] as num).toDouble(),
                (b[z][2] as num).toDouble())));
          }
        }
      }
    }
    return points;
  }

  static vm.Vector3 viewCenter(SocketMediaModel m, SocketMediaPose p) {
    final points = _corners(m, p);
    return vm.Vector3(
        (points.map((v) => v.x).reduce(math.min) +
                points.map((v) => v.x).reduce(math.max)) /
            2,
        (points.map((v) => v.y).reduce(math.min) +
                points.map((v) => v.y).reduce(math.max)) /
            2,
        0);
  }

  static vm.Matrix4 viewTransform(SocketMediaModel m, SocketMediaPose p) {
    if (p.inspectedPart == 'cartridge') return _basis(p);
    final c = viewCenter(m, p);
    return vm.Matrix4.translationValues(-c.x, -c.y, 0) * _basis(p);
  }

  static double fittedUnits(
      SocketMediaModel m, SocketMediaPose p, double width, double height) {
    if (p.inspectedPart == 'cartridge') {
      return math.min(width * .72 / (m.data['cartridgeFrameWidth'] as num),
          height * .68 / (m.data['cartridgeFrameHeight'] as num));
    }
    final center = viewCenter(m, p);
    var x = .01, y = .01;
    for (final point in _corners(m, p)) {
      final w = math.max(.1, 1 - .25 * point.z);
      x = math.max(x, (point.x - center.x).abs() / w);
      y = math.max(y, (point.y - center.y).abs() / w);
    }
    return math.min(width * .43 / x, height * .43 / y);
  }
}

class _NesSceneTextures extends CachingAssetBundle {
  final Map<String, AssetBundle> sources;
  _NesSceneTextures(this.sources);
  @override
  Future<ByteData> load(String key) {
    final name = key.startsWith(SocketMediaModel.assetRoot)
        ? key.substring(SocketMediaModel.assetRoot.length)
        : '';
    final source = sources[name];
    if (source == null) {
      throw const FormatException('Unknown NES scene texture');
    }
    return source.load(
        '${SocketMediaModel.assetRoot}${name.substring(name.indexOf('/') + 1)}');
  }
}
