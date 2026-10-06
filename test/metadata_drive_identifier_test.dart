import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';

RemoteArtifact artifact(
        {String name = 'Game.sfc',
        String provider = 'drive',
        String? account = 'account',
        String? version = '1',
        int? size = 1024,
        Map<String, String>? hashes}) =>
    RemoteArtifact(
        id: RemoteArtifactId(
            providerId: provider,
            sourceId: 'source',
            accountId: account,
            providerFileId: 'file'),
        displayName: name,
        displayPath: name,
        version: version,
        sizeBytes: size,
        providerChecksums: hashes ?? {'md5': 'a' * 32, 'sha1': 'b' * 40});

void main() {
  test('only mapped uncompressed files expose version-bound Drive ROM hashes',
      () {
    final raw = MetadataRomIdentifier.fromUncompressedDriveArtifact(
        artifact(), 'snes')!;
    expect(raw.kind, RomIdentifierKind.rawRom);
    expect(raw.md5, 'a' * 32);
    expect(raw.sha1, 'b' * 40);
    final iso = MetadataRomIdentifier.fromUncompressedDriveArtifact(
        artifact(name: 'Game.iso'), 'ps2')!;
    expect(iso.kind, RomIdentifierKind.rawIso);
    for (final value in [
      artifact(name: 'Game.zip'),
      artifact(name: 'Game.chd'),
      artifact(name: 'Game.rvz'),
      artifact(name: 'Game.7z'),
      artifact(name: 'Game.bin'),
      artifact(name: 'Game.cue'),
      artifact(name: '../Game.sfc'),
      artifact(name: r'a\Game.sfc'),
      artifact(provider: 'web'),
      artifact(account: null),
      artifact(version: null),
      artifact(size: null),
      artifact(size: 0),
      artifact(hashes: {}),
      artifact(hashes: {'sha256': 'a' * 64}),
      artifact(hashes: {'md5': '0' * 32}),
      artifact(hashes: {'sha1': 'invalid'}),
      artifact(hashes: {'md5': 'a' * 32, 'sha1': 'bad'})
    ]) {
      expect(MetadataRomIdentifier.fromUncompressedDriveArtifact(value, 'snes'),
          isNull);
    }
    expect(
        MetadataRomIdentifier.fromUncompressedDriveArtifact(artifact(), 'ps2'),
        isNull);
    expect(
        MetadataRomIdentifier.fromUncompressedDriveArtifact(
            artifact(), 'unknown'),
        isNull);
  });
}
