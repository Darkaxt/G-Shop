import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/providers/installed_files_provider.dart';

class _CountedId extends RemoteArtifactId {
  static int keyReads = 0;
  _CountedId(String fileId,
      {String provider = 'drive',
      String source = 'source',
      String account = 'account'})
      : super(
            providerId: provider,
            sourceId: source,
            accountId: account,
            providerFileId: fileId);

  @override
  String get key {
    keyReads++;
    return super.key;
  }
}

RemoteArtifact _artifact(String fileId,
        {String provider = 'drive',
        String source = 'source',
        String account = 'account',
        String version = 'v1',
        int size = 4,
        String digest = 'original',
        String name = 'Fixture.chd'}) =>
    RemoteArtifact(
        id: _CountedId(fileId,
            provider: provider, source: source, account: account),
        displayName: name,
        displayPath: name,
        sizeBytes: size,
        version: version,
        providerChecksums: {'md5': digest});

void main() {
  test('collection availability does not scan unrelated installed identities',
      () {
    const installedCount = 512;
    const collectionCount = 1536;
    final state = InstalledFilesState(exactBySystem: {
      'psx': [for (var i = 0; i < installedCount; i++) _artifact('$i')],
    });
    _CountedId.keyReads = 0;
    var installed = 0;
    for (var i = 0; i < collectionCount; i++) {
      if (state.hasExactArtifact('psx', _artifact('$i'))) installed++;
    }
    expect(installed, installedCount);
    // A deterministic operation bound, not a machine-dependent timing limit.
    expect(_CountedId.keyReads,
        lessThanOrEqualTo(4 * (installedCount + collectionCount)));
  });

  test('exact lookup retains every identity and content boundary', () {
    final first = _artifact('file');
    final second = _artifact('file', version: 'v2');
    final state = InstalledFilesState(exactBySystem: {
      'psx': [first, second],
    });
    expect(state.hasExactArtifact('psx', _artifact('file')), isTrue);
    expect(state.hasExactArtifact('psx', _artifact('file', version: 'v2')),
        isTrue);
    expect(
        state.hasExactArtifact('psx', _artifact('file', name: 'Renamed.chd')),
        isTrue);
    for (final other in [
      _artifact('other-file'),
      _artifact('file', provider: 'other-provider'),
      _artifact('file', source: 'other-source'),
      _artifact('file', account: 'other-account'),
      _artifact('file', version: 'v3'),
      _artifact('file', size: 5),
      _artifact('file', digest: 'changed'),
    ]) {
      expect(state.hasExactArtifact('psx', other), isFalse);
    }
    expect(state.hasExactArtifact('nes', first), isFalse);
    expect(InstalledFilesState().hasExactArtifact('psx', first), isFalse);
  });

  test('lookup snapshot cannot diverge when constructor inputs change', () {
    final first = _artifact('first');
    final list = [first];
    final input = {'psx': list};
    final state = InstalledFilesState(exactBySystem: input);
    expect(state.hasExactArtifact('psx', first), isTrue);
    list.clear();
    input.clear();
    expect(state.exactBySystem['psx'], [first]);
    expect(state.hasExactArtifact('psx', first), isTrue);
    expect(() => state.exactBySystem.clear(), throwsUnsupportedError);
    expect(() => state.exactBySystem['psx']!.clear(), throwsUnsupportedError);
  });
}
