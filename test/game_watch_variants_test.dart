import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/console_model.dart';
import 'package:retro_eshop/models/packaging_model.dart';
import 'package:retro_eshop/models/socket_media_model.dart';
import 'package:retro_eshop/features/preview/console_hardware_view.dart';
import 'package:retro_eshop/features/preview/game_watch_variants_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Directory('${Directory.systemTemp.path}/rshop-gw-variant-test');
  final hardware = Directory('${root.path}/handhelds/gameandwatch');
  Future<void> model(String path, {String? set, String? variant}) async {
    final base = PackagingModel(PackagingKind.keepCase).build();
    final dir = Directory('${hardware.path}/$path');
    await dir.create(recursive: true);
    final data = Map<String, dynamic>.from(base.data)..remove('ownedGeometry');
    await File('${dir.path}/model.json').writeAsString(jsonEncode({
      ...data,
      'name': 'console-gameandwatch-v1',
      'system': 'gameandwatch',
      'motionKind': 'hardware',
      'hardwareGeometry': true,
      'privateImport': true,
      'resourceKind': 'handheld',
      if (set != null) 'romSet': set,
      if (variant != null) 'visualVariantId': variant,
      'textureFiles': {
        'screen.png': sha256.convert([1, 2, 3]).toString()
      },
      'sourceReference': {
        'author': 'Fixture',
        'url': 'local:fixture',
        'licence': 'local-import-only',
        'sha256': 'b' * 64,
      },
    }));
    await File('${dir.path}/model.mesh')
        .writeAsBytes(base.mesh.buffer.asUint8List());
    await File('${dir.path}/screen.png').writeAsBytes([1, 2, 3]);
  }

  Future<void> index(List<Map<String, Object>> models,
      {List<String> sets = const ['gnw_zelda']}) async {
    await File('${hardware.path}/variants.json').writeAsString(jsonEncode({
      'schemaVersion': 1,
      'groups': [
        {'sets': sets, 'models': models}
      ],
    }));
  }

  setUp(() async {
    await model('gnw_zelda', set: 'gnw_zelda');
    await model('variants/zelda-2021', variant: 'zelda-2021');
    await index([
      {'directory': 'gnw_zelda', 'label': 'Multi Screen'},
      {'directory': 'variants/zelda-2021', 'label': '2021 edition'},
    ]);
  });
  test('visual editions keep the exact primary and never bind another ROM',
      () async {
    final models = await ConsoleModel.findGameWatchVariants('Zelda (World).7z',
        modelsDirectory: root);
    expect(models.map((v) => v.label), ['Multi Screen', '2021 edition']);
    expect(models.first.model.romSet, 'gnw_zelda');
    expect(models.last.model.romSet, isNull);
    expect(models.last.model.visualVariantId, 'zelda-2021');
    expect(
        (await models.last.model.load()).data['visualVariantId'], 'zelda-2021');
    expect(
        (await ConsoleModel.findGameWatch('Zelda (World).7z',
                modelsDirectory: root))!
            .romSet,
        'gnw_zelda');
    expect(
        await ConsoleModel.findGameWatchVariants('Fire (World) (Silver).7z',
            modelsDirectory: root),
        isEmpty);
  });
  test('primary order follows the selected exact edition, not catalogue order',
      () async {
    await model('gnw_smb', set: 'gnw_smb');
    await model('gnw_smbn', set: 'gnw_smbn');
    await index([
      {'directory': 'gnw_smbn', 'label': 'New Wide Screen'},
      {'directory': 'gnw_smb', 'label': 'Crystal Screen'},
    ], sets: [
      'gnw_smbn',
      'gnw_smb'
    ]);
    final models = await ConsoleModel.findGameWatchVariants('gnw_smb.zip',
        modelsDirectory: root);
    expect(models.map((v) => v.model.romSet), ['gnw_smb', 'gnw_smbn']);
  });
  test('absent optional imports keep the primary; unsafe paths are rejected',
      () async {
    await index([
      {'directory': 'gnw_zelda', 'label': 'Multi Screen'},
      {'directory': 'variants/not-imported', 'label': 'Additional edition'},
    ]);
    expect(
        (await ConsoleModel.findGameWatchVariants('gnw_zelda.zip',
                modelsDirectory: root))
            .length,
        1);
    await index([
      {'directory': 'gnw_zelda', 'label': 'Multi Screen'},
      {'directory': '../gnw_fire', 'label': 'Invalid'},
    ]);
    await expectLater(
        ConsoleModel.findGameWatchVariants('gnw_zelda.zip',
            modelsDirectory: root),
        throwsFormatException);
  });
  test(
      'another local visual import joins a group without changing ROM bindings',
      () async {
    await model('variants/additional-edition', variant: 'additional-edition');
    await index([
      {'directory': 'gnw_zelda', 'label': 'Multi Screen'},
      {'directory': 'variants/zelda-2021', 'label': '2021 edition'},
      {
        'directory': 'variants/additional-edition',
        'label': 'Additional edition'
      },
    ]);
    final models = await ConsoleModel.findGameWatchVariants('gnw_zelda.zip',
        modelsDirectory: root);
    expect(models.length, 3);
    expect(models.map((v) => v.model.romSet), ['gnw_zelda', null, null]);
  });
  final privateRoot = Platform.environment['RSHOP_GAMEWATCH_MODEL_DIR'];
  test(
      'real paired imports validate geometry, textures and visual-only identity',
      () async {
    for (final set in ['gnw_smbn', 'gnw_zelda', 'gnw_dkjr']) {
      final models = await ConsoleModel.findGameWatchVariants('$set.zip',
          modelsDirectory: Directory(privateRoot!));
      expect(models.length, greaterThanOrEqualTo(2), reason: set);
      expect(models.first.model.romSet, set);
      for (final entry in models) {
        final loaded = await entry.model.load();
        expect(
            loaded.data['geometrySha256'], matches(RegExp(r'^[a-f0-9]{64}$')));
        for (final texture in (loaded.data['textureFiles'] as Map).keys) {
          await loaded.textureBundle!
              .load('${SocketMediaModel.assetRoot}$texture');
        }
      }
      if (set != 'gnw_smbn') {
        expect(models.last.model.romSet, isNull);
        expect(models.last.model.visualVariantId, isNotEmpty);
      }
    }
  },
      skip: privateRoot == null
          ? 'Private owner imports are not bundled'
          : false);
  testWidgets('paired layout keeps gestures separate and waits for both models',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final models = (await tester.runAsync(() =>
        ConsoleModel.findGameWatchVariants('gnw_zelda.zip',
            modelsDirectory: root)))!;
    var ready = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GameWatchVariantsView(
                variants: models,
                reducedMotion: true,
                onReady: () => ready++))));
    final views = tester
        .widgetList<ConsoleHardwareView>(find.byType(ConsoleHardwareView))
        .toList();
    expect(views.length, 2);
    expect(views.every((v) => v.reducedMotion && !v.turntable), true);
    expect(find.text('Multi Screen'), findsOneWidget);
    expect(find.text('2021 edition'), findsOneWidget);
    final left = tester.getRect(find.byType(ConsoleHardwareView).at(0));
    final right = tester.getRect(find.byType(ConsoleHardwareView).at(1));
    expect(left.right, lessThanOrEqualTo(right.left));
    expect(left.left, greaterThanOrEqualTo(0));
    expect(right.right, lessThanOrEqualTo(1240));
    expect(ready, 0);
    views.first.onReady?.call();
    expect(ready, 0);
    views.last.onReady?.call();
    expect(ready, 1);
    views.last.onReady?.call();
    expect(ready, 1, reason: 'No duplicate aggregate completion');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GameWatchVariantsView(
                variants: models.reversed.toList(),
                reducedMotion: true,
                onReady: () => ready++))));
    views.first.onReady?.call();
    views.last.onReady?.call();
    expect(ready, 1, reason: 'Stale callbacks cannot finish a new selection');
    final replacement = tester
        .widgetList<ConsoleHardwareView>(find.byType(ConsoleHardwareView))
        .toList();
    replacement.first.onReady?.call();
    expect(ready, 1);
    replacement.last.onReady?.call();
    expect(ready, 2);
    await tester.pumpWidget(const SizedBox());
    replacement.first.onReady?.call();
    expect(ready, 2, reason: 'Disposed selection cannot complete again');
  });
  test('all private edition groups load exact primary first and valid textures',
      () async {
    final dir = Directory(privateRoot!);
    final catalogue = jsonDecode(
        await File('${dir.path}/handhelds/gameandwatch/variants.json')
            .readAsString());
    for (final group in catalogue['groups'] as List) {
      for (final set in group['sets'] as List) {
        final models = await ConsoleModel.findGameWatchVariants('$set.zip',
            modelsDirectory: dir);
        expect(models.first.model.romSet, set);
        expect(models.length, (group['models'] as List).length);
        for (final entry in models) {
          final geometry = await entry.model.load();
          expect(geometry.triangles, greaterThan(0));
          for (final file in (geometry.data['textureFiles'] as Map).keys) {
            await geometry.textureBundle!
                .load('${SocketMediaModel.assetRoot}$file');
          }
        }
      }
    }
  },
      skip: privateRoot == null
          ? 'Private owner imports are not bundled'
          : false);
  testWidgets('three editions fit Thor logical width and wait for all frames',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 764);
    tester.view.devicePixelRatio = 369 / 160;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final models = (await tester.runAsync(() async {
      await model('variants/additional-edition', variant: 'additional-edition');
      await index([
        {'directory': 'gnw_zelda', 'label': 'New Wide Screen'},
        {'directory': 'variants/zelda-2021', 'label': 'Panorama Screen'},
        {'directory': 'variants/additional-edition', 'label': 'Special edition'}
      ]);
      return ConsoleModel.findGameWatchVariants('gnw_zelda.zip',
          modelsDirectory: root);
    }))!;
    var ready = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GameWatchVariantsView(
                variants: models,
                reducedMotion: true,
                onReady: () => ready++))));
    final views = tester
        .widgetList<ConsoleHardwareView>(find.byType(ConsoleHardwareView))
        .toList();
    expect(views.length, 3);
    var edge = 0.0;
    for (var i = 0; i < 3; i++) {
      final rect = tester.getRect(find.byType(ConsoleHardwareView).at(i));
      expect(rect.left, greaterThanOrEqualTo(edge));
      expect(rect.right, lessThanOrEqualTo(1240 / (369 / 160) + .001));
      edge = rect.right;
      views[i].onReady?.call();
      expect(ready, i == 2 ? 1 : 0);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
