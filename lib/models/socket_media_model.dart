import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

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
      'gbc' =>
        dualMode?.toLowerCase() == 'no' ? gameBoyColorDual : gameBoyColor,
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
  static const assetRoot = 'assets/socket_media/';
  static const apkSha256 =
      'bccf6bf5beccf5155645638e52a20f6e6e6deed902bd23b6b69ae7060c04bd70';
  final Map<String, dynamic> data;
  final ByteData mesh;
  SocketMediaModel._(this.data, this.mesh);

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

  static Future<SocketMediaModel> load(PhysicalMediaFormat format,
      {AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
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
  final double rx, ry, rz, y, z, scaleX, scaleY, scaleZ, labelSpin;
  const SocketMediaPose(
      {this.rx = 0,
      this.ry = 0,
      this.rz = 0,
      this.y = 0,
      this.z = 0,
      this.scaleX = 1,
      this.scaleY = 1,
      this.scaleZ = 1,
      this.labelSpin = 0});

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
      bool reducedMotion = false}) {
    const degrees = math.pi / 180;
    final chosen = reducedMotion ? 1.0 : _expoOut(selected);
    var rx = _mix(-90, 20, chosen) * degrees;
    var rz = _mix(90, 20, chosen) * degrees;
    var ry = manualRotation, y = -(1 - chosen) * .816, z = -(1 - chosen) * .64;
    var sx = _mix(1 / 1.4, 1, chosen), sy = sx, sz = sx, spin = 0.0;
    if (!reducedMotion && insertion == 0) {
      y -= math.sin(seconds * 2.5) * .08 * .32;
      rx += math.sin(seconds * 1.5) * 3 * degrees;
      ry += math.cos(seconds * 1.5 * .8) * 1.5 * degrees;
      rz += math.sin(seconds * 1.5 * 1.2) * 2.4 * degrees;
    }
    if (insertion > 0) {
      final t = insertion;
      final turn = _phase(t, 0, .2);
      rx *= 1 - turn;
      rz *= 1 - turn;
      ry = kind == 'umd' || kind == 'disc'
          ? ry * (1 - turn)
          : _mix(ry, math.pi * 2, turn);
      y = -.5 * .32 * _backOut(_phase(t, 0, .15));
      z = -.2 * .32 * _backOut(_phase(t, 0, .15));
      final spinEnd = kind == 'disc' ? .3 : .2;
      spin = kind == 'disc'
          ? math.pi * 4 * _phase(t, 0, .3)
          : kind == 'umd'
              ? math.pi * 6 * turn
              : 0;
      if (t > spinEnd) {
        final click = kind == 'pushClick';
        final landDuration = click ? .2 : .3;
        final target = kind == 'disc'
            ? (2.5 + .45) * .32
            : click
                ? (3.8 + .45) * .32
                : (3.5 + .45) * .32;
        final landing = _expoIn(_phase(t, spinEnd, landDuration));
        y = _mix(-.5 * .32, target, landing);
        z = _mix(-.2 * .32, 0, landing);
        final landed = spinEnd + landDuration;
        if (click && t > landed) {
          y = _mix(target, (3.4 + .45) * .32, _backOut(_phase(t, landed, .12)));
          sx = sy = sz = _mix(1, 1, _elasticOut(_phase(t, landed, .25)));
          if (t > landed + .25) {
            y = (3.4 + .45) * .32 +
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
            y = target + .32 * _phase(t, landed + .2, .8);
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
        labelSpin: spin);
  }
}
