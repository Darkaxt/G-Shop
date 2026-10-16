import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/patch_catalogue.dart';
import '../models/portable_patch_recipe.dart';
import 'metadata/shared_metadata_store.dart';

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

/// Private build recovery and public recipes have distinct owners. Reconnecting
/// shared metadata restores instructions, never another device's installations.
class PatchBuildStore {
  final Future<Database> database;
  final Future<SharedMetadataStore?>? sharedStore;
  String? sharedIssue;
  PatchBuildStore(this.database, {this.sharedStore});

  Future<void> publishReady(String buildId) async {
    if (sharedStore == null) return;
    final row = await get(buildId);
    if (row == null || row['state'] != 'ready') return;
    try {
      final shared = await sharedStore!;
      if (shared == null) throw StateError('shared_storage_required');
      await shared.putPatchRecipe(PortablePatchRecipe.fromBuild(row));
      if (row['shareIssue'] != null) {
        await update(buildId, {'shareIssue': null});
      }
    } catch (error) {
      await update(buildId, {
        'shareIssue': error is FormatException &&
                error.message == 'patch_recipe_output_conflict'
            ? 'patch_recipe_output_conflict'
            : 'shared_storage_unavailable'
      });
      // The verified local installation remains ready. Its durable build row is
      // the pending publication source, retried on actual reopening/reconnection.
    }
  }

  Future<PortablePatchRecipe> importRecipe(PortablePatchRecipe recipe) async {
    final shared = await sharedStore;
    if (shared == null) throw StateError('shared_storage_required');
    return shared.putPatchRecipe(recipe);
  }

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

  Future<List<Map<String, dynamic>>> forGame(String platform, String gameId) =>
      _withShared(platform, gameId,
          _read('platform_id=? AND source_game_id=?', [platform, gameId]));
  Future<List<Map<String, dynamic>>> forRecipe(String recipeId) async =>
      _read('recipe_id=?', [recipeId]);
  Future<List<Map<String, dynamic>>> forPlatform(String platform) =>
      _withShared(platform, null, _read('platform_id=?', [platform]));

  Future<List<Map<String, dynamic>>> _withShared(String platform,
      String? gameId, Future<List<Map<String, dynamic>>> privateRows) async {
    var rows = await privateRows;
    sharedIssue = null;
    if (sharedStore == null) return rows;
    for (final row in rows.where((row) => row['state'] == 'ready')) {
      await publishReady(row['buildId'] as String);
    }
    rows = await _read(
        gameId == null ? 'platform_id=?' : 'platform_id=? AND source_game_id=?',
        [platform, if (gameId != null) gameId]);
    try {
      final shared = await sharedStore!;
      if (shared == null) {
        sharedIssue = 'shared_storage_required';
        return rows;
      }
      final recipes = await shared.patchRecipes(platform, sourceGameId: gameId);
      return [
        ...rows,
        for (final portable in recipes)
          if (!rows.any((row) =>
              row['state'] == 'ready' &&
              PatchRecipe.fromJson(
                          (row['recipe'] as Map).cast<String, dynamic>())
                      .id ==
                  portable.recipe.id))
            {
              'state': 'recipe',
              'portable': portable.toJson(),
              'recipe': portable.recipe.toJson(),
              'sourceGameId': portable.sourceGameId,
              'gameTitle': portable.gameTitle,
              'gameIndexPath': portable.gameIndexPath.value,
              'providerSourceId': 'portable',
              'title': portable.title,
            }
      ];
    } catch (_) {
      // Local build history remains usable when the selected shared folder is
      // unavailable; imports/publication still report their actual failure.
      sharedIssue = 'shared_storage_unavailable';
      return rows;
    }
  }

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
