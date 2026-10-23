import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

enum PhysicalMediaFormat {
  gameBoy('gb', 'Game Boy cartridge', 850),
  gameBoyColor('gbc', 'Game Boy Color cartridge', 850),
  gameBoyColorDual('gbc_dual_mode', 'Game Boy Color cartridge', 850),
  gba('gba', 'Game Boy Advance cartridge', 700),
  n64('n64', 'Nintendo 64 cartridge', 700),
  nes('nes', 'Nintendo Entertainment System cartridge', 850),
  snesPal('snes_pal', 'Super Nintendo cartridge', 700),
  snesUs('snes_us', 'Super Nintendo cartridge', 700),
  nds('nds', 'Nintendo DS game card', 850),
  n3ds('3ds', 'Nintendo 3DS game card', 850),
  switchCard('switch', 'Nintendo Switch game card', 850),
  genesis('genesis', 'Genesis cartridge', 850),
  megadrive('megadrive', 'Mega Drive cartridge', 850),
  psp('psp', 'PlayStation Portable UMD', 700),
  vita('vita', 'PlayStation Vita game card', 850),
  disc('disc', 'optical disc', 1600);

  final String assetName, description;
  final int insertionMilliseconds;
  const PhysicalMediaFormat(
      this.assetName, this.description, this.insertionMilliseconds);

  static PhysicalMediaFormat? forSystem(String systemId,
      {String? region, String? dualMode}) {
    final pal = {
      'eu',
      'europe',
      'uk',
      'united kingdom',
      'fr',
      'france',
      'de',
      'germany',
      'es',
      'spain',
      'it',
      'italy',
      'au',
      'australia',
      'jp',
      'japan',
      'pal'
    }.contains(region?.toLowerCase());
    return switch (systemId) {
      'gb' => gameBoy,
      // This is the actual (counterintuitively named) Socket binding.
      'gbc' => !{'jp', 'japan'}.contains(region?.toLowerCase()) &&
              dualMode?.toLowerCase() == 'no'
          ? gameBoyColorDual
          : gameBoyColor,
      'gba' => gba,
      'n64' => n64,
      'nes' => nes,
      'snes' => pal ? snesPal : snesUs,
      'nds' || 'dsi' => nds,
      'n3ds' => n3ds,
      'switch' => switchCard,
      'megadrive' => pal ? megadrive : genesis,
      'psp' => psp,
      'psvita' => vita,
      'psx' || 'ps2' || 'ps3' || 'dreamcast' || 'gc' || 'wii' || 'wiiu' => disc,
      _ => null,
    };
  }
}

/// Exact source triangles, UVs, material bindings and animation provenance.
/// GPU resources belong to the selected view, not a cache of every console.
class SocketMediaModel {
  static vm.Matrix4 openingTransform(
      Map<String, dynamic> surface, double opening) {
    final transform = vm.Matrix4.identity();
    for (final raw in surface['openingTranslations'] as List? ?? const []) {
      final keys = (raw['keys'] as List).cast<List>();
      final t = opening.clamp(0.0, 1.0);
      var value = (keys.last.sublist(1)).cast<num>();
      for (var i = 1; i < keys.length; i++) {
        final a = keys[i - 1], b = keys[i];
        if (t <= (b[0] as num)) {
          final f = ((t - (a[0] as num)) / ((b[0] as num) - (a[0] as num)))
              .clamp(0.0, 1.0);
          value = [
            for (var n = 1; n < 4; n++)
              (a[n] as num) + ((b[n] as num) - (a[n] as num)) * f
          ];
          break;
        }
      }
      transform.translateByDouble(
          value[0].toDouble(), value[1].toDouble(), value[2].toDouble(), 1);
    }
    for (final raw in surface['openingHinges'] as List? ?? const []) {
      final hinge = raw as Map;
      final keys = (hinge['keys'] as List).cast<List>();
      final t = opening.clamp(0.0, 1.0);
      var angle = (keys.last[1] as num).toDouble();
      for (var i = 1; i < keys.length; i++) {
        final a = keys[i - 1], b = keys[i];
        if (t <= (b[0] as num)) {
          final f = ((t - (a[0] as num)) / ((b[0] as num) - (a[0] as num)))
              .clamp(0.0, 1.0);
          angle =
              (a[1] as num).toDouble() + ((b[1] as num) - (a[1] as num)) * f;
          break;
        }
      }
      final p = (hinge['pivot'] as List).cast<num>();
      final a = (hinge['axis'] as List).cast<num>();
      transform
        ..translateByDouble(
            p[0].toDouble(), p[1].toDouble(), p[2].toDouble(), 1)
        ..rotate(vm.Vector3(a[0].toDouble(), a[1].toDouble(), a[2].toDouble()),
            angle)
        ..translateByDouble(
            -p[0].toDouble(), -p[1].toDouble(), -p[2].toDouble(), 1);
    }
    return transform;
  }

