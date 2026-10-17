import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:retro_eshop/models/socket_media_model.dart';
import 'package:retro_eshop/widgets/socket_media_renderer.dart';
import 'helpers/socket_media_oracle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(useSocketOracle);
  tearDownAll(() => SocketMediaModel.importedBundle = null);
  test('plastic housings retain distinct label, disc and hardware materials',
      () {
    final source = <String, dynamic>{
      'color': [1, 1, 1, 1],
      'sourceProperties': {'metallic': 1, 'roughness': 1}
    };
    final gb = SocketMediaGpu.materialUniforms(source, plasticHousing: true);
    expect(gb[5], 0);
    expect(gb[19], 1,
        reason:
            'Matte housings must not retain grazing HDR metallic-like glare');
    final label = SocketMediaGpu.materialUniforms(source,
        plasticHousing: true, isLabel: true);
    expect(label[5], 1);
    expect(label[19], 0);
    final other = SocketMediaGpu.materialUniforms(source);
    expect(other[5], 1);
    expect(other[19], 0);
    expect(
        SocketMediaGpu.plasticHousing('gb',
            {'role': 'shell', 'node': 'gb/Gameboy', 'name': 'Material.001'}),
        isTrue);
    expect(
        SocketMediaGpu.plasticHousing('psp', {
          'role': 'shell',
          'node': 'umd/UMD - Shell - Front Plastic',
          'name': 'Shell Plastic'
        }),
        isTrue);
    expect(
        SocketMediaGpu.plasticHousing('psp', {
          'role': 'shell',
          'node': 'umd/Disc - Glass/Disc - Data',
          'name': 'Diffraction Grating (Stylized)'
        }),
        isFalse);
    expect(
        SocketMediaGpu.plasticHousing(
            '3ds', {'role': 'shell', 'node': 'cart', 'name': 'Gold Contacts'}),
        isFalse);
    expect(
        SocketMediaGpu.plasticHousing('switch',
            {'role': 'shell', 'node': 'cart/CircuitBoard', 'name': 'lambert1'}),
        isFalse);
    expect(
        SocketMediaGpu.plasticHousing(
            'disc', {'role': 'shell', 'node': 'disc', 'name': 'Disc'}),
        isFalse);
  });
  test(
      'source studio environment keeps its HDR mip chain and camera-relative light',
      () async {
    final sky = await SocketMediaModel.loadEnvironment();
    expect(sky.data['format'], 'astc4x4HDR');
    expect(sky.data['mips'], hasLength(11));
    expect(sky.pixels.lengthInBytes, 699088);
    expect(sky.data['lightDirection'][1], closeTo(.8141155243, 1e-8));
    expect(sky.data['lightDirection'][2], greaterThan(0));
    expect(sky.data['lightEnergy'], closeTo(math.pi, 1e-8),
        reason:
            'Godot converts default nonphysical directional energy to radiance');
    expect(SocketMediaGpu.environmentPrefixMipLevels,
        lessThanOrEqualTo(gpu.Texture.fullMipCount(1024, 512)));
    final tail = (sky.data['mips'] as List)
        .skip(SocketMediaGpu.environmentPrefixMipLevels)
        .toList();
    expect(tail, hasLength(2));
    expect(tail.map((level) => level['length']), everyElement(16),
        reason: 'Each tail level must remain one unchanged ASTC 4x4 block');
  },
      skip: socketOracleRoot.isEmpty
          ? 'Requires private owner APK oracle'
          : false);
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
    }
  },
      skip: socketOracleRoot.isEmpty
          ? 'Requires private owner APK oracle'
          : false);
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
