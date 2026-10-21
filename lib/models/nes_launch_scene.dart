import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'console_model.dart';
import 'nes_unboxing_scene.dart';
import 'socket_media_model.dart';

/// Continue the selected carton/shell scene into the calibrated 72-pin NES.
/// The controller and external CRT are calibrated private imports. NES has no
/// built-in screen or universal Nintendo boot logo.
class NesLaunchScene {
  final NesUnboxingScene media;
  final ConsoleModel console;
  final ConsoleModel display;
  final Rect? initialViewport;
  const NesLaunchScene(this.media, this.console, this.display,
      {this.initialViewport});
  String get identity =>
      '${media.identity}:${console.generation}:${display.generation}';

  static bool _standard(String style) => NesUnboxingScene.usesSleeve(style);

  /// The launch owner selects once, using the actual selected shell reference.
  /// Decorative Famicom/collector imports and invalid optional resources stay out.
  static Future<ConsoleModel?> chooseConsole(String? style,
      {Directory? modelsDirectory, math.Random? random}) async {
    final eligible = <ConsoleModel>[];
    for (final target in [
      'front-loader',
      if (style != null && _standard(style)) 'top-loader'
    ]) {
      try {
        final candidate = await ConsoleModel.findNesLaunchTarget(target,
            modelsDirectory: modelsDirectory);
        if (candidate == null) continue;
        _profile(await candidate.load(), style);
        eligible.add(candidate);
      } on FormatException {
        // Optional private hardware must validate before entering the pool.
      } on FileSystemException {
        // Missing optional imports do not disable the owned-ROM launcher.
      }
    }
    return eligible.isEmpty
        ? null
        : eligible[(random ?? math.Random()).nextInt(eligible.length)];
  }

