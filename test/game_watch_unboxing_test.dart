import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/console_model.dart';
import 'package:retro_eshop/models/game_watch_unboxing_scene.dart';
import 'package:retro_eshop/models/socket_media_model.dart';
import 'package:retro_eshop/widgets/socket_media_renderer.dart';
import 'package:retro_eshop/features/preview/console_hardware_view.dart';
import 'package:retro_eshop/features/preview/game_watch_variants_preview.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

List<vm.Vector3> vertices(
    SocketMediaModel model, String part, SocketMediaPose pose) {
  final result = <vm.Vector3>[];
  for (final surface
      in model.surfaces.where((s) => s['hardwarePart'] == part)) {
    final transform = GameWatchUnboxingScene.partTransform(model, part, pose) *
        SocketMediaGpu.openingTransform(
            surface, SocketMediaGpu.surfaceOpening(model, surface, pose));
    for (var i = 0; i < surface['vertexCount']; i++) {
      final o = (surface['vertexOffset'] as int) + i * 32;
      result.add(transform.transform3(vm.Vector3(
          model.mesh.getFloat32(o, Endian.little),
          model.mesh.getFloat32(o + 4, Endian.little),
          model.mesh.getFloat32(o + 8, Endian.little))));
    }
  }
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['RSHOP_GAMEWATCH_MODEL_DIR'];
  final absent = path == null ? 'Private imports are not bundled' : false;
  test(
      'eight real pairs preserve source meshes/textures and clear before unfolding',
      () async {
    final root = Directory(path!);
    for (final set in ConsoleModel.gameWatchBoxSets) {
      final variants = await ConsoleModel.findGameWatchVariants('$set.zip',
          modelsDirectory: root);
      final variant = variants.single;
      expect(variant.box!.hardwareId, set);
      final scene = GameWatchUnboxingScene(variant.model, variant.box!);
      final model = await scene.load();
      final console = await variant.model.load(),
          box = await variant.box!.load();
      expect(model.mesh.lengthInBytes,
          console.mesh.lengthInBytes + box.mesh.lengthInBytes);
      expect(
          model.mesh.buffer.asUint8List(0, console.mesh.lengthInBytes),
          console.mesh.buffer.asUint8List(
              console.mesh.offsetInBytes, console.mesh.lengthInBytes));
      for (final surface in model.surfaces) {
        for (final texture in (surface['material']['textures'] as Map).values) {
          expect(
              (await model.textureBundle!
                      .load('${SocketMediaModel.assetRoot}$texture'))
                  .lengthInBytes,
              greaterThan(0));
        }
      }
      final seated = vertices(model, 'console', const SocketMediaPose());
      final carton = vertices(model, 'box', const SocketMediaPose());
      for (var axis = 0; axis < 3; axis++) {
        expect(seated.map((v) => v[axis]).reduce(math.min),
            greaterThan(carton.map((v) => v[axis]).reduce(math.min)),
            reason: '$set seat axis $axis');
        expect(seated.map((v) => v[axis]).reduce(math.max),
            lessThan(carton.map((v) => v[axis]).reduce(math.max)));
      }
      final clearT = (variant.box!.openingDurationMs + 1200) / scene.durationMs;
      final clearPose = SocketMediaPose(
          unboxing: clearT, opening: scene.handheldOpening(clearT));
      expect(clearPose.opening, 0, reason: 'Folded until completely outside');
      expect(
          vertices(model, 'console', clearPose)
              .map((v) => v.x)
              .reduce(math.min),
          greaterThan(vertices(model, 'box', clearPose)
              .map((v) => v.x)
              .reduce(math.max)),
          reason: '$set right-hand exit');
      final finalPose =
          SocketMediaPose(unboxing: 1, opening: variant.model.canOpen ? 1 : 0);
      final finalConsole = vertices(model, 'console', finalPose);
      final finalBox = vertices(model, 'box', finalPose);
      expect(
          finalConsole.map((v) => v.y).reduce(math.min), closeTo(-.65, .00001));
      expect(finalBox.map((v) => v.y).reduce(math.min), closeTo(-.65, .00001));
      expect(finalConsole.map((v) => v.z).reduce(math.min),
          greaterThan(finalBox.map((v) => v.z).reduce(math.max)),
          reason: '$set console rests in front');
      for (final opening in [0.0, .25, .5, .75, 1.0]) {
        expect(
            vertices(model, 'console',
                    SocketMediaPose(unboxing: 1, opening: opening))
                .map((v) => v.y)
                .reduce(math.min),
            closeTo(-.65, .003),
            reason: '$set independently folded console stays seated');
      }
      // Every animated vertex, not just a nominal model rectangle, must fit
      // the actual Thor lower canvas and a three-edition cell.
      for (final size in [
        const Size(537.67, 331.27),
        const Size(171.22, 258.39)
      ]) {
        for (var step = 0; step <= 30; step++) {
          final t = step / 30;
          final pose = SocketMediaPose(
              unboxing: t,
              opening: scene.handheldOpening(t),
              rx: .18,
              ry: -.2,
              scaleX: .9,
              scaleY: .9,
              scaleZ: .9);
          final projection = SocketMediaGpu.cameraProjection(
                  size.width,
                  size.height,
                  SocketMediaGpu.fittedUnits(model, size, pose: pose)) *
              SocketMediaGpu.modelTransform(model, pose);
          for (final part in ['box', 'console']) {
            for (final vertex in vertices(model, part, pose)) {
              final v = projection
                  .transform(vm.Vector4(vertex.x, vertex.y, vertex.z, 1));
              expect(v.x / v.w, inInclusiveRange(-1.0, 1.0),
                  reason: '$set $part x step $step size $size');
              expect(v.y / v.w, inInclusiveRange(-1.0, 1.0),
                  reason: '$set $part y step $step');
            }
          }
        }
      }
    }
  }, skip: absent);

  test('missing boxes remain absent and never borrow another edition',
      () async {
    final root = Directory(path!);
    for (final set in ['gnw_dkjr', 'gnw_zelda', 'gnw_smbn']) {
      final variants = await ConsoleModel.findGameWatchVariants('$set.zip',
          modelsDirectory: root);
      expect(variants.every((v) => v.box == null), isTrue);
    }
    final dk = await ConsoleModel.findGameWatchVariants('gnw_dkong.zip',
        modelsDirectory: root);
    final other = await ConsoleModel.findGameWatchVariants('gnw_dkong2.zip',
        modelsDirectory: root);
    await expectLater(
        GameWatchUnboxingScene(dk.single.model, other.single.box!).load(),
        throwsFormatException);
  }, skip: absent);

  testWidgets(
      'one sequence owns readiness, ordered editions, pause, inspect and replacement',
      (tester) async {
    final models = (await tester.runAsync(() async {
      // Scheduler verification with two independently imported real pairs;
      // this test does not add a false same-game group to the private catalogue.
      final a = await ConsoleModel.findGameWatchVariants('gnw_dkong.zip',
          modelsDirectory: Directory(path!));
      final b = await ConsoleModel.findGameWatchVariants('gnw_mario.zip',
          modelsDirectory: Directory(path));
      return [a.single, b.single];
    }))!;
    final key = GlobalKey<GameWatchVariantsViewState>();
    var reduced = false;
    late StateSetter redraw;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: StatefulBuilder(builder: (_, update) {
      redraw = update;
      return GameWatchVariantsView(
          key: key, variants: models, reducedMotion: reduced);
    }))));
    final views = tester
        .widgetList<ConsoleHardwareView>(find.byType(ConsoleHardwareView))
        .toList();
    expect(key.currentState!.snapshot['sequenceRunning'], isFalse);
    views.first.onReady!();
    await tester.pump(const Duration(seconds: 1));
    expect(key.currentState!.snapshot['sequenceProgress'], [0.0, 0.0]);
    views.last.onReady!();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    var progress = key.currentState!.snapshot['sequenceProgress'] as List;
    expect(progress.first, greaterThan(0));
    expect(progress.last, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 2));
    expect(key.currentState!.snapshot['sequenceProgress'], progress);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    progress = key.currentState!.snapshot['sequenceProgress'] as List;
    expect(progress.first, 1);
    expect(progress.last, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('gamewatch-inspect-1')));
    await tester.pump();
    expect(key.currentState!.snapshot['sequenceSettled'], isTrue);
    expect(key.currentState!.snapshot['inspectedIndex'], 1);
    expect(
        tester
            .widgetList<ConsoleHardwareView>(find.byType(ConsoleHardwareView))
            .single
            .inspecting,
        isTrue);
    redraw(() => reduced = true);
    await tester.pump();
    expect(key.currentState!.snapshot['sequenceRunning'], isFalse);
    await tester.pumpWidget(MaterialApp(
        home: GameWatchVariantsView(
            key: key, variants: models.reversed.toList())));
    views.first.onReady!();
    views.last.onReady!();
    expect(key.currentState!.snapshot['frameRendered'], isFalse,
        reason: 'Old generation cannot start replacement');
    expect(key.currentState!.snapshot['sequenceProgress'], [0.0, 0.0]);
    await tester.pumpWidget(MaterialApp(
        home: GameWatchVariantsView(
            key: key,
            variants: models.reversed.toList(),
            reducedMotion: true)));
    expect(key.currentState!.snapshot['sequenceProgress'], [1.0, 1.0]);
    expect(key.currentState!.snapshot['sequenceRunning'], isFalse);
    await tester.pumpWidget(const SizedBox());
  }, skip: path == null);
}
