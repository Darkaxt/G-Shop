import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:g_shop/models/console_model.dart';
import 'package:g_shop/models/nes_launch_scene.dart';
import 'package:g_shop/models/nes_media_catalogue.dart';
import 'package:g_shop/models/nes_unboxing_scene.dart';
import 'package:g_shop/models/socket_media_model.dart';
import 'package:g_shop/widgets/socket_media_renderer.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

typedef _Triangle = ({
  vm.Vector3 a,
  vm.Vector3 b,
  vm.Vector3 c,
  vm.Vector3 low,
  vm.Vector3 high
});

List<_Triangle> _meshTriangles(SocketMediaModel model,
    Map<String, dynamic> surface, vm.Matrix4 transform) {
  final points = <vm.Vector3>[];
  for (var i = 0; i < surface['vertexCount']; i++) {
    final o = surface['vertexOffset'] + i * 32;
    points.add(transform.transformed3(vm.Vector3(
        model.mesh.getFloat32(o, Endian.little),
        model.mesh.getFloat32(o + 4, Endian.little),
        model.mesh.getFloat32(o + 8, Endian.little))));
  }
  return [
    for (var i = 0; i < surface['indexCount']; i += 3)
      (() {
        final v = [
          for (var j = 0; j < 3; j++)
            points[model.mesh
                .getUint32(surface['indexOffset'] + (i + j) * 4, Endian.little)]
        ];
        return (
          a: v[0],
          b: v[1],
          c: v[2],
          low: vm.Vector3(
              v.map((p) => p.x).reduce(math.min),
              v.map((p) => p.y).reduce(math.min),
              v.map((p) => p.z).reduce(math.min)),
          high: vm.Vector3(
              v.map((p) => p.x).reduce(math.max),
              v.map((p) => p.y).reduce(math.max),
              v.map((p) => p.z).reduce(math.max))
        );
      })()
  ];
}

bool _boundsOverlap(vm.Vector3 a, vm.Vector3 b, vm.Vector3 c, vm.Vector3 d) =>
    a.x <= d.x &&
    b.x >= c.x &&
    a.y <= d.y &&
    b.y >= c.y &&
    a.z <= d.z &&
    b.z >= c.z;

bool _segmentHits(vm.Vector3 start, vm.Vector3 end, _Triangle triangle) {
  final direction = end - start,
      e1 = triangle.b - triangle.a,
      e2 = triangle.c - triangle.a;
  final h = direction.cross(e2), determinant = e1.dot(h);
  if (determinant.abs() < 1e-10) return false;
  final inverse = 1 / determinant,
      s = start - triangle.a,
      u = inverse * s.dot(h);
  if (u < 0 || u > 1) return false;
  final q = s.cross(e1), v = inverse * direction.dot(q);
  if (v < 0 || u + v > 1) return false;
  final distance = inverse * e2.dot(q);
  return distance >= 0 && distance <= 1;
}

