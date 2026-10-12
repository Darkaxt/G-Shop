/// Only cartridge battery routes currently integrated with the owned launch
/// review. Not a user-supplied directory, generic core registry or state format.
enum RetroArchBatteryRoute {
  mgba('gba', 'mgba', 'libretro-mgba-sram-v1', 16 * 1024 * 1024, 'mgba-battery',
      'mGBA'),
  nes('nes', 'fceumm', 'libretro-fceumm-sram-v1', 16 * 1024 * 1024,
      'nes-battery', 'NES'),
  gameGear('gamegear', 'genesis_plus_gx', 'libretro-genesis-plus-gx-sram-v1',
      65536, 'gamegear-battery', 'Game Gear'),
  masterSystem(
      'mastersystem',
      'genesis_plus_gx',
      'libretro-genesis-plus-gx-sram-v1',
      65536,
      'mastersystem-battery',
      'Master System'),
  megaDrive('megadrive', 'genesis_plus_gx', 'libretro-genesis-plus-gx-sram-v1',
      65536, 'megadrive-battery', 'Mega Drive'),
  n64('n64', 'mupen64plus_next_gles3', 'libretro-mupen64plus-next-srm-v1',
      296960, 'n64-battery', 'Nintendo 64');

  final String platformId, coreId, formatId, journalId, label;
  final int maxBytes;
  const RetroArchBatteryRoute(this.platformId, this.coreId, this.formatId,
      this.maxBytes, this.journalId, this.label);

  static RetroArchBatteryRoute? forPlatform(String? platform) {
    for (final route in values) {
      if (route.platformId == platform) return route;
    }
    return null;
  }

  bool get includesRtc => this == mgba;

  String get directory => '/storage/emulated/0/RetroArch/saves/$coreLabel';

  // Mupen's EEPROM, four Controller Paks, SRAM and FlashRAM are one fixed-size
  // libretro memory region. A standalone .eep/.mpk or truncated SRM is not it.
  bool acceptsSize(int size) =>
      size > 0 && size <= maxBytes && (this != n64 || size == maxBytes);

  String get coreLabel => switch (this) {
        mgba => 'mGBA',
        nes => 'FCEUmm',
        n64 => 'Mupen64Plus-Next',
        _ => 'Genesis Plus GX',
      };
}
