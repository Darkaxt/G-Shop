import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../services/metadata/igdb_provider.dart';
import '../services/metadata/metadata_credentials.dart';
import '../services/metadata/metadata_provider.dart';
import '../services/metadata/metadata_refresh_jobs.dart';
import '../services/metadata/screenscraper_provider.dart';
import 'library_providers.dart';

class MetadataControlsState {
  final String providerId;
  final bool loading, busy, error, accountConfigured, applicationConfigured;
  final List<String> systems;
  final MetadataRefreshReport? report;
  const MetadataControlsState(
      {this.providerId = 'screenscraper',
      this.loading = true,
      this.busy = false,
      this.error = false,
      this.accountConfigured = false,
      this.applicationConfigured = false,
      this.systems = const [],
      this.report});

  MetadataControlsState copyWith(
          {String? providerId,
          bool? loading,
          bool? busy,
          bool? error,
          bool? accountConfigured,
          bool? applicationConfigured,
          List<String>? systems,
          MetadataRefreshReport? report,
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
          report: clearReport ? null : report ?? this.report);
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
  Future<void>? _operation, _loading, _closing;
  bool _closed = false;
  bool _pauseRequested = false;

  MetadataControlsController(
      {required Future<Database> database,
      required Map<String, MetadataProvider> providers,
      required ScreenScraperCredentialStore screenScraperCredentials,
      required IgdbCredentialStore igdbCredentials,
      required void Function() catalogueChanged})
      : _database = database,
        _jobs = MetadataRefreshJobs(database),
        _providers = providers,
        _screenScraper = screenScraperCredentials,
        _igdb = igdbCredentials,
        _catalogueChanged = catalogueChanged,
        super(const MetadataControlsState());

  void _set(MetadataControlsState next) {
    if (!_closed && mounted) state = next;
  }

  Future<void> load() =>
      _loading ??= _load().whenComplete(() => _loading = null);
  Future<void> _load() async {
    try {
      final id = state.providerId;
      final db = await _database;
      final systems = await db.rawQuery(
          'SELECT DISTINCT systemSlug FROM games WHERE is_folder = 0 ORDER BY systemSlug');
      final account =
          id == 'screenscraper' && await _screenScraper.readUser() != null;
      final application = id == 'screenscraper'
          ? await _screenScraper.readDeveloper() != null
          : await _igdb.read() != null;
      final report = await _jobs.latest(providerId: id);
      _set(state.copyWith(
          loading: false,
          error: false,
          accountConfigured: account,
          applicationConfigured: application,
          systems:
              List.unmodifiable(systems.map((r) => r['systemSlug'] as String)),
          report: report,
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
            _set(state.copyWith(report: await _jobs.report(id)));
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
        await load();
      });

  Future<void> saveIgdb(IgdbCredentials credentials) => _perform(() async {
        await _igdb.save(credentials);
        await load();
      });

  Future<void> removeCredentials() => _perform(() async {
        if (state.providerId == 'screenscraper') {
          await _screenScraper.removeUser();
          await _screenScraper.removeDeveloper();
        } else {
          await _igdb.remove();
        }
        await load();
      });

  Future<void> refresh({String? systemSlug, int? cacheRowId}) =>
      _perform(() async {
        final job = await _jobs.createFromCatalogue(
            providerId: state.providerId,
            systemSlug: systemSlug,
            cacheRowId: cacheRowId);
        _set(state.copyWith(report: job));
        if (_closed) return;
        _catalogueChanged(); // Mark retained scores stale once, not per item/frame.
        await _run(job.id);
      });

  Future<void> resume() => _perform(() async {
        final id = state.report?.id;
        if (id != null) await _run(id);
      });

  Future<void> retryUnresolved() => _perform(() async {
        final id = state.report?.id;
        if (id == null) return;
        final job = await _jobs.retryUnresolved(id);
        _set(state.copyWith(report: job));
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
      final result = await _jobs.run(id, provider,
          recheckAccess: provider is MetadataAccessProvider,
          onProgress: (report) => _set(state.copyWith(report: report)));
      _set(state.copyWith(report: result));
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
      catalogueChanged: () => ref.read(gameDbChangedProvider.notifier).state++);
  unawaited(controller.load());
  return controller;
});
