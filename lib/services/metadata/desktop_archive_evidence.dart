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
/// The normal job retains classification/publication ownership. An explicit
/// import may also retain its already acquired exact provider response.
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
    if (!{1, 2}.contains(receipt['version']) ||
        receipt['platformId'] != platform ||
        jsonEncode(RemoteArtifact.fromJson(receipt['artifact']).toJson()) !=
            jsonEncode(artifact.toJson())) {
      throw const FormatException('Desktop evidence artifact changed');
    }
    return validate(artifact, platform, receipt['observation'] as Map);
  }

  static Future<void> preserve(
      Directory root, RemoteArtifact artifact, String platform, Map observation,
      {Map? lookup}) async {
    validate(artifact, platform, observation);
    final target = file(root, artifact, platform);
    await target.parent.create(recursive: true);
    final body = jsonEncode({
      'version': lookup == null ? 1 : 2,
      'platformId': platform,
      'artifact': artifact.toJson(),
      'observation': observation,
      if (lookup != null) 'lookup': lookup
    });
    if (await target.exists()) {
      final previous = jsonDecode(await target.readAsString()) as Map;
      if (jsonEncode(previous['artifact']) != jsonEncode(artifact.toJson()) ||
          previous['platformId'] != platform ||
          jsonEncode(previous['observation']) != jsonEncode(observation) ||
          (lookup != null &&
              previous['lookup'] != null &&
              jsonEncode(previous['lookup']) != jsonEncode(lookup))) {
        throw const FormatException('Immutable desktop evidence changed');
      }
      if (lookup == null || previous['lookup'] != null) return;
    }
    final staged = File('${target.path}.next');
    await staged.writeAsString(body, flush: true);
    await staged.rename(target.path);
  }

  /// Validate the captured request and response before retaining any pack body.
  /// Ratings are deliberately excluded from this resource acquisition lane.
  static MetadataLookupResult validateLookup(Map lookup,
      {required String gameId,
      required String editionId,
      required String platform,
      required MetadataRomIdentifier raw,
      int? generation}) {
    final captured = MetadataLookupRequest.fromJson(
        (lookup['request'] as Map).cast<String, dynamic>());
    final recordJson = (lookup['record'] as Map).cast<String, dynamic>();
    if (recordJson['ratings'] is! List ||
        (recordJson['ratings'] as List).isNotEmpty) {
      throw const FormatException('Prepared resources cannot import ratings');
    }
    final record = MetadataRecord.fromJson(recordJson);
    if (captured.gameId != gameId ||
        captured.editionId != editionId ||
        captured.platformId != platform ||
        captured.baseProviderGameId != null ||
        jsonEncode(captured.romIdentifier?.toJson()) !=
            jsonEncode(raw.toJson()) ||
        record.gameId != gameId ||
        record.editionId != editionId ||
        record.platformId != platform ||
        record.providerId != 'screenscraper' ||
        !RegExp(r'^[1-9][0-9]*$').hasMatch(record.providerGameId) ||
        record.refreshGeneration != captured.refreshGeneration ||
        record.matchMethod != 'rawRomHashAndSize' ||
        !LibraryStore.hasConsistentProvenance(record) ||
        (captured.verifiedProviderGameId != null &&
            captured.verifiedProviderGameId != record.providerGameId) ||
        record.media.any((m) =>
            m.url != null ||
            m.importReference != null ||
            m.providerReference?.providerGameId != record.providerGameId ||
            m.providerReference?.providerPlatformId !=
                {'nes': 3, 'gba': 12}[platform])) {
      throw const FormatException('Prepared provider response is not bound');
    }
    final evidence = lookup['officialRomEvidence'] == null
        ? null
        : IdentityEvidence.fromJson(
            (lookup['officialRomEvidence'] as Map).cast<String, dynamic>());
    if (evidence != null) {
      final facts = jsonDecode(evidence.value) as Map;
      if (evidence.source != 'screenscraper' ||
          evidence.kind != 'exactRomOfficialRelease' ||
          facts['providerGameId'] != record.providerGameId ||
          facts['retrievedAt'] !=
              record.retrievedAt.toUtc().toIso8601String() ||
          jsonEncode(facts['identifier']) != jsonEncode(raw.toJson())) {
        throw const FormatException('Prepared official-ROM evidence changed');
      }
    }
    final seen = <String>{};
    for (final outcome in (lookup['artworkOutcomes'] as List? ?? const [])) {
      final media = MetadataMedia.fromJson(
          (outcome['media'] as Map).cast<String, dynamic>());
      final key = MetadataArtworkCache.key(media);
      if (!seen.add(key) ||
          !{
            'matched',
            'unmatched',
            'needsReview',
            'ambiguous',
            'unsupportedPlatform',
            'invalidRequest'
          }.contains(outcome['status']) ||
          !{
            'box-2D',
            'box-2D-back',
            'box-2D-side',
            'box-texture',
            'support-texture'
          }.contains(media.type) ||
          !record.media.any((m) => MetadataArtworkCache.key(m) == key)) {
        throw const FormatException('Prepared artwork outcome is not bound');
      }
    }
    return MetadataLookupResult(
        status: MetadataLookupStatus.matched,
        record: generation == null
            ? record
            : MetadataRecord.fromJson(
                {...record.toJson(), 'refreshGeneration': generation}),
        officialRomEvidence: evidence,
        message:
            'Exact Windows provider response reused; original retrieval retained.');
  }

  static Future<MetadataLookupStatus?> artworkOutcome(Database db,
      Directory root, String editionId, MetadataMedia media) async {
    final outcomes = await artworkOutcomes(db, root, editionId);
    final status = outcomes?[MetadataArtworkCache.key(media)];
    return status == MetadataLookupStatus.matched ? null : status;
  }

  /// Only the explicitly attempted physical-resource scope belongs to an
  /// offline response import. Other advertised regions/roles remain available
  /// to an explicit fresh fetch; they are not negative provider outcomes.
  static Future<Map<String, MetadataLookupStatus>?> artworkOutcomes(
      DatabaseExecutor db, Directory root, String editionId) async {
    final editionRows = await db.query('library_editions',
        where: 'edition_id=?', whereArgs: [editionId], limit: 1);
    final edition = editionRows.isEmpty
        ? null
        : EditionIdentity.fromJson(
            jsonDecode(editionRows.single['record_json'] as String));
    if (edition == null || edition.members.length != 1) return null;
    final gameRows = await db.query('library_game_identities',
        where: 'game_id=?', whereArgs: [edition.gameId], limit: 1);
    final game = gameRows.isEmpty
        ? null
        : GameIdentity.fromJson(
            jsonDecode(gameRows.single['record_json'] as String));
    final raw = MetadataRomIdentifier.fromEditionEvidence(edition);
    if (game?.platformId == null || raw == null) return null;
    final request = MetadataLookupRequest(
        gameId: game!.id,
        editionId: editionId,
        platformId: game.platformId!,
        title: game.title,
        contentTags: edition.tags,
        romIdentifier: raw,
        refreshGeneration: 0);
    if (await lookup(db, root, request) == null) return null;
    final artifactRows = await db.query('library_artifacts',
        where: 'artifact_id=?',
        whereArgs: [edition.members.single.artifactId.key],
        limit: 1);
    if (artifactRows.isEmpty) return null;
    final artifact = RemoteArtifact.fromJson(
        jsonDecode(artifactRows.single['record_json'] as String));
    final receipt =
        jsonDecode(await file(root, artifact, game.platformId!).readAsString());
    final outcomes = receipt['lookup']['artworkOutcomes'] as List? ?? const [];
    return {
      for (final outcome in outcomes)
        MetadataArtworkCache.key(MetadataMedia.fromJson(
                (outcome['media'] as Map).cast<String, dynamic>())):
            MetadataLookupStatus.values
                .singleWhere((s) => s.name == outcome['status'])
    };
  }

  static Future<MetadataLookupResult?> lookup(DatabaseExecutor db,
      Directory root, MetadataLookupRequest request) async {
    final editionRows = await db.query('library_editions',
        where: 'edition_id=?', whereArgs: [request.editionId], limit: 1);
    final edition = editionRows.isEmpty
        ? null
        : EditionIdentity.fromJson(
            jsonDecode(editionRows.single['record_json'] as String));
    if (edition == null || edition.members.length != 1) return null;
    final gameRows = await db.query('library_game_identities',
        where: 'game_id=?', whereArgs: [edition.gameId], limit: 1);
    final game = gameRows.isEmpty
        ? null
        : GameIdentity.fromJson(
            jsonDecode(gameRows.single['record_json'] as String));
    if (game == null ||
        game.id != request.gameId ||
        game.platformId != request.platformId ||
        game.baseGameId != null ||
        edition.patchId != null ||
        edition.isTranslation == true ||
        edition.translatedLanguages.isNotEmpty ||
        edition.tags.any((t) => !{'unknown', 'official'}.contains(t)) ||
        edition.evidence.any(
            (e) => e.source == 'manual' && e.kind == 'contentClassification'))
      return null;
    final artifactRows = await db.query('library_artifacts',
        where: 'artifact_id=?',
        whereArgs: [edition.members.single.artifactId.key],
        limit: 1);
    if (artifactRows.isEmpty) return null;
    final artifact = RemoteArtifact.fromJson(
        jsonDecode(artifactRows.single['record_json'] as String));
    final raw = await read(root, artifact, request.platformId);
    if (raw == null ||
        jsonEncode(raw.toJson()) != jsonEncode(request.romIdentifier?.toJson()))
      return null;
    final receipt = jsonDecode(
        await file(root, artifact, request.platformId).readAsString()) as Map;
    if (receipt['lookup'] == null) return null;
    final result = validateLookup(receipt['lookup'] as Map,
        gameId: request.gameId,
        editionId: request.editionId,
        platform: request.platformId,
        raw: raw,
        generation: request.refreshGeneration);
    return MetadataLookupResult(
        status: result.status,
        record: result.record,
        message: result.message,
        officialRomEvidence: request.contentTags.contains('official')
            ? null
            : result.officialRomEvidence);
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
