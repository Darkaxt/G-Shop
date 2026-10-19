import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'gba_cartridge_model.dart';
import 'packaging_model.dart';
import 'socket_media_model.dart';

/// A single depth-tested scene: the selected cartridge is physically seated in
/// the imported holder, rather than composited over a flat cover photograph.
class UnboxingScene {
  static const duration = Duration(seconds: 10);
  static Duration durationFor(bool hasBooklet) =>
      hasBooklet ? duration : const Duration(milliseconds: 6500);
  final String style;
  final bool hasBooklet;
  final double bookletAspect;
  final Directory? modelsDirectory;
  const UnboxingScene(this.style,
      {this.modelsDirectory,
      this.hasBooklet = false,
      this.bookletAspect = 1.35});

  Future<SocketMediaModel?> load() async {
    final carton = await PackagingModel(PackagingKind.box,
            systemId: 'gba',
            cartridgeStyle: GbaCartridgeModel.cartonVariant(style),
            aspect: 1,
            depth: GbaCartridgeModel.cartonDepth(style),
            modelsDirectory: modelsDirectory)
        .load();
    final slot = carton.data['cartridgeSlot'];
    if (slot is! Map || slot['fitPropExcluded'] != true) return null;
    final cartridge =
        await GbaCartridgeModel.load(style, modelsDirectory: modelsDirectory);
    if (cartridge == null) return null;
    final booklet = hasBooklet
        ? await PackagingModel(PackagingKind.booklet,
                aspect: bookletAspect,
                depth: .025,
                modelsDirectory: modelsDirectory)
            .load()
        : null;
    final parts = [
      (carton, 'box'),
      (cartridge, 'cartridge'),
      if (booklet != null) (booklet, 'booklet')
    ];
    final builder = BytesBuilder(copy: false);
    final surfaces = <Map<String, dynamic>>[];
    final bounds = <String, List<List<double>>>{};
    for (final entry in parts) {
      final (model, part) = entry;
      final offset = builder.length;
      final bytes = Uint8List.fromList(model.mesh.buffer
          .asUint8List(model.mesh.offsetInBytes, model.mesh.lengthInBytes));
      final data = ByteData.sublistView(bytes);
      final low = List.filled(3, double.infinity),
          high = List.filled(3, double.negativeInfinity);
      for (final original in model.surfaces) {
        final surface =
            jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
        for (var i = 0; i < surface['vertexCount']; i++) {
          final vertex = (surface['vertexOffset'] as int) + i * 32;
          for (var axis = 0; axis < 3; axis++) {
            final p = data.getFloat32(vertex + axis * 4, Endian.little);
            low[axis] = math.min(low[axis], p);
            high[axis] = math.max(high[axis], p);
          }
          if (surface['role'] == 'label') {
            final u = data.getFloat32(vertex + 24, Endian.little);
            final v = data.getFloat32(vertex + 28, Endian.little);
            final sourceCell = surface['atlasCell'] as int? ?? 0;
            final cell = part == 'booklet' ? 7 + sourceCell : 6;
            final localU = part == 'booklet' ? u * 3 - sourceCell % 3 : u;
            final localV = part == 'booklet' ? v * 2 - sourceCell ~/ 3 : v;
            data.setFloat32(vertex + 24,
                part == 'box' ? u : (cell % 3 + localU) / 3, Endian.little);
            data.setFloat32(
                vertex + 28,
                part == 'box' ? v / 2 : (cell ~/ 3 + localV) / 4,
                Endian.little);
          }
        }
        surface['vertexOffset'] = (surface['vertexOffset'] as int) + offset;
        surface['indexOffset'] = (surface['indexOffset'] as int) + offset;
        surface['unboxingPart'] = part;
        surfaces.add(surface);
      }
      bounds[part] = [low, high];
      builder.add(bytes);
    }
    final bytes = builder.takeBytes();
    final source = sha256
        .convert(utf8.encode(jsonEncode(
            parts.map((p) => p.$1.data['sourceReference']).toList())))
        .toString();
    final center = (slot['fitCenter'] as List).cast<num>();
    final fit = (slot['fitBounds'] as List).cast<List>();
    final special = GbaCartridgeModel.specialStyles.contains(style);
    final cartBounds = bounds['cartridge']!;
    final cartWidth = cartBounds[1][0] - cartBounds[0][0];
    final cartHeight = cartBounds[1][1] - cartBounds[0][1];
    final fitWidth = (fit[1][0] as num) - (fit[0][0] as num);
    final fitHeight = (fit[1][1] as num) - (fit[0][1] as num);
    final turned = special &&
        (fitWidth / cartHeight - fitHeight / cartWidth).abs() <
            (fitWidth / cartWidth - fitHeight / cartHeight).abs();
    return SocketMediaModel.privatePackaging({
      'name': 'gba-holder-tableau-v2',
      'packagingGeometry': true,
      'privateImport': true,
      'unboxingGeometry': true,
      'motionKind': 'packaging',
      'bounds': [2, 2, GbaCartridgeModel.cartonDepth(style)],
      'sourceWidth': 2,
      'labelAspect': .75,
      'frontSign': 1,
      'canOpen': true,
      'openingDurationMs': 3000,
      'maxOpenRadians': booklet?.data['maxOpenRadians'] ?? math.pi * .85,
      'cartridgeStyle': style,
      'seatCenter': [
        center[0],
        center[1],
        center[2] * GbaCartridgeModel.cartonDepth(style) / 2
      ],
      'seatScale': special
          ? (turned ? fitWidth / cartHeight : fitWidth / cartWidth)
          : fitWidth,
      'seatRotationZ': turned ? -math.pi / 2 : 0.0,
      'openingSide': carton.data['openingSide'],
      'partBounds': bounds,
      'hasBooklet': booklet != null,
      'bookletSeatScale': math.min(.62, .90 / bookletAspect),
      'geometrySha256': sha256.convert(bytes).toString(),
      'sourceReference': {
        'author': 'Owner-imported carton and cartridge',
        'url': 'local:holder-unboxing',
        'licence': 'local-import-only',
        'sha256': source,
        'sources': parts.map((p) => p.$1.data['sourceReference']).toList()
      },
      'surfaces': surfaces,
    }, ByteData.sublistView(bytes), textureBundle: cartridge.textureBundle);
  }

