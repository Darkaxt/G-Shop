import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/rom_cache_policy.dart';

class RomCacheSchema {
  static Future<void> install(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS rom_cache_policy(
      singleton INTEGER PRIMARY KEY CHECK(singleton=1), revision INTEGER NOT NULL,
      record_json TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS rom_cache_usage(
      installation_id TEXT PRIMARY KEY, installed_at INTEGER, last_used_at INTEGER)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS rom_cache_pins(
      collection_key TEXT PRIMARY KEY)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS rom_cache_decisions(
      installation_id TEXT PRIMARY KEY, policy_revision INTEGER NOT NULL,
      reason TEXT NOT NULL, outcome TEXT NOT NULL, issue TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS rom_cache_clock(
      singleton INTEGER PRIMARY KEY CHECK(singleton=1), wall_ms INTEGER NOT NULL,
      elapsed_ms INTEGER NOT NULL, boot_count INTEGER NOT NULL, issue TEXT)''');
  }

  /// Called in the installation's actual commit transaction, never on enumeration
  /// or migration. Existing installations deliberately keep unknown history.
  static Future<void> recordInstalled(
          DatabaseExecutor db, String id, DateTime now) =>
      db.insert(
          'rom_cache_usage',
          {
            'installation_id': id,
            'installed_at': now.toUtc().millisecondsSinceEpoch
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
}

class RomCacheStore {
  final Future<Database> database;
  RomCacheStore(this.database);

  /// Wall/elapsed disagreement is clock evidence, not an operation timeout.
  /// A detected change pauses destructive policy until explicitly acknowledged.
  Future<bool> observeClock(Map<String, int> sample,
      {bool acknowledge = false}) async {
    final wall = sample['wallMillis']!,
        elapsed = sample['elapsedMillis']!,
        boot = sample['bootCount']!;
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query('rom_cache_clock', limit: 1);
      String? issue;
      if (!acknowledge && rows.isNotEmpty) {
        final old = rows.single;
        final wallDelta = wall - (old['wall_ms'] as int);
        final elapsedDelta = elapsed - (old['elapsed_ms'] as int);
        issue = old['issue'] as String?;
        // Samples are taken before the SQL transaction. A UI preview may finish
        // after a newer pass; consistent older samples must not rewind its anchor.
        if (boot == old['boot_count'] &&
            elapsedDelta < 0 &&
            wallDelta <= 0 &&
            (wallDelta - elapsedDelta).abs() <=
                const Duration(minutes: 1).inMilliseconds) {
          return issue == null;
        }
        if (wallDelta < 0 ||
            boot == old['boot_count'] &&
                (elapsedDelta < 0 ||
                    (wallDelta - elapsedDelta).abs() >
                        const Duration(minutes: 1).inMilliseconds)) {
          issue = 'clock_changed';
        }
      }
      await txn.insert(
          'rom_cache_clock',
          {
            'singleton': 1,
            'wall_ms': wall,
            'elapsed_ms': elapsed,
            'boot_count': boot,
            'issue': issue
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      return issue == null;
    });
  }

  Future<RomCachePolicy> policy() async {
    final rows = await (await database).query('rom_cache_policy', limit: 1);
    return rows.isEmpty
        ? RomCachePolicy()
        : RomCachePolicy.decode(
            jsonDecode(rows.single['record_json'] as String) as Map);
  }

  Future<int> revision() async {
    final rows = await (await database)
        .query('rom_cache_policy', columns: ['revision'], limit: 1);
    return rows.isEmpty ? 0 : rows.single['revision'] as int;
  }

  Future<void> savePolicy(RomCachePolicy policy) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows =
          await txn.query('rom_cache_policy', columns: ['revision'], limit: 1);
      await txn.insert(
          'rom_cache_policy',
          {
            'singleton': 1,
            'revision': rows.isEmpty ? 1 : (rows.single['revision'] as int) + 1,
            'record_json': jsonEncode(policy.toJson())
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<({DateTime? installedAt, DateTime? lastUsedAt})?> usage(
      String id) async {
    final rows = await (await database).query('rom_cache_usage',
        where: 'installation_id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    DateTime? time(String key) => rows.single[key] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(rows.single[key] as int,
            isUtc: true);
    return (
      installedAt: time('installed_at'),
      lastUsedAt: time('last_used_at')
    );
  }

  /// Only native successful handoff calls this; browsing/failed starts do not.
  Future<void> recordSuccessfulUse(String id, DateTime now) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('rom_cache_usage', {'installation_id': id},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.rawUpdate(
          '''UPDATE rom_cache_usage SET last_used_at=?
        WHERE installation_id=? AND (last_used_at IS NULL OR last_used_at < ?)''',
          [
            now.toUtc().millisecondsSinceEpoch,
            id,
            now.toUtc().millisecondsSinceEpoch
          ]);
    });
  }

  Future<bool> isPinned(String key) async =>
      (await (await database).query('rom_cache_pins',
              where: 'collection_key=?', whereArgs: [key], limit: 1))
          .isNotEmpty;
  Future<void> setPinned(String key, bool value) async {
    if (key.isEmpty || key.length > 4096) {
      throw ArgumentError('Invalid collection key');
    }
    final db = await database;
    if (value) {
      await db.insert('rom_cache_pins', {'collection_key': key},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.delete('rom_cache_pins',
          where: 'collection_key=?', whereArgs: [key]);
    }
  }
}
