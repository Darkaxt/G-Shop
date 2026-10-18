import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:retro_eshop/models/packaging_model.dart';
import 'package:retro_eshop/models/socket_media_model.dart';
import 'package:retro_eshop/widgets/socket_media_renderer.dart';

void main() {
  test('box is six joined textured faces with no floating spine overlay', () {
    final model = PackagingModel(PackagingKind.box, aspect: .8).build();
    expect(model.surfaces.length, 6);
    final edges = <String, int>{};
    for (final face in model.surfaces) {
      expect(face['role'], 'label');
      final offset = face['vertexOffset'] as int;
      final points = List.generate(
          4,
          (i) => List.generate(
              3,
              (n) => model.mesh
                  .getFloat32(offset + i * 32 + n * 4, Endian.little)));
      for (var i = 0; i < 4; i++) {
        final ends = [points[i].toString(), points[(i + 1) % 4].toString()]
          ..sort();
        final key = ends.join('|');
        edges.update(key, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    expect(edges.length, 12);
    expect(edges.values, everyElement(2), reason: 'Each edge joins two faces');
  });
  test(
      'owned packaging has stable geometry identity and bounded named surfaces',
      () {
    for (final kind in PackagingKind.values) {
      final descriptor = PackagingModel(kind, aspect: .8);
      final model = descriptor.build();
      expect(model.data['ownedGeometry'], true);
      expect(model.data.containsKey('apkSha256'), false);
      expect(model.data['geometrySha256'],
          sha256.convert(model.mesh.buffer.asUint8List()).toString());
      expect(model.data['geometrySha256'],
          descriptor.build().data['geometrySha256']);
      expect(model.height, 2);
      expect(model.sourceWidth, 1.6);
      expect(model.data['canOpen'], kind != PackagingKind.box);
      expect(model.surfaces.where((s) => s['hinged'] == true).isNotEmpty,
          kind != PackagingKind.box);
      for (final s in model.surfaces) {
        for (var i = 0; i < (s['indexCount'] as int); i++) {
          expect(
              model.mesh
                  .getUint32((s['indexOffset'] as int) + i * 4, Endian.little),
              lessThan(s['vertexCount'] as int));
        }
        final uniforms = SocketMediaGpu.materialUniforms(
            s['material'] as Map<String, dynamic>,
            plasticHousing: true);
        expect(uniforms[5], 0, reason: 'Ordinary packaging is not metal');
        expect(uniforms[19], 1);
      }
    }
  });
  test(
      'panel aspect affects geometry, not an unfolded sheet or imported identity',
      () {
    final wide = PackagingModel(PackagingKind.box, aspect: 1.2).build();
    final narrow = PackagingModel(PackagingKind.box, aspect: .5).build();
    expect(wide.sourceWidth / narrow.sourceWidth, 2.4);
    expect(wide.height, narrow.height);
    expect(wide.data['geometrySha256'], isNot(narrow.data['geometrySha256']));
    expect(() => PackagingModel(PackagingKind.keepCase, aspect: double.nan),
        throwsFormatException);
    expect(() => PackagingModel(PackagingKind.box, depth: 0),
        throwsFormatException);
    expect(() => SocketMediaModel.owned({'apkSha256': 'fake'}, ByteData(0)),
        throwsFormatException);
  });
  test('spine art lies outside the case hinge rather than underneath it', () {
    final model = PackagingModel(PackagingKind.keepCase).build();
    final spine = model.surfaces.singleWhere((s) => s['name'] == 'spine');
    final x =
        model.mesh.getFloat32(spine['vertexOffset'] as int, Endian.little);
    expect(x, lessThan(-.72 - .018));
    expect(spine['role'], 'label');
  });
}
