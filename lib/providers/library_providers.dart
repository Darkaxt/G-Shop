import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/database_service.dart';
import '../services/library_sync_service.dart';
import '../services/library_query.dart';
import '../services/metadata/effective_overall_rating.dart';
import '../services/metadata/metadata_artwork_cache.dart';
import '../services/metadata/shared_metadata_store.dart';
export '../services/library_query.dart' show coverRatingKey;

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

const sharedMetadataDirectoryKey = 'metadata_shared_directory_v1';

/// The choice is private configuration, while facts/artwork live in the chosen
/// shared directory. Opening a cache never authenticates or fetches ROM/media.
final sharedMetadataStoreProvider =
    Provider<Future<SharedMetadataStore?>>((ref) {
  var disposed = false;
  SharedMetadataStore? opened;
  ref.onDispose(() {
    disposed = true;
    unawaited(opened?.close());
  });
  return () async {
    final prefs = await SharedPreferences.getInstance();
    final selected = prefs.getString(sharedMetadataDirectoryKey);
    if (selected == null) return null;
    final store =
        await SharedMetadataStore.open(Directory(selected), existingOnly: true);
    if (disposed) {
      await store.close();
      throw StateError('Metadata cache owner was disposed');
    }
    opened = store;
    return store;
  }();
});

/// Catalogue publication can happen after the durable store was opened. Join
/// its projection before normal discovery/ratings/detail reads; don't dispose
/// the store or interrupt its worker just because a catalogue changed.
final sharedMetadataProjectionProvider = FutureProvider<int>((ref) async {
  ref.watch(gameDbChangedProvider);
  ref.watch(librarySyncServiceProvider.select((s) => s.completedSystems));
  final database = ref.watch(libraryDbProvider).database;
  final shared = await ref.watch(sharedMetadataStoreProvider);
  if (shared == null) return 0;
  return shared.restore(await database);
});

/// Join recovery when it is available, without making an unavailable metadata
/// store a prerequisite for reading the last usable private projection. Keep the
/// actual failure as data; the strict store/projection providers and settings
/// continue to report it, and refresh/publication must still use the strict path.
final cachedMetadataReadinessProvider =
    FutureProvider<AsyncValue<int>>((ref) async {
  try {
    return AsyncData(await ref.watch(sharedMetadataProjectionProvider.future));
  } catch (error, stack) {
    return AsyncError(error, stack);
  }
});

/// Producer and readers use the same selected root. Before a user selects shared
/// storage, preserve the existing private cache for non-destructive migration.
final metadataArtworkCacheProvider =
    Provider<Future<MetadataArtworkCache>>((ref) {
  final database = ref.watch(libraryDbProvider).database;
  final shared = ref.watch(sharedMetadataStoreProvider);
  return () async {
    final store = await shared;
    return store == null
        ? await MetadataArtworkCache.open(database)
        : MetadataArtworkCache(database, store.artworkRoot, sharedStore: store);
  }();
});

/// Cache readers do not need a writable shared database. On storage failure use
/// only the recorded artwork location and the last private manifest: no opening,
/// directory creation, migration, body request or alternate write destination.
final cachedMetadataArtworkProvider =
    Provider<Future<MetadataArtworkCache>>((ref) {
  final database = ref.watch(libraryDbProvider).database;
  return () async {
    final readiness = await ref.watch(cachedMetadataReadinessProvider.future);
    if (!readiness.hasError) return ref.watch(metadataArtworkCacheProvider);
    final prefs = await SharedPreferences.getInstance();
    final selected = prefs.getString(sharedMetadataDirectoryKey);
    return selected == null
        ? await MetadataArtworkCache.open(database)
        : MetadataArtworkCache(database, Directory('$selected/artwork'));
  }();
});

final cachedMetadataCoversProvider = FutureProvider.autoDispose
    .family<Map<String, String?>, String>((ref, scope) async {
  ref.watch(gameDbChangedProvider);
  ref.watch(librarySyncServiceProvider.select((s) => s.completedSystems));
  var active = true;
  ref.onDispose(() => active = false);
  final db = await ref.watch(libraryDbProvider).database;
  await ref.watch(cachedMetadataReadinessProvider.future);
  final cache = await ref.watch(cachedMetadataArtworkProvider);
  final query = LibraryQuery(Future.value(db));
  var cursor = 0;
  final result = <String, String?>{};
  while (active) {
    final rows = await db.query('games',
        columns: ['id', 'systemSlug', 'filename', 'artifact_key'],
        where: 'id > ? AND is_folder = 0'
            '${scope.isEmpty ? '' : ' AND systemSlug = ?'}',
        whereArgs: [cursor, if (scope.isNotEmpty) scope],
        orderBy: 'id',
        limit: 128);
    if (!active || rows.isEmpty) break;
    final covers = await query.cachedCovers(
        rows.map((r) => r['id'] as int).toList(), cache);
    if (!active) break;
    for (final row in rows) {
      final artifact = row['artifact_key'] as String?;
      final key = coverRatingKey(row['systemSlug'] as String,
          artifact == null ? row['filename'] as String : 'artifact:$artifact');
      result[key] = result.containsKey(key) ? null : covers[row['id']];
    }
    cursor = rows.last['id'] as int;
    if (rows.length < 128) break;
  }
  return Map.unmodifiable(result);
});

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
  await ref.watch(cachedMetadataReadinessProvider.future);
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
