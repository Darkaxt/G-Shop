import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../../models/library_identity.dart';
import 'drive_metadata_api.dart';
import 'metadata_artwork_cache.dart';
import 'metadata_cloud_library.dart';
import 'preview_video_cache.dart';
import 'shared_metadata_store.dart';

/// Windows catalogue publication (CATALOGUE-READONLY-01): writes the same
/// per-game folders as the old Drive publisher, directly into a local folder
/// (normally the Google Drive for desktop mount). Clients only read it.
class CataloguePublisher {
  static final _role = RegExp(
      r'^(box(?:-back|-spine|-wrap)?|outer-box-(?:front|back|left|right|top|bottom)|manual-page-[0-9]+|(?:fanart|flyer|maps)-[0-9]+|cartridge|disc(?:-[0-9]+)?|screenshot-[0-9]+|trailer)\.(png|mp4)$');
  static final _hex64 = RegExp(r'^[a-f0-9]{64}$');

  final SharedMetadataStore store;
  final Directory catalogue;
  final Set<String>? platforms;
  final bool dryRun;
  final void Function(String line)? log;
  CataloguePublisher(
      {required this.store,
      required this.catalogue,
      this.platforms,
      this.dryRun = false,
      this.log});

  final summary = CataloguePublishSummary();
  final _siblings = <String, Set<String>>{};
  Map<String, String>? _savedFolders;

  Future<CataloguePublishSummary> publish() async {
    final editions = <String>[];
    final seen = <String>{};
    await for (final packet in store.cloudPackets()) {
      if (platforms != null && !platforms!.contains(packet['platform'])) {
        continue;
      }
      for (final row in packet['records'] as List) {
        final edition = row['edition_id'] as String;
        if (seen.add(edition)) editions.add(edition);
      }
    }
    for (final edition in editions) {
      await publishGame(
          await store.cloudPackets(editionId: edition).single);
    }
    return summary;
  }

  Future<Map<String, String>> _saved() async {
    if (_savedFolders != null) return _savedFolders!;
    final db = store.cloudIndex;
    final exists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='metadata_cloud_games'");
    final result = <String, String>{};
    if (exists.isNotEmpty) {
      for (final row in await db.query('metadata_cloud_games',
          orderBy: 'account')) {
        result.putIfAbsent(
            row['edition_key'] as String, () => row['folder_path'] as String);
      }
    }
    return _savedFolders = result;
  }

