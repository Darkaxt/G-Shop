import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import '../services/metadata/igdb_provider.dart';
import '../services/metadata/metadata_credentials.dart';
import '../services/metadata/metadata_artwork_cache.dart';
import '../services/metadata/metadata_provider.dart';
import '../services/metadata/metadata_refresh_jobs.dart';
import '../services/metadata/screenscraper_provider.dart';
import '../services/metadata/shared_metadata_store.dart';
import '../services/metadata/es_de_metadata_publication.dart';
import '../models/config/app_config.dart';
import '../models/config/provider_config.dart';
import '../models/library_identity.dart';
import '../services/source_resolver.dart';
import '../services/drive/drive_runtime.dart';
import 'app_providers.dart' show configStorageServiceProvider;
import 'library_providers.dart';

/// Use only the existing enabled, exact account/source/platform mapping. Never
/// borrow a different source's grant or broaden the configured folder boundary.
ProviderConfig? metadataHeaderSource(
    AppConfig? config, RemoteArtifact artifact, String platformId) {
  final systems = config?.systems.where((s) => s.id == platformId).toList();
  if (systems?.length != 1) return null;
  final sources = SourceResolver.providersFor(systems!.single, config!.sources)
      .where((p) =>
          p.type == ProviderType.drive &&
          p.sourceId == artifact.id.sourceId &&
          p.drive?.accountId == artifact.id.accountId &&
          p.drive?.isConfigured == true &&
          p.path?.isNotEmpty == true)
      .toList();
  return sources.length == 1 ? sources.single : null;
}

class MetadataControlsState {
  final String providerId;
  final bool loading, busy, error, accountConfigured, applicationConfigured;
  final List<String> systems;
  final MetadataRefreshReport? report;
  final MetadataRefreshReport? artworkReport;
  final String? sharedDirectory;
  final bool sharedStorageUnavailable;
  final EsDePublicationResult? esDeReport;
  final List<String> esDeTargets;
  const MetadataControlsState(
      {this.providerId = 'screenscraper',
      this.loading = true,
      this.busy = false,
      this.error = false,
      this.accountConfigured = false,
      this.applicationConfigured = false,
      this.systems = const [],
      this.report,
      this.artworkReport,
      this.sharedDirectory,
      this.sharedStorageUnavailable = false,
      this.esDeReport,
      this.esDeTargets = const []});

  MetadataControlsState copyWith(
          {String? providerId,
          bool? loading,
          bool? busy,
          bool? error,
          bool? accountConfigured,
          bool? applicationConfigured,
          List<String>? systems,
          MetadataRefreshReport? report,
          MetadataRefreshReport? artworkReport,
          String? sharedDirectory,
          bool? sharedStorageUnavailable,
          EsDePublicationResult? esDeReport,
          List<String>? esDeTargets,
          bool clearArtworkReport = false,
          bool clearReport = false}) =>
      MetadataControlsState(
          providerId: providerId ?? this.providerId,
          loading: loading ?? this.loading,
          busy: busy ?? this.busy,
          error: error ?? this.error,
          accountConfigured: accountConfigured ?? this.accountConfigured,
          applicationConfigured:
              applicationConfigured ?? this.applicationConfigured,
          systems: systems ?? this.systems,
          sharedDirectory: sharedDirectory ?? this.sharedDirectory,
          sharedStorageUnavailable:
              sharedStorageUnavailable ?? this.sharedStorageUnavailable,
          esDeReport: esDeReport ?? this.esDeReport,
          esDeTargets: esDeTargets ?? this.esDeTargets,
          report: clearReport ? null : report ?? this.report,
          artworkReport: clearReport || clearArtworkReport
              ? null
              : artworkReport ?? this.artworkReport);
}

/// One app-scoped worker for normal settings and exact game-details controls.
/// Opening a screen reads only secure configuration and one durable local job.
class MetadataControlsController extends StateNotifier<MetadataControlsState> {
  final Future<Database> _database;
  final MetadataRefreshJobs _jobs;
  final Map<String, MetadataProvider> _providers;
  final ScreenScraperCredentialStore _screenScraper;
  final IgdbCredentialStore _igdb;
  final void Function() _catalogueChanged;
  final Future<MetadataArtworkCache>? _artworkCache;
  final Future<SharedMetadataStore?>? _sharedStore;
  final Future<String?> Function(String systemId)? _configuredTarget;
  Future<void>? _operation, _loading, _closing;
  bool _closed = false;
  bool _pauseRequested = false;

