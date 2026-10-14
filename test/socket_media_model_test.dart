import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/socket_media_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('selected pose retains source Euler angles before camera conversion',
      () {
    final pose = SocketMediaPose.sample(
        kind: 'drop', selected: 1, seconds: 0, reducedMotion: true);
    expect(pose.rx, closeTo(-70 * 3.141592653589793 / 180, 1e-8));
    expect(pose.rz, closeTo(20 * 3.141592653589793 / 180, 1e-8));
  });
  test(
      'Socket console bindings include GBA, UMD, regional and optical variants',
      () {
    for (final id in [
      'gb',
      'gbc',
      'gba',
      'n64',
      'nes',
      'snes',
      'nds',
      'n3ds',
      'switch',
      'megadrive',
      'psp',
      'psvita',
      'psx',
      'ps2',
      'ps3',
      'dreamcast',
      'gc',
      'wii',
      'wiiu'
    ]) {
      expect(PhysicalMediaFormat.forSystem(id), isNotNull, reason: id);
    }
    expect(PhysicalMediaFormat.forSystem('snes', region: 'Japan'),
        PhysicalMediaFormat.snesPal);
    expect(PhysicalMediaFormat.forSystem('snes', region: 'USA'),
        PhysicalMediaFormat.snesUs);
    expect(PhysicalMediaFormat.forSystem('megadrive', region: 'Europe'),
        PhysicalMediaFormat.megadrive);
    expect(PhysicalMediaFormat.forSystem('gbc', dualMode: 'no'),
        PhysicalMediaFormat.gameBoyColorDual);
    expect(PhysicalMediaFormat.forSystem('psp'), PhysicalMediaFormat.psp);
    expect(PhysicalMediaFormat.forSystem('xbox'), isNull);
  });
  test(
      'every source-bound model loads all indexed source triangles and label surfaces',
      () async {
    const counts = {
      '3ds': 4240,
      'disc': 8064,
      'gb': 1162,
      'gba': 1092,
      'gbc': 1162,
      'gbc_dual_mode': 1776,
      'genesis': 2186,
      'megadrive': 2186,
      'n64': 1050,
      'nds': 5030,
      'nes': 7257,
      'psp': 144640,
      'snes_pal': 12130,
      'snes_us': 8251,
      'switch': 1494,
      'vita': 2627
    };
    for (final format in PhysicalMediaFormat.values) {
      final model = await SocketMediaModel.load(format);
      expect(model.triangles, counts[format.assetName]);
      expect(model.surfaces.where((s) => s['role'] == 'label'), hasLength(1));
      expect(model.labelAspect, greaterThan(0));
      expect(model.data['animationSourceSha256'], hasLength(64));
      expect(model.data['animationTokens'], isNotEmpty);
    }
  });
  test(
      'push-click, drop, disc and UMD retain source timing and independent label spin',
      () {
    final cart = SocketMediaPose.sample(
        kind: 'drop', selected: 1, seconds: 0, insertion: .2);
    expect(cart.rx, closeTo(-3.141592653589793 / 2, 1e-8));
    expect(cart.ry, closeTo(2 * 3.141592653589793, .0001));
    final umd = SocketMediaPose.sample(
        kind: 'umd', selected: 1, seconds: 0, insertion: .2);
    expect(umd.ry, 0,
        reason: 'The UMD plastic casing must not spin with the label');
    expect(umd.labelSpin, closeTo(6 * 3.141592653589793, .0001));
    final disc = SocketMediaPose.sample(
        kind: 'disc', selected: 1, seconds: 0, insertion: 1.6);
    final clicked = SocketMediaPose.sample(
        kind: 'pushClick', selected: 1, seconds: 0, insertion: .85);
    expect(disc.y, lessThan(-1));
    expect(clicked.y, lessThan(-1));
  });
}
