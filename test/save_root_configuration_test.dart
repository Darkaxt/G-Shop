import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/save_root_configuration.dart';

void main() {
  test(
      'Azahar title save profile keeps each title separate and includes its binary saves',
      () {
    final config = SaveRootConfiguration.decode({
      'schema': 1,
      'directory':
          '/storage/emulated/0/Azahar/sdmc/Nintendo 3DS/${'0' * 32}/${'0' * 32}/title/00040000',
      'emulator': 'io.github.lime3ds.android',
      'core': 'azahar',
      'kind': 'save',
      'format': 'azahar-title-save-v1',
      'profile': 'azahar-title-save-v1',
      'files': ['004c5700/data/00000001.metadata'],
      'folders': ['004c5700/data/00000001'],
      'required': ['004c5700/data/00000001.metadata'],
    });
    expect(config.sharedResourceKey, isNull);
    expect(config.acceptsFile('004c5700/data/00000001/main.bin'), isTrue);
    expect(config.acceptsFile('00934200/data/00000001/hime00.sav'), isFalse);
    expect(config.acceptsFile('004c5700/content/game.app'), isFalse);
    expect(config.acceptsFile('004c5700/data/00000001/bios.bin'), isFalse);
    expect(config.completeGroup({'004c5700/data/00000001/main.bin'}), isFalse);
    expect(SaveRootConfiguration.decode(config.toJson()).identity,
        config.identity);
  });
  final mapping = <String, dynamic>{
    'schema': 1,
    'directory':
        '/storage/emulated/0/Android/data/example.emulator/files/saves',
    'emulator': 'example.emulator',
    'core': 'example',
    'kind': 'save',
    'format': 'example-save-v1',
    'files': ['{romStem}.sav', '{romStem}.rtc'],
    'folders': <String>[],
    'required': ['{romStem}.sav'],
  };
  test('one configuration binds external save groups to the exact ROM', () {
    final config = SaveRootConfiguration.decode(mapping, romName: 'Game.gba');
    expect(config.files, ['Game.sav', 'Game.rtc']);
    expect(config.acceptsFile('Game.sav'), isTrue);
    expect(config.acceptsFile('Other.sav'), isFalse);
    expect(config.acceptsFile('../Game.sav'), isFalse);
    expect(config.completeGroup({'Game.sav'}), isTrue);
    expect(config.completeGroup({'Game.rtc'}), isFalse);
    expect(config.completeGroup({}), isTrue);
    expect(SaveRootConfiguration.decode(config.toJson()).toJson(),
        config.toJson());
  });
  test('a configured game directory includes derived descendants, not app data',
      () {
    final config = SaveRootConfiguration.decode({
      ...mapping,
      'directory': '/data/user/0/example.emulator/files/saves',
      'files': ['card.bin'],
      'folders': ['TITLE123'],
      'required': <String>[],
    });
    expect(config.acceptsFile('card.bin'), isTrue);
    expect(config.acceptsFile('TITLE123/slot/save.dat'), isTrue);
    expect(config.acceptsDirectory('TITLE123/slot'), isTrue);
    expect(config.acceptsFile('TITLE124/slot/save.dat'), isFalse);
    expect(config.acceptsFile('TITLE123/settings.ini'), isFalse);
    expect(config.acceptsFile('TITLE123/other.iso'), isFalse);
    expect(config.acceptsFile('TITLE123/bios.bin'), isFalse);
    for (final directory in [
      '/data/user/0/other.app/files/saves',
      '/data/user/0/example.emulator',
      '/storage/emulated/0'
    ]) {
      expect(
          () => SaveRootConfiguration.decode(
              {...mapping, 'directory': directory},
              romName: 'Game.gba'),
          throwsFormatException);
    }
  });
  test(
      'shared card selection is stable across ROMs and separate from other cards',
      () {
    final row = {
      ...mapping,
      'resourceId': 'card-1',
      'files': ['Mcd001.ps2'],
      'folders': <String>[],
      'required': ['Mcd001.ps2']
    };
    final first = SaveRootConfiguration.decode(row, romName: 'One.chd');
    final second = SaveRootConfiguration.decode(row, romName: 'Two.chd');
    expect(first.identity, second.identity);
    expect(first.logicalRomName, 'shared-card-1.save');
    expect(first.sharedResourceKey, second.sharedResourceKey);
    expect(first.acceptsFile('Mcd002.ps2'), isFalse);
    expect(
        SaveRootConfiguration.decode({...row, 'resourceId': 'card-2'})
            .sharedResourceKey,
        isNot(first.sharedResourceKey));
    for (final change in [
      {'kind': 'state'},
      {'resourceId': '../other'},
      {
        'files': ['{romStem}.sav']
      }
    ]) {
      expect(
          () => SaveRootConfiguration.decode({...row, ...change},
              romName: 'One.chd'),
          throwsFormatException);
    }
  });
}
