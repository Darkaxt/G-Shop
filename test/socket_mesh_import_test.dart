import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/services/socket_mesh_import.dart';

void main() {
  const fixtureRoot = String.fromEnvironment('RSHOP_SOCKET_IMPORT_FIXTURES');
  test('all owner APK mesh recipes reproduce the native-verified oracle', () {
    final recipe =
        jsonDecode(File('assets/socket_import_recipe.json').readAsStringSync())
            as Map;
    for (final model
        in (recipe['models'] as List).cast<Map<String, dynamic>>()) {
      final resources = <String, ByteData>{};
      for (final surface in model['surfaces'] as List) {
        final member = surface['import']['member'] as String;
        resources.putIfAbsent(
            member,
            () => ByteData.sublistView(
                File('$fixtureRoot/${sha256.convert(utf8.encode(member))}.bin')
                    .readAsBytesSync()));
      }
      final mesh = convertSocketMesh(model, resources);
      expect(sha256.convert(mesh.buffer.asUint8List()).toString(),
          model['meshSha256'],
          reason: model['name'] as String);
    }
  },
      skip: fixtureRoot.isEmpty
          ? 'Requires the owner APK private source fixtures'
          : false);
  test('APK mesh conversion uses source row-major transforms', () {
    final source = ByteData(78);
    for (var i = 0; i < 3; i++) {
      source.setFloat32(i * 12, 1, Endian.little);
      source.setUint16(36 + i * 4, 65535, Endian.little);
      source.setUint16(38 + i * 4, 32768, Endian.little);
      source.setUint16(72 + i * 2, i, Endian.little);
    }
    Map<String, Object> span(int offset, int length) => {
          'offset': offset,
          'length': length,
          'sha256': sha256
              .convert(source.buffer.asUint8List(offset, length))
              .toString(),
        };
    final model = <String, dynamic>{
      'name': 'gb',
      'normalizationCenter': [0, 0, 0],
      'sourceWidth': 1,
      'surfaces': [
        {
          'role': 'shell',
          'vertexOffset': 0,
          'vertexCount': 3,
          'indexOffset': 96,
          'indexCount': 3,
          'sourceTransform': [0, -1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0],
          'import': {
            'member': 'source',
            'resourceSha256':
                sha256.convert(source.buffer.asUint8List()).toString(),
            'spans': {
              'vertex_data': span(0, 48),
              'attribute_data': span(48, 24),
              'index_data': span(72, 6),
            },
            'format': 18,
            'aabb': [0, 0, 0, 1, 1, 1],
            'uvScale': [0, 0, 0, 0],
          }
        }
      ]
    };
    final converted = convertSocketMesh(model, {'source': source});
    expect(converted.getFloat32(0, Endian.little), 0);
    expect(converted.getFloat32(4, Endian.little), -1);
    expect(converted.getFloat32(16, Endian.little), closeTo(-1, .0001));
    expect(converted.getUint32(104, Endian.little), 2);
    source.setUint8(0, 1);
    expect(() => convertSocketMesh(model, {'source': source}),
        throwsFormatException);
  });
}
