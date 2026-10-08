import '../../../models/config/provider_config.dart';
import '../../../models/library_identity.dart';
import '../../../models/game_item.dart';

class LibraryEntry {
  final String filename;
  final String displayName;
  final String cardTitle;
  final String url;
  final String? coverUrl;
  final String systemSlug;
  final ProviderConfig? providerConfig;
  final bool hasThumbnail;
  final RemoteArtifact? remoteArtifact;
  String get selectionKey =>
      remoteArtifact == null ? filename : 'artifact:${remoteArtifact!.id.key}';
  String get raMatchKey => GameItem.achievementKey(filename, remoteArtifact);
  bool get hasDownloadSource => GameItem(
          filename: filename,
          displayName: displayName,
          url: url,
          providerConfig: providerConfig,
          remoteArtifact: remoteArtifact)
      .hasDownloadSource;

  const LibraryEntry({
    required this.filename,
    required this.displayName,
    required this.cardTitle,
    required this.url,
    this.coverUrl,
    required this.systemSlug,
    this.providerConfig,
    this.hasThumbnail = false,
    this.remoteArtifact,
  });
}
