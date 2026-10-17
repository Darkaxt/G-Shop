import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/custom_shelf.dart';
import '../models/sound_settings.dart';
import '../models/preview_settings.dart';
import '../models/commercial_release_preference.dart';

enum ControllerLayout { nintendo, xbox, playstation }

class StorageService {
  static const commercialReleasePreferenceKey =
      'commercial_release_preference_v1';
  CommercialReleasePreference getCommercialReleasePreference() {
    final raw = _prefs?.getString(commercialReleasePreferenceKey);
    if (raw == null) return const CommercialReleasePreference();
    try {
      return CommercialReleasePreference.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } on FormatException {
      return const CommercialReleasePreference();
    } on TypeError {
      return const CommercialReleasePreference();
    }
  }

  Future<void> setCommercialReleasePreference(
      CommercialReleasePreference value) async {
    if (await _prefs?.setString(
            commercialReleasePreferenceKey, jsonEncode(value.toJson())) !=
        true) {
      throw StateError('Collection filters could not be saved');
    }
  }

  PreviewSettings getPreviewSettings() {
    final raw = _prefs?.getString('preview_settings_v1');
    if (raw == null) return const PreviewSettings();
    try {
      return PreviewSettings.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } on FormatException {
      return const PreviewSettings();
    } on TypeError {
      return const PreviewSettings();
    }
  }

  Future<void> setPreviewSettings(PreviewSettings settings) async {
    if (await _prefs?.setString(
            'preview_settings_v1', jsonEncode(settings.toJson())) !=
        true) {
      throw StateError('Preview settings could not be saved');
    }
  }

  static const _romPathKey = 'rom_path';
  static const _hapticEnabledKey = 'haptic_enabled';
  static const _onboardingCompletedKey = 'onboarding_completed';
  static const _soundSettingsKey = 'sound_settings';
  static const _gridColumnsPrefix = 'grid_columns_';
  static const _showFullFilenameKey = 'show_full_filename';
  static const _maxConcurrentDownloadsKey = 'max_concurrent_downloads';
  static const _downloadQueueKey = 'download_queue';
  static const _filterPrefix = 'filters_';
  static const _rommUrlKey = 'romm_url';
  static const _rommAuthKey = 'romm_auth';
  static const _favoritesKey = 'favorite_games';
  static const _xboxLayoutKey = 'xbox_layout'; // legacy bool key
  static const _controllerLayoutKey = 'controller_layout';
  static const _homeLayoutKey = 'home_layout';
  static const _favoritesVersionKey = 'favorites_version';
  static const _customShelvesKey = 'custom_shelves';
  static const _selectionsKey = 'exact_selections_v1';
  Future<void> _selectionWrite = Future.value();
  bool _selectionPersistenceUncertain = false;
  static const _secureAuthMigratedKey = 'secure_auth_migrated';
  static const _allowNonLanHttpKey = 'allow_non_lan_http';
  static const _raUsernameKey = 'ra_username';
  static const _raApiKeyKey = 'ra_api_key';
  static const _raEnabledKey = 'ra_enabled';
  static const _raLastSyncKey = 'ra_last_sync';
  static const _hideEmptyConsolesKey = 'hide_empty_consoles';
  static const _ratingOverlaysKey = 'rating_overlays';
  static const _physicalMediaKey = 'physical_media_enabled';
  static const _reducedMediaMotionKey = 'physical_media_reduced_motion';
  static const _startHintShownKey = 'start_hint_shown';
  static const _localeOverrideKey = 'locale_override';
  static const _syncTimeoutSecondsKey = 'sync_timeout_seconds';
  static const _syncCooldownMinutesKey = 'sync_cooldown_minutes';
  static const _lastSyncPrefix = 'last_sync_';
  SharedPreferences? _prefs;
  final FlutterSecureStorage _secureStorage;

