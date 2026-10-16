import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/game_item.dart';
import '../models/library_identity.dart';
import '../models/patch_catalogue.dart';
import '../models/portable_patch_recipe.dart';
import '../models/system_model.dart';
import '../models/transfer_record.dart';
import 'database_service.dart';
import 'drive/drive_patch_catalogue.dart';
import 'drive/drive_runtime.dart';
import 'installation_index.dart';
import 'library_store.dart';
import 'owned_installation_removal.dart';
import 'owned_storage.dart';
import 'patch_build_publication.dart';
import 'patch_build_store.dart';
import 'transfer_journal.dart';
import 'metadata/shared_metadata_store.dart';

class PatchBuildResult {
  final PatchRecipe recipe;
  final GameItem game;
  final String targetRoot;
  final bool reused;
  const PatchBuildResult(this.recipe, this.game, this.targetRoot,
      {this.reused = false});
}

/// One app-owned patch operation uses existing Drive transfers, installation
/// ownership and library identity. Native algorithms never receive cloud URLs.
class PatchBuildService {
  static Future<PatchBuildResult>? _activeOperation;
  final Future<Database> database;
  final DriveRuntime runtime;
  final OwnedStorage storage;
  final MethodChannel native;
  final Future<SharedMetadataStore?>? sharedStore;
  Future<PatchBuildResult>? _operation;
  CancelToken? _cancellation;
  String? _engineRevision;
  PatchBuildService(
      {Future<Database>? database,
      DriveRuntime? runtime,
      this.sharedStore,
      this.storage = const OwnedStorage(),
      this.native = const MethodChannel('com.retro.rshop/patches')})
      : database = database ?? DatabaseService().database,
        runtime = runtime ?? DriveRuntime.instance;
  late final PatchBuildStore store =
      PatchBuildStore(database, sharedStore: sharedStore);
  TransferJournal get journal => TransferJournal(database);

  Future<void> cancel() async {
    _cancellation?.cancel();
    try {
      await _operation;
    } catch (_) {/* The original result owner reports the failure. */}
  }

  Future<PatchBuildResult> build(
      {required DrivePatchCatalogue catalogue,
      required IndexedPatchGame indexedGame,
      required IndexedRomPatch patch,
      required IndexedPatchPayload payload,
      required IndexedPatchBase base,
      required SystemModel system,
      required String targetFolder,
      String? retryBuildId,
      List<String> preprocessing = const [],
      PortablePatchRecipe? importedRecipe,
      void Function(String phase, int completed, int total)? onProgress}) {
    return _run((cancellation) => _build(
        catalogue,
        indexedGame,
        patch,
        payload,
        base,
        system,
        targetFolder,
        preprocessing,
        cancellation,
        onProgress,
        retryBuildId,
        importedRecipe));
  }

  Future<PatchBuildResult> _run(
      Future<PatchBuildResult> Function(CancelToken) action) {
    if (_activeOperation != null) throw const PatchBuildException('busy');
    final cancellation = CancelToken();
    _cancellation = cancellation;
    final operation = action(cancellation);
    _operation = operation;
    _activeOperation = operation;
    return operation.whenComplete(() {
      if (identical(_operation, operation)) {
        _operation = null;
        _cancellation = null;
      }
      if (identical(_activeOperation, operation)) _activeOperation = null;
    });
  }

  /// Replay the same output publication, never reapply the patch to its result.
  Future<PatchBuildResult> resumePublication(String buildId,
          {void Function(String, int, int)? onProgress}) =>
      _run((cancellation) async {
        final row = await store.get(buildId);
        if (row == null || row['outputArtifact'] == null) {
          throw const PatchBuildException('rebuild_required');
        }
        final recipe = PatchRecipe.fromJson(
            (row['recipe'] as Map).cast<String, dynamic>());
        final previous = await existing(recipe, cancellation);
        if (previous != null) return previous;
        final root =
            await native.invokeMethod<String>('reopen', {'jobId': buildId});
        if (root == null || root != row['jobRoot']) {
          throw const PatchBuildException('scratch_unavailable');
        }
        final artifact = RemoteArtifact.fromJson(
            (row['outputArtifact'] as Map).cast<String, dynamic>());
        final output = File(p.join(root, 'result.raw'));
        try {
          final record = await journal.transfer('patch-$buildId');
          // A durable publication intent owns its verified stage even if raw scratch
          // disappeared after publication. Before that intent, raw output is required.
          if (record?.publication == null) {
            await fingerprintPatchBytes(output.openRead(), cancellation,
                expectedSize: artifact.sizeBytes,
                expected: artifact.providerChecksums);
          }
          onProgress?.call('Saving patched game', 0, 0);
          final result =
              await _publishBuild(row, recipe, artifact, output, cancellation);
          await _cleanup(buildId);
          return result;
        } catch (error) {
          await store.update(buildId, {'issue': _issue(error, cancellation)},
              state: 'failed');
          rethrow;
        }
      });

