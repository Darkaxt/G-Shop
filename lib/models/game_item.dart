import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../utils/game_metadata.dart';
import 'config/provider_config.dart';
import 'library_identity.dart';

class AlternativeSource {
  final String url;
  final ProviderConfig providerConfig;

  const AlternativeSource({required this.url, required this.providerConfig});

  Map<String, dynamic> toJson() => {
        'url': url,
        'provider_config': providerConfig.toJsonWithoutAuth(),
      };

  factory AlternativeSource.fromJson(Map<String, dynamic> json) {
    return AlternativeSource(
      url: json['url'] as String,
      providerConfig: ProviderConfig.fromJson(
          (json['provider_config'] as Map).cast<String, dynamic>()),
    );
  }
}

class GameItem {
  final String filename;
  final String displayName;
  final String url;
  final String? cachedCoverUrl;
  final ProviderConfig? providerConfig;
  final bool hasThumbnail;
  final bool isFolder;
  final List<AlternativeSource> alternativeSources;
  final RemoteArtifact? remoteArtifact;

  /// A console may mix local cache rows and remote entries. Only this exact
  /// entry's source can offer a download; never borrow a console's provider or
  /// an identically named remote artifact for a local row.
  bool get hasDownloadSource {
    final provider = providerConfig;
    if (provider == null) return false;
    if (provider.type == ProviderType.drive) {
      return remoteArtifact != null && remoteArtifact!.canDownload != false;
    }
    return false;
  }

  /// Exact file identity is independent of title, location and current version.
  /// Legacy providers retain their existing filename grouping.
  String get identityKey => remoteArtifact == null
      ? 'legacy:$filename'
      : 'artifact:${remoteArtifact!.id.key}';

  /// Retains existing favorites/shelves keys for all legacy records.
  String get selectionKey => remoteArtifact == null ? filename : identityKey;
  String get groupKey => remoteArtifact == null ? displayName : identityKey;

  /// Achievement evidence is content-version-specific, unlike favorites/shelves.
  /// The NUL namespace cannot collide with any legacy filesystem filename.
  String get raMatchKey => achievementKey(filename, remoteArtifact);

  static String achievementKey(String filename, RemoteArtifact? artifact) {
    if (artifact == null) return filename;
    final digests = artifact.providerChecksums.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final content = jsonEncode([
      artifact.id.key,
      artifact.version,
      artifact.sizeBytes,
      {for (final digest in digests) digest.key: digest.value}
    ]);
    return '\u0000artifact-ra:${sha256.convert(utf8.encode(content))}';
  }

  const GameItem({
    required this.filename,
    required this.displayName,
    required this.url,
    this.cachedCoverUrl,
    this.providerConfig,
    this.hasThumbnail = false,
    this.isFolder = false,
    this.alternativeSources = const [],
    this.remoteArtifact,
  });

  GameItem copyWith({
    String? url,
    String? cachedCoverUrl,
    ProviderConfig? providerConfig,
    bool? hasThumbnail,
    bool? isFolder,
    List<AlternativeSource>? alternativeSources,
    RemoteArtifact? remoteArtifact,
  }) {
    return GameItem(
      filename: filename,
      displayName: displayName,
      url: url ?? this.url,
      cachedCoverUrl: cachedCoverUrl ?? this.cachedCoverUrl,
      providerConfig: providerConfig ?? this.providerConfig,
      hasThumbnail: hasThumbnail ?? this.hasThumbnail,
      isFolder: isFolder ?? this.isFolder,
      alternativeSources: alternativeSources ?? this.alternativeSources,
      remoteArtifact: remoteArtifact ?? this.remoteArtifact,
    );
  }

  factory GameItem.fromJson(Map<String, dynamic> json) {
    return GameItem(
      filename: json['filename'] as String,
      displayName: json['displayName'] as String,
      url: json['url'] as String,
      cachedCoverUrl: json['cachedCoverUrl'] as String?,
      providerConfig: json['providerConfig'] != null
          ? ProviderConfig.fromJson(
              json['providerConfig'] as Map<String, dynamic>)
          : null,
      hasThumbnail: json['hasThumbnail'] as bool? ?? false,
      isFolder: json['isFolder'] as bool? ?? false,
      remoteArtifact: json['remoteArtifact'] == null
          ? null
          : RemoteArtifact.fromJson(
              (json['remoteArtifact'] as Map).cast<String, dynamic>()),
    );
  }

  Map<String, dynamic> toJson() => {
        'filename': filename,
        'displayName': displayName,
        'url': url,
        if (cachedCoverUrl != null) 'cachedCoverUrl': cachedCoverUrl,
        if (providerConfig != null) 'providerConfig': providerConfig!.toJson(),
        if (hasThumbnail) 'hasThumbnail': hasThumbnail,
        if (isFolder) 'isFolder': isFolder,
        if (remoteArtifact != null) 'remoteArtifact': remoteArtifact!.toJson(),
      };

  /// Re-injects auth credentials from system providers into games loaded
  /// from DB (which strips auth for security). Matches by provider type
  /// and connection details.
  static List<GameItem> rehydrateAuth(
    List<GameItem> games,
    List<ProviderConfig> providers,
  ) {
    if (providers.isEmpty) return games;
    return games.map((game) {
      final pc = game.providerConfig;
      if (pc == null || pc.auth != null) return game;
      final match = pc.findMatchIn(providers);
      if (match?.auth == null) return game;
      return game.copyWith(providerConfig: pc.copyWith(auth: match!.auth));
    }).toList();
  }

  static String cleanDisplayName(String filename) {
    return GameMetadata.cleanTitle(filename);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GameItem &&
          filename == other.filename &&
          url == other.url &&
          remoteArtifact?.id == other.remoteArtifact?.id &&
          isFolder == other.isFolder;

  @override
  int get hashCode => Object.hash(filename, url, isFolder, remoteArtifact?.id);
}
