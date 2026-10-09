import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/config/app_config.dart';
import '../models/library_identity.dart';
import '../models/system_model.dart';
import '../services/installation_index.dart';
import 'game_providers.dart';
import 'rom_status_providers.dart';

class InstalledFilesState {
  /// systemId → unmanaged basenames found in that system's target folder.
  final Map<String, Set<String>> bySystem;

  /// Flat union of all filenames across every system.
  final Set<String> all;

  /// Verified managed files are never filename evidence for another game.
  final Map<String, List<RemoteArtifact>> exactBySystem;

  /// Bytes of verified manifest-owned files, including bundle dependencies.
  /// This is not whole-volume usage; unmanaged files have no cached size here.
  final Map<String, int> managedBytesBySystem;

  InstalledFilesState({
    this.bySystem = const {},
    this.all = const {},
    Map<String, List<RemoteArtifact>> exactBySystem = const {},
    this.managedBytesBySystem = const {},
  }) : exactBySystem = Map.unmodifiable({
          for (final entry in exactBySystem.entries)
            entry.key: List<RemoteArtifact>.unmodifiable(entry.value),
        });

  // Build once per immutable installation snapshot, not once per card/header
  // query. Keep all versions for an object: a matching ID is only a candidate,
  // never a substitute for the full content check below.
  late final _exactById = {
    for (final system in exactBySystem.entries)
      system.key: <RemoteArtifactId, List<RemoteArtifact>>{},
  }..forEach((system, byId) {
      for (final artifact in exactBySystem[system]!) {
        (byId[artifact.id] ??= []).add(artifact);
      }
    });

  bool hasExactArtifact(String systemId, RemoteArtifact artifact) =>
      _exactById[systemId]?[artifact.id]?.any((installed) =>
          InstallationSnapshot.sameContent(installed, artifact)) ??
      false;
}

/// Central index of all installed ROM files, scanned on an isolate.
/// Re-scans whenever [romChangeSignalProvider] bumps.
final installedFilesProvider = FutureProvider<InstalledFilesState>((ref) async {
  ref.watch(romChangeSignalProvider);
  final config = await ref.watch(bootstrappedConfigProvider.future);
  final candidates = await compute(_scanAllSystems, config);
  final bySystem = <String, Set<String>>{};
  final exactBySystem = <String, List<RemoteArtifact>>{};
  final managedBytesBySystem = <String, int>{};
  final all = <String>{};
  final index = InstallationIndex.application();
  for (final sysConfig in config.systems) {
    final paths = candidates[sysConfig.id];
    if (paths == null) continue;
    // Read journal truth after enumeration so newly published files cannot use
    // an exclusion snapshot captured before their public create/rename.
    final snapshot = await index.scan(sysConfig.targetFolder);
    final filenames =
        paths.where(snapshot.allowsLegacy).map(p.basename).toSet();
    bySystem[sysConfig.id] = filenames;
    all.addAll(filenames);
    exactBySystem[sysConfig.id] = snapshot.installed.values
        .map((installation) => installation.artifact)
        .toList();
    final files = <String, int>{};
    for (final installation in snapshot.installed.values) {
      for (final member in [installation, ...installation.dependencies]) {
        // Bundled members can also occur in the index. Count each owned path
        // once, never a source estimate or an uncommitted publication.
        files[p.normalize(
                p.join(member.destinationRoot, member.relativePath))] =
            member.sizeBytes;
      }
    }
    managedBytesBySystem[sysConfig.id] =
        files.values.fold(0, (sum, bytes) => sum + bytes);
  }
  return InstalledFilesState(
      bySystem: bySystem,
      all: all,
      exactBySystem: exactBySystem,
      managedBytesBySystem: managedBytesBySystem);
});

Map<String, Set<String>> _scanAllSystems(AppConfig config) {
  final bySystem = <String, Set<String>>{};

  // Build valid ROM extensions per system (includes multiFileExtensions)
  final extsBySystem = <String, Set<String>>{};
  for (final sysConfig in config.systems) {
    final system = SystemModel.supportedSystems
        .where((s) => s.id == sysConfig.id)
        .firstOrNull;
    if (system != null) {
      extsBySystem[sysConfig.id] = {
        ...system.romExtensions.map((e) => e.toLowerCase()),
        if (system.multiFileExtensions != null)
          ...system.multiFileExtensions!.map((e) => e.toLowerCase()),
      };
    }
  }

  for (final sysConfig in config.systems) {
    if (sysConfig.targetFolder.isEmpty) continue;
    if (InstallationIndex.isRedirectedPath(sysConfig.targetFolder)) continue;
    final dir = Directory(sysConfig.targetFolder);
    if (!dir.existsSync()) continue;
    final filenames = <String>{};
    final validExts = extsBySystem[sysConfig.id] ?? {};
    try {
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is Directory) {
          // Only count directories that contain ROM files (one level deep)
          if (_directoryContainsRom(entity, validExts)) {
            filenames.add(entity.path);
          }
        } else if (entity is File) {
          filenames.add(entity.path);
        }
      }
    } catch (e) {
      debugPrint('InstalledFiles: listSync failed: $e');
    }
    bySystem[sysConfig.id] = filenames;
  }

  return bySystem;
}

/// Checks if a directory contains at least one file with a valid ROM extension.
bool _directoryContainsRom(Directory dir, Set<String> validExts) {
  if (validExts.isEmpty) return true;
  try {
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is File &&
          validExts.contains(p.extension(entity.path).toLowerCase())) {
        return true;
      }
    }
  } catch (e) {
    debugPrint('InstalledFiles: subfolder scan failed: $e');
  }
  return false;
}
