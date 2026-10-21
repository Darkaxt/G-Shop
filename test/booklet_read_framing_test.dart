import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:g_shop/models/packaging_model.dart';
import 'package:g_shop/models/socket_media_model.dart';
import 'package:g_shop/widgets/socket_media_renderer.dart';

void main() {
  test('all scene uniforms fit their block including GPU alignment padding',
      () {
    final materialBytes = SocketMediaGpu.materialUniforms({
      'color': [1, 1, 1, 1],
      'sourceProperties': <String, dynamic>{},
    }).lengthInBytes;
    expect(materialBytes, 112);
    for (final alignment in [16, 64, 256]) {
      for (final surfaces in [59, 65, 101, 131, 192]) {
        var cursor = 0;
        final capacity = SocketMediaGpu.uniformBlockLength(surfaces, alignment);
        for (final length in [
          64,
          for (var i = 0; i < surfaces; i++) ...[192, materialBytes]
        ]) {
          cursor = (cursor + alignment - 1) ~/ alignment * alignment;
          expect(cursor + length, lessThanOrEqualTo(capacity),
              reason:
                  '$surfaces surfaces at $alignment-byte uniform alignment');
          cursor += length;
        }
        expect(capacity - cursor, lessThan(alignment));
      }
    }
  });
  test('inspection isolates the selected object until overview is restored',
      () {
    final model = PackagingModel(PackagingKind.box).build();
    model.data.addAll({
      'unboxingGeometry': true,
      'partBounds': {
        for (final part in ['box', 'cartridge', 'booklet'])
          part: [
            [-.5, -.3, -.05],
            [.5, .3, .05]
          ]
      },
      'seatCenter': [0, 0, 0],
      'seatScale': .9,
      'bookletSeatScale': .5,
      'hasBooklet': true,
    });
    for (final selected in ['box', 'cartridge', 'booklet']) {
      for (final progress in [0.0, .01, .5, 1.0]) {
        final bounds = SocketMediaGpu.inspectionBounds(
            model,
            SocketMediaPose(
                unboxing: 1, inspectedPart: selected, inspection: progress),
            const Size(1240, 1080));
        expect(bounds.keys, [selected]);
      }
    }
    expect(
        SocketMediaGpu.inspectionBounds(model,
                const SocketMediaPose(unboxing: 1), const Size(1240, 1080))
            .keys,
        containsAll(['box', 'cartridge', 'booklet']));
  });
  test(
      'focused scene booklet opens eighteen degrees without opening the carton',
      () {
    final model = PackagingModel(PackagingKind.booklet).build();
    model.data['unboxingGeometry'] = true;
    final maximum = (model.data['maxOpenRadians'] as num).toDouble();
    for (final progress in [0.0, .5, 1.0]) {
      final pose =
          SocketMediaPose(inspectedPart: 'booklet', inspection: progress);
      expect(
          SocketMediaGpu.surfaceOpening(
                  model, {'unboxingPart': 'booklet'}, pose) *
              maximum,
          closeTo(18 * math.pi / 180 * progress, .00001));
      expect(
          SocketMediaGpu.surfaceOpening(model, {'unboxingPart': 'box'}, pose),
          0);
    }
    expect(
        SocketMediaGpu.surfaceOpening(model, {'unboxingPart': 'booklet'},
            const SocketMediaPose(opening: 1)),
        0,
        reason: 'The booklet stays closed inside the extraction sequence');
  });
  for (final size in [const Size(1240, 1080), const Size(1920, 1080)]) {
    for (final aspect in [.7, 1.0, 1.35]) {
      test('inside-left mesh maps upright to reader bounds $size/$aspect', () {
        final model =
            PackagingModel(PackagingKind.booklet, aspect: aspect).build();
        final surface = model.surfaces
            .firstWhere((s) => s['atlasCell'] == 2 && s['hinged'] == true);
        final pivot = (surface['pivot'] as List).cast<num>();
        final hinge = vm.Matrix4.identity()
          ..translateByDouble(pivot[0].toDouble(), 0, 0, 1)
          ..rotateY(-(model.data['maxOpenRadians'] as num).toDouble())
          ..translateByDouble(-pivot[0].toDouble(), 0, 0, 1);
        final transform = SocketMediaGpu.cameraProjection(
            size.width, size.height, SocketMediaGpu.fittedUnits(model, size))
          ..multiply(SocketMediaGpu.bookletPageTransform(model, size,
              pageAspect: aspect))
          ..multiply(hinge);
        final width = math.min(size.width, size.height * aspect);
        final height = width / aspect;
        for (var i = 0; i < surface['vertexCount']; i++) {
          final o = (surface['vertexOffset'] as int) + i * 32;
          final p = transform.transform(vm.Vector4(
              model.mesh.getFloat32(o, Endian.little),
              model.mesh.getFloat32(o + 4, Endian.little),
              model.mesh.getFloat32(o + 8, Endian.little),
              1));
          final x = (p.x / p.w + 1) * size.width / 2;
          final y = (1 - p.y / p.w) * size.height / 2;
          final u = model.mesh.getFloat32(o + 24, Endian.little) * 3 - 2;
          final v = model.mesh.getFloat32(o + 28, Endian.little) * 2;
          expect(x, closeTo((size.width - width) / 2 + u * width, .002));
          expect(y, closeTo((size.height - height) / 2 + v * height, .002));
        }
      });
    }
  }
}
