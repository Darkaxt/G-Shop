import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:retro_eshop/models/unboxing_scene.dart';
import 'package:retro_eshop/widgets/socket_media_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['RSHOP_UNBOXING_MODEL_DIR'];
  test('real holder scene seats, opens, extracts and focuses one cartridge',
      () async {
    final model =
        (await UnboxingScene('blue', modelsDirectory: Directory(root!))
            .load())!;
    expect(model.data['unboxingGeometry'], true);
    expect(
        model.surfaces.where((s) => s['unboxingPart'] == 'box'), hasLength(59));
    expect(model.surfaces.where((s) => s['unboxingPart'] == 'cartridge'),
        hasLength(35));
    final start = UnboxingScene.partTransform(model, 'cartridge', 0, 6);
    final center = start.transform3(vm.Vector3.zero());
    expect(center.x, lessThan(0));
    expect(center.y, closeTo(.45625, .001));
    final bottom = start.transform3(vm.Vector3(-.5, 0, 0));
    expect(bottom.y, greaterThan(-.05));
    expect(UnboxingScene.opening(3 / 6.5), 1);
    final extracted =
        UnboxingScene.partTransform(model, 'cartridge', 4.2 / 6.5, 6);
    expect(extracted.transform3(vm.Vector3(-.5, 0, 0)).y, greaterThan(1.05));
    final finalPose = UnboxingScene.partTransform(model, 'cartridge', 1, 6);
    expect(finalPose.transform3(vm.Vector3.zero()).length, closeTo(0, .00001));
    expect(finalPose.transform3(vm.Vector3(1, 0, 0)).x, closeTo(3, .00001));
    expect(
        UnboxingScene.partTransform(model, 'box', 1, 6)
            .transform3(vm.Vector3(1, 1, 0))
            .x,
        lessThan(-3));
    final lid = model.surfaces.firstWhere((s) => s['node'] == 'Top_lid');
    expect(SocketMediaGpu.openingTransform(lid, 1).storage,
        isNot(orderedEquals(SocketMediaGpu.openingTransform(lid, 0).storage)));
  }, skip: root == null ? 'Requires owner local imports' : false);
}
