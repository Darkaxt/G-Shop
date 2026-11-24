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
  final int? publicationCompleted, publicationTotal;
  const MetadataCloudState(
      {this.enabled = false,
      this.busy = false,
      this.sourceId,
      this.message,
      this.publicationCompleted,
      this.publicationTotal,
      this.budgetBytes = MetadataCloudLibrary.defaultBudgetBytes,
      this.cachedBytes = 0});

  double? get publicationFraction =>
      publicationCompleted == null || publicationTotal == null
          ? null
          : publicationTotal == 0
              ? 0
              : publicationCompleted! / publicationTotal!;
}

/// One foreground owner of the read-only catalogue reader and its media cache.
/// Clients never write the catalogue (spec revision 186); Windows publishes it.
class MetadataCloudController extends StateNotifier<MetadataCloudState> {
  final Ref ref;
  MetadataCloudLibrary? library;
  DriveMetadataApi? _api;
  Map<String, dynamic> _settings = {};
  bool _disposed = false, _paused = false;
  Future<void> _operation = Future.value();
  late final Future<void> ready = _load();
  MetadataCloudController(this.ref) : super(const MetadataCloudState()) {
    unawaited(ready);
  }
  void _state(
      {bool? busy,
      String? message,
      int? publicationCompleted,
      int? publicationTotal}) {
    if (_disposed) return;
    state = MetadataCloudState(
        enabled: _settings['enabled'] == true,
        busy: busy ?? state.busy,
        sourceId: _settings['source'] as String?,
        message: message,
        publicationCompleted: publicationCompleted,
        publicationTotal: publicationTotal,
        budgetBytes: (_settings['budget'] as int?) ??
            MetadataCloudLibrary.defaultBudgetBytes,
        cachedBytes: state.cachedBytes);
  }

  Future<void> _save() async => (await SharedPreferences.getInstance())
      .setString(metadataCloudSettingsKey, jsonEncode(_settings));
  void _failure(Object error, [StackTrace? trace]) {
    debugPrint(
        'Metadata cloud incomplete: ${error is DriveAuthorizationException ? error.issue.name : error.runtimeType}');
    if (error is FormatException) {
      debugPrint('Metadata catalogue: ${error.message}');
    }
    if (trace != null) {
      final sites = trace
          .toString()
          .split('\n')
          .where((line) => line.contains('package:g_shop/'))
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
              publicationCompleted: completed,
              publicationTotal: total,
              message: 'Reading catalogue: $completed/$total games'
                  '${total > 0 ? ' · ${completed * 100 ~/ total}%' : ''}');
          if (completed == 0 || completed == total || completed % 500 == 0)
            debugPrint('Metadata catalogue read: games=$completed/$total');
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
      await auth.acquire(expectedAccountId: drive.accountId, interactive: true);
      final api =
          DriveMetadataApi(authorization: auth, accountId: drive.accountId);
      try {
        final root = await api.findRoot();
        if (root == null) throw StateError('No catalogue folder in Drive');
        _settings = {
          'enabled': true,
          'source': source.id,
          'account': drive.accountId,
          'client': drive.serverClientId,
          'root': root.id,
          'budget': state.budgetBytes
        };
        await _save();
      } finally {
        api.close();
      }
      await _open();
      await library!.sync(ref.read(libraryDbProvider).database);
      if (!_disposed) ref.read(gameDbChangedProvider.notifier).state++;
      await refreshUsage();
      _state(busy: false, message: 'Catalogue is up to date');
    } catch (error, trace) {
      _failure(error, trace);
      _state(
          busy: false,
          message: error is StateError
              ? error.message
              : 'Could not read the catalogue. Retry when Drive is available.');
    }
  }

  Future<void> sync() {
    if (_paused ||
        state.busy ||
        _settings['enabled'] != true ||
        MigrationMaintenance.active) return Future.value();
    return _operation = _sync();
  }

  Future<void> _sync() async {
    if (_paused ||
        state.busy ||
        _settings['enabled'] != true ||
        MigrationMaintenance.active) return;
    _state(busy: true);
    try {
      await _open();
      await library!.sync(ref.read(libraryDbProvider).database);
      if (_paused) return;
      if (!_disposed) ref.read(gameDbChangedProvider.notifier).state++;
      await refreshUsage();
      debugPrint(
          'Metadata cloud sync completed: cachedBytes=${state.cachedBytes}');
      _state(busy: false, message: 'Catalogue is up to date');
    } catch (error, trace) {
      _failure(error, trace);
      _state(
          busy: false,
          message: 'Waiting for Drive. Local metadata remains available.');
    }
  }

  Future<void> refreshUsage() async {
    final bytes = await library?.cachedBytes() ?? 0;
    if (!_disposed)
      state = MetadataCloudState(
          enabled: _settings['enabled'] == true,
          sourceId: _settings['source'] as String?,
          busy: state.busy,
          message: state.message,
          publicationCompleted: state.publicationCompleted,
          publicationTotal: state.publicationTotal,
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

  Future<void> pause() async {
    _paused = true;
    await _operation;
    await closeLibrary();
    // A joined sync can return early while paused. Release its UI admission
    // state only after the owner is closed.
    _state(busy: false);
  }

  void resume() => _paused = false;

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
    // Only actual misses are fetched from the catalogue; video downloads
    // remain owned by playback, while the leases protect all selected media.
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
