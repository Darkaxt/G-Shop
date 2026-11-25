import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../models/scraped_metadata.dart';
import '../../models/library_identity.dart';
import '../../models/socket_media_model.dart';
import 'drive_metadata_api.dart';
import 'metadata_artwork_cache.dart';
import 'preview_video_cache.dart';
import 'shared_metadata_store.dart';

/// Read-only reader and local cache for the shop catalogue (spec revision 186,
/// CATALOGUE-READONLY-01). Windows publishes the catalogue; clients never write
/// it. A resource is trusted when its SHA-256 and size match its game record.
class MetadataCloudLibrary {
  static const defaultBudgetBytes = 2 * 1024 * 1024 * 1024;
  static String gameFolderName(String title) {
    var name = title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]+'), ' - ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[ .]+$'), '');
    name = String.fromCharCodes(name.runes.take(120));
    if (name.isEmpty || name == '.' || name == '..') name = 'Untitled';
    if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
            caseSensitive: false)
        .hasMatch(name)) name = '_$name';
    return name;
  }

  static String? resourceName(String type, String platform, {int index = 1}) {
    if ({'box-2D', 'box-3D', 'cover'}.contains(type)) return 'box.png';
    if (type == 'support-texture') {
      final format = PhysicalMediaFormat.forSystem(platform);
      return {PhysicalMediaFormat.disc, PhysicalMediaFormat.psp}
              .contains(format)
          ? 'disc.png'
          : 'cartridge.png';
    }
    if ({'ss', 'screenshot'}.contains(type))
      return 'screenshot-${index.toString().padLeft(2, '0')}.png';
    if ({'video', 'video-normalized'}.contains(type)) return 'trailer.mp4';
    if (type == 'box-2D-back') return 'box-back.png';
    if (type == 'box-2D-side') return 'box-spine.png';
    if (type == 'box-texture') return 'box-wrap.png';
    if (type == 'manual-page')
      return 'manual-page-${index.toString().padLeft(3, '0')}.png';
    if ({
      'outer-box-front',
      'outer-box-back',
      'outer-box-left',
      'outer-box-right',
      'outer-box-top',
      'outer-box-bottom'
    }.contains(type)) return '$type.png';
    if ({'fanart', 'flyer', 'maps'}.contains(type))
      return '$type-${index.toString().padLeft(3, '0')}.png';
    return null;
  }

  final SharedMetadataStore store;
  final MetadataCloudRemote remote;
  final String accountId, rootId;
  final void Function()? changed;
  final void Function(String mediaKey)? mediaChanged;
  final void Function(int completed, int total)? progress;
  final Future<bool> Function(String path)? allowBackgroundDownload;
  int budgetBytes;
  Future<void> _tail = Future.value();
  Future<void>? _syncing;
  bool _stopSync = false;
  void stopSync() => _stopSync = true;
  final _holds = <Object, Set<String>>{};
  final _folders = <String, String>{};
  bool _closed = false;
  int _clock = 0;
  MetadataCloudLibrary(
      {required this.store,
      required this.remote,
      required this.accountId,
      required this.rootId,
      this.budgetBytes = defaultBudgetBytes,
      this.changed,
      this.mediaChanged,
      this.progress,
      this.allowBackgroundDownload});
  Database get _db => store.cloudIndex;
  void _notifyMedia(String? key) {
    if (key != null && mediaChanged != null) {
      mediaChanged!(key);
    } else {
      changed?.call();
    }
  }

  Future<T> _lane<T>(Future<T> Function() work) {
    if (_closed) return Future.error(StateError('Metadata cache is closed'));
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> open() async {
    await store.requireAccess();
    await _db.execute('''CREATE TABLE IF NOT EXISTS metadata_cloud_files (
      account TEXT NOT NULL, path TEXT NOT NULL, file_id TEXT NOT NULL,
      digest TEXT NOT NULL, bytes INTEGER NOT NULL, media_key TEXT,
      verified INTEGER NOT NULL DEFAULT 0, used INTEGER NOT NULL DEFAULT 0,
      receipt_json TEXT, parent_id TEXT, PRIMARY KEY(account, path))''');
    await _db.execute('''CREATE TABLE IF NOT EXISTS metadata_cloud_media (
      account TEXT NOT NULL, media_key TEXT NOT NULL, path TEXT NOT NULL,
      PRIMARY KEY(account, media_key, path))''');
    await _db.execute('''CREATE TABLE IF NOT EXISTS metadata_cloud_folders (
      account TEXT NOT NULL, path TEXT NOT NULL, file_id TEXT NOT NULL,
      PRIMARY KEY(account, path))''');
    final columns =
        (await _db.rawQuery('PRAGMA table_info(metadata_cloud_files)'))
            .map((row) => row['name'])
            .toSet();
    for (final column in ['remote_name', 'folder_path', 'replaces_digest']) {
      if (!columns.contains(column))
        await _db.execute(
            'ALTER TABLE metadata_cloud_files ADD COLUMN $column TEXT');
    }
    await _db.execute('''CREATE TABLE IF NOT EXISTS metadata_cloud_games (
      account TEXT NOT NULL, edition_key TEXT NOT NULL, folder_path TEXT NOT NULL,
      PRIMARY KEY(account,edition_key))''');
    _clock =
        ((await _db.rawQuery('SELECT MAX(used) AS n FROM metadata_cloud_files'))
                .single['n'] as int?) ??
            0;
    store.cloudManaged = true;
    store.fetchCloudMedia = ensureMedia;
  }

  void hold(Object owner, Set<String> paths) =>
      _holds[owner] = paths.map(p.normalize).toSet();
  void release(Object owner) => _holds.remove(owner);
  Future<void> leaseMedia(Object owner, Iterable<String> keys) async {
    final paths = <String>{};
    for (final key in keys) {
      final rows = await _db.query('metadata_cloud_media',
          columns: ['path'],
          where: 'account=? AND media_key=?',
          whereArgs: [accountId, key]);
      paths.addAll(rows.map((r) => _local(r['path'] as String).path));
    }
    hold(owner, paths);
  }

  Future<void> close() async {
    _closed = true;
    await _tail;
    store.cloudManaged = false;
    store.fetchCloudMedia = null;
    store.cloudChanged = null;
    store.joinCloudOwner = null;
    _holds.clear();
  }

  static void _path(String path) {
    final normalized = RegExp(
            r'^[a-z0-9][a-z0-9_-]{0,63}/games/[a-f0-9]{64}/(box(?:-back|-spine|-wrap)?|outer-box-(?:front|back|left|right|top|bottom)|manual-page-[0-9]+|(?:fanart|flyer|maps)-[0-9]+|cartridge|disc(?:-[0-9]+)?|screenshot-[0-9]+|trailer|metadata)/[a-f0-9]{64}\.(png|mp4|json)$')
        .hasMatch(path);
    if (!normalized &&
        !RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}/(artwork|preview-videos|records)/[a-f0-9]{64}\.(png|mp4|json)$')
            .hasMatch(path)) {
      throw const FormatException('Invalid metadata cache path');
    }
    final parts = path.split('/');
    final kind = normalized ? parts[3] : parts[1];
    if (!parts.last.endsWith(normalized
        ? kind == 'metadata'
            ? '.json'
            : kind == 'trailer'
                ? '.mp4'
                : '.png'
        : {
            'artwork': '.png',
            'preview-videos': '.mp4',
            'records': '.json'
          }[kind]!)) {
      throw const FormatException('Metadata payload type mismatch');
    }
  }

  File _local(String path) {
    _path(path);
    final filename = p.posix.basename(path);
    final kind = filename.endsWith('.png')
        ? 'artwork'
        : filename.endsWith('.mp4')
            ? 'preview-videos'
            : 'records';
    return File(p.join(store.root.path, kind, filename));
  }

  Future<bool> _intact(File file, String digest, int bytes) async =>
      await FileSystemEntity.type(file.path, followLinks: false) ==
          FileSystemEntityType.file &&
      await file.length() == bytes &&
      (await sha256.bind(file.openRead()).first).toString() == digest;
  Future<List<Map<String, Object?>>> _rows(String path) =>
      _db.query('metadata_cloud_files',
          where: 'account = ? AND path = ?',
          whereArgs: [accountId, path],
          limit: 1);
  Future<File?> localFile(String path) async {
    final rows = await _rows(path);
    if (rows.isEmpty) return null;
    final row = rows.single;
    final file = _local(path);
    return await _intact(file, row['digest'] as String, row['bytes'] as int)
        ? file
        : null;
  }

  Future<String> _folder(String path) async {
    if (_folders.containsKey(path)) return _folders[path]!;
    if (path.isEmpty) {
      final root = await remote.get(rootId);
      if (root?.kind != 'folder' ||
          !DriveMetadataApi.rootNames.contains(root?.name))
        throw const FormatException('Catalogue root changed');
      await _db.insert('metadata_cloud_folders',
          {'account': accountId, 'path': '', 'file_id': rootId},
          conflictAlgorithm: ConflictAlgorithm.replace);
      return _folders[path] = rootId;
    }
    final parent = await _folder(
        p.posix.dirname(path) == '.' ? '' : p.posix.dirname(path));
    final rows = await _db.query('metadata_cloud_folders',
        where: 'account = ? AND path = ?',
        whereArgs: [accountId, path],
        limit: 1);
    if (rows.isNotEmpty) return _folders[path] = rows.single['file_id'] as String;
    final matches = (await remote.children(parent))
        .where((f) => f.kind == 'folder' && f.name == p.posix.basename(path))
        .toList();
    if (matches.length != 1)
      throw FormatException(matches.isEmpty
          ? 'Missing catalogue folder'
          : 'Ambiguous catalogue folder');
    await _db.insert('metadata_cloud_folders',
        {'account': accountId, 'path': path, 'file_id': matches.single.id},
        conflictAlgorithm: ConflictAlgorithm.replace);
    return _folders[path] = matches.single.id;
  }

  Future<void> _verify(
      MetadataCloudFile remoteFile, String path, String digest, int bytes,
      {String? name}) async {
    if (remoteFile.digest != digest ||
        remoteFile.bytes != bytes ||
        remoteFile.name != (name ?? p.posix.basename(path))) {
      throw const FormatException('Cloud metadata bytes changed');
    }
    if (remoteFile.checksum == digest) return;
    final staging = Directory(p.join(store.root.path, '.cloud-staging'));
    await staging.create(recursive: true);
    final file = File(p.join(staging.path, '$digest.verify'));
    try {
      await remote.download(remoteFile, file);
      if (!await _intact(file, digest, bytes))
        throw const FormatException('Cloud metadata digest mismatch');
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  Future<File?> ensure(String path, {bool userRequested = false}) =>
      _lane(() => _ensure(path, userRequested: userRequested));
  Future<File?> _ensure(String path, {bool userRequested = false}) async {
    _path(path);
    final rows = await _rows(path);
    if (rows.isEmpty) return null;
    final row = rows.single;
    final file = _local(path);
    final digest = row['digest'] as String, bytes = row['bytes'] as int;
    if (!await _intact(file, digest, bytes)) {
      if (bytes > budgetBytes) return null;
      if (!userRequested &&
          allowBackgroundDownload != null &&
          !await allowBackgroundDownload!(path)) return null;
      final object = await remote.get(row['file_id'] as String);
      if (object == null ||
          object.bytes != bytes ||
          object.digest != digest ||
          object.name != (row['remote_name'] ?? p.posix.basename(path)) ||
          object.parent != row['parent_id']) return null;
      await file.parent.create(recursive: true);
      final staged = File('${file.path}.cloud-part');
      try {
        await remote.download(object, staged);
        if (!await _intact(staged, digest, bytes))
          throw const FormatException('Cloud media integrity mismatch');
        await staged.rename(file.path);
      } finally {
        if (await staged.exists()) await staged.delete();
      }
      if (row['receipt_json'] != null) {
        final receipt = jsonDecode(row['receipt_json'] as String) as Map;
        final key = row['media_key'] as String;
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key) ||
            receipt['file'] != p.basename(file.path)) {
          throw const FormatException('Invalid cloud video receipt');
        }
        await File(p.join(file.parent.path, '$key.json'))
            .writeAsString(jsonEncode(receipt), flush: true);
      }
      _notifyMedia(row['media_key'] as String?);
    }
    await _db.update('metadata_cloud_files', {'used': ++_clock},
        where: 'account = ? AND path = ?', whereArgs: [accountId, path]);
    await _trim(budgetBytes, protected: {file.path});
    return file;
  }

  Future<File?> ensureMedia(String mediaKey,
      {bool userRequested = false}) async {
    final rows = await _db.rawQuery('''SELECT f.path FROM metadata_cloud_media m
      JOIN metadata_cloud_files f ON f.account=m.account AND f.path=m.path
      WHERE m.account=? AND m.media_key=? AND f.verified=1 LIMIT 1''',
        [accountId, mediaKey]);
    if (rows.isEmpty) return null;
    final path = rows.single['path'] as String;
    final file = await ensure(path, userRequested: userRequested);
    if (file != null && path.endsWith('.mp4')) {
      final row = (await _rows(path)).single;
      final receipt = (jsonDecode(row['receipt_json'] as String) as Map)
          .cast<String, dynamic>();
      receipt['key'] = mediaKey;
      await File(p.join(file.parent.path, '$mediaKey.json'))
          .writeAsString(jsonEncode(receipt), flush: true);
    }
    return file;
  }

  Future<int> cachedBytes() async {
    var total = 0;
    for (final kind in ['artwork', 'preview-videos']) {
      final directory = Directory(p.join(store.root.path, kind));
      if (!await directory.exists()) continue;
      await for (final file in directory.list(followLinks: false)) {
        if (file is File &&
            RegExp(r'^[a-f0-9]{64}\.(png|mp4)$')
                .hasMatch(p.basename(file.path))) {
          total += await file.length();
        }
      }
    }
    return total;
  }

  Future<void> trim(int bytes) => _lane(() => _trim(bytes));

  Future<void> _trim(int bytes, {Set<String> protected = const {}}) async {
    var total = await cachedBytes();
    if (total <= bytes) return;
    _folders.clear();
    final active = {
      ...protected.map(p.normalize),
      for (final paths in _holds.values) ...paths
    };
    final rows = await _db.query('metadata_cloud_files',
        where: 'account = ? AND verified = 1',
        whereArgs: [accountId],
        orderBy: 'used, path');
    for (final row in rows) {
      if (total <= bytes) break;
      final path = row['path'] as String;
      if (path.endsWith('.json')) continue;
      final file = _local(path);
      if (active.contains(file.path)) continue;
      if (!await _intact(file, row['digest'] as String, row['bytes'] as int))
        continue;
      try {
        final parent = await _folder(
            (row['folder_path'] as String?) ?? p.posix.dirname(path));
        final remoteFile = await remote.get(row['file_id'] as String);
        if (remoteFile == null ||
            remoteFile.parent != row['parent_id'] ||
            remoteFile.parent != parent) continue;
        await _verify(
            remoteFile, path, row['digest'] as String, row['bytes'] as int,
            name: row['remote_name'] as String?);
      } on FileSystemException {
        continue;
      } // Offline: retain the last verified local copy.
      await file.delete();
      total -= row['bytes'] as int;
      _notifyMedia(row['media_key'] as String?);
    }
  }

  /// Pull the published catalogue into the local projection.
  Future<void> sync(Future<Database> projection) {
    if (_syncing != null) return _syncing!;
    _stopSync = false;
    return _syncing =
        _synchronize(projection).whenComplete(() => _syncing = null);
  }

  Future<void> _synchronize(Future<Database> projection) async {
    await _lane(() async {
      _folders.clear();
      await _folder('');
    });
    // Catalogue layout: <root>/<console>/<game folder>/metadata.json + roles.
    // `retained` and `_`-prefixed folders are not catalogue consoles.
    final consoles = (await remote.children(rootId))
        .where((f) =>
            f.kind == 'folder' &&
            f.name != 'retained' &&
            RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(f.name))
        .toList();
    final games = <({String console, MetadataCloudFile folder})>[];
    for (final console in consoles) {
      if (_stopSync) return;
      for (final folder in await remote.children(console.id)) {
        if (folder.kind == 'folder' &&
            !{'records', 'artwork', 'preview-videos', '_previous'}
                .contains(folder.name)) {
          games.add((console: console.name, folder: folder));
        }
      }
    }
    progress?.call(0, games.length);
    for (final (index, game) in games.indexed) {
      if (_stopSync) return;
      await _lane(() => _recoverGame(game.console, game.folder));
      progress?.call(index + 1, games.length);
    }
    await _lane(() async {
      await store.restore(await projection);
      await _trim(budgetBytes);
      changed?.call();
    });
  }

  static String editionKey(String edition) =>
      sha256.convert(utf8.encode(edition)).toString();

  /// Catalogue folder name for one edition, before any collision suffix
  /// (`" [<first 8 of editionKey>]"`) for a case-insensitive name clash.
  static String folderTitle(GameIdentity game, EditionIdentity edition) {
    final qualifiers = [
      ...edition.regions,
      if (edition.revision != null) 'Rev ${edition.revision}',
      if (edition.tags.contains('Hack')) 'Hack',
      if (edition.isTranslation == true) 'T-Eng',
      if (edition.patchId != null) edition.patchId!,
    ];
    return gameFolderName(
        '${game.title}${qualifiers.isEmpty ? '' : ' (${qualifiers.join(', ')})'}');
  }

  static Map<String, MetadataMedia> resources(Map<String, dynamic> packet) {
    final platform = packet['platform'] as String;
    final records = (packet['records'] as List)
        .map((r) =>
            MetadataRecord.fromJson(jsonDecode(r['record_json'] as String)))
        .toList()
      ..sort((a, b) {
        // A retail 'reference' record (COVERAGE-FACTS-01) holds only the
        // roles a digital re-release lacks; it goes first so a carton is
        // never assembled from two different releases.
        int order(String id) => switch (id) {
              'reference' => -1,
              'packaging' => 0,
              'launchbox' => 1,
              'screenscraper' => 2,
              _ => 3
            };
        return order(a.providerId).compareTo(order(b.providerId));
      });
    final result = <String, MetadataMedia>{}, screenshots = <String>{};
    var index = 0;
    for (final record in records) {
      final row = (packet['records'] as List).firstWhere((r) =>
          r['edition_id'] == record.editionId &&
          r['provider_id'] == record.providerId);
      final regions =
          EditionIdentity.fromJson(jsonDecode(row['edition_json'] as String))
              .regions;
      for (final media in MetadataArtworkCache.displayMedia(record,
          regions: regions, includeVideo: true, includePackaging: true)) {
        if ({'ss', 'screenshot'}.contains(media.type)) {
          if (!screenshots.add(MetadataArtworkCache.key(media))) continue;
          result[resourceName(media.type, platform, index: ++index)!] = media;
        } else {
          final name =
              resourceName(media.type, platform, index: media.memberIndex ?? 1);
          if (name != null) result.putIfAbsent(name, () => media);
        }
      }
      final labels =
          MetadataArtworkCache.physicalLabels(record, regions: regions);
      if (labels.length == 1 &&
          (labels.single.memberIndex == null ||
              labels.single.memberIndex == 1)) {
        result.putIfAbsent(
            resourceName('support-texture', platform)!, () => labels.single);
      } else if (labels.isNotEmpty &&
          labels.every((m) => m.memberIndex != null) &&
          labels.map((m) => m.memberIndex).toSet().length == labels.length) {
        for (final label in labels) {
          result.putIfAbsent(
              'disc-${label.memberIndex!.toString().padLeft(2, '0')}.png',
              () => label);
        }
      }
      final videos = record.media
          .where((m) => {'video', 'video-normalized'}.contains(m.type))
          .toList();
      if (videos.isNotEmpty)
        result.putIfAbsent(
            'trailer.mp4',
            () =>
                videos.where((m) => m.type == 'video-normalized').firstOrNull ??
                videos.first);
    }
    return result;
  }

  static const assetFields = [
    'path',
    'file_id',
    'digest',
    'bytes',
    'media_key',
    'receipt_json',
    'remote_name',
    'folder_path'
  ];

  static List<int> gamePacketBytes(Map<String, dynamic> packet, String key,
          String folder, List<Map<String, Object?>> assets) =>
      utf8.encode(jsonEncode({
        ...packet,
        'layout': 2,
        'entity_key': key,
        'folder': p.posix.basename(folder),
        'game': jsonDecode(
            (packet['records'] as List).first['game_json'] as String),
        'edition': jsonDecode(
            (packet['records'] as List).first['edition_json'] as String),
        'metadata': [
          for (final row in packet['records'] as List)
            jsonDecode(row['record_json'] as String)
        ],
        'assets': assets,
        'resources': {
          for (final a in assets)
            a['remote_name'] as String: {
              'sha256': a['digest'],
              'bytes': a['bytes']
            }
        }
      }));

  Future<void> _recoverGame(String platform, MetadataCloudFile folder) async {
    final entries = await remote.children(folder.id);
    final manifests = entries
        .where((f) => f.kind == 'records' && f.name == 'metadata.json')
        .toList();
    if (manifests.isEmpty) return;
    if (manifests.length != 1)
      throw const FormatException('Ambiguous game metadata');
    final object = manifests.single;
    if (object.bytes > DriveMetadataApi.maxRecordBytes)
      throw const FormatException('Game metadata exceeds budget');
    final known = await _db.query('metadata_cloud_files',
        where: 'account=? AND file_id=? AND digest=? AND verified=1',
        whereArgs: [accountId, object.id, object.digest]);
    if (known.isNotEmpty) return;
    final file =
        File(p.join(store.root.path, 'records', '${object.digest}.json'));
    await file.parent.create(recursive: true);
    try {
      await remote.download(object, file);
      if (!await _intact(file, object.digest!, object.bytes))
        throw const FormatException('Game metadata digest mismatch');
      final packet = (jsonDecode(await file.readAsString()) as Map)
          .cast<String, dynamic>();
      final records = packet['records'] as List;
      final key = packet['entity_key'] as String;
      if (packet['layout'] != 2 ||
          packet['platform'] != platform ||
          packet['folder'] != folder.name ||
          records.isEmpty ||
          records.any((r) => editionKey(r['edition_id'] as String) != key)) {
        debugPrint('Catalogue game skipped: binding mismatch in $platform');
        return;
      }
      final roles = resources(packet);
      final assets = <Map<String, Object?>>[];
      for (final raw in packet['assets'] as List) {
        final a = (raw as Map).cast<String, dynamic>();
        final path = a['path'] as String;
        _path(path);
        final name = a['remote_name'] as String;
        final media = roles[name];
        final video = name.endsWith('.mp4');
        if (media == null ||
            !path.startsWith('$platform/games/$key/') ||
            path.split('/')[3] != name.split('.').first ||
            a['digest'] != p.posix.basename(path).split('.').first ||
            a['media_key'] !=
                (video
                    ? PreviewVideoCache.key(media)
                    : MetadataArtworkCache.key(media)) ||
            a['folder_path'] != '$platform/${folder.name}')
          throw const FormatException('Game resource role mismatch');
        // Resolve by name in this game folder; trust by hash and size only.
        final named = entries.where((f) => f.name == name).toList();
        final actual = named.length == 1 ? named.single : null;
        if (actual == null ||
            actual.digest != a['digest'] ||
            actual.bytes != a['bytes'] ||
            actual.bytes < 1 ||
            actual.bytes > 256 * 1024 * 1024 ||
            actual.kind != (video ? 'video' : 'artwork')) {
          // Absent, still uploading or replaced: leave this resource absent.
          continue;
        }
        if (video) {
          final receipt = jsonDecode(a['receipt_json'] as String) as Map;
          if (receipt['version'] != 1 ||
              receipt['key'] != a['media_key'] ||
              receipt['file'] != p.posix.basename(path) ||
              receipt['sha256'] != a['digest'] ||
              receipt['bytes'] != a['bytes'])
            throw const FormatException('Invalid game video receipt');
        }
        assets.add({
          'account': accountId,
          for (final field in [
            'path',
            'file_id',
            'digest',
            'bytes',
            'media_key',
            'receipt_json',
            'remote_name',
            'folder_path'
          ])
            field: a[field],
          'file_id': actual.id,
          'parent_id': folder.id,
          'verified': 1
        });
      }
      await store.importCloudPacket(packet);
      for (final a in assets) {
        await _db.insert('metadata_cloud_files', a,
            conflictAlgorithm: ConflictAlgorithm.replace);
        await _db.insert(
            'metadata_cloud_media',
            {
              'account': accountId,
              'path': a['path'],
              'media_key': a['media_key']
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await _db.insert(
          'metadata_cloud_games',
          {
            'account': accountId,
            'edition_key': key,
            'folder_path': '$platform/${folder.name}'
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await _db.insert(
          'metadata_cloud_folders',
          {
            'account': accountId,
            'path': '$platform/${folder.name}',
            'file_id': folder.id
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await _db.insert(
          'metadata_cloud_files',
          {
            'account': accountId,
            'path': '$platform/games/$key/metadata/${object.digest}.json',
            'file_id': object.id,
            'digest': object.digest,
            'bytes': object.bytes,
            'verified': 1,
            'parent_id': folder.id,
            'remote_name': 'metadata.json',
            'folder_path': '$platform/${folder.name}'
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

}
