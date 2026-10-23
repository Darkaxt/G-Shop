import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

bool validMetadataPng(Uint8List bytes) {
  if (bytes.length < 57 ||
      bytes.length > 4 * 1024 * 1024 ||
      base64Encode(Uint8List.sublistView(bytes, 0, 8)) != 'iVBORw0KGgo=') {
    return false;
  }
  final data = ByteData.sublistView(bytes);
  var offset = 8;
  var imageData = false;
  while (offset + 12 <= bytes.length) {
    final length = data.getUint32(offset);
    final end = offset + length + 12;
    if (end > bytes.length) return false;
    final type =
        ascii.decode(bytes.sublist(offset + 4, offset + 8), allowInvalid: true);
    if (getCrc32(Uint8List.sublistView(bytes, offset + 4, end - 4)) !=
        data.getUint32(end - 4)) {
      return false;
    }
    if (offset == 8) {
      if (type != 'IHDR' || length != 13) return false;
      final width = data.getUint32(offset + 8);
      final height = data.getUint32(offset + 12);
      if (width < 1 || height < 1 || width > 1024 || height > 1024) {
        return false;
      }
    } else if (type == 'IHDR' || type == 'acTL') {
      return false; // No duplicate header or unbounded animation frames.
    }
    if (type == 'IDAT' && length > 0) imageData = true;
    if (type == 'IEND') {
      return length == 0 && imageData && end == bytes.length;
    }
    offset = end;
  }
  return false;
}
