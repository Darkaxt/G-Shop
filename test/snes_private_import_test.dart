import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/console_model.dart';
import 'package:g_shop/features/preview/console_hardware_view.dart';
import 'package:g_shop/models/socket_media_model.dart';
import 'package:g_shop/widgets/socket_media_renderer.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

// Actual private source/texture verification; no third-party payload in Git.
void main() {
  final path = Platform.environment['GSHOP_SNES_IMPORTS'];
  test(
      'prepared SNES overview passes the production geometry and texture loader',
      () async {
    final console =
        (await ConsoleModel.find('snes', modelsDirectory: Directory(path!)))!;
    expect(console.isCollectionOverview, isTrue);
    expect(console.canOpen, isFalse);
    final model = await console.load();
    expect(model.mesh.lengthInBytes, lessThanOrEqualTo(20 * 1024 * 1024));
    expect(model.surfaces.length, lessThanOrEqualTo(128));
    expect(model.data['groundSupports'], hasLength(6));
    expect(
        () => SocketMediaModel.privateHardware({
              ...model.data,
              'groundSupports': [
                [0, 0, double.nan, 1]
              ]
            }, model.mesh, textureBundle: model.textureBundle!),
        throwsFormatException);
    expect(
        () => SocketMediaModel.privateHardware({
              ...model.data,
              'groundSupports': [
                [1, 0, 0, 1]
              ]
            }, model.mesh, textureBundle: model.textureBundle!),
        throwsFormatException);
    // The earlier screen-relative glow sat below the physical supports. Bind
    // its centre to the actual mesh's ground plane through changing cameras.
    final low = vm.Vector3.all(double.infinity);
    final high = vm.Vector3.all(double.negativeInfinity);
    for (final surface in model.surfaces) {
      for (var i = 0; i < surface['vertexCount']; i++) {
        final offset = (surface['vertexOffset'] as int) + i * 32;
        for (var axis = 0; axis < 3; axis++) {
          final value = model.mesh.getFloat32(offset + axis * 4, Endian.little);
          if (value < low[axis]) low[axis] = value;
          if (value > high[axis]) high[axis] = value;
        }
      }
    }
    const viewport = Size(1240, 1080);
    for (final yaw in [0.0, .8, 2.5]) {
      final pose = SocketMediaPose(
          rx: ConsoleHardwareViewState.selectorPitch,
          ry: yaw,
          scaleX: .9,
          scaleY: .9,
          scaleZ: .9);
      final floor = SocketMediaGpu.groundProjection(model, pose, viewport);
      final center = (low + high) * .5;
      final projected =
          (SocketMediaGpu.compositionProjection(model, pose, viewport) *
                  SocketMediaGpu.modelTransform(model, pose))
              .transform(vm.Vector4(center.x, low.y, center.z, 1));
      expect(floor, hasLength(193));
      expect(floor.first.dx,
          closeTo((1 + projected.x / projected.w) * viewport.width / 2, .001));
      expect(floor.first.dy,
          closeTo((1 - projected.y / projected.w) * viewport.height / 2, .001));
      expect(floor.first.dy, lessThan(viewport.height * .65),
          reason:
              'The stage must sit under this composition, not the old fixed 70% screen anchor');
    }
    final preparation = model.data['sourceReference']['showcasePreparation'];
    expect(preparation['sourceSha256'],
        '4905e01b24108b83b5c8eb392477bdd00f5eff822c5eb5c43ee1763f082254a6');
    expect(preparation['physicalScale'], hasLength(2));
    for (final cable in preparation['cables']) {
      expect(cable['lengthMetres'], closeTo(1.8288, .00001));
      expect(cable['straightConnectorLeadMetres'], .025);
      expect(cable['connectorLeadMaxLateralErrorMetres'], lessThan(.000001));
      final clearance = cable['controllerClearance'];
      expect(clearance['samples'], greaterThan(500));
      expect(clearance['minimumSurfaceDistanceMetres'],
          greaterThanOrEqualTo(clearance['cableRadiusMetres'] + .001));
    }
    expect(preparation['crossControllerClearance'], hasLength(2));
    for (final check in preparation['crossControllerClearance']) {
      expect(check['intersectingTrianglePairs'], 0);
    }
    final names = (preparation['objects'] as List)
        .map((o) => o['object'] as String)
        .toList();
    expect(names.any((n) => n.startsWith('US_Manny_')), isTrue);
    expect(names.any((n) => n.startsWith('PAL_bottom_')), isTrue);
    expect(names.any((n) => n.contains('Display_Plinth')), isFalse);
    for (final name in (model.data['textureFiles'] as Map).keys) {
      expect(
          (await model.textureBundle!
                  .load('${SocketMediaModel.assetRoot}$name'))
              .lengthInBytes,
          greaterThan(0));
    }
  },
      skip: path == null
          ? 'Set GSHOP_SNES_IMPORTS to the private imports root'
          : false);
}