  static vm.Vector3 poseCenter(Map<String, dynamic> data, double opening) {
    final centers = data['poseCenters'] as List?;
    if (centers != null) {
      for (var i = 1; i < centers.length; i++) {
        final a = (centers[i - 1] as List).cast<num>();
        final b = (centers[i] as List).cast<num>();
        if (opening <= b[0] || i == centers.length - 1) {
          final f = ((opening - a[0]) / (b[0] - a[0])).clamp(0.0, 1.0);
          return vm.Vector3(
              a[1].toDouble() + (b[1] - a[1]) * f,
              a[2].toDouble() + (b[2] - a[2]) * f,
              a[3].toDouble() + (b[3] - a[3]) * f);
        }
      }
    }
    return vm.Vector3.zero();
  }

  static const assetRoot = 'assets/socket_media/';
  static AssetBundle? importedBundle;
  static const apkSha256 =
      'bccf6bf5beccf5155645638e52a20f6e6e6deed902bd23b6b69ae7060c04bd70';
  final Map<String, dynamic> data;
  final ByteData mesh;
  final AssetBundle? textureBundle;
  SocketMediaModel._(this.data, this.mesh, {this.textureBundle});

  /// App-owned geometry has an explicit, independent identity. Imported APK
  /// receipts/checksums remain enforced only by the original import path.
  factory SocketMediaModel.owned(Map<String, dynamic> data, ByteData mesh) {
    if (data['ownedGeometry'] != true || data.containsKey('apkSha256')) {
      throw const FormatException('Invalid owned geometry identity');
    }
    return SocketMediaModel._(data, mesh);
  }

  /// Attributed, converted packaging geometry is not an owned Socket resource.
  factory SocketMediaModel.packaging(Map<String, dynamic> data, ByteData mesh) {
    final source = data['sourceReference'];
    if (data['packagingGeometry'] != true ||
        data.containsKey('apkSha256') ||
        source is! Map ||
        source['licence'] != 'CC-BY-4.0' ||
        source['author'] is! String ||
        source['url'] is! String ||
        sha256
                .convert(mesh.buffer
                    .asUint8List(mesh.offsetInBytes, mesh.lengthInBytes))
                .toString() !=
            data['geometrySha256']) {
      throw const FormatException('Invalid attributed packaging geometry');
    }
    return SocketMediaModel._(data, mesh);
  }

  /// User-imported packaging is not bundled artwork or a redistribution grant.
  factory SocketMediaModel.privatePackaging(
      Map<String, dynamic> data, ByteData mesh,
      {AssetBundle? textureBundle}) {
    if (data['packagingGeometry'] != true || data['hardwareGeometry'] == true) {
      throw const FormatException('Invalid local packaging identity');
    }
    return SocketMediaModel._privateGeometry(data, mesh,
        textureBundle: textureBundle);
  }

