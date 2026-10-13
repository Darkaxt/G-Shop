import 'emulator_family_registry.dart';

/// Product coverage, not permission to capture files. The native capture and
/// restore boundaries remain authoritative for each explicitly mapped game.
class SaveEmulatorCoverage {
  final String packageName, versionName;
  final EmulatorRegistration registration;
  final List<String> documentAuthorities;
  const SaveEmulatorCoverage._(this.packageName, this.versionName,
      this.documentAuthorities, this.registration);
  String get label => registration.name;
  String get family => registration.family;
  String get familyLabel => EmulatorFamilyRegistry.familyNames[family]!;

  static List<SaveEmulatorCoverage> decode(List<dynamic>? rows,
      {required EmulatorFamilyRegistry registry}) {
    if (rows == null || rows.length > registry.packages.length) {
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
      if (!registry.packages.containsKey(name) ||
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
      result.add(SaveEmulatorCoverage._(name, version,
          List<String>.unmodifiable(authorities), registry.packages[name]!));
    }
    result.sort((a, b) => a.label.compareTo(b.label));
    return List.unmodifiable(result);
  }

  bool get _retroArch => family == 'retroarch';
  bool get _psp => family == 'ppsspp';
  bool get _melon => family == 'melonds';
  bool get _reviewed => _retroArch
      ? packageName == 'com.retroarch.aarch64' &&
          {'1.22.2', '1.22.2_GIT'}.contains(versionName)
      : _psp
          ? packageName == 'org.ppsspp.ppsspp' &&
              {'1.20.4', 'v1.20.4'}.contains(versionName)
          : _melon &&
              packageName == 'me.magnum.melondualds' &&
              versionName == '0.8.0.rc2';
  bool get _launcher => family == 'launcher';

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
                  : family == 'pcsx2' && packageName == 'xyz.aethersx2.android'
                      ? 'In-game saves · enabled shared memory cards from emulator settings; custom mappings remain available.'
                      : family == 'flycast' &&
                              packageName == 'com.flycast.emulator'
                          ? 'In-game saves · shared virtual VMU cards from emulator settings; per-game cards need an exact mapping.'
                          : family == 'azahar' &&
                                  packageName == 'io.github.lime3ds.android'
                              ? 'In-game saves · one title’s data and format metadata, resolved from a validated raw ROM header; compressed/custom layouts need an exact mapping.'
                              : family == 'dolphin' &&
                                      packageName == 'org.dolphinemu.dolphinemu'
                                  ? 'GameCube saves · enabled shared GCI memory-card folders; Wii and custom/raw cards use exact mappings.'
                                  : 'Automatic mapping pending · exact save-folder mapping is available';
  String get states => _launcher
      ? 'Not applicable · launcher; use the selected emulator'
      : _psp
          ? _reviewed
              ? 'Verified · reviewed PPSSPP state slot'
              : 'Needs review · installed PPSSPP runtime is not verified'
          : 'Custom mapping · exact state files and runtime identity required';
  String get storage => family == 'eden'
      ? 'Map the exact title and user/profile save folder, not the entire NAND save root. '
          'Family registration does not choose a save folder or make save states compatible.'
      : _melon && _reviewed
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
              : family == 'pcsx2' && packageName == 'xyz.aethersx2.android'
                  ? 'Current memory-card settings supply the watched folder and enabled card files. '
                      'Cards share one backup history across games. Game-specific card overrides need an exact custom mapping.'
                  : family == 'dolphin' &&
                          packageName == 'org.dolphinemu.dolphinemu'
                      ? 'GameCube card folders share one history across games. Current Core slot settings select only enabled GCI cards. '
                          'SRAM, BIOS, Wii NAND and disabled cards are not included. Raw cards, custom paths and game-specific overrides need an exact mapping.'
                      : family == 'flycast' &&
                              packageName == 'com.flycast.emulator'
                          ? 'The configured home and VMU folder supply enabled shared virtual cards. '
                              'Only those card files are backed up, not BIOS or the whole data folder. '
                              'Per-game, network and legacy-location cards need an exact mapping.'
                          : family == 'azahar' &&
                                  packageName == 'io.github.lime3ds.android'
                              ? 'The configured user directory and installed NCCH/NCSD program ID select one title’s save group, not the entire SDMC. Content, DLC, system files and other titles are excluded. Compressed ROMs, CIA installers, extdata and states need exact custom mappings.'
                              : documentAuthorities.isNotEmpty
                                  ? 'Document picker provider advertised: ${documentAuthorities.join(', ')}. '
                                      'It does not select this game’s saves; an exact root-folder mapping is available.'
                                  : _retroArch && _reviewed
                                      ? 'Current routes: shared RetroArch/saves/SameBoy GB/GBC SRAM and optional RTC, FCEUmm NES battery memory, Snes9x SNES SRAM and optional RTC, mGBA and Genesis Plus GX '
                                          'Game Gear, Master System and Mega Drive cartridge SRAM, plus '
                                          'Mupen64Plus-Next complete Nintendo 64 save memory with exact launch binding. '
                                          'Other cores and custom paths use explicit folder mappings.'
                                      : _launcher
                                          ? 'This launcher does not own the emulator’s save files.'
                                          : '$familyLabel family. Automatic save-folder selection is pending; an exact custom mapping '
                                              'uses the shared root pipeline. This is not a claim of automatic support.';
}