  static double phase(double t, double start, double end) {
    final p = ((t - start) / (end - start)).clamp(0.0, 1.0);
    return p * p * (3 - 2 * p);
  }

  static double opening(double t, {bool hasBooklet = false}) {
    final seconds = t * durationFor(hasBooklet).inMilliseconds / 1000;
    final delay = hasBooklet ? 3.5 : 0.0;
    return phase(seconds, 1.38, 3) *
        (1 - phase(seconds, 4.65 + delay, 5.65 + delay));
  }

  /// The closed front takes over in place, then the camera frames out before
  /// the first flap opens. This is presentation motion, not a readiness delay.
  static double framing(SocketMediaModel model, double t) => phase(
      t * durationFor(model.data['hasBooklet'] == true).inMilliseconds / 1000,
      .18,
      1.38);

  static double overviewElevation(SocketMediaModel model, double t) =>
      .55 *
      phase(
          t *
              durationFor(model.data['hasBooklet'] == true).inMilliseconds /
              1000,
          5.65,
          6.5);

  static vm.Matrix4 partTransform(
      SocketMediaModel model, String part, double t, double worldWidth,
      {String? inspectedPart, double inspection = 0}) {
    final seat = (model.data['seatCenter'] as List).cast<num>();
    final scale = (model.data['seatScale'] as num).toDouble();
    final book = part == 'booklet', box = part == 'box';
    final hasBooklet = model.data['hasBooklet'] == true;
    final seconds = t * durationFor(hasBooklet).inMilliseconds / 1000;
    // One object at a time through the opening. The booklet waits until the
    // cartridge rests on the left; the carton stays open for the second exit.
    final localSeconds = seconds - ((book || box && hasBooklet) ? 3.5 : 0);
    final extract = phase(localSeconds, 3, 4.2);
    final forward = phase(localSeconds, 4.2, 4.65);
    final spread = phase(localSeconds, 4.65, 5.65);
    final lower = phase(localSeconds, 5.65, 6.5);
    // Clear the right-hand opening first. Pass in front of the retained carton
    // before crossing to the display positions, then settle back alongside it.
    final separation = math.min(1.72, worldWidth * .32);
    var x = box
        ? 0.0
        : ((book ? 0.0 : seat[0].toDouble()) + extract * (book ? 1.76 : 1.12)) *
                (1 - spread) +
            (book ? separation : -separation) * spread;
    var y = box
        ? .1 * spread
        : (book ? 0.0 : seat[1].toDouble()) * (1 - spread) - .55 * spread;
    final seatedZ = book ? -.11 : seat[2].toDouble();
    var z = box
        ? -.28 * spread
        : (seatedZ + (.60 - seatedZ) * forward) * (1 - lower) + .65 * lower;
    var size = box
        ? 1 - .28 * spread
        : book
            ? (model.data['bookletSeatScale'] as num).toDouble() *
                    (1 - spread) +
                .5 * spread
            : scale + (1.45 - scale) * spread;
    var rz = (book
            ? -math.pi / 2 * (1 - spread)
            : ((model.data['seatRotationZ'] as num?)?.toDouble() ?? 0) *
                (1 - spread)) +
        (box
                ? 0.0
                : book
                    ? .22
                    : -.22) *
            lower;
    var rx = box ? 0.0 : -math.pi / 2 * lower;
    if (!box) {
      // Rotate the face onto the tabletop, then seat the physical underside on
      // the same plane as the standing carton. Different mesh thicknesses must
      // not make the manual float or the cartridge sink into that plane.
      final bounds = (model.data['partBounds'] as Map)[part] as List;
      final restingY = -.62 - (bounds[0][2] as num).toDouble() * size;
      y += (restingY - y) * lower;
    }
    if (book) {
      // Once the book clears the opening, one sweep carries, turns and lays it
      // down together. Do not stop to move forward, then spread, then lower.
      final sweep = phase(seconds, 7.7, 10);
      final arc = math.sin(math.pi * sweep);
      final seatedScale = (model.data['bookletSeatScale'] as num).toDouble();
      size = seatedScale + (.5 - seatedScale) * sweep;
      x = 1.76 * extract * (1 - sweep) + separation * sweep + .28 * arc;
      z = -.11 + (.65 + .11) * sweep;
      final bounds = (model.data['partBounds'] as Map)['booklet'] as List;
      final restingY = -.62 - (bounds[0][2] as num).toDouble() * size;
      y = restingY * sweep + .12 * arc;
      rx = -math.pi / 2 * sweep;
      rz = -math.pi / 2 * (1 - sweep) + .22 * sweep;
    }
    if (inspectedPart != null && inspection > 0) {
      final selected = inspectedPart == part;
      final targetX = selected ? 0.0 : (x < 0 ? -1 : 1) * (worldWidth / 2 + 4);
      final targetSize = selected
          ? (box
              ? 1.35
              : book
                  ? 1.15
                  : 3.0)
          : size;
      x += (targetX - x) * inspection;
      y *= 1 - inspection;
      z *= 1 - inspection;
      size += (targetSize - size) * inspection;
      rx *= 1 - inspection;
      rz *= 1 - inspection;
    }
    return vm.Matrix4.identity()
      ..translateByDouble(x, y, z, 1)
      ..rotateX(rx)
      ..rotateZ(rz)
      ..scaleByDouble(size, size, size, 1);
  }
}
