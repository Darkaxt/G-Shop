import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/nes_cartridge_model.dart';
import 'package:g_shop/models/nes_media_catalogue.dart';
import 'package:g_shop/models/nes_unboxing_scene.dart';
import 'package:g_shop/models/socket_media_model.dart';
import 'package:g_shop/widgets/physical_media_view.dart';
import 'package:g_shop/widgets/socket_media_renderer.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

List<vm.Vector3> vertices(SocketMediaModel m, String part, SocketMediaPose p) {
  final result = <vm.Vector3>[];
  for (final s in m.surfaces.where((s) => s['nesPart'] == part)) {
    final t = NesUnboxingScene.partTransform(m, part, p) *
        SocketMediaGpu.openingTransform(
            s, SocketMediaGpu.surfaceOpening(m, s, p));
    for (var i = 0; i < s['vertexCount']; i++) {
      final o = (s['vertexOffset'] as int) + i * 32;
      result.add(t.transformed3(vm.Vector3(
          m.mesh.getFloat32(o, Endian.little),
          m.mesh.getFloat32(o + 4, Endian.little),
          m.mesh.getFloat32(o + 8, Endian.little))));
    }
  }
  return result;
}

double edge(List<vm.Vector3> points, int axis, bool high) =>
    points.map((v) => v[axis]).reduce(high ? math.max : math.min);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['GSHOP_NES_IMPORTS'];
  final absent = path == null ? 'Private owner imports are not bundled' : false;
  Future<NesUnboxingScene> scene(String style) async {
    final root = Directory(path!);
    final catalogue = (await NesMediaCatalogue.load(modelsDirectory: root))!;
    final box =
        (await catalogue.editions.values.first.load(modelsDirectory: root))!;
    return NesUnboxingScene(box, style, modelsDirectory: root);
  }

  test('dust sleeves apply to standard Nintendo shells, not unrelated shapes',
      () {
    for (final style in [
      'nintendo-3-gray',
      'nintendo-5-gray',
      'nintendo-3-gold',
      'nintendo-5-gold',
      'nintendo-3-white'
    ]) {
      expect(NesUnboxingScene.usesSleeve(style), isTrue);
    }
    for (final style in [
      'tengen',
      'active-clear',
      'aladdin',
      'famicom-gold',
      'pcb-nrom-256'
    ]) {
      expect(NesUnboxingScene.usesSleeve(style), isFalse);
    }
  });
  test(
      'real shells seat, clear opened flaps, leave the sleeve and frame all parts',
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
      final selected = await scene(style), m = await selected.load();
      final box = vertices(m, 'box', const SocketMediaPose());
      final cart = vertices(m, 'cartridge', const SocketMediaPose());
      final contents = [
        ...cart,
        if (selected.hasSleeve)
          ...vertices(m, 'sleeve', const SocketMediaPose())
      ];
      for (var a = 0; a < 3; a++) {
        expect(edge(contents, a, false), greaterThan(edge(box, a, false)),
            reason: '$style seated minimum $a');
        expect(edge(contents, a, true), lessThan(edge(box, a, true)),
            reason: '$style seated maximum $a');
      }
      final opened = selected.box.openingDurationMs / 1000;
      SocketMediaPose at(double seconds) =>
          SocketMediaPose(unboxing: seconds * 1000 / selected.durationMs);
      expect(
          NesUnboxingScene.boxOpening(m, opened * 1000 / selected.durationMs),
          1);
      final released = at(opened + 1.2);
      expect(edge(vertices(m, 'cartridge', released), 1, false),
          greaterThan(edge(vertices(m, 'box', released), 1, true)),
          reason: '$style clears the opened top first');
      if (selected.hasSleeve) {
        final free = at(opened + 3.1);
        expect(edge(vertices(m, 'cartridge', free), 1, false),
            greaterThan(edge(vertices(m, 'sleeve', free), 1, true)),
            reason: 'Cartridge leaves the sleeve through its top');
      }
      const end = SocketMediaPose(unboxing: 1);
      expect(edge(vertices(m, 'cartridge', end), 2, false),
          greaterThan(edge(vertices(m, 'box', end), 2, true)),
          reason: 'Cartridge rests in front of the carton');
      expect(
          m.surfaces
              .any((s) => s['nesPart'] == 'cartridge' && s['role'] == 'label'),
          isTrue);
      final original = (await NesCartridgeModel.load(style,
          modelsDirectory: Directory(path!)))!;
      expect(m.labelAspect, original.labelAspect);
      for (final s in m.surfaces) {
        for (final name
            in (s['material']['textures'] as Map).values.cast<String>()) {
          expect(
              (await m.textureBundle!
                      .load('${SocketMediaModel.assetRoot}$name'))
                  .lengthInBytes,
              greaterThan(0));
        }
      }
      for (final progress in [0.0, .2, .4, .6, .8, 1.0]) {
        final pose = SocketMediaPose(unboxing: progress, rx: .12, ry: -.12);
        const size = Size(1240, 610);
        final projection = SocketMediaGpu.cameraProjection(size.width,
            size.height, SocketMediaGpu.fittedUnits(m, size, pose: pose));
        final transform = projection * SocketMediaGpu.modelTransform(m, pose);
        for (final part in [
          'box',
          'cartridge',
          if (selected.hasSleeve) 'sleeve'
        ]) {
          for (final v in vertices(m, part, pose)) {
            final clip = transform.transformed(vm.Vector4(v.x, v.y, v.z, 1));
            expect(clip.w, greaterThan(0));
            expect((clip.x / clip.w).abs(), lessThanOrEqualTo(.99),
                reason: '$style $part x at $progress');
            expect((clip.y / clip.w).abs(), lessThanOrEqualTo(.99),
                reason: '$style $part y at $progress');
          }
        }
      }
    }
  }, skip: absent);
  testWidgets(
      'NES sequence waits for resources/GPU and preserves lifecycle and launch ownership',
      (tester) async {
    final selected = (await tester.runAsync(() => scene('nintendo-3-gray')))!;
    final key = GlobalKey<PhysicalMediaViewState>();
    Widget view({bool resources = false, bool reduced = false}) => MaterialApp(
        home: PhysicalMediaView(
            key: key,
            identity: 'nes-sequence',
            title: 'Game',
            format: PhysicalMediaFormat.nes,
            cartridgeStyle: 'nintendo-3-gray',
            nesScene: selected,
            resourcesReady: resources,
            reducedMotion: reduced,
            label: const Text('Personalized label')));
    await tester.pumpWidget(view());
    tester
        .widget<SocketMediaRenderer>(find.byType(SocketMediaRenderer))
        .onReady!();
    await tester.pump(const Duration(seconds: 2));
    expect(key.currentState!.pose.unboxing, 0,
        reason: 'Resources have not resolved');
    await tester.pumpWidget(view(resources: true));
    await tester.pump(const Duration(seconds: 2));
    final halfway = key.currentState!.pose.unboxing;
    expect(halfway, greaterThan(0));
    expect(halfway, lessThan(1));
    key.currentState!.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 10));
    expect(key.currentState!.pose.unboxing, halfway);
    key.currentState!.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(Duration(milliseconds: selected.durationMs));
    expect(key.currentState!.pose.unboxing, 1);
    key.currentState!.replayUnboxing();
    expect(key.currentState!.pose.unboxing, 0);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(key.currentState!.pose.unboxing, greaterThan(0));
    expect(key.currentState!.pose.unboxing, lessThan(1));
    await tester.pumpWidget(view(resources: true, reduced: true));
    key.currentState!.replayUnboxing();
    expect(key.currentState!.pose.unboxing, 1,
        reason: 'Reduced Motion settles immediately');
    await tester.pumpWidget(view(resources: true));
    final launch = key.currentState!.playInsertion();
    expect(key.currentState!.pose.inspectedPart, 'cartridge');
    key.currentState!.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(await launch, isFalse,
        reason: 'Backgrounding cancels the existing launch animation');
    await tester.pumpWidget(const SizedBox());
  }, skip: path == null);
  test('all prepared cartons support extraction through the actual opening',
      () async {
    final root = Directory(path!);
    final catalogue = (await NesMediaCatalogue.load(modelsDirectory: root))!;
    for (final edition in catalogue.editions.values) {
      final box = (await edition.load(modelsDirectory: root))!;
      final selected =
          NesUnboxingScene(box, 'nintendo-3-gray', modelsDirectory: root);
      final model = await selected.load();
      expect(model.data['seatScale'], greaterThan(0), reason: edition.id);
      final progress = (box.openingDurationMs + 1200) / selected.durationMs;
      final pose = SocketMediaPose(unboxing: progress);
      final axis = (model.data['exitAxis'] as List).cast<int>();
      final contents = vertices(model, 'cartridge', pose),
          carton = vertices(model, 'box', pose);
      final near = edge(contents, axis[0], axis[1] < 0),
          far = edge(carton, axis[0], axis[1] > 0);
      expect(axis[1] * (near - far), greaterThan(0), reason: edition.id);
    }
  }, skip: absent, timeout: Timeout.none);
}
