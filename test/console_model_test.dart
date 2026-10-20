import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:retro_eshop/models/console_model.dart';
import 'package:retro_eshop/models/packaging_model.dart';
import 'package:retro_eshop/models/socket_media_model.dart';
import 'package:retro_eshop/features/preview/console_hardware_view.dart';
import 'package:retro_eshop/widgets/socket_media_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root =
      Directory('${Directory.systemTemp.path}/rshop-console-model-test');
  late Map<String, dynamic> data;
  setUp(() async {
    final dir = Directory('${root.path}/consoles/gba');
    await dir.create(recursive: true);
    final base = PackagingModel(PackagingKind.keepCase).build();
    data = Map<String, dynamic>.from(base.data)
      ..remove('ownedGeometry')
      ..addAll({
        'name': 'console-gba-v1',
        'system': 'gba',
        'hardwareGeometry': true,
        'privateImport': true,
        'motionKind': 'hardware',
        'textureFiles': {
          'screen.png': sha256.convert([1, 2, 3]).toString()
        },
        'sourceReference': {
          'author': 'Fixture',
          'url': 'local:fixture',
          'licence': 'local-import-only',
          'sha256': 'b' * 64
        }
      });
    await File('${dir.path}/model.json').writeAsString(jsonEncode(data));
    await File('${dir.path}/model.mesh')
        .writeAsBytes(base.mesh.buffer.asUint8List());
    await File('${dir.path}/screen.png').writeAsBytes([1, 2, 3]);
  });
  test('local scene validates provenance and independent texture checksums',
      () async {
    final model = (await ConsoleModel.find('gba', modelsDirectory: root))!;
    final geometry = await model.load();
    expect(geometry.data['hardwareGeometry'], true);
    expect(geometry.textureBundle, isNotNull);
    expect(SocketMediaModel.importedBundle, isNull);
    expect(
        (await geometry.textureBundle!
                .load('${SocketMediaModel.assetRoot}screen.png'))
            .lengthInBytes,
        3);
    await File('${model.directory.path}/screen.png').writeAsBytes([3, 2, 1]);
    await expectLater(
        geometry.textureBundle!.load('${SocketMediaModel.assetRoot}screen.png'),
        throwsFormatException);
    expect(await ConsoleModel.find('gb', modelsDirectory: root), isNull);
    await expectLater(ConsoleModel.find('../gba', modelsDirectory: root),
        throwsFormatException);
    await File('${model.directory.path}/model.json')
        .writeAsString(jsonEncode({...data, 'name': 'replacement'}));
    await expectLater(model.load(), throwsFormatException);
    final replacement =
        (await ConsoleModel.find('gba', modelsDirectory: root))!;
    expect(replacement.generation, isNot(model.generation));
    expect((await replacement.load()).name, 'replacement');
  });
  test(
      'solid-colour imports need no artificial texture and reject missing maps',
      () async {
    data['textureFiles'] = <String, String>{};
    for (final surface in data['surfaces'] as List) {
      surface['material']['textures'] = <String, String>{};
    }
    final manifest = File('${root.path}/consoles/gba/model.json');
    await manifest.writeAsString(jsonEncode(data));
    final model = (await ConsoleModel.find('gba', modelsDirectory: root))!;
    expect((await model.load()).data['textureFiles'], isEmpty);
    data['surfaces'][0]['material']['textures'] = {'albedo': 'missing.png'};
    await manifest.writeAsString(jsonEncode(data));
    final invalid = (await ConsoleModel.find('gba', modelsDirectory: root))!;
    await expectLater(invalid.load(), throwsFormatException);
  });
  test('console turntable keeps the original upright axis fixed', () async {
    final geometry =
        await (await ConsoleModel.find('gba', modelsDirectory: root))!.load();
    final a =
        SocketMediaGpu.modelTransform(geometry, const SocketMediaPose(rx: .75));
    final b = SocketMediaGpu.modelTransform(
        geometry, const SocketMediaPose(rx: .75, ry: 2));
    final up = vm.Vector3(0, 1, 0);
    expect(a.transform3(up.clone()).distanceTo(b.transform3(up.clone())),
        lessThan(1e-6));
  });
  test('collection overview has a scoped budget without widening handhelds',
      () async {
    final dir = Directory('${root.path}/consoles/gameandwatch');
    await dir.create(recursive: true);
    await File('${root.path}/consoles/gba/model.mesh')
        .copy('${dir.path}/model.mesh');
    final manifest = File('${dir.path}/model.json');
    data['system'] = 'gameandwatch';
    data['selectorScene'] = {
      'kind': 'gamewatchCollection',
      'deviceCount': 63,
      'devices': List.generate(63, (i) => 'device-$i'),
      'hiddenNodes': ['Display_board'],
      'textureMaxDimension': 256,
    };
    data['surfaces'] = List.generate(140, (_) => data['surfaces'][0]);
    await manifest.writeAsString(jsonEncode(data));
    final scene =
        (await ConsoleModel.find('gameandwatch', modelsDirectory: root))!;
    expect((await scene.load()).surfaces.length, 140);
    data.remove('selectorScene');
    await manifest.writeAsString(jsonEncode(data));
    final ordinary =
        (await ConsoleModel.find('gameandwatch', modelsDirectory: root))!;
    await expectLater(ordinary.load(), throwsFormatException);
    data['selectorScene'] = {'kind': 'gamewatchCollection', 'deviceCount': 1};
    await manifest.writeAsString(jsonEncode(data));
    final invalid =
        (await ConsoleModel.find('gameandwatch', modelsDirectory: root))!;
    await expectLater(invalid.load(), throwsFormatException);
  });
  test(
      'folding turntable rotates around the visible pose, not its swept envelope',
      () async {
    final dir = Directory('${root.path}/consoles/gba');
    await File('${dir.path}/model.json').writeAsString(jsonEncode({
      ...data,
      'poseCenters': [
        [0, .5, .2, -.1],
        [1, 0, -.2, -.5]
      ]
    }));
    final geometry =
        await (await ConsoleModel.find('gba', modelsDirectory: root))!.load();
    for (final opening in [0.0, .5, 1.0]) {
      final center =
          vm.Vector3(.5 * (1 - opening), .2 - .4 * opening, -.1 - .4 * opening);
      for (final yaw in [-3.0, -1.0, 0.0, 1.0, 3.0]) {
        final matrix = SocketMediaGpu.modelTransform(
            geometry, SocketMediaPose(rx: .18, ry: yaw, opening: opening));
        expect(matrix.transform3(center.clone()).length, lessThan(1e-6),
            reason:
                'Visible centre must remain fixed through yaw at opening=$opening');
      }
    }
  });
  testWidgets('collection camera views the original layout from above',
      (tester) async {
    final model = await tester.runAsync(() async {
      final dir = Directory('${root.path}/consoles/gameandwatch');
      await dir.create(recursive: true);
      await File('${root.path}/consoles/gba/model.mesh')
          .copy('${dir.path}/model.mesh');
      data['system'] = 'gameandwatch';
      data['selectorScene'] = {
        'kind': 'gamewatchCollection',
        'deviceCount': 63,
        'devices': List.generate(63, (i) => 'device-$i'),
        'hiddenNodes': ['Display_board'],
        'textureMaxDimension': 256,
      };
      await File('${dir.path}/model.json').writeAsString(jsonEncode(data));
      return ConsoleModel.find('gameandwatch', modelsDirectory: root);
    });
    await tester.pumpWidget(MaterialApp(
        home: ConsoleHardwareView(model: model!, title: 'Game & Watch')));
    expect(
        tester
            .widget<SocketMediaRenderer>(find.byType(SocketMediaRenderer))
            .pose
            .rx,
        .85);
    await tester.pumpWidget(const SizedBox());
  });
  test('expanded handheld imports retain exact hardware editions', () {
    const releases = {
      'Black Jack (World).7z': 'gnw_bjack',
      'Bomb Sweeper (World).7z': 'gnw_bsweep',
      'Boxing (World).7z': 'gnw_boxing',
      'Gold Cliff (World).7z': 'gnw_gcliff',
      'Green House (World).7z': 'gnw_ghouse',
      'Lifeboat (World).7z': 'gnw_lboat',
      'Mickey & Donald (World).7z': 'gnw_mickdon',
      'Oil Panic (World).7z': 'gnw_opanic',
      'Pinball (World).7z': 'gnw_pinball',
      'Rain Shower (World).7z': 'gnw_rshower',
      'Safe Buster (World).7z': 'gnw_sbuster',
      'Snoopy (World).7z': 'gnw_snoopyp',
      'Spitball Sparky (World).7z': 'gnw_ssparky',
      'Squish (World).7z': 'gnw_squish',
    };
    for (final entry in releases.entries) {
      expect(ConsoleModel.gameWatchSet(entry.key), entry.value,
          reason: entry.key);
      expect(ConsoleModel.gameWatchSet('${entry.value}.zip'), entry.value);
    }
    expect(ConsoleModel.gameWatchSet('gnw_smb.zip'), 'gnw_smb');
    expect(
        ConsoleModel.gameWatchSet('Super Mario Bros. (World).7z'), 'gnw_smbn');
    expect(
        ConsoleModel.gameWatchSet('Snoopy Tennis (World).7z'), 'gnw_stennis');
    expect(ConsoleModel.gameWatchSet('gnw_dkjrp.zip'), 'gnw_dkjrp');
    expect(ConsoleModel.gameWatchSet('Fire (World) (Silver).7z'), 'gnw_fires');
  });
  test(
      'Helmet MCU revisions share an exterior while retaining exact ROM identity',
      () async {
    for (final kind in ['handhelds', 'boxes']) {
      final dir = Directory('${root.path}/$kind/gameandwatch/gnw_helmeto');
      await dir.create(recursive: true);
      final base = PackagingModel(PackagingKind.keepCase).build();
      await File('${dir.path}/model.json').writeAsString(jsonEncode({
        ...data,
        'system': 'gameandwatch',
        'romSet': 'gnw_helmeto',
        'resourceKind': kind == 'boxes' ? 'box' : 'handheld',
      }));
      await File('${dir.path}/model.mesh')
          .writeAsBytes(base.mesh.buffer.asUint8List());
      await File('${dir.path}/screen.png').writeAsBytes([1, 2, 3]);
    }
    final original = (await ConsoleModel.findGameWatch('Helmet (World).7z',
        modelsDirectory: root))!;
    final revised = (await ConsoleModel.findGameWatch(
        'Helmet (World) (Rev 1).7z',
        modelsDirectory: root))!;
    expect(original.romSet, 'gnw_helmeto');
    expect(revised.romSet, 'gnw_helmet');
    expect(revised.hardwareId, original.hardwareId);
    expect(revised.directory.path, original.directory.path);
    expect(revised.generation, original.generation);
    expect((await revised.load()).data['romSet'], 'gnw_helmet');
    expect((await revised.load()).data['physicalModelRomSet'], 'gnw_helmeto');
    expect((await original.load()).data['romSet'], 'gnw_helmeto');
    final variants = await ConsoleModel.findGameWatchVariants('gnw_helmet.zip',
        modelsDirectory: root);
    expect(variants, hasLength(1));
    expect(variants.single.model.romSet, 'gnw_helmet');
    expect(variants.single.box!.romSet, 'gnw_helmet');
    expect(variants.single.box!.hardwareId, 'gnw_helmeto');
    expect((await variants.single.box!.load()).data['physicalModelRomSet'],
        'gnw_helmeto');
  });
  test('handheld imports use exact MAME hardware sets, never title variants',
      () async {
    expect(ConsoleModel.gameWatchSet('gnw_dkong.zip'), 'gnw_dkong');
    expect(ConsoleModel.gameWatchSet('folder/gnw_smbn.zip'), 'gnw_smbn');
    expect(ConsoleModel.gameWatchSet('Donkey Kong (World).7z'), 'gnw_dkong');
    expect(
        ConsoleModel.gameWatchSet('Fire (World) (Wide Screen).7z'), 'gnw_fire');
    for (final wrong in [
      'Donkey Kong.zip',
      'gnw_dkong (USA).zip',
      'gnw_dkong.zip.exe',
    ]) {
      expect(ConsoleModel.gameWatchSet(wrong), isNull);
    }
    final dir = Directory('${root.path}/handhelds/gameandwatch/gnw_dkong');
    await dir.create(recursive: true);
    final base = PackagingModel(PackagingKind.keepCase).build();
    final handheld = {
      ...data,
      'system': 'gameandwatch',
      'romSet': 'gnw_dkong',
      'canOpen': true,
      'openingDurationMs': 2000
    };
    await File('${dir.path}/model.json').writeAsString(jsonEncode(handheld));
    await File('${dir.path}/model.mesh')
        .writeAsBytes(base.mesh.buffer.asUint8List());
    await File('${dir.path}/screen.png').writeAsBytes([1, 2, 3]);
    final model = (await ConsoleModel.findGameWatch('gnw_dkong.zip',
        modelsDirectory: root))!;
    expect(model.canOpen, true);
    expect((await model.load()).data['romSet'], 'gnw_dkong');
    expect(
        await ConsoleModel.findGameWatch('gnw_smb.zip', modelsDirectory: root),
        isNull);
    await File('${dir.path}/model.json')
        .writeAsString(jsonEncode({...handheld, 'romSet': 'gnw_zelda'}));
    final wrong = (await ConsoleModel.findGameWatch('gnw_dkong.zip',
        modelsDirectory: root))!;
    await expectLater(wrong.load(), throwsFormatException);
  });
  testWidgets(
      'folding handheld starts open and double tap drives its actual hinge pose',
      (tester) async {
    final dir = Directory('${root.path}/handhelds/gameandwatch/gnw_mario');
    await tester.runAsync(() async {
      await dir.create(recursive: true);
      await File('${dir.path}/model.json').writeAsString(jsonEncode({
        ...data,
        'system': 'gameandwatch',
        'romSet': 'gnw_mario',
        'canOpen': true,
        'openingDurationMs': 2000
      }));
    });
    final model = (await tester.runAsync(() =>
        ConsoleModel.findGameWatch('gnw_mario.zip', modelsDirectory: root)))!;
    final key = GlobalKey<ConsoleHardwareViewState>();
    await tester.pumpWidget(MaterialApp(
        home: ConsoleHardwareView(
            key: key,
            model: model,
            title: 'Mario Bros.',
            reducedMotion: true)));
    expect(key.currentState!.snapshot['opening'], 1);
    final surface = find.byKey(const ValueKey('console-model-gestures'));
    await tester.tap(surface);
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tap(surface);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(key.currentState!.snapshot['opening'], inExclusiveRange(0, 1));
    await tester.pump(const Duration(seconds: 1));
    expect(key.currentState!.snapshot['opening'], 0);
    expect(find.byType(IconButton), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  test('a box import cannot replace its handheld or another hardware set',
      () async {
    final dir = Directory('${root.path}/boxes/gameandwatch/gnw_ghouse');
    await dir.create(recursive: true);
    final base = PackagingModel(PackagingKind.keepCase).build();
    final box = {
      ...data,
      'system': 'gameandwatch',
      'romSet': 'gnw_ghouse',
      'resourceKind': 'box',
      'canOpen': true,
      'openingDurationMs': 2000
    };
    await File('${dir.path}/model.json').writeAsString(jsonEncode(box));
    await File('${dir.path}/model.mesh')
        .writeAsBytes(base.mesh.buffer.asUint8List());
    await File('${dir.path}/screen.png').writeAsBytes([1, 2, 3]);
    final model = (await ConsoleModel.findGameWatch('Green House (World).7z',
        box: true, modelsDirectory: root))!;
    expect(model.isBox, true);
    expect((await model.load()).data['resourceKind'], 'box');
    expect(
        await ConsoleModel.findGameWatch('Spitball Sparky (World).7z',
            box: true, modelsDirectory: root),
        isNull);
    await File('${dir.path}/model.json')
        .writeAsString(jsonEncode({...box, 'resourceKind': 'handheld'}));
    final wrong = (await ConsoleModel.findGameWatch('Green House (World).7z',
        box: true, modelsDirectory: root))!;
    await expectLater(wrong.load(), throwsFormatException);
  });
  test('independent emission maps do not replace the surface albedo', () {
    final material = <String, dynamic>{
      'color': [1, 1, 1, 1],
      'textures': {'albedo': 'paint.png', 'emission': 'lights.png'},
      'sourceProperties': {
        'emission': [1, .5, .25]
      }
    };
    expect(SocketMediaGpu.materialUniforms(material).sublist(20, 24),
        [1, .5, .25, 1]);
    material['textures'] = {'albedo': 'paint.png'};
    expect(SocketMediaGpu.materialUniforms(material).sublist(20, 24),
        [1, .5, .25, 0]);
  });
  testWidgets(
      'game hardware only wobbles while the selector keeps its turntable',
      (tester) async {
    final model = (await tester
        .runAsync(() => ConsoleModel.find('gba', modelsDirectory: root)))!;
    final key = GlobalKey<ConsoleHardwareViewState>();
    await tester.pumpWidget(MaterialApp(
        home: ConsoleHardwareView(
            key: key, model: model, title: 'Game handheld', turntable: false)));
    await tester.pump();
    final renderer = find.byType(SocketMediaRenderer);
    tester.widget<SocketMediaRenderer>(renderer).onReady!();
    await tester.pump();
    expect(key.currentState!.snapshot['motion'], 'wobble');
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<SocketMediaRenderer>(renderer).pose.ry,
          inInclusiveRange(-.340001, -.059999));
    }
    await tester.pumpWidget(const SizedBox());
  });
  final handhelds = Platform.environment['RSHOP_GAMEWATCH_MODEL_DIR'];
  test('all supplied boxes load exact art and articulated flap geometry',
      () async {
    for (final set in ConsoleModel.gameWatchBoxSets) {
      final model = (await ConsoleModel.findGameWatch('$set.zip',
          box: true, modelsDirectory: Directory(handhelds!)))!;
      final geometry = await model.load();
      expect(model.isBox, true, reason: set);
      expect(model.canOpen, true, reason: set);
      expect(geometry.data['romSet'], set);
      expect(geometry.data['resourceKind'], 'box');
      expect(geometry.data['animationVerifiedMaxError'], lessThan(.0001));
      expect(geometry.data['poseCenters'], isNotEmpty);
      expect(
          geometry.surfaces.any((s) => (s['openingHinges'] as List).isNotEmpty),
          true);
      expect(geometry.triangles, greaterThan(0));
      expect(geometry.textureBundle, isNotNull);
      for (final file in (geometry.data['textureFiles'] as Map).keys) {
        expect(
            (await geometry.textureBundle!
                    .load('${SocketMediaModel.assetRoot}$file'))
                .lengthInBytes,
            greaterThan(0),
            reason: '$set/$file');
      }
    }
  }, skip: handhelds == null ? 'Private source models not supplied' : false);
  test('all supplied mapped handhelds load exact geometry and texture receipts',
      () async {
    const folding = {
      // The refined Micro VS model now supplies its rear storage opening.
      'gnw_boxing',
      'gnw_dkong',
      'gnw_zelda',
      'gnw_dkong2',
      'gnw_mario',
      'gnw_bjack',
      'gnw_ghouse',
      'gnw_mickdon',
      'gnw_pinball',
      'gnw_bsweep',
      'gnw_gcliff',
      'gnw_lboat',
      'gnw_opanic',
      'gnw_rshower',
      'gnw_sbuster',
      'gnw_squish',
      'gnw_snoopyp',
      'gnw_popeyep',
      'gnw_dkjrp',
      'gnw_mbaway',
      'gnw_mmousep',
      'gnw_dkcirc',
    };
    for (final set in ConsoleModel.gameWatchSets) {
      final model = (await ConsoleModel.findGameWatch('$set.zip',
          modelsDirectory: Directory(handhelds!)))!;
      final geometry = await model.load();
      expect(model.canOpen, folding.contains(set), reason: set);
      expect(geometry.triangles, greaterThan(0), reason: set);
      expect(geometry.data['romSet'], set);
      expect(
          geometry.surfaces.any((s) => (s['openingHinges'] as List).isNotEmpty),
          folding.contains(set),
          reason: set);
      if (model.canOpen) {
        expect(geometry.data['animationVerifiedMaxError'], lessThan(.0001));
        expect(geometry.data['poseCenters'], isNotEmpty,
            reason:
                'Folding imports must provide visible-pose rotation centres');
        for (final opening in [0.0, .5, 1.0]) {
          final low = vm.Vector3.all(double.infinity);
          final high = vm.Vector3.all(double.negativeInfinity);
          for (final surface in geometry.surfaces) {
            final hinge = SocketMediaGpu.openingTransform(surface, opening);
            for (var i = 0; i < (surface['vertexCount'] as int); i++) {
              final offset = (surface['vertexOffset'] as int) + i * 32;
              final point = hinge.transform3(vm.Vector3(
                  geometry.mesh.getFloat32(offset, Endian.little),
                  geometry.mesh.getFloat32(offset + 4, Endian.little),
                  geometry.mesh.getFloat32(offset + 8, Endian.little)));
              for (var axis = 0; axis < 3; axis++) {
                if (point[axis] < low[axis]) low[axis] = point[axis];
                if (point[axis] > high[axis]) high[axis] = point[axis];
              }
            }
          }
          final center = (low + high) * .5;
          for (final yaw in [0.0, 1.5, 3.0]) {
            final matrix = SocketMediaGpu.modelTransform(
                geometry, SocketMediaPose(opening: opening, ry: yaw));
            expect(matrix.transform3(center.clone()).length, lessThan(.00001),
                reason: '$set must rotate in place at opening=$opening');
          }
        }
        for (final surface in geometry.surfaces) {
          for (final hinge in surface['openingHinges'] as List) {
            expect((hinge['keys'] as List).first[1], 0,
                reason: 'Frame-zero geometry must receive no hinge delta');
          }
        }
      }
      for (final file in (geometry.data['textureFiles'] as Map).keys) {
        expect(
            (await geometry.textureBundle!
                    .load('${SocketMediaModel.assetRoot}$file'))
                .lengthInBytes,
            greaterThan(0));
      }
    }
  },
      skip: handhelds == null
          ? 'Requires private supplied handheld imports'
          : false,
      timeout: Timeout.none);
  testWidgets(
      'console rotates only after a GPU frame and obeys reduced motion and lifecycle',
      (tester) async {
    final model = (await tester
        .runAsync(() => ConsoleModel.find('gba', modelsDirectory: root)))!;
    final key = GlobalKey<ConsoleHardwareViewState>();
    Widget view(bool reduced) => MaterialApp(
        home: Scaffold(
            body: ConsoleHardwareView(
                key: key, model: model, title: 'GBA', reducedMotion: reduced)));
    await tester.pumpWidget(view(false));
    await tester.pump();
    // Host Flutter has no Impeller. Simulate only its completed-frame callback;
    // real texture/GPU/visual acceptance is performed separately on Thor.
    final renderer = find.byType(SocketMediaRenderer);
    expect(renderer, findsOneWidget);
    expect(tester.widget<SocketMediaRenderer>(renderer).pose.rx,
        closeTo(.18, .001),
        reason: 'Use a near-level view, not the former steep overhead camera');
    expect(key.currentState!.snapshot['rotationRunning'], false);
    tester.widget<SocketMediaRenderer>(renderer).onReady!();
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(key.currentState!.snapshot['rotationRunning'], true);
    expect(tester.widget<SocketMediaRenderer>(renderer).pose.ry,
        closeTo(-.2 + 3.141592653589793 / 2, .001));
    expect(find.byType(IconButton), findsNothing);
    await tester.drag(find.byKey(const ValueKey('console-model-gestures')),
        const Offset(80, 10));
    await tester.pump();
    expect(key.currentState!.snapshot['rotationRunning'], false);
    final inspected = tester.widget<SocketMediaRenderer>(renderer).pose.ry;
    await tester.pump(const Duration(seconds: 4));
    expect(key.currentState!.snapshot['rotationRunning'], false);
    expect(tester.widget<SocketMediaRenderer>(renderer).pose.ry, inspected);
    await tester.pump(const Duration(seconds: 1));
    expect(key.currentState!.snapshot['rotationRunning'], true);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<SocketMediaRenderer>(renderer).pose.ry,
        greaterThan(inspected));
    final area =
        tester.getRect(find.byKey(const ValueKey('console-model-gestures')));
    final a = await tester.startGesture(area.center - const Offset(40, 0),
        pointer: 1);
    final b = await tester.startGesture(area.center + const Offset(40, 0),
        pointer: 2);
    await a.moveBy(const Offset(-40, 0));
    await b.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(tester.widget<SocketMediaRenderer>(renderer).pose.scaleX,
        greaterThan(.9));
    await a.up();
    await b.up();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(view(true));
    expect(key.currentState!.snapshot['rotationRunning'], false);
    final held = tester.widget<SocketMediaRenderer>(renderer).pose.ry;
    await tester.pump(const Duration(seconds: 8));
    expect(tester.widget<SocketMediaRenderer>(renderer).pose.ry, held);
    await tester.pumpWidget(view(false));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(key.currentState!.snapshot['rotationRunning'], false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(key.currentState!.snapshot['rotationRunning'], true);
    await tester.pumpWidget(const SizedBox());
  });
  final actual = Platform.environment['RSHOP_CONSOLE_MODEL_DIR'];
  final selector = Platform.environment['RSHOP_GW_SELECTOR_MODEL_DIR'];
  test('owner collection selector retains 63 devices and hides only its board',
      () async {
    final model = (await ConsoleModel.find('gameandwatch',
        modelsDirectory: Directory(selector!)))!;
    final geometry = await model.load();
    final scene = geometry.data['selectorScene'];
    expect(scene['deviceCount'], 63);
    expect((scene['devices'] as List).toSet().length, 63);
    expect(scene['hiddenNodes'], ['Display_board']);
    expect((geometry.data['bounds'][2] as num),
        greaterThan((geometry.data['bounds'][1] as num) * 3),
        reason: 'Preserve the source tabletop arrangement and vertical axis');
    expect(
        scene['devices'],
        containsAll([
          'donkey-kong-jr-tabletop',
          'marios-cement-factory-tabletop',
          'popeye-tabletop',
          'snoopy-tabletop',
          'balloon-fight-new-wide'
        ]));
    expect(geometry.surfaces.length, lessThanOrEqualTo(384));
    expect(geometry.mesh.lengthInBytes, lessThanOrEqualTo(20 * 1024 * 1024));
    expect(geometry.data['sourceReference']['sha256'],
        '1093ca53da36b88ba472d713c31e278336a693c05cf2d09397e925c8c326e9cd');
    for (final file in (geometry.data['textureFiles'] as Map).keys) {
      expect(
          (await geometry.textureBundle!
                  .load('${SocketMediaModel.assetRoot}$file'))
              .lengthInBytes,
          greaterThan(0));
    }
  },
      skip: selector == null
          ? 'Requires private owner selector conversion'
          : false,
      timeout: Timeout.none);
  test('owner GBA scene retains all parts, textures and source identity',
      () async {
    final model =
        (await ConsoleModel.find('gba', modelsDirectory: Directory(actual!)))!;
    final geometry = await model.load();
    expect(geometry.triangles, 6621);
    expect(geometry.surfaces.length, 10);
    expect(geometry.data['textureFiles'].length, 17);
    expect(geometry.data['sourceReference']['sha256'],
        '2b38e6bd383ec258b757092e6cbde486d034c2c4c47686989d31522f48e8af16');
    for (final file in (geometry.data['textureFiles'] as Map).keys) {
      expect(
          (await geometry.textureBundle!
                  .load('${SocketMediaModel.assetRoot}$file'))
              .lengthInBytes,
          greaterThan(0));
    }
    final screens =
        geometry.surfaces.where((s) => s['physicalMaterial'] == 'glass');
    expect(screens.length, 2);
    for (final screen in screens) {
      expect(SocketMediaGpu.materialUniforms(screen['material']).sublist(20),
          [1, 1, 1, 0]);
    }
  },
      skip: actual == null
          ? 'Requires the private owner console conversion'
          : false);
}
