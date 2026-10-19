import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/gba_cartridge_model.dart';
import 'package:retro_eshop/models/unboxing_scene.dart';
import 'package:retro_eshop/models/packaging_model.dart';
import 'package:retro_eshop/models/socket_media_model.dart';
import 'package:retro_eshop/widgets/socket_media_renderer.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('supplied special housings match titles and supported regions only', () {
    expect(
        GbaCartridgeModel.styleFor(
            'WarioWare - Twisted! (USA).gba', ['official']),
        'twisted-us');
    expect(
        GbaCartridgeModel.styleFor(
            'Mawaru Made in Wario (Japan).gba', ['official']),
        isNull);
    expect(GbaCartridgeModel.styleFor('WarioWare - Twisted!.gba', ['official']),
        isNull);
    expect(
        GbaCartridgeModel.styleFor(
            'Boktai - The Sun Is in Your Hand (USA).gba', ['official']),
        'boktai');
    expect(
        GbaCartridgeModel.styleFor(
            'Boktai 2 - Solar Boy Django (Europe).gba', ['official']),
        'boktai');
    expect(
        GbaCartridgeModel.styleFor(
            'Shin Bokura no Taiyou - Gyakushuu no Sabata (Japan).gba',
            ['official']),
        'boktai');
    expect(
        GbaCartridgeModel.styleFor('Yoshi Topsy-Turvy (USA).gba', ['official']),
        'yoshi-us');
    expect(
        GbaCartridgeModel.styleFor(
            "Yoshi's Universal Gravitation (Europe).gba", ['official']),
        isNull);
    expect(
        GbaCartridgeModel.styleFor('WarioWare - Twisted! (USA).gba', ['hack']),
        isNull);
    expect(GbaCartridgeModel.styleFor('Drill Dozer (USA).gba', ['official']),
        isNull);
  });
  test('five commercial colors stay distinct from hacks and unknown editions',
      () {
    const titles = {
      'Ruby': 'red',
      'Sapphire': 'blue',
      'Emerald': 'green',
      'FireRed': 'cloudy-red',
      'LeafGreen': 'cloudy-green'
    };
    for (final entry in titles.entries) {
      expect(
          GbaCartridgeModel.styleFor(
              'Pokemon - ${entry.key} Version (Europe).gba', ['official']),
          entry.value);
    }
    expect(
        GbaCartridgeModel.styleFor(
            'Pokemon - Emerald Version (USA).gba', ['Hack']),
        isNull);
    expect(
        GbaCartridgeModel.styleFor('Pokemon Emerald Unbound.gba', ['official']),
        'gray');
    expect(GbaCartridgeModel.styleFor('Pokemon Emerald.gba', []), isNull);
    expect(
        GbaCartridgeModel.styleFor(
            'Boktai - The Sun Is in Your Hand (USA).gba', ['official']),
        'boktai');
    expect(GbaCartridgeModel.styleFor('Castlevania (Europe).gba', ['official']),
        'gray');
  });
  final source = Platform.environment['RSHOP_CARTRIDGE_MODEL_DIR'];
  final specials = Platform.environment['RSHOP_SPECIAL_MODEL_DIR'];
  for (final style in ['twisted-us', 'boktai', 'yoshi-us']) {
    test(
        'actual $style assembly retains its shell, fitted holder and replaceable label',
        () async {
      final root = Directory(specials!);
      final cartridge =
          (await GbaCartridgeModel.load(style, modelsDirectory: root))!;
      expect(
          cartridge.surfaces.where((s) => s['role'] == 'label'), hasLength(1));
      expect(cartridge.surfaces.any((s) => s['shellMaterial'] == true), true);
      final label = cartridge.surfaces.singleWhere((s) => s['role'] == 'label');
      expect(label['material']['textures'], isEmpty);
      expect(label['material']['color'][3], 1);
      if (style == 'yoshi-us') {
        final colors = cartridge.surfaces
            .where((s) => s['shellMaterial'] == true)
            .map((s) => s['material']['color'].toString())
            .toSet();
        expect(colors, hasLength(2),
            reason: 'Preserve green front and white rear');
      }
      final carton = await PackagingModel(PackagingKind.box,
              systemId: 'gba',
              cartridgeStyle: style,
              aspect: 1,
              depth: GbaCartridgeModel.cartonDepth(style),
              modelsDirectory: root)
          .load();
      expect(carton.data['openingSide'], 'right');
      expect(carton.data['cartridgeSlot']['clearanceMm'],
          everyElement(greaterThan(0)));
      expect(
          carton.surfaces
              .where((s) => (s['node'] as String).startsWith('Holder_'))
              .map((s) => s['node'])
              .toSet(),
          hasLength(7));
      final scene =
          (await UnboxingScene(style, modelsDirectory: root, hasBooklet: true)
              .load())!;
      final matrix = UnboxingScene.partTransform(scene, 'cartridge', 0, 6);
      final sourceBounds =
          (scene.data['partBounds']['cartridge'] as List).cast<List>();
      final fit =
          (carton.data['cartridgeSlot']['fitBounds'] as List).cast<List>();
      final low = [double.infinity, double.infinity, double.infinity];
      final high = [-double.infinity, -double.infinity, -double.infinity];
      for (var x = 0; x < 2; x++) {
        for (var y = 0; y < 2; y++) {
          for (var z = 0; z < 2; z++) {
            final p = matrix.transform3(vm.Vector3(
                (sourceBounds[x][0] as num).toDouble(),
                (sourceBounds[y][1] as num).toDouble(),
                (sourceBounds[z][2] as num).toDouble()));
            for (var a = 0; a < 3; a++) {
              if (p[a] < low[a]) low[a] = p[a];
              if (p[a] > high[a]) high[a] = p[a];
            }
          }
        }
      }
      for (var axis = 0; axis < 3; axis++) {
        final multiplier =
            axis == 2 ? GbaCartridgeModel.cartonDepth(style) / 2 : 1.0;
        expect(low[axis], closeTo((fit[0][axis] as num) * multiplier, .002));
        expect(high[axis], closeTo((fit[1][axis] as num) * multiplier, .002));
      }
    }, skip: specials == null ? 'Requires owner special conversions' : false);
  }
  test(
      'actual conversion retains separate label, shells and PCB with optical materials',
      () async {
    final root = Directory(source!);
    final red = (await GbaCartridgeModel.load('red', modelsDirectory: root))!;
    expect(red.triangles, 32170);
    expect(red.surfaces, hasLength(35));
    expect(red.surfaces.where((s) => s['role'] == 'label'), hasLength(1));
    final label = red.surfaces.singleWhere((s) => s['role'] == 'label');
    final rows = List.generate(label['vertexCount'] as int, (i) {
      final offset = (label['vertexOffset'] as int) + i * 32;
      return [
        for (final n in [0, 4, 24, 28])
          red.mesh.getFloat32(offset + n, Endian.little)
      ];
    });
    final top = rows.reduce((a, b) => a[1] > b[1] ? a : b);
    final bottom = rows.reduce((a, b) => a[1] < b[1] ? a : b);
    expect(top[3], closeTo(0, .00001),
        reason:
            'A new top-down game label must not inherit rotated source-print UVs');
    expect(bottom[3], closeTo(1, .00001));
    expect(red.surfaces.any((s) => s['node'] == 'PCB_AGB_E05_01'), true);
    final shell = red.surfaces.firstWhere((s) => s['shellMaterial'] == true);
    expect(shell['material']['color'][3], 1);
    expect(shell['material']['sourceProperties']['transmission'],
        closeTo(.42, 1e-6));
    expect(shell['material']['sourceProperties']['sourceTransmission'],
        closeTo(.94, 1e-6));
    final cloudy =
        (await GbaCartridgeModel.load('cloudy-green', modelsDirectory: root))!;
    expect(
        cloudy.surfaces
                .firstWhere((s) => s['shellMaterial'] == true)['material']
            ['sourceProperties']['transmission'],
        lessThan(.42));
    final gray = (await GbaCartridgeModel.load('gray', modelsDirectory: root))!;
    expect(
        gray.surfaces.firstWhere((s) => s['shellMaterial'] == true)['material']
            ['sourceProperties']['transmission'],
        0);
    final pose = SocketMediaGpu.modelTransform(
        red, const SocketMediaPose(rx: -1.57079632679));
    expect(pose.transform3(vm.Vector3(0, 0, 1)).z, closeTo(1, .00001));
    for (final surface in red.surfaces) {
      for (final name in (surface['material']['textures'] as Map).values) {
        expect(
            (await red.textureBundle!
                    .load('${SocketMediaModel.assetRoot}$name'))
                .lengthInBytes,
            greaterThan(0));
      }
    }
  }, skip: source == null ? 'Requires the owner private conversion' : false);
}
