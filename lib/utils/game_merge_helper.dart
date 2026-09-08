import 'package:flutter/foundation.dart';

import '../models/game_item.dart';
import '../models/system_model.dart';
import '../services/rom_manager.dart';

class GameMergeHelper {
  /// Merges remote provider games with locally-scanned games.
  ///
  /// Remote games win on filename collision (they have URL, cover, provider info).
  /// Local files that would be produced by extracting a remote archive are skipped.
  static List<GameItem> merge(
    List<GameItem> remoteGames,
    List<GameItem> localGames,
    SystemModel system,
  ) {
    // Compute local filenames that remote archives would produce after extraction
    // (e.g. "Game.zip" -> "Game.iso"), so we can skip redundant local entries.
    final remoteTargetNames = <String>{};
    for (final game in remoteGames) {
      // A local namesake is not proof that an exact remote object is installed.
      if (game.remoteArtifact != null) continue;
      final targetName = RomManager.getTargetFilename(game, system);
      if (targetName != game.filename) {
        remoteTargetNames.add(targetName);
      }
      // Multi-file archives extract to a folder with the stripped archive name
      if (system.multiFileExtensions != null &&
          system.multiFileExtensions!.isNotEmpty) {
        final folderName = RomManager.extractGameName(game.filename);
        if (folderName != null && folderName != game.filename) {
          remoteTargetNames.add(folderName);
        }
      }
    }

    // Merge: remote wins on filename collision (has URL, cover, provider info)
    final byFilename = <String, GameItem>{};
    for (final game in remoteGames) {
      byFilename[game.identityKey] = game;
    }
    for (final game in localGames) {
      if (remoteTargetNames.contains(game.filename)) {
        debugPrint('GameMergeHelper: skipping local "${game.filename}" '
            '(matches remote archive target)');
        continue;
      }
      if (byFilename.containsKey(game.identityKey)) {
        debugPrint('GameMergeHelper: local "${game.filename}" '
            'shadowed by remote with same filename');
        continue;
      }
      byFilename[game.identityKey] = game;
    }

    return byFilename.values.toList()
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  }
}
