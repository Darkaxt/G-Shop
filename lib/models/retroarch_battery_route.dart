/// Only cartridge battery routes currently integrated with the owned launch
/// review. Not a user-supplied directory, generic core registry or state format.
enum RetroArchBatteryRoute {
  mgba('gba', 'mgba', 'libretro-mgba-sram-v1', 16 * 1024 * 1024),
  gameGear(
      'gamegear', 'genesis_plus_gx', 'libretro-genesis-plus-gx-sram-v1', 65536);

  final String platformId, coreId, formatId;
  final int maxBytes;
  const RetroArchBatteryRoute(
      this.platformId, this.coreId, this.formatId, this.maxBytes);

  bool get includesRtc => this == mgba;
}
