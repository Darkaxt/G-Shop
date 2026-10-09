import 'package:flutter/foundation.dart';

import '../models/game_item.dart';
import '../models/library_identity.dart';
import '../models/config/provider_config.dart';
import '../models/system_model.dart';
import '../services/rom_manager.dart';
import '../services/installation_index.dart';

class GameMergeHelper {
  /// Read-only projection of proven local paths onto current sourced objects.
  /// Missing historical copies can retire a stale local cache card, but cannot
  /// claim residency. Changed/inaccessible paths never enter [observations].
  static Map<String, String> verifiedSelectionAliases(
      List<GameItem> games, Map<String, RemoteArtifact> observations) {
    final sourced = <String, RemoteArtifact>{
      for (final game in games)
        if (game.remoteArtifact != null &&
            game.providerConfig?.type == ProviderType.drive)
          game.remoteArtifact!.id.key: game.remoteArtifact!,
    };
    final otherSources = {
      for (final game in games)
        if (game.remoteArtifact == null && game.hasDownloadSource)
          game.filename,
    };
    return {
      for (final entry in observations.entries)
        if (!otherSources.contains(entry.key))
          if (sourced[entry.value.id.key] case final current?)
            if (InstallationSnapshot.sameContent(entry.value, current))
              entry.key: 'artifact:${current.id.key}',
    };
  }

  static List<GameItem> coalesceVerifiedCopies(
      List<GameItem> games, Map<String, RemoteArtifact> observations) {
    final aliases = verifiedSelectionAliases(games, observations);
    final visible = <String, GameItem>{};
    for (final game in games) {
      if (game.remoteArtifact == null &&
          !game.hasDownloadSource &&
          aliases.containsKey(game.filename)) {
        continue;
      }
      final previous = visible[game.identityKey];
      if (previous == null ||
          (!previous.hasDownloadSource && game.hasDownloadSource)) {
        visible[game.identityKey] = game;
      }
    }
    return visible.values.toList();
  }

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
      if (game.remoteArtifact == null &&
          remoteTargetNames.contains(game.filename)) {
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
