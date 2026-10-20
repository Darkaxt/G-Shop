import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'console_model.dart';
import 'socket_media_model.dart';

/// One exact imported handheld and its box, sharing a depth buffer. Source
/// vertices, UVs, hinges and texture receipts remain unchanged by composition.
class GameWatchUnboxingScene {
  final ConsoleModel handheld, box;
  const GameWatchUnboxingScene(this.handheld, this.box);
  String get identity => '${handheld.generation}:${box.generation}';
  int get durationMs =>
      box.openingDurationMs +
      (handheld.canOpen ? handheld.openingDurationMs : 0) +
      3700;

  double handheldOpening(double progress) {
    if (!handheld.canOpen) return 0;
    final seconds = progress * durationMs / 1000;
    final start = box.openingDurationMs / 1000 + 1.9;
    return phase(seconds, start, start + handheld.openingDurationMs / 1000);
  }

  static double phase(double t, double start, double end) {
    final p = ((t - start) / (end - start)).clamp(0.0, 1.0);
    return p * p * (3 - 2 * p);
  }

  Future<SocketMediaModel> load() async {
    if (!box.isBox || handheld.isBox || handheld.hardwareId != box.hardwareId) {
      throw const FormatException('Unboxing requires the exact hardware box');
    }
    final console = await handheld.load(), carton = await box.load();
    final restPitch =
        ((console.data['restingPitchRadians'] as num?) ?? -math.pi / 2)
            .toDouble();
    if (!restPitch.isFinite || restPitch.abs() > math.pi) {
      throw const FormatException('Invalid handheld resting orientation');
    }
    final insertNodes =
        ((carton.data['removableInsertNodes'] as List?) ?? const <String>[])
            .cast<String>()
            .toSet();
    final bytes = BytesBuilder(copy: false);
    final surfaces = <Map<String, dynamic>>[];
    final bundles = <String, AssetBundle>{};
    for (final (part, model) in [('console', console), ('box', carton)]) {
      final offset = bytes.length;
      bytes.add(model.mesh.buffer
          .asUint8List(model.mesh.offsetInBytes, model.mesh.lengthInBytes));
      for (final original in model.surfaces) {
        final surface =
            jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
        surface['vertexOffset'] = (surface['vertexOffset'] as int) + offset;
        surface['indexOffset'] = (surface['indexOffset'] as int) + offset;
        surface['hardwarePart'] =
            part == 'box' && insertNodes.contains(surface['node'])
                ? 'insert'
                : part;
        final maps = surface['material']['textures'] as Map;
        for (final role in maps.keys.toList()) {
          final name = maps[role] as String;
          final key = '$part/$name';
          maps[role] = key;
          bundles[key] = model.textureBundle!;
        }
        surfaces.add(surface);
      }
    }
    final consoleClosed = bounds(console, 0);
    final boxClosed = bounds(carton, 0);
    final boxCenter = SocketMediaModel.poseCenter(carton.data, 0);
    final seating = carton.data['seatingBounds'] as List?;
    final cavity = seating == null
        ? boxClosed
        : [
            for (final row in seating.cast<List>())
              [
                for (var a = 0; a < 3; a++)
                  (row[a] as num).toDouble() - boxCenter[a]
              ]
          ];
    if (cavity.length != 2 ||
        cavity.any((r) => r.length != 3) ||
        [0, 1, 2].any((a) =>
            !cavity[0][a].isFinite ||
            !cavity[1][a].isFinite ||
            cavity[0][a] >= cavity[1][a])) {
      throw const FormatException('Invalid reviewed carton seating cavity');
    }
    final seatOffset = [
      for (var a = 0; a < 3; a++) (cavity[0][a] + cavity[1][a]) / 2
    ];
    final insertBounds =
        insertNodes.isEmpty ? null : bounds(carton, 0, nodes: insertNodes);
    final exitAxis = extractionAxis(carton, boxClosed);
    final boxExit = bounds(carton, 1);
    final centreDelta = SocketMediaModel.poseCenter(carton.data, 1) -
        SocketMediaModel.poseCenter(carton.data, 0);
    final exitOffset = List.filled(3, 0.0);
    // Both imports have independent uniform normalization. Fit the folded
    // handheld inside the real closed carton, preserving every aspect ratio.
    var seatScale = double.infinity;
    for (var axis = 0; axis < 3; axis++) {
      seatScale = math.min(
          seatScale,
          (cavity[1][axis] - cavity[0][axis]) *
              .88 /
              (consoleClosed[1][axis] - consoleClosed[0][axis]));
    }
    for (var axis = 0; axis < 3; axis++) {
      if (exitAxis[axis] == 0) continue;
      final positive = exitAxis[axis] > 0;
      var contentsEdge =
          consoleClosed[positive ? 0 : 1][axis] * seatScale + seatOffset[axis];
      if (insertBounds != null) {
        contentsEdge = positive
            ? math.min(contentsEdge, insertBounds[0][axis])
            : math.max(contentsEdge, insertBounds[1][axis]);
      }
      exitOffset[axis] = boxExit[positive ? 1 : 0][axis] +
          centreDelta[axis] -
          contentsEdge +
          (positive ? .1 : -.1);
    }
    final geometry = bytes.takeBytes();
    final sources = [
      console.data['sourceReference'],
      carton.data['sourceReference']
    ];
    return SocketMediaModel.privateHardware({
      'name': 'gamewatch-exact-unboxing-v1',
      'hardwareGeometry': true,
      'gameWatchUnboxing': true,
      'privateImport': true,
      'motionKind': 'hardware',
      'sourceWidth': 4.8,
      'labelAspect': 1,
      'frontSign': 1,
      'bounds': [4.8, 3.0, 2.0],
      'canOpen': handheld.canOpen,
      'openingDurationMs': handheld.openingDurationMs,
      'boxOpeningMs': box.openingDurationMs,
      'consoleOpeningMs': handheld.canOpen ? handheld.openingDurationMs : 0,
      'sequenceDurationMs': durationMs,
      'seatScale': seatScale,
      'seatOffset': seatOffset,
      'seatingBounds': cavity,
      'extractionAxis': exitAxis,
      'exitOffset': exitOffset,
      'motionFrameWidth': math.max(
          4.8,
          2 *
              (exitOffset[0].abs() +
                  console.sourceWidth * seatScale / 2 +
                  .25)),
      'motionFrameHeight': math.max(2.0,
          2 * (exitOffset[1].abs() + console.height * seatScale / 2 + .25)),
      'boxClosedBounds': boxClosed,
      'consoleClosedBounds': consoleClosed,
      'consoleData': {'poseCenters': console.data['poseCenters']},
      'boxData': {'poseCenters': carton.data['poseCenters']},
      'consoleRestLows': [
        for (var i = 0; i <= 60; i++)
          bounds(console, i / 60, pitch: restPitch)[0][1]
      ],
      'consoleRestPitch': restPitch,
      'consoleRestScale': seatScale * .84,
      'consoleSourceWidth': console.sourceWidth,
      'consoleHeight': console.height,
      'consoleGeometrySha256': console.data['geometrySha256'],
      'boxGeometrySha256': carton.data['geometrySha256'],
      'geometrySha256': sha256.convert(geometry).toString(),
      'sourceReference': {
        'author': 'Owner-imported exact Game & Watch handheld and box',
        'url': 'local:gamewatch-unboxing/${handheld.hardwareId}',
        'licence': 'local-import-only',
        'sha256': sha256.convert(utf8.encode(jsonEncode(sources))).toString(),
        'sources': sources,
      },
      'surfaces': surfaces,
    }, ByteData.sublistView(geometry), textureBundle: _PairTextures(bundles));
  }

