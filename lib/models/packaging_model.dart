import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'socket_media_model.dart';

enum PackagingKind { box, keepCase, jewelCase, booklet }

/// Owned, parameterized geometry. Never masquerades as an imported Socket asset.
/// The manually controlled hinge is independent of the later cinematic timeline.
class PackagingModel {
  final PackagingKind kind;
  final double aspect, depth;
  final String? systemId;
  final Directory? modelsDirectory;
  PackagingModel(this.kind,
      {this.aspect = .72, double? depth, this.systemId, this.modelsDirectory})
      : depth = depth ?? (kind == PackagingKind.booklet ? .025 : .14) {
    if (!aspect.isFinite ||
        aspect < .25 ||
        aspect > 2.5 ||
        !this.depth.isFinite ||
        this.depth <= 0 ||
        this.depth > 1) {
      throw const FormatException('Invalid packaging dimensions');
    }
  }
  bool get canOpen => kind != PackagingKind.box;
  String get id => 'rshop-${kind.name}-v1';

  Future<SocketMediaModel> load() async {
    Map<String, dynamic> data;
    ByteData source;
    final local = modelsDirectory ??
        (Platform.isAndroid
            ? Directory('/storage/emulated/0/RShop/models')
            : null);
    final name = kind == PackagingKind.box && systemId != null
        ? 'cartons/$systemId/model'
        : 'booklet';
    final manifest = local == null ? null : File('${local.path}/$name.json');
    if ((kind == PackagingKind.booklet ||
            kind == PackagingKind.box && systemId != null) &&
        manifest != null &&
        await manifest.exists()) {
      final mesh = File('${local!.path}/$name.mesh');
      if (await manifest.length() > 1024 * 1024 ||
          await mesh.length() > 20 * 1024 * 1024) {
        throw const FormatException('Local model exceeds import size');
      }
      data = jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      source = ByteData.sublistView(await mesh.readAsBytes());
      SocketMediaModel.privatePackaging(data, source);
    } else if (kind == PackagingKind.box) {
      data = jsonDecode(
              await rootBundle.loadString('assets/packaging/cardboard.json'))
          as Map<String, dynamic>;
      source = await rootBundle.load('assets/packaging/cardboard.mesh');
      SocketMediaModel.packaging(data, source);
    } else {
      return build();
    }
    // Verify the conversion before deriving selected dimensions/normal matrices.
    final bytes = ByteData.sublistView(Uint8List.fromList(
        source.buffer.asUint8List(source.offsetInBytes, source.lengthInBytes)));
    if (kind == PackagingKind.box &&
        systemId == 'gba' &&
        data['cartridgeSlot'] is Map &&
        data['openingSide'] != 'right') {
      _rightOpening(data, bytes);
    }
    for (final raw in data['surfaces'] as List) {
      final surface = raw as Map;
      for (final hinge in surface['openingHinges'] as List? ?? const []) {
        final pivot = (hinge['pivot'] as List).cast<num>();
        hinge['pivot'] = [pivot[0] * aspect, pivot[1], pivot[2] * depth / 2];
      }
      if (surface['pivot'] is List) {
        final pivot = (surface['pivot'] as List).cast<num>();
        surface['pivot'] = [pivot[0] * aspect, pivot[1], pivot[2] * depth / 2];
      }
      for (var i = 0; i < surface['vertexCount']; i++) {
        final offset = (surface['vertexOffset'] as int) + i * 32;
        final scales = [aspect, 1.0, depth / 2];
        var length = 0.0;
        for (var axis = 0; axis < 3; axis++) {
          bytes.setFloat32(
              offset + axis * 4,
              bytes.getFloat32(offset + axis * 4, Endian.little) * scales[axis],
              Endian.little);
          final n = bytes.getFloat32(offset + 12 + axis * 4, Endian.little) /
              scales[axis];
          bytes.setFloat32(offset + 12 + axis * 4, n, Endian.little);
          length += n * n;
        }
        length = math.sqrt(length);
        for (var axis = 0; axis < 3; axis++) {
          final n = offset + 12 + axis * 4;
          bytes.setFloat32(
              n, bytes.getFloat32(n, Endian.little) / length, Endian.little);
        }
      }
    }
    data['bounds'] = [aspect * 2, 2, depth];
    data['sourceWidth'] = aspect * 2;
    data['geometrySha256'] =
        sha256.convert(bytes.buffer.asUint8List()).toString();
    return data['privateImport'] == true
        ? SocketMediaModel.privatePackaging(data, bytes)
        : SocketMediaModel.packaging(data, bytes);
  }

