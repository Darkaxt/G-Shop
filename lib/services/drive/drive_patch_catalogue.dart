import 'package:dio/dio.dart';

import '../../models/config/provider_config.dart';
import '../../models/library_identity.dart';
import '../../models/patch_catalogue.dart';
import '../../models/patch_chain.dart';
import '../../models/portable_patch_recipe.dart';
import 'drive_catalogue.dart';
import 'drive_runtime.dart';

class IndexedPatchGame {
  final String sourceGameId;
  final String title;
  final PatchRelativePath indexPath;
  const IndexedPatchGame(this.sourceGameId, this.title, this.indexPath);
}

class ResolvedPatchRecipe {
  final IndexedPatchGame game;
  final IndexedRomPatch patch;
  final IndexedPatchPayload payload;
  final IndexedPatchBase base;
  final List<IndexedRomPatch> availablePatches;
  const ResolvedPatchRecipe(this.game, this.patch, this.payload, this.base,
      [this.availablePatches = const []]);
}

class PatchRecipeRequirements {
  final ResolvedPatchRecipe? resolved;
  final List<String> missing;
  const PatchRecipeRequirements(this.resolved, this.missing);
}

/// Source-root-relative producer references resolve through published folder IDs.
/// Duplicate Drive names, source changes and unsafe references fail explicitly;
/// neither display-name matching nor authenticated saved URLs are involved.
class DrivePatchCatalogue {
  final DriveRuntime runtime;
  final ProviderConfig config;
  final bool localOnly;
  DrivePatchCatalogue(this.config,
      {DriveRuntime? runtime, this.localOnly = false})
      : runtime = runtime ?? DriveRuntime.instance;

  Future<Map<String, dynamic>> _readArtifact(
      RemoteArtifact artifact, CancelToken cancellation) async {
    if (cancellation.isCancelled) {
      throw const DriveCatalogueException('cancelled');
    }
    final cached = await runtime.catalogue.cachedPatchIndex(artifact);
    if (cached != null) return cached;
    if (localOnly) throw const DriveCatalogueException('patchIndexNotCached');
    return runtime.readPatchIndex(
        config: config, artifact: artifact, cancellation: cancellation);
  }

  /// Explicit sync/Patches work prepares metadata; launch checks remain local.
  Future<void> refreshIndexes(CancelToken cancellation) async {
    for (final game in await games(cancellation)) {
      final available = await patches(game, cancellation);
      await rememberBases(game, available);
    }
  }

  Future<void> rememberBases(
      IndexedPatchGame game, List<IndexedRomPatch> available) async {
    final generation = await _generation();
    final drive = config.drive!;
    final ids = <String>{};
    for (final patch in available) {
      if (patch.requires != null) {
        continue; // Original inputs live at chain roots.
      }
      for (final base in patch.bases) {
        try {
          ids.add((await resolve(base.relativePath)).id.providerFileId);
        } on DriveCatalogueException catch (error) {
          if (error.code != 'ambiguousOrMissingDependency') rethrow;
        }
      }
    }
    await runtime.catalogue.cachePatchBaseLinks(
        scope: DriveCatalogue.scopeKey(
            config.sourceId!, drive.accountId, drive.rootFolderId),
        generation: generation,
        folderId: config.path!,
        indexPath: game.indexPath.value,
        gameId: game.sourceGameId,
        title: game.title,
        baseFileIds: ids);
  }

  Future<List<IndexedPatchGame>> cachedGamesFor(RemoteArtifact artifact) async {
    final drive = config.drive;
    if (drive == null ||
        artifact.id.sourceId != config.sourceId ||
        artifact.id.accountId != drive.accountId) {
      return const [];
    }
    final rows = await runtime.catalogue.cachedPatchGames(
        scope: DriveCatalogue.scopeKey(
            config.sourceId!, drive.accountId, drive.rootFolderId),
        generation: await _generation(),
        folderId: config.path!,
        baseFileId: artifact.id.providerFileId);
    return [
      for (final row in rows)
        IndexedPatchGame(row['game_id'] as String, row['title'] as String,
            PatchRelativePath(row['index_path'] as String))
    ];
  }

  Future<PatchRecipeRequirements> resolveRecipe(
      PortablePatchRecipe portable, CancelToken cancellation) async {
    final candidates = (await games(cancellation))
        .where((game) => game.sourceGameId == portable.sourceGameId);
    var patchFound = false;
    final step = portable.recipe.steps.last;
    for (final game in candidates) {
      final available = await patches(game, cancellation);
      patchFound = patchFound ||
          available.any((patch) =>
              patch.source == step.source &&
              patch.section == step.section &&
              patch.sourceId == step.sourceId &&
              patch.version == step.version &&
              patch.payloads.any((payload) =>
                  payload.sha256 == step.patchSha256 &&
                  payload.format == step.format));
      final found = matchRecipe(portable, game, available);
      if (found != null) return PatchRecipeRequirements(found, const []);
    }
    return PatchRecipeRequirements(null, [
      if (!patchFound) 'Exact patch version',
      'Original game fingerprints',
    ]);
  }

