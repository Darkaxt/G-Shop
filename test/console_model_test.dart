import 'dart:convert';
import 'dart:io';
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
  final root = Directory('D:/Temp/rshop-s25-hardware-20261018/test-console');
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