  static Map<String, dynamic> _profile(
      SocketMediaModel hardware, String? style) {
    final profile = hardware.data['launchHardware'];
    if (profile is! Map ||
        profile['schema'] != 1 ||
        !{'nes-front-loader', 'nes-top-loader'}.contains(profile['target']) ||
        profile['target'] == 'nes-top-loader' &&
            (style == null || !_standard(style)) ||
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
      if (profile['target'] == 'nes-front-loader') 'sourceTrayPivot'
    ]) {
      final point = profile[key];
      if (point is! List ||
          point.length != 3 ||
          point.any((v) => v is! num || !v.isFinite)) {
        throw const FormatException('NES launch slot anchor is absent');
      }
    }
    for (final key in profile['target'] == 'nes-front-loader'
        ? ['insertionPitch', 'trayPressRadians']
        : <String>[]) {
      final value = profile[key];
      if (value is! num || !value.isFinite || value.abs() > math.pi / 6) {
        throw const FormatException('NES launch tray angle is uncalibrated');
      }
    }
    if (profile['target'] == 'nes-top-loader' &&
        (profile['insertionMode'] != 'vertical' ||
            profile['bodyWidthCm'] != 15)) {
      throw const FormatException('NES-101 insertion calibration differs');
    }
    return Map<String, dynamic>.from(profile);
  }

  Future<SocketMediaModel> load() async {
    final base = await media.load(), hardware = await console.load();
    final profile = _profile(hardware, media.style);
    final screen = await display.load();
    final displayProfile = screen.data['launchDisplay'];
    if (displayProfile is! Map ||
        displayProfile['schema'] != 1 ||
        displayProfile['target'] != 'sony-kv1300e' ||
        displayProfile['sourceUnits'] != 'centimetres' ||
        displayProfile['physicalWidthCm'] != 47.4 ||
        displayProfile['geometrySha256'] != screen.data['geometrySha256'] ||
        !screen.surfaces
            .any((s) => s['node'] == displayProfile['screenNode'])) {
      throw const FormatException(
          'NES launch needs its calibrated external TV');
    }
    for (final key in ['sourceCenter', 'sourceScreenCenter']) {
      final point = displayProfile[key];
      if (point is! List ||
          point.length != 3 ||
          point.any((v) => v is! num || !v.isFinite)) {
        throw const FormatException('External TV anchor differs');
      }
    }
    if (displayProfile['sourceScale'] is! num ||
        !(displayProfile['sourceScale'] as num).isFinite ||
        (displayProfile['sourceScale'] as num) <= 0 ||
        displayProfile['sourceScreenSize'] is! List ||
        (displayProfile['sourceScreenSize'] as List).length != 2 ||
        (displayProfile['sourceScreenSize'] as List)
            .any((v) => v is! num || !v.isFinite || v <= 0)) {
      throw const FormatException('External TV physical scale differs');
    }
    final payload = BytesBuilder(copy: false);
    final surfaces = <Map<String, dynamic>>[];
    final bundles = <String, AssetBundle>{};
    for (final (group, model) in [
      ('media', base),
      ('console', hardware),
      ('display', screen)
    ]) {
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
    final bytes = payload.takeBytes();
    final model = SocketMediaModel.privateHardware({
      ...base.data,
      'name': 'nes-cartridge-console-launch-v1',
      'nesLaunch': true,
      if (initialViewport case final rect?)
        'launchInitialViewport': [rect.left, rect.top, rect.width, rect.height],
      'launchHardware': profile,
      'launchDisplay': displayProfile,
      'consoleGeometrySha256': hardware.data['geometrySha256'],
      'displayGeometrySha256': screen.data['geometrySha256'],
      'geometrySha256': sha256.convert(bytes).toString(),
      'surfaces': surfaces,
      'sourceReference': {
        'author': 'Owner-imported NES media, hardware and Sony display',
        'url': 'local:nes-launch/$identity',
        'licence': 'local-import-only',
        'sha256': sha256
            .convert(utf8.encode(jsonEncode([
              base.data['sourceReference'],
              hardware.data['sourceReference'],
              screen.data['sourceReference']
            ])))
            .toString(),
        'sources': [
          base.data['sourceReference'],
          hardware.data['sourceReference'],
          screen.data['sourceReference']
        ],
      },
    }, ByteData.sublistView(bytes), textureBundle: _LaunchTextures(bundles));
    // Fit the assembled composition from its actual transformed geometry.
    // Shared physical scale stays fixed; a larger TV changes camera framing.
    const workPose = SocketMediaPose(unboxing: 1, launch: .76);
    final view = vm.Matrix4.identity()
      ..rotateY(-.12)
      ..rotateX(.24);
    final low = vm.Vector2.all(double.infinity);
    final high = vm.Vector2.all(double.negativeInfinity);
    for (final surface in surfaces) {
      final transform = view * partTransform(model, surface, workPose);
      for (var i = 0; i < surface['vertexCount']; i++) {
        final offset = surface['vertexOffset'] + i * 32;
        final p = transform.transformed3(vm.Vector3(
            model.mesh.getFloat32(offset, Endian.little),
            model.mesh.getFloat32(offset + 4, Endian.little),
            model.mesh.getFloat32(offset + 8, Endian.little)));
        low.x = math.min(low.x, p.x);
        low.y = math.min(low.y, p.y);
        high.x = math.max(high.x, p.x);
        high.y = math.max(high.y, p.y);
      }
    }
    model.data['launchWorkSize'] = [high.x - low.x, high.y - low.y];
    model.data['launchWorkCenter'] = [
      (high.x + low.x) / 2,
      (high.y + low.y) / 2
    ];
    return model;
  }

  static double phase(double value, double begin, double end) {
    final t = ((value - begin) / (end - begin)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static bool visible(Map<String, dynamic> surface, SocketMediaPose p) =>
      p.launch > 0 || !{'console', 'display'}.contains(surface['launchPart']);

  static double opening(SocketMediaModel model, Map<String, dynamic> surface,
          SocketMediaPose p) =>
      surface['launchPart'] == 'console'
          ? phase(p.launch, 0, .18) *
              (model.data['launchHardware']['target'] == 'nes-top-loader'
                  ? 1
                  : 1 - phase(p.launch, .69, .76))
          : 0;

  static vm.Matrix4 _hardware(SocketMediaModel m) {
    final profile = m.data['launchHardware'] as Map;
    final sourceScale = (profile['sourceScale'] as num).toDouble();
    final center = (profile['sourceCenter'] as List).cast<num>();
    // One source centimetre has the same scene size for every hardware edition.
    // Fitting each body to an equal width would enlarge the smaller NES-101.
    const centimetre = 1.85 / 25.6;
    final scale = centimetre / sourceScale;
    final groundZ = (profile['controllerLayout']['groundZ'] as num).toDouble();
    return vm.Matrix4.identity()
      ..translateByDouble(-.65, -.8 - groundZ * centimetre, -.6, 1)
      ..scaleByDouble(scale, scale, scale, 1)
      ..translateByDouble(center[0] * sourceScale, center[1] * sourceScale,
          center[2] * sourceScale, 1);
  }

  static vm.Matrix4 _display(SocketMediaModel m) {
    final profile = m.data['launchDisplay'] as Map;
    final scale = (profile['sourceScale'] as num).toDouble();
    final center = (profile['sourceCenter'] as List).cast<num>();
    const centimetre = 1.85 / 25.6;
    return vm.Matrix4.identity()
      // TV stands to the left on the same support plane. Its nearest side
      // clears the front loader by about 5.5 cm; the console never blocks it.
      ..translateByDouble(-.65 - 42 * centimetre, -.8, -.6 + 12 * centimetre, 1)
      ..scaleByDouble(
          centimetre / scale, centimetre / scale, centimetre / scale, 1)
      ..translateByDouble(
          center[0] * scale, center[1] * scale, center[2] * scale, 1);
  }

  static vm.Vector3 screenCenter(SocketMediaModel m) {
    final profile = m.data['launchDisplay'] as Map;
    final point = (profile['sourceScreenCenter'] as List).cast<num>();
    final center = (profile['sourceCenter'] as List).cast<num>();
    final scale = (profile['sourceScale'] as num).toDouble();
    return _display(m).transformed3(vm.Vector3((point[0] - center[0]) * scale,
        (point[2] - center[1]) * scale, (-point[1] - center[2]) * scale));
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
      return vm.Matrix4.translationValues(0, 0, -3 * (1 - introduce))
        ..multiply(_display(m));
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
    final profile = m.data['launchHardware'] as Map;
    final vertical = profile['target'] == 'nes-top-loader';
    final press = vertical ? 0.0 : phase(t, .60, .69);
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
    final basis = vm.Matrix4.identity();
    if (!vertical) {
      basis
        ..setColumn(0, vm.Vector4(-1, 0, 0, 0))
        ..setColumn(1, vm.Vector4(0, 0, 1, 0))
        ..setColumn(2, vm.Vector4(0, 1, 0, 0));
    }
    final target = _hardware(m)
      ..translateByDouble(position.x, position.y, position.z, 1)
      ..rotateX(((profile['insertionPitch'] as num?) ?? 0) * (1 - press))
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
    final screen = screenCenter(m);
    final work = (m.data['launchWorkCenter'] as List).cast<num>();
    return vm.Matrix4.identity()
      ..translateByDouble(
          -(baseCenter.x * (1 - enter) +
              work[0] * enter * (1 - zoom) +
              screen.x * zoom),
          -(baseCenter.y * (1 - enter) +
              work[1] * enter * (1 - zoom) +
              screen.y * zoom),
          0,
          1)
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
    final workSize = (m.data['launchWorkSize'] as List).cast<num>();
    final work = math.min(width / workSize[0], height / workSize[1]) / 1.10;
    final enter = phase(p.launch, 0, .22), zoom = phase(p.launch, .82, 1);
    final screenSize =
        (m.data['launchDisplay']['sourceScreenSize'] as List).cast<num>();
    const centimetre = 1.85 / 25.6;
    final screen = 1.296 *
        math.max(width / (screenSize[0] * centimetre),
            height / (screenSize[1] * centimetre));
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
    if (surface['node'] != 'SonyCrtScreen') return original;
    final power = phase(p.launch, .76, .82);
    return {
      ...original,
      'textures': {...original['textures'] as Map}..remove('emission'),
      'sourceProperties': {
        ...original['sourceProperties'] as Map,
        'emission': [.025 * power, .032 * power, .028 * power],
      },
    };
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
