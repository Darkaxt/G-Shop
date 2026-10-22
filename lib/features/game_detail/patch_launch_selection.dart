import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/input/input.dart';
import '../../models/game_item.dart';
import '../../models/library_identity.dart';
import '../../models/patch_catalogue.dart';
import '../../models/patch_chain.dart';
import '../../models/system_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/game_providers.dart';
import '../../providers/library_providers.dart';
import '../../services/config_bootstrap.dart';
import '../../services/drive/drive_patch_catalogue.dart';
import '../../services/patch_build_service.dart';
import '../../services/source_resolver.dart';
import '../library/patch_library_screen.dart';

class PatchLaunchTarget {
  final GameItem game;
  final String target;
  const PatchLaunchTarget(this.game, this.target);
}

/// Selection happens before animation; it never owns the eventual emulator launch.
/// Availability uses only the published catalogue and verified metadata cache.
Future<PatchLaunchTarget> choosePatchLaunch(WidgetRef ref, BuildContext context,
    GameItem original, SystemModel system, String target) async {
  final artifact = original.remoteArtifact;
  if (artifact == null || artifact.id.providerId == 'patch-build') {
    debugPrint(
        'GShopPatchLaunch {"phase":"bypass","derived":${artifact?.id.providerId == 'patch-build'}}');
    return PatchLaunchTarget(original, target);
  }
  final storage = ref.read(storageServiceProvider);
  final key =
      '${system.id}_${sha256.convert(utf8.encode(original.raMatchKey))}';
  final remembered = storage.getPatchLaunchChoice(key);
  if (remembered == 'original') return PatchLaunchTarget(original, target);
  final service =
      PatchBuildService(database: ref.read(libraryDbProvider).database);
  final candidates = <PatchGameData>[];
  final bases = <IndexedPatchBase>[];
  final builds = <Map<String, dynamic>>[];
  var unavailablePreference = false;
  try {
    final config = ref.read(bootstrappedConfigProvider).value;
    final mapping =
        config == null ? null : ConfigBootstrap.configForSystem(config, system);
    if (mapping != null) {
      for (final provider
          in SourceResolver.providersFor(mapping, config!.sources)) {
        if (provider.sourceId != artifact.id.sourceId ||
            provider.drive == null) {
          continue;
        }
        final catalogue = DrivePatchCatalogue(provider, localOnly: true);
        for (final game in await catalogue.cachedGamesFor(artifact)) {
          final patches = await catalogue.patches(game, CancelToken());
          final matched = <String, GameItem>{};
          final compatible = <IndexedRomPatch>[];
          for (final patch in patches) {
            for (final payload in patch.payloads) {
              try {
                final chain = PatchChain.resolve(patches, patch, payload);
                for (final base in chain.bases) {
                  if ((await catalogue.resolve(base.relativePath)).id ==
                      artifact.id) {
                    matched[base.relativePath.value] = original;
                    bases.add(base);
                    if (!compatible.contains(patch)) compatible.add(patch);
                  }
                }
              } on FormatException {/* Not a compatible declared chain. */}
            }
          }
          if (matched.isNotEmpty && compatible.isNotEmpty) {
            // Retain prerequisites in the data; only matching roots are selectable.
            candidates.add(PatchGameData(catalogue, game, patches, matched,
                sourceId: provider.sourceId!));
          }
        }
      }
    }
  } catch (error) {
    // Unavailable metadata is unknown, not "no patches". Original stays playable.
    debugPrint('Patch launch availability unknown: ${error.runtimeType}');
  }
  for (final row in await service.store.localForPlatform(system.id)) {
    if (row['state'] != 'ready') continue;
    final recipe =
        PatchRecipe.fromJson((row['recipe'] as Map).cast<String, dynamic>());
    final declared = row['baseArtifact'] == null
        ? null
        : RemoteArtifact.fromJson(
            (row['baseArtifact'] as Map).cast<String, dynamic>());
    final exactArtifact = declared?.id == artifact.id &&
        declared?.version == artifact.version &&
        declared?.sizeBytes == artifact.sizeBytes &&
        declared!.providerChecksums.length ==
            artifact.providerChecksums.length &&
        declared.providerChecksums.entries
            .every((e) => artifact.providerChecksums[e.key] == e.value);
    final exactBase = bases.any((base) =>
        base.sizeBytes == recipe.base.sizeBytes &&
        base.checksums.length == recipe.base.checksums.length &&
        base.checksums.entries
            .every((e) => recipe.base.checksums[e.key] == e.value));
    if (exactArtifact || exactBase) builds.add(row);
  }
  if (!context.mounted) throw PlatformException(code: 'cancelled');
  if (remembered != null) {
    for (final row in builds) {
      final recipe =
          PatchRecipe.fromJson((row['recipe'] as Map).cast<String, dynamic>());
      if (recipe.id != remembered) continue;
      final existing = await service.existing(recipe, CancelToken());
      if (existing != null) {
        return PatchLaunchTarget(existing.game, existing.targetRoot);
      }
    }
    await storage.setPatchLaunchChoice(key, null);
    unavailablePreference = true;
    builds.removeWhere((row) =>
        PatchRecipe.fromJson((row['recipe'] as Map).cast<String, dynamic>())
            .id ==
        remembered);
  }
  if (candidates.isEmpty && builds.isEmpty && !unavailablePreference) {
    return PatchLaunchTarget(original, target);
  }
  if (!context.mounted) {
    throw PlatformException(code: 'cancelled');
  }
  final decision = await showPatchLaunchChoice(context,
      builds: builds,
      candidates: candidates,
      unavailablePreference: unavailablePreference);
  final choice = decision.choice;
  final remember = decision.remember;
  if (!context.mounted || choice == null) {
    throw PlatformException(code: 'cancelled');
  }
  if (choice == 'original') {
    if (remember) await storage.setPatchLaunchChoice(key, 'original');
    return PatchLaunchTarget(original, target);
  }
  PatchBuildResult? selected;
  if (choice is Map<String, dynamic>) {
    selected = await service.existing(
        PatchRecipe.fromJson((choice['recipe'] as Map).cast<String, dynamic>()),
        CancelToken());
    if (selected == null) {
      throw PlatformException(code: 'installation_unavailable');
    }
  } else if (choice is PatchGameData) {
    selected = await Navigator.push<PatchBuildResult>(
        context,
        MaterialPageRoute(
            builder: (_) => PatchGameScreen(
                system: system,
                targetFolder: target,
                row: choice,
                selectForLaunch: true,
                launchBases: bases,
                collection: [original])));
  }
  if (!context.mounted || selected == null) {
    throw PlatformException(code: 'cancelled');
  }
  if (remember) await storage.setPatchLaunchChoice(key, selected.recipe.id);
  return PatchLaunchTarget(selected.game, selected.targetRoot);
}

