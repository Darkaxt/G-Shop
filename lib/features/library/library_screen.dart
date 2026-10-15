import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/input.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/animated_background.dart';
import '../../core/util/source_color.dart';
import '../../l10n/app_localizations.dart';
import '../../models/config/app_config.dart';
import '../../models/library_identity.dart';
import '../../models/config/provider_config.dart';
import '../../models/config/source.dart';
import '../../models/custom_shelf.dart';
import '../../models/game_item.dart';
import '../../models/system_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/download_providers.dart';
import '../../providers/installed_files_provider.dart';
import '../../models/ra_models.dart';
import '../../providers/game_providers.dart';
import '../../providers/library_providers.dart';
import '../../services/metadata/effective_overall_rating.dart';
import '../../providers/shelf_providers.dart';
import '../../services/config_bootstrap.dart';
import '../../services/library_query.dart';
import '../../services/source_resolver.dart';
import '../../utils/friendly_error.dart';
import '../../services/input_debouncer.dart';
import '../../services/thumbnail_service.dart';
import '../../utils/game_metadata.dart';
import '../../utils/game_merge_helper.dart';
import '../../utils/image_helper.dart';
import '../game_detail/game_detail_screen.dart';
import '../settings/metadata_settings_screen.dart';
import '../home/widgets/manufacturer_filter.dart';
import '../game_detail/widgets/cover_section.dart';
import '../game_list/logic/filter_state.dart';
import '../game_list/widgets/filter_overlay.dart';
import '../../widgets/base_game_card.dart';
import '../../widgets/console_hud.dart';
import '../../widgets/download_overlay.dart';
import '../../widgets/quick_menu.dart';
import '../../widgets/physical_media_view.dart';
import '../../widgets/selection_aware_item.dart';
import 'shelf_edit_screen.dart';
import 'patch_library_screen.dart';
import 'widgets/library_entry.dart';
import 'widgets/library_dashboard.dart';
import 'widgets/library_tabs.dart';
import 'widgets/reorderable_card_wrapper.dart';
import 'widgets/shelf_picker_dialog.dart';

enum LibrarySortMode { featured, alphabetical, bySystem }

enum ReorderState { none, selecting, grabbed }

class LibraryScreen extends ConsumerStatefulWidget {
  final bool openSearch;
  final String? initialManufacturer;
  final SystemType? initialSystemType;
  const LibraryScreen(
      {super.key,
      this.openSearch = false,
      this.initialManufacturer,
      this.initialSystemType});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with ConsoleScreenMixin, SearchableScreenMixin {
  static const _fixedTabCount = 3;
  int _selectedTab = 0; // 0=All, 1=Installed, 2=Favorites, 3+=Shelves
  String? _selectedConsole;
  String? _manufacturer;
  String? _category;
  SystemType? _systemType;
  final _brandFocus = FocusScopeNode(debugLabel: 'Library brands');
  final _typeFocus = FocusScopeNode(debugLabel: 'Library types');
  List<SystemModel> get _browseSystems {
    final slugs = _visibleGames.map((g) => g.systemSlug).toSet();
    return SystemModel.supportedSystems
        .where((s) => slugs.contains(s.id))
        .toList();
  }

  bool get _hasTypes =>
      availableSystemTypes(_browseSystems, _manufacturer).length > 1;
  bool _matchesBrowse(String slug) {
    if (_manufacturer == null && _systemType == null) return true;
    final system =
        SystemModel.supportedSystems.where((s) => s.id == slug).firstOrNull;
    return system != null &&
        (_manufacturer == null || system.manufacturer == _manufacturer) &&
        (_systemType == null || system.types.contains(_systemType));
  }

  Iterable<LibraryEntry> get _browseGames =>
      _visibleGames.where((g) => _matchesBrowse(g.systemSlug));
  bool _globalDiscoveryRequested = false;
  bool _consoleNavigation = false;
  bool _categoryNavigation = false;
  int _dashboardColumns = 1;
  List<LibraryConsoleSummary> _consoleSummaries = const [];
  bool get _isDashboard =>
      _selectedConsole == null &&
      _selectedTab == 0 &&
      _searchQuery.isEmpty &&
      !_globalDiscoveryRequested;
  int get _visibleCount =>
      _isDashboard ? _consoleSummaries.length : _filteredGames.length;
  Iterable<LibraryEntry> get _scopedGames => _selectedConsole == null
      ? _browseGames
      : _browseGames.where((g) => g.systemSlug == _selectedConsole);
  Set<String> get _rankingPlatforms => _selectedConsole == null
      ? (_manufacturer == null && _systemType == null
          ? _filters.selectedPlatforms
          : systemsForManufacturer(_browseSystems, _manufacturer,
                  type: _systemType)
              .map((s) => s.id)
              .where((id) =>
                  _filters.selectedPlatforms.isEmpty ||
                  _filters.selectedPlatforms.contains(id))
              .toSet())
      : {_selectedConsole!};
  LibrarySortMode _sortMode = LibrarySortMode.featured;
  bool get _needsDiscovery =>
      _category != null ||
      _filters.hasMetadataFilters ||
      (!_isShelfTab && _sortMode == LibrarySortMode.featured);
  List<CustomShelf> _shelves = [];

  // Reorder mode
  ReorderState _reorderState = ReorderState.none;
  int _grabbedIndex = -1;
  int? _reorderClaimToken;
  final ValueNotifier<int> _selectedIndexNotifier = ValueNotifier(0);
  int get _currentIndex => _selectedIndexNotifier.value;
  set _currentIndex(int v) {
    _selectedIndexNotifier.value = v;
    _focusManager.setSelectedIndex(v);
  }

  late int _columns;
  String _searchQuery = '';
  bool _isLoading = true;

  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _scrollSuppression = ValueNotifier(false);
  final Map<int, GlobalKey> _itemKeys = {};

  late InputDebouncer _debouncer;
  late final FocusSyncManager _focusManager;

  ProviderSubscription? _installedFilesSubscription;
  ProviderSubscription? _metadataSubscription;
  ProviderSubscription? _catalogueSubscription;
  ProviderSubscription? _selectionSubscription;
  Future<void>? _dataWork;
  bool _reloadData = false;
  bool _loadedOnce = false;
  ActiveFilters _filters = const ActiveFilters();
  bool _isFiltering = false;
  bool _queryingDiscovery = false;
  int _discoveryGeneration = 0;
  Future<void>? _discoveryWork;
  Future<void>? _genreWork;
  Future<void> _filterSave = Future.value();
  List<LibraryEntry> _discoveryEntries = const [];
  LibraryDiscoveryResult? _discovery;
  String? _discoveryError;
  List<String> _availableGenres = const [];
  Map<String, List<LibraryEntry>> _discoveryVariants = const {};
  Map<String, String> _discoveryGroups = const {};
  String? _focusedKey, _focusedGroup;

  String get _baseFilterContext => _isShelfTab
      ? 'library:shelf:${_activeShelf?.id}'
      : 'library:${['all', 'installed', 'favorites'][_selectedTab]}';
  String get _filterContext => _selectedConsole == null
      ? _baseFilterContext
      : '$_baseFilterContext:console:$_selectedConsole';

  void _restoreFilters() {
    final storage = ref.read(storageServiceProvider);
    final saved = storage.getFilters(_filterContext);
    try {
      _filters = saved == null
          ? const ActiveFilters()
          : ActiveFilters.fromJson(jsonDecode(saved) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Library filters could not be restored: $e');
      _filters = const ActiveFilters();
    }
  }

  void _changeFilters(ActiveFilters value) {
    _filters = value;
    _globalDiscoveryRequested = value.isNotEmpty;
    final key = _filterContext;
    final encoded = jsonEncode(value.toJson());
    final storage = ref.read(storageServiceProvider);
    _filterSave = _filterSave
        .then((_) => storage.setFilters(key, encoded))
        .catchError((Object e) {
      if (mounted) setState(() => _discoveryError = getUserFriendlyError(e));
    });
    _applyFilters();
  }

  void _openFilter() {
    closeQuickMenu();
    setState(() => _isFiltering = true);
    if (_isDashboard && _filters.isNotEmpty) {
      _globalDiscoveryRequested = true;
      _applyFilters();
    }
    _genreWork ??= _loadGenres();
  }

  Future<void> _loadGenres() async {
    try {
      await ref.read(cachedMetadataReadinessProvider.future);
      if (!mounted) return;
      final genres =
          await LibraryQuery(ref.read(libraryDbProvider).database).genres();
      if (mounted) setState(() => _availableGenres = genres);
    } catch (e) {
      if (mounted) setState(() => _discoveryError = getUserFriendlyError(e));
    } finally {
      _genreWork = null;
    }
  }

  void _closeFilter() {
    setState(() => _isFiltering = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) requestScreenFocus();
    });
  }

  Widget _buildFilter() {
    final l = L.of(context);
    final platforms = _scopedGames.map((g) => g.systemSlug).toSet().toList()
      ..sort();
    final labels = {
      for (final slug in platforms)
        slug: SystemModel.supportedSystems
                .where((s) => s.id == slug)
                .firstOrNull
                ?.name ??
            slug
    };
    final scope = _rankingPlatforms.isEmpty
        ? l.filter_allScope
        : '${l.filter_scope}: ${_rankingPlatforms.map((s) => labels[s] ?? s).join(', ')}\n${l.filter_oneLimit}';
    final coverage = _discovery;
    final status = _queryingDiscovery
        ? l.filter_querying
        : _discoveryError ??
            (coverage == null
                ? null
                : '${l.filter_coverage(coverage.rankedGames, coverage.collectionGames, coverage.totalMatches)}'
                    '${coverage.provisional ? ' · ${l.filter_provisional}' : ''}');
    return DialogFocusScope(
        isVisible: _isFiltering,
        onClose: _closeFilter,
        child: FilterOverlay(
            accentColor: Colors.cyanAccent,
            availableRegions: const [],
            availableLanguages: const [],
            selectedRegions: const {},
            selectedLanguages: const {},
            favoritesOnly: _filters.favoritesOnly,
            localOnly: _filters.localOnly,
            isLocalSystem: false,
            onToggleRegion: (_) {},
            onToggleLanguage: (_) {},
            onToggleFavorites: () =>
                _changeFilters(_filters.toggleFavoritesOnly()),
            onToggleLocal: () => _changeFilters(_filters.toggleLocalOnly()),
            onClearAll: () => _changeFilters(_filters.clearAll()),
            onClose: _closeFilter,
            discoveryFilters: _filters,
            onDiscoveryChanged: _changeFilters,
            availableGenres: _availableGenres,
            availablePlatforms: _selectedConsole == null ? labels : const {},
            discoveryScope: scope,
            discoveryStatus: status));
  }

