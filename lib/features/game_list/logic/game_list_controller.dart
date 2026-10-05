import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../../models/config/system_config.dart';
import '../../../models/config/provider_config.dart';
import '../../../models/game_item.dart';
import '../../../models/library_identity.dart';
import '../../../models/system_model.dart';
import '../../../services/database_service.dart';
import '../../../services/installation_index.dart';
import '../../../services/library_sync_service.dart';
import '../../../services/library_query.dart';
import '../../../services/rom_manager.dart';
import '../../../services/storage_service.dart';
import '../../../services/unified_game_service.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/game_merge_helper.dart';
import '../../../utils/game_metadata.dart';
import 'filter_state.dart';

class GameListState {
  final List<GameItem> allGames;
  final Map<String, List<GameItem>> groupedGames;
  final List<String> allGroups;
  final List<String> filteredGroups;
  final Map<String, bool> installedCache;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final ActiveFilters activeFilters;
  final Map<String, RegionInfo> regionCache;
  final Map<String, List<LanguageInfo>> languageCache;
  final List<FilterOption> availableRegions;
  final List<FilterOption> availableLanguages;
  final Map<String, List<GameItem>> filteredGroupedGames;
  final bool isLocalOnly;
  final bool isOffline;
  final bool queryingDiscovery;
  final LibraryDiscoveryResult? discovery;
  final String? discoveryError;
  final List<String> availableGenres;

  const GameListState({
    this.allGames = const [],
    this.groupedGames = const {},
    this.allGroups = const [],
    this.filteredGroups = const [],
    this.installedCache = const {},
    this.isLoading = true,
    this.error,
    this.searchQuery = '',
    this.activeFilters = const ActiveFilters(),
    this.regionCache = const {},
    this.languageCache = const {},
    this.availableRegions = const [],
    this.availableLanguages = const [],
    this.filteredGroupedGames = const {},
    this.isLocalOnly = false,
    this.isOffline = false,
    this.queryingDiscovery = false,
    this.discovery,
    this.discoveryError,
    this.availableGenres = const [],
  });

  GameListState copyWith({
    List<GameItem>? allGames,
    Map<String, List<GameItem>>? groupedGames,
    List<String>? allGroups,
    List<String>? filteredGroups,
    Map<String, bool>? installedCache,
    bool? isLoading,
    String? error,
    String? searchQuery,
    ActiveFilters? activeFilters,
    Map<String, RegionInfo>? regionCache,
    Map<String, List<LanguageInfo>>? languageCache,
    List<FilterOption>? availableRegions,
    List<FilterOption>? availableLanguages,
    Map<String, List<GameItem>>? filteredGroupedGames,
    bool? isLocalOnly,
    bool? isOffline,
    bool? queryingDiscovery,
    LibraryDiscoveryResult? discovery,
    String? discoveryError,
    List<String>? availableGenres,
    bool clearDiscovery = false,
  }) {
    return GameListState(
      allGames: allGames ?? this.allGames,
      groupedGames: groupedGames ?? this.groupedGames,
      allGroups: allGroups ?? this.allGroups,
      filteredGroups: filteredGroups ?? this.filteredGroups,
      installedCache: installedCache ?? this.installedCache,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      searchQuery: searchQuery ?? this.searchQuery,
      activeFilters: activeFilters ?? this.activeFilters,
      regionCache: regionCache ?? this.regionCache,
      languageCache: languageCache ?? this.languageCache,
      availableRegions: availableRegions ?? this.availableRegions,
      availableLanguages: availableLanguages ?? this.availableLanguages,
      filteredGroupedGames: filteredGroupedGames ?? this.filteredGroupedGames,
      isLocalOnly: isLocalOnly ?? this.isLocalOnly,
      isOffline: isOffline ?? this.isOffline,
      queryingDiscovery: queryingDiscovery ?? this.queryingDiscovery,
      discovery: clearDiscovery ? null : discovery ?? this.discovery,
      discoveryError: discoveryError,
      availableGenres: availableGenres ?? this.availableGenres,
    );
  }
}

