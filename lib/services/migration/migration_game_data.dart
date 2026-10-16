import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../saves/save_capture.dart';
import 'migration_archive.dart';

/// Actual imported game data is a local device-aware backup branch. It is not
/// an uploaded cloud generation, native capture receipt or permission grant.
/// Existing destination saves remain current; absent saves materialize through
/// the established native restore lane before launching the game.
class MigrationGameData {
  final String id;
  final Map<String, dynamic> data;
  MigrationGameData(this.id, this.data);
  String get state => data['state'] as String;
  List<Map<String, dynamic>> get members => (data['members'] as List)
      .map((raw) => (raw as Map).cast<String, dynamic>())
      .toList();
  String? get restoreId => data['restoreId'] as String?;
  String? get baselineId => data['baselineId'] as String?;
  bool get grouped => data['grouped'] == true;

  static String scopeKey(Map<String, Object?> scope) {
    final keys = scope.keys.toList()..sort();
    return sha256
        .convert(
            utf8.encode(jsonEncode({for (final key in keys) key: scope[key]})))
        .toString();
  }

  static Future<void> install(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS migration_game_data(
      branch_id TEXT PRIMARY KEY, scope_key TEXT NOT NULL, state TEXT NOT NULL,
      created_at INTEGER NOT NULL, record_json TEXT NOT NULL)''');
    await db.execute('CREATE INDEX IF NOT EXISTS migration_game_data_scope '
        'ON migration_game_data(scope_key,state,created_at)');
  }

  static Future<MigrationGameData?> latest(
      Database db, Map<String, Object?> scope) async {
    await install(db);
    final rows = await db.query('migration_game_data',
        where: 'scope_key=?',
        whereArgs: [scopeKey(scope)],
        orderBy: 'created_at DESC, branch_id',
        limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.single;
    final encoded = row['record_json'] as String;
    if (encoded.length > 128 * 1024) {
      throw const MigrationArchiveException('invalid_game_data');
    }
    final data = (jsonDecode(encoded) as Map).cast<String, dynamic>();
    if (data['schema'] != 1 ||
        data['id'] != row['branch_id'] ||
        data['state'] != row['state'] ||
        data['scope'] is! Map ||
        scopeKey((data['scope'] as Map).cast<String, Object?>()) !=
            row['scope_key'] ||
        data['members'] is! List ||
        (data['members'] as List).length > 128) {
      throw const MigrationArchiveException('invalid_game_data');
    }
    if (!{
      'pending',
      'conflict',
      'preparing',
      'publishing',
      'restored',
      'ignored'
    }.contains(data['state'])) {
      throw const MigrationArchiveException('invalid_game_data');
    }
    if ({'preparing', 'publishing'}.contains(data['state']) &&
        (data['restoreId'] is! String ||
            data['baselineId'] is! String ||
            !RegExp(r'^[a-f0-9]{32}$').hasMatch(data['restoreId']) ||
            !RegExp(r'^[a-f0-9]{32}$').hasMatch(data['baselineId']) ||
            data['restoreId'] == data['baselineId'] ||
            data['grouped'] is! bool ||
            data['operationMembers'] is! List ||
            data['operationRuntime'] is! Map)) {
      throw const MigrationArchiveException('invalid_game_data');
    }
    final names = <String>{};
    for (final raw in data['members'] as List) {
      if (raw is! Map ||
          raw['name'] is! String ||
          raw['path'] is! String ||
          raw['size'] is! int ||
          raw['size'] < 0 ||
          raw['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['sha256']) ||
          !names.add((raw['name'] as String).toLowerCase())) {
        throw const MigrationArchiveException('invalid_game_data');
      }
      MigrationArchive.checkName(raw['name']);
    }
    return MigrationGameData(row['branch_id'] as String, data);
  }

  Future<void> save(Database db, String next,
      {String? restoreId, String? baselineId, bool? grouped}) async {
    data['state'] = next;
    if (restoreId != null) data['restoreId'] = restoreId;
    if (baselineId != null) data['baselineId'] = baselineId;
    if (grouped != null) data['grouped'] = grouped;
    await db.update(
        'migration_game_data', {'state': next, 'record_json': jsonEncode(data)},
        where: 'branch_id=?', whereArgs: [id]);
  }

  Future<List<RestoreSaveMember>> restoreMembers(
      {List<Map<String, dynamic>>? from}) async {
    final support =
        await (await getApplicationSupportDirectory()).resolveSymbolicLinks();
    final roots = ['migration-game-data', 'save-captures', 'migration-history']
        .map((name) => p.join(support, name))
        .toList();
    final result = <RestoreSaveMember>[];
    for (final member in from ?? members) {
      final name = member['name'] as String;
      MigrationArchive.checkName(name);
      final file = File(member['path'] as String);
      if (!roots.any((root) => p.isWithin(root, file.absolute.path)) ||
          await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          p.normalize(await file.resolveSymbolicLinks()) !=
              p.normalize(file.absolute.path) ||
          await file.length() != member['size'] ||
          '${await sha256.bind(file.openRead()).first}' != member['sha256']) {
        throw const MigrationArchiveException('game_data_changed');
      }
      result.add(RestoreSaveMember(name, member['size'] as int,
          member['sha256'] as String, file.openRead().map(Uint8List.fromList)));
    }
    return result;
  }
}