  // Raw data from DB
  List<LibraryEntry> _allGames = [];
  List<LibraryEntry> _visibleGames = [];
  InstalledFilesState _installationState = InstalledFilesState();
  Set<String> get _installedFiles => _installationState.all;
  Set<String> _favoriteIds = {};
  // Filtered/sorted view
  List<LibraryEntry> _filteredGames = [];
  // RA match data keyed by filename
  Map<String, RaMatchResult> _raMatches = {};
  // Pre-computed cover URLs per filtered index
  Map<int, List<String>> _coverUrlCache = {};
  Map<String, EffectiveOverallRating?> _ratings = const {};
  Map<String, String?> _metadataCovers = const {};
  bool _showRatings = true;

  int get _totalTabCount => _fixedTabCount + _shelves.length;

  bool get _isShelfTab => _selectedTab >= _fixedTabCount;

  CustomShelf? get _activeShelf {
    if (!_isShelfTab) return null;
    final idx = _selectedTab - _fixedTabCount;
    if (idx < 0 || idx >= _shelves.length) return null;
    return _shelves[idx];
  }

  @override
  String get routeId => 'library';

  @override
  Color get searchAccentColor => Colors.cyanAccent;

  @override
  String get searchHintText => L.of(context).library_searchHint;

  @override
  void onSearchQueryChanged(String query) {
    _searchQuery = query;
    _currentIndex = 0;
    _applyFilters();
  }

  @override
  void onSearchReset() {
    _searchQuery = '';
    _applyFilters();
  }

  @override
  void onSearchSelectionReset() => _currentIndex = 0;

  // L1/R1 own the current tab row; L2/R2 remain aliases and PageUp/Down zoom.

  @override
  Map<Type, Action<Intent>> get screenActions {
    return {
      NavigateIntent: OverlayGuardedAction<NavigateIntent>(
        ref,
        onInvoke: (intent) {
          _navigateGrid(intent.direction);
          return null;
        },
        isEnabledOverride: _reorderOrSearchOrNone,
      ),
      AdjustColumnsIntent: OverlayGuardedAction<AdjustColumnsIntent>(
        ref,
        onInvoke: (intent) {
          _adjustColumns(intent.increase);
          return null;
        },
        isEnabledOverride: searchOrNone,
      ),
      ConfirmIntent: OverlayGuardedAction<ConfirmIntent>(
        ref,
        onInvoke: (_) {
          _handleConfirm();
          return null;
        },
        isEnabledOverride: _reorderOrSearchOrNone,
      ),
      BackIntent: OverlayGuardedAction<BackIntent>(
        ref,
        onInvoke: (_) {
          _handleBack();
          return null;
        },
        isEnabledOverride: _reorderOrSearchOrNone,
      ),
      SearchIntent: CallbackAction<SearchIntent>(
        onInvoke: (_) {
          toggleSearch();
          return null;
        },
      ),
      TabLeftIntent: TabLeftAction(ref, onTabLeft: _prevTab),
      TabRightIntent: TabRightAction(ref, onTabRight: _nextTab),
      FavoriteIntent: OverlayGuardedAction<FavoriteIntent>(
        ref,
        onInvoke: (_) {
          _handleFavorite();
          return null;
        },
      ),
      ToggleOverlayIntent: ToggleOverlayAction(ref, onToggle: toggleQuickMenu),
    };
  }

  bool _reorderOrSearchOrNone(dynamic priority) {
    if (_reorderState != ReorderState.none) return true;
    return searchOrNone(priority);
  }