class GameListController extends ChangeNotifier {
  final SystemModel system;
  final String targetFolder;
  final SystemConfig systemConfig;
  final UnifiedGameService _unifiedService;
  final DatabaseService _databaseService;
  final StorageService? _storage;
  final Future<void> Function()? _prepareMetadata;
  bool _disposed = false;
  Timer? _thumbnailDebounce;
  int _discoveryGeneration = 0;
  Future<void>? _discoveryWork;
  Future<void>? _genreWork;
  List<String> _discoveryKeys = const [];
  Future<void> get discoverySettled => _discoveryWork ?? Future.value();

  Future<void> loadDiscoveryGenres() => _genreWork ??= _loadDiscoveryGenres();

  Future<void> _loadDiscoveryGenres() async {
    try {
      await _prepareMetadata?.call();
      if (_disposed) return;
      final genres = await LibraryQuery(_databaseService.database)
          .genres(platformIds: {system.id});
      if (_disposed) return;
      _state = _state.copyWith(availableGenres: genres);
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      _state = _state.copyWith(discoveryError: getUserFriendlyError(e));
      notifyListeners();
    } finally {
      _genreWork = null;
    }
  }

  /// Called after games are saved to the database, so the UI layer
  /// can signal count providers to re-query.
  VoidCallback? onGamesSaved;

  GameListState _state = const GameListState();
  GameListState get state => _state;

