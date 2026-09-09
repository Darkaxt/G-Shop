import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/game_item.dart';
import '../models/config/provider_config.dart';
import '../models/system_model.dart';
import 'installation_index.dart';
import 'installation_paths.dart';

class RomManager {
  final InstallationIndex? installations;
  RomManager({this.installations});

  static String safePath(String baseDir, String filename) {
    final sanitized = p.basename(filename);
    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
      throw Exception('Invalid filename: path traversal detected');
    }
    return '$baseDir/$sanitized';
  }

  static String getTargetPath(
      GameItem game, SystemModel system, String targetFolder) {
    return safePath(targetFolder, getTargetFilename(game, system));
  }

  /// Archive formats the app can extract. `.7z` is excluded because it is
  /// downloaded as-is (not extracted), so its extension must be preserved.
  static const _extractableExtensions = ['.zip', '.rar'];

  /// Returns the filename a game would have after download (archive → ROM extension).
  static String getTargetFilename(GameItem game, SystemModel system) {
    var filename = p.basename(game.filename);

    for (final ext in _extractableExtensions) {
      if (filename.toLowerCase().endsWith(ext)) {
        filename = filename.substring(0, filename.length - ext.length);
        filename =
            '$filename${system.romExtensions.isNotEmpty ? system.romExtensions.first : ''}';
        break;
      }
    }

    return filename;
  }

  static String? extractGameName(String filename) {
    var name = filename;

    for (final ext in SystemModel.archiveExtensions) {
      if (name.toLowerCase().endsWith(ext)) {
        name = name.substring(0, name.length - ext.length);
        break;
      }
    }

    name = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

    return name.isEmpty ? null : name;
  }

  static Future<List<GameItem>> scanLocalGames(
    SystemModel system,
    String targetFolder, {
    InstallationIndex? installations,
  }) async {
    try {
      if (InstallationIndex.isRedirectedPath(targetFolder)) return [];
      final dir = Directory(targetFolder);
      if (!await dir.exists()) return [];

      final entities = await dir.list(followLinks: false).toList();
      final games = _scanDirectory(
        entities,
        system.romExtensions,
        system.multiFileExtensions,
      );
      if (games.isEmpty) return games;
      final index = await (installations ?? InstallationIndex.application())
          .scan(targetFolder);
      return index.filterLocal(games, targetFolder);
    } on FileSystemException catch (e) {
      debugPrint('RomManager: cannot scan $targetFolder: $e');
      return [];
    }
  }

  /// Returns the actual file path of an installed ROM, or null if not found.
  /// Checks direct path first, then original archive, then subfolder fallback.
  static Future<String?> resolveInstalledPath(
      GameItem game, SystemModel system, String targetFolder,
      {InstallationIndex? installations}) async {
    if (game.remoteArtifact != null) {
      return (installations ?? InstallationIndex.application())
          .resolveArtifact(game.remoteArtifact!, targetFolder);
    }
    if (game.providerConfig?.type == ProviderType.drive) return null;
    final candidate = await _resolveLegacyPath(game, system, targetFolder);
    if (candidate == null || InstallationIndex.isRedirectedPath(candidate)) {
      return null;
    }
    final index = await (installations ?? InstallationIndex.application())
        .scan(targetFolder, verifyInstalled: false);
    return _allowsLegacyCandidate(index, candidate, game, targetFolder)
        ? candidate
        : null;
  }

  static bool _allowsLegacyCandidate(InstallationSnapshot index,
      String candidate, GameItem game, String root) {
    if (!index.allowsLegacy(candidate)) return false;
    final gameName = extractGameName(game.filename);
    if (gameName == null) return true;
    final folder = safePath(root, gameName);
    return !p.isWithin(folder, candidate) || index.allowsLegacy(folder);
  }

  static Future<String?> _resolveLegacyPath(
      GameItem game, SystemModel system, String targetFolder) async {
    try {
      final directPath = getTargetPath(game, system, targetFolder);
      if (await File(directPath).exists()) return directPath;

      // Check if the original archive file exists (e.g. Game.zip not yet extracted)
      final basename = p.basename(game.filename);
      if (basename != p.basename(directPath)) {
        final archivePath = safePath(targetFolder, basename);
        if (await File(archivePath).exists()) return archivePath;
      }

      final gameName = extractGameName(game.filename);
      if (gameName != null) {
        final subfolderPath = safePath(targetFolder, gameName);
        final subfolder = Directory(subfolderPath);
        if (await subfolder.exists()) {
          final validExts = {
            ...system.romExtensions.map((e) => e.toLowerCase()),
            ...?system.multiFileExtensions?.map((e) => e.toLowerCase()),
          };
          for (final file in subfolder.listSync()) {
            if (file is File) {
              final ext = p.extension(file.path).toLowerCase();
              if (validExts.contains(ext)) return file.path;
            }
          }
        }
      }

      return null;
    } on FileSystemException catch (e) {
      debugPrint(
          'RomManager: resolveInstalledPath failed for ${game.filename}: $e');
      return null;
    }
  }

  /// Like [resolveInstalledPath], but returns a [SharePathResult] indicating
  /// whether the path is a single file or a directory (multi-file ROM).
  static Future<SharePathResult?> resolveSharePath(
      GameItem game, SystemModel system, String targetFolder,
      {InstallationIndex? installations}) async {
    if (game.remoteArtifact != null) {
      final path = await resolveInstalledPath(game, system, targetFolder,
          installations: installations);
      return path == null ? null : SharePathResult(path, isDirectory: false);
    }
    if (game.providerConfig?.type == ProviderType.drive) return null;
    final candidate = await _resolveLegacySharePath(game, system, targetFolder);
    if (candidate == null ||
        InstallationIndex.isRedirectedPath(candidate.path)) {
      return null;
    }
    final index = await (installations ?? InstallationIndex.application())
        .scan(targetFolder, verifyInstalled: false);
    return index.allowsLegacy(candidate.path) ? candidate : null;
  }

  static Future<SharePathResult?> _resolveLegacySharePath(
      GameItem game, SystemModel system, String targetFolder) async {
    try {
      final directPath = getTargetPath(game, system, targetFolder);
      if (await File(directPath).exists()) {
        return SharePathResult(directPath, isDirectory: false);
      }

      final basename = p.basename(game.filename);
      if (basename != p.basename(directPath)) {
        final archivePath = safePath(targetFolder, basename);
        if (await File(archivePath).exists()) {
          return SharePathResult(archivePath, isDirectory: false);
        }
      }

      final gameName = extractGameName(game.filename);
      if (gameName != null) {
        final subfolderPath = safePath(targetFolder, gameName);
        final subfolder = Directory(subfolderPath);
        if (await subfolder.exists()) {
          final validExts = {
            ...system.romExtensions.map((e) => e.toLowerCase()),
            ...?system.multiFileExtensions?.map((e) => e.toLowerCase()),
          };
          // Verify subfolder actually contains ROM files
          final hasRomFiles = subfolder.listSync().any((f) =>
              f is File &&
              validExts.contains(p.extension(f.path).toLowerCase()));
          final hasLinks = subfolder
              .listSync(recursive: true, followLinks: false)
              .any((entity) => entity is Link);
          if (hasRomFiles && !hasLinks) {
            return SharePathResult(subfolderPath, isDirectory: true);
          }
        }
      }

      return null;
    } on FileSystemException catch (e) {
      debugPrint(
          'RomManager: resolveSharePath failed for ${game.filename}: $e');
      return null;
    }
  }

  Future<bool> exists(
          GameItem game, SystemModel system, String targetFolder) async =>
      await resolveInstalledPath(game, system, targetFolder,
          installations: installations) !=
      null;

  Future<Map<int, bool>> checkMultipleExists(
    List<GameItem> variants,
    SystemModel system,
    String targetFolder,
  ) async {
    final candidates = <int, String>{};
    var hasExact = false;
    for (int i = 0; i < variants.length; i++) {
      final game = variants[i];
      if (game.remoteArtifact != null) {
        hasExact = true;
      } else if (game.providerConfig?.type != ProviderType.drive) {
        final path = await _resolveLegacyPath(game, system, targetFolder);
        if (path != null && !InstallationIndex.isRedirectedPath(path)) {
          candidates[i] = path;
        }
      }
    }
    if (!hasExact && candidates.isEmpty) {
      return {for (var i = 0; i < variants.length; i++) i: false};
    }
    final service = installations ?? InstallationIndex.application();
    final index = await service.scan(targetFolder, verifyInstalled: false);
    final exact = <int, bool>{};
    for (var i = 0; i < variants.length; i++) {
      final artifact = variants[i].remoteArtifact;
      if (artifact != null) {
        exact[i] =
            await service.resolveArtifact(artifact, targetFolder) != null;
      }
    }
    return {
      for (var i = 0; i < variants.length; i++)
        i: variants[i].remoteArtifact != null
            ? exact[i] == true
            : candidates[i] != null &&
                _allowsLegacyCandidate(
                    index, candidates[i]!, variants[i], targetFolder)
    };
  }

  Future<void> delete(GameItem game, SystemModel system, String targetFolder) =>
      InstallationMutations.run(
          targetFolder, () => _deleteLegacy(game, system, targetFolder));

  Future<void> _deleteLegacy(
      GameItem game, SystemModel system, String targetFolder) async {
    if (InstallationIndex.isRedirectedPath(targetFolder) ||
        InstallationIndex.isRedirectedPath(
            getTargetPath(game, system, targetFolder))) {
      throw StateError('Redirected ROM paths cannot use legacy removal');
    }
    if (game.remoteArtifact != null ||
        game.providerConfig?.type == ProviderType.drive) {
      throw StateError(
          'Managed ROM paths require verified installation removal');
    }
    Future<void> requireUnmanaged(String candidate) async {
      // Existence is observed first: any publisher that created this object
      // must already have committed its ownership/intent before this DB read.
      final index = await (installations ?? InstallationIndex.application())
          .scan(targetFolder, verifyInstalled: false);
      if (InstallationIndex.isRedirectedPath(candidate) ||
          index.protects(candidate)) {
        throw StateError(
            'Managed or redirected ROM paths cannot use legacy removal');
      }
    }

    try {
      final path = getTargetPath(game, system, targetFolder);
      final file = File(path);
      if (await file.exists()) {
        await requireUnmanaged(path);
        await file.delete();
        return;
      }

      // Check if the original archive file exists (e.g. Game.zip not extracted)
      final basename = p.basename(game.filename);
      if (basename != p.basename(path)) {
        final archivePath = safePath(targetFolder, basename);
        final archiveFile = File(archivePath);
        if (await archiveFile.exists()) {
          await requireUnmanaged(archivePath);
          await archiveFile.delete();
          return;
        }
      }

      final gameName = extractGameName(game.filename);
      if (gameName != null) {
        final subfolderPath = safePath(targetFolder, gameName);
        final subfolder = Directory(subfolderPath);
        if (await subfolder.exists()) {
          await requireUnmanaged(subfolderPath);
          await subfolder.delete(recursive: true);
        }
      }
    } on FileSystemException catch (e) {
      debugPrint('RomManager: delete failed for ${game.filename}: $e');
    }
  }

  Future<Set<String>> getInstalledFilenames(
    List<GameItem> variants,
    SystemModel system,
    String targetFolder,
  ) async {
    final status = await checkMultipleExists(variants, system, targetFolder);
    return {
      for (var i = 0; i < variants.length; i++)
        if (status[i] == true) variants[i].filename
    };
  }

  Future<bool> isAnyVariantInstalled(
    List<GameItem> variants,
    SystemModel system,
    String targetFolder,
  ) async {
    final status = await checkMultipleExists(variants, system, targetFolder);
    return status.values.any((installed) => installed);
  }

  /// Scans local games in an isolate. Used for bulk discovery where
  /// sequential scanning of many systems benefits from isolate offloading.
  static Future<List<GameItem>> scanLocalGamesIsolate(
    SystemModel system,
    String targetFolder, {
    InstallationIndex? installations,
  }) async {
    if (InstallationIndex.isRedirectedPath(targetFolder)) return [];
    final games = await compute(
      _scanLocalGamesIsolateEntry,
      _ScanParams(
        targetFolder: targetFolder,
        romExtensions: system.romExtensions,
        multiFileExtensions: system.multiFileExtensions,
      ),
    );
    if (games.isEmpty) return games;
    // Read durable evidence after the asynchronous enumeration, never before.
    final index = await (installations ?? InstallationIndex.application())
        .scan(targetFolder);
    return index.filterLocal(games, targetFolder);
  }

  /// Shared 2-pass scan logic used by both main-thread and isolate scanners.
  static List<GameItem> _scanDirectory(
    List<FileSystemEntity> entities,
    List<String> romExtensions,
    List<String>? multiFileExtensions,
  ) {
    final allExtensions = [
      ...romExtensions.map((e) => e.toLowerCase()),
      ...SystemModel.archiveExtensions,
    ];
    final multiExts =
        multiFileExtensions?.map((e) => e.toLowerCase()).toList() ?? [];

    final dirNames = <String>{};
    final games = <GameItem>[];

    // Pass 1: Directories containing ROM files
    final subDirExts = {
      ...romExtensions.map((e) => e.toLowerCase()),
      ...multiExts,
    };
    for (final entity in entities) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      List<FileSystemEntity> subFiles;
      try {
        subFiles = entity.listSync(recursive: true, followLinks: false);
      } on FileSystemException catch (e) {
        debugPrint('RomManager: cannot list subdirectory $name: $e');
        continue;
      }
      final hasMatchingFile = subFiles.any((f) =>
          f is File && subDirExts.contains(p.extension(f.path).toLowerCase()));
      if (hasMatchingFile) {
        dirNames.add(name);
        games.add(GameItem(
          filename: name,
          displayName: GameItem.cleanDisplayName(name),
          url: '',
        ));
      }
    }

    // Pass 2: Individual files (skip if a multi-file dir with same base name exists)
    for (final entity in entities) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final ext = p.extension(name).toLowerCase();
      if (!allExtensions.contains(ext)) continue;
      if (dirNames.contains(p.basenameWithoutExtension(name))) continue;
      games.add(GameItem(
        filename: name,
        displayName: GameItem.cleanDisplayName(name),
        url: '',
      ));
    }

    games.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return games;
  }
}

/// Result of resolving a ROM's share path.
class SharePathResult {
  final String path;
  final bool isDirectory;
  const SharePathResult(this.path, {required this.isDirectory});
}

class _ScanParams {
  final String targetFolder;
  final List<String> romExtensions;
  final List<String>? multiFileExtensions;

  const _ScanParams({
    required this.targetFolder,
    required this.romExtensions,
    this.multiFileExtensions,
  });
}

Future<List<GameItem>> _scanLocalGamesIsolateEntry(_ScanParams params) async {
  try {
    final dir = Directory(params.targetFolder);
    if (!await dir.exists()) return [];

    final entities = await dir.list(followLinks: false).toList();
    return RomManager._scanDirectory(
      entities,
      params.romExtensions,
      params.multiFileExtensions,
    );
  } on FileSystemException catch (e) {
    debugPrint('RomManager: isolate scan failed: $e');
    return [];
  }
}