  factory SocketMediaModel.privateHardware(
      Map<String, dynamic> data, ByteData mesh,
      {required AssetBundle textureBundle}) {
    if (data['hardwareGeometry'] != true || data['packagingGeometry'] == true) {
      throw const FormatException('Invalid local console identity');
    }
    return SocketMediaModel._privateGeometry(data, mesh,
        textureBundle: textureBundle);
  }

  /// The supplied 63-device overview has its own bounded draw/texture budget.
  /// Individual consoles and paired unboxing scenes keep their existing limits.
  static bool isGameWatchCollection(Map<String, dynamic> data) {
    final scene = data['selectorScene'];
    if (data['hardwareGeometry'] != true ||
        data['system'] != 'gameandwatch' ||
        data['romSet'] != null ||
        data['visualVariantId'] != null ||
        scene is! Map ||
        scene['kind'] != 'gamewatchCollection' ||
        scene['deviceCount'] != 63 ||
        scene['textureMaxDimension'] != 256) {
      return false;
    }
    final devices = scene['devices'], hidden = scene['hiddenNodes'];
    return devices is List &&
        devices.length == 63 &&
        devices.every(
            (v) => v is String && RegExp(r'^[a-z0-9_-]+$').hasMatch(v)) &&
        devices.toSet().length == 63 &&
        hidden is List &&
        hidden.length == 1 &&
        hidden.single == 'Display_board';
  }

  factory SocketMediaModel.privateCartridge(
      Map<String, dynamic> data, ByteData mesh,
      {AssetBundle? textureBundle}) {
    if (data['cartridgeGeometry'] != true ||
        data['hardwareGeometry'] == true ||
        data['packagingGeometry'] == true) {
      throw const FormatException('Invalid local cartridge identity');
    }
    return SocketMediaModel._privateGeometry(data, mesh,
        textureBundle: textureBundle);
  }