  /// The supplied holder carton was authored with its opening at +Y. The
  /// intended retail orientation has that opening at +X. Rotate the assembly,
  /// not just its printing: pivots, axes and fitting bounds travel with it.
  static void _rightOpening(Map<String, dynamic> data, ByteData bytes) {
    List<double> turn(List p) => [
          (p[1] as num).toDouble(),
          -(p[0] as num).toDouble(),
          (p[2] as num).toDouble()
        ];
    for (final surface in (data['surfaces'] as List).cast<Map>()) {
      for (final hinge in surface['openingHinges'] as List? ?? const []) {
        hinge['pivot'] = turn(hinge['pivot'] as List);
        hinge['axis'] = turn(hinge['axis'] as List);
      }
      if (surface['pivot'] is List)
        surface['pivot'] = turn(surface['pivot'] as List);
      final cell = surface['atlasCell'] as int?;
      final mapped = cell == null ? null : [0, 1, 5, 4, 3, 2][cell];
      if (mapped != null) surface['atlasCell'] = mapped;
      for (var i = 0; i < surface['vertexCount']; i++) {
        final offset = (surface['vertexOffset'] as int) + i * 32;
        for (final start in [0, 12]) {
          final x = bytes.getFloat32(offset + start, Endian.little);
          final y = bytes.getFloat32(offset + start + 4, Endian.little);
          bytes.setFloat32(offset + start, y, Endian.little);
          bytes.setFloat32(offset + start + 4, -x, Endian.little);
        }
        if (surface['role'] == 'label' && mapped != null) {
          final x = bytes.getFloat32(offset, Endian.little),
              y = bytes.getFloat32(offset + 4, Endian.little),
              z = bytes.getFloat32(offset + 8, Endian.little);
          final u = switch (mapped) {
            0 || 4 || 5 => (x + 1) / 2,
            1 => (1 - x) / 2,
            2 => (z + 1) / 2,
            _ => (1 - z) / 2,
          };
          final v = switch (mapped) {
            4 => (z + 1) / 2,
            5 => (1 - z) / 2,
            _ => (1 - y) / 2,
          };
          bytes.setFloat32(
              offset + 24, (mapped % 3 + u.clamp(0, 1)) / 3, Endian.little);
          bytes.setFloat32(
              offset + 28, (mapped ~/ 3 + v.clamp(0, 1)) / 2, Endian.little);
        }
      }
    }
    final slot = data['cartridgeSlot'] as Map;
    slot['fitCenter'] = turn(slot['fitCenter'] as List);
    final fit = (slot['fitBounds'] as List).cast<List>();
    slot['fitBounds'] = [
      [fit[0][1], -(fit[1][0] as num), fit[0][2]],
      [fit[1][1], -(fit[0][0] as num), fit[1][2]]
    ];
    slot['orientation'] = 'landscape';
    for (final field in ['fitSizeMm', 'clearPocketMm', 'clearanceMm']) {
      final p = slot[field] as List?;
      if (p != null) slot[field] = [p[1], p[0], p[2]];
    }
    data['openingSide'] = 'right';
  }