  Future<Set<String>> _children(String platform) async {
    if (_siblings[platform] case final cached?) return cached;
    final dir = Directory(p.join(catalogue.path, platform));
    final names = <String>{};
    if (await dir.exists()) {
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is Directory) {
          names.add(p.basename(entry.path).toLowerCase());
        }
      }
    }
    return _siblings[platform] = names;
  }

  Future<String?> _entityKey(String folder) async {
    final file = File(p.join(catalogue.path, folder, 'metadata.json'));
    if (!await file.exists() ||
        await file.length() > DriveMetadataApi.maxRecordBytes) return null;
    try {
      return (jsonDecode(await file.readAsString()) as Map)['entity_key']
          as String?;
    } on FormatException {
      return null;
    }
  }

  Future<String> _folder(Map<String, dynamic> packet, String key) async {
    final saved = (await _saved())[key];
    if (saved != null) return saved;
    final first = (packet['records'] as List).first;
    final game =
        GameIdentity.fromJson(jsonDecode(first['game_json'] as String));
    final edition =
        EditionIdentity.fromJson(jsonDecode(first['edition_json'] as String));
    final platform = packet['platform'] as String;
    final siblings = await _children(platform);
    var title = MetadataCloudLibrary.folderTitle(game, edition);
    if (siblings.contains(title.toLowerCase()) &&
        await _entityKey('$platform/$title') != key) {
      title = '$title [${key.substring(0, 8)}]';
    }
    siblings.add(title.toLowerCase());
    final path = '$platform/$title';
    _savedFolders![key] = path;
    return path;
  }

  Future<void> publishGame(Map<String, dynamic> packet) async {
    final platform = packet['platform'] as String;
    final key = MetadataCloudLibrary.editionKey(
        (packet['records'] as List).first['edition_id'] as String);
    final folder = await _folder(packet, key);
    final dir = Directory(p.join(catalogue.path, folder));
    summary.games++;
    final manifest = File(p.join(dir.path, 'metadata.json'));
    List<int>? existingBytes;
    var existingResources = <String, Map>{};
    var existingAssets = <String, Map>{};
    if (await manifest.exists() &&
        await manifest.length() <= DriveMetadataApi.maxRecordBytes) {
      existingBytes = await manifest.readAsBytes();
      try {
        final old = jsonDecode(utf8.decode(existingBytes)) as Map;
        existingResources =
            ((old['resources'] as Map?) ?? {}).cast<String, Map>();
        existingAssets = {
          for (final a in (old['assets'] as List?) ?? const [])
            (a as Map)['remote_name'] as String: a
        };
      } on FormatException {
        existingResources = {};
      }
    }
    final assets = <Map<String, Object?>>[];
    final writes = <String, File>{};
    for (final entry in MetadataCloudLibrary.resources(packet).entries) {
      final name = entry.key;
      final video = name.endsWith('.mp4');
      final mediaKey = video
          ? PreviewVideoCache.key(entry.value)
          : MetadataArtworkCache.key(entry.value);
      String? filename, receipt, digest;
      int? bytes;
      File? body;
      if (video) {
        final file =
            File(p.join(store.root.path, 'preview-videos', '$mediaKey.json'));
        if (await file.exists() && await file.length() <= 1024) {
          receipt = await file.readAsString();
          final r = jsonDecode(receipt) as Map;
          filename = r['file'] as String;
          digest = r['sha256'] as String?;
          bytes = r['bytes'] as int?;
          body = File(p.join(store.root.path, 'preview-videos', filename));
        }
      } else {
        final matches = (packet['artwork'] as List)
            .where((r) => r['media_key'] == mediaKey);
        if (matches.isNotEmpty) {
          filename = matches.first['filename'] as String;
          body = File(p.join(store.root.path, 'artwork', filename));
        }
      }
      if (filename == null || body == null || !await body.exists()) {
        // No local body: keep an already published, still present resource
        // for the same media rather than archiving it.
        final old = existingAssets[name];
        final target = File(p.join(dir.path, name));
        if (old != null &&
            old['media_key'] == mediaKey &&
            await target.exists() &&
            await target.length() == old['bytes']) {
          assets.add({
            for (final field in MetadataCloudLibrary.assetFields)
              if (field != 'file_id')
                field: field == 'folder_path' ? folder : old[field]
          });
          summary.carried++;
        } else if (filename != null || video == false) {
          summary.missing.add('$folder/$name');
        }
        continue;
      }
      final length = await body.length();
      bytes = length;
      final stem = p.basenameWithoutExtension(filename);
      if (digest == null || !_hex64.hasMatch(digest)) {
        digest = _hex64.hasMatch(stem)
            ? stem
            : (await sha256.bind(body.openRead()).first).toString();
      }
      final role = name.split('.').first;
      assets.add({
        'path': '$platform/games/$key/$role/$filename',
        'digest': digest,
        'bytes': bytes,
        'media_key': mediaKey,
        'receipt_json': receipt,
        'remote_name': name,
        'folder_path': folder,
      });
      final old = existingResources[name];
      final target = File(p.join(dir.path, name));
      if (old != null &&
          old['sha256'] == digest &&
          old['bytes'] == bytes &&
          await target.exists() &&
          await target.length() == bytes) {
        summary.filesSkipped++;
      } else {
        writes[name] = body;
      }
    }
    final packetBytes =
        MetadataCloudLibrary.gamePacketBytes(packet, key, folder, assets);
    if (packetBytes.length > DriveMetadataApi.maxRecordBytes) {
      throw FormatException('Game metadata exceeds budget: $folder');
    }
    final live = assets.map((a) => a['remote_name']).toSet();
    final stale = <File>[];
    if (await dir.exists()) {
      await for (final entry in dir.list(followLinks: false)) {
        final name = p.basename(entry.path);
        if (entry is File && _role.hasMatch(name) && !live.contains(name)) {
          stale.add(entry);
        }
      }
    }
    final manifestSame = existingBytes != null &&
        _sameBytes(existingBytes, packetBytes);
    if (writes.isEmpty && stale.isEmpty && manifestSame) {
      summary.filesSkipped++;
      return;
    }
    log?.call('${dryRun ? 'would update' : 'update'} $folder: '
        '${writes.length} file(s), ${stale.length} stale');
    if (!dryRun) await dir.create(recursive: true);
    for (final file in stale) {
      await _archive(file);
    }
    for (final MapEntry(key: name, value: body) in writes.entries) {
      final target = File(p.join(dir.path, name));
      if (!dryRun) {
        if (await target.exists()) await _archive(target);
        await _write(target, body.openRead());
      }
      summary.filesWritten++;
      summary.bytesWritten += await body.length();
    }
    if (manifestSame) {
      summary.filesSkipped++;
    } else {
      if (!dryRun) await _write(manifest, Stream.value(packetBytes));
      summary.filesWritten++;
      summary.bytesWritten += packetBytes.length;
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _archive(File file) async {
    summary.archived++;
    if (dryRun) return;
    final archive = Directory(p.join(file.parent.path, '_previous'));
    await archive.create();
    final name = p.basename(file.path);
    var target = File(p.join(archive.path, name));
    for (var n = 1; await target.exists(); n++) {
      target = File(p.join(archive.path,
          '${p.basenameWithoutExtension(name)}.$n${p.extension(name)}'));
    }
    await file.rename(target.path);
  }

  static Future<void> _write(File target, Stream<List<int>> data) async {
    final tmp = File('${target.path}.tmp');
    final sink = tmp.openWrite();
    await sink.addStream(data);
    await sink.flush();
    await sink.close();
    if (await target.exists()) await target.delete();
    await tmp.rename(target.path);
  }
}

class CataloguePublishSummary {
  int games = 0, filesWritten = 0, filesSkipped = 0, bytesWritten = 0;
  int archived = 0, carried = 0;
  final missing = <String>[];
  Map<String, Object?> toJson() => {
        'games': games,
        'files_written': filesWritten,
        'files_skipped': filesSkipped,
        'bytes_written': bytesWritten,
        'archived': archived,
        'carried_without_local_body': carried,
        'missing_local_bodies': missing.length,
        'missing': missing,
      };
  @override
  String toString() => 'games=$games written=$filesWritten '
      'skipped=$filesSkipped bytes=$bytesWritten archived=$archived '
      'carried=$carried missing=${missing.length}';
}
