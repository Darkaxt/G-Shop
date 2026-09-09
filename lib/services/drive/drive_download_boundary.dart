import 'package:dio/dio.dart';

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

  Future<void> revalidate({required CancelToken cancellation}) async {
    void checkCancellation() {
      if (cancellation.isCancelled) {
        throw const DriveTransferException(DriveTransferIssue.cancelled);
      }
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
      verification.requireCurrent(await api.getFile(artifact.id.providerFileId,
          cancelToken: cancellation));
      // Only fetch previously observed ancestors. Never follow a new live parent
      // or enumerate another folder/account to explain a moved artifact.
      for (final expected in ancestors) {
        checkCancellation();
        final actual =
            await api.getFile(expected.id, cancelToken: cancellation);
        if (!actual.isFolder ||
            actual.id != expected.id ||
            actual.parents.length != expected.parents.length ||
            !actual.parents.every(expected.parents.contains)) {
          throw const DriveTransferException(DriveTransferIssue.sourceChanged);
        }
      }
      checkCancellation();
      if (generation !=
          await catalogue.activeGeneration(
              sourceId: config.sourceId!,
              accountId: drive.accountId,
              rootFolderId: drive.rootFolderId)) {
        throw const DriveTransferException(DriveTransferIssue.sourceChanged);
      }
    } on DriveCatalogueException {
      throw const DriveTransferException(DriveTransferIssue.sourceChanged);
    }
  }
}
