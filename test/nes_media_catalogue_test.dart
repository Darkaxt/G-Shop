import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/nes_media_catalogue.dart';

void main() {
  Map<String, dynamic> fixture() => {
        'schemaVersion': 1,
        'system': 'nes',
        'editions': [
          for (final id in ['nes-aaaaaaaaaaaa', 'nes-bbbbbbbbbbbb'])
            {'id': id, 'label': id, 'manifestSha256': 'a' * 64}
        ],
        'bindings': {
          'Zelda (USA).7z': ['nes-aaaaaaaaaaaa', 'nes-bbbbbbbbbbbb']
        }
      };
  test('references retain every printing and never leak to another ROM edition',
      () {
    final catalogue = NesMediaCatalogue.parse(fixture());
    expect(catalogue.forArchive('Zelda (USA).7z').map((e) => e.id),
        ['nes-aaaaaaaaaaaa', 'nes-bbbbbbbbbbbb']);
    expect(catalogue.forArchive('Zelda (Europe).7z'), isEmpty);
    expect(catalogue.forArchive('Zelda (USA) [Hack].7z'), isEmpty);
    expect(catalogue.forArchive('../Zelda (USA).7z'), isEmpty);
  });
  test('catalogue rejects ambiguous paths, duplicates and missing receipts',
      () {
    for (final broken in [
      fixture()
        ..['bindings'] = {
          '../game.7z': ['nes-aaaaaaaaaaaa']
        },
      fixture()
        ..['bindings'] = {
          'game.7z': ['nes-aaaaaaaaaaaa', 'nes-aaaaaaaaaaaa']
        },
      fixture()
        ..['bindings'] = {
          'game.7z': ['nes-cccccccccccc']
        },
      fixture()
        ..['editions'] = [
          {'id': '../nes', 'label': 'NES', 'manifestSha256': 'a' * 64}
        ],
    ]) {
      expect(() => NesMediaCatalogue.parse(broken), throwsFormatException);
    }
  });
}
