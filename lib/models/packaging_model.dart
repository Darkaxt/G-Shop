import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'socket_media_model.dart';

enum PackagingKind { box, keepCase, jewelCase, booklet }

/// Owned, parameterized geometry. Never masquerades as an imported Socket asset.
/// The manually controlled hinge is independent of the later cinematic timeline.
class PackagingModel {
  final PackagingKind kind;
  final double aspect, depth;
  PackagingModel(this.kind, {this.aspect = .72, double? depth})
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
        {bool hinged = false, int? front, int? back}) {
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
          hinged: hinged);
    }

    if (kind == PackagingKind.box) {
      slab('outer', -w, w, -h, h, -d, d, front: 0, back: 1);
    } else {
      // Separate lid/tray and hinge: opening exposes real empty internal space,
      // not a rotated solid block. It makes no original-platform holder claim.
      const wall = .018;
      slab('lid', -w, w, -h, h, d - wall, d, hinged: true, front: 0);
      slab('tray', -w, w, -h, h, -d, -d + wall, back: 1);
      slab('tray/right', w - wall, w, -h, h, -d, 0);
      slab('tray/top', -w, w, h - wall, h, -d, 0);
      slab('tray/bottom', -w, w, -h, -h + wall, -d, 0);
      slab('hinge', -w - wall, -w + wall, -h, h, -d, d);
      // The lid rim stops short of the tray rim, leaving the opening divider.
      if (kind != PackagingKind.booklet) {
        slab('lid/right', w - wall, w, -h, h, .008, d, hinged: true);
        slab('lid/top', -w, w, h - wall, h, .008, d, hinged: true);
        slab('lid/bottom', -w, w, -h, -h + wall, .008, d, hinged: true);
      }
    }
    // Actual side artwork is a separate surface, never stretched front art.
    final spineX = -w - (kind == PackagingKind.box ? .001 : .019);
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