  @override
  void dispose() {
    _thumbnailDebounce?.cancel();
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Set<String>? _pendingInstalledFilenames;
  List<RemoteArtifact> _installedArtifacts = const [];

  GameListController({
    required this.system,
    required this.targetFolder,
    required this.systemConfig,
    Set<String>? installedFilenames,
    List<RemoteArtifact> installedArtifacts = const [],
    UnifiedGameService? unifiedService,
    DatabaseService? databaseService,
    StorageService? storage,
    Future<void> Function()? prepareMetadata,
  })  : _unifiedService = unifiedService ?? UnifiedGameService(),
        _databaseService = databaseService ?? DatabaseService(),
        _storage = storage,
        _prepareMetadata = prepareMetadata {
    _pendingInstalledFilenames = installedFilenames;
    _installedArtifacts = installedArtifacts;
    loadGames();
  }

  Future<void> loadGames(
      {bool forceRefresh = false, bool silent = false}) async {
    if (silent) {
      _state = _state.copyWith(error: null);
    } else {
      _state = _state.copyWith(isLoading: true, error: null);
      notifyListeners();
    }

    try {
      // Local-only systems always scan filesystem (it IS the source of truth)
      if (systemConfig.providers.isEmpty) {
        final games = await RomManager.scanLocalGames(system, targetFolder);
        _state = _state.copyWith(allGames: games, isLocalOnly: true);
        _groupGames();
        _restoreFilters();
        _resolveInstalledStatus();
        await _databaseService.saveGames(system.id, _state.allGames,
            forceDeleteOrphans: true);
        onGamesSaved?.call();
        refreshDiscovery();
        return;
      }

      // Cache-first: show cached games immediately if available
      if (!forceRefresh && await _databaseService.hasCache(system.id)) {
        var cached = await _databaseService.getGames(system.id);
        if (cached.isNotEmpty) {
          // DB strips auth for security — rehydrate from config
          cached = GameItem.rehydrateAuth(cached, systemConfig.providers);
          _state = _state.copyWith(allGames: cached, isLocalOnly: false);
          _groupGames();
          _restoreFilters();
          _resolveInstalledStatus();
          // Refresh from source in background
          _backgroundRefresh();
          return;
        }
      }

      // No cache or forced refresh — fetch from source
      await _fetchFromSource();
    } catch (e) {
      _state = _state.copyWith(
          error: getUserFriendlyError(e), isLoading: false, isOffline: true);
      notifyListeners();
    }
  }

  Future<void> _fetchFromSource() async {
    final remoteGames = await _unifiedService.fetchGamesForSystem(systemConfig);
    final localGames = await RomManager.scanLocalGames(system, targetFolder);
    final games = GameMergeHelper.merge(remoteGames, localGames, system);
    _state =
        _state.copyWith(allGames: games, isLocalOnly: false, isOffline: false);
    _groupGames();
    _restoreFilters();
    _resolveInstalledStatus();
    await _databaseService.saveGames(system.id, _state.allGames,
        deleteOrphans: true,
        authoritativeDriveSourceIds:
            UnifiedGameService.configuredDriveSourceIds(systemConfig));
    onGamesSaved?.call();
    refreshDiscovery();
  }

  Future<void> _backgroundRefresh() async {
    if (LibrarySyncService.isSyncingSystem(system.id)) return;
    // Skip if recently synced — unless the system has no games yet
    // (newly discovered systems should always sync on first visit).
    final hasGames = _state.allGames.isNotEmpty;
    if (hasGames) {
      if (LibrarySyncService.isFresh(system.id)) return;
      final lastPersistent = _storage?.getLastSyncTime(system.id);
      if (lastPersistent != null &&
          DateTime.now().difference(lastPersistent).inMinutes < 5) {
        return;
      }
    }
    try {
      final remoteGames =
          await _unifiedService.fetchGamesForSystem(systemConfig);
      final localGames = await RomManager.scanLocalGames(system, targetFolder);
      if (_disposed) return;
      final games = GameMergeHelper.merge(remoteGames, localGames, system);

      // Keep queued selections aligned with the current exact artifact version,
      // including size/checksum changes when its provider ID and name persist.
      // Legacy games retain their existing identity/name comparison semantics.
      String comparisonKey(GameItem game) => game.remoteArtifact == null
          ? '${game.identityKey}:${game.filename}'
          : jsonEncode(
              [game.identityKey, game.filename, game.remoteArtifact!.toJson()]);
      final oldFilenames = _state.allGames.map(comparisonKey).toSet();
      final newFilenames = games.map(comparisonKey).toSet();
      if (oldFilenames.length != newFilenames.length ||
          !oldFilenames.containsAll(newFilenames)) {
        _state = _state.copyWith(allGames: games, isLocalOnly: false);
        _groupGames();
        _restoreFilters();
        _resolveInstalledStatus();
      }
      await _databaseService.saveGames(system.id, games,
          deleteOrphans: true,
          authoritativeDriveSourceIds:
              UnifiedGameService.configuredDriveSourceIds(systemConfig));
      _storage?.setLastSyncTime(system.id, DateTime.now());
      onGamesSaved?.call();
      refreshDiscovery();
      if (_state.isOffline) {
        _state = _state.copyWith(isOffline: false);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Background refresh failed for ${system.id}: $e');
      _state = _state.copyWith(isOffline: true);
      notifyListeners();
    }
  }

  void _groupGames() {
    final groupedGames = <String, List<GameItem>>{};
    for (final game in _state.allGames) {
      groupedGames.putIfAbsent(game.groupKey, () => []).add(game);
    }
    final allGroups = groupedGames.keys.toList()
      ..sort((a, b) {
        final comparison = groupedGames[a]!
            .first
            .displayName
            .compareTo(groupedGames[b]!.first.displayName);
        return comparison == 0 ? a.compareTo(b) : comparison;
      });

    // Build region/language caches
    final regionCache = <String, RegionInfo>{};
    final languageCache = <String, List<LanguageInfo>>{};
    for (final game in _state.allGames) {
      regionCache[game.filename] = GameMetadata.extractRegion(game.filename);
      languageCache[game.filename] =
          GameMetadata.extractLanguages(game.filename);
    }

    final options = buildFilterOptions(
      groupedGames: groupedGames,
      regionCache: regionCache,
      languageCache: languageCache,
    );

    _state = _state.copyWith(
      groupedGames: groupedGames,
      allGroups: allGroups,
      filteredGroups: List.from(allGroups),
      filteredGroupedGames: groupedGames,
      regionCache: regionCache,
      languageCache: languageCache,
      availableRegions: options.regions,
      availableLanguages: options.languages,
    );
    notifyListeners();
  }

  void _restoreFilters() {
    final storage = _storage;
    if (storage == null) return;
    final json = storage.getFilters(system.id);
    if (json == null) return;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final restored = ActiveFilters.fromJson(map);
      if (restored.isNotEmpty) {
        _state = _state.copyWith(activeFilters: restored);
        _applyFilters();
      }
    } catch (e) {
      debugPrint(
          'GameListController: filter restore failed for ${system.id}: $e');
    }
  }

  void _saveFilters() {
    final storage = _storage;
    if (storage == null) return;
    final filters = _state.activeFilters;
    if (filters.isEmpty) {
      storage.removeFilters(system.id);
    } else {
      storage.setFilters(system.id, jsonEncode(filters.toJson()));
    }
  }

  /// Uses pre-provided filenames (from [installedFilesProvider]) if available,
  /// otherwise just clears the loading flag and lets the provider listener
  /// call [applyInstalledFilenames] when data arrives.
  void _resolveInstalledStatus() {
    if (_pendingInstalledFilenames != null) {
      applyInstalledFilenames(_pendingInstalledFilenames!,
          installedArtifacts: _installedArtifacts);
    } else {
      _state = _state.copyWith(isLoading: false);
      notifyListeners();
    }
  }

  void filterGames(String query) {
    _state =
        _state.copyWith(searchQuery: GameMetadata.normalizeForSearch(query));
    _applyFilters();
  }

  void resetFilter() {
    _state = _state.copyWith(searchQuery: '');
    _applyFilters();
  }

  void toggleRegionFilter(String region) {
    _state = _state.copyWith(
      activeFilters: _state.activeFilters.toggleRegion(region),
    );
    _applyFilters();
    _saveFilters();
  }

  void toggleLanguageFilter(String language) {
    _state = _state.copyWith(
      activeFilters: _state.activeFilters.toggleLanguage(language),
    );
    _applyFilters();
    _saveFilters();
  }

  void toggleFavoritesFilter() {
    _state = _state.copyWith(
      activeFilters: _state.activeFilters.toggleFavoritesOnly(),
    );
    _applyFilters();
    _saveFilters();
  }

  void toggleLocalFilter() {
    _state = _state.copyWith(
      activeFilters: _state.activeFilters.toggleLocalOnly(),
    );
    _applyFilters();
    _saveFilters();
  }

  void clearFilters() {
    _state = _state.copyWith(activeFilters: _state.activeFilters.clearAll());
    _applyFilters();
    _saveFilters();
  }

  void setTopFilter(int? top) =>
      _changeDiscovery(_state.activeFilters.withTop(top));
  void setDiscoveryFilters(ActiveFilters filters) => _changeDiscovery(filters);
  void toggleTagFilter(String tag) =>
      _changeDiscovery(_state.activeFilters.toggleTag(tag));
  void toggleGenreFilter(String genre) =>
      _changeDiscovery(_state.activeFilters.toggleGenre(genre));
  void toggleTagMatch() =>
      _changeDiscovery(_state.activeFilters.toggleTagMatch());
  void toggleRatingOrder() =>
      _changeDiscovery(_state.activeFilters.toggleRatingOrder());

  void _changeDiscovery(ActiveFilters filters) {
    _state = _state.copyWith(activeFilters: filters);
    _applyFilters();
    _saveFilters();
  }

  /// A committed catalogue/score publication re-evaluates cached membership;
  /// this is not a source refresh or a metadata request.
  void refreshDiscovery() {
    if (!_disposed && _state.activeFilters.hasMetadataFilters) _applyFilters();
  }

  void _applyFilters() {
    _discoveryGeneration++;
    var groups = List<String>.from(_state.allGroups);

    // 1. Search filter
    if (_state.searchQuery.isNotEmpty) {
      groups = groups
          .where((name) => GameMetadata.normalizeForSearch(
                  _state.groupedGames[name]!.first.displayName)
              .contains(_state.searchQuery))
          .toList();
    }

    // 2. Region/Language filter
    if (_state.activeFilters.isNotEmpty) {
      final filteredMap = <String, List<GameItem>>{};
      groups = groups.where((groupName) {
        final variants = _state.groupedGames[groupName];
        if (variants == null) return false;
        final matching =
            variants.where((game) => _matchesFilters(game)).toList();
        if (matching.isEmpty) return false;
        filteredMap[groupName] = matching;
        return true;
      }).toList();
      if (_state.activeFilters.hasMetadataFilters) {
        _discoveryKeys = [
          for (final group in groups)
            for (final game in filteredMap[group]!)
              coverRatingKey(system.id, game.selectionKey)
        ];
        _state = _state.copyWith(
            filteredGroups: const [],
            filteredGroupedGames: const {},
            queryingDiscovery: true,
            clearDiscovery: true);
        _discoveryWork ??= _runDiscovery();
      } else {
        _state = _state.copyWith(
            filteredGroups: groups,
            filteredGroupedGames: filteredMap,
            queryingDiscovery: false,
            clearDiscovery: true);
      }
    } else {
      _state = _state.copyWith(
          filteredGroups: groups,
          filteredGroupedGames: _state.groupedGames,
          queryingDiscovery: false,
          clearDiscovery: true);
    }
    notifyListeners();
  }

  Future<void> _runDiscovery() async {
    try {
      while (!_disposed && _state.activeFilters.hasMetadataFilters) {
        final generation = _discoveryGeneration;
        final filters = _state.activeFilters;
        final keys = _discoveryKeys;
        try {
          await _prepareMetadata?.call();
          if (_disposed) return;
          final result = await LibraryQuery(_databaseService.database).discover(
              filter: LibraryQueryFilter(
                  platformIds: {system.id},
                  tags: filters.selectedTags,
                  genres: filters.selectedGenres,
                  top: filters.top,
                  ratingOrder: filters.ratingOrder,
                  matchAllTags: filters.matchAllTags),
              orderedKeys: keys,
              preserveOrder: true,
              isCurrent: () =>
                  !_disposed && generation == _discoveryGeneration);
          if (_disposed) return;
          if (generation != _discoveryGeneration) continue;
          if (result == null) return;
          final files = {
            for (final g in _state.allGames)
              coverRatingKey(system.id, g.selectionKey): g
          };
          final groups = <String, List<GameItem>>{};
          final installed = Map<String, bool>.of(_state.installedCache);
          for (final entry in result.groups.entries) {
            final variants =
                entry.value.map((k) => files[k]).whereType<GameItem>().toList();
            if (variants.isEmpty) continue;
            groups[entry.key] = variants;
            installed[entry.key] =
                variants.any((g) => installed[g.groupKey] == true);
          }
          _state = _state.copyWith(
              filteredGroups: groups.keys.toList(),
              filteredGroupedGames: groups,
              installedCache: installed,
              discovery: result,
              availableGenres: result.genres,
              queryingDiscovery: false);
          notifyListeners();
          if (generation != _discoveryGeneration) continue;
          return;
        } catch (e) {
          if (_disposed) return;
          if (generation != _discoveryGeneration) continue;
          _state = _state.copyWith(
              queryingDiscovery: false,
              discoveryError: getUserFriendlyError(e),
              clearDiscovery: true);
          notifyListeners();
          if (generation != _discoveryGeneration) continue;
          return;
        }
      }
    } finally {
      _discoveryWork = null;
    }
  }

  bool _matchesFilters(GameItem game) {
    final filters = _state.activeFilters;

    // Region check: OR within regions (null = no metadata → pass through)
    if (filters.selectedRegions.isNotEmpty) {
      final region = _state.regionCache[game.filename];
      if (region != null && !filters.selectedRegions.contains(region.name)) {
        return false;
      }
    }

    // Language check: OR within languages (null/empty = no metadata → pass through)
    if (filters.selectedLanguages.isNotEmpty) {
      final languages = _state.languageCache[game.filename];
      if (languages != null &&
          languages.isNotEmpty &&
          !languages.any((l) => filters.selectedLanguages.contains(l.code))) {
        return false;
      }
    }

    if (filters.favoritesOnly) {
      final isFavorite =
          _storage?.getFavorites().contains(game.selectionKey) ?? false;
      if (!isFavorite) return false;
    }

    if (filters.localOnly) {
      if (_state.installedCache[game.groupKey] != true) {
        return false;
      }
    }

    return true;
  }

  /// Fast path: apply pre-scanned filenames from the central index.
  void applyInstalledFilenames(Set<String> installedFilenames,
      {List<RemoteArtifact> installedArtifacts = const []}) {
    _pendingInstalledFilenames = installedFilenames;
    _installedArtifacts = installedArtifacts;
    final installedCache = <String, bool>{};
    for (final entry in _state.groupedGames.entries) {
      installedCache[entry.key] =
          _isAnyVariantInSet(entry.value, installedFilenames);
    }
    for (final entry in _state.filteredGroupedGames.entries) {
      installedCache[entry.key] =
          _isAnyVariantInSet(entry.value, installedFilenames);
    }
    _state = _state.copyWith(installedCache: installedCache, isLoading: false);
    if (_state.activeFilters.localOnly) {
      _applyFilters();
    } else {
      notifyListeners();
    }
  }

  bool _isAnyVariantInSet(List<GameItem> variants, Set<String> filenames) {
    for (final variant in variants) {
      final artifact = variant.remoteArtifact;
      if (artifact != null) {
        if (_installedArtifacts.any((installed) =>
            InstallationSnapshot.sameContent(installed, artifact))) {
          return true;
        }
        continue;
      }
      if (variant.providerConfig?.type == ProviderType.drive) continue;
      final fn = variant.filename;
      if (filenames.contains(fn)) return true;
      // Check archive→extracted match
      for (final ext in SystemModel.archiveExtensions) {
        if (fn.toLowerCase().endsWith(ext)) {
          final stripped = fn.substring(0, fn.length - ext.length);
          if (filenames.contains(stripped)) return true;
          for (final romExt in system.romExtensions) {
            if (filenames.contains('$stripped$romExt')) return true;
          }
        }
      }
    }
    return false;
  }

  Future<bool> _isAnyVariantInstalled(List<GameItem> variants) async {
    final romManager = RomManager();
    return romManager.isAnyVariantInstalled(variants, system, targetFolder);
  }

  Future<void> updateInstalledStatus(String displayName) async {
    final variants = _state.filteredGroupedGames[displayName] ??
        _state.groupedGames[displayName];
    if (variants == null) return;

    final isInstalled = await _isAnyVariantInstalled(variants);
    final newCache = Map<String, bool>.from(_state.installedCache);
    newCache[displayName] = isInstalled;

    _state = _state.copyWith(installedCache: newCache);
    _applyFilters();
  }

  Future<void> updateCoverUrls(List<GameItem> variants, String url) async {
    final filenames = variants.map((v) => v.filename).toList();
    await _databaseService.batchUpdateCoverUrl(filenames, url);
    // Silent update — cover URL is persistence-only, image is already displayed
    _updateInMemorySilent(filenames, (g) => g.copyWith(cachedCoverUrl: url));
  }

  Future<void> updateThumbnailData(List<GameItem> variants) async {
    final filenames = variants.map((v) => v.filename).toList();
    await _databaseService.batchUpdateThumbnailData(
      filenames,
      hasThumbnail: true,
    );
    _updateInMemorySilent(filenames, (g) => g.copyWith(hasThumbnail: true));
    _scheduleThumbnailNotify();
  }

  void _scheduleThumbnailNotify() {
    _thumbnailDebounce?.cancel();
    _thumbnailDebounce = Timer(const Duration(milliseconds: 100), () {
      notifyListeners();
    });
  }

  void _updateInMemorySilent(
      List<String> filenames, GameItem Function(GameItem) updater) {
    final filenameSet = filenames.toSet();
    final newAllGames = _state.allGames.map((g) {
      return filenameSet.contains(g.filename) ? updater(g) : g;
    }).toList();

    final newGrouped = <String, List<GameItem>>{};
    for (final entry in _state.groupedGames.entries) {
      newGrouped[entry.key] = entry.value.map((g) {
        return filenameSet.contains(g.filename) ? updater(g) : g;
      }).toList();
    }

    final newFilteredGrouped = <String, List<GameItem>>{};
    for (final entry in _state.filteredGroupedGames.entries) {
      newFilteredGrouped[entry.key] = entry.value.map((g) {
        return filenameSet.contains(g.filename) ? updater(g) : g;
      }).toList();
    }

    _state = _state.copyWith(
      allGames: newAllGames,
      groupedGames: newGrouped,
      filteredGroupedGames: newFilteredGrouped,
    );
  }
}