  factory SocketMediaModel._privateGeometry(
      Map<String, dynamic> data, ByteData mesh,
      {AssetBundle? textureBundle}) {
    final source = data['sourceReference'];
    if (data['privateImport'] != true ||
        data.containsKey('apkSha256') ||
        data.containsKey('ownedGeometry') ||
        source is! Map ||
        source['licence'] != 'local-import-only' ||
        source['author'] is! String ||
        source['url'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch('${source['sha256']}') ||
        sha256
                .convert(mesh.buffer
                    .asUint8List(mesh.offsetInBytes, mesh.lengthInBytes))
                .toString() !=
            data['geometrySha256']) {
      throw const FormatException('Invalid local packaging import');
    }
    final surfaces = data['surfaces'];
    // Twisted has 65 cartridge surfaces and the refined Panorama hardware has
    // up to 70. Paired scenes also include their separate carton/booklet parts.
    // An NES launch additionally retains its wired console and supplied TV.
    final surfaceBudget = isGameWatchCollection(data)
        ? 384
        : data['unboxingGeometry'] == true ||
                data['gameWatchUnboxing'] == true ||
                data['nesLaunch'] == true
            ? 192
            : data['cartridgeGeometry'] == true ||
                    data['hardwareGeometry'] == true
                ? 128
                : 64;
    if (surfaces is! List ||
        surfaces.isEmpty ||
        surfaces.length > surfaceBudget) {
      throw const FormatException('Invalid local packaging surfaces');
    }
    for (final s in surfaces) {
      final vo = s['vertexOffset'] as int, vc = s['vertexCount'] as int;
      final io = s['indexOffset'] as int, ic = s['indexCount'] as int;
      if (vo < 0 ||
          vc <= 0 ||
          io < vo + vc * 32 ||
          ic <= 0 ||
          ic % 3 != 0 ||
          io + ic * 4 > mesh.lengthInBytes) {
        throw const FormatException('Invalid local packaging range');
      }
      for (var i = 0; i < ic; i++) {
        if (mesh.getUint32(io + i * 4, Endian.little) >= vc) {
          throw const FormatException('Invalid local packaging index');
        }
      }
      final hinges = s['openingHinges'];
      final motions = s['openingTranslations'];
      if (motions != null) {
        if (motions is! List || motions.length > 16)
          throw const FormatException('Invalid assembly hierarchy');
        for (final motion in motions) {
          final keys = motion['keys'];
          if (keys is! List || keys.length < 2 || keys.length > 256)
            throw const FormatException('Invalid assembly keys');
          var previous = -1.0;
          for (final key in keys) {
            if (key is! List ||
                key.length != 4 ||
                key.any((v) => v is! num || !v.isFinite) ||
                key[0] <= previous ||
                key[0] < 0 ||
                key[0] > 1)
              throw const FormatException('Invalid assembly displacement');
            previous = (key[0] as num).toDouble();
          }
          if (keys.first[0] != 0 || keys.last[0] != 1)
            throw const FormatException('Incomplete assembly keys');
        }
      }
      if (hinges != null) {
        if (hinges is! List || hinges.length > 16) {
          throw const FormatException('Invalid local opening hierarchy');
        }
        for (final hinge in hinges) {
          for (final name in ['pivot', 'axis']) {
            final vector = hinge[name];
            if (vector is! List ||
                vector.length != 3 ||
                vector.any((v) => v is! num || !v.isFinite)) {
              throw const FormatException('Invalid opening vector');
            }
          }
          final axis = (hinge['axis'] as List).cast<num>();
          if (axis.fold<double>(0, (sum, v) => sum + v * v) < .000001) {
            throw const FormatException('Empty opening axis');
          }
          final keys = hinge['keys'];
          if (keys is! List || keys.length < 2 || keys.length > 256) {
            throw const FormatException('Invalid opening keyframes');
          }
          var previous = -1.0;
          for (final key in keys) {
            if (key is! List ||
                key.length != 2 ||
                key.any((v) => v is! num || !v.isFinite) ||
                key[0] <= previous ||
                key[0] < 0 ||
                key[0] > 1) {
              throw const FormatException('Unordered opening keyframes');
            }
            previous = (key[0] as num).toDouble();
          }
          if (keys.first[0] != 0 || keys.last[0] != 1) {
            throw const FormatException('Incomplete opening keyframes');
          }
        }
      }
    }
    return SocketMediaModel._(data, mesh, textureBundle: textureBundle);
  }

  String get name => data['name'] as String;
  String get motionKind => data['motionKind'] as String;
  double get height => (data['bounds'][1] as num).toDouble();
  double get sourceWidth => (data['sourceWidth'] as num).toDouble();
  double get labelAspect => (data['labelAspect'] as num).toDouble();
  int get frontSign => data['frontSign'] as int;
  List<Map<String, dynamic>> get surfaces =>
      (data['surfaces'] as List).cast<Map<String, dynamic>>();
  int get triangles =>
      surfaces.fold(0, (n, s) => n + (s['indexCount'] as int) ~/ 3);

  static Future<({Map<String, dynamic> data, ByteData pixels})> loadEnvironment(
      {AssetBundle? bundle}) async {
    final assets = bundle ?? importedBundle;
    if (assets == null) {
      throw StateError('Import the original APK before enabling 3D media');
    }
    final data =
        jsonDecode(await assets.loadString('${assetRoot}environment.json'))
            as Map<String, dynamic>;
    if (data['apkSha256'] != apkSha256 ||
        data['format'] != 'astc4x4HDR' ||
        data['width'] != 1024 ||
        data['height'] != 512) {
      throw const FormatException(
          'Physical-media environment identity mismatch');
    }
    final pixels = await assets.load('$assetRoot${data['file']}');
    if (sha256
            .convert(pixels.buffer
                .asUint8List(pixels.offsetInBytes, pixels.lengthInBytes))
            .toString() !=
        data['pixelsSha256']) {
      throw const FormatException(
          'Physical-media environment checksum mismatch');
    }
    final mips = data['mips'] as List;
    var offset = 0;
    if (mips.length != 11) {
      throw const FormatException('Incomplete environment mip chain');
    }
    for (var level = 0; level < mips.length; level++) {
      final w = math.max(1, 1024 >> level), h = math.max(1, 512 >> level);
      final length = ((w + 3) ~/ 4) * ((h + 3) ~/ 4) * 16;
      if (mips[level]['offset'] != offset || mips[level]['length'] != length) {
        throw const FormatException('Invalid environment mip range');
      }
      offset += length;
    }
    if (offset != pixels.lengthInBytes) {
      throw const FormatException('Invalid environment payload length');
    }
    return (data: data, pixels: pixels);
  }

  static Future<SocketMediaModel> load(PhysicalMediaFormat format,
      {AssetBundle? bundle}) async {
    final assets = bundle ?? importedBundle;
    if (assets == null) {
      throw StateError('Import the original APK before enabling 3D media');
    }
    final json = jsonDecode(
            await assets.loadString('$assetRoot${format.assetName}.json'))
        as Map<String, dynamic>;
    if (json['apkSha256'] != apkSha256 || json['name'] != format.assetName) {
      throw const FormatException('Physical-media source identity mismatch');
    }
    final bytes = await assets.load('$assetRoot${json['meshFile']}');
    if (sha256
            .convert(bytes.buffer
                .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes))
            .toString() !=
        json['meshSha256']) {
      throw const FormatException('Physical-media geometry checksum mismatch');
    }
    final result = SocketMediaModel._(json, bytes);
    for (final s in result.surfaces) {
      final vo = s['vertexOffset'] as int, vc = s['vertexCount'] as int;
      final io = s['indexOffset'] as int, ic = s['indexCount'] as int;
      if (vo < 0 ||
          vc <= 0 ||
          io < vo + vc * 32 ||
          ic <= 0 ||
          ic % 3 != 0 ||
          io + ic * 4 > bytes.lengthInBytes) {
        throw const FormatException('Invalid physical-media surface range');
      }
      for (var i = 0; i < ic; i++) {
        if (bytes.getUint32(io + i * 4, Endian.little) >= vc) {
          throw const FormatException('Invalid physical-media triangle index');
        }
      }
    }
    return result;
  }
}

