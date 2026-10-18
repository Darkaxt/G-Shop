import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/gba_cartridge_model.dart';
import 'package:retro_eshop/models/socket_media_model.dart';
import 'package:retro_eshop/widgets/socket_media_renderer.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
        isNull);
    expect(GbaCartridgeModel.styleFor('Castlevania (Europe).gba', ['official']),
        'gray');
  });
  final source = Platform.environment['RSHOP_CARTRIDGE_MODEL_DIR'];
  test(
      'actual conversion retains separate label, shells and PCB with optical materials',
      () async {
    final root = Directory(source!);
    final red = (await GbaCartridgeModel.load('red', modelsDirectory: root))!;
    expect(red.triangles, 32170);
    expect(red.surfaces, hasLength(35));
    expect(red.surfaces.where((s) => s['role'] == 'label'), hasLength(1));
    expect(red.surfaces.any((s) => s['node'] == 'PCB_AGB_E05_01'), true);
    final shell = red.surfaces.firstWhere((s) => s['shellMaterial'] == true);
    expect(shell['material']['color'][3], 1);
    expect(shell['material']['sourceProperties']['transmission'],
        closeTo(.94, 1e-6));
    final cloudy =
        (await GbaCartridgeModel.load('cloudy-green', modelsDirectory: root))!;
    expect(
        cloudy.surfaces
                .firstWhere((s) => s['shellMaterial'] == true)['material']
            ['sourceProperties']['transmission'],
        lessThan(.9));
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
