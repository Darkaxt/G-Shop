import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/nes_cartridge_model.dart';

void main() {
  test('compound regions work without assigning virtual compilation cartridges',
      () {
    expect(NesCartridgeModel.referencesFor('10-Yard Fight (USA, Europe).7z'),
        ['nintendo-3-gray', 'nintendo-5-gray']);
    expect(NesCartridgeModel.referencesFor('Super Mario Bros. (Japan, USA).7z'),
        ['nintendo-3-gray', 'nintendo-5-gray']);
    for (final tag in [
      '3DS Virtual Console',
      'Wii and Wii U Virtual Console',
      'Retro-Bit Generations',
      'Mega Man Legacy Collection',
      'FamicomBox'
    ]) {
      expect(
          NesCartridgeModel.referencesFor('Super Mario Bros. (USA) ($tag).7z'),
          isEmpty);
    }
    expect(NesCartridgeModel.regionsForArchive('Fixture (En,Fr) (Rev 1).7z'),
        isEmpty);
  });
  test('late revisions and fixed Camerica finishes are not invented', () {
    expect(NesCartridgeModel.referencesFor('Mega Man 6 (USA).7z'),
        ['nintendo-3-gray']);
    expect(
        NesCartridgeModel.referencesFor(
            'Zelda II - The Adventure of Link (USA).7z'),
        ['nintendo-3-gold', 'nintendo-3-gray']);
    expect(NesCartridgeModel.referencesFor('Bee 52 (USA) (Unl).7z'),
        ['camerica-silver']);
    expect(
        NesCartridgeModel.referencesFor(
            'Ultimate Stuntman, The (USA) (Unl).7z'),
        ['camerica-gold']);
    expect(
        NesCartridgeModel.referencesFor(
            'Quattro Sports (USA) (Aladdin Deck Enhancer) (Unl).7z'),
        ['aladdin']);
  });
  test('licensed and unlicensed releases of one title retain different shells',
      () {
    expect(NesCartridgeModel.referencesFor('Gauntlet (USA).7z'),
        ['nintendo-3-gray']);
    expect(
        NesCartridgeModel.referencesFor('Gauntlet (USA) (Unl).7z'), ['tengen']);
    expect(
        NesCartridgeModel.referencesFor('Gauntlet (USA) [Hack].7z'), isEmpty);
    expect(NesCartridgeModel.referencesFor('Gauntlet (Japan).7z'), isEmpty);
  });
  test('ambiguous stock is offered as references, never fixed by title alone',
      () {
    expect(NesCartridgeModel.referencesFor('Legend of Zelda, The (USA).7z'),
        containsAll(['nintendo-3-gold', 'nintendo-3-gray']));
    expect(NesCartridgeModel.referencesFor('Action 52 (USA) (Unl).7z'),
        ['active-clear']);
    expect(NesCartridgeModel.referencesFor('Maxi 15 (USA) (Unl).7z'),
        ['ave-square']);
    expect(
        NesCartridgeModel.referencesFor('Dizzy the Adventurer (USA) (Unl).7z'),
        ['aladdin']);
    expect(
        NesCartridgeModel.referencesFor(
            'Some New Homebrew (USA) (Aftermarket) (Unl).7z'),
        isEmpty);
  });
}
