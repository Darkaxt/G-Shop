import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/console_model.dart';
import 'package:g_shop/models/nes_launch_scene.dart';
import 'package:g_shop/models/nes_media_catalogue.dart';
import 'package:g_shop/models/nes_unboxing_scene.dart';
import 'package:g_shop/models/socket_media_model.dart';
import 'package:g_shop/widgets/socket_media_renderer.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mediaRoot = Platform.environment['GSHOP_NES_IMPORTS'];
  final targetRoot = Platform.environment['GSHOP_NES_LAUNCH_IMPORTS'];
  final absent = mediaRoot == null || targetRoot == null
      ? 'Private owner geometry is not bundled'
      : false;

  Future<SocketMediaModel> load(String style) async {
    final root = Directory(mediaRoot!);
    final catalogue = (await NesMediaCatalogue.load(modelsDirectory: root))!;
    final box =
        (await catalogue.editions.values.first.load(modelsDirectory: root))!;
    final target = (await ConsoleModel.findNesLaunchTarget('front-loader',
        modelsDirectory: Directory(targetRoot!)))!;
    return NesLaunchScene(
            NesUnboxingScene(box, style, modelsDirectory: root), target)
        .load();
  }

  test('uncalibrated and incompatible console identities cannot be selected',
      () async {
    expect(() => ConsoleModel.findNesLaunchTarget('famicom'),
        throwsFormatException);
    expect(() => ConsoleModel.findNesLaunchTarget('../front-loader'),
        throwsFormatException);
  });

  test(
      'real selected shells clear the front aperture before being pressed down',
      () async {
    for (final style in [
      'nintendo-3-gray',
      'nintendo-5-gray',
      'nintendo-3-gold',
      'nintendo-5-gold',
      'tengen',
      'camerica-gold',
      'camerica-silver',
      'dreams-blue',
      'dreams-black',
      'ave-square',
      'ave-angle',
      'active-clear',
      'aladdin'
    ]) {
      final m = await load(style);
      expect(m.data['cartridgeStyle'], style);
      expect(m.data['sourceReference']['sources'], hasLength(2));
      final profile = m.data['launchHardware'] as Map;
      expect(profile['controllerLayout']['cableSide'], 'right');
      expect(
          profile['controllerLayout']['controllerPosition'], 'centered-front');
      expect(profile['controllerLayout']['controllerBottomZ'],
          closeTo(profile['controllerLayout']['groundZ'] as num, .0001));
      expect(
          profile['controllerLayout']['cableBottomZ'],
          greaterThanOrEqualTo(
              (profile['controllerLayout']['groundZ'] as num) - .0001));
      final c = (profile['sourceCenter'] as List).cast<num>();
      final scale = profile['sourceScale'] as num;
      final controller = m.surfaces.firstWhere((s) =>
          s['launchPart'] == 'console' &&
          s['node'] ==
              'NES_Controller|NES_Cotroller_Case.002|Dupli|4_Base_Light_Grey_0');
      final controllerPoints = <vm.Vector3>[
        for (var i = 0; i < controller['vertexCount']; i++)
          vm.Vector3(
            m.mesh.getFloat32(
                        controller['vertexOffset'] + i * 32, Endian.little) /
                    scale +
                c[0],
            -(m.mesh.getFloat32(controller['vertexOffset'] + i * 32 + 8,
                        Endian.little) /
                    scale +
                c[2]),
            m.mesh.getFloat32(controller['vertexOffset'] + i * 32 + 4,
                        Endian.little) /
                    scale +
                c[1],
          ),
      ];
      final xs = controllerPoints.map((p) => p.x).toList()..sort();
      expect((xs.first + xs.last) / 2, closeTo(0, .001),
          reason: 'controller centered across the console');
      expect(controllerPoints.every((p) => p.y < -17.9), isTrue,
          reason: 'controller entirely in front of the console');
      final body = m.surfaces.firstWhere((s) =>
          s['launchPart'] == 'console' &&
          !(profile['trayNodes'] as List).contains(s['node']));
      for (var step = 0; step <= 25; step++) {
        final p = SocketMediaPose(unboxing: 1, launch: .35 + .25 * step / 25);
        final inverse =
            vm.Matrix4.inverted(NesLaunchScene.partTransform(m, body, p));
        for (final s
            in m.surfaces.where((s) => s['launchPart'] == 'cartridge')) {
          final transform = inverse *
              NesLaunchScene.partTransform(m, s, p) *
              SocketMediaGpu.openingTransform(
                  s, SocketMediaGpu.surfaceOpening(m, s, p));
          final points = <vm.Vector3>[];
          for (var i = 0; i < (s['vertexCount'] as int); i++) {
            final offset = (s['vertexOffset'] as int) + i * 32;
            final v = transform.transformed3(vm.Vector3(
                m.mesh.getFloat32(offset, Endian.little),
                m.mesh.getFloat32(offset + 4, Endian.little),
                m.mesh.getFloat32(offset + 8, Endian.little)));
            points.add(vm.Vector3(
                v.x / scale + c[0], -(v.z / scale + c[2]), v.y / scale + c[1]));
          }
          for (var i = 0; i < (s['indexCount'] as int); i += 3) {
            final triangle = [
              for (var j = 0; j < 3; j++)
                points[m.mesh.getUint32(
                    (s['indexOffset'] as int) + (i + j) * 4, Endian.little)]
            ];
            for (var j = 0; j < 3; j++) {
              final a = triangle[j], b = triangle[(j + 1) % 3];
              const frontY = -10.16;
              if ((a.y - frontY) * (b.y - frontY) >= 0) continue;
              final f = (frontY - a.y) / (b.y - a.y);
              final x = a.x + (b.x - a.x) * f, z = a.z + (b.z - a.z) * f;
              expect(x, inInclusiveRange(-10.0, 5.9),
                  reason: '$style aperture width');
              expect(z, inInclusiveRange(4.955, 8.878),
                  reason: '$style aperture clearance at launch=${p.launch}');
            }
          }
          if (step == 25) {
            expect(points.every((v) => v.y > -10.16), isTrue,
                reason: '$style fully inside before the tray press');
          }
        }
      }
      expect(
          m.surfaces.any(
              (s) => s['role'] == 'label' && s['launchPart'] == 'cartridge'),
          isTrue);
    }
  }, skip: absent);
}
