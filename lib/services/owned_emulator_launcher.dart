import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../models/game_item.dart';
import '../models/system_model.dart';
import '../models/transfer_record.dart';
import '../models/retroarch_battery_route.dart';
import '../models/pcsx_save_layout.dart';
import 'rom_manager.dart';
import 'owned_storage.dart';
import 'saves/save_capture.dart';
import 'installation_paths.dart';

/// Exact local handoff through an owned installation or separately byte-bound
/// read-only copy. No source access, ownership adoption or emulator setup mutation.
class OwnedEmulatorLauncher {
  static String emulatorName(String platformId) => switch (platformId) {
        'nds' => 'MelonDualDS',
        'psp' => 'PPSSPP',
        'ps2' => 'NetherSX2',
        'wiiu' => 'Cemu',
        'gc' || 'wii' => 'Dolphin',
        _ => 'RetroArch',
      };

  final RomManager romManager;
  final MethodChannel channel;
  final _opening = <String, Future<void>>{};
  OwnedEmulatorLauncher(
      {RomManager? romManager,
      this.channel = const MethodChannel('com.retro.rshop/storage')})
      : romManager = romManager ?? RomManager();

  static bool supports(GameItem game, SystemModel system) =>
      game.remoteArtifact != null &&
      !game.isFolder &&
      ((const {'gc', 'wii'}.contains(system.id) &&
              system.romExtensions
                  .any((ext) => game.filename.toLowerCase().endsWith(ext))) ||
          (const {'psx', 'psp', 'ps2'}.contains(system.id) &&
              game.filename.toLowerCase().endsWith('.chd')) ||
          (system.id == 'nds' &&
              game.filename.toLowerCase().endsWith('.nds')) ||
          (system.id == 'wiiu' &&
              game.filename.toLowerCase().endsWith('.wua')) ||
          ((RetroArchBatteryRoute.forPlatform(system.id) != null ||
                  system.id == 'sg1000') &&
              system.romExtensions
                  .any((ext) => game.filename.toLowerCase().endsWith(ext))) ||
          TransferRecord.supportsArchiveMapping(game.filename, system.id));

  Future<void> open(GameItem game, SystemModel system, String root,
      {String? companionComponent, Future<void> Function()? prepareSave}) {
    if (!supports(game, system)) {
      return Future.error(
          UnsupportedError('No verified emulator handoff for this format'));
    }
    final key = game.selectionKey;
    final current = _opening[key];
    if (current != null) return current;
    final operation =
        _open(game, system, root, companionComponent, prepareSave);
    _opening[key] = operation;
    // Clear after acknowledgement, retaining the original error on the caller.
    operation.then<void>((_) => _opening.remove(key),
        onError: (Object _, StackTrace __) {
      _opening.remove(key);
    });
    return operation;
  }

  Future<Map<String, Object>> _grant(
      GameItem game, String platformId, String root,
      {void Function(String)? resolvedPath}) async {
    Map<String, Object> grant;
    try {
      final installed = await romManager.requireInstalledArtifact(game, root);
      resolvedPath
          ?.call(p.join(installed.destinationRoot, installed.relativePath));
      grant = {
        'installationId': installed.id,
        'filename': installed.relativePath
      };
    } on OwnedStorageException catch (error) {
      if (error.code != 'changed') rethrow;
      final copy = await romManager.requireLocalCopy(game, root);
      resolvedPath?.call(p.join(
          copy.observation.destinationRoot, copy.observation.relativePath));
      grant = {
        'observationId': copy.id,
        'platformId': platformId,
        'filename': copy.observation.relativePath
      };
    }
    return grant;
  }

  Future<Map<String, Object>> resolveRomCompanionGrant(
      GameItem game, String platformId, String root) {
    if (game.isFolder || game.remoteArtifact == null) {
      throw UnsupportedError('No installed ROM companion target');
    }
    return _grant(game, platformId, root);
  }

