import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import '../../models/library_identity.dart';
import '../../models/scraped_metadata.dart';
import '../library_store.dart';
import 'metadata_artwork_cache.dart';
import 'metadata_provider.dart';

/// Hash evidence prepared from the exact mounted Drive artifact on Windows.
/// It supplies an identifier to the ordinary provider job, never classification.
class DesktopArchiveEvidence {
  static String key(RemoteArtifact artifact, String platform) => sha256
      .convert(utf8.encode(jsonEncode([platform, artifact.toJson()])))
      .toString();

  static MetadataRomIdentifier validate(
      RemoteArtifact artifact, String platform, Map observation) {
    final raw = MetadataRomIdentifier.fromJson(
        (observation['raw'] as Map).cast<String, dynamic>());
    final container = observation['container'] as Map;
    final extension = {'nes': '.nes', 'gba': '.gba'}[platform];
    if (artifact.id.providerId != 'drive' ||
        artifact.version?.isNotEmpty != true ||
        artifact.canDownload != true ||
        container['sizeBytes'] != artifact.sizeBytes ||
        raw.kind != RomIdentifierKind.rawRom ||
        raw.sizeBytes <= 0 ||
        raw.md5 == null ||
        raw.sha1 == null ||
        extension == null ||
        !raw.filename.toLowerCase().endsWith(extension) ||
        raw.filename.contains(RegExp(r'[/\\\x00]')) ||
        !artifact.providerChecksums.keys
            .any({'md5', 'sha1', 'sha256'}.contains)) {
      throw const FormatException('Desktop archive evidence is not bound');
    }
    for (final entry in artifact.providerChecksums.entries) {
      if ({'md5', 'sha1', 'sha256'}.contains(entry.key) &&
          container[entry.key]?.toString().toLowerCase() !=
              entry.value.toLowerCase()) {
        throw const FormatException('Desktop archive differs from Drive');
      }
    }
    return raw;
  }

  static File file(Directory root, RemoteArtifact artifact, String platform) =>
      File(
          '${root.path}/desktop-archive-evidence/${key(artifact, platform)}.json');

  static Future<MetadataRomIdentifier?> read(
      Directory root, RemoteArtifact artifact, String platform) async {
    final source = file(root, artifact, platform);
    if (!await source.exists()) return null;
    if (await source.length() > 64 * 1024) {
      throw const FormatException('Desktop evidence exceeds its bound');
    }
    final receipt = jsonDecode(await source.readAsString()) as Map;
    if (receipt['version'] != 1 ||
        receipt['platformId'] != platform ||
        jsonEncode(RemoteArtifact.fromJson(receipt['artifact']).toJson()) !=
            jsonEncode(artifact.toJson())) {
      throw const FormatException('Desktop evidence artifact changed');
    }
    return validate(artifact, platform, receipt['observation'] as Map);
  }

  static Future<void> preserve(Directory root, RemoteArtifact artifact,
      String platform, Map observation) async {
    validate(artifact, platform, observation);
    final target = file(root, artifact, platform);
    await target.parent.create(recursive: true);
    final body = jsonEncode({
      'version': 1,
      'platformId': platform,
      'artifact': artifact.toJson(),
      'observation': observation
    });
    if (await target.exists()) {
      if (await target.readAsString() != body) {
        throw const FormatException('Immutable desktop evidence changed');
      }
      return;
    }
    final staged = File('${target.path}.next');
    await staged.writeAsString(body, flush: true);
    await staged.rename(target.path);
  }

  /// Prepared image reuse is source/edition scoped, never a fresh provider-body
  /// receipt. The normal job must first corroborate the raw ROM and selector.
  static Future<void> preserveArtwork(
      Directory root,
      RemoteArtifact artifact,
      String platform,
      String editionId,
      MetadataMedia media,
      MetadataArtworkBlob blob,
      DateTime at) async {
    final receipt = _artworkFile(root, artifact, platform, editionId, media);
    await receipt.parent.create(recursive: true);
    final value = {
      'version': 1,
      'editionId': editionId,
      'media': media.toJson(),
      'filename': blob.filename,
      'bytes': blob.length
    };
    if (await receipt.exists()) {
      final previous = jsonDecode(await receipt.readAsString()) as Map;
      previous.remove('importedAt');
      if (jsonEncode(previous) != jsonEncode(value)) {
        throw const FormatException('Prepared artwork receipt changed');
      }
      return;
    }
    final staged = File('${receipt.path}.next');
    await staged.writeAsString(
        jsonEncode({...value, 'importedAt': at.toIso8601String()}),
        flush: true);
    await staged.rename(receipt.path);
  }

  static File _artworkFile(Directory root, RemoteArtifact artifact,
      String platform, String editionId, MetadataMedia media) {
    final owner = sha256.convert(utf8.encode(editionId));
    return File(
        '${root.path}/desktop-archive-evidence/${key(artifact, platform)}/$owner/${MetadataArtworkCache.key(media)}.json');
  }

  static Future<({MetadataArtworkBlob blob, DateTime retrievedAt})?> artwork(
      Database db,
      MetadataArtworkCache cache,
      String editionId,
      MetadataMedia media) async {
    final shared = cache.sharedStore;
    if (shared == null || media.providerReference == null) return null;
    await shared.requireAccess();
    final library = LibraryStore(Future.value(db));
    final edition = await library.edition(editionId);
    if (edition == null || edition.members.length != 1) return null;
    final game = await library.game(edition.gameId);
    final platform = game?.platformId;
    if (game == null ||
        platform == null ||
        game.baseGameId != null ||
        edition.patchId != null ||
        edition.isTranslation == true ||
        edition.translatedLanguages.isNotEmpty ||
        edition.tags.any((t) => !{'unknown', 'official'}.contains(t)) ||
        edition.evidence.any(
            (e) => e.source == 'manual' && e.kind == 'contentClassification'))
      return null;
    final artifact = await library.artifact(edition.members.single.artifactId);
    if (artifact == null) return null;
    final source =
        _artworkFile(shared.root, artifact, platform, editionId, media);
    if (!await source.exists()) return null;
    if (await source.length() > 64 * 1024)
      throw const FormatException('Prepared artwork receipt exceeds bound');
    final raw = await read(shared.root, artifact, platform);
    final currentRaw = MetadataRomIdentifier.fromEditionEvidence(edition);
    if (raw == null ||
        currentRaw == null ||
        jsonEncode(raw.toJson()) != jsonEncode(currentRaw.toJson()))
      return null;
    final receipt = jsonDecode(await source.readAsString()) as Map;
    if (receipt['version'] != 1 ||
        receipt['editionId'] != editionId ||
        jsonEncode(receipt['media']) != jsonEncode(media.toJson())) return null;
    final filename = receipt['filename'] as String;
    if (!RegExp(r'^[a-f0-9]{64}\.png$').hasMatch(filename) ||
        receipt['bytes'] is! int ||
        (receipt['bytes'] as int) > MetadataArtworkCache.maxBytes) return null;
    final image = await cache.fileFor(editionId, 'screenscraper', media);
    if (image == null ||
        !image.path.endsWith('/$filename') &&
            !image.path.endsWith('\\$filename') ||
        await image.length() != receipt['bytes'] ||
        (await sha256.bind(image.openRead()).first).toString() !=
            filename.substring(0, 64)) return null;
    return (
      blob: MetadataArtworkBlob(
          MetadataArtworkCache.key(media), filename, receipt['bytes'] as int),
      retrievedAt: DateTime.parse(receipt['importedAt'] as String)
    );
  }
}
