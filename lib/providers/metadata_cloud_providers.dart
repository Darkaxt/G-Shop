import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../services/drive/drive_authorization.dart';
import '../models/config/source.dart';
import '../models/preview_settings.dart';
import '../models/scraped_metadata.dart';
import '../services/secondary_preview.dart';
import '../services/drive/drive_runtime.dart';
import '../services/library_query.dart';
import '../services/library_store.dart';
import '../services/metadata/drive_metadata_api.dart';
import '../services/metadata/metadata_artwork_cache.dart';
import '../services/metadata/metadata_cloud_library.dart';
import '../services/metadata/preview_video_cache.dart';
import '../services/migration/migration_maintenance.dart';
import '../services/image_cache_service.dart';
import '../services/thumbnail_service.dart';
import 'library_providers.dart';
import 'preview_providers.dart';
import 'metadata_providers.dart';

const metadataCloudSettingsKey = 'metadata_cloud_v1';
final metadataMediaKeyRevisionProvider =
    StateProvider.autoDispose.family<int, String>((ref, key) => 0);
final editionGalleryMediaProvider = FutureProvider.autoDispose
    .family<Map<String, List<String>>, String>((ref, edition) async {
  return _editionPanels(ref, edition, booklet: true);
});
final boxCardMediaProvider = FutureProvider.autoDispose
    .family<Map<String, List<String>>, ({String platform, String selection})>(
        (ref, selection) async {
  ref.watch(gameDbChangedProvider);
  await ref.watch(scopedMetadataReadinessProvider(selection.platform).future);
  final edition = await LibraryQuery(ref.read(libraryDbProvider).database)
      .editionForSelection(selection.platform, selection.selection);
  if (edition == null) return const {};
  return _editionPanels(ref, edition, booklet: false);
});

Future<Map<String, List<String>>> _editionPanels(Ref ref, String edition,
    {required bool booklet}) async {
  ref.watch(metadataMediaRevisionProvider);
  final controller = ref.read(metadataCloudProvider.notifier);
  await controller.ready;
  final cloud = controller.library;
  final owner = Object();
  var active = true;
  final keys = <String>{};
  ref.onDispose(() {
    active = false;
    cloud?.release(owner);
  });
  if (cloud != null) {
    final database = ref.read(libraryDbProvider).database;
    for (final provider in [
      'packaging',
      'launchbox',
      'screenscraper',
      'romm'
    ]) {
      final record = await LibraryStore(database).metadata(edition, provider);
      if (record != null) {
        final pages = record.media
            .where((m) => m.type == 'manual-page')
            .toList()
          ..sort((a, b) => (a.memberIndex ?? 0).compareTo(b.memberIndex ?? 0));
        final requiredPages = {
          pages.firstOrNull,
          pages.lastOrNull,
          pages.length > 1 ? pages[1] : null,
          pages.length > 2 ? pages[2] : null
        };
        keys.addAll(record.media
            .where((m) =>
                m.type.startsWith('outer-box-') ||
                {'box-2D', 'box-2D-back', 'box-2D-side'}.contains(m.type) ||
                booklet && requiredPages.contains(m))
            .map(MetadataArtworkCache.key));
      }
    }
    if (active) await cloud.leaseMedia(owner, keys);
    if (!active) cloud.release(owner);
  }
  final resources = await (await ref.read(cachedMetadataArtworkProvider))
      .galleryForEdition(edition, hydrateBooklet: booklet, hydrateTypes: const {
    'outer-box-front',
    'outer-box-back',
    'outer-box-left',
    'outer-box-right',
    'outer-box-top',
    'outer-box-bottom',
    'box-2D',
    'box-2D-back',
    'box-2D-side'
  });
  if (active) {
    for (final key in keys) {
      ref.watch(metadataMediaKeyRevisionProvider(key));
    }
  }
  return resources;
}

final metadataMediaRevisionProvider = StateProvider<int>((ref) => 0);

class MetadataCloudState {
  final bool enabled, busy;
  final String? sourceId, message;
  final int budgetBytes, cachedBytes;
  const MetadataCloudState(
      {this.enabled = false,
      this.busy = false,
      this.sourceId,
      this.message,
      this.budgetBytes = MetadataCloudLibrary.defaultBudgetBytes,
      this.cachedBytes = 0});
}

