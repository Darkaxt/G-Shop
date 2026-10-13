/// Product coverage, not permission to capture files. The native capture and
/// restore boundaries remain authoritative for each explicitly mapped game.
class SaveEmulatorCoverage {
  static const knownPackages = <String, String>{
    'com.retroarch.aarch64': 'RetroArch',
    'org.ppsspp.ppsspp': 'PPSSPP',
    'org.dolphinemu.dolphinemu': 'Dolphin',
    'io.github.lime3ds.android': 'Azahar',
    'me.magnum.melondualds': 'MelonDualDS',
    'dev.twilitrealm.dusk': 'Dusk',
    'org.kenjinx.android': 'KenjiNX',
    'dev.eden.eden_emulator': 'Eden',
    'dev.eden.eden_emulator.nightly': 'Eden Nightly',
    'dev.legacy.eden_emulator': 'Eden Legacy',
    'com.flycast.emulator': 'Flycast',
    'com.neogamelab.neostation': 'NeoStation',
    'xyz.aethersx2.android': 'NetherSX2',
    'info.cemu.cemu': 'Cemu',
    'com.darkaxt.dualdex': 'DualDex',
    'io.github.darkaxt.dualsouls': 'DualSouls',
    'com.retrohrai.launcher': 'RetroHrai',
    'rip.moth.cocoonshell': 'Cocoon',
    'org.es_de.frontend': 'ES-DE',
    'org.solarus_games.solarus': 'Solarus',
    'dev.picori.tmc': 'Picori',
    'com.dishii.zelda3': 'Zelda3',
    'com.zelda.ladxhd': 'Link’s Awakening DX HD',
    'com.dishii.soh': 'Ship of Harkinian',
    'com.underdecodedhd.gen2recomp': 'Gen2Recomp',
    'com.theboisclub.pokemonred': 'Pokémon Red',
    'com.balatro.dualscreen': 'Balatro Dual Screen',
  };

  final String packageName, versionName;
  final List<String> documentAuthorities;
  const SaveEmulatorCoverage._(
      this.packageName, this.versionName, this.documentAuthorities);
  String get label => knownPackages[packageName]!;

  static List<SaveEmulatorCoverage> decode(List<dynamic>? rows) {
    if (rows == null || rows.length > knownPackages.length) {
      throw const FormatException('Invalid emulator inventory');
    }
    final seen = <String>{};
    final result = <SaveEmulatorCoverage>[];
    for (final row in rows) {
      if (row is! Map ||
          row['packageName'] is! String ||
          row['versionName'] is! String ||
          row['documentAuthorities'] is! List) {
        throw const FormatException('Invalid emulator inventory');
      }
      final name = row['packageName'] as String;
      final version = row['versionName'] as String;
      final authorities = row['documentAuthorities'] as List;
      if (!knownPackages.containsKey(name) ||
          !seen.add(name) ||
          version.isEmpty ||
          version.length > 128 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(version) ||
          authorities.length > 32 ||
          authorities.toSet().length != authorities.length ||
          authorities.any((value) =>
              value is! String ||
              value.length > 255 ||
              !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(value))) {
        throw const FormatException('Invalid emulator inventory');
      }
      result.add(SaveEmulatorCoverage._(
          name, version, List<String>.unmodifiable(authorities)));
    }
    result.sort((a, b) => a.label.compareTo(b.label));
    return List.unmodifiable(result);
  }

  bool get _retroArch => packageName == 'com.retroarch.aarch64';
  bool get _psp => packageName == 'org.ppsspp.ppsspp';
  bool get _melon => packageName == 'me.magnum.melondualds';
  bool get _reviewed => _retroArch
      ? {'1.22.2', '1.22.2_GIT'}.contains(versionName)
      : _psp
          ? {'1.20.4', 'v1.20.4'}.contains(versionName)
          : _melon && versionName == '0.8.0.rc2';
  bool get _launcher =>
      {'rip.moth.cocoonshell', 'org.es_de.frontend'}.contains(packageName);

