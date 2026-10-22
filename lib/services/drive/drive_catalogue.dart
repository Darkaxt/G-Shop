import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import '../../models/library_identity.dart';

import 'drive_api.dart';
import 'drive_media.dart';
import 'drive_verification.dart';

class DriveCatalogueException implements Exception {
  final String code;
  const DriveCatalogueException(this.code);
  @override
  String toString() => 'Drive catalogue: $code';
}

class DriveCatalogueEntry {
  final DriveFile file;
  final String displayPath;
  DriveCatalogueEntry(this.file, this.displayPath);
}

class DriveCatalogueSchema {
  static Future<void> installPatchIndexCache(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS drive_patch_index_cache (
      artifact_key TEXT PRIMARY KEY, content_key TEXT NOT NULL, document TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS drive_patch_base_links (
      scope TEXT NOT NULL, generation INTEGER NOT NULL, folder_id TEXT NOT NULL,
      base_file_id TEXT NOT NULL, index_path TEXT NOT NULL, game_id TEXT NOT NULL,
      title TEXT NOT NULL,
      PRIMARY KEY(scope, generation, folder_id, base_file_id, index_path)
    )''');
  }

  static Future<void> install(DatabaseExecutor db) async {
    await installPatchIndexCache(db);
    await db.execute('''CREATE TABLE IF NOT EXISTS drive_catalogue_state (
      scope TEXT PRIMARY KEY, active INTEGER, pending INTEGER,
      next_generation INTEGER NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS drive_catalogue_entries (
      scope TEXT NOT NULL, generation INTEGER NOT NULL, file_id TEXT NOT NULL,
      parent_id TEXT, display_path TEXT NOT NULL, is_folder INTEGER NOT NULL,
      record_json TEXT NOT NULL, file_name TEXT NOT NULL,
      PRIMARY KEY(scope, generation, file_id)
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS drive_catalogue_parent
      ON drive_catalogue_entries(scope, generation, parent_id)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS drive_catalogue_work (
      scope TEXT NOT NULL, generation INTEGER NOT NULL, file_id TEXT NOT NULL,
      page_token TEXT, done INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(scope, generation, file_id)
    )''');
    await installPendingWorkIndex(db);
    await installNameLookup(db);
    await db.execute('''CREATE TABLE IF NOT EXISTS drive_catalogue_pages (
      scope TEXT NOT NULL, generation INTEGER NOT NULL, file_id TEXT NOT NULL,
      page_token TEXT NOT NULL, PRIMARY KEY(scope, generation, file_id, page_token)
    )''');
  }

  /// Exact observed names permit bounded lookups without transferring every
  /// sibling's JSON through the platform channel for each patch/base reference.
  static Future<void> installNameLookup(DatabaseExecutor db) async {
    final columns =
        await db.rawQuery('PRAGMA table_info(drive_catalogue_entries)');
    if (!columns.any((row) => row['name'] == 'file_name')) {
      await db.execute(
          "ALTER TABLE drive_catalogue_entries ADD COLUMN file_name TEXT NOT NULL DEFAULT ''");
      var cursor = 0;
      while (true) {
        final rows = await db.rawQuery(
            '''SELECT rowid AS entry_rowid,record_json
          FROM drive_catalogue_entries WHERE rowid>? ORDER BY rowid LIMIT 256''',
            [cursor]);
        if (rows.isEmpty) break;
        final batch = db.batch();
        for (final row in rows) {
          final name =
              (jsonDecode(row['record_json'] as String) as Map)['name'];
          if (name is! String || name.isEmpty) {
            throw const DriveCatalogueException('invalidCachedFileName');
          }
          cursor = row['entry_rowid'] as int;
          batch.update('drive_catalogue_entries', {'file_name': name},
              where: 'rowid=?', whereArgs: [cursor]);
        }
        await batch.commit(noResult: true);
      }
    }
    await db.execute('''CREATE INDEX IF NOT EXISTS drive_catalogue_name
      ON drive_catalogue_entries(scope, generation, parent_id, file_name)''');
  }

  static Future<void> installPendingWorkIndex(DatabaseExecutor db) async {
    // Equal scope/generation keys are ordered by rowid in this index, keeping
    // durable insertion order without rescanning already completed folders.
    await db.execute('''CREATE INDEX IF NOT EXISTS drive_catalogue_pending_work
      ON drive_catalogue_work(scope, generation) WHERE done=0''');
  }
}

/// A refresh writes page-sized transactions into an unpublished generation.
/// Cursor advancement and its entries commit together; publication is a single
/// pointer swap after traversal and folder-boundary revalidation. Old snapshots
/// remain readable on every failure. No installation table is ever modified.
class DriveCatalogue {
  final Future<Database> _database;
  DriveCatalogue(this._database);

  static String _patchContentKey(RemoteArtifact artifact) {
    final keys = artifact.providerChecksums.keys.toList()..sort();
    return jsonEncode([
      artifact.id.key,
      artifact.version,
      artifact.sizeBytes,
      {for (final key in keys) key: artifact.providerChecksums[key]}
    ]);
  }

  Future<void> cachePatchIndex(
      RemoteArtifact artifact, Map<String, dynamic> document) async {
    await (await _database).insert(
        'drive_patch_index_cache',
        {
          'artifact_key': artifact.id.key,
          'content_key': _patchContentKey(artifact),
          'document': jsonEncode(document),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> cachedPatchIndex(
      RemoteArtifact artifact) async {
    final rows = await (await _database).query('drive_patch_index_cache',
        columns: ['document'],
        where: 'artifact_key=? AND content_key=?',
        whereArgs: [artifact.id.key, _patchContentKey(artifact)],
        limit: 1);
    if (rows.isEmpty) return null;
    return (jsonDecode(rows.single['document'] as String) as Map)
        .cast<String, dynamic>();
  }

  Future<void> cachePatchBaseLinks(
      {required String scope,
      required int generation,
      required String folderId,
      required String indexPath,
      required String gameId,
      required String title,
      required Set<String> baseFileIds}) async {
    await (await _database).transaction((txn) async {
      await txn.delete('drive_patch_base_links',
          where: 'scope=? AND folder_id=? AND generation<>?',
          whereArgs: [scope, folderId, generation]);
      await txn.delete('drive_patch_base_links',
          where: 'scope=? AND generation=? AND folder_id=? AND index_path=?',
          whereArgs: [scope, generation, folderId, indexPath]);
      for (final id in baseFileIds) {
        await txn.insert('drive_patch_base_links', {
          'scope': scope,
          'generation': generation,
          'folder_id': folderId,
          'base_file_id': id,
          'index_path': indexPath,
          'game_id': gameId,
          'title': title
        });
      }
    });
  }

  Future<List<Map<String, Object?>>> cachedPatchGames(
          {required String scope,
          required int generation,
          required String folderId,
          required String baseFileId}) async =>
      (await _database).query('drive_patch_base_links',
          columns: ['index_path', 'game_id', 'title'],
          where: 'scope=? AND generation=? AND folder_id=? AND base_file_id=?',
          whereArgs: [scope, generation, folderId, baseFileId]);

  static String scopeKey(
          String sourceId, String accountId, String rootFolderId) =>
      jsonEncode([sourceId, accountId, rootFolderId]);

  void _cancelled(CancelToken? token) {
    if (token?.isCancelled == true) {
      throw const DriveCatalogueException('cancelled');
    }
  }

  Future<void> refresh(
      {required String sourceId,
      required String accountId,
      required String rootFolderId,
      required DriveCatalogueApi api,
      bool restart = false,
      void Function(int filesRead, int foldersChecked)? onProgress,
      CancelToken? cancelToken}) async {
    if ([sourceId, accountId, rootFolderId].any((s) => s.isEmpty) ||
        rootFolderId == 'root') {
      throw const DriveCatalogueException('invalidRootIdentity');
    }
    _cancelled(cancelToken);
    final root = await api.getFile(rootFolderId, cancelToken: cancelToken);
    if (!root.isFolder || root.id != rootFolderId) {
      throw const DriveCatalogueException('unsupportedRoot');
    }
    final db = await _database;
    final scope = scopeKey(sourceId, accountId, rootFolderId);
    final generation = await db.transaction((txn) async {
      _cancelled(cancelToken);
      final rows = await txn.query('drive_catalogue_state',
          where: 'scope = ?', whereArgs: [scope]);
      final previous = rows.isEmpty ? null : rows.single;
      final pending = previous?['pending'] as int?;
      if (pending != null && !restart) return pending;
      final generation = previous?['next_generation'] as int? ?? 1;
      await _discardInactive(txn, scope, previous?['active'] as int?);
      await txn.insert(
          'drive_catalogue_state',
          {
            'scope': scope,
            'active': previous?['active'],
            'pending': generation,
            'next_generation': generation + 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await _put(txn, scope, generation, root, null, '');
      return generation;
    });
    var filesRead = 0;
    var foldersChecked = 0;
    onProgress?.call(filesRead, foldersChecked);
    try {
      while (true) {
        _cancelled(cancelToken);
        // Keep pending work outermost: older Android SQLite planners otherwise
        // scan the full catalogue and sort it to choose a single work item.
        final work = await db.rawQuery(
            '''SELECT w.*, e.record_json, e.display_path
          FROM drive_catalogue_work w CROSS JOIN drive_catalogue_entries e
          ON e.scope=w.scope AND e.generation=w.generation AND e.file_id=w.file_id
          WHERE w.scope=? AND w.generation=? AND w.done=0 ORDER BY w.rowid LIMIT 1''',
            [scope, generation]);
        if (work.isEmpty) break;
        final row = work.single;
        final parent = DriveFile.fromJson(
            jsonDecode(row['record_json'] as String) as Map<String, dynamic>);
        _sameFolder(
            parent, await api.getFile(parent.id, cancelToken: cancelToken));
        final cursor = row['page_token'] as String?;
        final page = await api.listChildren(parent.id,
            pageToken: cursor, cancelToken: cancelToken);
        _cancelled(cancelToken);
        await db.transaction((txn) async {
          await _requirePending(txn, scope, generation);
          final current = await txn.query('drive_catalogue_work',
              where: 'scope=? AND generation=? AND file_id=?',
              whereArgs: [scope, generation, parent.id]);
          if (current.single['done'] != 0 ||
              current.single['page_token'] != cursor) {
            throw const DriveCatalogueException('concurrentRefresh');
          }
          final repeated = await txn.query('drive_catalogue_pages',
              where: 'scope=? AND generation=? AND file_id=? AND page_token=?',
              whereArgs: [
                scope,
                generation,
                parent.id,
                page.nextPageToken ?? ''
              ],
              limit: 1);
          if (page.nextPageToken != null &&
              (page.nextPageToken == cursor || repeated.isNotEmpty)) {
            throw const DriveCatalogueException('repeatedPageToken');
          }
          await txn.insert('drive_catalogue_pages', {
            'scope': scope,
            'generation': generation,
            'file_id': parent.id,
            'page_token': cursor ?? '',
          });
          for (final file in page.files) {
            // Every edge must have come from this exact parent. A shortcut is
            // retained as an unsupported record, never substituted with its target.
            if (file.parents.length != 1 ||
                file.parents.single != parent.id ||
                file.id == rootFolderId ||
                file.trashed) {
              throw const DriveCatalogueException('invalidParent');
            }
            final exists = await txn.query('drive_catalogue_entries',
                columns: ['file_id'],
                where: 'scope=? AND generation=? AND file_id=?',
                whereArgs: [scope, generation, file.id],
                limit: 1);
            if (exists.isNotEmpty) {
              throw const DriveCatalogueException('duplicateOrMovedEntry');
            }
            final path = row['display_path'] as String;
            await _put(txn, scope, generation, file, parent.id,
                path.isEmpty ? file.name : '$path/${file.name}');
          }
          await txn.update(
              'drive_catalogue_work',
              {
                'page_token': page.nextPageToken,
                'done': page.nextPageToken == null ? 1 : 0
              },
              where: 'scope=? AND generation=? AND file_id=?',
              whereArgs: [scope, generation, parent.id]);
          _cancelled(cancelToken);
        });
        filesRead += page.files.where((file) => !file.isFolder).length;
        if (page.nextPageToken == null) foldersChecked++;
        onProgress?.call(filesRead, foldersChecked);
      }
      // The provider does not offer a subtree-wide snapshot transaction. Check
      // every observed folder again to reject a moved ancestor before publishing;
      // transfers must still revalidate the individual file's current lineage.
      var offset = 0;
      while (true) {
        final folders = await db.query('drive_catalogue_entries',
            columns: ['record_json'],
            where: 'scope=? AND generation=? AND is_folder=1',
            whereArgs: [scope, generation],
            orderBy: 'file_id',
            limit: 100,
            offset: offset);
        if (folders.isEmpty) break;
        _cancelled(cancelToken);
        final expectedFolders = [
          for (final row in folders)
            DriveFile.fromJson(jsonDecode(row['record_json'] as String)
                as Map<String, dynamic>)
        ];
        final actualFolders = await api.getFolderBatch(
            expectedFolders.map((folder) => folder.id).toList(),
            cancelToken: cancelToken);
        _cancelled(cancelToken);
        if (actualFolders.length != expectedFolders.length) {
          throw const DriveApiException(DriveApiIssue.invalidResponse);
        }
        for (var index = 0; index < expectedFolders.length; index++) {
          _cancelled(cancelToken);
          _sameFolder(expectedFolders[index], actualFolders[index]);
        }
        offset += folders.length;
      }
      await db.transaction((txn) async {
        _cancelled(cancelToken);
        await _requirePending(txn, scope, generation);
        await txn.update(
            'drive_catalogue_state', {'active': generation, 'pending': null},
            where: 'scope=?', whereArgs: [scope]);
        await _discardInactive(txn, scope, generation);
        await txn.delete('drive_catalogue_work',
            where: 'scope=? AND generation=?', whereArgs: [scope, generation]);
        await txn.delete('drive_catalogue_pages',
            where: 'scope=? AND generation=?', whereArgs: [scope, generation]);
        _cancelled(cancelToken);
      });
    } on DriveCatalogueException catch (error) {
      if (!{'cancelled', 'concurrentRefresh', 'supersededRefresh'}
          .contains(error.code)) {
        await _invalidatePending(db, scope, generation);
      }
      rethrow;
    } on DriveApiException catch (error) {
      if (error.issue == DriveApiIssue.invalidPageToken ||
          error.issue == DriveApiIssue.notFound) {
        // Invalid server cursors cannot be resumed. Forget only the unpublished
        // generation; next explicit refresh starts clean, with no hidden retry.
        await _invalidatePending(db, scope, generation);
      }
      rethrow;
    }
  }

  Future<void> _invalidatePending(Database db, String scope, int generation) =>
      db.transaction((txn) async {
        // Compare-and-clear so an old refresh cannot invalidate a newer job.
        await txn.update('drive_catalogue_state', {'pending': null},
            where: 'scope=? AND pending=?', whereArgs: [scope, generation]);
      });

  void _sameFolder(DriveFile expected, DriveFile actual) {
    if (!actual.isFolder ||
        expected.id != actual.id ||
        expected.name != actual.name ||
        jsonEncode(expected.parents) != jsonEncode(actual.parents)) {
      throw const DriveCatalogueException('folderChanged');
    }
  }

  Future<void> _requirePending(
      DatabaseExecutor db, String scope, int generation) async {
    final state = await db.query('drive_catalogue_state',
        columns: ['pending'], where: 'scope=?', whereArgs: [scope]);
    if (state.isEmpty || state.single['pending'] != generation) {
      throw const DriveCatalogueException('supersededRefresh');
    }
  }

  Future<void> _put(DatabaseExecutor db, String scope, int generation,
      DriveFile file, String? parentId, String path) async {
    await db.insert('drive_catalogue_entries', {
      'scope': scope,
      'generation': generation,
      'file_id': file.id,
      'file_name': file.name,
      'parent_id': parentId,
      'display_path': path,
      'is_folder': file.isFolder ? 1 : 0,
      'record_json': jsonEncode(file.toJson())
    });
    if (file.isFolder) {
      await db.insert('drive_catalogue_work', {
        'scope': scope,
        'generation': generation,
        'file_id': file.id,
      });
    }
  }

  Future<void> _discardInactive(
      DatabaseExecutor db, String scope, int? keep) async {
    for (final table in [
      'drive_catalogue_entries',
      'drive_catalogue_work',
      'drive_catalogue_pages'
    ]) {
      await db.delete(table,
          where: keep == null ? 'scope=?' : 'scope=? AND generation!=?',
          whereArgs: keep == null ? [scope] : [scope, keep]);
    }
  }

  Future<int?> activeGeneration(
      {required String sourceId,
      required String accountId,
      required String rootFolderId}) async {
    final db = await _database;
    final state = await db.query('drive_catalogue_state',
        columns: ['active'],
        where: 'scope=?',
        whereArgs: [scopeKey(sourceId, accountId, rootFolderId)]);
    return state.isEmpty ? null : state.single['active'] as int?;
  }

  Future<DriveFile> requireFolder(
      {required String sourceId,
      required String accountId,
      required String rootFolderId,
      required String folderId,
      required int generation}) async {
    final db = await _database;
    final scope = scopeKey(sourceId, accountId, rootFolderId);
    final rows = await db.rawQuery(
        '''SELECT e.record_json FROM drive_catalogue_entries e
      JOIN drive_catalogue_state s ON s.scope=e.scope AND s.active=e.generation
      WHERE e.scope=? AND e.generation=? AND e.file_id=? AND e.is_folder=1''',
        [scope, generation, folderId]);
    if (rows.isEmpty) throw const DriveCatalogueException('mappingUnavailable');
    return DriveFile.fromJson(jsonDecode(rows.single['record_json'] as String)
        as Map<String, dynamic>);
  }

  /// Exact observed binary in a still-published snapshot, never a filename match.
  Future<DriveFile> requireBinary(
      {required String sourceId,
      required String accountId,
      required String rootFolderId,
      required String fileId,
      required int generation}) async {
    final db = await _database;
    final rows = await db.rawQuery('''SELECT e.record_json
      FROM drive_catalogue_entries e
      JOIN drive_catalogue_state s ON s.scope=e.scope AND s.active=e.generation
      WHERE e.scope=? AND e.generation=? AND e.file_id=? AND e.is_folder=0''',
        [scopeKey(sourceId, accountId, rootFolderId), generation, fileId]);
    if (rows.isEmpty) {
      throw const DriveCatalogueException('artifactUnavailable');
    }
    final file = DriveFile.fromJson(
        jsonDecode(rows.single['record_json'] as String)
            as Map<String, dynamic>);
    if (!file.isSupportedBinary) {
      throw const DriveCatalogueException('unsupportedArtifact');
    }
    return file;
  }

  /// Reconcile only a byte-identical patch-index metadata revision, after its
  /// live ancestry was verified. No path, parent, content or generation changes.
  Future<void> reconcilePatchIndexRevision({
    required String sourceId,
    required String accountId,
    required String rootFolderId,
    required int generation,
    required RemoteArtifact expected,
    required DriveFile current,
    required CancelToken cancellation,
  }) async {
    if (!{'index.json', 'game.json'}.contains(expected.displayName) ||
        current.name != expected.displayName ||
        expected.id.sourceId != sourceId ||
        expected.id.accountId != accountId) {
      throw const DriveTransferException(DriveTransferIssue.sourceChanged);
    }
    DriveVerification(expected).requirePatchIndexMetadataRevision(current);
    final db = await _database;
    final scope = scopeKey(sourceId, accountId, rootFolderId);
    await db.transaction((txn) async {
      _cancelled(cancellation);
      final state = await txn.query('drive_catalogue_state',
          columns: ['active'], where: 'scope=?', whereArgs: [scope]);
      if (state.isEmpty || state.single['active'] != generation) {
        throw const DriveCatalogueException('snapshotChanged');
      }
      final rows = await txn.query('drive_catalogue_entries',
          columns: ['record_json'],
          where: 'scope=? AND generation=? AND file_id=? AND is_folder=0',
          whereArgs: [scope, generation, expected.id.providerFileId]);
      if (rows.length != 1) {
        throw const DriveCatalogueException('artifactUnavailable');
      }
      final cached = DriveFile.fromJson(
          jsonDecode(rows.single['record_json'] as String)
              as Map<String, dynamic>);
      DriveVerification(expected).requireCurrent(cached);
      if (cached.name != expected.displayName) {
        throw const DriveTransferException(DriveTransferIssue.sourceChanged);
      }
      _cancelled(cancellation);
      await txn.update('drive_catalogue_entries',
          {'record_json': jsonEncode(current.toJson())},
          where: 'scope=? AND generation=? AND file_id=? AND is_folder=0',
          whereArgs: [scope, generation, expected.id.providerFileId]);
      _cancelled(cancellation);
    });
  }

  /// Paged descendants of an observed folder ID, never a path-prefix match.
  Future<DriveCatalogueEntry> requireRelativeBinary(
      {required String sourceId,
      required String accountId,
      required String rootFolderId,
      required String parentId,
      required List<String> segments,
      required int generation}) async {
    if (segments.isEmpty ||
        segments.any((s) =>
            s.isEmpty ||
            s == '.' ||
            s == '..' ||
            s.contains('/') ||
            s.contains('\\'))) {
      throw const DriveCatalogueException('unsafeDependency');
    }
    final db = await _database;
    final scope = scopeKey(sourceId, accountId, rootFolderId);
    return db.transaction((txn) async {
      var parent = parentId;
      DriveCatalogueEntry? result;
      for (var i = 0; i < segments.length; i++) {
        final matches = await txn
            .rawQuery('''SELECT e.file_id, e.record_json, e.display_path
          FROM drive_catalogue_entries e JOIN drive_catalogue_state s
          ON s.scope=e.scope AND s.active=e.generation
          WHERE e.scope=? AND e.generation=? AND e.parent_id=? AND e.file_name=?
          LIMIT 2''', [scope, generation, parent, segments[i]]);
        // Duplicate names in Drive are legal. Two matches establish ambiguity;
        // never pick a namesake or normalize case/Unicode to manufacture a match.
        if (matches.length != 1) {
          throw const DriveCatalogueException('ambiguousOrMissingDependency');
        }
        final row = matches.single;
        final file = DriveFile.fromJson(
            jsonDecode(row['record_json'] as String) as Map<String, dynamic>);
        if (file.name != segments[i]) {
          throw const DriveCatalogueException('snapshotChanged');
        }
        if (i + 1 < segments.length
            ? !file.isFolder
            : !file.isSupportedBinary) {
          throw const DriveCatalogueException('unsupportedDependency');
        }
        result = DriveCatalogueEntry(file, row['display_path'] as String);
        parent = file.id;
      }
      return result!;
    });
  }

  /// Paged descendants of an observed folder ID, never a path-prefix match.
  Future<List<DriveCatalogueEntry>> entries(
      {required String sourceId,
      required String accountId,
      required String rootFolderId,
      required String folderId,
      int limit = 500,
      int offset = 0,
      int? generation}) async {
    if (limit < 1 || limit > 1000 || offset < 0) {
      throw ArgumentError('Invalid catalogue page');
    }
    final db = await _database;
    final scope = scopeKey(sourceId, accountId, rootFolderId);
    return db.transaction((txn) async {
      if (generation != null) {
        final state = await txn.query('drive_catalogue_state',
            columns: ['active'], where: 'scope=?', whereArgs: [scope]);
        if (state.isEmpty || state.single['active'] != generation) {
          throw const DriveCatalogueException('snapshotChanged');
        }
      }
      // Every row of a published generation was observed by the validated root
      // traversal. A root page need not rebuild that same tree on each request.
      // Still require its supported root row and the exact active generation.
      if (folderId == rootFolderId) {
        final rows = await txn.rawQuery('''SELECT e.record_json,e.display_path
          FROM drive_catalogue_state s
          JOIN drive_catalogue_entries r ON r.scope=s.scope
            AND r.generation=COALESCE(?,s.active) AND r.file_id=? AND r.is_folder=1
          JOIN drive_catalogue_entries e ON e.scope=r.scope AND e.generation=r.generation
          WHERE s.scope=? AND e.file_id!=r.file_id
          ORDER BY e.file_id LIMIT ? OFFSET ?''',
            [generation, rootFolderId, scope, limit, offset]);
        return rows
            .map((r) => DriveCatalogueEntry(
                DriveFile.fromJson(jsonDecode(r['record_json'] as String)
                    as Map<String, dynamic>),
                r['display_path'] as String))
            .toList();
      }
      final rows =
          await txn.rawQuery('''WITH RECURSIVE descendants(file_id) AS (
      SELECT e.file_id FROM drive_catalogue_entries e JOIN drive_catalogue_state s ON s.scope=e.scope
      WHERE e.scope=? AND e.generation=COALESCE(?,s.active) AND e.file_id=? AND e.is_folder=1
      UNION ALL SELECT e.file_id FROM drive_catalogue_state s
      CROSS JOIN descendants d
      CROSS JOIN drive_catalogue_entries e INDEXED BY drive_catalogue_parent ON e.parent_id=d.file_id
      WHERE s.scope=? AND e.scope=s.scope AND e.generation=COALESCE(?,s.active)
        AND e.is_folder=1
    ), page(file_id) AS (
      SELECT e.file_id FROM drive_catalogue_state s
      CROSS JOIN descendants d
      CROSS JOIN drive_catalogue_entries e INDEXED BY drive_catalogue_parent ON e.parent_id=d.file_id
      WHERE s.scope=? AND e.scope=s.scope AND e.generation=COALESCE(?,s.active)
      ORDER BY e.file_id LIMIT ? OFFSET ?
    ) SELECT e.record_json, e.display_path FROM drive_catalogue_state s
      CROSS JOIN page d
      CROSS JOIN drive_catalogue_entries e ON d.file_id=e.file_id
      WHERE s.scope=? AND e.scope=s.scope AND e.generation=COALESCE(?,s.active)
      ORDER BY d.file_id''', [
        scope,
        generation,
        folderId,
        scope,
        generation,
        scope,
        generation,
        limit,
        offset,
        scope,
        generation
      ]);
      return rows
          .map((r) => DriveCatalogueEntry(
              DriveFile.fromJson(jsonDecode(r['record_json'] as String)
                  as Map<String, dynamic>),
              r['display_path'] as String))
          .toList();
    });
  }
}
