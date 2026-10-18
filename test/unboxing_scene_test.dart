import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:retro_eshop/models/unboxing_scene.dart';
import 'package:retro_eshop/models/socket_media_model.dart';
import 'package:retro_eshop/widgets/socket_media_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['RSHOP_UNBOXING_MODEL_DIR'];
  test('real holder scene extracts two objects into a retained three-part view',
      () async {
    final model = (await UnboxingScene('blue',
            hasBooklet: true, modelsDirectory: Directory(root!))
        .load())!;
    expect(model.data['unboxingGeometry'], true);
    expect(
        model.surfaces.where((s) => s['unboxingPart'] == 'box'), hasLength(59));
    expect(model.surfaces.where((s) => s['unboxingPart'] == 'cartridge'),
        hasLength(35));
    expect(model.surfaces.where((s) => s['unboxingPart'] == 'booklet'),
        hasLength(7));
    final start = UnboxingScene.partTransform(model, 'cartridge', 0, 6);
    final center = start.transform3(vm.Vector3.zero());
    expect(center.x, closeTo(.45625, .001));
    expect(center.y, greaterThan(0));
    final bottom = start.transform3(vm.Vector3(-.5, 0, 0));
    expect(bottom.x, greaterThan(-.05));
    expect(UnboxingScene.opening(3 / 10, hasBooklet: true), 1);
    expect(UnboxingScene.opening(.6 / 10, hasBooklet: true), 0,
        reason: 'Frame out the closed front before opening it');
    for (final viewport in [const Size(620, 403), const Size(960, 540)]) {
      // Project the actual front print, not the whole mesh bounds (which
      // include hinges and contents hidden behind the front).
      final front = model.surfaces
          .firstWhere((s) => s['node'] == '01_Front' && s['role'] == 'label');
      final units = SocketMediaGpu.fittedUnits(model, viewport,
          pose: const SocketMediaPose(unboxing: 0, rx: .06, ry: -.2));
      final matrix = SocketMediaGpu.cameraProjection(
          viewport.width, viewport.height, units)
        ..multiply(SocketMediaGpu.modelTransform(
            model, const SocketMediaPose(unboxing: 0, rx: .06, ry: -.2)));
      var left = double.infinity, right = double.negativeInfinity;
      var top = double.infinity, bottom = double.negativeInfinity;
      for (var i = 0; i < front['vertexCount']; i++) {
        final offset = (front['vertexOffset'] as int) + i * 32;
        final v = matrix.transform(vm.Vector4(
            model.mesh.getFloat32(offset, Endian.little),
            model.mesh.getFloat32(offset + 4, Endian.little),
            model.mesh.getFloat32(offset + 8, Endian.little),
            1));
        final x = (1 + v.x / v.w) * viewport.width / 2;
        final y = (1 - v.y / v.w) * viewport.height / 2;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
      final side = viewport.shortestSide;
      expect(right - left, closeTo(side, 2));
      expect(bottom - top, closeTo(side, 2));
      expect((left + right) / 2, closeTo(viewport.width / 2, 1));
      expect((top + bottom) / 2, closeTo(viewport.height / 2, 1));
    }
    final extracted =
        UnboxingScene.partTransform(model, 'cartridge', 4.2 / 10, 6);
    expect(extracted.transform3(vm.Vector3(-.5, 0, 0)).x, greaterThan(1.05));
    final bookWaiting =
        UnboxingScene.partTransform(model, 'booklet', 6.5 / 10, 6);
    expect(bookWaiting.transform3(vm.Vector3.zero()).x, closeTo(0, .00001),
        reason: 'Booklet waits until the cartridge has settled on the left');
    final cartSettled =
        UnboxingScene.partTransform(model, 'cartridge', 6.5 / 10, 6);
    expect(cartSettled.transform3(vm.Vector3.zero()).x, lessThan(-1.5));
    final bookExtracted =
        UnboxingScene.partTransform(model, 'booklet', 7.7 / 10, 6);
    expect(bookExtracted.transform3(vm.Vector3(0, -1, 0)).x, greaterThan(1.05));
    // Translation, turning and laying down belong to the same post-clear sweep.
    for (final seconds in [8.0, 8.5, 9.0]) {
      final sweep =
          UnboxingScene.partTransform(model, 'booklet', seconds / 10, 6);
      final normal = sweep.getRotation().transform(vm.Vector3(0, 0, 1))
        ..normalize();
      expect(normal.y, greaterThan(.01),
          reason: 'The booklet must already be laying down at $seconds');
      expect(sweep.transform3(vm.Vector3.zero()).z, greaterThan(-.11),
          reason: 'Position and rotation must advance together');
    }
    final finalPose = UnboxingScene.partTransform(model, 'cartridge', 1, 6);
    expect(finalPose.transform3(vm.Vector3.zero()).x, lessThan(-1.5));
    expect(
        UnboxingScene.partTransform(model, 'booklet', 1, 6)
            .transform3(vm.Vector3.zero())
            .x,
        greaterThan(1.5));
    expect(
        UnboxingScene.partTransform(model, 'box', 1, 6)
            .transform3(vm.Vector3.zero())
            .x,
        closeTo(0, .00001));
    expect(UnboxingScene.opening(1, hasBooklet: true), 0);
    // Resting objects lie on the same tabletop, not merely lean towards it.
    // The upright box is at the rear centre of a shallow semicircle.
    final boxPose = UnboxingScene.partTransform(model, 'box', 1, 6);
    final boxBottom = boxPose.transform3(vm.Vector3(0, -1, 0)).y;
    for (final part in ['cartridge', 'booklet']) {
      final pose = UnboxingScene.partTransform(model, part, 1, 6);
      final normal = pose.getRotation().transform(vm.Vector3(0, 0, 1))
        ..normalize();
      expect(normal.y, closeTo(1, .00001), reason: '$part must lie flat');
      expect(normal.z, closeTo(0, .00001));
      final bounds = (model.data['partBounds'] as Map)[part] as List;
      var lowest = double.infinity;
      for (var x = 0; x < 2; x++) {
        for (var y = 0; y < 2; y++) {
          for (var z = 0; z < 2; z++) {
            final point = pose.transform3(vm.Vector3(
                (bounds[x][0] as num).toDouble(),
                (bounds[y][1] as num).toDouble(),
                (bounds[z][2] as num).toDouble()));
            if (point.y < lowest) lowest = point.y;
          }
        }
      }
      expect(lowest, closeTo(boxBottom, .00001),
          reason: '$part and box must share a supporting plane');
      expect(pose.transform3(vm.Vector3.zero()).z,
          greaterThan(boxPose.transform3(vm.Vector3.zero()).z + .5));
    }
    for (final viewport in [const Size(620, 403), const Size(960, 540)]) {
      final overview = SocketMediaGpu.modelTransform(
          model, const SocketMediaPose(unboxing: 1));
      final upward = overview.getRotation().transform(vm.Vector3(0, 1, 0));
      expect(upward.z, greaterThan(.5),
          reason: 'The overview must look down onto the horizontal faces');
      final rects = SocketMediaGpu.inspectionBounds(model,
          const SocketMediaPose(unboxing: 1, rx: .06, ry: -.2), viewport);
      expect(rects.keys, containsAll(['box', 'cartridge', 'booklet']));
      expect(rects['cartridge']!.right, lessThan(rects['box']!.left));
      expect(rects['booklet']!.left, greaterThan(rects['box']!.right));
      for (final rect in rects.values) {
        expect(rect.left, greaterThanOrEqualTo(8));
        expect(rect.right, lessThanOrEqualTo(viewport.width - 8));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(viewport.height));
      }
      for (final part in rects.keys) {
        final selected = SocketMediaGpu.inspectionBounds(
            model,
            SocketMediaPose(unboxing: 1, inspectedPart: part, inspection: 1),
            viewport);
        expect(selected[part]!.width, greaterThan(rects[part]!.width));
        expect(selected[part]!.center.dx, closeTo(viewport.width / 2, 1));
      }
    }
    final lid = model.surfaces.firstWhere((s) => s['node'] == 'Top_lid');
    expect(SocketMediaGpu.openingTransform(lid, 1).storage,
        isNot(orderedEquals(SocketMediaGpu.openingTransform(lid, 0).storage)));
    expect(model.data['openingSide'], 'right');
    // The physical right-hand opening and front artwork must agree;
    // rotating only the UVs
    // would fail this check even if a still front screenshot looked upright.
    final front = model.surfaces
        .firstWhere((s) => s['node'] == '01_Front' && s['role'] == 'label');
    final vertex = front['vertexOffset'] as int;
    final firstY = model.mesh.getFloat32(vertex + 4, Endian.little);
    final firstV = model.mesh.getFloat32(vertex + 28, Endian.little);
    final upperY = model.mesh.getFloat32(vertex + 2 * 32 + 4, Endian.little);
    final upperV = model.mesh.getFloat32(vertex + 2 * 32 + 28, Endian.little);
    expect(upperY, lessThan(firstY));
    expect(upperV, greaterThan(firstV));
    for (var i = 0; i < lid['vertexCount']; i++) {
      expect(
          model.mesh
              .getFloat32((lid['vertexOffset'] as int) + i * 32, Endian.little),
          closeTo(1, .002));
    }
  }, skip: root == null ? 'Requires owner local imports' : false);
}
