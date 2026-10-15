import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Converts factual source spans from the user's APK into indexed GPU buffers.
/// The recipe contains no geometry. Source bytes must be decrypted/decompressed
/// and hash checked by the import boundary before reaching this converter.
ByteData convertSocketMesh(
    Map<String, dynamic> model, Map<String, ByteData> resources) {
  final surfaces = (model['surfaces'] as List).cast<Map<String, dynamic>>();
  final size = surfaces.fold<int>(
      0,
      (size, s) => math.max(
          size, (s['indexOffset'] as int) + (s['indexCount'] as int) * 4));
  final output = ByteData(size);
  final center = (model['normalizationCenter'] as List).cast<num>();
  final width = (model['sourceWidth'] as num).toDouble();
  if (!width.isFinite || width <= 0) {
    throw const FormatException('Invalid model width');
  }
  for (final surface in surfaces) {
    final source = surface['import'] as Map<String, dynamic>;
    final resource = resources[source['member']];
    if (resource == null) {
      throw const FormatException('Missing source resource');
    }
    final resourceBytes = resource.buffer
        .asUint8List(resource.offsetInBytes, resource.lengthInBytes);
    if (sha256.convert(resourceBytes).toString() != source['resourceSha256']) {
      throw const FormatException('Source resource checksum mismatch');
    }
    ByteData span(String name) {
      final item = source['spans'][name] as Map<String, dynamic>;
      final offset = item['offset'] as int, length = item['length'] as int;
      if (offset < 0 ||
          length < 0 ||
          offset + length > resource.lengthInBytes) {
        throw const FormatException('Source span out of bounds');
      }
      final bytes =
          Uint8List.sublistView(resourceBytes, offset, offset + length);
      if (sha256.convert(bytes).toString() != item['sha256']) {
        throw const FormatException('Source buffer checksum mismatch');
      }
      return ByteData.sublistView(bytes);
    }

    final vertices = span('vertex_data'), attributes = span('attribute_data');
    final indices = span('index_data');
    final count = surface['vertexCount'] as int,
        indexCount = surface['indexCount'] as int;
    final format = source['format'] as int;
    final compressed = (format & 0x20000000) != 0;
    final positionStride = compressed ? 8 : 12;
    final normalStride = vertices.lengthInBytes ~/ count - positionStride;
    final attributeStride = attributes.lengthInBytes ~/ count;
    final bounds = (source['aabb'] as List).cast<num>();
    final uvScale = (source['uvScale'] as List).cast<num>();
    final matrix = (surface['sourceTransform'] as List).cast<num>();
    final positions = <List<double>>[],
        normals = <List<double>>[],
        uvs = <List<double>>[];
    for (var i = 0; i < count; i++) {
      final position = [
        for (var c = 0; c < 3; c++)
          compressed
              ? bounds[c].toDouble() +
                  vertices.getUint16(i * 8 + c * 2, Endian.little) /
                      65535 *
                      bounds[c + 3]
              : vertices.getFloat32(i * 12 + c * 4, Endian.little)
      ];
      final transformed = _point(matrix, position);
      positions.add([
        (transformed[0] - center[0]) / width,
        (-transformed[1] - center[1]) / width,
        (transformed[2] - center[2]) / width
      ]);
      if ((format & 2) == 0) {
        throw const FormatException('Source normal data missing');
      }
      final normalOffset = count * positionStride + i * normalStride;
      var normal = _octNormal(
          vertices.getUint16(normalOffset, Endian.little) / 65535,
          vertices.getUint16(normalOffset + 2, Endian.little) / 65535);
      if (compressed) {
        final angle =
            (vertices.getUint16(i * 8 + 6, Endian.little) / 65535 * 2 - 1)
                    .abs() *
                math.pi;
        final x = normal[0], y = normal[1], z = normal[2];
        final cosine = math.cos(angle), sine = math.sin(angle);
        normal = [
          (1 - cosine) * z * x - sine * y,
          (1 - cosine) * z * y + sine * x,
          cosine + (1 - cosine) * z * z
        ];
      }
      final transformedNormal = _normal(matrix, normal);
      normals.add(
          [transformedNormal[0], -transformedNormal[1], transformedNormal[2]]);
      if ((format & 16) != 0) {
        final offset = i * attributeStride + ((format & 8) != 0 ? 4 : 0);
        uvs.add([
          for (var c = 0; c < 2; c++)
            compressed
                ? (uvScale.any((v) => v != 0)
                    ? (attributes.getUint16(offset + c * 2, Endian.little) /
                                65535 -
                            .5) *
                        uvScale[c]
                    : attributes.getUint16(offset + c * 2, Endian.little) /
                        65535)
                : attributes.getFloat32(offset + c * 4, Endian.little)
        ]);
      }
    }
    if (uvs.isEmpty) {
      if (model['name'] != 'vita') {
        throw const FormatException('Source UV data missing');
      }
      if (surface['role'] == 'label') {
        final low = [
          for (var c = 0; c < 2; c++)
            positions.map((p) => p[c]).reduce(math.min)
        ];
        final high = [
          for (var c = 0; c < 2; c++)
            positions.map((p) => p[c]).reduce(math.max)
        ];
        uvs.addAll(positions.map((p) => [
              for (var c = 0; c < 2; c++) (p[c] - low[c]) / (high[c] - low[c])
            ]));
        for (final uv in uvs) {
          uv[0] = 1 - uv[0];
        }
      } else {
        uvs.addAll(List.generate(count, (_) => [0, 0]));
      }
    }
    final vertexOffset = surface['vertexOffset'] as int;
    for (var i = 0; i < count; i++) {
      final values = [...positions[i], ...normals[i], ...uvs[i]];
      for (var c = 0; c < 8; c++) {
        if (!values[c].isFinite) {
          throw const FormatException('Non-finite source geometry');
        }
        output.setFloat32(
            vertexOffset + i * 32 + c * 4, values[c], Endian.little);
      }
    }
    final indexWidth = count <= 65536 ? 2 : 4;
    if (indices.lengthInBytes != indexCount * indexWidth ||
        indexCount % 3 != 0) {
      throw const FormatException('Invalid source topology size');
    }
    for (var i = 0; i < indexCount; i++) {
      final index = indexWidth == 2
          ? indices.getUint16(i * 2, Endian.little)
          : indices.getUint32(i * 4, Endian.little);
      if (index >= count) {
        throw const FormatException('Invalid source topology index');
      }
      output.setUint32(
          (surface['indexOffset'] as int) + i * 4, index, Endian.little);
    }
  }
  return output;
}

