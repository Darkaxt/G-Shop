/// Only cartridge battery routes currently integrated with the owned launch
/// review. Not a user-supplied directory, generic core registry or state format.
enum RetroArchBatteryRoute {
  mgba('gba', 'mgba', 'libretro-mgba-sram-v1', 16 * 1024 * 1024, 'mgba-battery',
      'mGBA'),
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
      65536, 'megadrive-battery', 'Mega Drive');

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
}
