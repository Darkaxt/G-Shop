import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/database_service.dart';
import '../services/library_sync_service.dart';
import '../services/library_query.dart';
import '../services/metadata/effective_overall_rating.dart';
import '../services/metadata/metadata_artwork_cache.dart';
import '../services/metadata/shared_metadata_store.dart';
import '../models/game_item.dart';
import '../models/config/provider_config.dart';
import '../models/library_identity.dart';
import '../utils/game_merge_helper.dart';
import 'installed_files_provider.dart';
import 'app_providers.dart';
import 'shelf_providers.dart';
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

/// Use complete cache membership so an unlinked namesake in another console
/// retains its legacy selection. Does not rewrite catalogue/metadata/job rows.
final selectionContinuityProvider = FutureProvider<void>((ref) async {
  var active = true;
  ref.onDispose(() => active = false);
  ref.watch(gameDbChangedProvider);
  ref.watch(librarySyncServiceProvider.select((s) => s.completedSystems));
  final installation = await ref.watch(installedFilesProvider.future);
  if (!active ||
      installation.legacyAliasesBySystem.values.every((m) => m.isEmpty)) {
    return;
  }
  final database = await ref.watch(libraryDbProvider).database;
  final storage = ref.read(storageServiceProvider);
  final favorites = ref.read(favoriteGamesProvider.notifier);
  final shelves = ref.read(customShelvesProvider.notifier);
  final observedNames = installation.legacyAliasesBySystem.values
      .expand((items) => items.keys)
      .toSet();
  final observedIds = installation.legacyAliasesBySystem.values
      .expand((items) => items.values.map((artifact) => artifact.id.key))
      .toSet();
  final needsLegacyMigration =
      storage.getFavoritesVersion() == 0 && storage.getFavorites().isNotEmpty;
  final games = <String, List<GameItem>>{};
  var cursor = 0;
  while (true) {
    final rows = await database.query('games',
        columns: [
          'id',
          'systemSlug',
          'filename',
          'displayName',
          'url',
          'artifact_key',
          'remote_artifact',
          'provider_config'
        ],
        where: 'id > ?',
        whereArgs: [cursor],
        orderBy: 'id',
        limit: 128);
    if (!active) return;
    if (rows.isEmpty) break;
    for (final row in rows) {
      if (!needsLegacyMigration &&
          !(row['artifact_key'] == null
              ? observedNames.contains(row['filename'])
              : observedIds.contains(row['artifact_key']))) {
        continue;
      }
      games.putIfAbsent(row['systemSlug'] as String, () => []).add(GameItem(
            filename: row['filename'] as String,
            displayName: row['displayName'] as String,
            url: row['url'] as String,
            remoteArtifact: row['remote_artifact'] == null
                ? null
                : RemoteArtifact.fromJson(
                    (jsonDecode(row['remote_artifact'] as String) as Map)
                        .cast<String, dynamic>()),
            providerConfig: row['provider_config'] == null
                ? null
                : ProviderConfig.fromJson(
                    (jsonDecode(row['provider_config'] as String) as Map)
                        .cast<String, dynamic>()),
          ));
    }
    cursor = rows.last['id'] as int;
  }
  final aliases = {
    for (final system in games.entries)
      system.key: GameMergeHelper.verifiedSelectionAliases(system.value,
          installation.legacyAliasesBySystem[system.key] ?? const {})
  };
  final remaining = <String>{
    for (final system in games.entries)
      for (final game in system.value)
        if (game.remoteArtifact == null &&
            !aliases[system.key]!.containsKey(game.filename))
          game.filename
  };
  await favorites
      .migrateIfNeeded(games.values.expand((items) => items).toList());
  if (!active) return;
  await storage.migrateExactSelections(aliases, remainingLegacyKeys: remaining);
  if (!active) return;
  favorites.reloadSelections();
  shelves.reloadSelections();
});

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
  var active = true;
  ref.onDispose(() => active = false);
  final cache = await ref.watch(cachedMetadataArtworkProvider);
  // Drive-backed cards own their exact mounted selection. The old local-only
  // whole-console reader must not compete with them or prefetch the collection.
  if (!active || cache.sharedStore?.cloudManaged == true) return const {};
  ref.watch(gameDbChangedProvider);
  ref.watch(librarySyncServiceProvider.select((s) => s.completedSystems));
  final db = await ref.watch(libraryDbProvider).database;
  await ref.watch(cachedMetadataReadinessProvider.future);
  final query = LibraryQuery(Future.value(db));
  var cursor = 0;
  final result = <String, String?>{};
  while (active) {
    if (cache.sharedStore?.cloudManaged == true) return const {};
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