List<double> _point(List<num> matrix, List<double> value) => [
      for (var r = 0; r < 3; r++)
        List.generate(3, (c) => matrix[r * 3 + c] * value[c])
                .fold<num>(0, (a, b) => a + b)
                .toDouble() +
            matrix[9 + r]
    ];

List<double> _cross(List<num> a, List<num> b) => [
      (a[1] * b[2] - a[2] * b[1]).toDouble(),
      (a[2] * b[0] - a[0] * b[2]).toDouble(),
      (a[0] * b[1] - a[1] * b[0]).toDouble()
    ];

List<double> _unit(List<double> vector) {
  final length = math.sqrt(vector.fold<double>(0, (s, v) => s + v * v));
  if (length == 0 || !length.isFinite) {
    throw const FormatException('Invalid source normal');
  }
  return vector.map((v) => v / length).toList();
}

List<double> _normal(List<num> matrix, List<double> normal) {
  final columns = [
    for (var c = 0; c < 3; c++) [matrix[c], matrix[3 + c], matrix[6 + c]]
  ];
  final cofactors = [
    _cross(columns[1], columns[2]),
    _cross(columns[2], columns[0]),
    _cross(columns[0], columns[1])
  ];
  final determinant = List.generate(3, (i) => columns[0][i] * cofactors[0][i])
      .fold<num>(0, (a, b) => a + b);
  if (determinant.abs() < 1e-15) {
    throw const FormatException('Singular source transform');
  }
  return _unit([
    for (var r = 0; r < 3; r++)
      List.generate(3, (c) => cofactors[c][r] * normal[c])
              .fold<double>(0, (a, b) => a + b) /
          determinant
  ]);
}

List<double> _octNormal(double x, double y) {
  x = x * 2 - 1;
  y = y * 2 - 1;
  final z = 1 - x.abs() - y.abs();
  if (z < 0) {
    final oldX = x;
    x = (1 - y.abs()) * (x >= 0 ? 1 : -1);
    y = (1 - oldX.abs()) * (y >= 0 ? 1 : -1);
  }
  return _unit([x, y, z]);
}