  /// New reconstructions declare their reviewed opening. The original imports
  /// have all root flap pivots on one end: derive that actual end, rather than
  /// moving a handheld through the opposite, still-closed carton wall.
  static List<double> extractionAxis(
      SocketMediaModel carton, List<List<double>> closed) {
    final declared = carton.data['extractionAxis'];
    if (declared is List &&
        declared.length == 3 &&
        declared.every((v) => v is num && (v == 0 || v == 1 || v == -1)) &&
        declared.where((v) => v != 0).length == 1) {
      return declared.cast<num>().map((v) => v.toDouble()).toList();
    }
    final pivots = <double>[];
    for (final surface in carton.surfaces) {
      final hinges = surface['openingHinges'];
      if (hinges is List && hinges.isNotEmpty) {
        pivots.add((hinges.first['pivot'][0] as num).toDouble());
      }
    }
    final middle = (closed[0][0] + closed[1][0]) / 2;
    if (pivots.isEmpty ||
        !(pivots.every((x) => x < middle) || pivots.every((x) => x > middle))) {
      throw const FormatException('Carton needs its reviewed extraction axis');
    }
    return [pivots.first < middle ? -1 : 1, 0, 0];
  }

  /// Exact animated vertex bounds, also used to seat the resting underside.
  static List<List<double>> bounds(SocketMediaModel model, double opening,
      {double pitch = 0, Set<String>? nodes}) {
    final low = List.filled(3, double.infinity);
    final high = List.filled(3, double.negativeInfinity);
    final center = SocketMediaModel.poseCenter(model.data, opening);
    final basis = vm.Matrix4.identity()
      ..rotateX(pitch)
      ..translateByDouble(-center.x, -center.y, -center.z, 1);
    for (final surface in model.surfaces) {
      if (nodes != null && !nodes.contains(surface['node'])) continue;
      final transform =
          basis * SocketMediaModel.openingTransform(surface, opening);
      for (var i = 0; i < surface['vertexCount']; i++) {
        final offset = (surface['vertexOffset'] as int) + i * 32;
        final point = transform.transform3(vm.Vector3(
            model.mesh.getFloat32(offset, Endian.little),
            model.mesh.getFloat32(offset + 4, Endian.little),
            model.mesh.getFloat32(offset + 8, Endian.little)));
        for (var axis = 0; axis < 3; axis++) {
          low[axis] = math.min(low[axis], point[axis]);
          high[axis] = math.max(high[axis], point[axis]);
        }
      }
    }
    return [low, high];
  }