  static ({String packageName, String coreId}) romCompanionRuntime(
          String platform) =>
      switch (platform) {
        'nds' => (packageName: 'me.magnum.melondualds', coreId: 'melonds'),
        'psp' => (packageName: 'org.ppsspp.ppsspp', coreId: 'ppsspp'),
        'ps2' => (packageName: 'xyz.aethersx2.android', coreId: 'pcsx2'),
        'wiiu' => (packageName: 'info.cemu.cemu', coreId: 'cemu'),
        'gc' || 'wii' => (
            packageName: 'org.dolphinemu.dolphinemu',
            coreId: 'dolphin'
          ),
        'psx' => (packageName: 'com.retroarch.aarch64', coreId: 'pcsx_rearmed'),
        'sg1000' => (
            packageName: 'com.retroarch.aarch64',
            coreId: 'genesis_plus_gx'
          ),
        _ => (
            packageName: 'com.retroarch.aarch64',
            coreId: RetroArchBatteryRoute.forPlatform(platform)?.coreId ??
                (throw UnsupportedError('No configured ROM runtime'))
          ),
      };

  /// Resolves the save for the very same validated external URI as DS launch,
  /// using Melon's current settings and actual filename, without opening it.
  Future<({String directory, String name})> reviewMelonSave(
      GameItem game, SystemModel system, String root) async {
    if (system.id != 'nds' || !supports(game, system)) {
      throw UnsupportedError('No reviewed DS save route for this format');
    }
    final grant = await _grant(game, system.id, root);
    final mapping = await channel.invokeMapMethod<String, dynamic>(
        'reviewOwnedMelonSave', grant);
    if (mapping == null ||
        mapping['directory'] is! String ||
        mapping['name'] is! String) {
      throw StateError('No validated DS save target');
    }
    return (
      directory: mapping['directory'] as String,
      name: mapping['name'] as String
    );
  }

  /// RetroArch names SAF saves from the encoded document leaf, not the display
  /// title or the archive member's basename. Review shares the launch grant.
  Future<String> reviewRetroArchGbaSave(
          GameItem game, SystemModel system, String root) =>
      reviewRetroArchBatterySave(
          game, system, root, RetroArchBatteryRoute.mgba);

  /// Game Gear ZIPs use the same owned-document naming contract, but their
  /// save review must not accidentally select the GBA/core namespace.
  Future<String> reviewRetroArchGameGearSave(
          GameItem game, SystemModel system, String root) =>
      reviewRetroArchBatterySave(
          game, system, root, RetroArchBatteryRoute.gameGear);

  Future<String> reviewRetroArchBatterySave(GameItem game, SystemModel system,
      String root, RetroArchBatteryRoute route) async {
    if (system.id != route.platformId || !supports(game, system)) {
      throw UnsupportedError('No reviewed save route for this format');
    }
    final method = switch (route) {
      RetroArchBatteryRoute.gameBoy => 'reviewOwnedRetroArchGameBoySave',
      RetroArchBatteryRoute.gameBoyColor =>
        'reviewOwnedRetroArchGameBoyColorSave',
      RetroArchBatteryRoute.mgba => 'reviewOwnedRetroArchGameBoyAdvanceSave',
      RetroArchBatteryRoute.nes => 'reviewOwnedRetroArchNesSave',
      RetroArchBatteryRoute.snes => 'reviewOwnedRetroArchSnesSave',
      RetroArchBatteryRoute.gameGear => 'reviewOwnedRetroArchGameGearSave',
      RetroArchBatteryRoute.masterSystem =>
        'reviewOwnedRetroArchMasterSystemSave',
      RetroArchBatteryRoute.megaDrive => 'reviewOwnedRetroArchMegaDriveSave',
      RetroArchBatteryRoute.n64 => 'reviewOwnedRetroArchN64Save',
    };
    final grant = await _grant(game, system.id, root);
    final name = await channel.invokeMethod<String>(method, grant);
    if (name == null || name.isEmpty) {
      throw StateError('No validated launch save target');
    }
    return name;
  }

