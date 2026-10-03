import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';

import '../services/database_service.dart';
import '../services/library_sync_service.dart';
import '../services/library_query.dart';
import '../services/metadata/effective_overall_rating.dart';

final libraryDbProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

final librarySyncServiceProvider =
    StateNotifierProvider<LibrarySyncService, LibrarySyncState>((ref) {
  return LibrarySyncService();
});

/// Bumped when games are saved to DB outside of LibrarySyncService
/// (e.g. by GameListController). Watched by count providers to re-query.
final gameDbChangedProvider = StateProvider<int>((ref) => 0);

/// Exact cover ownership uses the existing selection identity plus console.
/// A cleaned title is never used to attach a rating to a different artifact.
String coverRatingKey(String systemSlug, String selectionKey) =>
    jsonEncode([systemSlug, selectionKey]);

/// One shared, cache-only read per mounted view. Scores are fetched in pages of
/// 128, not per card/frame; scrolling only reads this immutable in-memory map.
/// Empty scope is the cross-system library, including its existing shelves.
final cachedCoverRatingsProvider = FutureProvider.autoDispose
    .family<Map<String, EffectiveOverallRating?>, String>((ref, scope) async {
  ref.watch(gameDbChangedProvider);
  ref.watch(librarySyncServiceProvider.select((s) => s.completedSystems));
  var active = true;
  ref.onDispose(() => active = false);
  final db = await ref.watch(libraryDbProvider).database;
  final query = LibraryQuery(Future.value(db));
  var cursor = 0;
  final result = <String, EffectiveOverallRating?>{};
  while (active) {
    final rows = await db.query('games',
        columns: ['id', 'systemSlug', 'filename', 'artifact_key'],
        where: 'id > ? AND is_folder = 0'
            '${scope.isEmpty ? '' : ' AND systemSlug = ?'}',
        whereArgs: [cursor, if (scope.isNotEmpty) scope],
        orderBy: 'id',
        limit: 128);
    if (!active || rows.isEmpty) break;
    final ratings =
        await query.cachedRatings(rows.map((row) => row['id'] as int).toList());
    if (!active) break;
    for (final row in rows) {
      final artifact = row['artifact_key'] as String?;
      final key = coverRatingKey(row['systemSlug'] as String,
          artifact == null ? row['filename'] as String : 'artifact:$artifact');
      // A duplicate UI identity is ambiguous; don't choose its largest score.
      result[key] = result.containsKey(key) ? null : ratings[row['id']];
    }
    cursor = rows.last['id'] as int;
    if (rows.length < 128) break;
  }
  return Map.unmodifiable(result);
});

/// Whether the last library sync had failures (and is not currently syncing).
final lastSyncHadFailuresProvider = Provider<bool>((ref) {
  final state = ref.watch(librarySyncServiceProvider);
  return !state.isSyncing && state.hadFailures;
});

/// Game counts per system, auto-refreshes when sync starts or completes.
final gameCountsPerSystemProvider =
    FutureProvider<Map<String, int>>((ref) async {
  // Re-fetch after each system completes sync
  ref.watch(librarySyncServiceProvider.select((s) => s.completedSystems));
  ref.watch(gameDbChangedProvider);
  return ref.read(libraryDbProvider).getGameCountsPerSystem();
});