/// The same controller/touch dialog used by both launch entry points.
Future<({Object? choice, bool remember})> showPatchLaunchChoice(
    BuildContext context,
    {required List<Map<String, dynamic>> builds,
    required List<PatchGameData> candidates,
    bool unavailablePreference = false}) async {
  var remember = false;
  debugPrint('GShopPatchLaunch ${jsonEncode({
        'phase': 'choice-ready',
        'builds': builds.length,
        'patchGames': candidates.length,
        'unavailablePreference': unavailablePreference
      })}');
  final choice = await showConsoleDialog<Object>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
                title: const Text('Choose what to play'),
                content: SizedBox(
                    width: 480,
                    child: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      if (unavailablePreference)
                        const Text(
                            'Your remembered build is missing or changed. Choose the original or rebuild from the available patches.'),
                      ListTile(
                          autofocus: true,
                          leading: const Icon(Icons.play_arrow),
                          title: const Text('Play original'),
                          onTap: () => Navigator.pop(context, 'original')),
                      for (final row in builds)
                        ListTile(
                            leading: const Icon(Icons.check_circle_outline),
                            title: Text(row['title'] as String),
                            subtitle: const Text(
                                'Installed build · verified before launch'),
                            onTap: () => Navigator.pop(context, row)),
                      for (final row in candidates)
                        ListTile(
                            leading: const Icon(Icons.extension_outlined),
                            title: const Text('Choose a compatible patch'),
                            subtitle: Text(row.game.title),
                            onTap: () => Navigator.pop(context, row)),
                      CheckboxListTile(
                          value: remember,
                          title: const Text('Remember my choice for this ROM'),
                          onChanged: (value) =>
                              update(() => remember = value == true)),
                    ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'))
                ],
              )));
  return (choice: choice, remember: remember);
}
