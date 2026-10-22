import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:g_shop/models/console_model.dart';
import 'package:g_shop/models/nes_media_catalogue.dart';
import 'package:g_shop/models/socket_media_model.dart';
import 'package:g_shop/widgets/socket_media_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final imports = Platform.environment['GSHOP_NES_IMPORTS'];
  final cataloguePath = Platform.environment['GSHOP_NES_CATALOGUE'];
  test(
      'every bound imported carton retains geometry and a face-aligned badge surface',
      () async {
    final root = Directory(imports!);
    final catalogue = NesMediaCatalogue.parse(
        jsonDecode(await File(cataloguePath!).readAsString()));
    for (final edition in catalogue.editions.values) {
      final source = (await edition.load(modelsDirectory: root))!;
      final original = await source.load();
      final decorated = ConsoleModel.withGalleryBadges(original);
      expect(
          decorated.mesh.buffer.asUint8List(0, original.mesh.lengthInBytes),
          orderedEquals(original.mesh.buffer.asUint8List(
              original.mesh.offsetInBytes, original.mesh.lengthInBytes)));
      expect(decorated.data['galleryFrontBasis'], isNull);
      expect(original.surfaces.any((s) => s['galleryBadges'] == true), false);
      expect(decorated.surfaces.length, original.surfaces.length + 1);
      final badge =
          decorated.surfaces.singleWhere((s) => s['galleryBadges'] == true);
      final front = original
          .surfaces[decorated.data['galleryBadgeFrontSurfaceIndex'] as int];
      for (final key in ['vertexCount', 'indexCount']) {
        expect(badge[key], front[key],
            reason: '${edition.id}: original face triangles/UVs');
      }
      expect(badge['role'], 'label');
      expect(decorated.labelAspect, inInclusiveRange(.5, 2.0));
      for (final yaw in [-.70, -.523599, 0.0, .523599]) {
        final pose = SocketMediaPose(ry: yaw);
        final base = SocketMediaGpu.modelTransform(decorated, pose);
        expect(
            base.storage,
            orderedEquals(
                SocketMediaGpu.modelTransform(original, pose).storage),
            reason:
                'Badge placement must not rotate the source carton to hide orientation errors');
        final a = SocketMediaGpu.surfaceTransform(
            decorated, front, pose, base, const Size(400, 300), 100);
        final b = SocketMediaGpu.surfaceTransform(
            decorated, badge, pose, base, const Size(400, 300), 100);
        final offset = front['vertexOffset'] as int;
        final vertex = vm.Vector3(
            original.mesh.getFloat32(offset, Endian.little),
            original.mesh.getFloat32(offset + 4, Endian.little),
            original.mesh.getFloat32(offset + 8, Endian.little));
        expect((a.transformed3(vertex) - b.transformed3(vertex)).length,
            lessThan(.001));
        expect((a.transformed3(vertex) - b.transformed3(vertex)).length,
            greaterThan(0));
      }
      for (var i = 0; i < badge['vertexCount']; i++) {
        final at = (badge['vertexOffset'] as int) + i * 32;
        expect(decorated.mesh.getFloat32(at + 24, Endian.little),
            inInclusiveRange(0, 1));
        expect(decorated.mesh.getFloat32(at + 28, Endian.little),
            inInclusiveRange(0, 1));
        expect(decorated.mesh.getFloat32(at + 20, Endian.little),
            closeTo(1, .00001));
      }
    }
  },
      skip: imports == null || cataloguePath == null
          ? 'Private owner models are not bundled'
          : false);
}