  MetadataControlsController(
      {required Future<Database> database,
      required Map<String, MetadataProvider> providers,
      required ScreenScraperCredentialStore screenScraperCredentials,
      required IgdbCredentialStore igdbCredentials,
      Future<MetadataArtworkCache>? artworkCache,
      Future<SharedMetadataStore?>? sharedStore,
      Future<Uint8List?> Function(RemoteArtifact, String, CancelToken)?
          readRomHeader,
      Future<String?> Function(String systemId)? configuredTarget,
      required void Function() catalogueChanged})
      : _database = database,
        _jobs = MetadataRefreshJobs(database,
            sharedStore: sharedStore, readRomHeader: readRomHeader),
        _providers = providers,
        _screenScraper = screenScraperCredentials,
        _igdb = igdbCredentials,
        _catalogueChanged = catalogueChanged,
        _artworkCache = artworkCache,
        _sharedStore = sharedStore,
        _configuredTarget = configuredTarget,
        super(const MetadataControlsState()) {
    // These owned futures can fail before load reaches them (or before an artwork
    // action is selected). Observe early completion without replacing the future:
    // load/run still await and report the original failure. Otherwise an ordinary
    // unavailable store escapes as an unhandled asynchronous application error.
    _sharedStore?.ignore();
    _artworkCache?.ignore();
  }

  void _set(MetadataControlsState next) {
    if (!_closed && mounted) state = next;
  }

  Future<void> load() =>
      _loading ??= _load().whenComplete(() => _loading = null);
  Future<void> _load() async {
    try {
      final id = state.providerId;
      final db = await _database;
      var sharedUnavailable = false;
      if (_sharedStore != null) {
        final prefs = await SharedPreferences.getInstance();
        _set(state.copyWith(
            sharedDirectory: prefs.getString(sharedMetadataDirectoryKey)));
        try {
          final store = await _sharedStore;
          await store?.restore(db);
          _set(state.copyWith(
              esDeTargets: await store?.esDeTargets() ?? const []));
        } catch (_) {
          // Shared storage is not the source of credentials, catalogue membership
          // or committed private job progress. Preserve those independent reads
          // and expose the storage failure; do not redirect any worker writes.
          sharedUnavailable = true;
        }
      }
      final systems = await db.rawQuery(
          'SELECT DISTINCT systemSlug FROM games WHERE is_folder = 0 ORDER BY systemSlug');
      final account =
          id == 'screenscraper' && await _screenScraper.readUser() != null;
      final application = id == 'screenscraper'
          ? await _screenScraper.readDeveloper() != null
          : await _igdb.read() != null;
      final report = await _jobs.latest(providerId: id);
      final artwork =
          report == null ? null : await _jobs.artworkForMetadata(report.id);
      _set(state.copyWith(
          loading: false,
          error: sharedUnavailable,
          sharedStorageUnavailable: sharedUnavailable,
          accountConfigured: account,
          applicationConfigured: application,
          systems:
              List.unmodifiable(systems.map((r) => r['systemSlug'] as String)),
          report: report,
          artworkReport: artwork,
          clearArtworkReport: artwork == null,
          clearReport: report == null));
    } catch (_) {
      _set(state.copyWith(loading: false, error: true));
    }
  }

  Future<void> selectProvider(String id) async {
    if (_closed || state.busy || state.loading || !_providers.containsKey(id)) {
      return;
    }
    _set(state.copyWith(providerId: id, loading: true, clearReport: true));
    await load();
  }

  Future<List<MetadataRefreshReport>> savedJobs({int? beforeId}) async {
    if (_closed || state.busy || state.loading) {
      throw StateError('Metadata controls are unavailable');
    }
    final providerId = state.providerId;
    final page =
        await _jobs.savedJobs(providerId: providerId, beforeId: beforeId);
    if (_closed || state.providerId != providerId) {
      throw StateError('Metadata provider changed');
    }
    return page;
  }