/// Source tween phases in a fitted main-screen coordinate system. Geometry is
/// not reshaped; source translation units are scaled to fit this frontend.
class SocketMediaPose {
  final double rx,
      ry,
      rz,
      y,
      z,
      scaleX,
      scaleY,
      scaleZ,
      labelSpin,
      opening,
      unboxing,
      launch,
      inspection,
      pageFocus,
      pageAspect;
  final String? inspectedPart;
  // An overview composition supplies one shared physical camera scale.
  final double? cameraUnits, cameraCenterX, cameraCenterY;
  const SocketMediaPose(
      {this.rx = 0,
      this.ry = 0,
      this.rz = 0,
      this.y = 0,
      this.z = 0,
      this.scaleX = 1,
      this.scaleY = 1,
      this.scaleZ = 1,
      this.labelSpin = 0,
      this.opening = 0,
      this.unboxing = 0,
      this.launch = 0,
      this.inspectedPart,
      this.cameraUnits,
      this.cameraCenterX,
      this.cameraCenterY,
      this.inspection = 0,
      this.pageFocus = 0,
      this.pageAspect = 0});

  static double _phase(double t, double start, double duration) =>
      ((t - start) / duration).clamp(0.0, 1.0);
  static double _backOut(double t) =>
      1 + 2.70158 * math.pow(t - 1, 3) + 1.70158 * math.pow(t - 1, 2);
  static double _backInOut(double t) {
    const s = 1.70158 * 1.525;
    final x = t * 2;
    return x < 1
        ? x * x * ((s + 1) * x - s) / 2
        : ((x - 2) * (x - 2) * ((s + 1) * (x - 2) + s) + 2) / 2;
  }

