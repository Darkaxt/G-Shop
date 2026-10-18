import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:retro_eshop/models/packaging_model.dart';
import 'package:retro_eshop/models/socket_media_model.dart';
import 'package:retro_eshop/widgets/socket_media_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final actualBooklet = Platform.environment['RSHOP_BOOKLET_MODEL_DIR'];
  test('owner-exported booklet fits each page aspect without corrupting UVs',
      () async {
    for (final aspect in [.75, 1.0, 4 / 3]) {
      final model = await PackagingModel(PackagingKind.booklet,
              aspect: aspect,
              depth: .025,
              modelsDirectory: Directory(actualBooklet!))
          .load();
      expect(model.name, 'brochure-booklet-v1');
      expect(model.data['originalTriangles'], 77756);
      expect(model.triangles, greaterThan(77756));
      expect(model.data['sourceReference']['sha256'],
          'e7e86e5833deb8c5b2580166ef5eb7800a52f832078f32027e2eaf402d14808a');
      expect(model.surfaces.where((s) => s['hinged'] == true), hasLength(2));
      expect(
          SocketMediaGpu.windingOrder(model), gpu.WindingOrder.counterClockwise,
          reason: 'Outward cover faces must survive native back-face culling');
      for (final s in model.surfaces) {
        if (s['role'] != 'label') continue;
        final cell = s['atlasCell'] as int;
        for (var i = 0; i < s['vertexCount']; i++) {
          final n = (s['vertexOffset'] as int) + i * 32;
          final x = model.mesh.getFloat32(n, Endian.little);
          final y = model.mesh.getFloat32(n + 4, Endian.little);
          final u = model.mesh.getFloat32(n + 24, Endian.little) * 3 - cell % 3;
          final v =
              model.mesh.getFloat32(n + 28, Endian.little) * 2 - cell ~/ 3;
          expect(x.abs(), lessThanOrEqualTo(aspect + .00001));
          expect(y.abs(), lessThanOrEqualTo(1.00001));
          expect(u, inInclusiveRange(-.00001, 1.00001));
          expect(v, inInclusiveRange(-.00001, 1.00001));
        }
      }
    }
  },
      skip: actualBooklet == null
          ? 'Requires the owner-provided local GLB conversion'
          : false);
  test('local booklet uses verified source mesh, fitted dimensions and hinge',
      () async {
    final directory =
        Directory('D:/Temp/rshop-s25-booklet-20261018/test-model');
    await directory.create(recursive: true);
    final source = PackagingModel(PackagingKind.booklet).build();
    final payload = source.mesh.buffer.asUint8List();
    final data = Map<String, dynamic>.from(source.data)
      ..remove('ownedGeometry')
      ..addAll({
        'name': 'brochure-booklet-v1',
        'packagingGeometry': true,
        'privateImport': true,
        'bounds': [2, 2, 2],
        'sourceWidth': 2,
        'sourceReference': {
          'url': 'https://sketchfab.com/3d-models/example',
          'author': 'Fixture author',
          'licence': 'local-import-only',
          'sha256': 'a' * 64
        },
      });
    await File('${directory.path}/booklet.json')
        .writeAsString(jsonEncode(data));
    await File('${directory.path}/booklet.mesh').writeAsBytes(payload);
    final model = await PackagingModel(PackagingKind.booklet,
            aspect: 1.25, depth: .04, modelsDirectory: directory)
        .load();
    expect(model.name, 'brochure-booklet-v1');
    expect(model.data['privateImport'], true);
    expect(model.data['ownedGeometry'], isNot(true));
    expect(model.data['bounds'], [2.5, 2, .04]);
    expect(model.surfaces.where((s) => s['hinged'] == true), isNotEmpty);
    expect(model.surfaces.first['pivot'][0], closeTo(-.9, .00001));
    await File('${directory.path}/booklet.mesh').writeAsBytes([0]);
    await expectLater(
        PackagingModel(PackagingKind.booklet, modelsDirectory: directory)
            .load(),
        throwsFormatException);
  });
  test(
      'attributed cardboard preserves mesh detail and parameterized dimensions',
      () async {
    final model =
        await PackagingModel(PackagingKind.box, aspect: 1, depth: .34).load();
    expect(model.triangles, 12000);
    expect(model.surfaces, hasLength(6));
    expect(model.data['ownedGeometry'], isNot(true));
    expect(model.data['sourceReference']['licence'], 'CC-BY-4.0');
    expect(model.data['canOpen'], false);
    expect(model.data['bounds'], [2.0, 2, .34]);
    final transform =
        SocketMediaGpu.modelTransform(model, const SocketMediaPose());
    for (var row = 0; row < 4; row++) {
      for (var column = 0; column < 4; column++) {
        expect(transform.entry(row, column), row == column ? 1 : 0,
            reason:
                'Converted packaging is already Y-up; no Socket reflection');
      }
    }
    for (final surface in model.surfaces) {
      for (var i = 0; i < surface['vertexCount']; i++) {
        final offset = (surface['vertexOffset'] as int) + i * 32;
        final x = model.mesh.getFloat32(offset, Endian.little);
        final y = model.mesh.getFloat32(offset + 4, Endian.little);
        final z = model.mesh.getFloat32(offset + 8, Endian.little);
        expect(x.abs(), lessThanOrEqualTo(1.00001));
        expect(y.abs(), lessThanOrEqualTo(1.00001));
        expect(z.abs(), lessThanOrEqualTo(.17001));
        var length = 0.0;
        for (var axis = 0; axis < 3; axis++) {
          final n =
              model.mesh.getFloat32(offset + 12 + axis * 4, Endian.little);
          length += n * n;
        }
        expect(length, closeTo(1, .00001));
      }
    }
  });
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