bool _trianglesIntersect(_Triangle a, _Triangle b) =>
    _boundsOverlap(a.low, a.high, b.low, b.high) &&
    (_segmentHits(a.a, a.b, b) ||
        _segmentHits(a.b, a.c, b) ||
        _segmentHits(a.c, a.a, b) ||
        _segmentHits(b.a, b.b, a) ||
        _segmentHits(b.b, b.c, a) ||
        _segmentHits(b.c, b.a, a));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mediaRoot = Platform.environment['GSHOP_NES_IMPORTS'];
  final targetRoot = Platform.environment['GSHOP_NES_LAUNCH_IMPORTS'];
  final absent = mediaRoot == null || targetRoot == null
      ? 'Private owner geometry is not bundled'
      : false;

  Future<SocketMediaModel> load(String style,
      {String target = 'front-loader'}) async {
    final root = Directory(mediaRoot!);
    final catalogue = (await NesMediaCatalogue.load(modelsDirectory: root))!;
    final box =
        (await catalogue.editions.values.first.load(modelsDirectory: root))!;
    final console = (await ConsoleModel.findNesLaunchTarget(target,
        modelsDirectory: Directory(targetRoot!)))!;
    final display = (await ConsoleModel.findNesLaunchDisplay(
        modelsDirectory: Directory(targetRoot)))!;
    return NesLaunchScene(NesUnboxingScene(box, style, modelsDirectory: root),
            console, display)
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
      'hardware appears after camera withdrawal and packaging retires before insertion',
      () async {
    final m = await load('nintendo-3-gray');
    final hardware = m.surfaces.firstWhere((s) => s['launchPart'] == 'console');
    final box = m.surfaces.firstWhere((s) => s['launchPart'] == 'box');
    expect(NesLaunchScene.visible(hardware, const SocketMediaPose(launch: .21)),
        isFalse);
    expect(NesLaunchScene.visible(hardware, const SocketMediaPose(launch: .22)),
        isTrue);
    expect(NesLaunchScene.visible(box, const SocketMediaPose(launch: .22)),
        isFalse);
    final faded =
        NesLaunchScene.material(hardware, const SocketMediaPose(launch: .27));
    expect(faded['color'][3], closeTo(.5, .000001));
    expect(
        NesLaunchScene.material(
            hardware, const SocketMediaPose(launch: .35))['color'],
        hardware['material']['color']);
  }, skip: absent);

  final standard = Platform.environment['GSHOP_NES_STANDARD_CARTON_ID'];
  test('foam remains part of its carton and retires before console insertion',
      () async {
    final root = Directory(mediaRoot!);
    final digest = sha256
        .convert(await File('${root.path}/boxes/nes/$standard/model.json')
            .readAsBytes())
        .toString();
    final box = (await ConsoleModel.findNesBox(standard!,
        manifestSha256: digest, modelsDirectory: root))!;
    final console = (await ConsoleModel.findNesLaunchTarget('front-loader',
        modelsDirectory: Directory(targetRoot!)))!;
    final display = (await ConsoleModel.findNesLaunchDisplay(
        modelsDirectory: Directory(targetRoot)))!;
    final m = await NesLaunchScene(
            NesUnboxingScene(box, 'nintendo-3-gray', modelsDirectory: root),
            console,
            display)
        .load();
    final foam =
        m.surfaces.firstWhere((s) => s['node'] == 'Separate foam spacer');
    expect(foam['launchPart'], 'box');
    expect(
        NesLaunchScene.visible(
            foam, const SocketMediaPose(unboxing: 1, launch: .22)),
        false);
    for (final t in [0.0, .1, .22, .35, 1.0]) {
      final transform = NesLaunchScene.partTransform(
          m, foam, SocketMediaPose(unboxing: 1, launch: t));
      expect(transform.storage.every((v) => v.isFinite), true);
    }
  }, skip: absent != false || standard == null, timeout: Timeout.none);

  test(
      'launch uses the supplied calibrated curved TV, not a display placeholder',
      () async {
    final m = await load('nintendo-3-gray');
    expect(m.data['launchDisplay']['target'], 'sony-kv1300e');
    expect(m.data['launchDisplay']['physicalWidthCm'], 47.4);
    expect(m.data['sourceReference']['sources'], hasLength(3));
    final display =
        m.surfaces.where((s) => s['launchPart'] == 'display').toList();
    expect(display, hasLength(13));
    expect(display.any((s) => s['node'] == 'SonyCrtScreen'), isTrue);
    expect(
        display.any((s) => (s['node'] as String).startsWith('crt-')), isFalse);
    const pose = SocketMediaPose(unboxing: 1, launch: .82);
    var bottom = double.infinity;
    var displayRight = double.negativeInfinity;
    for (final s in display) {
      final transform = NesLaunchScene.partTransform(m, s, pose);
      for (var i = 0; i < s['vertexCount']; i++) {
        final o = s['vertexOffset'] + i * 32;
        final point = transform.transformed3(vm.Vector3(
            m.mesh.getFloat32(o, Endian.little),
            m.mesh.getFloat32(o + 4, Endian.little),
            m.mesh.getFloat32(o + 8, Endian.little)));
        bottom = math.min(bottom, point.y);
        displayRight = math.max(displayRight, point.x);
      }
    }
    expect(bottom, closeTo(-.8, .00001),
        reason: 'TV feet share the console/controller support plane');
    var consoleLeft = double.infinity;
    for (final s in m.surfaces.where((s) => s['launchPart'] == 'console')) {
      for (final triangle
          in _meshTriangles(m, s, NesLaunchScene.partTransform(m, s, pose))) {
        consoleLeft = math.min(consoleLeft, triangle.low.x);
      }
    }
    expect(displayRight + .3, lessThan(consoleLeft),
        reason: 'Same-level TV is beside the console with physical clearance');
    final screen = display.singleWhere((s) => s['node'] == 'SonyCrtScreen');
    const finalPose = SocketMediaPose(unboxing: 1, launch: 1);
    final projected = _meshTriangles(
        m,
        screen,
        NesLaunchScene.viewTransform(m, finalPose) *
            NesLaunchScene.partTransform(m, screen, finalPose));
    final xLow = projected.map((t) => t.low.x).reduce(math.min);
    final xHigh = projected.map((t) => t.high.x).reduce(math.max);
    final yLow = projected.map((t) => t.low.y).reduce(math.min);
    final yHigh = projected.map((t) => t.high.y).reduce(math.max);
    expect((xLow + xHigh) / 2, closeTo(0, .00001));
    expect((yLow + yHigh) / 2, closeTo(0, .00001));
    for (final viewport in [(1240.0, 1080.0), (640.0, 480.0)]) {
      final units =
          NesLaunchScene.fittedUnits(m, finalPose, viewport.$1, viewport.$2);
      expect((xHigh - xLow) * units, greaterThan(viewport.$1));
      expect((yHigh - yLow) * units, greaterThan(viewport.$2),
          reason: 'The actual curved screen fills the handoff viewport');
    }
    final cabinet = display.firstWhere((s) => s != screen);
    expect(NesLaunchScene.material(cabinet, pose), same(cabinet['material']));
    expect(
        NesLaunchScene.material(screen, pose)['sourceProperties']['emission'],
        isNot(screen['material']['sourceProperties']['emission']));
  }, skip: absent);

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
      expect(m.data['sourceReference']['sources'], hasLength(3));
      final profile = m.data['launchHardware'] as Map;
      expect(profile['controllerLayout']['cableSide'], 'right');
      expect(profile['controllerLayout']['nominalCableLengthCm'], 230);
      expect(profile['controllerLayout']['measuredCableLengthCm'],
          closeTo(230, .05));
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

  test(
      'NES-101 standard shells fit vertically and use the shared physical scale',
      () async {
    for (final style in [
      'nintendo-3-gray',
      'nintendo-5-gray',
      'nintendo-3-gold',
      'nintendo-5-gold',
      'nintendo-3-white'
    ]) {
      final m = await load(style, target: 'top-loader');
      final profile = m.data['launchHardware'] as Map;
      final c = (profile['sourceCenter'] as List).cast<num>();
      final scale = profile['sourceScale'] as num;
      final bounds = (profile['sourceDustFlapBounds'] as List).cast<List>();
      final body = m.surfaces.firstWhere((s) =>
          s['launchPart'] == 'console' && s['node'] == 'ToploaderPart04');
      expect(profile['powerLedNode'], isNull,
          reason: 'NES-101 has no front-loader LED');
      expect(
          profile['controllerLayout']['controllerPosition'], 'centered-front');
      expect(profile['controllerLayout']['controllerBottomZ'],
          closeTo(profile['controllerLayout']['groundZ'] as num, .0001));
      final hardware = NesLaunchScene.partTransform(
          m, body, const SocketMediaPose(unboxing: 1, launch: 1));
      final origin = hardware.transformed3(vm.Vector3.zero());
      final centimetre =
          hardware.transformed3(vm.Vector3(scale.toDouble(), 0, 0));
      expect((centimetre - origin).length, closeTo(1.85 / 25.6, .000001),
          reason: 'same cm unit as the larger front loader');
      List<_Triangle>? hardwareTriangles;
      for (var step = 0; step <= 25; step++) {
        final p = SocketMediaPose(unboxing: 1, launch: .35 + .25 * step / 25);
        final inverse =
            vm.Matrix4.inverted(NesLaunchScene.partTransform(m, body, p));
        hardwareTriangles ??= [
          for (final s in m.surfaces.where((s) =>
              s['launchPart'] == 'console' &&
              !(profile['controllerNodes'] as List).contains(s['node'])))
            ..._meshTriangles(
                m,
                s,
                inverse *
                    NesLaunchScene.partTransform(m, s, p) *
                    SocketMediaGpu.openingTransform(
                        s, SocketMediaGpu.surfaceOpening(m, s, p)))
        ];
        final cartridge = [
          for (final s
              in m.surfaces.where((s) => s['launchPart'] == 'cartridge'))
            ..._meshTriangles(
                m, s, inverse * NesLaunchScene.partTransform(m, s, p))
        ];
        final low = vm.Vector3.all(double.infinity),
            high = vm.Vector3.all(double.negativeInfinity);
        for (final t in cartridge) {
          for (var axis = 0; axis < 3; axis++) {
            low[axis] = math.min(low[axis], t.low[axis]);
            high[axis] = math.max(high[axis], t.high[axis]);
          }
        }
        final candidates = hardwareTriangles
            .where((t) => _boundsOverlap(t.low, t.high, low, high))
            .toList();
        for (final t in cartridge) {
          expect(candidates.any((h) => _trianglesIntersect(h, t)), isFalse,
              reason:
                  '$style intersects actual NES-101 case/flap at ${p.launch}');
        }
        if (step == 25) {
          final plane = ((bounds[1][2] as num) - c[1]) * scale;
          expect(
              cartridge.any((t) => t.low.y < plane && t.high.y > plane), isTrue,
              reason: 'Seated cartridge crosses the actual slot mouth');
        }
        expect(NesLaunchScene.opening(m, body, p), 1,
            reason: 'Dust flap stays open while occupied');
      }
    }
    expect(() => load('tengen', target: 'top-loader'), throwsFormatException);
  }, skip: absent);

  test(
      'random launch pool uses compatible validated bodies and a stable descriptor',
      () async {
    final random = math.Random(7), choices = <String>{};
    for (var i = 0; i < 12; i++) {
      final console = await NesLaunchScene.chooseConsole('nintendo-3-gray',
          modelsDirectory: Directory(targetRoot!), random: random);
      expect(console, isNotNull);
      choices.add(console!.launchTarget!);
      final generation = console.generation;
      await console.load();
      expect(console.generation, generation);
    }
    expect(choices, {'front-loader', 'top-loader'});
    final restricted = await NesLaunchScene.chooseConsole('tengen',
        modelsDirectory: Directory(targetRoot!), random: random);
    expect(restricted!.launchTarget, 'front-loader');
  }, skip: absent);
}
