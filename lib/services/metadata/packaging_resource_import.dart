import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../models/scraped_metadata.dart';
import '../library_store.dart';
import 'metadata_artwork_cache.dart';
import 'shared_metadata_store.dart';

/// Desktop-prepared scans/documents enter the same durable metadata and cloud
/// lane as provider artwork. A pack cannot create games, ratings or ROMs.
class PackagingResourceImport {
  final Future<Database> database;
  final MetadataArtworkCache cache;
  final SharedMetadataStore shared;
  PackagingResourceImport(this.database, this.cache, this.shared);
  static const roles = {
    'box-2D',
    'box-2D-back',
    'box-2D-side',
    'box-texture',
    'outer-box-front',
    'outer-box-back',
    'outer-box-left',
    'outer-box-right',
    'outer-box-top',
    'outer-box-bottom',
    'manual-page',
    'support-texture',
    'fanart',
    'flyer',
    'maps'
  };

  Future<int> import(File source) async {
    await shared.requireAccess();
    if (await source.length() > 1024 * 1024 * 1024)
      throw const FormatException('Artwork pack is too large');
    final input = InputFileStream(source.path);
    try {
      return await _import(input);
    } finally {
      await input.close();
    }
  }

  Future<int> _import(InputFileStream input) async {
    // PNGs are already compressed. Read stored ZIP members individually instead
    // of keeping hundreds of manual pages in the Android heap.
    final archive = ZipDirectory.read(input);
    if (archive.fileHeaders.length > 4096)
      throw const FormatException('Too many artwork pack members');
    final members = <String, ZipFileHeader>{};
    List<int> read(ZipFileHeader file) {
      final bytes = file.file!.rawContent!.toUint8List();
      if (bytes.length != file.uncompressedSize ||
          getCrc32(bytes) != file.crc32)
        throw const FormatException('Artwork pack member integrity failed');
      return bytes;
    }

    var total = 0;
    for (final file in archive.fileHeaders) {
      final size = file.uncompressedSize ?? 0;
      final mode = (file.externalFileAttributes ?? 0) >> 16;
      if (!{0, 0x8000}.contains(mode & 0xf000) ||
          file.compressionMethod != 0 ||
          file.generalPurposeBitFlag & 1 != 0 ||
          members.containsKey(file.filename) ||
          !(file.filename == 'packaging.json' ||
              RegExp(r'^images/[a-f0-9]{64}\.png$').hasMatch(file.filename)) ||
          size < 1 ||
          size > 4 * 1024 * 1024) {
        throw const FormatException('Invalid artwork pack member');
      }
      total += size;
      if (total > 1024 * 1024 * 1024)
        throw const FormatException('Artwork pack exceeds decoded budget');
      members[file.filename] = file;
    }
    final manifestFile = members['packaging.json'];
    if (manifestFile == null)
      throw const FormatException('Missing artwork manifest');
    final manifest = jsonDecode(utf8.decode(read(manifestFile))) as Map;
    if (manifest['version'] != 1 ||
        manifest['games'] is! List ||
        (manifest['games'] as List).isEmpty ||
        (manifest['games'] as List).length > 25)
      throw const FormatException('Invalid artwork pack scope');
    final db = await database;
    final library = LibraryStore(database);
    final prepared = <({
      Map<String, Object?> identity,
      Map game,
      List<MetadataMedia> media
    })>[];
    final seen = <String>{};
    // Validate all supplied bindings/content before publishing any game.
    for (final raw in manifest['games'] as List) {
      final game = raw as Map;
      final edition = game['editionId'] as String;
      if (!seen.add(edition))
        throw const FormatException('Duplicate pack edition');
      final rows = await db.rawQuery('''SELECT g.record_json AS game_json,
        e.record_json AS edition_json FROM library_editions e JOIN
        library_game_identities g ON g.game_id=e.game_id WHERE e.edition_id=?''',
          [edition]);
      if (rows.length != 1 ||
          LibraryStore.metadataIdentity(rows.single, providerId: 'packaging') !=
              game['identityKey'])
        throw const FormatException(
            'Collection changed since artwork preparation');
      final identity = rows.single;
      final current = jsonDecode(identity['game_json'] as String) as Map;
      if (current['id'] != game['gameId'] ||
          current['platformId'] != manifest['platform'])
        throw const FormatException(
            'Artwork belongs to another game or console');
      final regions = (jsonDecode(identity['edition_json'] as String)
          as Map)['regions'] as List;
      final media = <MetadataMedia>[];
      final roleKeys = <String>{};
      for (final resource in game['resources'] as List) {
        final m =
            MetadataMedia.fromJson((resource as Map).cast<String, dynamic>());
        final ref = m.importReference;
        if (!roles.contains(m.type) ||
            ref == null ||
            m.region != null &&
                m.region != 'wor' &&
                !regions.contains(m.region) ||
            !roleKeys.add('${m.type}:${m.memberIndex ?? 0}') ||
            m.type == 'manual-page' &&
                (m.memberIndex == null || m.memberIndex! < 1))
          throw const FormatException('Invalid artwork role or edition');
        final image = members['images/${ref.sha256}.png'];
        if (image == null ||
            sha256.convert(read(image)).toString() != ref.sha256)
          throw const FormatException(
              'Artwork content does not match manifest');
        media.add(m);
      }
      if (media.isEmpty) throw const FormatException('Empty game artwork');
      prepared.add((identity: identity, game: game, media: media));
    }
    var generation = await shared.maximumGeneration();
    final private = await db
        .rawQuery('SELECT MAX(generation_id) AS n FROM library_metadata');
    final privateMax = private.single['n'] as int? ?? 0;
    if (privateMax > generation) generation = privateMax;
    generation++;
    final now = DateTime.now().toUtc();
    for (final entry in prepared) {
      final previous = await library.metadata(
          entry.game['editionId'] as String, 'packaging');
      final replacedRoles = entry.media.map((m) => m.type).toSet();
      final retained =
          previous?.media.where((m) => !replacedRoles.contains(m.type)) ??
              <MetadataMedia>[];
      final record = MetadataRecord(
          gameId: entry.game['gameId'] as String,
          editionId: entry.game['editionId'] as String,
          platformId: manifest['platform'] as String,
          providerId: 'packaging',
          providerGameId: sha256
              .convert(utf8.encode(entry.game['editionId'] as String))
              .toString(),
          retrievedAt: now,
          refreshGeneration: generation,
          matchMethod: 'editionResourcePack',
          titles: [],
          media: [
            ...entry.media,
            ...retained
          ],
          matchEvidence: {
            'identityKey': entry.game['identityKey'],
            'preparation': 'classified-same-edition-resources-v1'
          });
      await cache.root.create(recursive: true);
      final staging = await cache.root.createTemp('packaging-');
      try {
        for (final media in entry.media) {
          final digest = media.importReference!.sha256;
          final file = File(p.join(staging.path, '$digest.png'));
          await file.writeAsBytes(read(members['images/$digest.png']!),
              flush: true);
          final imported = await cache.importReviewedImage(file, media);
          if (imported.blob.filename != '$digest.png')
            throw const FormatException('Prepared artwork is not normalized');
          await shared.preserveBlob(imported.blob, now,
              providerId: 'packaging', generation: generation);
          await MetadataArtworkCache.publish(db, imported.blob, now);
        }
        await shared.preserve(record, entry.identity, db);
        await library.putMetadata(record);
      } finally {
        await staging.delete(recursive: true);
      }
    }
    return prepared.length;
  }
}