  static String _issue(Object error, CancelToken cancellation) =>
      cancellation.isCancelled
          ? 'cancelled'
          : error is PatchBuildException
              ? error.code
              : error is OwnedStorageException
                  ? error.code
                  : 'build_failed';

  Future<PatchBuildResult?> existing(
      PatchRecipe recipe, CancelToken cancellation) async {
    for (final row in await store.forRecipe(recipe.id)) {
      if (row['state'] != 'ready') continue;
      final game =
          GameItem.fromJson((row['game'] as Map).cast<String, dynamic>());
      final record = await journal.transfer(row['transferId'] as String);
      if (record == null) continue;
      final manifest = await journal.installationForTarget(
          destinationRoot: record.destinationRoot,
          relativePath: record.relativePath);
      try {
        await InstallationIndex(journal, storage: storage)
            .requireInstallation(record, manifest);
        final session = await storage.open(
            destinationRoot: record.destinationRoot,
            relativePath: record.relativePath,
            stagePath: record.stagePath,
            durableOffset: record.durableOffset,
            expectedIdentity: manifest!.fileIdentity,
            published: true);
        try {
          await fingerprintPatchBytes(
              session.bytes(manifest.sizeBytes), cancellation,
              expectedSize: manifest.sizeBytes,
              expected: manifest.verifiedChecksums);
          if (!(await session.checkpoint()).matches(manifest.fileIdentity)) {
            throw const PatchBuildException('output_changed');
          }
        } finally {
          await session.close();
        }
        return PatchBuildResult(recipe, game, record.destinationRoot,
            reused: true);
      } on OwnedStorageException catch (error) {
        if (!{'changed', 'not_found'}.contains(error.code)) rethrow;
        await store.update(row['buildId'] as String, {}, state: 'unavailable');
      } on PatchBuildException catch (error) {
        if (error.code == 'cancelled') rethrow;
        await store.update(row['buildId'] as String, {}, state: 'changed');
      }
    }
    return null;
  }

