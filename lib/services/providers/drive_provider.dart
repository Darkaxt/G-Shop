import 'dart:convert';

import '../../models/config/provider_config.dart';
import '../../models/config/system_config.dart';
import '../../models/game_item.dart';
import '../../models/system_model.dart';
import '../download_handle.dart';
import '../drive/drive_authorization.dart';
import '../drive/drive_catalogue.dart';
import '../drive/drive_runtime.dart';
import '../source_provider.dart';

/// Normal source adapter. Catalogue preparation is source-scoped by the sync
/// session, so mapping ten consoles does not traverse a Drive root ten times.
class DriveProvider implements SourceProvider {
  @override
  final ProviderConfig config;
  final DriveRuntime runtime;
  DriveProvider(this.config, {DriveRuntime? runtime})
      : runtime = runtime ?? DriveRuntime.instance;

  @override
  String get displayLabel => 'Google Drive';

  @override
  Future<List<GameItem>> fetchGames(SystemConfig system) async {
    final drive = config.drive;
    if (drive == null ||
        !drive.isConfigured ||
        config.sourceId?.isNotEmpty != true) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.setupRequired);
    }
    final mapped = config.path;
    if (mapped == null || mapped.isEmpty) {
      throw const DriveCatalogueException('mappingRequired');
    }
    final systems =
        SystemModel.supportedSystems.where((s) => s.id == system.id);
    if (systems.isEmpty) {
      throw const DriveCatalogueException('unsupportedPlatform');
    }
    final extensions = [
      ...systems.single.romExtensions,
      if (systems.single.romExtensions.contains('.cue')) '.m3u',
      ...SystemModel.archiveExtensions,
    ];
    final generation = await runtime.catalogue.activeGeneration(
        sourceId: config.sourceId!,
        accountId: drive.accountId,
        rootFolderId: drive.rootFolderId);
    if (generation == null) {
      throw const DriveCatalogueException('refreshRequired');
    }
    await runtime.catalogue.requireFolder(
        sourceId: config.sourceId!,
        accountId: drive.accountId,
        rootFolderId: drive.rootFolderId,
        folderId: mapped,
        generation: generation);
    final result = <GameItem>[];
    var offset = 0;
    while (true) {
      final page = await runtime.catalogue.entries(
          sourceId: config.sourceId!,
          accountId: drive.accountId,
          rootFolderId: drive.rootFolderId,
          folderId: mapped,
          generation: generation,
          offset: offset,
          limit: 500);
      for (final entry in page) {
        if (!entry.file.isSupportedBinary ||
            !extensions.any(
                (ext) => entry.file.name.toLowerCase().endsWith(ext))) {
          continue;
        }
        final artifact = entry.file.artifact(
            sourceId: config.sourceId!,
            accountId: drive.accountId,
            displayPath: entry.displayPath);
        result.add(GameItem(
            filename: entry.file.name,
            displayName: GameItem.cleanDisplayName(entry.file.name),
            // Opaque non-network reference, never an expiring authenticated URL.
            url:
                'drive-artifact:${base64Url.encode(utf8.encode(artifact.id.key))}',
            providerConfig: config,
            remoteArtifact: artifact));
      }
      if (page.length < 500) break;
      offset += page.length;
    }
    return result;
  }

  @override
  Future<DownloadHandle> resolveDownload(GameItem game) async {
    // S3 must provide a verified artifact handle and durable installation lane.
    // Returning an ordinary HTTP handle here would bypass version/hash checks.
    throw const DriveCatalogueException('verifiedTransferNotAvailable');
  }

  @override
  Future<SourceConnectionResult> testConnection() async {
    try {
      final drive = config.drive;
      if (drive == null || !drive.isConfigured) {
        throw const DriveAuthorizationException(
            DriveAuthorizationIssue.setupRequired);
      }
      final root = await runtime.apiFor(drive).getFile(drive.rootFolderId);
      if (!root.isFolder || root.id != drive.rootFolderId) {
        throw const DriveCatalogueException('unsupportedRoot');
      }
      return const SourceConnectionResult.ok();
    } catch (error) {
      // API/auth/catalogue exceptions contain only sanitized codes.
      return SourceConnectionResult.failed(
          error is DriveAuthorizationException ||
                  error is DriveCatalogueException
              ? error.toString()
              : 'Google Drive connection unavailable');
    }
  }
}