/// One foreground owner: startup recovery, scrape publication and cache fills
/// share the same serialized library. No ROM or save-write API is used here.
class MetadataCloudController extends StateNotifier<MetadataCloudState> {
  final Ref ref;
  MetadataCloudLibrary? library;
  DriveMetadataApi? _api;
  Map<String, dynamic> _settings = {};
  bool _dirty = false, _publishing = false, _disposed = false, _paused = false;
  Future<void> _operation = Future.value();
  late final Future<void> ready = _load();
  MetadataCloudController(this.ref) : super(const MetadataCloudState()) {
    unawaited(ready);
  }
  void _state({bool? busy, String? message}) {
    if (_disposed) return;
    state = MetadataCloudState(
        enabled: _settings['enabled'] == true,
        busy: busy ?? state.busy,
        sourceId: _settings['source'] as String?,
        message: message,
        budgetBytes: (_settings['budget'] as int?) ??
            MetadataCloudLibrary.defaultBudgetBytes,
        cachedBytes: state.cachedBytes);
  }

  Future<void> _save() async => (await SharedPreferences.getInstance())
      .setString(metadataCloudSettingsKey, jsonEncode(_settings));
  void _failure(Object error, [StackTrace? trace]) {
    debugPrint(
        'Metadata cloud incomplete: ${error is DriveAuthorizationException ? error.issue.name : error.runtimeType}');
    if (error is FormatException &&
        const {
          'Metadata rebuild target changed remotely',
          'Metadata rebuild trash was not verified',
          'Metadata root changed',
          'Not an owned R-Shop metadata object',
          'Metadata rebuild is incomplete',
          'Metadata version changed remotely',
          'Metadata publication intent changed',
          'Metadata publication changed remotely',
          'Game resource role mismatch',
          'Game resource publication changed',
          'Ambiguous game resource',
          'Ambiguous game metadata',
          'Cloud media ownership changed',
          'Local metadata bytes changed',
        }.contains(error.message))
      debugPrint('Metadata rebuild: ${error.message}');
    if (trace != null) {
      final sites = trace
          .toString()
          .split('\n')
          .where((line) => line.contains('package:retro_eshop/'))
          .take(4)
          .join('\n');
      if (sites.isNotEmpty) debugPrint('Metadata cloud failure sites:\n$sites');
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    final raw = prefs.getString(metadataCloudSettingsKey);
    if (raw != null) {
      try {
        final saved = (jsonDecode(raw) as Map).cast<String, dynamic>();
        final budget =
            saved['budget'] ?? MetadataCloudLibrary.defaultBudgetBytes;
        if (![1, 2, 4, 8].any((n) => budget == n * 1024 * 1024 * 1024) ||
            (saved['enabled'] == true &&
                !['account', 'client', 'root', 'source'].every((k) =>
                    saved[k] is String && (saved[k] as String).isNotEmpty))) {
          throw const FormatException('Invalid metadata settings');
        }
        _settings = saved;
      } catch (_) {
        _state(message: 'Reconnect the metadata library in Storage settings');
        return;
      }
    }
    _state();
    if (_settings['enabled'] == true) {
      try {
        await _open();
      } catch (_) {
        _state(message: 'Shared metadata storage is unavailable');
      }
      // Opening the app may drain local backups, not refresh every remote game.
      unawaited(sync(pull: false));
    }
  }

  Future<void> _open() async {
    if (library != null) return;
    final store = await ref.read(sharedMetadataStoreProvider);
    if (store == null) throw StateError('Choose shared metadata storage first');
    final auth =
        DriveRuntime.instance.authorizationFor(_settings['client'] as String);
    _api = DriveMetadataApi(
        authorization: auth, accountId: _settings['account'] as String);
    final opened = MetadataCloudLibrary(
        store: store,
        remote: _api!,
        accountId: _settings['account'] as String,
        rootId: _settings['root'] as String,
        progress: (completed, total) {
          _state(
              busy: true,
              message: 'Backing up metadata: $completed/$total games');
          if (completed == 0 || completed == total || completed % 100 == 0)
            debugPrint('Metadata cloud publication: games=$completed/$total');
        },
        budgetBytes: (_settings['budget'] as int?) ??
            MetadataCloudLibrary.defaultBudgetBytes,
        allowBackgroundDownload: (path) async {
          if (!path.endsWith('.mp4')) return true;
          final policy = ref.read(previewSettingsProvider).downloads;
          return policy == PreviewDownloadPolicy.any ||
              (policy == PreviewDownloadPolicy.wifi &&
                  await SecondaryPreview.channel.invokeMethod<bool>('wifi') ==
                      true);
        },
        changed: () {
          if (!_disposed)
            ref.read(metadataMediaRevisionProvider.notifier).state++;
        },
        mediaChanged: (key) {
          if (!_disposed)
            ref.read(metadataMediaKeyRevisionProvider(key).notifier).state++;
        });
    await opened.open();
    if (_disposed || _paused) {
      await opened.close();
      throw StateError('Metadata owner closed');
    }
    library = opened;
    store.cloudChanged = _publishChanged;
    store.joinCloudOwner = pause;
    await refreshUsage();
  }

  Future<void> connect(Source source) {
    if (state.busy || _paused || MigrationMaintenance.active)
      return Future.value();
    return _operation = _connect(source);
  }

  Future<void> _connect(Source source) async {
    if (state.busy || MigrationMaintenance.active) return;
    final drive = source.drive;
    if (source.type != SourceType.drive || drive == null || !drive.isConfigured)
      return;
    _state(busy: true);
    try {
      final store = await ref.read(sharedMetadataStoreProvider);
      if (store == null)
        throw StateError('Choose shared metadata storage first');
      await closeLibrary();
      final auth = DriveRuntime.instance.authorizationFor(drive.serverClientId);
      await auth.acquireMetadata(
          expectedAccountId: drive.accountId, interactive: true);
      final api =
          DriveMetadataApi(authorization: auth, accountId: drive.accountId);
      try {
        // Persist the creation identity before issuing a write; a lost reply
        // resumes this intent rather than creating duplicate roots.
        final sameAccount = _settings['account'] == drive.accountId;
        final roots = sameAccount && _settings['root'] != null
            ? <MetadataCloudFile>[]
            : await api.children(null);
        if (roots.length > 1)
          throw StateError('More than one metadata library needs review');
        _settings = {
          'enabled': true,
          'source': source.id,
          'account': drive.accountId,
          'client': drive.serverClientId,
          'root': sameAccount && _settings['root'] != null
              ? _settings['root']
              : roots.isEmpty
                  ? await api.reserveId()
                  : roots.single.id,
          'budget': state.budgetBytes
        };
        await _save();
        await api.folder(_settings['root'] as String, null, 'R-Shop Metadata');
      } finally {
        api.close();
      }
      await _open();
      await library!.sync(ref.read(libraryDbProvider).database);
      if (!_disposed) ref.read(gameDbChangedProvider.notifier).state++;
      await refreshUsage();
      _state(busy: false, message: 'Metadata is backed up in Drive');
      if (_dirty) _publishChanged();
    } catch (error, trace) {
      _failure(error, trace);
      _state(
          busy: false,
          message:
              'Could not finish. Local metadata is safe; retry when Drive is available.');
    }
  }

  Future<void> sync({bool pull = true}) {
    if (_paused ||
        state.busy ||
        _settings['enabled'] != true ||
        MigrationMaintenance.active) return Future.value();
    return _operation = _sync(pull);
  }

  Future<void> _sync(bool pull) async {
    if (_paused ||
        state.busy ||
        _settings['enabled'] != true ||
        MigrationMaintenance.active) return;
    _state(busy: true);
    try {
      await _open();
      if (_settings['rebuildPending'] == true) await _discardCollectedMedia();
      await library!.sync(ref.read(libraryDbProvider).database, pull: pull);
      if (_paused) return;
      if (pull && !_disposed) ref.read(gameDbChangedProvider.notifier).state++;
      await refreshUsage();
      debugPrint(
          'Metadata cloud sync completed: cachedBytes=${state.cachedBytes}');
      _state(busy: false, message: 'Metadata is backed up in Drive');
      if (_dirty) _publishChanged();
    } catch (error, trace) {
      _failure(error, trace);
      _state(
          busy: false,
          message: 'Waiting for Drive. Local metadata remains available.');
    }
  }

  void _publishChanged() {
    _dirty = true;
    if (_publishing || _paused || state.busy || _disposed) return;
    unawaited(() async {
      _publishing = true;
      try {
        while (_dirty && !_paused && !_disposed) {
          _dirty = false;
          await sync(pull: false);
          if (state.message != 'Metadata is backed up in Drive') break;
        }
      } finally {
        _publishing = false;
      }
    }());
  }

  Future<void> refreshUsage() async {
    final bytes = await library?.cachedBytes() ?? 0;
    if (!_disposed)
      state = MetadataCloudState(
          enabled: _settings['enabled'] == true,
          sourceId: _settings['source'] as String?,
          busy: state.busy,
          message: state.message,
          budgetBytes: (_settings['budget'] as int?) ??
              MetadataCloudLibrary.defaultBudgetBytes,
          cachedBytes: bytes);
  }

  Future<void> setBudget(int bytes) async {
    if (state.busy ||
        MigrationMaintenance.active ||
        ![1, 2, 4, 8].any((g) => bytes == g * 1024 * 1024 * 1024)) return;
    _settings['budget'] = bytes;
    await _save();
    _state(busy: true);
    try {
      library?.budgetBytes = bytes;
      await library?.trim(bytes);
      await refreshUsage();
      _state(busy: false);
    } catch (_) {
      _state(
          busy: false,
          message: 'Connect to Drive to free verified cached media');
    }
  }

  Future<void> clearCache() async {
    if (state.busy || MigrationMaintenance.active) return;
    _state(busy: true);
    try {
      await library?.trim(0);
      await ThumbnailService.clearAll();
      await GameCoverCacheManager.instance.emptyCache();
      await ref.read(libraryDbProvider).clearThumbnailData();
      FailedUrlsCache.instance.clear();
      await refreshUsage();
      _state(busy: false);
    } catch (_) {
      _state(
          busy: false, message: 'Only verified, unused media can be removed');
    }
  }

  /// A deliberate rebuild is distinct from clearing verified local copies.
  Future<void> rebuildMedia() {
    if (_paused ||
        (state.busy && _settings['rebuildPending'] == true) ||
        MigrationMaintenance.active ||
        !state.enabled) {
      return Future.value();
    }
    _paused = true;
    library?.stopPublication();
    final previous = _operation;
    return _operation = () async {
      await previous;
      _state(busy: true, message: 'Removing old collected media');
      _settings['rebuildPending'] = true;
      await _save();
      try {
        _paused = false;
        await _open();
        await _discardCollectedMedia();
        _dirty = false;
        await refreshUsage();
        _state(
            busy: false,
            message:
                'Old media removed. Collect media to download fresh resources.');
      } catch (error) {
        _failure(error);
        _state(
            busy: false,
            message:
                'Media rebuild is paused. Sync will finish removing old resources.');
      } finally {
        _paused = false;
      }
    }();
  }

  Future<void> _discardCollectedMedia() async {
    await ref.read(metadataControlsProvider.notifier).pause();
    final recordsBefore = (await library!.store.cloudIndex
            .rawQuery('SELECT COUNT(*) AS n FROM records'))
        .single['n'];
    final bytesBefore = await library!.cachedBytes();
    await library!.discardCollectedMedia();
    await ThumbnailService.clearAll();
    await GameCoverCacheManager.instance.emptyCache();
    await ref.read(libraryDbProvider).clearThumbnailData();
    FailedUrlsCache.instance.clear();
    _settings.remove('rebuildPending');
    await _save();
    ref.read(metadataMediaRevisionProvider.notifier).state++;
    final recordsAfter = (await library!.store.cloudIndex
            .rawQuery('SELECT COUNT(*) AS n FROM records'))
        .single['n'];
    debugPrint(
        'Metadata media rebuild completed: records=$recordsBefore/$recordsAfter '
        'discardedBytes=$bytesBefore cachedBytes=${await library!.cachedBytes()}');
  }

  Future<void> pause() async {
    _paused = true;
    await _operation;
    await closeLibrary();
    // A joined sync can return early while paused. Release its UI admission
    // state only after the owner is closed, so resume can publish imported work.
    _state(busy: false);
  }

  void resume() {
    _paused = false;
    if (_settings['enabled'] == true) unawaited(sync(pull: false));
  }

  Future<void> disconnect() async {
    if (state.busy || MigrationMaintenance.active) return;
    await pause();
    _settings['enabled'] = false;
    await _save();
    _paused = false;
    _state();
  }

  Future<void> closeLibrary() async {
    final old = library;
    library = null;
    await old?.close();
    _api?.close();
    _api = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _paused = true;
    unawaited(closeLibrary());
    super.dispose();
  }
}

final metadataCloudProvider =
    StateNotifierProvider<MetadataCloudController, MetadataCloudState>(
        (ref) => MetadataCloudController(ref));

typedef CloudSelection = ({String platform, String selection, bool details});

/// Mounted cards request covers only. Selected details additionally request
/// screenshots/physical labels; trailer bodies are fetched only by playback.
final cloudSelectionMediaProvider = FutureProvider.autoDispose
    .family<String?, CloudSelection>((ref, selection) async {
  ref.watch(metadataCloudProvider.select((s) => (s.enabled, s.sourceId)));
  ref.watch(gameDbChangedProvider);
  ref.watch(metadataMediaRevisionProvider);
  final controller = ref.watch(metadataCloudProvider.notifier);
  await controller.ready;
  final cloud = controller.library;
  if (cloud == null || MigrationMaintenance.active) return null;
  final owner = Object();
  var active = true;
  ref.onDispose(() {
    active = false;
    cloud.release(owner);
  });
  final database = ref.read(libraryDbProvider).database;
  await ref.read(scopedMetadataReadinessProvider(selection.platform).future);
  final edition = await LibraryQuery(database)
      .editionForSelection(selection.platform, selection.selection);
  if (edition == null || !active) return null;
  final keys = <String>{};
  final images = <String, ({String provider, MetadataMedia media})>{};
  final regions = (await LibraryStore(database).edition(edition))?.regions ??
      const <String>[];
  for (final provider in ['screenscraper', 'romm']) {
    final record = await LibraryStore(database).metadata(edition, provider);
    if (record == null) continue;
    final media = MetadataArtworkCache.displayMedia(record,
        regions: regions, includePhysicalLabel: selection.details);
    for (final item in media.where((m) =>
        selection.details || {'box-2D', 'box-3D', 'cover'}.contains(m.type))) {
      final key = MetadataArtworkCache.key(item);
      keys.add(key);
      images[key] = (provider: provider, media: item);
    }
    if (selection.details)
      keys.addAll(MetadataArtworkCache.displayMedia(record, includeVideo: true)
          .where((m) => {'video', 'video-normalized'}.contains(m.type))
          .map(PreviewVideoCache.key));
  }
  await cloud.leaseMedia(owner, keys);
  try {
    final cache = await ref.read(cachedMetadataArtworkProvider);
    final missing = <String>{};
    for (final entry in images.entries) {
      if (!active) return null;
      if (await cache.fileFor(
              edition, entry.value.provider, entry.value.media) ==
          null) {
        missing.add(entry.key);
      }
    }
    // Locally verified images are ready independently of backup publication.
    // Only actual misses join the cloud owner; video downloads remain owned by
    // playback, while the existing leases protect all selected media.
    if (missing.isNotEmpty) {
      await cloud.publishSelection(edition, missing);
      await cloud.leaseMedia(owner, keys);
    }
    if (!active) {
      cloud.release(owner);
      return null;
    }
    for (final key in missing) {
      if (!active) break;
      await cloud.ensureMedia(key);
    }
    return active
        ? (await cache.artworkForEdition(edition,
                coverOnly: !selection.details))
            .cover
        : null;
  } catch (_) {
    return null;
  } finally {
    if (active) {
      for (final key in keys) {
        ref.watch(metadataMediaKeyRevisionProvider(key));
      }
    }
  } // Cache miss/offline keeps the existing fallback.
});
