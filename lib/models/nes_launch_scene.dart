import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'console_model.dart';
import 'nes_unboxing_scene.dart';
import 'socket_media_model.dart';

/// Continue the selected carton/shell scene into the calibrated 72-pin NES.
/// The controller belongs to the imported hardware; the display is our neutral
/// external CRT. NES has no built-in screen or universal Nintendo boot logo.
class NesLaunchScene {
  final NesUnboxingScene media;
  final ConsoleModel console;
  final Rect? initialViewport;
  const NesLaunchScene(this.media, this.console, {this.initialViewport});
  String get identity => '${media.identity}:${console.generation}';

  Future<SocketMediaModel> load() async {
    final base = await media.load(), hardware = await console.load();
    final profile = hardware.data['launchHardware'];
    if (profile is! Map ||
        profile['schema'] != 1 ||
        profile['target'] != 'nes-front-loader' ||
        profile['compatibleMedia'] != 'nes-72-pin' ||
        profile['controllerPort'] != 1 ||
        profile['geometrySha256'] != hardware.data['geometrySha256'] ||
        profile['sourceScale'] is! num ||
        !(profile['sourceScale'] as num).isFinite ||
        (profile['sourceScale'] as num) <= 0 ||
        profile['sourceCenter'] is! List ||
        (profile['sourceCenter'] as List).length != 3 ||
        (profile['sourceCenter'] as List)
            .any((v) => v is! num || !v.isFinite)) {
      throw const FormatException(
          'NES launch needs calibrated matching hardware');
    }
    for (final key in [
      'sourceSlotEntry',
      'sourceSlotInserted',
      'sourceSlotSeated',
      'sourceTrayPivot'
    ]) {
      final point = profile[key];
      if (point is! List ||
          point.length != 3 ||
          point.any((v) => v is! num || !v.isFinite)) {
        throw const FormatException('NES launch slot anchor is absent');
      }
    }
    for (final key in ['insertionPitch', 'trayPressRadians']) {
      final value = profile[key];
      if (value is! num || !value.isFinite || value.abs() > math.pi / 6) {
        throw const FormatException('NES launch tray angle is uncalibrated');
      }
    }
    final payload = BytesBuilder(copy: false);
    final surfaces = <Map<String, dynamic>>[];
    final bundles = <String, AssetBundle>{};
    for (final (group, model) in [('media', base), ('console', hardware)]) {
      final offset = payload.length;
      payload.add(model.mesh.buffer
          .asUint8List(model.mesh.offsetInBytes, model.mesh.lengthInBytes));
      for (final original in model.surfaces) {
        final s = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
        s['vertexOffset'] = (s['vertexOffset'] as int) + offset;
        s['indexOffset'] = (s['indexOffset'] as int) + offset;
        s['launchPart'] = group == 'media' ? s['nesPart'] : group;
        final textures = s['material']['textures'] as Map;
        for (final role in textures.keys.toList()) {
          final name = textures[role] as String, key = '$group/$name';
          textures[role] = key;
          bundles[key] = model.textureBundle!;
        }
        surfaces.add(s);
      }
    }
    // A plain period display avoids claiming a specific television edition.
    _cuboid(payload, surfaces, 'crt-cabinet', [.65, .72, -1.65],
        [1.83, 1.45, .76], [.07, .065, .06, 1]);
    _cuboid(payload, surfaces, 'crt-bezel', [.65, .72, -1.245],
        [1.64, 1.27, .10], [.018, .018, .017, 1]);
    _cuboid(payload, surfaces, 'crt-screen', [.58, .75, -1.183],
        [1.40, 1.05, .025], [.005, .007, .006, 1]);
    _cuboid(payload, surfaces, 'crt-controls', [1.415, .72, -1.175],
        [.10, .82, .04], [.09, .085, .075, 1]);
    final bytes = payload.takeBytes();
    return SocketMediaModel.privateHardware({
      ...base.data,
      'name': 'nes-cartridge-console-launch-v1',
      'nesLaunch': true,
      if (initialViewport case final rect?)
        'launchInitialViewport': [rect.left, rect.top, rect.width, rect.height],
      'launchHardware': profile,
      'consoleGeometrySha256': hardware.data['geometrySha256'],
      'geometrySha256': sha256.convert(bytes).toString(),
      'surfaces': surfaces,
      'sourceReference': {
        'author':
            'Owner-imported NES media and hardware; G-Shop display geometry',
        'url': 'local:nes-launch/$identity',
        'licence': 'local-import-only',
        'sha256': sha256
            .convert(utf8.encode(jsonEncode([
              base.data['sourceReference'],
              hardware.data['sourceReference']
            ])))
            .toString(),
        'sources': [
          base.data['sourceReference'],
          hardware.data['sourceReference']
        ],
      },
    }, ByteData.sublistView(bytes), textureBundle: _LaunchTextures(bundles));
  }

