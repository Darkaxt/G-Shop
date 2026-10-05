import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'es_de_metadata_projection.dart';

class EsDePublicationResult {
  final String status;
  final List<EsDeMetadataConflict> conflicts;
  const EsDePublicationResult(this.status, [this.conflicts = const []]);
}

/// Pending metadata and field ownership live in the shared metadata database.
/// The OS lock excludes cooperating R-Shop publishers, NOT ES-DE. Publication
/// requires ES-DE's documented closed-writer maintenance window throughout.
class EsDeMetadataPublication {
  final Database _db;
  EsDeMetadataPublication(this._db);

  static Future<void> install(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE es_de_pending (
      target_path TEXT NOT NULL, edition_id TEXT NOT NULL,
      identity_key TEXT NOT NULL, generation INTEGER NOT NULL,
      rom_path TEXT NOT NULL, fields_json TEXT NOT NULL, revision TEXT NOT NULL,
      PRIMARY KEY(target_path, edition_id))''');
    await db.execute('''CREATE TABLE es_de_ownership (
      target_path TEXT NOT NULL, rom_path TEXT NOT NULL, ownership_json TEXT NOT NULL,
      PRIMARY KEY(target_path, rom_path))''');
    await db.execute('''CREATE TABLE es_de_publications (
      target_path TEXT PRIMARY KEY, stage_path TEXT NOT NULL,
      before_hash TEXT, after_hash TEXT NOT NULL, xml TEXT NOT NULL,
      ownership_json TEXT NOT NULL, pending_json TEXT NOT NULL)''');
    await installArtwork(db);
  }

  static Future<void> installArtwork(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE es_de_media_ownership (
      target_path TEXT PRIMARY KEY, edition_id TEXT NOT NULL,
      identity_key TEXT NOT NULL, content_hash TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE es_de_media_publications (
      target_path TEXT PRIMARY KEY, edition_id TEXT NOT NULL,
      identity_key TEXT NOT NULL, source_path TEXT NOT NULL,
      before_hash TEXT, after_hash TEXT NOT NULL, stage_path TEXT NOT NULL)''');
  }

  static String _hash(List<int> bytes) => sha256.convert(bytes).toString();
  static String _target(File target) => p.normalize(target.absolute.path);
  static File _stage(String path, Map<String, Object?> journal) {
    final hash = journal['after_hash'] as String;
    final expected = '$path.rshop-$hash.pending';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        journal['stage_path'] != expected) {
      throw const FormatException('Invalid ES-DE publication stage binding');
    }
    return File(expected);
  }

  static bool _prefix(List<int> candidate, List<int> complete) =>
      candidate.length < complete.length &&
      Iterable<int>.generate(candidate.length)
          .every((i) => candidate[i] == complete[i]);

  Future<void> queue(
      {required File target,
      required String identityKey,
      required int generation,
      required EsDeMetadataUpdate update,
      DatabaseExecutor? transaction}) async {
    if (identityKey.isEmpty || generation < 1) {
      throw const FormatException('Verified current metadata is required');
    }
    final db = transaction ?? _db;
    final path = _target(target);
    final previous = await db.query('es_de_pending',
        columns: ['generation'],
        where: 'target_path = ? AND edition_id = ?',
        whereArgs: [path, update.editionId]);
    if (previous.isNotEmpty &&
        (previous.single['generation'] as int) > generation) {
      return;
    }
    final fields = jsonEncode(update.fields);
    final revision = _hash(utf8.encode(
        jsonEncode([identityKey, generation, update.relativeRomPath, fields])));
    await db.insert(
        'es_de_pending',
        {
          'target_path': path,
          'edition_id': update.editionId,
          'identity_key': identityKey,
          'generation': generation,
          'rom_path': update.relativeRomPath,
          'fields_json': fields,
          'revision': revision,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> pendingCount(File target) async =>
      Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT COUNT(*) FROM es_de_pending WHERE target_path = ?',
          [_target(target)]))!;

  static Future<void> _noLinks(String path) async {
    var cursor = path;
    while (true) {
      if (await FileSystemEntity.type(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FileSystemException(
            'ES-DE publication cannot follow links');
      }
      final parent = p.dirname(cursor);
      if (parent == cursor) break;
      cursor = parent;
    }
  }

  // XML is necessarily parsed as a document; bound that external format at IO,
  // including a growing file, rather than buffering unbounded launcher data.
  static Future<List<int>?> _read(File file,
      {int maxBytes = 32 * 1024 * 1024}) async {
    await _noLinks(file.absolute.path);
    if (!await file.exists()) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const FormatException(
            'ES-DE gamelist exceeds the XML publication budget');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  /// An immutable validated cache image is copied to ES-DE's lowercase PNG
  /// layout. This ownership journal is independent of the XML journal: a cover
  /// conflict cannot erase already published facts or be reported as success.
  /// Existing unowned images (including JPG/WebP alternatives) require review.
  Future<EsDePublicationResult> publishArtwork(
      {required File target,
      required Directory mediaRoot,
      required File source,
      required String contentHash,
      required String editionId,
      required String identityKey,
      required String relativeRomPath,
      required bool esDeClosed,
      required Future<bool> Function(String editionId, String identityKey)
          isCurrent}) async {
    if (!esDeClosed) return const EsDePublicationResult('esDeMustBeClosed');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(contentHash) ||
        p.extension(target.path) != '.png') {
      throw const FormatException('A validated PNG publication is required');
    }
    final path = _target(target);
    EsDePublicationResult conflict(String reason) => EsDePublicationResult(
        'conflict', [EsDeMetadataConflict(relativeRomPath, reason, 'artwork')]);
    await _noLinks(path);
    if (!p.isWithin(mediaRoot.absolute.path, path)) {
      throw const FormatException(
          'Artwork is outside selected ES-DE media root');
    }
    if (!await mediaRoot.exists()) {
      return const EsDePublicationResult('storageUnavailable');
    }
    await target.parent.create(recursive: true);
    final lockPath = '$path.rshop-publisher.lock';
    await _noLinks(lockPath);
    final lock = await File(lockPath).open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.blockingExclusive);
      if (!await isCurrent(editionId, identityKey)) {
        return const EsDePublicationResult('identityChanged');
      }
      for (final extension in ['.jpg', '.webp']) {
        final alternate = File(p.withoutExtension(path) + extension);
        await _noLinks(alternate.path);
        if (await alternate.exists()) return conflict('ambiguousArtwork');
      }
      final saved = await _db.query('es_de_media_publications',
          where: 'target_path = ?', whereArgs: [path]);
      if (saved.isNotEmpty) {
        final recovery = await _finishArtwork(saved.single, isCurrent);
        if (recovery.status != 'published') return recovery;
      }
      final bytes = await _read(source, maxBytes: 4 * 1024 * 1024);
      if (bytes == null || bytes.isEmpty || _hash(bytes) != contentHash) {
        return const EsDePublicationResult('sourceChanged');
      }
      final before = await _read(target, maxBytes: 4 * 1024 * 1024);
      final beforeHash = before == null ? null : _hash(before);
      final owners = await _db.query('es_de_media_ownership',
          where: 'target_path = ?', whereArgs: [path]);
      if (owners.isNotEmpty &&
          (owners.single['edition_id'] != editionId ||
              owners.single['identity_key'] != identityKey)) {
        return conflict('differentEdition');
      }
      if (before != null &&
          (owners.isEmpty || owners.single['content_hash'] != beforeHash)) {
        return conflict('manualArtwork');
      }
      if (beforeHash == contentHash) {
        return const EsDePublicationResult('upToDate');
      }
      final stage = '$path.rshop-$contentHash.pending';
      final previous = await _read(File(stage), maxBytes: 4 * 1024 * 1024);
      if (previous != null && _hash(previous) != contentHash) {
        return const EsDePublicationResult('stageChanged');
      }
      final journal = <String, Object?>{
        'target_path': path,
        'edition_id': editionId,
        'identity_key': identityKey,
        'source_path': source.absolute.path,
        'before_hash': beforeHash,
        'after_hash': contentHash,
        'stage_path': stage,
      };
      await _db.insert('es_de_media_publications', journal);
      await File(stage).writeAsBytes(bytes, flush: true);
      return await _finishArtwork(journal, isCurrent);
    } finally {
      await lock.close();
    }
  }

  Future<EsDePublicationResult> _finishArtwork(Map<String, Object?> journal,
      Future<bool> Function(String, String) isCurrent) async {
    final path = journal['target_path'] as String;
    final edition = journal['edition_id'] as String;
    final identity = journal['identity_key'] as String;
    if (!await isCurrent(edition, identity)) {
      return const EsDePublicationResult('identityChanged');
    }
    final stage = _stage(path, journal);
    final after = await _read(File(journal['source_path'] as String),
        maxBytes: 4 * 1024 * 1024);
    if (after == null || _hash(after) != journal['after_hash']) {
      return const EsDePublicationResult('sourceChanged');
    }
    final target = File(path);
    final current = await _read(target, maxBytes: 4 * 1024 * 1024);
    final currentHash = current == null ? null : _hash(current);
    if (currentHash != journal['after_hash']) {
      if (currentHash != journal['before_hash']) {
        return const EsDePublicationResult('fileChanged');
      }
      final staged = await _read(stage, maxBytes: 4 * 1024 * 1024);
      if (staged == null || _prefix(staged, after)) {
        await stage.writeAsBytes(after, flush: true);
      } else if (_hash(staged) != journal['after_hash']) {
        return const EsDePublicationResult('stageChanged');
      }
      final last = await _read(target, maxBytes: 4 * 1024 * 1024);
      if ((last == null ? null : _hash(last)) != journal['before_hash'] ||
          !await isCurrent(edition, identity)) {
        return const EsDePublicationResult('fileChanged');
      }
      await stage.rename(path);
      final written = await _read(target, maxBytes: 4 * 1024 * 1024);
      if (written == null || _hash(written) != journal['after_hash']) {
        return const EsDePublicationResult('fileChanged');
      }
    }
    await _db.transaction((txn) async {
      await txn.insert(
          'es_de_media_ownership',
          {
            'target_path': path,
            'edition_id': edition,
            'identity_key': identity,
            'content_hash': journal['after_hash'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('es_de_media_publications',
          where: 'target_path = ?', whereArgs: [path]);
    });
    final leftover = await _read(stage, maxBytes: 4 * 1024 * 1024);
    if (leftover != null && _hash(leftover) == journal['after_hash']) {
      await stage.delete();
    }
    return const EsDePublicationResult('published');
  }

  Future<List<Map<String, Object?>>> _pending(String path) =>
      _db.query('es_de_pending',
          where: 'target_path = ?', whereArgs: [path], orderBy: 'edition_id');

  /// Persist a prepared generation before filesystem mutation. Exposed separately
  /// for recovery inspection; it never replaces the launcher's gamelist.
  Future<EsDePublicationResult> prepare(File target,
      {required Future<bool> Function(String editionId, String identityKey)
          isCurrent}) async {
    final path = _target(target);
    if ((await _db.query('es_de_publications',
            where: 'target_path = ?', whereArgs: [path]))
        .isNotEmpty) {
      return const EsDePublicationResult('prepared');
    }
    final pending = await _pending(path);
    if (pending.isEmpty) return const EsDePublicationResult('upToDate');
    for (final row in pending) {
      if (!await isCurrent(
          row['edition_id'] as String, row['identity_key'] as String)) {
        return const EsDePublicationResult('identityChanged');
      }
    }
    final before = await _read(target);
    final owners = await _db
        .query('es_de_ownership', where: 'target_path = ?', whereArgs: [path]);
    final projection = EsDeMetadataProjection.merge(
        before == null ? null : utf8.decode(before),
        pending.map((r) => EsDeMetadataUpdate(
            editionId: r['edition_id'] as String,
            relativeRomPath: r['rom_path'] as String,
            fields: Map<String, String>.from(
                jsonDecode(r['fields_json'] as String)))),
        previousOwnership: {
          for (final r in owners)
            r['rom_path'] as String: EsDeFieldOwnership.fromJson(
                jsonDecode(r['ownership_json'] as String))
        });
    // Do not partially publish a generation whose manual/edition conflicts need
    // review. Keep all pending fields and the exact last-good launcher document.
    if (projection.conflicts.isNotEmpty) {
      return EsDePublicationResult('conflict', projection.conflicts);
    }
    final after = utf8.encode(projection.xml);
    if (after.length > 32 * 1024 * 1024) {
      throw const FormatException(
          'ES-DE gamelist exceeds the XML publication budget');
    }
    final afterHash = _hash(after);
    final stage = '$path.rshop-$afterHash.pending';
    await _noLinks(stage);
    final existingStage = await _read(File(stage));
    if (existingStage != null && _hash(existingStage) != afterHash) {
      return const EsDePublicationResult('stageChanged');
    }
    await _db.insert('es_de_publications', {
      'target_path': path,
      'stage_path': stage,
      'before_hash': before == null ? null : _hash(before),
      'after_hash': afterHash,
      'xml': projection.xml,
      'ownership_json': jsonEncode(
          projection.ownership.map((k, v) => MapEntry(k, v.toJson()))),
      'pending_json': jsonEncode(pending),
    });
    await File(stage).writeAsBytes(after, flush: true);
    return const EsDePublicationResult('prepared');
  }

  Future<void> _acknowledge(String path, Map<String, Object?> journal) async {
    final ownership =
        jsonDecode(journal['ownership_json'] as String) as Map<String, dynamic>;
    final pending = jsonDecode(journal['pending_json'] as String) as List;
    await _db.transaction((txn) async {
      for (final entry in ownership.entries) {
        await txn.insert(
            'es_de_ownership',
            {
              'target_path': path,
              'rom_path': entry.key,
              'ownership_json': jsonEncode(entry.value)
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in pending) {
        await txn.delete('es_de_pending',
            where: 'target_path = ? AND edition_id = ? AND revision = ?',
            whereArgs: [path, row['edition_id'], row['revision']]);
      }
      await txn.delete('es_de_publications',
          where: 'target_path = ?', whereArgs: [path]);
    });
    final stage = _stage(path, journal);
    final bytes = await _read(stage);
    if (bytes != null && _hash(bytes) == journal['after_hash']) {
      await stage.delete();
    }
  }

  Future<EsDePublicationResult> publish(File target,
      {required bool esDeClosed,
      bool rebasePrepared = false,
      required Future<bool> Function(String editionId, String identityKey)
          isCurrent}) async {
    if (!esDeClosed) return const EsDePublicationResult('esDeMustBeClosed');
    final path = _target(target);
    await _noLinks(path);
    // This lock is persistent but not a stale lockfile: OS ownership lasts until
    // this handle closes. It cannot coordinate an uncooperative ES-DE writer.
    final lockPath = '$path.rshop-publisher.lock';
    await _noLinks(lockPath);
    final lock = await File(lockPath).open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.blockingExclusive);
      if (rebasePrepared) {
        final saved = await _db.query('es_de_publications',
            where: 'target_path = ?', whereArgs: [path]);
        if (saved.isNotEmpty) {
          final journal = saved.single;
          final current = await _read(target);
          // A committed rename must be acknowledged, not rolled back as an
          // unpublished preparation. A missing prior file is not an empty list.
          if (current == null && journal['before_hash'] != null) {
            return const EsDePublicationResult('storageUnavailable');
          }
          if ((current == null ? null : _hash(current)) !=
              journal['after_hash']) {
            final stage = _stage(path, journal);
            final bytes = await _read(stage);
            final complete = utf8.encode(journal['xml'] as String);
            if (_hash(complete) != journal['after_hash']) {
              throw const FormatException('Invalid ES-DE publication journal');
            }
            if (bytes != null) {
              if (_hash(bytes) != journal['after_hash'] &&
                  !_prefix(bytes, complete)) {
                return const EsDePublicationResult('stageChanged');
              }
              await stage
                  .delete(); // Exact journal-owned, verified expendable stage.
            }
            await _db.delete('es_de_publications',
                where: 'target_path = ?', whereArgs: [path]);
            // Pending responses and last-written field ownership are retained.
            // The new merge still reports manual edits instead of taking them.
          }
        }
      }
      final prepared = await prepare(target, isCurrent: isCurrent);
      if (prepared.status != 'prepared') return prepared;
      final journal = (await _db.query('es_de_publications',
              where: 'target_path = ?', whereArgs: [path]))
          .single;
      final current = await _read(target);
      final currentHash = current == null ? null : _hash(current);
      if (currentHash == journal['after_hash']) {
        await _acknowledge(path, journal);
        return const EsDePublicationResult('published');
      }
      if (currentHash != journal['before_hash']) {
        return const EsDePublicationResult('fileChanged');
      }
      final pending = jsonDecode(journal['pending_json'] as String) as List;
      for (final row in pending) {
        if (!await isCurrent(
            row['edition_id'] as String, row['identity_key'] as String)) {
          return const EsDePublicationResult('identityChanged');
        }
        final latest = await _db.query('es_de_pending',
            columns: ['revision'],
            where: 'target_path = ? AND edition_id = ?',
            whereArgs: [path, row['edition_id']]);
        if (latest.isEmpty || latest.single['revision'] != row['revision']) {
          return const EsDePublicationResult('pendingChanged');
        }
      }
      final stage = _stage(path, journal);
      final after = utf8.encode(journal['xml'] as String);
      if (_hash(after) != journal['after_hash']) {
        throw const FormatException('Invalid ES-DE publication journal');
      }
      final stageBytes = await _read(stage);
      final isInterruptedPrefix =
          stageBytes != null && _prefix(stageBytes, after);
      if (stageBytes == null || isInterruptedPrefix) {
        await stage.writeAsBytes(after, flush: true);
      } else if (_hash(stageBytes) != journal['after_hash']) {
        return const EsDePublicationResult('stageChanged');
      }
      // This revalidation detects edits since preparation. It is NOT cross-writer
      // CAS; correctness depends on the closed maintenance window remaining true.
      final last = await _read(target);
      if ((last == null ? null : _hash(last)) != journal['before_hash']) {
        return const EsDePublicationResult('fileChanged');
      }
      await stage
          .rename(path); // Same directory/volume; never delete old XML first.
      final published = await _read(target);
      if (published == null || _hash(published) != journal['after_hash']) {
        return const EsDePublicationResult('fileChanged');
      }
      await _acknowledge(path, journal);
      return const EsDePublicationResult('published');
    } finally {
      await lock.close();
    }
  }
}