  @override
  void initState() {
    super.initState();
    _manufacturer = widget.initialManufacturer;
    _systemType = widget.initialSystemType;
    _columns = ref.read(gridColumnsProvider('library'));
    _debouncer = ref.read(inputDebouncerProvider);
    _shelves = ref.read(customShelvesProvider);
    final savedConsole = ref.read(storageServiceProvider).getLibraryConsole();
    _selectedConsole =
        savedConsole == null || savedConsole.isEmpty ? null : savedConsole;
    _restoreFilters();

    _focusManager = FocusSyncManager(
      scrollController: _scrollController,
      getCrossAxisCount: () => _columns,
      getItemCount: () => _visibleCount,
      getGridRatio: () => 1.0,
      onSelectionChanged: (index) => _selectedIndexNotifier.value = index,
      scrollSuppression: _scrollSuppression,
    );

    initSearch();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A read of .future is not a subscription. Keep migration live while this
      // screen awaits it so catalogue/installation invalidation rebuilds the
      // provider and completes the pending future instead of stranding loading.
      _selectionSubscription =
          ref.listenManual(selectionContinuityProvider, (_, __) {});
      _loadData();
      _installedFilesSubscription =
          ref.listenManual(installedFilesProvider, (prev, next) {
        if (!mounted) return;
        final data = next.value;
        if (data != null && !identical(data, _installationState)) {
          _installationState = data;
          unawaited(_loadData());
        }
      });
      _metadataSubscription = ref.listenManual(gameDbChangedProvider, (_, __) {
        if (mounted) unawaited(_loadData());
      });
      _catalogueSubscription = ref.listenManual(
          librarySyncServiceProvider.select((s) => s.completedSystems),
          (_, __) {
        if (mounted) unawaited(_loadData());
      });
    });
  }

  @override
  void dispose() {
    _exitReorderMode();
    final selectedIndex = _currentIndex;
    Future.microtask(() {
      focusStateManager.saveFocusState(routeId, selectedIndex: selectedIndex);
    });
    _installedFilesSubscription?.close();
    _metadataSubscription?.close();
    _catalogueSubscription?.close();
    _selectionSubscription?.close();
    _discoveryGeneration++;
    _debouncer.stopHold();
    _focusManager.dispose();
    _scrollController.dispose();
    _brandFocus.dispose();
    _typeFocus.dispose();
    disposeSearch();
    _scrollSuppression.dispose();
    _selectedIndexNotifier.dispose();
    super.dispose();
  }

  Future<void> _refreshInstalledFiles() async {
    final installed = await ref.read(installedFilesProvider.future);
    if (mounted) {
      setState(() => _installationState = installed);
    }
  }

  Future<void> _loadData() {
    _reloadData = true;
    return _dataWork ??= _reloadCollection();
  }

  Future<void> _reloadCollection() async {
    try {
      while (mounted && _reloadData) {
        _reloadData = false;
        _discoveryGeneration++;
        await _loadDataOnce();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _discoveryError = getUserFriendlyError(e);
        });
      }
    } finally {
      _dataWork = null;
    }
  }

  Future<void> _loadDataOnce() async {
    setState(() => _isLoading = true);

    final db = ref.read(libraryDbProvider);

    // Load all games from DB
    final rawGames = await db.getAllGames();

    // Use centralized installed-files index (provider-driven)
    final installedData = ref.read(installedFilesProvider).value;
    if (installedData != null) {
      _installationState = installedData;
    } else {
      // Await the same verified index; never bypass it with a filename scan.
      await _refreshInstalledFiles();
    }

    final entries = <LibraryEntry>[];
    for (final row in rawGames) {
      final systemSlug = row['systemSlug'] as String;

      ProviderConfig? providerConfig;
      final pcJson = row['provider_config'] as String?;
      if (pcJson != null) {
        try {
          providerConfig = ProviderConfig.fromJson(
              jsonDecode(pcJson) as Map<String, dynamic>);
        } catch (e) {
          debugPrint('LibraryScreen: provider config parse failed: $e');
        }
      }

      final fname = row['filename'] as String;
      entries.add(LibraryEntry(
        filename: fname,
        displayName: GameMetadata.cleanTitle(fname),
        cardTitle: GameMetadata.fileTitle(fname),
        url: row['url'] as String,
        coverUrl: row['cover_url'] as String?,
        systemSlug: systemSlug,
        providerConfig: providerConfig,
        remoteArtifact: row['remote_artifact'] == null
            ? null
            : RemoteArtifact.fromJson(
                jsonDecode(row['remote_artifact'] as String)
                    as Map<String, dynamic>),
        hasThumbnail: (row['has_thumbnail'] as int?) == 1,
      ));
    }

    if (!mounted) return;

    // Trigger deferred migration from displayName → filename favorites
    final allGameItems = entries
        .map((e) => GameItem(
              filename: e.filename,
              displayName: e.displayName,
              url: e.url,
              remoteArtifact: e.remoteArtifact,
            ))
        .toList();
    await ref
        .read(favoriteGamesProvider.notifier)
        .migrateIfNeeded(allGameItems);
    await ref.read(selectionContinuityProvider.future);
    if (!mounted) return;
    _shelves = ref.read(customShelvesProvider);
    final migratedFavorites = ref.read(favoriteGamesProvider).toSet();

    // Load RA matches for all systems represented in the library
    final raMatches = <String, RaMatchResult>{};
    final storage = ref.read(storageServiceProvider);
    if (storage.getRaEnabled()) {
      final systemSlugs = entries.map((e) => e.systemSlug).toSet();
      final db = ref.read(libraryDbProvider);
      for (final slug in systemSlugs) {
        final matches = await db.getRaMatchesForSystem(slug);
        raMatches.addAll(matches);
      }
    }

    if (!mounted) return;

    setState(() {
      _allGames = entries;
      if (_selectedConsole != null &&
          !entries.any((g) => g.systemSlug == _selectedConsole)) {
        _selectedConsole = null;
        _restoreFilters();
      }
      _favoriteIds = migratedFavorites;
      _raMatches = raMatches;
      _isLoading = false;
    });

    final initialLoad = !_loadedOnce;
    _loadedOnce = true;
    _applyFilters();

    // Route entry restores focus once. Metadata/catalogue reloads retain the
    // current game, not the index captured when a previous route was closed.
    final saved = getSavedFocusState();
    if (initialLoad &&
        !_queryingDiscovery &&
        _filteredGames.isNotEmpty &&
        saved?.selectedIndex != null &&
        saved!.selectedIndex! > 0) {
      _currentIndex = saved.selectedIndex!.clamp(0, _filteredGames.length - 1);
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelected();
      });
    }

    if (initialLoad && widget.openSearch) {
      openSearch();
    }
    debugPrint('Library collection loaded: games=${_visibleGames.length} '
        'console=${_selectedConsole ?? "dashboard"}');
  }

  void _applyFilters() {
    final bySystem = <String, Map<GameItem, LibraryEntry>>{};
    for (final entry in _allGames) {
      final item = GameItem(
          filename: entry.filename,
          displayName: entry.displayName,
          url: entry.url,
          providerConfig: entry.providerConfig,
          remoteArtifact: entry.remoteArtifact);
      bySystem.putIfAbsent(entry.systemSlug, () => {})[item] = entry;
    }
    _visibleGames = [
      for (final system in bySystem.entries)
        for (final item in GameMergeHelper.coalesceVerifiedCopies(
            system.value.keys.toList(),
            _installationState.legacyAliasesBySystem[system.key] ?? const {}))
          system.value[item]!,
    ];
    if (_manufacturer != null &&
        !_browseSystems.any((s) => s.manufacturer == _manufacturer)) {
      _manufacturer = null;
    }
    final types = availableSystemTypes(_browseSystems, _manufacturer);
    if (types.length <= 1 || !types.contains(_systemType)) _systemType = null;
    _consoleSummaries = LibraryConsoleSummary.fromEntries(_browseGames.toList(),
        isInstalled: _isGameInstalled,
        favorites: _favoriteIds,
        installation: _installationState);
    if (_selectedConsole != null &&
        !_consoleSummaries.any((s) => s.slug == _selectedConsole)) {
      _selectedConsole = _consoleSummaries.firstOrNull?.slug;
      _restoreFilters();
    }
    if (!_queryingDiscovery && _currentIndex < _filteredGames.length) {
      final entry = _filteredGames[_currentIndex];
      _focusedKey = coverRatingKey(entry.systemSlug, entry.selectionKey);
      _focusedGroup = _discoveryGroups[_focusedKey];
    }
    _discoveryGeneration++;
    List<LibraryEntry> games;
    bool isManualSort = false;
    ShelfSortMode? shelfSortMode;

    if (_isShelfTab) {
      final resolved = _resolveShelfGames();
      games = resolved.games;
      isManualSort = resolved.isManualSort;
      shelfSortMode = resolved.shelfSortMode;
    } else {
      games = List<LibraryEntry>.from(_scopedGames);
      // Tab filter
      switch (_selectedTab) {
        case 1: // Installed
          games = games.where(_isGameInstalled).toList();
          if (!_filters.hasMetadataFilters) {
            games = _deduplicateInstalled(games);
          }
        case 2: // Favorites
          games = games
              .where((g) => _favoriteIds.contains(g.selectionKey))
              .toList();
      }
    }

    if (_selectedConsole != null) {
      games = games.where((g) => g.systemSlug == _selectedConsole).toList();
    }
    if (_isDashboard) {
      _discoveryVariants = const {};
      _discoveryGroups = const {};
      _discovery = null;
      _discoveryError = null;
      _queryingDiscovery = false;
      _publishGames([]);
      return;
    }

    if (_filters.favoritesOnly) {
      games =
          games.where((g) => _favoriteIds.contains(g.selectionKey)).toList();
    }
    if (_filters.localOnly) {
      games = games.where(_isGameInstalled).toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final query = GameMetadata.normalizeForSearch(_searchQuery);
      games = games
          .where((g) =>
              GameMetadata.normalizeForSearch(g.displayName).contains(query))
          .toList();
    }

    // Sort (skip for manual-sort shelves)
    if (!isManualSort) {
      final effectiveSort = shelfSortMode != null
          ? (shelfSortMode == ShelfSortMode.bySystem
              ? LibrarySortMode.bySystem
              : LibrarySortMode.alphabetical)
          : _sortMode;
      switch (effectiveSort) {
        case LibrarySortMode.featured:
        case LibrarySortMode.alphabetical:
          games.sort((a, b) => a.displayName
              .toLowerCase()
              .compareTo(b.displayName.toLowerCase()));
        case LibrarySortMode.bySystem:
          games.sort((a, b) {
            final cmp = a.systemSlug.compareTo(b.systemSlug);
            if (cmp != 0) return cmp;
            return a.displayName
                .toLowerCase()
                .compareTo(b.displayName.toLowerCase());
          });
      }
    }

    if ((_manufacturer != null || _systemType != null) &&
        _selectedConsole == null &&
        _filters.selectedPlatforms.isNotEmpty &&
        _rankingPlatforms.isEmpty) {
      games = [];
    }
    if (_needsDiscovery) {
      _discoveryEntries = games;
      setState(() {
        _queryingDiscovery = true;
        _discoveryError = null;
        _discovery = null;
        _filteredGames = [];
        _coverUrlCache = {};
        _updateItemKeys();
      });
      _discoveryWork ??= _runDiscovery();
      return;
    }
    _discoveryVariants = const {};
    _discoveryGroups = const {};
    _discovery = null;
    _discoveryError = null;
    _queryingDiscovery = false;
    _publishGames(games);
  }

  void _publishGames(List<LibraryEntry> games) {
    setState(() {
      _filteredGames = games;
      _rebuildCoverUrlCache();
      _updateItemKeys();
      final identityIndex = games.indexWhere((g) {
        final key = coverRatingKey(g.systemSlug, g.selectionKey);
        return _focusedGroup != null &&
                _discoveryGroups[key] == _focusedGroup ||
            key == _focusedKey;
      });
      if (identityIndex >= 0) {
        _currentIndex = identityIndex;
      } else if (_currentIndex >= _visibleCount) {
        _currentIndex = _visibleCount == 0 ? 0 : _visibleCount - 1;
      }
    });
  }

  Future<void> _runDiscovery() async {
    try {
      while (mounted && _needsDiscovery && !_isDashboard) {
        final generation = _discoveryGeneration;
        final filters = _filters;
        final entries = _discoveryEntries;
        try {
          if (entries.isEmpty) {
            _discovery = LibraryDiscoveryResult(
                groups: const {},
                genres: const [],
                collectionGames: 0,
                rankedGames: 0,
                totalMatches: 0);
            _queryingDiscovery = false;
            _publishGames([]);
            return;
          }
          await ref.read(cachedMetadataReadinessProvider.future);
          if (!mounted) return;
          final result =
              await LibraryQuery(ref.read(libraryDbProvider).database).discover(
                  filter: LibraryQueryFilter(
                      platformIds: _rankingPlatforms,
                      category: _category,
                      tags: filters.selectedTags,
                      genres: filters.selectedGenres,
                      top: filters.top,
                      featuredTop:
                          !_isShelfTab && _sortMode == LibrarySortMode.featured
                              ? 100
                              : null,
                      ratingOrder: filters.ratingOrder,
                      matchAllTags: filters.matchAllTags),
                  orderedKeys: [
                    for (final g in entries)
                      coverRatingKey(g.systemSlug, g.selectionKey)
                  ],
                  preserveOrder: true,
                  isCurrent: () =>
                      mounted && generation == _discoveryGeneration);
          if (!mounted) return;
          if (generation != _discoveryGeneration) continue;
          if (result == null) return;
          final lookup = {
            for (final g in entries)
              coverRatingKey(g.systemSlug, g.selectionKey): g
          };
          final variants = <String, List<LibraryEntry>>{};
          final groups = <String, String>{};
          final visible = <LibraryEntry>[];
          for (final group in result.groups.entries) {
            final editions = [
              for (final key in group.value)
                if (lookup[key] != null) lookup[key]!
            ];
            if (editions.isEmpty) continue;
            final first = editions.first;
            final key = coverRatingKey(first.systemSlug, first.selectionKey);
            visible.add(first);
            variants[key] = List.unmodifiable(editions);
            for (final key in group.value) {
              groups[key] = group.key;
            }
          }
          if (!filters.hasMetadataFilters && _category == null) {
            // Browsing order must not hide files whose identity is unresolved.
            // They cannot be ranked, but remain visible in the A-Z remainder.
            for (final entry in entries) {
              if (!groups.containsKey(
                  coverRatingKey(entry.systemSlug, entry.selectionKey))) {
                visible.add(entry);
              }
            }
            visible.sort((a, b) {
              int? rank(LibraryEntry entry) => result.featuredRanks[
                  groups[coverRatingKey(entry.systemSlug, entry.selectionKey)]];
              final ar = rank(a), br = rank(b);
              if (ar != null || br != null) {
                if (ar == null) return 1;
                if (br == null) return -1;
                final order = ar.compareTo(br);
                if (order != 0) return order;
              }
              final title = a.displayName
                  .toLowerCase()
                  .compareTo(b.displayName.toLowerCase());
              return title != 0
                  ? title
                  : coverRatingKey(a.systemSlug, a.selectionKey)
                      .compareTo(coverRatingKey(b.systemSlug, b.selectionKey));
            });
          }
          _discoveryVariants = variants;
          _discoveryGroups = groups;
          _discovery = result;
          _availableGenres = result.genres;
          _queryingDiscovery = false;
          _publishGames(visible);
          if (generation != _discoveryGeneration) continue;
          return;
        } catch (e) {
          if (!mounted) return;
          if (generation != _discoveryGeneration) continue;
          setState(() {
            _queryingDiscovery = false;
            _discoveryError = getUserFriendlyError(e);
          });
          return;
        }
      }
    } finally {
      _discoveryWork = null;
    }
  }

  ({List<LibraryEntry> games, bool isManualSort, ShelfSortMode? shelfSortMode})
      _resolveShelfGames() {
    final shelf = _activeShelf;
    if (shelf == null) {
      return (
        games: <LibraryEntry>[],
        isManualSort: false,
        shelfSortMode: null
      );
    }

    final allGameRecords = _visibleGames
        .map((g) => (
              filename: g.selectionKey,
              displayName: g.displayName,
              systemSlug: g.systemSlug,
            ))
        .toList();

    final filenames = shelf.resolveFilenames(allGameRecords);
    final lookup = <String, LibraryEntry>{};
    for (final g in _visibleGames) {
      lookup[g.selectionKey] = g;
    }

    final games = <LibraryEntry>[];
    for (final f in filenames) {
      final entry = lookup[f];
      if (entry != null) games.add(entry);
    }

    return (
      games: games,
      isManualSort: shelf.sortMode == ShelfSortMode.manual,
      shelfSortMode: shelf.sortMode
    );
  }

  void _updateItemKeys() {
    final count = _visibleCount;
    if (_itemKeys.length == count) return;
    _itemKeys.clear();
    for (int i = 0; i < count; i++) {
      _itemKeys[i] = GlobalKey();
    }
  }

  void _rebuildCoverUrlCache() {
    _coverUrlCache = {};
    for (int i = 0; i < _filteredGames.length; i++) {
      final entry = _filteredGames[i];
      final systemModel = SystemModel.supportedSystems
          .where((s) => s.id == entry.systemSlug)
          .firstOrNull;
      if (systemModel != null) {
        _coverUrlCache[i] =
            ImageHelper.getCoverUrlsForSingle(systemModel, entry.filename);
      }
    }
  }

  // --- Tab Navigation ---

  void _nextTab() {
    if (_cycleBrowseFilter(1)) return;
    if (_categoryNavigation) {
      _cycleCategory(1);
      return;
    }
    if (_consoleNavigation) {
      _navigateGrid(GridDirection.right);
      return;
    }
    if (_reorderState != ReorderState.none) return;
    ref.read(feedbackServiceProvider).tick();
    _shelves = ref.read(customShelvesProvider);
    setState(() {
      _selectedTab = (_selectedTab + 1) % _totalTabCount;
      _currentIndex = 0;
    });
    _focusedKey = _focusedGroup = null;
    _restoreFilters();
    _applyFilters();
    _scrollToTop();
  }

  void _prevTab() {
    if (_cycleBrowseFilter(-1)) return;
    if (_categoryNavigation) {
      _cycleCategory(-1);
      return;
    }
    if (_consoleNavigation) {
      _navigateGrid(GridDirection.left);
      return;
    }
    if (_reorderState != ReorderState.none) return;
    ref.read(feedbackServiceProvider).tick();
    _shelves = ref.read(customShelvesProvider);
    setState(() {
      _selectedTab = (_selectedTab - 1 + _totalTabCount) % _totalTabCount;
      _currentIndex = 0;
    });
    _focusedKey = _focusedGroup = null;
    _restoreFilters();
    _applyFilters();
    _scrollToTop();
  }

  void _selectTab(int index) {
    if (index == _selectedTab) return;
    if (_reorderState != ReorderState.none) return;
    ref.read(feedbackServiceProvider).tick();
    _shelves = ref.read(customShelvesProvider);
    setState(() {
      _selectedTab = index;
      _currentIndex = 0;
    });
    _focusedKey = _focusedGroup = null;
    _restoreFilters();
    _applyFilters();
    _scrollToTop();
  }

  void _cycleSortMode() {
    ref.read(feedbackServiceProvider).tick();

    if (_isShelfTab) {
      final shelf = _activeShelf;
      if (shelf == null) return;
      final next = switch (shelf.sortMode) {
        ShelfSortMode.alphabetical => ShelfSortMode.bySystem,
        ShelfSortMode.bySystem => ShelfSortMode.manual,
        ShelfSortMode.manual => ShelfSortMode.alphabetical,
      };
      ref.read(customShelvesProvider.notifier).updateShelf(
            shelf.id,
            shelf.copyWith(sortMode: next),
          );
      _shelves = ref.read(customShelvesProvider);
    } else {
      _sortMode = switch (_sortMode) {
        LibrarySortMode.featured => LibrarySortMode.alphabetical,
        LibrarySortMode.alphabetical => LibrarySortMode.bySystem,
        LibrarySortMode.bySystem => LibrarySortMode.featured,
      };
    }

    setState(() => _currentIndex = 0);
    _applyFilters();
    _scrollToTop();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  // --- Grid Navigation ---

  void _selectConsole(String? slug) {
    if (_reorderState != ReorderState.none) return;
    _debouncer.stopHold();
    setState(() {
      _selectedConsole = slug;
      _categoryNavigation = false;
      _globalDiscoveryRequested = false;
      if (slug == null) _selectedTab = 0;
      _currentIndex = 0;
      _focusedKey = _focusedGroup = null;
    });
    final storage = ref.read(storageServiceProvider);
    _filterSave = _filterSave
        .then((_) => storage.setLibraryConsole(slug))
        .catchError((Object e) {
      if (mounted) setState(() => _discoveryError = getUserFriendlyError(e));
    });
    _restoreFilters();
    _applyFilters();
    _scrollToTop();
    requestScreenFocus();
  }

  void _setBrowseScope(String? brand, SystemType? type) {
    _manufacturer = brand;
    final types = availableSystemTypes(_browseSystems, brand);
    _systemType = types.length > 1 && types.contains(type) ? type : null;
    final selected = _selectedConsole;
    final systems =
        systemsForManufacturer(_browseSystems, brand, type: _systemType);
    _selectConsole(selected == null || _matchesBrowse(selected)
        ? selected
        : systems.firstOrNull?.id);
  }

  bool _cycleBrowseFilter(int delta) {
    if (_typeFocus.hasFocus && _hasTypes) {
      final values = <SystemType?>[
        null,
        ...SystemType.values
            .where(availableSystemTypes(_browseSystems, _manufacturer).contains)
      ];
      _setBrowseScope(_manufacturer,
          values[(values.indexOf(_systemType) + delta) % values.length]);
      _typeFocus.requestFocus();
      _typeFocus.nextFocus();
      return true;
    }
    if (_brandFocus.hasFocus) {
      final brands = _browseSystems.map((s) => s.manufacturer).toSet().toList()
        ..sort();
      final values = <String?>[null, ...brands];
      _setBrowseScope(
          values[(values.indexOf(_manufacturer) + delta) % values.length],
          _systemType);
      _brandFocus.requestFocus();
      _brandFocus.nextFocus();
      return true;
    }
    return false;
  }

  void _selectCategory(String? category) {
    if (category == 'patches') {
      unawaited(_openPatchLibrary());
      return;
    }
    _category = category;
    _currentIndex = 0;
    _focusedKey = _focusedGroup = null;
    _applyFilters();
    _scrollToTop();
  }

  void _cycleCategory(int delta) {
    const values = [null, 'commercial', 'hacks', 'patches'];
    _selectCategory(
        values[(values.indexOf(_category) + delta) % values.length]);
  }

  Future<void> _openPatchLibrary() async {
    final console = _selectedConsole;
    if (console == null) return;
    final config =
        ref.read(bootstrappedConfigProvider).value ?? AppConfig.empty;
    final system =
        SystemModel.supportedSystems.where((s) => s.id == console).firstOrNull;
    if (system == null) return;
    final mapping = ConfigBootstrap.configForSystem(config, system);
    if (mapping == null || mapping.targetFolder.isEmpty) {
      setState(() => _discoveryError =
          'Set up this console’s game folder before opening Patches.');
      return;
    }
    suspendSearchOverlay();
    try {
      await Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => PatchLibraryScreen(
                  system: system,
                  targetFolder: mapping.targetFolder,
                  providers:
                      SourceResolver.providersFor(mapping, config.sources),
                  collection: _visibleGames
                      .where((entry) => entry.systemSlug == console)
                      .map((entry) => GameItem(
                          filename: entry.filename,
                          displayName: entry.displayName,
                          url: entry.url,
                          cachedCoverUrl: entry.coverUrl,
                          providerConfig: entry.providerConfig,
                          remoteArtifact: entry.remoteArtifact))
                      .toList())));
    } finally {
      if (mounted) {
        resumeSearchOverlay();
        await _loadData();
      }
    }
  }

  void _navigateGrid(GridDirection direction) {
    if (_categoryNavigation) {
      if (direction == GridDirection.left || direction == GridDirection.right) {
        _cycleCategory(direction == GridDirection.left ? -1 : 1);
      } else {
        setState(() {
          _categoryNavigation = false;
          _consoleNavigation = direction == GridDirection.up;
        });
      }
      return;
    }
    if (_brandFocus.hasFocus || _typeFocus.hasFocus) {
      if (direction == GridDirection.down && _typeFocus.hasFocus ||
          direction == GridDirection.down &&
              _brandFocus.hasFocus &&
              !_hasTypes) {
        requestScreenFocus();
        setState(() => _consoleNavigation = true);
      } else {
        primaryFocus?.focusInDirection(switch (direction) {
          GridDirection.up => TraversalDirection.up,
          GridDirection.down => TraversalDirection.down,
          GridDirection.left => TraversalDirection.left,
          GridDirection.right => TraversalDirection.right,
        });
      }
      return;
    }
    final columns = _isDashboard ? _dashboardColumns : _columns;
    if (_consoleNavigation) {
      final slugs = [null, ..._consoleSummaries.map((s) => s.slug)];
      final index = slugs.indexOf(_selectedConsole);
      if (direction == GridDirection.left || direction == GridDirection.right) {
        final next = (index + (direction == GridDirection.left ? -1 : 1))
            .clamp(0, slugs.length - 1);
        _selectConsole(slugs[next]);
      } else if (direction == GridDirection.down) {
        setState(() {
          _consoleNavigation = false;
          _categoryNavigation = _selectedConsole != null;
        });
      } else if (direction == GridDirection.up) {
        if (!_isDashboard) {
          _selectConsole(null);
          _consoleNavigation = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final target = _hasTypes ? _typeFocus : _brandFocus;
            target.requestFocus();
            target.nextFocus();
          });
          return;
        }
        final target = _hasTypes ? _typeFocus : _brandFocus;
        target.requestFocus();
        target.nextFocus();
      }
      return;
    }
    if (direction == GridDirection.up && _currentIndex < columns) {
      _debouncer.stopHold();
      setState(() => _consoleNavigation = true);
      return;
    }
    if (_visibleCount == 0) return;
    if (_isDashboard) {
      final delta = switch (direction) {
        GridDirection.up => -columns,
        GridDirection.down => columns,
        GridDirection.left => -1,
        GridDirection.right => 1,
      };
      setState(() =>
          _currentIndex = (_currentIndex + delta).clamp(0, _visibleCount - 1));
      _scrollToSelected();
      return;
    }

    if (_reorderState == ReorderState.grabbed) {
      _reorderMove(direction);
      return;
    }

    if (_debouncer.startHold(() {
      if (_focusManager.moveFocus(direction)) {
        _scrollToSelected(instant: _debouncer.isHolding);
      }
    })) {
      ref.read(feedbackServiceProvider).tick();
    }
  }

  void _scrollToSelected({bool instant = false}) {
    if (_isDashboard) {
      final target = _itemKeys[_currentIndex]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(target,
            alignment: 0.3,
            duration:
                instant ? Duration.zero : const Duration(milliseconds: 200),
            curve: Curves.easeOut);
      }
      return;
    }
    _focusManager.scrollToSelectedWithFallback(
      itemKey: _itemKeys[_focusManager.selectedIndex],
      crossAxisCount: _columns,
      instant: instant,
      isMounted: () => mounted,
      retryCallback: () => _scrollToSelected(instant: true),
    );
  }

  // --- Scroll Sync ---

  bool _handleScrollNotification(ScrollNotification notification) {
    _focusManager.updateScrollVelocity(notification);
    return _focusManager.handleScrollNotification(notification, context);
  }

  // --- Columns ---

  void _adjustColumns(bool increase) {
    final next = adjustColumnCount(
      current: _columns,
      increase: increase,
      providerKey: 'library',
      ref: ref,
    );
    if (next == _columns) return;
    setState(() => _columns = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelected();
    });
  }

  // --- Game Detail ---

  void _openSelectedGame() {
    if (_currentIndex < 0 || _currentIndex >= _filteredGames.length) return;
    final entry = _filteredGames[_currentIndex];
    _openGameDetail(entry);
  }

  Future<void> _openGameDetail(LibraryEntry entry) async {
    searchFieldNode.unfocus();
    suspendSearchOverlay();
    ref.read(feedbackServiceProvider).confirm();

    final appConfig =
        ref.read(bootstrappedConfigProvider).value ?? AppConfig.empty;
    final systemModel = SystemModel.supportedSystems
        .where((s) => s.id == entry.systemSlug)
        .firstOrNull;
    if (systemModel == null) return;

    final systemConfig =
        ConfigBootstrap.configForSystem(appConfig, systemModel);
    final targetFolder = systemConfig?.targetFolder ?? '';

    final game = GameItem(
      filename: entry.filename,
      displayName: entry.displayName,
      url: entry.url,
      cachedCoverUrl: entry.coverUrl,
      providerConfig: entry.providerConfig,
      remoteArtifact: entry.remoteArtifact,
    );

    final isLocalOnly = systemConfig == null || systemConfig.providers.isEmpty;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GameDetailScreen(
          game: game,
          variants: (_discoveryVariants[
                      coverRatingKey(entry.systemSlug, entry.selectionKey)] ??
                  [entry])
              .map((e) => GameItem(
                  filename: e.filename,
                  displayName: e.displayName,
                  url: e.url,
                  cachedCoverUrl: e.coverUrl,
                  providerConfig: e.providerConfig,
                  remoteArtifact: e.remoteArtifact))
              .toList(),
          system: systemModel,
          targetFolder: targetFolder,
          isLocalOnly: isLocalOnly,
          autoExtract: systemConfig?.autoExtract ?? false,
        ),
      ),
    );

    if (mounted) {
      resumeSearchOverlay();
      // Reload to pick up install/favorite/shelf changes
      _favoriteIds = ref.read(favoriteGamesProvider).toSet();
      _shelves = ref.read(customShelvesProvider);
      final data = ref.read(installedFilesProvider).value;
      if (data != null) {
        _installationState = data;
      }
      _applyFilters();
      if (isSearchActive) {
        requestScreenFocus();
      }
    }
  }

  void _handleConfirm() {
    if (_categoryNavigation) {
      setState(() => _categoryNavigation = false);
      return;
    }
    if (_brandFocus.hasFocus || _typeFocus.hasFocus) {
      final target = primaryFocus?.context;
      if (target != null) Actions.maybeInvoke(target, const ActivateIntent());
      return;
    }
    if (_consoleNavigation) {
      setState(() => _consoleNavigation = false);
      return;
    }
    if (_isDashboard) {
      if (_currentIndex < _consoleSummaries.length) {
        _selectConsole(_consoleSummaries[_currentIndex].slug);
      }
      return;
    }
    if (_reorderState == ReorderState.selecting) {
      _grabItem();
      return;
    }
    if (_reorderState == ReorderState.grabbed) {
      _dropItem();
      return;
    }
    _openSelectedGame();
  }

  void _handleBack() {
    if (_categoryNavigation) {
      setState(() => _categoryNavigation = false);
      return;
    }
    if (_brandFocus.hasFocus || _typeFocus.hasFocus) {
      requestScreenFocus();
      return;
    }
    if (_isFiltering) {
      _closeFilter();
      return;
    }
    ref.read(feedbackServiceProvider).cancel();
    if (_reorderState == ReorderState.grabbed) {
      _dropItem();
      return;
    }
    if (_reorderState == ReorderState.selecting) {
      _exitReorderMode();
      return;
    }
    if (isSearchActive) {
      handleSearchBack();
    } else if (_consoleNavigation) {
      setState(() => _consoleNavigation = false);
    } else if (_selectedConsole != null || _globalDiscoveryRequested) {
      _selectConsole(null);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _onCoverFound(String url, LibraryEntry entry) async {
    await ref.read(libraryDbProvider).updateGameCover(entry.filename, url);
    final idx =
        _allGames.indexWhere((g) => g.selectionKey == entry.selectionKey);
    if (idx >= 0) {
      _allGames[idx] = LibraryEntry(
        filename: entry.filename,
        displayName: entry.displayName,
        cardTitle: entry.cardTitle,
        url: entry.url,
        coverUrl: url,
        systemSlug: entry.systemSlug,
        providerConfig: entry.providerConfig,
        remoteArtifact: entry.remoteArtifact,
        hasThumbnail: entry.hasThumbnail,
      );
    }
  }

  Future<void> _onThumbnailNeeded(String url, LibraryEntry entry) async {
    if (entry.hasThumbnail) return;
    final result = await ThumbnailService.generateThumbnail(url);
    if (result.success) {
      await ref.read(libraryDbProvider).updateGameThumbnailData(
            entry.filename,
            hasThumbnail: true,
          );
      final idx =
          _allGames.indexWhere((g) => g.selectionKey == entry.selectionKey);
      if (idx >= 0) {
        _allGames[idx] = LibraryEntry(
          filename: entry.filename,
          displayName: entry.displayName,
          cardTitle: entry.cardTitle,
          url: entry.url,
          coverUrl: entry.coverUrl,
          systemSlug: entry.systemSlug,
          providerConfig: entry.providerConfig,
          remoteArtifact: entry.remoteArtifact,
          hasThumbnail: true,
        );
      }
    }
  }

  // --- Reorder Mode ---

  void _enterReorderMode() {
    if (_filters.isNotEmpty || _queryingDiscovery || _searchQuery.isNotEmpty) {
      return;
    }
    final shelf = _activeShelf;
    if (shelf == null || shelf.sortMode != ShelfSortMode.manual) return;
    _reorderClaimToken = ref
        .read(overlayPriorityProvider.notifier)
        .claim(OverlayPriority.dialog);
    setState(() {
      _reorderState = ReorderState.selecting;
      _grabbedIndex = -1;
    });
  }

  void _exitReorderMode() {
    if (_reorderState == ReorderState.none) return;
    final token = _reorderClaimToken;
    if (token != null) {
      _reorderClaimToken = null;
      if (!ref.read(overlayPriorityProvider.notifier).release(token)) {
        ref
            .read(overlayPriorityProvider.notifier)
            .releaseByPriority(OverlayPriority.dialog);
      }
    }
    setState(() {
      _reorderState = ReorderState.none;
      _grabbedIndex = -1;
    });
  }

  void _grabItem() {
    if (_filteredGames.isEmpty) return;
    ref.read(feedbackServiceProvider).confirm();
    setState(() {
      _reorderState = ReorderState.grabbed;
      _grabbedIndex = _currentIndex;
    });
  }

  void _dropItem() {
    ref.read(feedbackServiceProvider).tick();
    setState(() {
      _reorderState = ReorderState.selecting;
      _grabbedIndex = -1;
    });
  }

  void _reorderMove(GridDirection direction) {
    final shelf = _activeShelf;
    if (shelf == null || _grabbedIndex < 0) return;

    int targetIndex;
    switch (direction) {
      case GridDirection.left:
        targetIndex = _grabbedIndex - 1;
      case GridDirection.right:
        targetIndex = _grabbedIndex + 1;
      case GridDirection.up:
        targetIndex = _grabbedIndex - _columns;
      case GridDirection.down:
        targetIndex = _grabbedIndex + _columns;
    }

    if (targetIndex < 0 || targetIndex >= _filteredGames.length) return;

    ref.read(feedbackServiceProvider).tick();
    ref.read(customShelvesProvider.notifier).reorderGameInShelf(
          shelf.id,
          _grabbedIndex,
          targetIndex,
          resolvedOrder: _filteredGames.map((g) => g.selectionKey).toList(),
        );
    _shelves = ref.read(customShelvesProvider);
    _applyFilters();
    setState(() {
      _grabbedIndex = targetIndex;
      _currentIndex = targetIndex;
    });
    _scrollToSelected();
  }

  // --- Shelf Management ---

  Future<void> _createShelf() async {
    final allGameRecords = _visibleGames
        .map((g) => (
              filename: g.selectionKey,
              displayName: g.displayName,
              systemSlug: g.systemSlug,
            ))
        .toList();
    final shelf = await Navigator.push<CustomShelf>(
      context,
      MaterialPageRoute(
          builder: (_) => ShelfEditScreen(allGameRecords: allGameRecords)),
    );
    if (shelf != null && mounted) {
      ref.read(customShelvesProvider.notifier).addShelf(shelf);
      _shelves = ref.read(customShelvesProvider);
      setState(() {
        _selectedTab = _fixedTabCount + _shelves.length - 1;
        _currentIndex = 0;
      });
      _applyFilters();
      _scrollToTop();
    }
  }

  Future<void> _editShelf() async {
    final shelf = _activeShelf;
    if (shelf == null) return;
    final allGameRecords = _visibleGames
        .map((g) => (
              filename: g.selectionKey,
              displayName: g.displayName,
              systemSlug: g.systemSlug,
            ))
        .toList();
    final updated = await Navigator.push<CustomShelf>(
      context,
      MaterialPageRoute(
          builder: (_) =>
              ShelfEditScreen(shelf: shelf, allGameRecords: allGameRecords)),
    );
    if (!mounted) return;
    if (updated != null) {
      ref.read(customShelvesProvider.notifier).updateShelf(shelf.id, updated);
    }
    // Always refresh — shelf may have been deleted from edit screen
    _shelves = ref.read(customShelvesProvider);
    final stillExists = _shelves.any((s) => s.id == shelf.id);
    if (!stillExists) {
      setState(() {
        _selectedTab = (_selectedTab - 1).clamp(0, _totalTabCount - 1);
      });
    }
    _currentIndex = 0;
    _applyFilters();
    _scrollToTop();
  }

  void _addCurrentGameToShelf() {
    if (_currentIndex < 0 || _currentIndex >= _filteredGames.length) return;
    if (_shelves.isEmpty) return;
    final entry = _filteredGames[_currentIndex];
    final availableShelves = _shelves
        .where((s) => !s.containsGame(
            entry.selectionKey, entry.displayName, entry.systemSlug))
        .toList();
    if (availableShelves.isEmpty) return;
    showShelfPickerDialog(
      context: context,
      ref: ref,
      shelves: availableShelves,
      onSelect: (shelfId) {
        ref
            .read(customShelvesProvider.notifier)
            .addGameToShelf(shelfId, entry.selectionKey);
        _shelves = ref.read(customShelvesProvider);
        _applyFilters();
      },
    );
  }

  void _removeCurrentGameFromShelf() {
    final shelf = _activeShelf;
    if (shelf == null) return;
    if (_currentIndex < 0 || _currentIndex >= _filteredGames.length) return;
    final entry = _filteredGames[_currentIndex];
    final matchesFilter = shelf.filterRules.any(
      (r) => r.matches(entry.displayName, entry.systemSlug),
    );
    if (matchesFilter) {
      // Filter-matched: must explicitly exclude so filter doesn't re-add it
      ref
          .read(customShelvesProvider.notifier)
          .excludeGameFromShelf(shelf.id, entry.selectionKey);
    } else {
      // Truly manual: just remove from manualGameIds, no exclusion needed
      ref
          .read(customShelvesProvider.notifier)
          .removeGameFromShelf(shelf.id, entry.selectionKey);
    }
    _shelves = ref.read(customShelvesProvider);
    _applyFilters();
  }

  void _handleFavorite() {
    if (_currentIndex < 0 || _currentIndex >= _filteredGames.length) return;
    final entry = _filteredGames[_currentIndex];
    ref.read(feedbackServiceProvider).tick();
    ref.read(favoriteGamesProvider.notifier).toggleFavorite(entry.selectionKey);
    _favoriteIds = ref.read(favoriteGamesProvider).toSet();
    _applyFilters();
  }

  List<QuickMenuItem?> _buildQuickMenuItems() {
    final l = L.of(context);
    final sortLabel = _isShelfTab
        ? switch (_activeShelf?.sortMode ?? ShelfSortMode.alphabetical) {
            ShelfSortMode.alphabetical => l.library_sortSystem,
            ShelfSortMode.bySystem => l.library_sortManual,
            ShelfSortMode.manual => l.library_sortAZ,
          }
        : switch (_sortMode) {
            LibrarySortMode.featured => l.library_sortAZ,
            LibrarySortMode.alphabetical => l.library_sortSystem,
            LibrarySortMode.bySystem => l.filter_topLimit(100),
          };
    final hasDownloads = ref.read(hasQueueItemsProvider);
    final shelf = _activeShelf;
    return [
      QuickMenuItem(
        label: l.library_zoomIn,
        icon: Icons.zoom_in_rounded,
        onSelect: () => _adjustColumns(true),
      ),
      QuickMenuItem(
        label: l.library_zoomOut,
        icon: Icons.zoom_out_rounded,
        onSelect: () => _adjustColumns(false),
      ),
      QuickMenuItem(
        label: l.common_search,
        icon: Icons.search_rounded,
        shortcutHint: 'Y',
        onSelect: openSearch,
      ),
      QuickMenuItem(
          label: l.filter_title,
          icon: Icons.filter_alt_rounded,
          onSelect: _openFilter),
      if (!_isDashboard)
        QuickMenuItem(
            label: 'Get ratings',
            icon: Icons.star_outline_rounded,
            onSelect: () => openRatingsCollector(context, ref,
                systemSlug: _selectedConsole,
                systemSlugs:
                    _selectedConsole == null && _rankingPlatforms.isNotEmpty
                        ? _rankingPlatforms.toList()
                        : null)),
      if (_filteredGames.isNotEmpty) ...[
        QuickMenuItem(
          label:
              _favoriteIds.contains(_filteredGames[_currentIndex].selectionKey)
                  ? l.common_unfavorite
                  : l.common_favorite,
          icon:
              _favoriteIds.contains(_filteredGames[_currentIndex].selectionKey)
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
          shortcutHint: '−',
          onSelect: _handleFavorite,
        ),
      ],
      QuickMenuItem(
        label: sortLabel,
        icon: Icons.sort_rounded,
        onSelect: _cycleSortMode,
      ),
      // --- Shelf management ---
      null,
      QuickMenuItem(
        label: l.library_newShelf,
        icon: Icons.create_new_folder_rounded,
        onSelect: _createShelf,
      ),
      if (shelf != null)
        QuickMenuItem(
          label: l.library_editShelf,
          icon: Icons.edit_rounded,
          onSelect: _editShelf,
        ),
      if (_filteredGames.isNotEmpty &&
          _shelves.any((s) => !s.containsGame(
              _filteredGames[_currentIndex].selectionKey,
              _filteredGames[_currentIndex].displayName,
              _filteredGames[_currentIndex].systemSlug)))
        QuickMenuItem(
          label: l.library_addToShelf,
          icon: Icons.add_rounded,
          onSelect: _addCurrentGameToShelf,
        ),
      if (shelf != null && _filteredGames.isNotEmpty)
        QuickMenuItem(
          label: l.library_removeFromShelf,
          icon: Icons.remove_rounded,
          onSelect: _removeCurrentGameFromShelf,
        ),
      if (shelf != null &&
          _selectedConsole == null &&
          shelf.sortMode == ShelfSortMode.manual &&
          _filters.isEmpty &&
          _searchQuery.isEmpty &&
          _filteredGames.length > 1)
        QuickMenuItem(
          label: l.library_reorderGames,
          icon: Icons.swap_vert_rounded,
          onSelect: _enterReorderMode,
        ),
      // --- Downloads ---
      if (hasDownloads) ...[
        null,
        QuickMenuItem(
          label: l.common_downloads,
          icon: Icons.download_rounded,
          onSelect: () => toggleDownloadOverlay(ref),
          highlight: true,
        ),
      ],
    ];
  }

  // --- Key Events ---

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final searchResult = handleSearchKeyEvent(event);
    if (searchResult != null) return searchResult;
    if (event is KeyUpEvent) {
      _debouncer.stopHold();
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  // --- Count helpers ---

  bool _isGameInstalled(LibraryEntry entry) {
    final artifact = entry.remoteArtifact;
    if (artifact != null) {
      return _installationState.hasExactArtifact(entry.systemSlug, artifact);
    }
    if (entry.providerConfig?.type == ProviderType.drive) return false;
    final filenames =
        _installationState.bySystem[entry.systemSlug] ?? const <String>{};
    final filename = entry.filename;
    if (filenames.contains(filename)) return true;
    // Strip archive extension for extracted ROM match
    for (final ext in SystemModel.archiveExtensions) {
      if (filename.toLowerCase().endsWith(ext)) {
        final stripped = filename.substring(0, filename.length - ext.length);
        // Folder match (multi-file games)
        if (filenames.contains(stripped)) return true;
        // ROM extension replacement (like RomManager.getTargetFilename)
        final system = SystemModel.supportedSystems
            .where((s) => s.id == entry.systemSlug)
            .firstOrNull;
        if (system != null) {
          for (final romExt in system.romExtensions) {
            if (filenames.contains('$stripped$romExt')) return true;
          }
        }
        return false;
      }
    }
    return false;
  }

  /// Deduplicates installed entries that share the same display name and system
  /// (e.g., Mario.iso and Mario.zip both matching after archive-fallback).
  /// Prefers the entry with an exact filesystem match.
  List<LibraryEntry> _deduplicateInstalled(List<LibraryEntry> games) {
    final seen = <String, LibraryEntry>{};
    for (final game in games) {
      final key = game.remoteArtifact == null
          ? '${game.systemSlug}::${game.displayName.toLowerCase()}'
          : '${game.systemSlug}::${game.selectionKey}';
      final existing = seen[key];
      if (existing == null) {
        seen[key] = game;
      } else {
        final gameIsExact = _installedFiles.contains(game.filename);
        final existingIsExact = _installedFiles.contains(existing.filename);
        if (gameIsExact && !existingIsExact) {
          seen[key] = game;
        }
      }
    }
    return seen.values.toList();
  }

  int get _allCount => _scopedGames.length;

  int get _installedCount => _deduplicateInstalled(
        _scopedGames.where((g) => _isGameInstalled(g)).toList(),
      ).length;

  int get _favoritesCount =>
      _scopedGames.where((g) => _favoriteIds.contains(g.selectionKey)).length;

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    _showRatings = ref.watch(ratingOverlaysProvider);
    // Dashboard metrics have no game artwork or score consumers. Console pages
    // consume only their scope; an explicit global shortlist still uses ''.
    final metadataScope = _selectedConsole ?? '';
    _metadataCovers = _isDashboard
        ? const {}
        : ref
                .watch(cachedMetadataCoversProvider(metadataScope))
                .asData
                ?.value ??
            const {};
    final ratings = _showRatings && !_isDashboard
        ? ref.watch(cachedCoverRatingsProvider(metadataScope))
        : null;
    _ratings = ratings == null || ratings.isLoading || ratings.hasError
        ? const {}
        : ratings.asData?.value ?? const {};
    return buildWithActions(
      PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleBack();
        },
        child: Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          body: Stack(
            children: [
              const Positioned.fill(child: AnimatedBackground()),
              Column(children: [
                _buildHeader(rs),
                Expanded(child: _buildContent(rs)),
              ]),
              // Search bar
              if (isSearchActive) _buildSearchBar(),
              // HUD
              if (!showQuickMenu && !_isFiltering) _buildHud(),
              // Quick Menu
              if (showQuickMenu)
                QuickMenuOverlay(
                  items: _buildQuickMenuItems(),
                  onClose: closeQuickMenu,
                ),
              if (_isFiltering) _buildFilter(),
            ],
          ),
        ),
      ),
      onKeyEvent: _handleKeyEvent,
    );
  }

  Widget _buildHeader(Responsive rs) {
    final l = L.of(context);
    final fixedLabels = [
      l.library_tabAll,
      l.library_tabInstalled,
      l.library_tabFavorites
    ];
    final fixedCounts = [_allCount, _installedCount, _favoritesCount];

    final tabs = <LibraryTab>[
      for (int i = 0; i < _fixedTabCount; i++)
        LibraryTab(label: fixedLabels[i], count: fixedCounts[i]),
      for (final shelf in _shelves)
        LibraryTab(
          label: shelf.name,
          count: _shelfGameCount(shelf),
          isCustomShelf: true,
        ),
    ];

    return Container(
      key: const ValueKey('library-header'),
      decoration: const BoxDecoration(
        gradient: AppTheme.headerGradient,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: rs.isSmall ? 16.0 : 24.0,
            vertical: rs.isSmall ? 8.0 : 12.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    l.library_title,
                    style: TextStyle(
                      fontSize: rs.isSmall ? 18 : 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 4,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                      onPressed: _openFilter,
                      icon: const Icon(Icons.filter_alt_rounded),
                      label: Text(_filters.isEmpty
                          ? l.filter_title
                          : l.filter_activeCount(_filters.activeCount))),
                  // Sort indicator
                  Flexible(
                      child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _isShelfTab
                          ? switch (_activeShelf?.sortMode ??
                              ShelfSortMode.alphabetical) {
                              ShelfSortMode.alphabetical =>
                                l.library_sortIndicatorAZ,
                              ShelfSortMode.bySystem =>
                                l.library_sortIndicatorBySystem,
                              ShelfSortMode.manual =>
                                l.library_sortIndicatorManual,
                            }
                          : switch (_sortMode) {
                              LibrarySortMode.featured => _queryingDiscovery
                                  ? l.filter_querying
                                  : (_discovery?.featuredRanks.isNotEmpty ==
                                          true
                                      ? '${l.filter_topLimit(_discovery!.featuredRanks.length)} · ${l.library_sortIndicatorAZ}'
                                      : '${l.library_sortIndicatorAZ} · ${l.metadata_staleScore}'),
                              LibrarySortMode.alphabetical =>
                                l.library_sortIndicatorAZ,
                              LibrarySortMode.bySystem =>
                                l.library_sortIndicatorBySystem,
                            },
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: rs.isSmall ? 9 : 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[400],
                        letterSpacing: 1,
                      ),
                    ),
                  )),
                ],
              ),
              SizedBox(height: rs.isSmall ? 6 : 10),
              if (_isDashboard)
                FocusScope(
                    node: _brandFocus,
                    child: ManufacturerFilter(
                        systems: _browseSystems,
                        selected: _manufacturer,
                        onSelected: (value) =>
                            _setBrowseScope(value, _systemType))),
              if (_isDashboard && _hasTypes)
                FocusScope(
                    node: _typeFocus,
                    child: SystemTypeFilter(
                        systems: _browseSystems,
                        manufacturer: _manufacturer,
                        selected: _systemType,
                        onSelected: (value) =>
                            _setBrowseScope(_manufacturer, value))),
              if (!_isDashboard)
                TextButton.icon(
                  key: const ValueKey('library-browse-parent'),
                  onPressed: () => _selectConsole(null),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_manufacturer case final brand?)
                      Image.asset(
                          'assets/brand_logos/${manufacturerLogos[brand]}.png',
                          width: 72,
                          height: 22,
                          fit: BoxFit.contain,
                          color: Colors.white)
                    else
                      const Text('All manufacturers'),
                    if (_systemType != null) ...[
                      const SizedBox(width: 8),
                      Icon(_systemType!.icon, size: 18),
                      const SizedBox(width: 4),
                      Text(_systemType!.label),
                    ],
                  ]),
                ),
              LibraryTabs(
                key: const ValueKey('library-console-tabs'),
                selectedTab: _selectedConsole == null
                    ? 0
                    : _consoleSummaries
                            .indexWhere((s) => s.slug == _selectedConsole) +
                        1,
                focused: _consoleNavigation,
                tabs: [
                  LibraryTab(
                      label: l.library_dashboard,
                      count: _consoleSummaries.length),
                  for (final summary in _consoleSummaries)
                    LibraryTab(
                        label: _systemShortLabel(summary.slug),
                        count: summary.entries)
                ],
                onTap: (index) {
                  _consoleNavigation = false;
                  _selectConsole(
                      index == 0 ? null : _consoleSummaries[index - 1].slug);
                },
              ),
              const SizedBox(height: 8),
              Row(children: [
                if (_selectedConsole != null) ...[
                  Expanded(
                      child: LibraryTabs(
                    key: const ValueKey('library-category-tabs'),
                    focused: _categoryNavigation,
                    selectedTab: _category == null
                        ? 0
                        : _category == 'commercial'
                            ? 1
                            : 2,
                    tabs: const [
                      LibraryTab(label: 'All'),
                      LibraryTab(label: 'Commercial'),
                      LibraryTab(label: 'Hacks'),
                      LibraryTab(label: 'Patches')
                    ],
                    onTap: (index) => _selectCategory(
                        [null, 'commercial', 'hacks', 'patches'][index]),
                  )),
                  const SizedBox(width: 12),
                ],
                Expanded(
                    child: LibraryTabs(
                  key: const ValueKey('library-status-tabs'),
                  selectedTab: _selectedTab,
                  tabs: tabs,
                  accentColor: Colors.cyanAccent,
                  onTap: _selectTab,
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  int _shelfGameCount(CustomShelf shelf) {
    final allGameRecords = _scopedGames
        .map((g) => (
              filename: g.selectionKey,
              displayName: g.displayName,
              systemSlug: g.systemSlug,
            ))
        .toList();
    return shelf.resolveFilenames(allGameRecords).length;
  }

  Widget _buildSearchBar() {
    return buildSearchWidget(searchQuery: _searchQuery);
  }

  Widget _buildDashboard(Responsive rs) {
    final l = L.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      _dashboardColumns = constraints.maxWidth >= 1300
          ? 3
          : constraints.maxWidth >= 700
              ? 2
              : 1;
      return Column(key: const ValueKey('library-dashboard'), children: [
        Padding(
            padding:
                EdgeInsets.symmetric(horizontal: rs.spacing.lg, vertical: 8),
            child: Tooltip(
                message: l.library_dashboardNote,
                child: Text(l.library_dashboardNote,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 12)))),
        Expanded(
            child: SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(rs.spacing.lg, 8, rs.spacing.lg, 100),
          // Only one tile per available console, not one per ROM. Natural row
          // height accommodates localization/text scaling; every mounted tile
          // has an exact scroll target for controller navigation.
          child: Column(children: [
            for (var start = 0;
                start < _consoleSummaries.length;
                start += _dashboardColumns)
              Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IntrinsicHeight(
                      child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var column = 0;
                          column < _dashboardColumns;
                          column++) ...[
                        if (column > 0) const SizedBox(width: 16),
                        Expanded(
                            child: start + column >= _consoleSummaries.length
                                ? const SizedBox()
                                : KeyedSubtree(
                                    key: _itemKeys[start + column],
                                    child: LibraryConsoleCard(
                                        key: ValueKey(
                                            'console-summary-${_consoleSummaries[start + column].slug}'),
                                        summary:
                                            _consoleSummaries[start + column],
                                        selected: !_consoleNavigation &&
                                            _currentIndex == start + column,
                                        onTap: () {
                                          _consoleNavigation = false;
                                          _selectConsole(
                                              _consoleSummaries[start + column]
                                                  .slug);
                                        }))),
                      ]
                    ],
                  ))),
          ]),
        )),
      ]);
    });
  }

  Widget _buildContent(Responsive rs) {
    if (_isLoading || _queryingDiscovery) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyanAccent),
      );
    }
    if (_discoveryError != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_discoveryError!, style: const TextStyle(color: Colors.white)),
        TextButton(
            onPressed: _applyFilters, child: Text(L.of(context).common_retry)),
      ]));
    }

    if (_isDashboard && _consoleSummaries.isNotEmpty) {
      return _buildDashboard(rs);
    }

    if (_filteredGames.isEmpty) {
      final l = L.of(context);
      final String title;
      final String? subtitle;
      if (_filters.isNotEmpty || _category != null) {
        title = l.filter_noMatches;
        subtitle = null;
      } else if (_searchQuery.isNotEmpty) {
        title = l.library_noResults(_searchQuery);
        subtitle = l.library_tryShorterSearch;
      } else if (_selectedTab == 1) {
        title = l.library_noInstalledGames;
        subtitle = l.library_downloadGamesToSee;
      } else if (_selectedTab == 2) {
        title = l.library_noFavoritesYet;
        subtitle = l.library_pressFavoriteHint;
      } else if (_isShelfTab) {
        title = l.library_noGamesInShelf;
        subtitle = l.library_addGamesViaEditor;
      } else {
        title = l.library_noGamesInLibrary;
        subtitle = _allGames.isEmpty ? l.library_gamesAfterSync : null;
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_books_outlined,
                size: 64, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final media = ref.watch(mediaPresentationProvider);
      final showPreview = !rs.isPortrait && constraints.maxWidth >= 720;
      final previewWidth = showPreview ? constraints.maxWidth * 0.28 : 0.0;
      return Row(children: [
        if (showPreview)
          SizedBox(
              width: previewWidth,
              child: ValueListenableBuilder<int>(
                valueListenable: _selectedIndexNotifier,
                builder: (context, index, _) => _buildMediaPreview(
                    _filteredGames[index.clamp(0, _filteredGames.length - 1)],
                    media,
                    _coverDecodeWidth(rs, constraints.maxWidth - previewWidth)),
              )),
        Expanded(child: _buildGrid(rs, constraints.maxWidth - previewWidth)),
      ]);
    });
  }

  int _coverDecodeWidth(Responsive rs, double availableWidth) {
    final deviceMemory = ref.read(deviceMemoryProvider);
    final gridPadding = rs.spacing.lg * 2;
    final spacing = rs.isSmall ? 10.0 : 16.0;
    final gridWidth = availableWidth - gridPadding;
    final itemWidth = (gridWidth - (_columns - 1) * spacing) / _columns;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return (itemWidth * dpr).round().clamp(150, deviceMemory.memCacheWidthMax);
  }

  Widget _buildGrid(Responsive rs, double availableWidth) {
    final deviceMemory = ref.read(deviceMemoryProvider);
    final optimalCacheWidth = _coverDecodeWidth(rs, availableWidth);

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: RepaintBoundary(
        child: GridView.builder(
          scrollCacheExtent:
              ScrollCacheExtent.pixels(deviceMemory.libraryCacheExtent),
          controller: _scrollController,
          padding: EdgeInsets.only(
            left: rs.spacing.lg,
            right: rs.spacing.lg,
            top: rs.spacing.md,
            bottom: rs.isPortrait ? 80 : 100,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _columns,
            mainAxisSpacing: rs.isSmall ? 10 : 16,
            crossAxisSpacing: rs.isSmall ? 10 : 16,
            childAspectRatio: 1.0,
          ),
          itemCount: _filteredGames.length,
          itemBuilder: (context, index) {
            final entry = _filteredGames[index];
            final variants = _discoveryVariants[
                    coverRatingKey(entry.systemSlug, entry.selectionKey)] ??
                [entry];
            final isInstalled = variants.any(_isGameInstalled);
            final isFavorite =
                variants.any((g) => _favoriteIds.contains(g.selectionKey));

            final coverUrls = _coverUrlCache[index] ?? const [];

            final systemModel = SystemModel.supportedSystems
                .where((s) => s.id == entry.systemSlug)
                .firstOrNull;

            // Short system label for badge
            final systemLabel = _systemShortLabel(entry.systemSlug);
            final systemColor = systemModel?.accentColor ?? Colors.grey;

            final raMatch = _raMatches[entry.raMatchKey];

            // Source dot lookup — entry.providerConfig is rehydrated from
            // the games DB; if it was synthesised by SourceResolver it
            // carries a sourceId we can map back to a live Source.
            final sourcesState = ref.watch(sourcesProvider);
            final entrySourceId = entry.providerConfig?.sourceId;
            Source? entrySource;
            if (entrySourceId != null) {
              for (final s in sourcesState.sources) {
                if (s.id == entrySourceId) {
                  entrySource = s;
                  break;
                }
              }
            }
            final entryDotColor =
                entrySource == null ? null : sourceDotColorFor(entrySource);
            final entryDotBorrowed = entrySource?.borrowed ?? false;

            // Library entries don't carry alternativeSources today (they
            // come from a flat DB row), so the extras list is always empty.
            // Wired through anyway so adding multi-source DB support later
            // only needs to populate this list.
            const List<SourceDotData> entryExtraDots = [];
            final isGrabbed =
                _reorderState == ReorderState.grabbed && _grabbedIndex == index;
            final isReordering = _reorderState != ReorderState.none;

            Widget card = RepaintBoundary(
              key: _itemKeys[index],
              child: SelectionAwareItem(
                selectedIndexNotifier: _selectedIndexNotifier,
                index: index,
                builder: (isSelected) => BaseGameCard(
                  systemId: entry.systemSlug,
                  gameIdentity: entry.selectionKey,
                  displayName: entry.cardTitle,
                  variantCount: variants.length,
                  systemLabel: systemLabel,
                  accentColor: systemColor,
                  coverUrls: coverUrls,
                  cachedUrl: _metadataCovers[coverRatingKey(
                          entry.systemSlug, entry.selectionKey)] ??
                      entry.coverUrl,
                  hasThumbnail: entry.hasThumbnail,
                  memCacheWidth: optimalCacheWidth,
                  scrollSuppression: _scrollSuppression,
                  isInstalled: isInstalled,
                  isRemoteAvailable: variants.any((g) => g.hasDownloadSource),
                  isSelected: isSelected,
                  isFavorite: isFavorite,
                  raAchievementCount: raMatch?.achievementCount,
                  raMatchType: raMatch?.type ?? RaMatchType.none,
                  isMastered: raMatch?.isMastered ?? false,
                  overallRating: _ratings[
                      coverRatingKey(entry.systemSlug, entry.selectionKey)],
                  showRating: _showRatings,
                  sourceDotColor: entryDotColor,
                  sourceDotBorrowed: entryDotBorrowed,
                  extraSourceDots: entryExtraDots,
                  onCoverFound: (url) => _onCoverFound(url, entry),
                  onThumbnailNeeded: (url) => _onThumbnailNeeded(url, entry),
                  onTap: () {
                    if (_reorderState == ReorderState.selecting) {
                      _currentIndex = index;
                      _grabItem();
                      return;
                    }
                    if (_reorderState == ReorderState.grabbed) return;
                    if (_currentIndex == index) {
                      _openGameDetail(entry);
                    } else {
                      _currentIndex = index;
                      ref.read(feedbackServiceProvider).tick();
                    }
                  },
                  onTapSelect: () {
                    if (_reorderState != ReorderState.none) return;
                    if (_currentIndex != index) {
                      _currentIndex = index;
                      ref.read(feedbackServiceProvider).tick();
                    }
                  },
                  onLongPress: isReordering
                      ? null
                      : () {
                          if (_isShelfTab &&
                              _selectedConsole == null &&
                              _activeShelf?.sortMode == ShelfSortMode.manual) {
                            _currentIndex = index;
                            _enterReorderMode();
                            _grabItem();
                          }
                        },
                ),
              ),
            );

            if (isReordering) {
              card = ReorderableCardWrapper(
                isJiggling: _reorderState == ReorderState.selecting,
                isGrabbed: isGrabbed,
                child: card,
              );
            }

            return card;
          },
        ),
      ),
    );
  }

  Widget _buildMediaPreview(LibraryEntry entry,
      ({bool enabled, bool reducedMotion}) media, int coverDecodeWidth) {
    final system = SystemModel.supportedSystems
        .where((system) => system.id == entry.systemSlug)
        .firstOrNull;
    if (system == null) return const SizedBox.shrink();
    final physicalMetadata = media.enabled &&
            PhysicalMediaFormat.forSystem(system.id) != null
        ? ref
            .watch(gameMetadataProvider(
                (filename: entry.selectionKey, systemSlug: entry.systemSlug)))
            .asData
            ?.value
        : null;
    final variants = _discoveryVariants[
            coverRatingKey(entry.systemSlug, entry.selectionKey)] ??
        [entry];
    final installed = variants.any(_isGameInstalled);
    final game = GameItem(
        filename: entry.filename,
        displayName: entry.displayName,
        url: entry.url,
        providerConfig: entry.providerConfig,
        remoteArtifact: entry.remoteArtifact,
        hasThumbnail: entry.hasThumbnail);
    return Padding(
      key: const ValueKey('library-media-preview'),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Column(children: [
        Expanded(
            child: HeroMode(
                enabled: false,
                child: CoverSection(
                  key: ValueKey(entry.selectionKey),
                  game: game,
                  system: system,
                  coverUrls:
                      ImageHelper.getCoverUrlsForSingle(system, entry.filename),
                  physicalLabelUrl: physicalMetadata?.cachedSupportTexture,
                  gbcDualMode: physicalMetadata?.gbcDualMode,
                  boxArtDecodeWidth: coverDecodeWidth,
                  cachedUrl: _metadataCovers[coverRatingKey(
                          entry.systemSlug, entry.selectionKey)] ??
                      entry.coverUrl,
                  metadata: GameMetadata.parse(entry.filename),
                  isFavorite: variants
                      .any((g) => _favoriteIds.contains(g.selectionKey)),
                  isInstalled: installed,
                  hasThumbnail: entry.hasThumbnail,
                  reducedMotion: media.reducedMotion,
                  physicalMediaEnabled: media.enabled,
                  showPresentationControls: false,
                ))),
        Text(GameMetadata.cleanTitle(entry.displayName),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(installed ? Icons.sd_card_outlined : Icons.cloud_outlined,
              color: Colors.white70, size: 20),
          const SizedBox(width: 6),
          Text(_systemShortLabel(entry.systemSlug),
              style: const TextStyle(color: Colors.white70)),
        ]),
        TextButton.icon(
            onPressed: () => _openGameDetail(entry),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Details')),
      ]),
    );
  }

  Widget _buildHud() {
    final l = L.of(context);
    if (_reorderState == ReorderState.grabbed) {
      return ConsoleHud(
        dpad: (label: '\u2190\u2191\u2193\u2192', action: l.common_move),
        a: HudAction(l.common_drop, onTap: _dropItem),
        b: HudAction(l.common_cancel, onTap: _dropItem),
      );
    }
    if (_reorderState == ReorderState.selecting) {
      return ConsoleHud(
        a: HudAction(l.common_grab, onTap: _grabItem),
        b: HudAction(l.common_done, onTap: _exitReorderMode),
      );
    }
    if (isSearchActive) {
      return buildSearchHud(
        aAction: HudAction(l.common_select, onTap: _openSelectedGame),
      );
    }

    return ConsoleHud(
      a: HudAction(l.common_select, onTap: _handleConfirm),
      b: HudAction(l.common_back, onTap: _handleBack),
      start: HudAction(l.common_menu, onTap: toggleQuickMenu),
    );
  }

  static String _systemShortLabel(String slug) {
    const labels = {
      'nes': 'NES',
      'snes': 'SNES',
      'n64': 'N64',
      'gc': 'GCN',
      'wii': 'Wii',
      'wiiu': 'Wii U',
      'switch': 'Switch',
      'gb': 'GB',
      'gbc': 'GBC',
      'gba': 'GBA',
      'nds': 'NDS',
      'n3ds': '3DS',
      'psx': 'PS1',
      'ps2': 'PS2',
      'ps3': 'PS3',
      'psp': 'PSP',
      'psvita': 'Vita',
      'mastersystem': 'SMS',
      'megadrive': 'MD',
      'gamegear': 'GG',
      'dreamcast': 'DC',
      'saturn': 'Saturn',
      'segacd': 'SCD',
      'sega32x': '32X',
      'atari2600': '2600',
      'atari5200': '5200',
      'atari7800': '7800',
      'lynx': 'Lynx',
      'pico8': 'P-8',
    };
    return labels[slug] ?? slug.toUpperCase();
  }
}