  SocketMediaModel build() {
    final bytes = BytesBuilder(copy: false);
    final surfaces = <Map<String, dynamic>>[];
    final w = aspect, h = 1.0, d = depth / 2;
    final paper = kind == PackagingKind.box || kind == PackagingKind.booklet;
    final tint = paper ? .34 : .075;
    void face(String name, List<List<double>> points, List<double> normal,
        {int? art, bool hinged = false}) {
      final offset = bytes.length;
      final vertices = ByteData(4 * 32);
      final col = (art ?? 0) % 3, row = (art ?? 0) ~/ 3;
      final uvs = [
        [0.0, 1.0],
        [1.0, 1.0],
        [1.0, 0.0],
        [0.0, 0.0]
      ];
      for (var i = 0; i < 4; i++) {
        final values = [
          ...points[i],
          ...normal,
          (col + uvs[i][0]) / 3,
          (row + uvs[i][1]) / 2
        ];
        for (var n = 0; n < 8; n++) {
          vertices.setFloat32(i * 32 + n * 4, values[n], Endian.little);
        }
      }
      bytes.add(vertices.buffer.asUint8List());
      final indices = ByteData(24);
      const order = [0, 1, 2, 0, 2, 3];
      for (var i = 0; i < 6; i++) {
        indices.setUint32(i * 4, order[i], Endian.little);
      }
      bytes.add(indices.buffer.asUint8List());
      surfaces.add({
        'node': id,
        'name': name,
        'role': art == null ? 'shell' : 'label',
        if (art != null) 'atlasCell': art,
        'vertexOffset': offset,
        'vertexCount': 4,
        'indexOffset': offset + 128,
        'indexCount': 6,
        'hinged': hinged,
        'pivot': [-w, 0, 0],
        'spinAxis': [0, 1, 0],
        'material': {
          'color': [tint, tint, tint, 1.0],
          'sourceProperties': {'roughness': 1.0, 'metallic': 0.0},
          'textures': <String, String>{}
        }
      });
    }

    void slab(String name, double x0, double x1, double y0, double y1,
        double z0, double z1,
        {bool hinged = false,
        int? front,
        int? back,
        int? left,
        int? right,
        int? top,
        int? bottom}) {
      face(
          '$name/front',
          [
            [x0, y0, z1],
            [x1, y0, z1],
            [x1, y1, z1],
            [x0, y1, z1]
          ],
          [0, 0, 1],
          art: front,
          hinged: hinged);
      face(
          '$name/back',
          [
            [x1, y0, z0],
            [x0, y0, z0],
            [x0, y1, z0],
            [x1, y1, z0]
          ],
          [0, 0, -1],
          art: back,
          hinged: hinged);
      face(
          '$name/left',
          [
            [x0, y0, z0],
            [x0, y0, z1],
            [x0, y1, z1],
            [x0, y1, z0]
          ],
          [-1, 0, 0],
          art: left,
          hinged: hinged);
      face(
          '$name/right',
          [
            [x1, y0, z1],
            [x1, y0, z0],
            [x1, y1, z0],
            [x1, y1, z1]
          ],
          [1, 0, 0],
          art: right,
          hinged: hinged);
      face(
          '$name/top',
          [
            [x0, y1, z1],
            [x1, y1, z1],
            [x1, y1, z0],
            [x0, y1, z0]
          ],
          [0, 1, 0],
          art: top,
          hinged: hinged);
      face(
          '$name/bottom',
          [
            [x0, y0, z0],
            [x1, y0, z0],
            [x1, y0, z1],
            [x0, y0, z1]
          ],
          [0, -1, 0],
          art: bottom,
          hinged: hinged);
    }

    if (kind == PackagingKind.box) {
      slab('outer', -w, w, -h, h, -d, d,
          front: 0, back: 1, left: 2, right: 3, top: 4, bottom: 5);
    } else {
      // Separate lid/tray and hinge: opening exposes real empty internal space,
      // not a rotated solid block. It makes no original-platform holder claim.
      const wall = .018;
      slab('lid', -w, w, -h, h, d - wall, d,
          hinged: true,
          front: 0,
          back: kind == PackagingKind.booklet ? 2 : null);
      slab('tray', -w, w, -h, h, -d, -d + wall,
          back: 1, front: kind == PackagingKind.booklet ? 3 : null);
      slab('tray/right', w - wall, w, -h, h, -d, 0);
      slab('tray/top', -w, w, h - wall, h, -d, 0);
      slab('tray/bottom', -w, w, -h, -h + wall, -d, 0);
      slab('hinge', -w - wall, -w + wall, -h, h, -d, d);
      // The lid rim stops short of the tray rim, leaving the opening divider.
      if (kind != PackagingKind.booklet) {
        slab('lid/right', w - wall, w, -h, h, .008, d, hinged: true);
        slab('lid/top', -w, w, h - wall, h, .008, d, hinged: true);
        slab('lid/bottom', -w, w, -h, -h + wall, .008, d, hinged: true);
        if (systemId == 'gba') {
          // Generic GBA protector: a 60 x 35.5 mm footprint, not a fabricated
          // original retail tray. Keep wall thickness independent of face aspect.
          final slotW = math.min(w * .72, .55),
              slotH = math.min(h * .38, math.min(w * .72, .55) / (60 / 35.5));
          final z0 = -d + wall, z1 = math.min(0.0, -d + wall + .035);
          const y = -.2;
          slab('gba-holder/left', -slotW - wall, -slotW, y - slotH, y + slotH,
              z0, z1);
          slab('gba-holder/right', slotW, slotW + wall, y - slotH, y + slotH,
              z0, z1);
          slab('gba-holder/bottom', -slotW, slotW, y - slotH - wall, y - slotH,
              z0, z1);
          slab('gba-holder/top-left', -slotW, -slotW * .35, y + slotH,
              y + slotH + wall, z0, z1);
          slab('gba-holder/top-right', slotW * .35, slotW, y + slotH,
              y + slotH + wall, z0, z1);
          slab('manual-clip/top', -w + .06, -w + .14, .50, .68, d - .06,
              d - wall,
              hinged: true);
          slab('manual-clip/bottom', -w + .06, -w + .14, -.68, -.50, d - .06,
              d - wall,
              hinged: true);
        }
      }
    }
    // Actual side artwork is a separate surface, never stretched front art.
    if (kind != PackagingKind.box) {
      final spineX = -w - .019;
      face(
          'spine',
          [
            [spineX, -h, -d],
            [spineX, -h, d],
            [spineX, h, d],
            [spineX, h, -d]
          ],
          [-1, 0, 0],
          art: 2);
    }
    final payload = bytes.takeBytes();
    return SocketMediaModel.owned({
      'name': id,
      'motionKind': 'packaging',
      'ownedGeometry': true,
      'geometrySha256': sha256.convert(payload).toString(),
      'bounds': [w * 2, 2, depth],
      'sourceWidth': w * 2,
      'labelAspect': 1.5,
      'frontSign': 1,
      'sourceRootTransform': [1, 0, 0, 0, 1, 0, 0, 0, 1],
      'canOpen': canOpen,
      'maxOpenRadians': canOpen ? math.pi * .72 : 0,
      'surfaces': surfaces,
    }, ByteData.sublistView(payload));
  }
}
