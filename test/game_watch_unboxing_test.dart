import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/console_model.dart';
import 'package:g_shop/models/game_watch_unboxing_scene.dart';
import 'package:g_shop/models/socket_media_model.dart';
import 'package:g_shop/widgets/socket_media_renderer.dart';
import 'package:g_shop/features/preview/console_hardware_view.dart';
import 'package:g_shop/features/preview/game_watch_variants_preview.dart';
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
  test('Diskun case opens at the front and releases its exact special handheld',
      () async {
    final root = Directory(path!);
    final editions = await ConsoleModel.findGameWatchVariants('gnw_smbn.zip',
        modelsDirectory: root);
    final special = editions.singleWhere(
        (v) => v.model.visualVariantId == 'super-mario-bros-special');
    final source = await special.box!.load();
    expect(source.data['containerType'], 'protectiveCase');
    expect(source.data['textureFiles'], isEmpty,
        reason: 'Source eyes and plastic are geometry and solid materials');
    final scene = GameWatchUnboxingScene(special.model, special.box!);
    final model = await scene.load();
    expect(model.data['extractionAxis'], [0.0, 0.0, 1.0]);
    final t = (special.box!.openingDurationMs + 1200) / scene.durationMs;
    final pose = SocketMediaPose(unboxing: t, opening: 0);
    final rear =
        vertices(model, 'console', pose).map((v) => v.z).reduce(math.min);
    final front = vertices(model, 'box', pose).map((v) => v.z).reduce(math.max);
    expect(rear, greaterThan(front),
        reason: 'The handheld clears the open front before settling');
    expect(special.model.romSet, isNull);
    expect(editions.first.model.romSet, 'gnw_smbn');
  }, skip: absent);
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
      // The renderer reads this complete metadata contract after GPU loading;
      // geometry-only validation previously missed the absent label dimensions.
      expect(model.labelAspect, 1);
      expect(model.frontSign, 1);
      expect(model.motionKind, 'hardware');
      expect(model.triangles, greaterThan(0));
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
      expect(model.data['extractionAxis'], [-1.0, 0.0, 0.0],
          reason: 'All eight supplied cartons open on their actual left end');
      final leftWall =
          vertices(model, 'box', clearPose).map((v) => v.x).reduce(math.min);
      for (final part in ['console', 'insert']) {
        expect(
            vertices(model, part, clearPose).map((v) => v.x).reduce(math.max),
            lessThan(leftWall),
            reason: '$set $part clears its open left end');
      }
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
          for (final part in ['box', 'console', 'insert']) {
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
  }, skip: absent, timeout: Timeout.none);

  test(
      'all scan cartons integrate exact editions, real openings and Thor framing',
      () async {
    final root = Directory(path!);
    final catalogue = <String, GameWatchModelVariant>{};
    for (final set in ConsoleModel.gameWatchSets) {
      for (final variant in await ConsoleModel.findGameWatchVariants('$set.zip',
          modelsDirectory: root)) {
        if (variant.box != null) catalogue[variant.model.hardwareId] = variant;
      }
    }
    expect(catalogue.length, 61,
        reason: 'Eight supplied cartons, 52 scan cartons and the Diskun case');
    for (final variant in catalogue.values) {
      final key = variant.model.hardwareId;
      final scene = GameWatchUnboxingScene(variant.model, variant.box!);
      final model = await scene.load();
      expect(variant.box!.hardwareId, key);
      final cavity = (model.data['seatingBounds'] as List).cast<List>();
      final seated = vertices(model, 'console', const SocketMediaPose());
      for (var a = 0; a < 3; a++) {
        expect(
            seated.map((p) => p[a]).reduce(math.min), greaterThan(cavity[0][a]),
            reason: '$key fits its real cavity');
        expect(seated.map((p) => p[a]).reduce(math.max), lessThan(cavity[1][a]),
            reason: '$key fits its real cavity');
      }
      final clearT = (variant.box!.openingDurationMs + 1200) / scene.durationMs;
      final clearPose = SocketMediaPose(
          unboxing: clearT, opening: scene.handheldOpening(clearT));
      final axis = (model.data['extractionAxis'] as List).cast<num>();
      final a = axis.indexWhere((v) => v != 0);
      final positive = axis[a] > 0;
      final wall = vertices(model, 'box', clearPose)
          .map((v) => v[a])
          .reduce(positive ? math.max : math.min);
      final console = vertices(model, 'console', clearPose)
          .map((v) => v[a])
          .reduce(positive ? math.min : math.max);
      expect(positive ? console > wall : console < wall, isTrue,
          reason: '$key clears its reviewed opening before unfolding');
      final restPose =
          SocketMediaPose(unboxing: 1, opening: variant.model.canOpen ? 1 : 0);
      expect(
          vertices(model, 'console', restPose).map((v) => v.y).reduce(math.min),
          closeTo(-.65, .003),
          reason: '$key rests on the shared plane');
      expect(
          vertices(model, 'console', restPose).map((v) => v.z).reduce(math.min),
          greaterThan(vertices(model, 'box', restPose)
              .map((v) => v.z)
              .reduce(math.max)),
          reason: '$key rests in front of its box without overlap');
      for (final size in [
        const Size(537.67, 331.27),
        const Size(171.22, 258.39)
      ]) {
        for (var step = 0; step <= 20; step++) {
          final t = step / 20;
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
          for (final part in ['box', 'console', 'insert']) {
            var maxX = 0.0, maxY = 0.0;
            for (final p in vertices(model, part, pose)) {
              final v = projection.transform(vm.Vector4(p.x, p.y, p.z, 1));
              maxX = math.max(maxX, (v.x / v.w).abs());
              maxY = math.max(maxY, (v.y / v.w).abs());
            }
            expect(maxX, lessThanOrEqualTo(1.0),
                reason: '$key $part x step $step $size');
            expect(maxY, lessThanOrEqualTo(1.0),
                reason: '$key $part y step $step $size');
          }
        }
      }
      final original = await variant.box!.load();
      for (final file
          in (original.data['textureFiles'] as Map).keys.cast<String>()) {
        expect(
            (await model.textureBundle!
                    .load('${SocketMediaModel.assetRoot}box/$file'))
                .lengthInBytes,
            greaterThan(0));
      }
    }
  }, skip: absent, timeout: Timeout.none);

  test('missing boxes remain absent and never borrow another edition',
      () async {
    final root = Directory(path!);
    final smb = await ConsoleModel.findGameWatchVariants('gnw_smbn.zip',
        modelsDirectory: root);
    expect(smb.first.box!.hardwareId, 'gnw_smbn');
    expect(
        (await smb
                .singleWhere((v) =>
                    v.model.visualVariantId == 'super-mario-bros-special')
                .box!
                .load())
            .data['containerType'],
        'protectiveCase');
    final shared = await ConsoleModel.findGameWatch('gnw_helmet.zip',
        modelsDirectory: root, box: true);
    expect(shared!.romSet, 'gnw_helmet');
    expect(shared.hardwareId, 'gnw_helmeto',
        reason:
            'MCU revision has shared Helmet-family packaging, not a new box');
    final shelf = await ConsoleModel.findGameWatchLibrary('gnw_smbn.zip',
        modelsDirectory: root);
    expect(shelf!.isBox, isTrue);
    expect(shelf.hardwareId, 'gnw_smbn');
    final unboxed = await ConsoleModel.findGameWatchLibrary('auslalom.zip',
        modelsDirectory: root);
    expect(unboxed!.isBox, isFalse);
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