  /// Select only; explicit Resume owns all provider/network work.
  Future<void> selectSavedJob(int id) => _perform(() async {
        final report = await _jobs.report(id);
        if (report.providerId != state.providerId ||
            report.kind != 'metadata') {
          throw StateError('Saved job does not belong to this provider');
        }
        final artwork = await _jobs.artworkForMetadata(id);
        _set(state.copyWith(
            report: report,
            artworkReport: artwork,
            clearArtworkReport: artwork == null));
      });

  Future<void> _perform(Future<void> Function() action) {
    if (_closed || state.busy || state.loading) return Future.value();
    _pauseRequested = false;
    _set(state.copyWith(busy: true, error: false));
    return _operation = () async {
      try {
        await action();
      } catch (_) {
        // Neither transport exceptions nor secure values belong in UI state.
        final id = state.report?.id;
        if (id != null) {
          try {
            _set(state.copyWith(
                report: await _jobs.report(id),
                artworkReport: await _jobs.artworkForMetadata(id)));
          } catch (_) {/* Retain last committed progress on storage failure. */}
        }
        _set(state.copyWith(error: true));
      } finally {
        _set(state.copyWith(busy: false));
        _operation = null;
      }
    }();
  }

  Future<void> saveScreenScraper(ScreenScraperUserCredentials? user,
          {ScreenScraperDeveloperCredentials? application}) =>
      _perform(() async {
        if (application != null) {
          await _screenScraper.saveDeveloper(application);
        }
        if (user != null) await _screenScraper.saveUser(user);
        await _jobs.clearQuotaObservation('screenscraper');
        await load();
      });

  Future<void> saveIgdb(IgdbCredentials credentials) => _perform(() async {
        await _igdb.save(credentials);
        await _jobs.clearQuotaObservation('igdb');
        await load();
      });

  Future<void> removeCredentials() => _perform(() async {
        if (state.providerId == 'screenscraper') {
          await _screenScraper.removeUser();
          await _screenScraper.removeDeveloper();
        } else {
          await _igdb.remove();
        }
        await _jobs.clearQuotaObservation(state.providerId);
        await load();
      });

  /// The picker and migration occupy the same app-scoped worker as refresh.
  /// Commit the selected path only after existing facts/blobs are preserved and
  /// recoverable; cancellation or storage failure leaves the old choice intact.
  /// Caller invalidates cache/controller providers only after this Future joins.
  Future<void> selectSharedStorage(Future<Directory?> Function() choose,
          {DatabaseFactory? factory}) =>
      _perform(() async {
        final selected = await choose();
        if (selected == null || _closed || _pauseRequested) return;
        final selectedPath = p.normalize(selected.absolute.path);
        if (Platform.isAndroid &&
            (!selectedPath.startsWith('/storage/') ||
                RegExp(r'/Android/(data|obb)(/|$)').hasMatch(selectedPath))) {
          throw StateError(
              'Select shared storage outside app-scoped directories');
        }
        final target = await SharedMetadataStore.open(
            Directory(p.join(selectedPath, 'RShopMetadata')),
            factory: factory);
        try {
          final db = await _database;
          final prefs = await SharedPreferences.getInstance();
          final previous = prefs.getString(sharedMetadataDirectoryKey);
          // Re-grant/reconnect does not await a permanently failed old Future.
          // Its recorded directory is explicit; absent bodies remain preserved
          // as unavailable rather than borrowed from another guessed location.
          final cache = previous == null
              ? await (_artworkCache ?? MetadataArtworkCache.open(_database))
              : MetadataArtworkCache(
                  _database, Directory(p.join(previous, 'artwork')));
          await target.migrate(db, cache);
          await target.restore(db);
          if (_closed || _pauseRequested) return;
          if (!await prefs.setString(
              sharedMetadataDirectoryKey, target.root.path)) {
            throw StateError('Shared directory selection could not be saved');
          }
          _set(state.copyWith(
              sharedDirectory: target.root.path,
              sharedStorageUnavailable: false));
          _catalogueChanged();
        } finally {
          await target.close();
        }
      });

  Future<void> refresh({String? systemSlug, int? cacheRowId}) =>
      _perform(() async {
        final job = await _jobs.createFromCatalogue(
            providerId: state.providerId,
            systemSlug: systemSlug,
            cacheRowId: cacheRowId);
        _set(state.copyWith(report: job, clearArtworkReport: true));
        if (_closed) return;
        _catalogueChanged(); // Mark retained scores stale once, not per item/frame.
        await _run(job.id);
      });

