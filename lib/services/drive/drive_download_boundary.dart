import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../models/config/provider_config.dart';
import '../../models/library_identity.dart';
import 'drive_api.dart';
import 'drive_catalogue.dart';
import 'drive_media.dart';
import 'drive_verification.dart';

/// Revalidates a queued binary and its observed ancestors before/after transfer.
class DriveDownloadBoundary {
  final ProviderConfig config;
  final RemoteArtifact artifact;
  final DriveCatalogue catalogue;
  final DriveCatalogueApi api;
  DriveDownloadBoundary(
      {required this.config,
      required this.artifact,
      required this.catalogue,
      required this.api});

  void _checkCancellation(CancelToken cancellation) {
    if (cancellation.isCancelled) {
      throw const DriveTransferException(DriveTransferIssue.cancelled);
    }
  }

  /// Observed names are only local lookup hints, not current cloud evidence.
  Future<List<DriveFile>> localLookupHints(
          {required CancelToken cancellation}) async =>
      (await _observeLineage(cancellation)).ancestors;

  Future<({int generation, List<DriveFile> ancestors})> _observeLineage(
      CancelToken cancellation) async {
    void checkCancellation() {
      _checkCancellation(cancellation);
    }

    checkCancellation();
    final drive = config.drive;
    if (config.type != ProviderType.drive ||
        drive == null ||
        !drive.isConfigured ||
        config.sourceId != artifact.id.sourceId ||
        drive.accountId != artifact.id.accountId ||
        config.path?.isNotEmpty != true) {
      throw const DriveTransferException(DriveTransferIssue.invalidSource);
    }
    final verification = DriveVerification(artifact);
    try {
      final generation = await catalogue.activeGeneration(
          sourceId: config.sourceId!,
          accountId: drive.accountId,
          rootFolderId: drive.rootFolderId);
      if (generation == null) {
        throw const DriveTransferException(DriveTransferIssue.sourceChanged);
      }
      final observed = await catalogue.requireBinary(
          sourceId: config.sourceId!,
          accountId: drive.accountId,
          rootFolderId: drive.rootFolderId,
          fileId: artifact.id.providerFileId,
          generation: generation);
      verification.requireCurrent(observed);
      final ancestors = <DriveFile>[];
      final seen = <String>{};
      var parent = artifact.parentId!;
      while (true) {
        checkCancellation();
        if (!seen.add(parent)) {
          throw const DriveTransferException(DriveTransferIssue.sourceChanged);
        }
        final folder = await catalogue.requireFolder(
            sourceId: config.sourceId!,
            accountId: drive.accountId,
            rootFolderId: drive.rootFolderId,
            folderId: parent,
            generation: generation);
        ancestors.add(folder);
        if (parent == drive.rootFolderId) break;
        if (folder.parents.length != 1) {
          throw const DriveTransferException(DriveTransferIssue.sourceChanged);
        }
        parent = folder.parents.single;
      }
      if (!seen.contains(config.path)) {
        throw const DriveTransferException(DriveTransferIssue.invalidSource);
      }
      checkCancellation();
      return (
        generation: generation,
        ancestors: List<DriveFile>.unmodifiable(ancestors)
      );
    } on DriveCatalogueException catch (error) {
      debugPrint('Drive lineage unavailable: code=${error.code}');
      throw const DriveTransferException(DriveTransferIssue.sourceChanged);
    }
  }

  /// Returns the current-cloud-validated lineage, nearest parent first.
  Future<List<DriveFile>> revalidate(
      {required CancelToken cancellation}) async {
    final observed = await _observeLineage(cancellation);
    final verification = DriveVerification(artifact);
    try {
      verification.requireCurrent(await api.getFile(artifact.id.providerFileId,
          cancelToken: cancellation));
      await _revalidateAncestors(
          observed.generation, observed.ancestors, cancellation);
      return List.unmodifiable(observed.ancestors);
    } on DriveCatalogueException {
      throw const DriveTransferException(DriveTransferIssue.sourceChanged);
    }
  }

  /// The bounded JSON reader may reconcile a metadata-only revision, never a
  /// changed index payload or a regular ROM/patch transfer snapshot.
  Future<RemoteArtifact> reconcilePatchIndexRevision(
      {required CancelToken cancellation}) async {
    if (!{'index.json', 'game.json'}.contains(artifact.displayName)) {
      throw const DriveTransferException(DriveTransferIssue.invalidSource);
    }
    final observed = await _observeLineage(cancellation);
    try {
      final current = await api.getFile(artifact.id.providerFileId,
          cancelToken: cancellation);
      final updated = DriveVerification(artifact)
          .requirePatchIndexMetadataRevision(current);
      await _revalidateAncestors(
          observed.generation, observed.ancestors, cancellation);
      if (updated.version != artifact.version) {
        final drive = config.drive!;
        await catalogue.reconcilePatchIndexRevision(
            sourceId: config.sourceId!,
            accountId: drive.accountId,
            rootFolderId: drive.rootFolderId,
            generation: observed.generation,
            expected: artifact,
            current: current,
            cancellation: cancellation);
      }
      return updated;
    } on DriveCatalogueException catch (error) {
      throw DriveTransferException(error.code == 'cancelled'
          ? DriveTransferIssue.cancelled
          : DriveTransferIssue.sourceChanged);
    }
  }

  Future<void> _revalidateAncestors(int generation, List<DriveFile> ancestors,
      CancelToken cancellation) async {
    final drive = config.drive!;
    void checkCancellation() => _checkCancellation(cancellation);
    // Only fetch previously observed ancestors. Never follow a new live parent
    // or enumerate another folder/account to explain a moved artifact.
    for (final expected in ancestors) {
      checkCancellation();
      final actual = await api.getFile(expected.id, cancelToken: cancellation);
      if (!actual.isFolder ||
          actual.id != expected.id ||
          actual.parents.length != expected.parents.length ||
          !actual.parents.every(expected.parents.contains)) {
        debugPrint(
            'Drive ancestor mismatch: depth=${ancestors.indexOf(expected)}');
        throw const DriveTransferException(DriveTransferIssue.sourceChanged);
      }
    }
    checkCancellation();
    if (generation !=
        await catalogue.activeGeneration(
            sourceId: config.sourceId!,
            accountId: drive.accountId,
            rootFolderId: drive.rootFolderId)) {
      debugPrint('Drive lineage snapshot changed during validation');
      throw const DriveTransferException(DriveTransferIssue.sourceChanged);
    }
  }
}