  /// Producer paths may differ on another source. Rebuild only when the entire
  /// declared content/engine recipe still agrees, not by filename or title.
  static ResolvedPatchRecipe? matchRecipe(PortablePatchRecipe portable,
      IndexedPatchGame game, List<IndexedRomPatch> patches) {
    if (game.sourceGameId != portable.sourceGameId) {
      return null;
    }
    final step = portable.recipe.steps.last;
    for (final patch in patches) {
      if (patch.source != step.source ||
          patch.section != step.section ||
          patch.sourceId != step.sourceId ||
          patch.version != step.version ||
          patch.unavailableReason != null) {
        continue;
      }
      for (final payload in patch.payloads) {
        if (payload.sha256 != step.patchSha256 ||
            payload.format != step.format) {
          continue;
        }
        final PatchChain chain;
        try {
          chain = PatchChain.resolve(patches, patch, payload);
        } on FormatException {
          continue;
        }
        for (final base in chain.bases) {
          final candidate = PatchRecipe(
              platformId: portable.recipe.platformId,
              base: base,
              steps: chain.recipeSteps,
              engineRevision: portable.recipe.engineRevision,
              preprocessing: portable.recipe.preprocessing);
          if (candidate.id == portable.recipe.id) {
            return ResolvedPatchRecipe(game, patch, payload, base, patches);
          }
        }
      }
    }
    return null;
  }

  Future<int> _generation() async {
    final drive = config.drive;
    if (drive == null || config.sourceId == null || config.path == null) {
      throw const DriveCatalogueException('mappingRequired');
    }
    final generation = await runtime.catalogue.activeGeneration(
        sourceId: config.sourceId!,
        accountId: drive.accountId,
        rootFolderId: drive.rootFolderId);
    if (generation == null) {
      throw const DriveCatalogueException('refreshRequired');
    }
    return generation;
  }

  Future<RemoteArtifact> resolve(PatchRelativePath reference) async {
    final generation = await _generation();
    final drive = config.drive!;
    final entry = await runtime.catalogue.requireRelativeBinary(
        sourceId: config.sourceId!,
        accountId: drive.accountId,
        rootFolderId: drive.rootFolderId,
        parentId: drive.rootFolderId,
        segments: reference.segments,
        generation: generation);
    return entry.file.artifact(
        sourceId: config.sourceId!,
        accountId: drive.accountId,
        displayPath: entry.displayPath);
  }

  Future<Map<String, dynamic>> read(
          PatchRelativePath reference, CancelToken cancellation) async =>
      _readArtifact(await resolve(reference), cancellation);

  /// Navigation availability reads the published local snapshot only. It does
  /// not download/parse an index, authenticate or start a catalogue refresh.
  Future<bool> hasCachedIndex() async {
    try {
      final generation = await _generation();
      final drive = config.drive!;
      await runtime.catalogue.requireRelativeBinary(
          sourceId: config.sourceId!,
          accountId: drive.accountId,
          rootFolderId: drive.rootFolderId,
          parentId: config.path!,
          segments: const ['Patches', 'index.json'],
          generation: generation);
      return true;
    } on DriveCatalogueException catch (error) {
      if ({
        'mappingRequired',
        'refreshRequired',
        'ambiguousOrMissingDependency',
        'unsupportedDependency'
      }.contains(error.code)) {
        return false;
      }
      rethrow;
    }
  }

  Future<List<IndexedPatchGame>> games(CancelToken cancellation) async {
    final generation = await _generation();
    final drive = config.drive!;
    final entry = await runtime.catalogue.requireRelativeBinary(
        sourceId: config.sourceId!,
        accountId: drive.accountId,
        rootFolderId: drive.rootFolderId,
        parentId: config.path!,
        segments: const ['Patches', 'index.json'],
        generation: generation);
    final index = await _readArtifact(
        entry.file.artifact(
            sourceId: config.sourceId!,
            accountId: drive.accountId,
            displayPath: entry.displayPath),
        cancellation);
    if (index['schema_version'] != 2 || index['games'] is! List) {
      throw const FormatException('unsupported_patch_index_schema');
    }
    final ids = <String>{};
    return [
      for (final value in index['games'] as List)
        () {
          final row = (value as Map).cast<String, dynamic>();
          final id = row['source_game_id']?.toString();
          final title = row['title'];
          if (id == null || title is! String || title.isEmpty || !ids.add(id)) {
            throw const FormatException('invalid_patch_game_reference');
          }
          return IndexedPatchGame(id, title,
              PatchRelativePath(row['rom_root_relative_path'] as String));
        }(),
    ];
  }

  Future<List<IndexedRomPatch>> patches(
      IndexedPatchGame game, CancelToken cancellation) async {
    final index = await read(game.indexPath, cancellation);
    if (index['schema_version'] != 2 ||
        index['source_game_id']?.toString() != game.sourceGameId ||
        index['sources'] is! List) {
      throw const FormatException('invalid_patch_game_index');
    }
    final result = <IndexedRomPatch>[];
    final identities = <String>{};
    for (final value in index['sources'] as List) {
      final source = (value as Map).cast<String, dynamic>();
      final document = await read(
          PatchRelativePath(source['rom_root_relative_path'] as String),
          cancellation);
      if (document['source'] != source['source'] ||
          document['source_game_id']?.toString() != game.sourceGameId) {
        throw const FormatException('patch_source_identity_mismatch');
      }
      for (final patch in PatchSourceIndex.fromJson(document).patches) {
        if (!identities.add(patch.id)) {
          throw const FormatException('duplicate_patch_identity');
        }
        result.add(patch);
      }
    }
    return result;
  }
}
