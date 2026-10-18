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
  static const duration = Duration(milliseconds: 6500);
  final String style;
  final Directory? modelsDirectory;
  const UnboxingScene(this.style, {this.modelsDirectory});

  Future<SocketMediaModel?> load() async {
    final carton = await PackagingModel(PackagingKind.box,
            systemId: 'gba',
            aspect: 1,
            depth: .3523316,
            modelsDirectory: modelsDirectory)
        .load();
    final slot = carton.data['cartridgeSlot'];
    if (slot is! Map || slot['fitPropExcluded'] != true) return null;
    final cartridge =
        await GbaCartridgeModel.load(style, modelsDirectory: modelsDirectory);
    if (cartridge == null) return null;
    final builder = BytesBuilder(copy: false);
    final surfaces = <Map<String, dynamic>>[];
    for (final entry in [(carton, 'box'), (cartridge, 'cartridge')]) {
      final (model, part) = entry;
      final offset = builder.length;
      final bytes = Uint8List.fromList(model.mesh.buffer
          .asUint8List(model.mesh.offsetInBytes, model.mesh.lengthInBytes));
      final data = ByteData.sublistView(bytes);
      for (final original in model.surfaces) {
        final surface =
            jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
        for (var i = 0; i < surface['vertexCount']; i++) {
          final vertex = (surface['vertexOffset'] as int) + i * 32;
          if (surface['role'] == 'label') {
            final u = data.getFloat32(vertex + 24, Endian.little);
            final v = data.getFloat32(vertex + 28, Endian.little);
            data.setFloat32(
                vertex + 24, part == 'box' ? u : u / 3, Endian.little);
            data.setFloat32(vertex + 28,
                part == 'box' ? v * 2 / 3 : (2 + v) / 3, Endian.little);
          }
        }
        surface['vertexOffset'] = (surface['vertexOffset'] as int) + offset;
        surface['indexOffset'] = (surface['indexOffset'] as int) + offset;
        surface['unboxingPart'] = part;
        surfaces.add(surface);
      }
      builder.add(bytes);
    }
    final bytes = builder.takeBytes();
    final source = sha256
        .convert(utf8.encode(jsonEncode([
          carton.data['sourceReference'],
          cartridge.data['sourceReference']
        ])))
        .toString();
    final center = (slot['fitCenter'] as List).cast<num>();
    final fit = (slot['fitBounds'] as List).cast<List>();
    return SocketMediaModel.privatePackaging({
      'name': 'gba-holder-unboxing-v1',
      'packagingGeometry': true,
      'privateImport': true,
      'unboxingGeometry': true,
      'motionKind': 'packaging',
      'bounds': [2, 2, .3523316],
      'sourceWidth': 2,
      'labelAspect': 1,
      'frontSign': 1,
      'canOpen': true,
      'openingDurationMs': 3000,
      'cartridgeStyle': style,
      'seatCenter': [center[0], center[1], center[2] * .3523316 / 2],
      'seatScale': (fit[1][1] as num) - (fit[0][1] as num),
      'geometrySha256': sha256.convert(bytes).toString(),
      'sourceReference': {
        'author': 'Owner-imported carton and cartridge',
        'url': 'local:holder-unboxing',
        'licence': 'local-import-only',
        'sha256': source,
        'sources': [
          carton.data['sourceReference'],
          cartridge.data['sourceReference']
        ]
      },
      'surfaces': surfaces,
    }, ByteData.sublistView(bytes), textureBundle: cartridge.textureBundle);
  }

  static double phase(double t, double start, double end) {
    final p = ((t - start) / (end - start)).clamp(0.0, 1.0);
    return p * p * (3 - 2 * p);
  }

  static double opening(double t) => phase(t, 0, 3 / 6.5);

  static vm.Matrix4 partTransform(
      SocketMediaModel model, String part, double t, double worldWidth) {
    final earlySlide = phase(t, 3 / 6.5, 4.2 / 6.5) * .28;
    final depart = phase(t, 4.2 / 6.5, 5.3 / 6.5);
    final boxX = -earlySlide - depart * (worldWidth / 2 + 3);
    if (part == 'box') {
      return vm.Matrix4.translationValues(boxX, 0, 0);
    }
    final seat = (model.data['seatCenter'] as List).cast<num>();
    final scale = (model.data['seatScale'] as num).toDouble();
    final extract = phase(t, 3 / 6.5, 4.2 / 6.5);
    // Bottom clears the holder and open top before the medium turns. Its
    // initial leftward travel follows the holder, so it cannot shear through it.
    final settle = phase(t, 4.2 / 6.5, 1);
    final x = (seat[0].toDouble() - earlySlide) * (1 - settle);
    final y = (seat[1].toDouble() + extract * 1.12) * (1 - settle);
    final z = seat[2].toDouble() * (1 - settle);
    final size = scale + (3.0 - scale) * phase(t, 5.0 / 6.5, 1);
    return vm.Matrix4.identity()
      ..translateByDouble(x, y, z, 1)
      ..rotateZ(math.pi / 2 * (1 - settle))
      ..scaleByDouble(size, size, size, 1);
  }
}
