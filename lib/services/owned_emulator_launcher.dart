import 'package:flutter/services.dart';
import '../models/game_item.dart';
import '../models/system_model.dart';
import 'rom_manager.dart';

/// First ordinary emulator handoff: Dolphin's existing launcher accepts a
/// granted content URI. No source access, emulator setup mutation or companions.
class OwnedEmulatorLauncher {
  final RomManager romManager;
  final MethodChannel channel;
  final _opening = <String, Future<void>>{};
  OwnedEmulatorLauncher({RomManager? romManager,
      this.channel = const MethodChannel('com.retro.rshop/storage')})
      : romManager = romManager ?? RomManager();

  static bool supports(GameItem game, SystemModel system) =>
      game.remoteArtifact != null && !game.isFolder &&
      const {'gc', 'wii'}.contains(system.id) &&
      system.romExtensions.any((ext) => game.filename.toLowerCase().endsWith(ext));

  Future<void> open(GameItem game, SystemModel system, String root) {
    if (!supports(game, system)) {
      return Future.error(UnsupportedError('No verified emulator handoff for this format'));
    }
    final key = game.selectionKey;
    final current = _opening[key];
    if (current != null) return current;
    final operation = _open(game, root);
    _opening[key] = operation;
    // Clear after acknowledgement, retaining the original error on the caller.
    operation.then<void>((_) => _opening.remove(key),
        onError: (Object _, StackTrace __) { _opening.remove(key); });
    return operation;
  }

  Future<void> _open(GameItem game, String root) async {
    final installed = await romManager.requireInstalledArtifact(game, root);
    await channel.invokeMethod<void>('launchOwnedDolphin', {
      'installationId': installed.id, 'filename': installed.relativePath,
    });
  }
}