  static double seconds(SocketMediaModel model, double t) =>
      t * (model.data['sequenceDurationMs'] as num) / 1000;
  static double boxOpening(SocketMediaModel model, double t) {
    final s = seconds(model, t);
    final openEnd = (model.data['boxOpeningMs'] as num) / 1000;
    return phase(s, 0, openEnd) * (1 - phase(s, openEnd + 2.7, openEnd + 3.4));
  }

  static double consoleOpening(SocketMediaModel model, double t) {
    final openEnd = (model.data['boxOpeningMs'] as num) / 1000;
    final duration = (model.data['consoleOpeningMs'] as num) / 1000;
    return duration == 0
        ? 0
        : phase(seconds(model, t), openEnd + 1.9, openEnd + 1.9 + duration);
  }

  static vm.Matrix4 partTransform(
      SocketMediaModel model, String part, SocketMediaPose pose) {
    final insert = part == 'insert';
    final box = part != 'console';
    final data = model.data;
    final opening = box ? boxOpening(model, pose.unboxing) : pose.opening;
    final center = SocketMediaModel.poseCenter(
        Map<String, dynamic>.from(data[box ? 'boxData' : 'consoleData'] as Map),
        box ? 0 : opening);
    if (pose.inspectedPart == 'console') {
      return vm.Matrix4.identity()
        ..translateByDouble(-center.x, -center.y, -center.z, 1);
    }
    final s = seconds(model, pose.unboxing);
    final opened = (data['boxOpeningMs'] as num) / 1000;
    final extract = phase(s, opened, opened + 1.2);
    final forward = phase(s, opened + 1.2, opened + 1.9);
    final unfoldEnd = opened + 1.9 + (data['consoleOpeningMs'] as num) / 1000;
    final settle = phase(s, unfoldEnd, unfoldEnd + 1.8);
    final closedBox = (data['boxClosedBounds'] as List).cast<List>();
    final seat = (data['seatScale'] as num).toDouble();
    final rest = (data['consoleRestScale'] as num).toDouble();
    final size = box ? 1 - .16 * settle : seat + (rest - seat) * settle;
    // First clear the actual opened end, then move in front, only then
    // unfold and return to centre. The carton never moves through its contents.
    final exit = (data['exitOffset'] as List).cast<num>();
    final seated = (data['seatOffset'] as List).cast<num>();
    final tray =
        insert ? extract * (1 - phase(s, opened + 1.9, opened + 2.6)) : 0.0;
    final x = box
        ? exit[0] * tray
        : exit[0] * extract * (1 - settle) + seated[0] * (1 - forward);
    final support = (data['consoleRestLows'] as List).cast<num>();
    final supportPosition = opening.clamp(0.0, 1.0) * (support.length - 1);
    final supportIndex = supportPosition.floor();
    final restLow = support[supportIndex] +
        (support[math.min(supportIndex + 1, support.length - 1)] -
                support[supportIndex]) *
            (supportPosition - supportIndex);
    final y = box
        ? exit[1] * tray + (-.65 - (closedBox[0][1] as num) * .84) * settle
        : exit[1] * extract * (1 - settle) +
            seated[1] * (1 - forward) +
            (-.65 - restLow * rest) * settle;
    final z = box
        ? exit[2] * tray - .6 * settle
        : exit[2] * extract * (1 - settle) +
            seated[2] * (1 - forward) +
            .95 * forward -
            .4 * settle;
    return vm.Matrix4.identity()
      ..translateByDouble(x, y, z, 1)
      ..rotateX(box ? 0 : (data['consoleRestPitch'] as num).toDouble() * settle)
      ..scaleByDouble(size, size, size, 1)
      ..translateByDouble(-center.x, -center.y, -center.z, 1);
  }
}

class _PairTextures extends CachingAssetBundle {
  final Map<String, AssetBundle> sources;
  _PairTextures(this.sources);
  @override
  Future<ByteData> load(String key) {
    final name = key.startsWith(SocketMediaModel.assetRoot)
        ? key.substring(SocketMediaModel.assetRoot.length)
        : '';
    final source = sources[name];
    if (source == null) throw const FormatException('Unknown paired texture');
    return source.load(
        '${SocketMediaModel.assetRoot}${name.substring(name.indexOf('/') + 1)}');
  }
}