  String get saves => _launcher
      ? 'Not applicable · launcher; use the selected emulator'
      : _retroArch
          ? _reviewed
              ? 'In-game saves · GB, GBC, NES, SNES and GBA (including paired clock data), Game Gear, Master System, Mega Drive and Nintendo 64 (including Controller Paks).'
              : 'Needs review · installed RetroArch runtime is not verified'
          : _melon
              ? _reviewed
                  ? 'In-game saves · shared or protected .sav/.srm file; completed writes can be backed up while MelonDualDS stays open.'
                  : 'Needs review · installed MelonDualDS runtime is not verified'
              : _psp
                  ? _reviewed
                      ? 'In-game saves · complete PPSSPP SAVEDATA folders.'
                      : 'Needs review · installed PPSSPP runtime is not verified'
                  : packageName == 'xyz.aethersx2.android'
                      ? 'In-game saves · enabled shared memory cards from emulator settings; custom mappings remain available.'
                      : packageName == 'com.flycast.emulator'
                          ? 'In-game saves · shared virtual VMU cards from emulator settings; per-game cards need an exact mapping.'
                          : 'Automatic mapping pending · exact save-folder mapping is available';
  String get states => _launcher
      ? 'Not applicable · launcher; use the selected emulator'
      : _psp
          ? _reviewed
              ? 'Verified · reviewed PPSSPP state slot'
              : 'Needs review · installed PPSSPP runtime is not verified'
          : 'Custom mapping · exact state files and runtime identity required';
  String get storage => _melon
      ? 'Root-assisted discovery automatically resolves the downloaded game’s save '
          'from MelonDualDS settings, including its standard Android/data folder. '
          'Custom folders remain configurable. Completed saves are watched and '
          'captured without stopping the emulator. Restore requires closing the '
          'game safely and preparing MelonDualDS through Android App info.'
      : _psp
          ? _reviewed
              ? 'PPSSPP’s Memory Stick setting supplies the SAVEDATA and '
                  'PPSSPP_STATE folders. Automatic root-assisted discovery '
                  'supports shared and protected storage. Select this game’s '
                  'save folder or state slot. Close the game using PPSSPP’s '
                  'Exit command before restoring.'
              : 'Needs review · installed PPSSPP runtime is not verified'
          : packageName == 'xyz.aethersx2.android'
              ? 'Current memory-card settings supply the watched folder and enabled card files. '
                  'Cards share one backup history across games. Game-specific card overrides need an exact custom mapping.'
              : packageName == 'com.flycast.emulator'
                  ? 'The configured home and VMU folder supply enabled shared virtual cards. '
                      'Only those card files are backed up, not BIOS or the whole data folder. '
                      'Per-game, network and legacy-location cards need an exact mapping.'
                  : packageName.contains('eden_emulator')
                      ? 'Automatic location resolution is pending. Map the exact title and user/profile save folder, not the entire NAND save root.'
                      : documentAuthorities.isNotEmpty
                          ? 'Document picker provider advertised: ${documentAuthorities.join(', ')}. '
                              'It does not select this game’s saves; an exact root-folder mapping is available.'
                          : _retroArch
                              ? 'Current routes: shared RetroArch/saves/SameBoy GB/GBC SRAM and optional RTC, FCEUmm NES battery memory, Snes9x SNES SRAM and optional RTC, mGBA and Genesis Plus GX '
                                  'Game Gear, Master System and Mega Drive cartridge SRAM, plus '
                                  'Mupen64Plus-Next complete Nintendo 64 save memory with exact launch binding. '
                                  'Other cores and custom paths use explicit folder mappings.'
                              : _launcher
                                  ? 'This launcher does not own the emulator’s save files.'
                                  : 'Automatic save-folder selection is pending; an exact custom mapping '
                                      'uses the shared root pipeline. This is not a claim of automatic support.';
}