  Future<void> mapEsDeEdition(
          {required int cacheRowId,
          required String editionId,
          required Directory romRoot,
          Directory? mediaRoot,
          required File gamelist}) =>
      _perform(() async {
        final store = await _sharedStore;
        final db = await _database;
        final rows = await db.query('games',
            columns: ['systemSlug'], where: 'id = ?', whereArgs: [cacheRowId]);
        if (rows.length != 1) throw StateError('Missing catalogue item');
        final destination =
            await _configuredTarget?.call(rows.single['systemSlug'] as String);
        if (destination == null || store == null) {
          throw StateError(
              'Shared storage and configured installation are required');
        }
        await store.mapEsDeEdition(db,
            cacheRowId: cacheRowId,
            editionId: editionId,
            providerId: state.providerId,
            installRoot: Directory(destination),
            romRoot: romRoot,
            mediaRoot: mediaRoot,
            gamelist: gamelist);
        _set(state.copyWith(esDeTargets: await store.esDeTargets()));
      });

  Future<void> publishEsDe(File gamelist, {required bool esDeClosed}) =>
      _perform(() async {
        final store = await _sharedStore;
        if (store == null || _configuredTarget == null) {
          throw StateError('ES-DE mapping is unavailable');
        }
        _set(state.copyWith(
            esDeReport: await store.publishEsDe(await _database, gamelist,
                esDeClosed: esDeClosed,
                rebasePrepared: {'fileChanged', 'pendingChanged'}
                    .contains(state.esDeReport?.status),
                configuredTarget: _configuredTarget!)));
      });

  Future<void> reviewEsDeArtwork(
          {required String editionId, required File source}) =>
      _perform(() async {
        final store = await _sharedStore;
        final cache = await _artworkCache;
        if (store == null || cache == null || _configuredTarget == null) {
          throw StateError(
              'Shared artwork and exact ES-DE mapping are required');
        }
        await store.reviewEsDeArtwork(await _database, cache,
            editionId: editionId,
            providerId: state.providerId,
            image: source,
            configuredTarget: _configuredTarget!);
        _catalogueChanged();
      });

  Future<void> rediscoverMatch(
          {required int cacheRowId, required String editionId}) =>
      _perform(() async {
        final job = await _jobs.createMatchReview(
            providerId: state.providerId,
            cacheRowId: cacheRowId,
            editionId: editionId);
        _set(state.copyWith(report: job, clearArtworkReport: true));
        if (_closed) return;
        _catalogueChanged();
        await _run(job.id);
      });

  Future<void> resume() => _perform(() async {
        final id = state.report?.id;
        if (id != null) await _run(id);
      });

  Future<void> retryUnresolved() => _perform(() async {
        final id = state.report?.id;
        if (id == null) return;
        const outcomes = {
          'unmatched',
          'invalidRequest',
          'invalidResponse',
          'unsupportedPlatform',
          'identityChanged'
        };
        final metadataPending =
            outcomes.any((s) => (state.report!.counts[s] ?? 0) > 0);
        if (!metadataPending &&
            state.artworkReport != null &&
            outcomes.any((s) => (state.artworkReport!.counts[s] ?? 0) > 0)) {
          final images = await _jobs.retryArtworkForMetadata(id);
          _set(state.copyWith(artworkReport: images));
          await _run(id);
          return;
        }
        final job = await _jobs.retryUnresolved(id);
        _set(state.copyWith(report: job, clearArtworkReport: true));
        if (_closed) return;
        _catalogueChanged();
        await _run(job.id);
      });

  /// Read bounded cached review outcomes; never start provider or ROM requests.
  Future<List<MetadataReviewItem>> reviewQueue(
          {String afterEditionId = '',
          int limit = 50,
          String? systemSlug,
          String? editionId,
          int? cacheRowId}) =>
      _jobs.reviewQueue(state.providerId,
          afterEditionId: afterEditionId,
          limit: limit,
          systemSlug: systemSlug,
          editionId: editionId,
          cacheRowId: cacheRowId);

