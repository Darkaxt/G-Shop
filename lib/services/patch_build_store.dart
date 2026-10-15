import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/patch_catalogue.dart';

class PatchBuildSchema {
  static Future<void> install(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS patch_builds (
      build_id TEXT PRIMARY KEY, recipe_id TEXT NOT NULL, platform_id TEXT NOT NULL,
      source_game_id TEXT NOT NULL, state TEXT NOT NULL, record_json TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS patch_build_recipe
      ON patch_builds(recipe_id, created_at)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS patch_build_game
      ON patch_builds(platform_id, source_game_id, created_at)''');
  }
}

/// Recipes survive result removal. Device paths/residency remain private;
/// S19 owns migration to the established shared store and portable sharing.
class PatchBuildStore {
  final Future<Database> database;
  PatchBuildStore(this.database);

  Future<void> begin(
      {required String buildId,
      required PatchRecipe recipe,
      required String sourceGameId,
      required String gameTitle,
      required String gameIndexPath,
      required String providerSourceId,
      required String title,
      required String jobRoot,
      required String targetRoot,
      required String filename}) async {
    final db = await database;
    await db.insert('patch_builds', {
      'build_id': buildId,
      'recipe_id': recipe.id,
      'platform_id': recipe.platformId,
      'source_game_id': sourceGameId,
      'state': 'building',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'record_json': jsonEncode({
        'buildId': buildId,
        'recipe': recipe.toJson(),
        'sourceGameId': sourceGameId,
        'gameTitle': gameTitle,
        'gameIndexPath': gameIndexPath,
        'providerSourceId': providerSourceId,
        'title': title,
        'jobRoot': jobRoot,
        'targetRoot': targetRoot,
        'filename': filename,
        'inputTransfers': <String>[],
      }),
    });
  }

  Future<Map<String, dynamic>?> get(String buildId) async {
    final rows = await (await database).query('patch_builds',
        where: 'build_id=?', whereArgs: [buildId], limit: 1);
    if (rows.isEmpty) return null;
    return {
      ...jsonDecode(rows.single['record_json'] as String)
          as Map<String, dynamic>,
      'state': rows.single['state'],
    };
  }

  Future<void> update(String buildId, Map<String, dynamic> changes,
      {String? state}) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('patch_builds',
          where: 'build_id=?', whereArgs: [buildId], limit: 1);
      if (rows.isEmpty) throw StateError('Unknown patch build');
      final record = jsonDecode(rows.single['record_json'] as String)
          as Map<String, dynamic>;
      await txn.update(
          'patch_builds',
          {
            'state': state ?? rows.single['state'],
            'record_json': jsonEncode({...record, ...changes}),
          },
          where: 'build_id=?',
          whereArgs: [buildId]);
    });
  }

  Future<List<Map<String, dynamic>>> forGame(
          String platform, String gameId) async =>
      _read('platform_id=? AND source_game_id=?', [platform, gameId]);
  Future<List<Map<String, dynamic>>> forRecipe(String recipeId) async =>
      _read('recipe_id=?', [recipeId]);
  Future<List<Map<String, dynamic>>> forPlatform(String platform) async =>
      _read('platform_id=?', [platform]);
  Future<List<Map<String, dynamic>>> _read(
      String where, List<Object> args) async {
    final rows = await (await database).query('patch_builds',
        where: where, whereArgs: args, orderBy: 'created_at DESC, build_id');
    return rows
        .map((row) => {
              ...jsonDecode(row['record_json'] as String)
                  as Map<String, dynamic>,
              'state': row['state'],
            })
        .toList();
  }
}
