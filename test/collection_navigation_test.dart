import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/features/home/widgets/manufacturer_filter.dart';

void main() {
  test('Nintendo chronology and explicit hybrid types share one registry', () {
    final systems = SystemModel.supportedSystems;
    final home = systemsForManufacturer(systems, 'Nintendo',
        type: SystemType.homeConsole);
    expect(home.map((s) => s.id), [
      'nes',
      'fds',
      'snes',
      'virtualboy',
      'n64',
      'gc',
      'wii',
      'wiiu',
      'switch'
    ]);
    final handheld =
        systemsForManufacturer(systems, 'Nintendo', type: SystemType.handheld);
    expect(handheld.map((s) => s.id),
        ['gameandwatch', 'gb', 'gbc', 'gba', 'nds', 'dsi', 'n3ds', 'switch']);
    expect(
        systemsForManufacturer(systems, 'Nintendo')
            .where((s) => s.id == 'switch'),
        hasLength(1));
    expect(availableSystemTypes(systems, 'Nintendo'),
        {SystemType.homeConsole, SystemType.handheld});
    expect(availableSystemTypes(systems, 'Bandai'), {SystemType.handheld});
  });
  test('chronology uses name and stable ID for ties without changing the input',
      () {
    const original = [
      SystemModel(
          id: 'z', name: 'Alpha', manufacturer: 'Test', releaseYear: 2000),
      SystemModel(
          id: 'b', name: 'Beta', manufacturer: 'Test', releaseYear: 1990),
      SystemModel(
          id: 'a', name: 'alpha', manufacturer: 'Test', releaseYear: 2000),
    ];
    expect(systemsForManufacturer(original, null).map((s) => s.id),
        ['b', 'a', 'z']);
    expect(original.map((s) => s.id), ['z', 'b', 'a']);
  });
}
