import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/pcsx_save_layout.dart';

Map<String, dynamic> layout({String stem = 'one%2FGame', String? directory}) =>
    {
      'directory':
          directory ?? '/storage/emulated/0/RetroArch/saves/PCSX-ReARMed',
      'cards': [
        {'slot': 1, 'mode': 'libretro', 'name': '$stem.srm'},
        {'slot': 2, 'mode': 'shared', 'name': 'pcsx-card2.mcd'},
      ],
    };

void main() {
  test('private cards differ by ROM while shared resource identity does not',
      () {
    final one = PcsxSaveLayout.decode(layout());
    final two = PcsxSaveLayout.decode(layout(stem: 'two%2FOther'));
    expect(one.cards.first.name, 'one%2FGame.srm');
    expect(two.cards.first.name, isNot(one.cards.first.name));
    expect(one.cards.first.isShared, false);
    expect(one.sharedResourceKey(one.cards.last),
        two.sharedResourceKey(two.cards.last));
    final custom =
        PcsxSaveLayout.decode(layout(directory: '/storage/75D7-DC5F/Saves'));
    expect(custom.sharedResourceKey(custom.cards.last),
        isNot(one.sharedResourceKey(one.cards.last)));
    expect(() => one.sharedResourceKey(one.cards.first), throwsArgumentError);
    expect(() => one.cards.clear(), throwsUnsupportedError);
  });

  test('serial mode stays unresolved until actual disc evidence is available',
      () {
    final raw = layout();
    raw['cards'] = [
      {'slot': 2, 'mode': 'serial', 'name': null}
    ];
    final result = PcsxSaveLayout.decode(raw);
    expect(result.cards.single.needsDiscSerial, true);
    expect(result.cards.single.isShared, false);
    expect(
        PcsxSaveLayout.decode({'directory': raw['directory'], 'cards': []})
            .cards,
        isEmpty);
  });

  test('requires an explicit name field even for unresolved serial cards', () {
    final raw = layout();
    raw['cards'] = [
      {'slot': 2, 'mode': 'serial', 'extra': true}
    ];
    expect(() => PcsxSaveLayout.decode(raw), throwsFormatException);
  });

  test('accepts the configured RetroArch external-files save directory', () {
    const path =
        '/storage/emulated/0/Android/data/com.retroarch.aarch64/files/saves';
    expect(PcsxSaveLayout.decode(layout(directory: path)).directory, path);
  });

  test('rejects altered shared roles, paths, slots and fabricated serials', () {
    for (final cards in [
      [
        {'slot': 2, 'mode': 'shared', 'name': 'Game.mcd'}
      ],
      [
        {'slot': 2, 'mode': 'libretro', 'name': 'Game.srm'}
      ],
      [
        {'slot': 1, 'mode': 'libretro', 'name': '../Game.srm'}
      ],
      [
        {'slot': 0, 'mode': 'shared', 'name': 'pcsx-card0.mcd'}
      ],
      [
        {'slot': 2, 'mode': 'serial', 'name': 'GUESS-00001_2.mcd'}
      ],
      [
        {'slot': 2, 'mode': 'shared', 'name': 'pcsx-card2.mcd'},
        {'slot': 1, 'mode': 'shared', 'name': 'pcsx-card1.mcd'}
      ],
      [
        {'slot': 1, 'mode': 'none', 'name': null}
      ],
      [
        {'slot': 1, 'mode': 'shared', 'name': 'pcsx-card1.mcd', 'extra': true}
      ],
    ]) {
      final raw = layout();
      raw['cards'] = cards;
      expect(() => PcsxSaveLayout.decode(raw), throwsFormatException);
    }
    for (final path in [
      '/data/user/0/other',
      '/storage/emulated/0/../Saves',
      '/storage/emulated/0//Saves',
      '/storage/emulated/0/Android/data/other/files'
    ]) {
      expect(() => PcsxSaveLayout.decode(layout(directory: path)),
          throwsFormatException);
    }
    expect(() => PcsxSaveLayout.decode(null), throwsFormatException);
    expect(() => PcsxSaveLayout.decode({...layout(), 'extra': true}),
        throwsFormatException);
  });
}