  Future<PatchBuildResult> _build(
      DrivePatchCatalogue catalogue,
      IndexedPatchGame indexedGame,
      IndexedRomPatch patch,
      IndexedPatchPayload payload,
      IndexedPatchBase base,
      SystemModel system,
      String targetFolder,
      List<String> preprocessing,
      CancelToken cancellation,
      void Function(String, int, int)? onProgress,
      String? retryBuildId,
      PortablePatchRecipe? importedRecipe) async {
    if (!patch.payloads.contains(payload) ||
        !patch.bases.contains(base) ||
        patch.unavailableReason != null) {
      throw const PatchBuildException('incompatible_selection');
    }
    final engineRevision = await native.invokeMethod<String>('revision');
    if (engineRevision == null || engineRevision.isEmpty) {
      throw const PatchBuildException('engine_unavailable');
    }
    _engineRevision = engineRevision;
    final recipe = PatchRecipe(
        platformId: system.id,
        base: base,
        steps: [PatchRecipeStep.fromPatch(patch, payload)],
        engineRevision: engineRevision,
        preprocessing: preprocessing);
    if (importedRecipe != null && importedRecipe.recipe.id != recipe.id) {
      throw const PatchBuildException('recipe_changed');
    }
    final previous = await existing(recipe, cancellation);
    if (previous != null) {
      if (importedRecipe?.outputSha256 != null) {
        final record = (await store.forRecipe(recipe.id))
            .firstWhere((row) => row['state'] == 'ready');
        final output = record['outputArtifact'] as Map;
        if (output['sizeBytes'] != importedRecipe!.outputSize ||
            (output['providerChecksums'] as Map)['sha256'] !=
                importedRecipe.outputSha256) {
          throw const PatchBuildException('recipe_output_conflict');
        }
      }
      return previous;
    }
    final extension =
        p.posix.extension(base.archiveMember?.value ?? base.relativePath.value);
    if (!system.romExtensions.contains(extension.toLowerCase()) ||
        extension.isEmpty) {
      throw const PatchBuildException('unsupported_base_format');
    }
    final selectedTargetRoot = p.join(targetFolder, 'Hacks');
    await Directory(selectedTargetRoot).create(recursive: true);
    final targetRoot =
        (await storage.prepare(selectedTargetRoot)).destinationRoot;
    final retry = retryBuildId == null ? null : await store.get(retryBuildId);
    if (retryBuildId != null &&
        (retry == null ||
            PatchRecipe.fromJson(
                        (retry['recipe'] as Map).cast<String, dynamic>())
                    .id !=
                recipe.id ||
            retry['sourceGameId'] != indexedGame.sourceGameId ||
            retry['targetRoot'] != targetRoot ||
            retry['outputArtifact'] != null)) {
      throw const PatchBuildException('recipe_changed');
    }
    final random = Random.secure();
    final buildId = retryBuildId ??
        List.generate(16,
                (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
            .join();
    final jobRoot = await native.invokeMethod<String>(
        retry == null ? 'prepare' : 'reopen', {'jobId': buildId});
    if (jobRoot == null) throw const PatchBuildException('scratch_unavailable');
    if (retry != null && jobRoot != retry['jobRoot']) {
      throw const PatchBuildException('scratch_unavailable');
    }
    final rawBase = File(p.join(jobRoot, 'base.raw'));
    final rawOutput = File(p.join(jobRoot, 'result.raw'));
    final title = '${indexedGame.title} — ${patch.title}';
    final filename = retry?['filename'] as String? ??
        '${_filename(title)} [${buildId.substring(0, 8)}]$extension';
    if (retry == null) {
      await store.begin(
          buildId: buildId,
          recipe: recipe,
          sourceGameId: indexedGame.sourceGameId,
          gameTitle: indexedGame.title,
          gameIndexPath: indexedGame.indexPath.value,
          providerSourceId: catalogue.config.sourceId!,
          title: title,
          jobRoot: jobRoot,
          targetRoot: targetRoot,
          filename: filename);
    }
    if (retry != null) {
      await store.update(buildId, {'issue': null}, state: 'building');
    }
    final inputRecords = <TransferRecord>[];
    Object? primaryFailure;
    try {
      onProgress?.call('Getting original game', 0, 0);
      final baseArtifact = await catalogue.resolve(base.relativePath);
      final baseFile = await _download(catalogue, baseArtifact,
          p.join(jobRoot, 'base-download'), cancellation, inputRecords,
          buildId: buildId,
          onProgress: (done, total) =>
              onProgress?.call('Getting original game', done, total),
          archivePlatform:
              _archivePlatform(baseArtifact.displayName, system.id));
      onProgress?.call('Getting patch', 0, 0);
      final patchArtifact =
          await catalogue.resolve(PatchRelativePath(payload.relativePath));
      final patchFile = await _download(catalogue, patchArtifact,
          p.join(jobRoot, 'patch-download'), cancellation, inputRecords,
          buildId: buildId,
          onProgress: (done, total) =>
              onProgress?.call('Getting patch', done, total));
      await fingerprintPatchBytes(patchFile.openRead(), cancellation,
          expectedSize: payload.sizeBytes,
          expected: {'sha256': payload.sha256});
      onProgress?.call('Checking original game', 2, 2);
      if (base.archiveMember != null) {
        await _nativeOperation(
            'extract',
            buildId,
            {
              'input': baseFile.path,
              'output': rawBase.path,
              'member': base.archiveMember!.value,
              'size': base.sizeBytes,
            },
            cancellation);
      } else {
        await _nativeOperation(
            'copy',
            buildId,
            {
              'input': baseFile.path,
              'output': rawBase.path,
              'size': base.sizeBytes,
            },
            cancellation);
      }
      await fingerprintPatchBytes(rawBase.openRead(), cancellation,
          expectedSize: base.sizeBytes, expected: base.checksums);
      onProgress?.call('Applying patch', 0, 0);
      await _nativeOperation(
          'apply',
          buildId,
          {
            'input': rawBase.path,
            'patch': patchFile.path,
            'output': rawOutput.path,
            'format': payload.format.name,
            'preprocessing': preprocessing,
          },
          cancellation);
      final fingerprint =
          await fingerprintPatchBytes(rawOutput.openRead(), cancellation);
      if (fingerprint.size <= 0) {
        throw const PatchBuildException('empty_output');
      }
      if (importedRecipe?.outputSha256 != null &&
          (fingerprint.size != importedRecipe!.outputSize ||
              fingerprint.hashes['sha256'] != importedRecipe.outputSha256)) {
        throw const PatchBuildException('recipe_output_conflict');
      }
      final artifact = RemoteArtifact(
          id: RemoteArtifactId(
              providerId: 'patch-build',
              sourceId: 'generated-patches',
              providerFileId: recipe.id),
          displayPath: 'Hacks/$filename',
          displayName: filename,
          sizeBytes: fingerprint.size,
          version: '${recipe.id}:${fingerprint.hashes['sha256']}',
          providerChecksums: {
            for (final entry in fingerprint.hashes.entries)
              if (entry.key != 'crc32') entry.key: entry.value
          },
          canDownload: false);
      await store.update(buildId, {'outputArtifact': artifact.toJson()},
          state: 'publishing');
      checkPatchCancellation(cancellation);
      onProgress?.call('Saving patched game', 0, 0);
      final result = await _publishBuild((await store.get(buildId))!, recipe,
          artifact, rawOutput, cancellation);
      onProgress?.call('Ready to play', 1, 1);
      return result;
    } catch (error, stack) {
      primaryFailure = error;
      debugPrint('Patch build failed: type=${error.runtimeType} '
          'issue=${_issue(error, cancellation)}');
      debugPrintStack(stackTrace: stack, maxFrames: 12);
      await store.update(buildId, {'issue': _issue(error, cancellation)},
          state: cancellation.isCancelled ? 'cancelled' : 'failed');
      rethrow;
    } finally {
      // The native request/transfer result has completed before this exact cleanup.
      // Retain failed publishing scratch for the recorded recovery procedure.
      final ready = (await store.get(buildId))?['state'] == 'ready';
      if (ready || (await store.get(buildId))?['outputArtifact'] == null) {
        final cleaned = await _cleanup(buildId, keepInputs: !ready);
        if (!cleaned && primaryFailure == null) {
          // Installation truth remains ready; cleanup remains independently visible.
          onProgress?.call('Game ready; cleanup pending', 1, 1);
        }
      }
    }
  }

  Future<PatchBuildResult> _publishBuild(
      Map<String, dynamic> row,
      PatchRecipe recipe,
      RemoteArtifact artifact,
      File output,
      CancelToken cancellation) async {
    final record = await PatchBuildPublication(journal, storage: storage)
        .publish(
            buildId: row['buildId'] as String,
            artifact: artifact,
            output: output,
            targetRoot: row['targetRoot'] as String,
            filename: row['filename'] as String,
            cancellation: cancellation);
    final game = GameItem(
        filename: row['filename'] as String,
        displayName: row['title'] as String,
        url: '',
        remoteArtifact: artifact);
    await _register(game, recipe,
        recipe.steps.any((step) => step.section == 'translations'));
    await store.update(row['buildId'] as String,
        {'transferId': record.id, 'game': game.toJson(), 'issue': null},
        state: 'ready');
    await store.publishReady(row['buildId'] as String);
    return PatchBuildResult(recipe, game, record.destinationRoot);
  }

  Future<bool> _cleanup(String buildId, {bool keepInputs = false}) async {
    try {
      final row = (await store.get(buildId))!;
      final root =
          await native.invokeMethod<String>('reopen', {'jobId': buildId});
      if (root == null || root != row['jobRoot']) {
        throw const PatchBuildException('scratch_unavailable');
      }
      for (final leaf in ['base.raw', 'result.raw']) {
        final file = File(p.join(root, leaf));
        if (await file.exists()) await file.delete();
      }
      if (!keepInputs) {
        for (final id in (row['inputTransfers'] as List).cast<String>()) {
          final record = await journal.transfer(id);
          if (record == null || !p.isWithin(root, record.destinationRoot)) {
            throw const PatchBuildException('cleanup_pending');
          }
          final installation = await journal.installationForTarget(
              destinationRoot: record.destinationRoot,
              relativePath: record.relativePath);
          if (installation != null) {
            await OwnedInstallationRemoval(journal, storage: storage)
                .remove(installation);
          }
          final directory = Directory(record.destinationRoot);
          if (await directory.exists() &&
              await directory.list(followLinks: false).isEmpty) {
            await directory.delete();
          }
        }
      }
      final directory = Directory(root);
      final empty = await directory.list(followLinks: false).isEmpty;
      if (empty) await directory.delete();
      await store.update(buildId, {
        'scratchCleanup': empty
            ? 'complete'
            : keepInputs
                ? 'retained_for_retry'
                : 'pending'
      });
      return empty;
    } catch (_) {
      await store.update(buildId, {'scratchCleanup': 'pending'});
      return false;
    }
  }

  Future<File> _download(DrivePatchCatalogue catalogue, RemoteArtifact artifact,
      String root, CancelToken cancellation, List<TransferRecord> inputs,
      {required String buildId,
      String? archivePlatform,
      void Function(int, int)? onProgress}) async {
    checkPatchCancellation(cancellation);
    await Directory(root).create(recursive: true);
    final destinationRoot = (await storage.prepare(root)).destinationRoot;
    final record = await runtime.reserveTransfer(
        config: catalogue.config,
        artifact: artifact,
        destinationRoot: destinationRoot,
        relativePath: artifact.displayName,
        archivePlatformId: archivePlatform);
    final saved = (await store.get(buildId))!;
    final ids = {
      ...(saved['inputTransfers'] as List).cast<String>(),
      record.id
    };
    await store.update(buildId, {'inputTransfers': ids.toList()});
    inputs.add(record);
    final operation = await runtime.startTransfer(
        config: catalogue.config,
        transferId: record.id,
        onCheckpoint: (current) => onProgress?.call(
            current.durableOffset, current.artifact.sizeBytes ?? 0));
    final finished = await Future.any([
      operation.result.then((_) => true),
      cancellation.whenCancel.then((_) => false),
    ]);
    if (!finished) await operation.pause();
    final completed = await operation.result;
    checkPatchCancellation(cancellation);
    if (completed.lifecycle != TransferLifecycle.completed) {
      throw const PatchBuildException('input_download_incomplete');
    }
    return File(p.join(completed.destinationRoot, completed.relativePath));
  }

  Future<void> _nativeOperation(String method, String jobId,
      Map<String, Object?> args, CancelToken cancellation) async {
    checkPatchCancellation(cancellation);
    final operation =
        native.invokeMethod<Map>(method, {'jobId': jobId, ...args});
    final finished = await Future.any([
      operation.then((_) => true),
      cancellation.whenCancel.then((_) => false),
    ]);
    if (!finished) {
      try {
        await native.invokeMethod<void>('cancel', {'jobId': jobId});
      } finally {
        await operation;
      }
    }
    final response = await operation;
    checkPatchCancellation(cancellation);
    if (response?['engineRevision'] != _engineRevision) {
      throw const PatchBuildException('engine_version_mismatch');
    }
  }

  Future<void> _register(
      GameItem game, PatchRecipe recipe, bool translation) async {
    // Reuse normal cache and canonical identity owners, never borrow base ratings.
    await DatabaseService().saveGames(recipe.platformId, [game]);
    final db = await database;
    final rows = await db.query('games',
        columns: ['id'],
        where: 'systemSlug=? AND artifact_key=?',
        whereArgs: [recipe.platformId, game.remoteArtifact!.id.key],
        limit: 1);
    final editionId = await LibraryStore.catalogueEditions(db,
            cacheRowId: rows.single['id'] as int)
        .single;
    final library = LibraryStore(database);
    final edition = (await library.edition(editionId))!;
    await library.putEdition(EditionIdentity.fromJson({
      ...edition.toJson(),
      'patchId': recipe.id,
      'tags': ['Hack', if (translation) 'T-Eng'],
      'isTranslation': translation,
      'collectionCategory': 'hacks',
      'evidence': [
        ...edition.evidence.map((item) => item.toJson()),
        IdentityEvidence(
                source: 'patch-build', kind: 'recipe', value: recipe.id)
            .toJson()
      ],
    }));
  }

  static String? _archivePlatform(String filename, String platform) =>
      TransferRecord.supportsArchiveMapping(filename, platform)
          ? platform
          : null;
  static String _filename(String title) {
    final cleaned =
        title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    var result = '';
    for (final rune in cleaned.runes) {
      final next = '$result${String.fromCharCode(rune)}';
      if (utf8.encode(next).length > 180) break;
      result = next;
    }
    return result.isEmpty ? 'Patched game' : result;
  }
}
