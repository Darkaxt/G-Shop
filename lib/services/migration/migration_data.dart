import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import 'migration_archive.dart';
import 'migration_game_data.dart';

/// Rebind only exact local roots and their descendants, never substring matches
/// in cloud URLs/identities. JSON preference/record strings retain their format.
class MigrationPaths {
  final Map<String, String> roots;
  final Map<String, String> identities;
  late final List<String> _ordered = roots.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  MigrationPaths(this.roots, {this.identities = const {}}) {
    for (final entry in roots.entries) {
      if (!(entry.key.startsWith('/') || p.isAbsolute(entry.key)) ||
          !(entry.value.startsWith('/') || p.isAbsolute(entry.value)) ||
          entry.key == '/' ||
          entry.value == '/' ||
          [entry.key, entry.value].any((v) =>
              v.endsWith('/') ||
              v.split('/').contains('..') ||
              v.contains('\u0000'))) {
        throw const MigrationArchiveException('invalid_root_mapping');
      }
    }
  }
  Object? value(Object? input) {
    if (input is Map) {
      return input.map((key, v) => MapEntry(
          key,
          {
            'auth',
            'credentials',
            'password',
            'secret',
            'token',
            'apikey',
            'api_key',
            'clientsecret',
            'client_secret',
            'providers',
            'sources',
            'provider_config',
            'remote_artifact',
            'artifact',
            'outputartifact'
          }.contains('$key'.toLowerCase())
              ? v
              : value(v)));
    }
    if (input is List) return input.map(value).toList();
    if (input is! String) return input;
    if (identities.containsKey(input)) return identities[input];
    for (final root in _ordered) {
      if (input == root ||
          input.startsWith('$root/') ||
          input.startsWith('$root\\')) {
        return '${roots[root]}${input.substring(root.length)}';
      }
    }
    if (input.startsWith('{') || input.startsWith('[')) {
      try {
        return jsonEncode(value(jsonDecode(input)));
      } on FormatException {
        // An ordinary string is not an invalid migration record.
      }
    }
    return input;
  }
}

class MigrationData {
  /// SQLite's online VACUUM INTO gives one transaction-consistent standalone
  /// database without copying an open WAL/journal. The caller has already joined
  /// file-mutating owners and holds save/cache admissions for its whole snapshot.
  static Future<void> snapshotDatabase(Database db, File destination) async {
    if (await destination.exists()) {
      throw const MigrationArchiveException('destination_exists');
    }
    await destination.parent.create(recursive: true);
    await db.execute('VACUUM INTO ?', [destination.path]);
    if (!await destination.exists() || await destination.length() == 0) {
      throw const MigrationArchiveException('snapshot_failed');
    }
  }

