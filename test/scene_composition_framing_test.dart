import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/console_model.dart';
import 'package:g_shop/models/game_watch_unboxing_scene.dart';
import 'package:g_shop/models/nes_launch_scene.dart';
import 'package:g_shop/models/nes_media_catalogue.dart';
import 'package:g_shop/models/nes_unboxing_scene.dart';
import 'package:g_shop/models/packaging_model.dart';
import 'package:g_shop/models/socket_media_model.dart';
import 'package:g_shop/models/unboxing_scene.dart';
import 'package:g_shop/widgets/socket_media_renderer.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

// Measure actual rendered vertices independently of the fitted envelopes.
Rect _pixels(SocketMediaModel m, SocketMediaPose p, Size size,
    {double zoom = 1, String? node}) {
  final projection =
      SocketMediaGpu.compositionProjection(m, p, size, zoom: zoom);
  final units = SocketMediaGpu.fittedUnits(m, size, pose: p);
  final base = SocketMediaGpu.modelTransform(m, p);
  var left = double.infinity, top = double.infinity;
  var right = double.negativeInfinity, bottom = double.negativeInfinity;
  for (final s in m.surfaces) {
    if (node != null && s['node'] != node) continue;
    if (m.data['nesLaunch'] == true && !NesLaunchScene.visible(s, p)) continue;
    if (!SocketMediaGpu.partVisible(
        (s['nesPart'] ?? s['hardwarePart'] ?? s['unboxingPart']) as String?,
        p)) {
      continue;
    }
    final transform = projection *
        SocketMediaGpu.surfaceTransform(m, s, p, base, size, units);
    for (var i = 0; i < s['vertexCount']; i++) {
      final o = (s['vertexOffset'] as int) + i * 32;
      final v = transform.transform(vm.Vector4(
          m.mesh.getFloat32(o, Endian.little),
          m.mesh.getFloat32(o + 4, Endian.little),
          m.mesh.getFloat32(o + 8, Endian.little),
          1));
      final x = (1 + v.x / v.w) * size.width / 2;
      final y = (1 - v.y / v.w) * size.height / 2;
      left = math.min(left, x);
      right = math.max(right, x);
      top = math.min(top, y);
      bottom = math.max(bottom, y);
    }
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

void _reserved(Rect rect, Size size) {
  const tolerance = .001;
  expect(rect.left, greaterThanOrEqualTo(size.width * .125 - tolerance));
  expect(rect.right, lessThanOrEqualTo(size.width * .875 + tolerance));
  expect(rect.top, greaterThanOrEqualTo(size.height * .125 - tolerance));
  expect(rect.bottom, lessThanOrEqualTo(size.height * .875 + tolerance));
  expect(math.max(rect.width / size.width, rect.height / size.height),
      greaterThanOrEqualTo(.70),
      reason: 'Actual geometry uses the reserved central area');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sizes = [Size(537.67, 331.27), Size(640, 480), Size(360, 640)];
  test(
      'lower camera centers rotated open geometry and explicit zoom still works',
      () {
    final m = PackagingModel(PackagingKind.keepCase).build();
    for (final size in sizes) {
      for (final angle in [0.0, .7, math.pi / 2, math.pi]) {
        final p = SocketMediaPose(rx: .18, ry: angle, opening: 1);
        final normal = _pixels(m, p, size);
        _reserved(normal, size);
        final zoomed = _pixels(m, p, size, zoom: 1.3);
        expect(zoomed.width, closeTo(normal.width * 1.3, .001));
        expect(zoomed.height, closeTo(normal.height * 1.3, .001));
      }
    }
    const upper = SocketMediaRenderer(
        format: PhysicalMediaFormat.nes,
        pose: SocketMediaPose(),
        identity: 'upper',
        title: 'Upper card',
        label: SizedBox());
    expect(upper.frameComposition, isFalse,
        reason: 'Upper cards retain their separate presentation');
  });

  final gw = Platform.environment['RSHOP_GAMEWATCH_MODEL_DIR'];
  test('real Game & Watch pairs use the central area throughout extraction',
      () async {
    for (final set in ['gnw_ball', 'gnw_bfight', 'gnw_climber', 'gnw_dkjr']) {
      final variants = await ConsoleModel.findGameWatchVariants('$set.zip',
          modelsDirectory: Directory(gw!));
      for (final variant in variants.where((v) => v.box != null)) {
        final scene = GameWatchUnboxingScene(variant.model, variant.box!);
        final m = await scene.load();
        for (final size in sizes) {
          for (var step = 0; step <= 20; step++) {
            final p = SocketMediaPose(
                unboxing: step / 20,
                opening: scene.handheldOpening(step / 20),
                rx: .18,
                ry: -.2,
                scaleX: .9,
                scaleY: .9,
                scaleZ: .9);
            _reserved(_pixels(m, p, size), size);
          }
        }
      }
    }
  }, skip: gw == null ? 'Private owner imports are not bundled' : false);

  final gba = Platform.environment['RSHOP_UNBOXING_MODEL_DIR'];
  test(
      'GBA box, cartridge and booklet retain margins through the full sequence',
      () async {
    final m = (await UnboxingScene('blue',
            hasBooklet: true, modelsDirectory: Directory(gba!))
        .load())!;
    for (final size in sizes) {
      for (var step = 0; step <= 30; step++) {
        final p = SocketMediaPose(
            unboxing: step / 30,
            opening: UnboxingScene.opening(step / 30, hasBooklet: true),
            rx: .06,
            ry: -.2);
        _reserved(_pixels(m, p, size), size);
      }
      final p = const SocketMediaPose(
          unboxing: 1,
          inspectedPart: 'cartridge',
          inspection: 1,
          rx: .06,
          ry: -.2);
      final rect = _pixels(m, p, size);
      _reserved(rect, size);
      final target = SocketMediaGpu.inspectionBounds(m, p, size,
          frameComposition: true)['cartridge']!;
      expect(target.contains(rect.center), isTrue,
          reason: 'Inspection hit testing follows the fitted camera');
    }
  }, skip: gba == null ? 'Private owner imports are not bundled' : false);

  final nes = Platform.environment['GSHOP_NES_IMPORTS'];
  final launch = Platform.environment['GSHOP_NES_LAUNCH_IMPORTS'];
  test('supplied collector compositions fit throughout their turntable',
      () async {
    for (final entry in [('nes', nes), ('gameandwatch', gw)]) {
      if (entry.$2 == null) continue;
      final console = (await ConsoleModel.find(entry.$1,
          modelsDirectory: Directory(entry.$2!)))!;
      final m = await console.load();
      for (final size in sizes) {
        for (var step = 0; step < 8; step++) {
          final pixels = _pixels(
              m,
              SocketMediaPose(
                  rx: entry.$1 == 'nes' ? .6 : .85,
                  ry: step * math.pi / 4,
                  scaleX: .9,
                  scaleY: .9,
                  scaleZ: .9),
              size);
          if (math.max(pixels.width / size.width, pixels.height / size.height) <
              .70) {
            fail('${entry.$1} turn $step size $size: actual $pixels');
          }
          _reserved(pixels, size);
        }
      }
    }
  },
      skip: nes == null && gw == null
          ? 'Private owner imports are not bundled'
          : false);
  test('NES browsing margins continue into launch without losing screen entry',
      () async {
    final root = Directory(nes!);
    final catalogue = (await NesMediaCatalogue.load(modelsDirectory: root))!;
    final box =
        (await catalogue.editions.values.first.load(modelsDirectory: root))!;
    final media =
        NesUnboxingScene(box, 'nintendo-3-gray', modelsDirectory: root);
    final m = await media.load();
    for (final size in sizes) {
      for (var step = 0; step <= 20; step++) {
        _reserved(
            _pixels(m, SocketMediaPose(unboxing: step / 20, rx: .12, ry: -.12),
                size),
            size);
      }
    }
    if (launch == null) return;
    final console = (await ConsoleModel.findNesLaunchTarget('front-loader',
        modelsDirectory: Directory(launch)))!;
    final display = (await ConsoleModel.findNesLaunchDisplay(
        modelsDirectory: Directory(launch)))!;
    final scene = await NesLaunchScene(media, console, display).load();
    const start = SocketMediaPose(unboxing: 1, rx: .12, ry: -.12);
    for (final size in sizes) {
      final before = _pixels(m, start, size);
      final after = _pixels(scene, start, size);
      expect(after.left, closeTo(before.left, .001));
      expect(after.top, closeTo(before.top, .001));
      expect(after.width, closeTo(before.width, .001));
      for (final progress in [.3, .6, .82]) {
        _reserved(
            _pixels(
                scene,
                SocketMediaPose(
                    unboxing: 1, launch: progress, rx: .12, ry: -.12),
                size),
            size);
      }
      final screen = _pixels(
          scene, const SocketMediaPose(unboxing: 1, launch: 1), size,
          node: 'SonyCrtScreen');
      expect(screen.width, greaterThan(size.width));
      expect(screen.height, greaterThan(size.height),
          reason:
              'Deliberate final screen zoom is separate from default framing');
    }
  }, skip: nes == null ? 'Private owner imports are not bundled' : false);
}
