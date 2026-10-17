import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../models/scraped_metadata.dart';
import '../../models/library_identity.dart';
import '../../models/socket_media_model.dart';
import 'drive_metadata_api.dart';
import 'metadata_artwork_cache.dart';
import 'preview_video_cache.dart';
import 'shared_metadata_store.dart';

/// One account-bound publication/cache lane. Cloud receipts are not file leases.
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
    return null;
  }

  final SharedMetadataStore store;
  final MetadataCloudRemote remote;
  final String accountId, rootId;
  final void Function()? changed;
  final void Function(int completed, int total)? progress;
  final Future<bool> Function(String path)? allowBackgroundDownload;
  int budgetBytes;
  Future<void> _tail = Future.value();
  Future<void>? _syncing;
  bool _stopSync = false;
  bool _rebuildPending = false;
  void stopPublication() => _stopSync = true;
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
      this.progress,
      this.allowBackgroundDownload});
  Database get _db => store.cloudIndex;
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
            r'^[a-z0-9][a-z0-9_-]{0,63}/games/[a-f0-9]{64}/(box|cartridge|disc(?:-[0-9]+)?|screenshot-[0-9]+|trailer|metadata)/[a-f0-9]{64}\.(png|mp4|json)$')
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
      var root = await remote.get(rootId);
      if (root == null) {
        await remote.folder(rootId, null, 'R-Shop Metadata');
        root = await remote.get(rootId);
      }
      if (root?.kind != 'folder' ||
          root?.parent != null ||
          root?.name != 'R-Shop Metadata')
        throw const FormatException('Metadata root changed');
      return _folders[path] = rootId;
    }
    final parent = await _folder(
        p.posix.dirname(path) == '.' ? '' : p.posix.dirname(path));
    final rows = await _db.query('metadata_cloud_folders',
        where: 'account = ? AND path = ?',
        whereArgs: [accountId, path],
        limit: 1);
    String id;
    if (rows.isNotEmpty) {
      id = rows.single['file_id'] as String;
    } else {
      final matches = (await remote.children(parent))
          .where((f) => f.kind == 'folder' && f.name == p.posix.basename(path))
          .toList();
      if (matches.length > 1)
        throw const FormatException('Ambiguous metadata folder');
      id = matches.isEmpty ? await remote.reserveId() : matches.single.id;
      await _db.insert('metadata_cloud_folders',
          {'account': accountId, 'path': path, 'file_id': id});
    }
    await remote.folder(id, parent, p.posix.basename(path));
    return _folders[path] = id;
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

  Future<void> publishFile(
          {required String path,
          required String mediaKey,
          required File file,
          required String kind,
          String? receiptJson}) =>
      _lane(() async {
        await _publishFile(path, mediaKey, file, kind, receiptJson);
        await _trim(budgetBytes, protected: {file.path});
      });
  Future<void> _publishFile(
      String path, String mediaKey, File file, String kind, String? receiptJson,
      {String? remoteFolder, String? remoteName}) async {
    _path(path);
    final digest = p.posix.basename(path).split('.').first;
    final bytes = await file.length();
    if (bytes < 1 ||
        bytes > 256 * 1024 * 1024 ||
        !await _intact(file, digest, bytes)) {
      throw const FormatException('Local metadata bytes changed');
    }
    final rows = await _rows(path);
    if (mediaKey.isNotEmpty)
      await _db.insert(
          'metadata_cloud_media',
          {
            'account': accountId,
            'media_key': mediaKey,
            'path': path,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    if (rows.isNotEmpty && rows.single['verified'] == 1) return;
    final folderPath = remoteFolder ?? p.posix.dirname(path);
    final name = remoteName ?? p.posix.basename(path);
    final parent = await _folder(folderPath);
    MetadataCloudFile? current;
    if (rows.isEmpty && remoteName != null) {
      final matches = (await remote.children(parent))
          .where((f) => f.name == name && f.kind == kind)
          .toList();
      if (matches.length > 1)
        throw const FormatException('Ambiguous game resource');
      current = matches.firstOrNull;
    }
    final id = rows.isEmpty
        ? current?.id ?? await remote.reserveId()
        : rows.single['file_id'] as String;
    if (rows.isEmpty)
      await _db.insert('metadata_cloud_files', {
        'account': accountId,
        'path': path,
        'file_id': id,
        'digest': digest,
        'bytes': bytes,
        'media_key': mediaKey,
        'receipt_json': receiptJson,
        'used': ++_clock,
        'remote_name': name,
        'folder_path': folderPath,
        'replaces_digest': current?.digest,
      });
    final replaces = rows.isEmpty
        ? current?.digest
        : rows.single['replaces_digest'] as String?;
    await remote.upload(id, parent, name, kind, file, digest, bytes,
        replacesDigest: replaces);
    final uploaded = await remote.get(id);
    if (uploaded == null ||
        uploaded.parent != parent ||
        uploaded.kind != kind) {
      throw const FormatException('Cloud metadata publication disappeared');
    }
    await _verify(uploaded, path, digest, bytes, name: name);
    await _db.update('metadata_cloud_files', {'verified': 0},
        where: 'account=? AND file_id=? AND path<>?',
        whereArgs: [accountId, id, path]);
    await _db.update(
        'metadata_cloud_files', {'verified': 1, 'parent_id': parent},
        where: 'account = ? AND path = ?', whereArgs: [accountId, path]);
  }

  Future<File?> ensure(String path, {bool userRequested = false}) =>
      _lane(() => _ensure(path, userRequested: userRequested));
  Future<File?> _ensure(String path, {bool userRequested = false}) async {
    if (_rebuildPending) return null;
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
      changed?.call();
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

  /// A just-collected visible game need not wait behind unrelated publication.
  /// Repeated focus with an existing mapping does not make a Drive request.
  Future<void> publishSelection(String edition, Set<String> requested) =>
      _lane(() async {
        if (_rebuildPending) return;
        final packets = await store.cloudPackets(editionId: edition).toList();
        if (packets.isEmpty) return;
        final packet = packets.single;
        var unpublishedLocal = false;
        for (final media in _resources(packet).values) {
          final video = {'video', 'video-normalized'}.contains(media.type);
          final key = video
              ? PreviewVideoCache.key(media)
              : MetadataArtworkCache.key(media);
          if (!requested.contains(key)) continue;
          final mapped = await _db.rawQuery(
              '''SELECT 1 FROM metadata_cloud_media m
        JOIN metadata_cloud_files f ON f.account=m.account AND f.path=m.path
        WHERE m.account=? AND m.media_key=? AND f.verified=1 LIMIT 1''',
              [accountId, key]);
          if (mapped.isNotEmpty) continue;
          if (video) {
            unpublishedLocal = await File(
                    p.join(store.root.path, 'preview-videos', '$key.json'))
                .exists();
          } else {
            final receipts =
                (packet['artwork'] as List).where((a) => a['media_key'] == key);
            unpublishedLocal = receipts.isNotEmpty &&
                await File(p.join(store.artworkRoot.path,
                        receipts.first['filename'] as String))
                    .exists();
          }
          if (unpublishedLocal) break;
        }
        if (unpublishedLocal) await _publishGame(packet);
      });

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

  /// Explicit user-requested rebuild, not automatic cache eviction. The caller
  /// persists the intent and joins collectors before entering this owner lane.
  Future<void> discardCollectedMedia() {
    _rebuildPending = true;
    return _lane(() async {
      await store.requireAccess();
      _folders.clear();
      await _folder('');
      for (final child in await remote.children(rootId)) {
        await remote.trash(child);
      }
      if ((await remote.children(rootId)).isNotEmpty) {
        throw const FormatException('Metadata rebuild is incomplete');
      }
      for (final kind in ['artwork', 'preview-videos']) {
        final directory = Directory(p.join(store.root.path, kind));
        if (!await directory.exists()) continue;
        await for (final file in directory.list(followLinks: false)) {
          if (file is File &&
              RegExp(kind == 'artwork'
                      ? r'^[a-f0-9]{64}\.png$'
                      : r'^[a-f0-9]{64}\.(mp4|json)$')
                  .hasMatch(p.basename(file.path)) &&
              await FileSystemEntity.type(file.path, followLinks: false) ==
                  FileSystemEntityType.file) {
            await file.delete();
          }
        }
      }
      await _db.transaction((txn) async {
        for (final table in [
          'metadata_cloud_media',
          'metadata_cloud_files',
          'metadata_cloud_folders',
          'metadata_cloud_games'
        ]) {
          await txn.delete(table, where: 'account=?', whereArgs: [accountId]);
        }
        await txn.delete('metadata_artwork_cache');
        await txn.delete('artwork_responses');
      });
      _folders.clear();
      _holds.clear();
      _rebuildPending = false;
      changed?.call();
    });
  }

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
      changed?.call();
    }
  }

  Future<void> sync(Future<Database> projection, {bool pull = true}) {
    if (_rebuildPending) {
      return Future.error(
          StateError('Finish the requested media rebuild first'));
    }
    if (_syncing != null) return _syncing!;
    _stopSync = false;
    return _syncing = _synchronize(projection, pull: pull)
        .whenComplete(() => _syncing = null);
  }

  Future<void> _synchronize(Future<Database> projection,
      {required bool pull}) async {
    await _lane(() async {
      _folders.clear();
      await _folder('');
    });
    // Read immutable packets first; cached text never needs media downloads.
    final consoles = <({MetadataCloudFile folder, String prefix})>[];
    if (pull) {
      final rootFolders = await remote.children(rootId);
      final legacy =
          rootFolders.where((f) => f.kind == 'folder' && f.name == '_legacy');
      if (legacy.length > 1)
        throw const FormatException('Ambiguous legacy metadata');
      if (legacy.isNotEmpty) {
        consoles.addAll((await remote.children(legacy.single.id))
            .map((f) => (folder: f, prefix: '_legacy/')));
      }
      consoles.addAll(rootFolders.map((f) => (folder: f, prefix: '')));
    }
    for (final entry in consoles) {
      if (_stopSync) return;
      final console = entry.folder;
      if (console.kind != 'folder' ||
          !RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(console.name))
        continue;
      for (final folder in await remote.children(console.id)) {
        if (folder.kind != 'folder') continue;
        if (!{'records', 'artwork', 'preview-videos'}.contains(folder.name)) {
          if (entry.prefix.isEmpty) {
            await _lane(() => _recoverGame(console.name, folder));
          }
          continue;
        }
        if (folder.name != 'records') continue;
        for (final object in await remote.children(folder.id)) {
          if (_stopSync) return;
          if (object.kind != 'records' ||
              object.bytes > DriveMetadataApi.maxRecordBytes) continue;
          await _lane(() async {
            final path = '${console.name}/records/${object.name}';
            _path(path);
            if (object.digest != p.posix.basename(path).split('.').first)
              throw const FormatException(
                  'Metadata packet name/digest mismatch');
            final existing = await _rows(path);
            if (existing.isNotEmpty && existing.single['verified'] == 1) return;
            final directory = Directory(p.join(store.root.path, 'records'));
            await directory.create(recursive: true);
            final file = File(p.join(directory.path, object.name));
            try {
              await remote.download(object, file);
              if (!await _intact(file, object.digest!, object.bytes))
                throw const FormatException('Metadata packet digest mismatch');
              final packet = (jsonDecode(await file.readAsString()) as Map)
                  .cast<String, dynamic>();
              if (packet['platform'] != console.name)
                throw const FormatException('Metadata console mismatch');
              final validatedAssets = <Map<String, Object?>>[];
              for (final raw in packet['assets'] as List) {
                final asset = (raw as Map).cast<String, dynamic>();
                _path(asset['path'] as String);
                if (!(asset['path'] as String).startsWith('${console.name}/'))
                  throw const FormatException('Cross-console media path');
                final assetPath = asset['path'] as String;
                if (assetPath.contains('/records/') ||
                    asset['digest'] !=
                        p.posix.basename(assetPath).split('.').first ||
                    asset['bytes'] is! int ||
                    (asset['bytes'] as int) < 1 ||
                    (asset['bytes'] as int) > 256 * 1024 * 1024 ||
                    asset['media_key'] is! String ||
                    !RegExp(r'^[a-f0-9]{64}$')
                        .hasMatch(asset['media_key'] as String)) {
                  throw const FormatException('Invalid cloud media receipt');
                }
                final folderPath =
                    '${entry.prefix}${p.posix.dirname(assetPath)}';
                final parent = await _folder(folderPath);
                final object = await remote.get(asset['file_id'] as String);
                if (object == null ||
                    object.parent != parent ||
                    object.name != p.posix.basename(assetPath) ||
                    object.digest != asset['digest'] ||
                    object.bytes != asset['bytes'] ||
                    object.kind !=
                        (assetPath.contains('/artwork/')
                            ? 'artwork'
                            : 'video')) {
                  throw const FormatException('Cloud media ownership changed');
                }
                if (asset['receipt_json'] != null) {
                  final receipt =
                      (jsonDecode(asset['receipt_json'] as String) as Map);
                  if (receipt['version'] != 1 ||
                      receipt['key'] != asset['media_key'] ||
                      receipt['file'] != object.name ||
                      receipt['sha256'] != object.digest ||
                      receipt['bytes'] != object.bytes) {
                    throw const FormatException('Invalid cloud video receipt');
                  }
                }
                validatedAssets.add({
                  'account': accountId,
                  'path': asset['path'],
                  'file_id': asset['file_id'],
                  'digest': asset['digest'],
                  'bytes': asset['bytes'],
                  'media_key': asset['media_key'],
                  'verified': 1,
                  'parent_id': parent,
                  'folder_path': folderPath,
                  'receipt_json': asset['receipt_json']
                });
              }
              await store.importCloudPacket(packet);
              for (final asset in validatedAssets) {
                await _db.insert('metadata_cloud_files', asset,
                    conflictAlgorithm: ConflictAlgorithm.ignore);
                await _db.insert(
                    'metadata_cloud_media',
                    {
                      'account': accountId,
                      'path': asset['path'],
                      'media_key': asset['media_key']
                    },
                    conflictAlgorithm: ConflictAlgorithm.ignore);
              }
              await _db.insert(
                  'metadata_cloud_files',
                  {
                    'account': accountId,
                    'path': path,
                    'file_id': object.id,
                    'digest': object.digest,
                    'bytes': object.bytes,
                    'parent_id': folder.id,
                    'folder_path': '${entry.prefix}${console.name}/records',
                    'verified': 1
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace);
            } finally {
              if (await file.exists()) await file.delete();
            }
          });
        }
      }
    }
    // Publication starts from local facts. Only a remote pull owns restoring
    // newly received facts into the projection; cache readers own startup recovery.
    if (pull) await _lane(() async => store.restore(await projection));
    final editions = <String>{};
    final total = (await _db
            .rawQuery('SELECT COUNT(DISTINCT edition_id) AS n FROM records'))
        .single['n'] as int;
    progress?.call(0, total);
    await for (final packet in store.cloudPackets()) {
      for (final row in packet['records'] as List) {
        if (_stopSync) return;
        final edition = row['edition_id'] as String;
        if (!editions.add(edition)) continue;
        await _lane(() async =>
            _publishGame(await store.cloudPackets(editionId: edition).single));
        progress?.call(editions.length, total);
      }
    }
    await _lane(() async {
      if (_stopSync) return;
      await _retainHistoricalMedia();
      if (pull) await _archiveLegacyFolders();
      await _trim(budgetBytes);
      changed?.call();
    });
  }

  Future<void> _archiveLegacyFolders() async {
    final consoles = await remote.children(rootId);
    for (final console in consoles) {
      if (console.kind != 'folder' ||
          console.name.startsWith('_') ||
          console.name == 'retained') continue;
      for (final folder in await remote.children(console.id)) {
        if (folder.kind != 'folder' ||
            !{'records', 'artwork', 'preview-videos'}.contains(folder.name))
          continue;
        final targetPath = '_legacy/${console.name}';
        final parent = await _folder(targetPath);
        final collision = (await remote.children(parent))
            .where((f) => f.name == folder.name && f.id != folder.id);
        if (collision.isNotEmpty)
          throw const FormatException('Legacy metadata archive collision');
        await remote.relocate(folder, parent);
        final oldPath = '${console.name}/${folder.name}';
        final archivedPath = '$targetPath/${folder.name}';
        await _db.transaction((txn) async {
          await txn.delete('metadata_cloud_folders',
              where: 'account=? AND path=?', whereArgs: [accountId, oldPath]);
          await txn.insert(
              'metadata_cloud_folders',
              {
                'account': accountId,
                'path': archivedPath,
                'file_id': folder.id
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
          await txn.update(
              'metadata_cloud_files', {'folder_path': archivedPath},
              where: 'account=? AND parent_id=?',
              whereArgs: [accountId, folder.id]);
        });
        _folders.remove(oldPath);
        _folders[archivedPath] = folder.id;
      }
    }
  }

  static String _editionKey(String edition) =>
      sha256.convert(utf8.encode(edition)).toString();

  Future<String> _gameFolder(Map<String, dynamic> packet) async {
    final first = (packet['records'] as List).first;
    final game =
        GameIdentity.fromJson(jsonDecode(first['game_json'] as String));
    final edition =
        EditionIdentity.fromJson(jsonDecode(first['edition_json'] as String));
    final key = _editionKey(edition.id);
    final saved = await _db.query('metadata_cloud_games',
        where: 'account=? AND edition_key=?', whereArgs: [accountId, key]);
    if (saved.isNotEmpty) return saved.single['folder_path'] as String;
    final platform = packet['platform'] as String;
    final qualifiers = [
      ...edition.regions,
      if (edition.revision != null) 'Rev ${edition.revision}',
      if (edition.tags.contains('Hack')) 'Hack',
      if (edition.isTranslation == true) 'T-Eng',
      if (edition.patchId != null) edition.patchId!,
    ];
    var title = gameFolderName(
        '${game.title}${qualifiers.isEmpty ? '' : ' (${qualifiers.join(', ')})'}');
    final parent = await _folder(platform);
    final existing = await remote.children(parent);
    if (existing.any((f) => f.name.toLowerCase() == title.toLowerCase()))
      title = '$title [${key.substring(0, 8)}]';
    final path = '$platform/$title';
    await _db.insert('metadata_cloud_games',
        {'account': accountId, 'edition_key': key, 'folder_path': path});
    return path;
  }

  Map<String, MetadataMedia> _resources(Map<String, dynamic> packet) {
    final platform = packet['platform'] as String;
    final records = (packet['records'] as List)
        .map((r) =>
            MetadataRecord.fromJson(jsonDecode(r['record_json'] as String)))
        .toList()
      ..sort((a, b) => (a.providerId == 'screenscraper' ? 0 : 1)
          .compareTo(b.providerId == 'screenscraper' ? 0 : 1));
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
          regions: regions, includeVideo: true)) {
        if ({'ss', 'screenshot'}.contains(media.type)) {
          if (!screenshots.add(MetadataArtworkCache.key(media))) continue;
          result[resourceName(media.type, platform, index: ++index)!] = media;
        } else {
          final name = resourceName(media.type, platform);
          if (name != null) result.putIfAbsent(name, () => media);
        }
      }
      final labels =
          MetadataArtworkCache.physicalLabels(record, regions: regions);
      if (labels.length == 1 && labels.single.memberIndex == null) {
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

  Future<void> _publishGame(Map<String, dynamic> packet) async {
    final platform = packet['platform'] as String;
    final edition = (packet['records'] as List).first['edition_id'] as String;
    final key = _editionKey(edition);
    final folder = await _gameFolder(packet);
    final assets = <Map<String, Object?>>[];
    for (final entry in _resources(packet).entries) {
      final video = entry.key.endsWith('.mp4');
      final mediaKey = video
          ? PreviewVideoCache.key(entry.value)
          : MetadataArtworkCache.key(entry.value);
      final previous =
          await _db.rawQuery('''SELECT f.path FROM metadata_cloud_media m
        JOIN metadata_cloud_files f ON f.account=m.account AND f.path=m.path
        WHERE m.account=? AND m.media_key=? AND f.verified=1
        AND f.path NOT LIKE '%/games/%' LIMIT 1''', [accountId, mediaKey]);
      if (previous.isNotEmpty &&
          !await _local(previous.single['path'] as String).exists()) {
        await _ensure(previous.single['path'] as String, userRequested: true);
      }
      String filename;
      String? receipt;
      if (video) {
        final file =
            File(p.join(store.root.path, 'preview-videos', '$mediaKey.json'));
        if (!await file.exists() || await file.length() > 1024) continue;
        receipt = await file.readAsString();
        filename = (jsonDecode(receipt) as Map)['file'] as String;
      } else {
        final matches = (packet['artwork'] as List)
            .where((r) => r['media_key'] == mediaKey);
        if (matches.isEmpty) continue;
        filename = matches.first['filename'] as String;
      }
      final role = entry.key.split('.').first;
      final path = '$platform/games/$key/$role/$filename';
      _path(path);
      final file = _local(path);
      if (await file.exists())
        await _publishFile(
            path, mediaKey, file, video ? 'video' : 'artwork', receipt,
            remoteFolder: folder, remoteName: entry.key);
      final saved = await _rows(path);
      if (saved.isNotEmpty && saved.single['verified'] == 1) {
        assets.add({
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
            field: saved.single[field]
        });
      }
    }
    packet.addAll({
      'layout': 2,
      'entity_key': key,
      'folder': p.posix.basename(folder),
      'game':
          jsonDecode((packet['records'] as List).first['game_json'] as String),
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
    });
    final bytes = utf8.encode(jsonEncode(packet));
    if (bytes.length > DriveMetadataApi.maxRecordBytes)
      throw const FormatException('Game metadata exceeds budget');
    final digest = sha256.convert(bytes).toString();
    final file = File(p.join(store.root.path, 'records', '$digest.json'));
    await file.parent.create(recursive: true);
    try {
      await file.writeAsBytes(bytes, flush: true);
      await _publishFile('$platform/games/$key/metadata/$digest.json', '', file,
          'records', null,
          remoteFolder: folder, remoteName: 'metadata.json');
      final parent = await _folder(folder);
      final live = assets.map((a) => a['file_id']).toSet();
      for (final old in await remote.children(parent)) {
        if (old.kind == 'folder' ||
            live.contains(old.id) ||
            !RegExp(r'^(box|cartridge|disc(?:-[0-9]+)?|screenshot-[0-9]+|trailer)\.(png|mp4)$')
                .hasMatch(old.name)) continue;
        final archive = '$folder/_previous';
        final archivedParent = await _folder(archive);
        await remote.relocate(old, archivedParent);
        await _db.update('metadata_cloud_files',
            {'parent_id': archivedParent, 'folder_path': archive},
            where: 'account=? AND file_id=?', whereArgs: [accountId, old.id]);
      }
    } finally {
      if (await file.exists()) await file.delete();
    }
    // Publishing existing local bytes changes remote receipts, not rendered
    // media. Downloads/eviction notify at their actual local mutation boundary;
    // per-game publication notifications restart every mounted media reader.
  }

  Future<void> _recoverGame(String platform, MetadataCloudFile folder) async {
    final manifests = (await remote.children(folder.id))
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
          records.any((r) => _editionKey(r['edition_id'] as String) != key))
        throw const FormatException('Game metadata binding mismatch');
      final resources = _resources(packet);
      final assets = <Map<String, Object?>>[];
      for (final raw in packet['assets'] as List) {
        final a = (raw as Map).cast<String, dynamic>();
        final path = a['path'] as String;
        _path(path);
        final name = a['remote_name'] as String;
        final media = resources[name];
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
        final actual = await remote.get(a['file_id'] as String);
        if (actual == null ||
            actual.parent != folder.id ||
            actual.name != name ||
            actual.digest != a['digest'] ||
            actual.bytes != a['bytes'] ||
            actual.bytes < 1 ||
            actual.bytes > 256 * 1024 * 1024 ||
            actual.kind != (video ? 'video' : 'artwork'))
          throw const FormatException('Game resource publication changed');
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

  Future<void> _publishPacket(
      String platform, Map<String, dynamic> packet) async {
    final bytes = utf8.encode(jsonEncode(packet));
    if (bytes.length > DriveMetadataApi.maxRecordBytes)
      throw const FormatException('Metadata packet exceeds publication budget');
    final digest = sha256.convert(bytes).toString();
    final directory = Directory(p.join(store.root.path, 'records'));
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, '$digest.json'));
    try {
      await file.writeAsBytes(bytes, flush: true);
      await _publishFile(
          '$platform/records/$digest.json', '', file, 'records', null);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  // Earlier refreshes may leave immutable bodies whose current game no longer
  // references them. Preserve those bytes too, without inventing a game match.
  Future<void> _retainHistoricalMedia() async {
    final assets = <Map<String, Object?>>[];
    Future<void> flush() async {
      if (assets.isEmpty) return;
      await _publishPacket('retained', {
        'version': 1,
        'platform': 'retained',
        'records': [],
        'bindings': [],
        'artwork': [],
        'responses': [],
        'assets': [...assets]
      });
      assets.clear();
    }

    for (final kind in ['artwork', 'preview-videos']) {
      final directory = Directory(p.join(store.root.path, kind));
      if (!await directory.exists()) continue;
      await for (final file in directory.list(followLinks: false)) {
        if (file is! File) continue;
        final filename = p.basename(file.path);
        if (!RegExp(kind == 'artwork'
                ? r'^[a-f0-9]{64}\.png$'
                : r'^[a-f0-9]{64}\.mp4$')
            .hasMatch(filename)) continue;
        final known = await _db.query('metadata_cloud_files',
            where: 'account=? AND path LIKE ? AND verified=1',
            whereArgs: [accountId, '%/$filename'],
            limit: 1);
        if (known.isNotEmpty) {
          final row = known.single;
          if ((row['path'] as String).startsWith('retained/')) {
            assets.add({
              for (final field in [
                'path',
                'file_id',
                'digest',
                'bytes',
                'media_key',
                'receipt_json'
              ])
                field: row[field]
            });
            if (assets.length == 128) await flush();
          }
          continue;
        }
        final bytes = await file.length();
        if (kind == 'artwork') {
          if (bytes > MetadataArtworkCache.maxBytes ||
              !MetadataArtworkCache.validNormalizedPng(
                  await file.readAsBytes())) continue;
        } else {
          await PreviewVideoCache.validateMp4(file);
        }
        final digest = filename.split('.').first;
        final key =
            sha256.convert(utf8.encode('retained:$kind:$digest')).toString();
        final path = 'retained/$kind/$filename';
        final receipt = kind == 'artwork'
            ? null
            : jsonEncode({
                'version': 1,
                'key': key,
                'file': filename,
                'bytes': bytes,
                'sha256': digest,
                'usedAt': (await file.lastModified()).toUtc().toIso8601String()
              });
        await _publishFile(
            path, key, file, kind == 'artwork' ? 'artwork' : 'video', receipt);
        final row = (await _rows(path)).single;
        assets.add({
          for (final field in [
            'path',
            'file_id',
            'digest',
            'bytes',
            'media_key',
            'receipt_json'
          ])
            field: row[field]
        });
        if (assets.length == 128) await flush();
      }
    }
    await flush();
  }
}