  static double _expoIn(double t) => t == 0
      ? 0
      : t == 1
          ? 1
          : math.pow(2, 10 * (t - 1)).toDouble() - .001;
  static double _expoOut(double t) =>
      t == 1 ? 1 : 1.001 * (1 - math.pow(2, -10 * t));
  static double _elasticOut(double t) => t == 0 || t == 1
      ? t
      : math.pow(2, -10 * t) * math.sin((t - .075) * 2 * math.pi / .3) + 1;
  static double _mix(double a, double b, double t) => a + (b - a) * t;

  static SocketMediaPose sample(
      {required String kind,
      required double selected,
      required double seconds,
      double insertion = 0,
      double manualRotation = 0,
      double opening = 0,
      bool reducedMotion = false}) {
    const degrees = math.pi / 180;
    final chosen = reducedMotion ? 1.0 : _expoOut(selected);
    // Source Node3D angles; the renderer replaces the baked rest basis once.
    var rx = _mix(-180, -70, chosen) * degrees;
    var rz = _mix(90, 20, chosen) * degrees;
    var ry = manualRotation, y = (1 - chosen) * .816, z = (1 - chosen) * .64;
    var sx = _mix(1 / 1.4, 1, chosen), sy = sx, sz = sx, spin = 0.0;
    if (!reducedMotion && insertion == 0) {
      y += math.sin(seconds * 2.5) * .08 * .32;
      rx += math.sin(seconds * 1.5) * 3 * degrees;
      ry += math.cos(seconds * 1.5 * .8) * 1.5 * degrees;
      rz += math.sin(seconds * 1.5 * 1.2) * 2.4 * degrees;
    }
    if (insertion > 0) {
      final t = insertion;
      final turn = _phase(t, 0, .2);
      rx = _mix(rx, -math.pi / 2, turn);
      rz *= 1 - turn;
      ry = kind == 'umd' || kind == 'disc'
          ? ry * (1 - turn)
          : _mix(ry, math.pi * 2, turn);
      y = .5 * .32 * _backOut(_phase(t, 0, .15));
      z = .2 * .32 * _backOut(_phase(t, 0, .15));
      final spinEnd = kind == 'disc' ? .3 : .2;
      spin = kind == 'disc'
          ? math.pi * 4 * _phase(t, 0, .3)
          : kind == 'umd'
              ? math.pi * 6 * turn
              : 0;
      if (t > spinEnd) {
        final click = kind == 'pushClick';
        final landDuration = click ? .2 : .3;
        final target = -(kind == 'disc'
            ? (2.5 + .45) * .32
            : click
                ? (3.8 + .45) * .32
                : (3.5 + .45) * .32);
        final landing = _expoIn(_phase(t, spinEnd, landDuration));
        y = _mix(.5 * .32, target, landing);
        z = _mix(.2 * .32, 0, landing);
        final landed = spinEnd + landDuration;
        if (click && t > landed) {
          y = _mix(
              target, -(3.4 + .45) * .32, _backOut(_phase(t, landed, .12)));
          sx = sy = sz = _mix(1, 1, _elasticOut(_phase(t, landed, .25)));
          if (t > landed + .25) {
            y = -(3.4 + .45) * .32 -
                .4 * .32 * _backInOut(_phase(t, landed + .25, .2));
          }
        } else if (!click) {
          final squash = _phase(t, spinEnd, .05);
          sx = sz = _mix(1, 1.2 / 1.4, squash);
          sy = _mix(1, .7 / 1.4, squash);
          if (t > landed) {
            final settle = _elasticOut(_phase(t, landed, .2));
            sx = sz = _mix(1.2 / 1.4, 1, settle);
            sy = _mix(.7 / 1.4, 1, settle);
          }
          if (kind == 'disc' && t > landed + .2) {
            y = target - .32 * _phase(t, landed + .2, .8);
          }
        }
      }
    }
    return SocketMediaPose(
        rx: rx,
        ry: ry,
        rz: rz,
        y: y,
        z: z,
        scaleX: sx,
        scaleY: sy,
        scaleZ: sz,
        labelSpin: spin,
        opening: opening);
  }
}