  StorageService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  // In-memory cache for secure values (avoid async reads on every access)
  String? _cachedRommUrl;
  String? _cachedRommAuth;
  String? _cachedRaUsername;
  String? _cachedRaApiKey;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _migrateAuthToSecureStorage();
  }

  /// Migrates RomM auth credentials from SharedPreferences to SecureStorage.
  /// Runs once, then sets a flag to skip on subsequent launches.
  Future<void> _migrateAuthToSecureStorage() async {
    final alreadyMigrated = _prefs!.getBool(_secureAuthMigratedKey) ?? false;
    if (!alreadyMigrated) {
      try {
        final oldUrl = _prefs!.getString(_rommUrlKey);
        final oldAuth = _prefs!.getString(_rommAuthKey);
        if (oldUrl != null) {
          await _secureStorage.write(key: _rommUrlKey, value: oldUrl);
          await _prefs!.remove(_rommUrlKey);
        }
        if (oldAuth != null) {
          await _secureStorage.write(key: _rommAuthKey, value: oldAuth);
          await _prefs!.remove(_rommAuthKey);
        }
        await _prefs!.setBool(_secureAuthMigratedKey, true);
        debugPrint('StorageService: migrated RomM auth to secure storage');
      } catch (e) {
        debugPrint('StorageService: secure storage migration failed: $e');
        // Leave old values in place so the app still works
      }
    }

    // Load secure values into cache
    try {
      _cachedRommUrl = await _secureStorage.read(key: _rommUrlKey);
      _cachedRommAuth = await _secureStorage.read(key: _rommAuthKey);
      _cachedRaUsername = await _secureStorage.read(key: _raUsernameKey);
      _cachedRaApiKey = await _secureStorage.read(key: _raApiKeyKey);
    } catch (e) {
      debugPrint('StorageService: failed to read secure storage: $e');
      // Fallback: try plain SharedPreferences (pre-migration or migration failure)
      _cachedRommUrl = _prefs!.getString(_rommUrlKey);
      _cachedRommAuth = _prefs!.getString(_rommAuthKey);
      _cachedRaUsername = _prefs!.getString(_raUsernameKey);
      _cachedRaApiKey = _prefs!.getString(_raApiKeyKey);
    }
  }

  void _ensureInitialized() {
    if (_prefs == null) {
      throw StateError('StorageService not initialized. Call init() first.');
    }
  }

  String? getRomPath() {
    _ensureInitialized();
    return _prefs!.getString(_romPathKey);
  }

  Future<void> setRomPath(String path) async {
    _ensureInitialized();
    await _prefs!.setString(_romPathKey, path);
  }

  bool getHapticEnabled() {
    _ensureInitialized();
    return _prefs!.getBool(_hapticEnabledKey) ?? true;
  }

  Future<void> setHapticEnabled(bool enabled) async {
    _ensureInitialized();
    await _prefs!.setBool(_hapticEnabledKey, enabled);
  }

  bool getOnboardingCompleted() {
    _ensureInitialized();
    return _prefs!.getBool(_onboardingCompletedKey) ?? false;
  }

  Future<void> setOnboardingCompleted(bool completed) async {
    _ensureInitialized();
    await _prefs!.setBool(_onboardingCompletedKey, completed);
  }

  bool getStartHintShown() {
    _ensureInitialized();
    return _prefs!.getBool(_startHintShownKey) ?? false;
  }

  Future<void> setStartHintShown() async {
    _ensureInitialized();
    await _prefs!.setBool(_startHintShownKey, true);
  }

  Future<void> resetOnboarding() async {
    _ensureInitialized();
    await _prefs!.remove(_onboardingCompletedKey);
    await _prefs!.remove(_romPathKey);
  }

  Future<void> resetAll() async {
    _ensureInitialized();
    await _prefs!.clear();
    try {
      await _secureStorage.deleteAll();
      _cachedRommUrl = null;
      _cachedRommAuth = null;
      _cachedRaUsername = null;
      _cachedRaApiKey = null;
    } catch (e) {
      debugPrint('StorageService: failed to clear secure storage: $e');
    }
  }

  SoundSettings getSoundSettings() {
    _ensureInitialized();
    final json = _prefs!.getString(_soundSettingsKey);
    if (json == null) return const SoundSettings();
    try {
      return SoundSettings.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (e) {
      debugPrint(
          'StorageService: sound settings parse failed, using defaults: $e');
      return const SoundSettings();
    }
  }

  Future<void> setSoundSettings(SoundSettings settings) async {
    _ensureInitialized();
    await _prefs!.setString(_soundSettingsKey, jsonEncode(settings.toJson()));
  }

  Future<String?> pickFolder() async {
    final status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) {
      return null;
    }

    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      await setRomPath(result);
    }
    return result;
  }

  int getGridColumns(String systemName) {
    _ensureInitialized();
    return _prefs!.getInt('$_gridColumnsPrefix$systemName') ?? 4;
  }

  Future<void> setGridColumns(String systemName, int columns) async {
    _ensureInitialized();
    await _prefs!.setInt('$_gridColumnsPrefix$systemName', columns);
  }

  bool getShowFullFilename() {
    _ensureInitialized();
    return _prefs!.getBool(_showFullFilenameKey) ?? false;
  }

  Future<void> setShowFullFilename(bool value) async {
    _ensureInitialized();
    await _prefs!.setBool(_showFullFilenameKey, value);
  }

  // --- Max Concurrent Downloads ---

  int getMaxConcurrentDownloads() {
    _ensureInitialized();
    return _prefs!.getInt(_maxConcurrentDownloadsKey) ?? 2;
  }

  Future<void> setMaxConcurrentDownloads(int value) async {
    _ensureInitialized();
    await _prefs!.setInt(_maxConcurrentDownloadsKey, value);
  }

  // --- Sync Timeout ---

  int getSyncTimeoutSeconds() {
    _ensureInitialized();
    return _prefs!.getInt(_syncTimeoutSecondsKey) ?? 60;
  }

  Future<void> setSyncTimeoutSeconds(int value) async {
    _ensureInitialized();
    await _prefs!.setInt(_syncTimeoutSecondsKey, value);
  }

  // --- Sync Cooldown ---

  int getSyncCooldownMinutes() {
    _ensureInitialized();
    return _prefs!.getInt(_syncCooldownMinutesKey) ?? 60;
  }

  Future<void> setSyncCooldownMinutes(int value) async {
    _ensureInitialized();
    await _prefs!.setInt(_syncCooldownMinutesKey, value);
  }

  // --- Per-System Last Sync Time ---

  DateTime? getLastSyncTime(String systemId) {
    _ensureInitialized();
    final iso = _prefs!.getString('$_lastSyncPrefix$systemId');
    if (iso == null) return null;
    return DateTime.tryParse(iso);
  }

  /// The whole collection is only as current as its oldest configured console.
  /// A never-refreshed console prevents claiming a complete collection refresh.
  DateTime? getOldestCollectionSync(Iterable<String> systemIds) {
    DateTime? oldest;
    for (final id in systemIds.toSet()) {
      final refreshed = getLastSyncTime(id);
      if (refreshed == null) return null;
      if (oldest == null || refreshed.isBefore(oldest)) oldest = refreshed;
    }
    return oldest;
  }

  Future<void> setLastSyncTime(String systemId, DateTime time) async {
    _ensureInitialized();
    await _prefs!
        .setString('$_lastSyncPrefix$systemId', time.toIso8601String());
  }

  // --- Download Queue Persistence ---

  String? getDownloadQueue() {
    _ensureInitialized();
    return _prefs!.getString(_downloadQueueKey);
  }

  Future<void> setDownloadQueue(String json) async {
    _ensureInitialized();
    if (!await _prefs!.setString(_downloadQueueKey, json)) {
      throw StateError('Download queue could not be persisted');
    }
  }

  Future<void> clearDownloadQueue() async {
    _ensureInitialized();
    if (!await _prefs!.remove(_downloadQueueKey)) {
      throw StateError('Download queue could not be cleared');
    }
  }

  // --- Filter Persistence ---

  String? getLibraryConsole() {
    _ensureInitialized();
    return _prefs!.getString('library_console');
  }

  Future<void> setLibraryConsole(String? slug) async {
    _ensureInitialized();
    if (!await _prefs!.setString('library_console', slug ?? '')) {
      throw StateError('Library console selection could not be persisted');
    }
  }

  String? getFilters(String systemId) {
    _ensureInitialized();
    return _prefs!.getString('$_filterPrefix$systemId');
  }

  Future<void> setFilters(String systemId, String json) async {
    _ensureInitialized();
    await _prefs!.setString('$_filterPrefix$systemId', json);
  }

  Future<void> removeFilters(String systemId) async {
    _ensureInitialized();
    await _prefs!.remove('$_filterPrefix$systemId');
  }

  bool getRatingOverlays() {
    _ensureInitialized();
    return _prefs!.getBool(_ratingOverlaysKey) ?? true;
  }

  bool getPhysicalMediaEnabled() {
    _ensureInitialized();
    return _prefs!.getBool(_physicalMediaKey) ?? false;
  }

  bool getReducedMediaMotion() {
    _ensureInitialized();
    return _prefs!.getBool(_reducedMediaMotionKey) ?? false;
  }

  Future<void> setPhysicalMediaEnabled(bool enabled) async {
    _ensureInitialized();
    if (!await _prefs!.setBool(_physicalMediaKey, enabled)) {
      throw StateError('3D media preference was not saved');
    }
  }

  Future<void> setReducedMediaMotion(bool enabled) async {
    _ensureInitialized();
    if (!await _prefs!.setBool(_reducedMediaMotionKey, enabled)) {
      throw StateError('Reduced motion preference was not saved');
    }
  }

  Future<void> setRatingOverlays(bool enabled) async {
    _ensureInitialized();
    if (!await _prefs!.setBool(_ratingOverlaysKey, enabled)) {
      throw StateError('Rating overlay preference was not saved');
    }
  }

  // --- Global RomM Connection (encrypted via SecureStorage) ---

  String? getRommUrl() {
    _ensureInitialized();
    return _cachedRommUrl;
  }

  Future<void> setRommUrl(String? url) async {
    _ensureInitialized();
    if (url == null || url.isEmpty) {
      await _secureStorage.delete(key: _rommUrlKey);
      _cachedRommUrl = null;
    } else {
      await _secureStorage.write(key: _rommUrlKey, value: url);
      _cachedRommUrl = url;
    }
  }

  String? getRommAuth() {
    _ensureInitialized();
    return _cachedRommAuth;
  }

  Future<void> setRommAuth(String? json) async {
    _ensureInitialized();
    if (json == null) {
      await _secureStorage.delete(key: _rommAuthKey);
      _cachedRommAuth = null;
    } else {
      await _secureStorage.write(key: _rommAuthKey, value: json);
      _cachedRommAuth = json;
    }
  }

  // --- Favorites Persistence ---

  int getFavoritesVersion() {
    _ensureInitialized();
    return _prefs!.getInt(_favoritesVersionKey) ?? 0;
  }

  Future<void> setFavoritesVersion(int version) async {
    _ensureInitialized();
    try {
      if (!await _prefs!.setInt(_favoritesVersionKey, version)) {
        throw StateError(
            'Favorites migration version was not durably acknowledged');
      }
    } catch (_) {
      // SharedPreferences updates its in-memory cache before the platform
      // acknowledges persistence. Do not let rejection masquerade as migration.
      await _prefs!.reload();
      rethrow;
    }
  }

  List<String> getFavorites() {
    _ensureInitialized();
    final selections = _readSelections();
    if (selections != null) {
      return (selections['favorites'] as List).cast<String>().toList();
    }
    return _prefs!.getStringList(_favoritesKey) ?? [];
  }

  Future<void> setFavorites(List<String> favorites) {
    final captured = List<String>.of(favorites);
    return _writeSelections((settings) => settings['favorites'] = captured);
  }

  Future<void> toggleFavorite(String gameId) => _writeSelections((settings) {
        final favorites =
            (settings['favorites'] as List).cast<String>().toList();
        if (favorites.contains(gameId)) {
          favorites.remove(gameId);
        } else {
          favorites.add(gameId);
        }
        settings['favorites'] = favorites;
      });

  Map<String, dynamic>? _readSelections() {
    if (_selectionPersistenceUncertain) {
      throw StateError('Selection settings require durable readback');
    }
    final encoded = _prefs!.getString(_selectionsKey);
    if (encoded == null) return null;
    final result = (jsonDecode(encoded) as Map).cast<String, dynamic>();
    if (result['schema'] != 1 ||
        result['favorites'] is! List ||
        result['shelves'] is! List ||
        result['migratedAliases'] is! List) {
      throw const FormatException('Invalid exact selection settings');
    }
    return result;
  }

  /// Companion ownership is an exact edition association, not a title/filename
  /// preference. Package visibility and current launchability are checked natively.
  String? getCompanion(String editionId) {
    _ensureInitialized();
    if (editionId.trim().isEmpty) {
      throw ArgumentError('An edition ID is required');
    }
    final companions = _readSelections()?['companions'];
    if (companions == null) return null;
    return (companions as Map)[editionId] as String?;
  }

  Future<void> setCompanion(String editionId, String? component) {
    if (editionId.trim().isEmpty) {
      throw ArgumentError('An edition ID is required');
    }
    if (component != null &&
        !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+/\.?[A-Za-z_$][A-Za-z0-9_.$]*$')
            .hasMatch(component)) {
      throw ArgumentError('An Android launcher component is required');
    }
    return _writeSelections((settings) {
      final companions =
          Map<String, dynamic>.from(settings['companions'] as Map? ?? const {});
      if (component == null) {
        companions.remove(editionId);
      } else {
        companions[editionId] = component;
      }
      settings['companions'] = companions;
    });
  }

  // Favorites, shelves and migration receipts share one acknowledged preference
  // write. Serializing their read/modify/write avoids lost concurrent toggles.
  Future<void> _writeSelections(void Function(Map<String, dynamic>) update) {
    _ensureInitialized();
    final work = _selectionWrite.then((_) async {
      if (_selectionPersistenceUncertain) {
        await _prefs!.reload();
        _selectionPersistenceUncertain = false;
      }
      final settings = _readSelections() ??
          {
            'schema': 1,
            'favorites': getFavorites(),
            'shelves': getCustomShelves().map((s) => s.toJson()).toList(),
            'migratedAliases': <String>[],
          };
      final before = jsonEncode(settings);
      update(settings);
      final encoded = jsonEncode(settings);
      if (before == encoded) return;
      try {
        if (!await _prefs!.setString(_selectionsKey, encoded)) {
          throw StateError('Selection settings were not durably acknowledged');
        }
      } catch (_) {
        _selectionPersistenceUncertain = true;
        await _prefs!.reload();
        _selectionPersistenceUncertain = false;
        rethrow;
      }
    });
    _selectionWrite =
        work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return work;
  }

  /// Caller supplies only exact, currently bound aliases, across the complete
  /// cached collection. Receipts prevent an old shared filename favorite from
  /// re-favoriting a cloud identity after an explicit unfavorite.
  Future<void> migrateExactSelections(Map<String, Map<String, String>> aliases,
      {required Set<String> remainingLegacyKeys}) {
    final captured = {
      for (final system in aliases.entries)
        system.key: Map<String, String>.of(system.value)
    };
    final remaining = Set<String>.of(remainingLegacyKeys);
    return _writeSelections((settings) {
      final receipts =
          (settings['migratedAliases'] as List).cast<String>().toSet();
      final pending = <String, Set<String>>{};
      final known = <String>{};
      for (final system in captured.entries) {
        for (final alias in system.value.entries) {
          if (!alias.value.startsWith('artifact:')) {
            throw ArgumentError('An exact selection key is required');
          }
          known.add(alias.key);
          if (receipts.add(jsonEncode([system.key, alias.key, alias.value]))) {
            pending.putIfAbsent(alias.key, () => {}).add(alias.value);
          }
        }
      }
      List<String> migrate(List<dynamic> keys) => <String>{
            for (final key in keys.cast<String>()) ...[
              if (!known.contains(key) || remaining.contains(key)) key,
              ...?pending[key],
            ],
          }.toList();
      settings['favorites'] = migrate(settings['favorites'] as List);
      settings['shelves'] = [
        for (final raw in settings['shelves'] as List)
          {
            ...(raw as Map).cast<String, dynamic>(),
            'manualGameIds': migrate(raw['manualGameIds'] as List? ?? []),
            'excludedGameIds': migrate(raw['excludedGameIds'] as List? ?? [])
          },
      ];
      settings['migratedAliases'] = receipts.toList();
    });
  }

  bool isFavorite(String gameId) {
    return getFavorites().contains(gameId);
  }

  // Controller Layout
  ControllerLayout getControllerLayout() {
    _ensureInitialized();
    final stored = _prefs!.getString(_controllerLayoutKey);
    if (stored != null) {
      return ControllerLayout.values.firstWhere(
        (e) => e.name == stored,
        orElse: () => ControllerLayout.nintendo,
      );
    }
    // Migration: read old bool key
    final oldBool = _prefs!.getBool(_xboxLayoutKey);
    if (oldBool == true) return ControllerLayout.xbox;
    return ControllerLayout.nintendo;
  }

  Future<void> setControllerLayout(ControllerLayout layout) async {
    _ensureInitialized();
    await _prefs!.setString(_controllerLayoutKey, layout.name);
  }

  // Home Layout
  bool getHomeLayoutIsGrid() {
    _ensureInitialized();
    return _prefs!.getBool(_homeLayoutKey) ?? false;
  }

  Future<void> setHomeLayoutIsGrid(bool value) async {
    _ensureInitialized();
    await _prefs!.setBool(_homeLayoutKey, value);
  }

  // Locale override (null = follow system)
  String? getLocaleOverride() {
    _ensureInitialized();
    return _prefs!.getString(_localeOverrideKey);
  }

  Future<void> setLocaleOverride(String? code) async {
    _ensureInitialized();
    if (code == null) {
      await _prefs!.remove(_localeOverrideKey);
    } else {
      await _prefs!.setString(_localeOverrideKey, code);
    }
  }

  // Hide Empty Consoles
  bool getHideEmptyConsoles() {
    _ensureInitialized();
    return _prefs!.getBool(_hideEmptyConsolesKey) ?? false;
  }

  Future<void> setHideEmptyConsoles(bool value) async {
    _ensureInitialized();
    await _prefs!.setBool(_hideEmptyConsolesKey, value);
  }

  // --- Custom Shelves ---

  List<CustomShelf> getCustomShelves() {
    _ensureInitialized();
    final selections = _readSelections();
    if (selections != null) {
      return (selections['shelves'] as List)
          .map((e) => CustomShelf.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    }
    final json = _prefs!.getString(_customShelvesKey);
    if (json == null) return [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => CustomShelf.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('StorageService: custom shelves parse failed: $e');
      return [];
    }
  }

  Future<void> setCustomShelves(List<CustomShelf> shelves) {
    final captured = shelves.map((s) => s.toJson()).toList();
    return _writeSelections((settings) => settings['shelves'] = captured);
  }

  // --- Non-LAN HTTP ---

  bool getAllowNonLanHttp() {
    _ensureInitialized();
    return _prefs!.getBool(_allowNonLanHttpKey) ?? false;
  }

  Future<void> setAllowNonLanHttp(bool allowed) async {
    _ensureInitialized();
    await _prefs!.setBool(_allowNonLanHttpKey, allowed);
  }

  // --- RetroAchievements (encrypted via SecureStorage) ---

  String? getRaUsername() {
    _ensureInitialized();
    return _cachedRaUsername;
  }

  Future<void> setRaUsername(String? username) async {
    _ensureInitialized();
    if (username == null || username.isEmpty) {
      await _secureStorage.delete(key: _raUsernameKey);
      _cachedRaUsername = null;
    } else {
      await _secureStorage.write(key: _raUsernameKey, value: username);
      _cachedRaUsername = username;
    }
  }

  String? getRaApiKey() {
    _ensureInitialized();
    return _cachedRaApiKey;
  }

  Future<void> setRaApiKey(String? key) async {
    _ensureInitialized();
    if (key == null || key.isEmpty) {
      await _secureStorage.delete(key: _raApiKeyKey);
      _cachedRaApiKey = null;
    } else {
      await _secureStorage.write(key: _raApiKeyKey, value: key);
      _cachedRaApiKey = key;
    }
  }

  bool getRaEnabled() {
    _ensureInitialized();
    return _prefs!.getBool(_raEnabledKey) ?? false;
  }

  Future<void> setRaEnabled(bool enabled) async {
    _ensureInitialized();
    await _prefs!.setBool(_raEnabledKey, enabled);
  }

  DateTime? getRaLastSync() {
    _ensureInitialized();
    final iso = _prefs!.getString(_raLastSyncKey);
    if (iso == null) return null;
    return DateTime.tryParse(iso);
  }

  Future<void> setRaLastSync(DateTime time) async {
    _ensureInitialized();
    await _prefs!.setString(_raLastSyncKey, time.toIso8601String());
  }

  /// Whether RA is fully configured (has credentials + enabled).
  bool get isRaConfigured =>
      getRaEnabled() && _cachedRaApiKey != null && _cachedRaApiKey!.isNotEmpty;
}