  static double phase(double value, double begin, double end) {
    final t = ((value - begin) / (end - begin)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static bool visible(Map<String, dynamic> surface, SocketMediaPose p) =>
      p.launch > 0 || !{'console', 'display'}.contains(surface['launchPart']);

  static double opening(Map<String, dynamic> surface, SocketMediaPose p) =>
      surface['launchPart'] == 'console'
          ? phase(p.launch, 0, .18) * (1 - phase(p.launch, .69, .76))
          : 0;

  static vm.Matrix4 _hardware(SocketMediaModel m) {
    final profile = m.data['launchHardware'] as Map;
    final sourceScale = (profile['sourceScale'] as num).toDouble();
    final center = (profile['sourceCenter'] as List).cast<num>();
    final scale = 1.85 / (25.6 * sourceScale);
    return vm.Matrix4.identity()
      ..translateByDouble(-.65, -.8, -.6, 1)
      ..scaleByDouble(scale, scale, scale, 1)
      ..translateByDouble(center[0] * sourceScale, center[1] * sourceScale,
          center[2] * sourceScale, 1);
  }

  static vm.Vector3 _anchor(SocketMediaModel m, List<double> zUp) {
    final profile = m.data['launchHardware'] as Map;
    final scale = (profile['sourceScale'] as num).toDouble();
    final center = (profile['sourceCenter'] as List).cast<num>();
    return vm.Vector3((zUp[0] - center[0]) * scale,
        (zUp[2] - center[1]) * scale, (-zUp[1] - center[2]) * scale);
  }

  static vm.Matrix4 partTransform(
      SocketMediaModel m, Map<String, dynamic> surface, SocketMediaPose p) {
    final part = surface['launchPart'] as String;
    if (p.launch == 0 && part != 'console' && part != 'display') {
      return NesUnboxingScene.partTransform(m, part, p);
    }
    final t = p.launch;
    final introduce = phase(t, 0, .22);
    if (part == 'display') {
      return vm.Matrix4.translationValues(0, 0, -3 * (1 - introduce));
    }
    if (part == 'console') {
      final matrix = vm.Matrix4.translationValues(0, 0, -3 * (1 - introduce))
        ..multiply(_hardware(m));
      final profile = m.data['launchHardware'] as Map;
      if ((profile['trayNodes'] as List).contains(surface['node'])) {
        final pivot = _anchor(
            m,
            (profile['sourceTrayPivot'] as List)
                .cast<num>()
                .map((v) => v.toDouble())
                .toList());
        matrix
          ..translateByDouble(pivot.x, pivot.y, pivot.z, 1)
          ..rotateX((profile['trayPressRadians'] as num) * phase(t, .60, .69))
          ..translateByDouble(-pivot.x, -pivot.y, -pivot.z, 1);
      }
      return matrix;
    }
    final settled = SocketMediaPose(
        unboxing: 1,
        inspectedPart: p.inspectedPart,
        opening: p.opening * (1 - phase(t, 0, .12)));
    final initial = NesUnboxingScene.partTransform(m, part, settled);
    if (part != 'cartridge') {
      return vm.Matrix4.translationValues(
          (part == 'box' ? -2.2 : 2.5) * introduce,
          -.5 * introduce,
          -1.4 * introduce)
        ..multiply(initial);
    }
    final enter = phase(t, .17, .35), insert = phase(t, .35, .60);
    final press = phase(t, .60, .69);
    final profile = m.data['launchHardware'] as Map;
    vm.Vector3 point(String key) => vm.Vector3.array(
        (profile[key] as List).cast<num>().map((v) => v.toDouble()).toList());
    final entry = point('sourceSlotEntry'),
        inserted = point('sourceSlotInserted');
    final source = vm.Vector3.zero();
    vm.Vector3.mix(entry, inserted, insert, source);
    vm.Vector3.mix(source, point('sourceSlotSeated'), press, source);
    final position = _anchor(m, [source.x, source.y, source.z]);
    final sourceScale =
        (m.data['launchHardware']['sourceScale'] as num).toDouble();
    final cartScale =
        12 * sourceScale / (m.data['cartridgeClosedSize'][0] as num);
    final center = SocketMediaModel.poseCenter(
        Map<String, dynamic>.from(m.data['cartridgeData'] as Map), 0);
    final basis = vm.Matrix4.identity()
      ..setColumn(0, vm.Vector4(-1, 0, 0, 0))
      ..setColumn(1, vm.Vector4(0, 0, 1, 0))
      ..setColumn(2, vm.Vector4(0, 1, 0, 0));
    final target = _hardware(m)
      ..translateByDouble(position.x, position.y, position.z, 1)
      ..rotateX((profile['insertionPitch'] as num) * (1 - press))
      ..multiply(basis)
      ..scaleByDouble(cartScale, cartScale, cartScale, 1)
      ..translateByDouble(-center.x, -center.y, -center.z, 1);
    // Before entering the slot, interpolate the free cartridge's rigid pose.
    // Insertion itself then follows one fixed source-space axis/tray angle.
    if (enter == 0) return initial;
    if (enter == 1) return target;
    final a = vm.Quaternion.identity(), b = vm.Quaternion.identity();
    final sa = vm.Vector3.zero(), sb = vm.Vector3.zero();
    final pa = vm.Vector3.zero(), pb = vm.Vector3.zero();
    initial.decompose(pa, a, sa);
    target.decompose(pb, b, sb);
    if (a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w < 0) b.scale(-1);
    final rotation = (a.scaled(1 - enter) + b.scaled(enter))..normalize();
    final positionBlend = vm.Vector3.zero(), scaleBlend = vm.Vector3.zero();
    vm.Vector3.mix(pa, pb, enter, positionBlend);
    vm.Vector3.mix(sa, sb, enter, scaleBlend);
    return vm.Matrix4.compose(positionBlend, rotation, scaleBlend);
  }

  static vm.Matrix4 viewTransform(SocketMediaModel m, SocketMediaPose p) {
    if (p.launch == 0) return NesUnboxingScene.viewTransform(m, p);
    final enter = phase(p.launch, 0, .22), zoom = phase(p.launch, .82, 1);
    final baseCenter = p.inspectedPart == 'cartridge'
        ? vm.Vector3.zero()
        : NesUnboxingScene.viewCenter(m, p);
    return vm.Matrix4.identity()
      ..translateByDouble(-(baseCenter.x * (1 - enter) + .58 * zoom),
          -(baseCenter.y * (1 - enter) + .75 * zoom), 0, 1)
      ..rotateY((math.atan2(math.sin(p.ry), math.cos(p.ry)) * (1 - enter) -
              .12 * enter) *
          (1 - zoom))
      ..rotateX((p.rx * (1 - enter) + .24 * enter) * (1 - zoom));
  }

  static Offset? cameraCenter(
      SocketMediaModel m, SocketMediaPose p, double width, double height) {
    final rect = m.data['launchInitialViewport'] as List?;
    if (rect == null) return null;
    final enter = phase(p.launch, 0, .22);
    return Offset(
        ((rect[0] as num) + (rect[2] as num) / 2) * (1 - enter) +
            width / 2 * enter,
        ((rect[1] as num) + (rect[3] as num) / 2) * (1 - enter) +
            height / 2 * enter);
  }

  static double fittedUnits(
      SocketMediaModel m, SocketMediaPose p, double width, double height) {
    final rect = m.data['launchInitialViewport'] as List?;
    final base = NesUnboxingScene.fittedUnits(
        m,
        p,
        (rect?[2] as num?)?.toDouble() ?? width,
        (rect?[3] as num?)?.toDouble() ?? height);
    final work = math.min(width / 5.4, height / 3.8);
    final enter = phase(p.launch, 0, .22), zoom = phase(p.launch, .82, 1);
    final screen = 1.296 * math.max(width / 1.4, height / 1.05);
    return (base * (1 - enter) + work * enter) * (1 - zoom) + screen * zoom;
  }

  static Map<String, dynamic> material(
      Map<String, dynamic> surface, SocketMediaPose p) {
    final original = surface['material'] as Map<String, dynamic>;
    if ((surface['node'] as String).endsWith('7_LED_0')) {
      final power = phase(p.launch, .76, .82);
      return {
        ...original,
        'color': [.015 + .8 * power, .004, .003, 1.0],
        'textures': {...original['textures'] as Map}
          ..remove('albedo')
          ..remove('emission'),
        'sourceProperties': {
          ...original['sourceProperties'] as Map,
          'emission': [1.2 * power, .005 * power, 0.0]
        },
      };
    }
    if (surface['node'] != 'crt-screen') return original;
    final power = phase(p.launch, .76, .82);
    return {
      ...original,
      'sourceProperties': {
        ...original['sourceProperties'] as Map,
        'emission': [.025 * power, .032 * power, .028 * power],
      },
    };
  }

  static void _cuboid(BytesBuilder payload, List<Map<String, dynamic>> surfaces,
      String name, List<double> center, List<double> size, List<double> color) {
    final vertices = <double>[];
    for (final (axis, sign) in [
      (0, -1),
      (0, 1),
      (1, -1),
      (1, 1),
      (2, -1),
      (2, 1)
    ]) {
      final normal = vm.Vector3.zero()..[axis] = sign.toDouble();
      final u = axis == 0 ? 1 : 0, v = axis == 2 ? 1 : 2;
      final corners = [
        for (final (a, b) in [(-1, -1), (1, -1), (1, 1), (-1, 1)])
          vm.Vector3.array(center)
            ..[axis] += sign * size[axis] / 2
            ..[u] += a * size[u] / 2
            ..[v] += b * size[v] / 2
      ];
      final order =
          (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(normal) >
                  0
              ? [0, 1, 2, 0, 2, 3]
              : [0, 2, 1, 0, 3, 2];
      for (final i in order) {
        vertices.addAll([...corners[i].storage, ...normal.storage, 0, 0]);
      }
    }
    final offset = payload.length, count = vertices.length ~/ 8;
    payload.add(Float32List.fromList(vertices).buffer.asUint8List());
    final indices = payload.length;
    payload.add(Uint32List.fromList(List.generate(count, (i) => i))
        .buffer
        .asUint8List());
    surfaces.add({
      'node': name,
      'name': name,
      'role': 'shell',
      'launchPart': 'display',
      'vertexOffset': offset,
      'vertexCount': count,
      'indexOffset': indices,
      'indexCount': count,
      'openingHinges': [],
      'openingTranslations': [],
      'singleSided': true,
      'material': {
        'color': color,
        'textures': <String, String>{},
        'sourceProperties': {
          'roughness': .8,
          'metallic': 0,
          'emission': [0.0, 0.0, 0.0]
        }
      },
    });
  }
}

class _LaunchTextures extends CachingAssetBundle {
  final Map<String, AssetBundle> sources;
  _LaunchTextures(this.sources);
  @override
  Future<ByteData> load(String key) {
    final name = key.startsWith(SocketMediaModel.assetRoot)
        ? key.substring(SocketMediaModel.assetRoot.length)
        : '';
    final source = sources[name];
    if (source == null) throw const FormatException('Unknown launch texture');
    return source.load(
        '${SocketMediaModel.assetRoot}${name.substring(name.indexOf('/') + 1)}');
  }
}