  Future<void> acceptReview(MetadataReviewItem item,
          {required String providerGameId,
          required Set<String> contentTags,
          String? reviewedRegion}) =>
      _perform(() async {
        final original = await _jobs.report(item.jobId);
        if (original.providerId != state.providerId) {
          throw StateError('Review belongs to another metadata provider');
        }
        final job = await _jobs.acceptCandidate(item.jobId,
            editionId: item.editionId,
            providerGameId: providerGameId,
            contentTags: contentTags,
            reviewedRegion: reviewedRegion);
        _set(state.copyWith(report: job, clearArtworkReport: true));
        if (_closed) return;
        _catalogueChanged();
        await _run(job.id);
      });

  Future<void> _run(int id) async {
    // Snapshot publication can still be in flight before the job runner owns
    // its cancellation token. Preserve that pause intent across this boundary.
    if (_closed || _pauseRequested) return;
    final provider = _providers[state.providerId]!;
    try {
      final cache = _artworkCache == null ? null : await _artworkCache;
      if (_closed || _pauseRequested) return;
      final result = await _jobs.run(id, provider,
          artworkCache: cache,
          recheckAccess: provider is MetadataAccessProvider,
          onProgress: (report) => _set(state.copyWith(report: report)));
      _set(state.copyWith(report: result));
      if (result.state == 'completed' &&
          provider is MetadataArtworkProvider &&
          !_closed &&
          !_pauseRequested) {
        final cache =
            await (_artworkCache ?? MetadataArtworkCache.open(_database));
        if (_closed || _pauseRequested) return;
        final artwork = await _jobs.ensureArtworkForMetadata(id);
        _set(state.copyWith(artworkReport: artwork));
        if (_closed || _pauseRequested) return;
        final images = await _jobs.run(artwork.id, provider,
            artworkCache: cache,
            recheckAccess: artwork.state != 'completed' &&
                provider is MetadataAccessProvider &&
                artwork.blockedStatus != null,
            onProgress: (report) =>
                _set(state.copyWith(artworkReport: report)));
        _set(state.copyWith(artworkReport: images));
        _set(state.copyWith(report: await _jobs.report(id)));
      }
    } finally {
      if (!_closed) _catalogueChanged();
    }
  }

  Future<void> pause() async {
    _pauseRequested = true;
    try {
      await _jobs.pause();
    } catch (_) {
      // The owning operation records the failed lookup; pause still joins it.
      _set(state.copyWith(error: true));
    }
    await _operation;
  }

  /// Join in-flight storage/network work before closing its adapters.
  Future<void> close() => _closing ??= () async {
        _closed = true;
        await pause();
        await _loading;
        for (final provider in _providers.values) {
          provider.close();
        }
      }();

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

final metadataControlsProvider =
    StateNotifierProvider<MetadataControlsController, MetadataControlsState>(
        (ref) {
  final ss = ScreenScraperCredentialStore();
  final igdb = IgdbCredentialStore();
  final controller = MetadataControlsController(
      database: ref.watch(libraryDbProvider).database,
      providers: {
        'screenscraper': ScreenScraperProvider(
            readDeveloperCredentials: ss.readDeveloper,
            readUserCredentials: ss.readUser),
        'igdb': IgdbMetadataProvider(readCredentials: igdb.read),
      },
      screenScraperCredentials: ss,
      igdbCredentials: igdb,
      artworkCache: ref.watch(metadataArtworkCacheProvider),
      sharedStore: ref.watch(sharedMetadataStoreProvider),
      readRomHeader: (artifact, platformId, cancel) async {
        final config =
            await ref.read(configStorageServiceProvider).loadConfig();
        final source = metadataHeaderSource(config, artifact, platformId);
        if (source == null) return null;
        return DriveRuntime.instance.readMetadataHeader(
            config: source, artifact: artifact, cancellation: cancel);
      },
      configuredTarget: (systemId) async {
        final config =
            await ref.read(configStorageServiceProvider).loadConfig();
        final systems = config?.systems.where((s) => s.id == systemId).toList();
        return systems?.length == 1 ? systems!.single.targetFolder : null;
      },
      catalogueChanged: () => ref.read(gameDbChangedProvider.notifier).state++);
  unawaited(controller.load());
  return controller;
});