  /// Operates ONLY on the validated incoming private database, not live state.
  /// Historical cloud decisions remain facts, not native work/receipt authority.
  static Future<void> prepareDatabase(Database db,
      {required MigrationPaths paths}) async {
    if (await db.getVersion() != 41) {
      throw const MigrationArchiveException('unsupported_database');
    }
    final tables = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"))
        .map((row) => row['name'] as String)
        .toSet();
    if (!tables
        .containsAll({'games', 'installed_artifacts', 'transfer_records'})) {
      throw const MigrationArchiveException('invalid_database');
    }
    await db.transaction((txn) async {
      await txn.execute('''CREATE TABLE IF NOT EXISTS migration_save_history(
        source_key TEXT PRIMARY KEY, record_json TEXT NOT NULL)''');
      if (tables.contains('save_backup_game_jobs')) {
        final columns =
            await txn.rawQuery('PRAGMA table_info(save_backup_game_jobs)');
        final key =
            columns.any((row) => row['name'] == 'job_key') ? 'job_key' : 'id';
        await txn.execute('INSERT OR REPLACE INTO migration_save_history '
            '(source_key,record_json) SELECT $key,record_json FROM save_backup_game_jobs');
      }
      if (tables.contains('automatic_save_backups')) {
        await txn.execute('''CREATE TABLE IF NOT EXISTS migration_save_mappings(
          source_key TEXT PRIMARY KEY, record_json TEXT NOT NULL, enabled INTEGER NOT NULL)''');
        await txn.execute('INSERT OR REPLACE INTO migration_save_mappings '
            '(source_key,record_json,enabled) SELECT mapping_key,record_json,enabled '
            'FROM automatic_save_backups');
      }
      if (tables.contains('rom_cache_usage')) {
        await txn.execute('''CREATE TABLE IF NOT EXISTS migration_cache_usage(
          installation_id TEXT PRIMARY KEY, installed_at INTEGER, last_used_at INTEGER)''');
        await txn.execute('INSERT OR REPLACE INTO migration_cache_usage '
            'SELECT installation_id,installed_at,last_used_at FROM rom_cache_usage');
      }
      for (final name in {
        'transfer_records',
        'installed_artifacts',
        'transfer_target_owners',
        'transfer_replacements',
        'owned_removals',
        'migration_byte_observations',
        'rom_cache_decisions',
        'rom_cache_usage',
        'rom_cache_clock',
        'drive_catalogue_work',
        'drive_catalogue_pages',
        'automatic_save_backups',
        'save_backup_game_jobs',
        'save_backup_conflict_captures',
      }.intersection(tables)) {
        await txn.delete(name);
      }
      if (tables.contains('drive_catalogue_state')) {
        await txn.update('drive_catalogue_state', {'pending': null});
      }
      // No imported background requests may run on startup. Saved metadata jobs
      // remain user-resumable; they are not restarted merely by importing them.
      for (final jobTable in {'metadata_refresh_jobs', 'metadata_artwork_jobs'}
          .intersection(tables)) {
        final columns = (await txn.rawQuery('PRAGMA table_info($jobTable)'))
            .map((row) => row['name'])
            .toSet();
        if (columns.contains('state')) {
          await txn.rawUpdate("UPDATE $jobTable SET state='paused' "
              "WHERE state IN ('running','queued')");
        }
      }
      if (tables.contains('patch_builds')) {
        for (final row in await txn
            .query('patch_builds', where: 'state<>?', whereArgs: ['ready'])) {
          final record = (jsonDecode(row['record_json'] as String) as Map)
              .cast<String, dynamic>();
          record['inputTransfers'] = <String>[];
          record['issue'] = 'migration_requires_rebuild';
          for (final key in [
            'transferId',
            'outputArtifact',
            'scratchCleanup'
          ]) {
            record.remove(key);
          }
          await txn.update('patch_builds',
              {'state': 'failed', 'record_json': jsonEncode(record)},
              where: 'build_id=?', whereArgs: [row['build_id']]);
        }
      }
      await rebindDatabase(txn, paths: paths);
      if (tables.contains('migration_game_data')) {
        for (final row in await txn.query('migration_game_data')) {
          final data = (jsonDecode(row['record_json'] as String) as Map)
              .cast<String, dynamic>();
          if ({'preparing', 'publishing'}.contains(data['state'])) {
            data['state'] = 'pending';
          }
          for (final key in [
            'restoreId',
            'baselineId',
            'grouped',
            'operationMembers',
            'operationRuntime'
          ]) {
            data.remove(key);
          }
          await txn.update(
              'migration_game_data',
              {
                'state': data['state'],
                'scope_key': MigrationGameData.scopeKey(
                    (data['scope'] as Map).cast<String, Object?>()),
                'record_json': jsonEncode(data),
              },
              where: 'branch_id=?',
              whereArgs: [row['branch_id']]);
        }
      }
    });
  }

  static Future<void> rebindDatabase(DatabaseExecutor db,
      {required MigrationPaths paths}) async {
    final tables = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"))
        .map((row) => row['name'] as String)
        .toSet();
    // Rebind path-bearing columns in bounded rowid batches. Stored IDs, cloud
    // file names, BLOBs and numeric facts remain unchanged.
    for (final table in tables) {
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(table) ||
          table == 'android_metadata') {
        continue;
      }
      final schema = await db.rawQuery('PRAGMA table_info("$table")');
      final columns = schema
          .where((c) => (c['type'] as String).toUpperCase().contains('TEXT'))
          .map((c) => c['name'] as String)
          .toList();
      if (columns.isEmpty) continue;
      var cursor = -9223372036854775807;
      while (true) {
        final rows = await db.rawQuery(
            'SELECT rowid AS migration_rowid,* '
            'FROM "$table" WHERE rowid > ? ORDER BY rowid LIMIT 256',
            [cursor]);
        if (rows.isEmpty) break;
        for (final row in rows) {
          cursor = row['migration_rowid'] as int;
          final changes = <String, Object?>{};
          for (final column in columns) {
            final original = row[column];
            final rebound = paths.value(original);
            if (rebound != original) changes[column] = rebound;
          }
          if (changes.isNotEmpty) {
            await db
                .update(table, changes, where: 'rowid=?', whereArgs: [cursor]);
          }
        }
      }
    }
  }
}
