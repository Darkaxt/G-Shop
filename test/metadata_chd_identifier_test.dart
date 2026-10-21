import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/services/metadata/metadata_provider.dart';

Uint8List header() {
  final bytes = Uint8List(140);
  bytes.setRange(0, 8, 'MComprHD'.codeUnits);
  final data = ByteData.sublistView(bytes);
  data.setUint32(8, 124);
  data.setUint32(12, 5);
  data.setUint64(32, 1121026048);
  data.setUint64(40, 200);
  data.setUint64(48, 124);
  data.setUint32(56, 4096);
  data.setUint32(60, 2048);
  bytes.setRange(64, 84, List.generate(20, (i) => i + 1));
  bytes.setRange(84, 104, List.filled(20, 0xff));
  bytes.setRange(124, 128, 'DVD '.codeUnits);
  return bytes;
}

void main() {
  test('DVD CHD supplies the declared original ISO hash, never container hash',
      () {
    final identifier =
        MetadataRomIdentifier.fromChdDvdHeader(header(), 'Game (USA).chd');
    expect(identifier, isNotNull);
    expect(identifier!.kind, RomIdentifierKind.rawIso);
    expect(identifier.filename, 'Game (USA).iso');
    expect(identifier.sizeBytes, 1121026048);
    expect(identifier.sha1, '0102030405060708090a0b0c0d0e0f1011121314');
    expect(identifier.md5, isNull);
    expect(identifier.crc32, isNull);
  });

  test(
      'unsupported, malformed, parent-dependent and non-DVD headers stay unknown',
      () {
    final cases = <Uint8List>[
      Uint8List.sublistView(header(), 0, 139),
      header()..[0] = 0,
      header()..[15] = 4,
      header()..[11] = 123,
      header()..[103] = 0, // Combined SHA-1 changes do not affect raw identity.
    ];
    // The final case is valid: a combined checksum is not the original ISO hash.
    expect(
        MetadataRomIdentifier.fromChdDvdHeader(cases.removeLast(), 'Game.chd'),
        isNotNull);
    final parent = header()..[104] = 1;
    final cd = header()..setRange(124, 128, 'CHT2'.codeUnits);
    final noRawHash = header()..fillRange(64, 84, 0);
    final wrongUnit = header();
    ByteData.sublistView(wrongUnit).setUint32(60, 2448);
    final movedMetadata = header();
    ByteData.sublistView(movedMetadata).setUint64(48, 1000000);
    final misaligned = header();
    ByteData.sublistView(misaligned).setUint64(32, 1121026049);
    final wrongHunk = header();
    ByteData.sublistView(wrongHunk).setUint32(56, 2448);
    cases.addAll([
      parent,
      cd,
      noRawHash,
      wrongUnit,
      movedMetadata,
      misaligned,
      wrongHunk
    ]);
    for (final bytes in cases) {
      expect(MetadataRomIdentifier.fromChdDvdHeader(bytes, 'Game.chd'), isNull);
    }
    for (final name in [
      'Game.iso',
      '../Game.chd',
      r'a\Game.chd',
      'a:Game.chd',
      'Game\u0000.chd'
    ]) {
      expect(MetadataRomIdentifier.fromChdDvdHeader(header(), name), isNull);
    }
  });
}