  /// Same exact CHD grant as PS1 launch, with the current core/card overrides.
  /// Keep a shared card separate from the selected game's private first card.
  Future<PcsxSaveLayout> reviewRetroArchPcsxSaves(
      GameItem game, SystemModel system, String root) async {
    if (system.id != 'psx' || !supports(game, system)) {
      throw UnsupportedError('No reviewed PlayStation card route');
    }
    final grant = await resolveRetroArchPcsxGrant(game, root);
    return PcsxSaveLayout.decode(await channel.invokeMapMethod<String, dynamic>(
        'reviewOwnedRetroArchPcsxSaves', grant));
  }

  /// Re-resolve durable installation/byte evidence for background card work.
  /// Never persist a launch URI or turn a filename into an ownership grant.
  Future<Map<String, Object>> resolveRetroArchPcsxGrant(
      GameItem game, String root) {
    if (game.isFolder ||
        game.remoteArtifact == null ||
        !game.filename.toLowerCase().endsWith('.chd')) {
      throw UnsupportedError('No reviewed PlayStation card route');
    }
    return _grant(game, 'psx', root);
  }

  /// Capture uses the same owned/byte-bound document as launch, never a title
  /// lookup. The native boundary rechecks this grant and current card settings.
  Future<CapturedSaveGroup> captureRetroArchPcsxSave(
      GameItem game, SystemModel system, String root,
      {required String captureId,
      required PcsxSaveLayout layout,
      required PcsxSaveCard card,
      bool restoreBaseline = false}) async {
    if (system.id != 'psx' || !supports(game, system)) {
      throw UnsupportedError('No reviewed PlayStation card route');
    }
    return SaveCapture().capturePcsx(
        captureId: captureId,
        grant: await resolveRetroArchPcsxGrant(game, root),
        layout: layout,
        card: card,
        restoreBaseline: restoreBaseline);
  }

  Future<void> _open(GameItem game, SystemModel system, String root,
      String? companionComponent, Future<void> Function()? prepareSave) async {
    String? exactPath;
    final grant = await _grant(game, system.id, root,
        resolvedPath: (path) => exactPath = path);
    await InstallationMutations.run(exactPath!, () async {
      await prepareSave?.call();
      if (companionComponent != null) {
        grant['companionComponent'] = companionComponent;
      }
      await channel.invokeMethod<void>(
          system.id == 'nds'
              ? 'launchOwnedMelon'
              : system.id == 'gamegear'
                  ? 'launchOwnedRetroArchGameGear'
                  : system.id == 'megadrive'
                      ? 'launchOwnedRetroArchMegaDrive'
                      : system.id == 'mastersystem'
                          ? 'launchOwnedRetroArchMasterSystem'
                          : system.id == 'sg1000'
                              ? 'launchOwnedRetroArchSG1000'
                              : system.id == 'n64'
                                  ? 'launchOwnedRetroArchN64'
                                  : system.id == 'nes'
                                      ? 'launchOwnedRetroArchNes'
                                      : system.id == 'snes'
                                          ? 'launchOwnedRetroArchSnes'
                                          : system.id == 'gb'
                                              ? 'launchOwnedRetroArchGameBoy'
                                              : system.id == 'gbc'
                                                  ? 'launchOwnedRetroArchGameBoyColor'
                                                  : system.id == 'gba'
                                                      ? 'launchOwnedRetroArchGameBoyAdvance'
                                                      : system.id == 'psx'
                                                          ? 'launchOwnedRetroArchPSX'
                                                          : system.id == 'psp'
                                                              ? 'launchOwnedPPSSPP'
                                                              : system.id ==
                                                                      'ps2'
                                                                  ? 'launchOwnedNetherSX2'
                                                                  : system.id ==
                                                                          'wiiu'
                                                                      ? 'launchOwnedCemu'
                                                                      : 'launchOwnedDolphin',
          grant);
      if (grant['installationId'] case final String id) {
        await romManager.recordSuccessfulLaunch(id);
      }
    });
  }
}
