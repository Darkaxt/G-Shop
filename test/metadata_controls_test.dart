import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/providers/metadata_providers.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MemorySecrets implements MetadataSecretStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class ControlsProvider implements MetadataProvider {
  final calls = <MetadataLookupRequest>[];
  final String id;
  bool closed = false;
  Future<MetadataLookupResult> Function(MetadataLookupRequest, CancelToken?)?
      reply;
  ControlsProvider([this.id = 'screenscraper']);
  @override
  String get providerId => id;
  @override
  MetadataProviderCapabilities get capabilities =>
      const MetadataProviderCapabilities(
          fields: {'titles'},
          verifiedIdLookup: true,
          rawRomLookup: false,
          titleSearch: true,
          documentedVoteCounts: false);
  @override
  Future<MetadataLookupResult> lookup(MetadataLookupRequest request,
      {CancelToken? cancelToken}) async {
    calls.add(request);
    return reply == null
        ? MetadataLookupResult(
            status: MetadataLookupStatus.unmatched, message: 'No match')
        : await reply!(request, cancelToken);
  }

  @override
  void close() => closed = true;
}

class ControlsArtworkProvider extends ControlsProvider
    implements MetadataArtworkProvider {
  int artworkCalls = 0;
  final bool includeScreenshot;
  Future<void> Function(CancelToken?)? onArtwork;
  MetadataLookupStatus artworkStatus = MetadataLookupStatus.matched;
  final media = MetadataMedia(
      type: 'box-2D',
      providerReference: ScreenScraperMediaReference(
          providerGameId: '42', providerPlatformId: 57, mediaType: 'box-2D'));
  final screenshot = MetadataMedia(
      type: 'ss',
      providerReference: ScreenScraperMediaReference(
          providerGameId: '42', providerPlatformId: 57, mediaType: 'ss'));
  ControlsArtworkProvider({this.includeScreenshot = false}) {
    reply = (request, _) async => MetadataLookupResult(
        status: MetadataLookupStatus.matched,
        message: 'Matched fixture',
        record: MetadataRecord(
            gameId: request.gameId,
            editionId: request.editionId,
            platformId: request.platformId,
            providerId: providerId,
            providerGameId: '42',
            retrievedAt: DateTime.now().toUtc(),
            refreshGeneration: request.refreshGeneration,
            matchMethod: 'platformAndTitle',
            titles: [MetadataText(text: request.title)],
            media: [media, if (includeScreenshot) screenshot]));
  }
  @override
  Future<MetadataLookupResult> fetchArtwork(MetadataMedia media,
      {required Future<void> Function(List<int>) write,
      CancelToken? cancelToken}) async {
    artworkCalls++;
    await onArtwork?.call(cancelToken);
    if (cancelToken?.isCancelled == true) {
      return MetadataLookupResult(
          status: MetadataLookupStatus.cancelled, message: 'Cancelled');
    }
    if (artworkStatus != MetadataLookupStatus.matched) {
      return MetadataLookupResult(
          status: artworkStatus, message: 'Fixture failure');
    }
    await write(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=='));
    return MetadataLookupResult(
        status: MetadataLookupStatus.matched, message: 'Fixture image');
  }
}

Future<Database> controlsDatabase(
    {DatabaseFactory? factory, String path = inMemoryDatabasePath}) async {
  if (factory == null) sqfliteFfiInit();
  final db = await (factory ?? databaseFactoryFfiNoIsolate).openDatabase(path);
  await LibrarySchema.install(db);
  await MetadataRefreshJobs.install(db);
  await db
      .execute('''CREATE TABLE games(id INTEGER PRIMARY KEY, systemSlug TEXT,
      displayName TEXT, filename TEXT, url TEXT, artifact_key TEXT,
      remote_artifact TEXT, is_folder INTEGER DEFAULT 0)''');
  for (final entry in [(1, 'psx'), (2, 'psp')]) {
    await db.insert('games', {
      'id': entry.$1,
      'systemSlug': entry.$2,
      'displayName': 'Game ${entry.$1}',
      'filename': 'Game ${entry.$1}.chd',
      'url': 'https://example.invalid/${entry.$1}'
    });
  }
  return db;
}

class _ThrowOnceCache extends MetadataArtworkCache {
  bool fail = true;
  _ThrowOnceCache(super.database, super.root);
  @override
  Future<({MetadataLookupResult result, MetadataArtworkBlob? blob})> download(
      MetadataMedia media,
      MetadataArtworkProvider provider,
      int workId,
      CancelToken cancel) {
    if (fail) {
      fail = false;
      throw StateError('private-secret');
    }
    return super.download(media, provider, workId, cancel);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('saved job selection resumes older pending work without repeating items',
      () async {
    final db = await controlsDatabase();
    final provider = ControlsProvider();
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {
          'screenscraper': provider,
          'igdb': ControlsProvider('igdb')
        },
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        catalogueChanged: () {});
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await db.close();
    });
    await controls.load();
    provider.reply = (_, __) async => MetadataLookupResult(
        status: provider.calls.length == 2
            ? MetadataLookupStatus.unavailable
            : MetadataLookupStatus.unmatched,
        message: 'Fixture');
    await controls.refresh();
    final older = controls.state.report!;
    final completedPlatform = provider.calls.first.platformId;
    final pendingPlatform = provider.calls.last.platformId;
    expect(older.counts['pending'], 1);
    expect(older.requested, 2);
    await controls.refresh(systemSlug: completedPlatform);
    final newer = controls.state.report!;
    expect(newer.id, isNot(older.id));
    final calls = provider.calls.length;
    final jobsBefore = (await db.query('metadata_refresh_jobs')).length;
    final List<MetadataRefreshReport> saved = await controls.savedJobs();
    expect(saved.map((j) => j.id), [newer.id, older.id]);
    await controls.selectSavedJob(older.id);
    expect(controls.state.report!.id, older.id);
    expect(controls.state.report!.generation, older.generation);
    expect(controls.state.report!.counts['pending'], 1);
    expect(provider.calls.length, calls);
    expect((await db.query('metadata_refresh_jobs')).length, jobsBefore);
    await controls.resume();
    expect(provider.calls.length, calls + 1);
    expect(provider.calls.last.platformId, pendingPlatform);
    expect(controls.state.report!.id, older.id);
    expect(controls.state.report!.state, 'completed');
    expect((await db.query('metadata_refresh_jobs')).length, jobsBefore);

    await controls.selectProvider('igdb');
    await controls.refresh(systemSlug: 'psp');
    final foreign = controls.state.report!.id;
    await controls.selectProvider('screenscraper');
    final selected = controls.state.report!.id;
    await controls.selectSavedJob(foreign);
    expect(controls.state.error, isTrue);
    expect(controls.state.report!.id, selected);
    expect(provider.calls.length, calls + 1);
    final artwork = await MetadataRefreshJobs(Future.value(db))
        .ensureArtworkForMetadata(selected);
    await controls.selectSavedJob(artwork.id);
    expect(controls.state.error, isTrue);
    expect(controls.state.report!.id, selected);
  });
  test('normal artwork pause joins transport and resumes the same linked job',
      () async {
    final db = await controlsDatabase();
    final root =
        await Directory.systemTemp.createTemp('rshop-controls-artwork-');
    final provider = ControlsArtworkProvider(includeScreenshot: true);
    final cache = MetadataArtworkCache(Future.value(db), root);
    MetadataControlsController controller(ControlsArtworkProvider p) =>
        MetadataControlsController(
            database: Future.value(db),
            providers: {'screenscraper': p},
            screenScraperCredentials:
                ScreenScraperCredentialStore(storage: MemorySecrets()),
            igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
            artworkCache: Future.value(cache),
            catalogueChanged: () {});
    var controls = controller(provider);
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await db.close();
      await root.delete(recursive: true);
    });
    await controls.load();
    final started = Completer<void>();
    provider.onArtwork = (cancel) async {
      started.complete();
      await cancel!.whenCancel;
    };
    final run = controls.refresh(systemSlug: 'psx');
    await started.future;
    await controls.pause();
    await run;
    expect(controls.state.report!.state, 'completed');
    expect(controls.state.artworkReport!.state, 'paused');
    expect(controls.state.artworkReport!.counts, {'pending': 2});
    final child = controls.state.artworkReport!.id;
    await controls.close();
    controls.dispose();
    final reopenedProvider = ControlsArtworkProvider(includeScreenshot: true);
    controls = controller(reopenedProvider);
    await controls.load();
    expect(controls.state.artworkReport!.id, child);
    await controls.resume();
    expect(controls.state.artworkReport!.id, child);
    expect(controls.state.artworkReport!.counts, {'matched': 2});
    expect(reopenedProvider.calls, isEmpty);
    expect(reopenedProvider.artworkCalls, 2);
  });
  test('artwork exception restores the child paused report, not running',
      () async {
    final db = await controlsDatabase();
    final provider = ControlsArtworkProvider();
    final root =
        await Directory.systemTemp.createTemp('rshop-controls-artwork-');
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        artworkCache: Future.value(_ThrowOnceCache(Future.value(db), root)),
        catalogueChanged: () {});
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await db.close();
      await root.delete(recursive: true);
    });
    await controls.load();
    await controls.refresh(systemSlug: 'psx');
    expect(controls.state.error, isTrue);
    expect(controls.state.report!.state, 'completed');
    expect(controls.state.artworkReport!.state, 'paused');
    expect(controls.state.artworkReport!.counts, {'pending': 1});
    await controls.resume();
    expect(controls.state.artworkReport!.counts, {'matched': 1});
    expect(provider.calls, hasLength(1));
  });
  test('explicit artwork retry preserves metadata lookup and completed images',
      () async {
    final db = await controlsDatabase();
    final provider = ControlsArtworkProvider(includeScreenshot: true);
    final root =
        await Directory.systemTemp.createTemp('rshop-controls-artwork-');
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        artworkCache:
            Future.value(MetadataArtworkCache(Future.value(db), root)),
        catalogueChanged: () {});
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await db.close();
      await root.delete(recursive: true);
    });
    await controls.load();
    provider.onArtwork = (_) async {
      provider.artworkStatus = provider.artworkCalls == 2
          ? MetadataLookupStatus.invalidResponse
          : MetadataLookupStatus.matched;
    };
    await controls.refresh(systemSlug: 'psx');
    final parent = controls.state.report!.id;
    final child = controls.state.artworkReport!.id;
    expect(controls.state.artworkReport!.counts,
        {'matched': 1, 'invalidResponse': 1});
    provider.onArtwork = null;
    provider.artworkStatus = MetadataLookupStatus.matched;
    await controls.retryUnresolved();
    expect(controls.state.report!.id, parent);
    expect(controls.state.artworkReport!.id, isNot(child));
    expect(controls.state.artworkReport!.counts, {'matched': 1});
    expect(provider.calls, hasLength(1));
    expect(provider.artworkCalls, 3,
        reason: 'The successful cover is not retried');
  });
  test('normal refresh publishes owned artwork without another game lookup',
      () async {
    final db = await controlsDatabase();
    final provider = ControlsArtworkProvider();
    final root =
        await Directory.systemTemp.createTemp('rshop-controls-artwork-');
    final cache = MetadataArtworkCache(Future.value(db), root);
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        artworkCache: Future.value(cache),
        catalogueChanged: () {});
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await db.close();
      await root.delete(recursive: true);
    });
    await controls.load();
    await controls.refresh(systemSlug: 'psx');
    expect(controls.state.report!.counts, {'matched': 1});
    expect(provider.calls, hasLength(1));
    expect(provider.artworkCalls, 1,
        reason:
            'Normal refresh must publish the matched cover, not only JSON.');
    expect(controls.state.artworkReport!.counts, {'matched': 1});
    final edition = provider.calls.single.editionId;
    expect(await cache.fileFor(edition, provider.providerId, provider.media),
        isNotNull);
    final child = controls.state.artworkReport!.id;
    await controls.resume();
    expect(controls.state.artworkReport!.id, child);
    expect(provider.calls, hasLength(1));
    expect(provider.artworkCalls, 1);
  });
  test(
      'normal review explicitly corrects an identity then verifies publication',
      () async {
    final db = await controlsDatabase();
    final provider = ControlsProvider();
    provider.reply = (request, _) async => MetadataLookupResult(
            status: MetadataLookupStatus.needsReview,
            message: 'Review',
            candidates: [
              MetadataLookupCandidate(
                  providerGameId: '42',
                  platformId: request.platformId,
                  titles: [MetadataText(text: request.title)],
                  titleMatched: true,
                  evidence: 'platformAndTitle')
            ]);
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        catalogueChanged: () {});
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await db.close();
    });
    await controls.load();
    await controls.refresh();
    final reviews = await controls.reviewQueue();
    expect(reviews, hasLength(2));
    expect(provider.calls, hasLength(2),
        reason: 'Review reads cached candidates only.');
    await controls.acceptReview(reviews.first,
        providerGameId: 'unoffered', contentTags: {'official'});
    expect(controls.state.error, isTrue);
    expect(await controls.reviewQueue(), hasLength(2));
    provider.reply = (request, _) async => MetadataLookupResult(
        status: MetadataLookupStatus.matched,
        message: 'Verified',
        record: MetadataRecord(
            gameId: request.gameId,
            editionId: request.editionId,
            platformId: request.platformId,
            providerId: 'screenscraper',
            providerGameId: request.verifiedProviderGameId!,
            retrievedAt: DateTime.now().toUtc(),
            refreshGeneration: request.refreshGeneration,
            matchMethod: 'verifiedProviderId',
            titles: [MetadataText(text: request.title)]));
    await controls.acceptReview(reviews.first,
        providerGameId: '42', contentTags: {'T-Eng', 'Undub', 'Uncensor'});
    expect(controls.state.error, isFalse);
    expect(controls.state.report!.counts, {'matched': 1});
    expect(provider.calls.last.verifiedProviderGameId, '42');
    expect(provider.calls.last.contentTags, {'T-Eng', 'Undub', 'Uncensor'});
    expect((await controls.reviewQueue()).single.editionId,
        reviews.last.editionId);
    final saved = await LibraryStore(Future.value(db))
        .metadata(reviews.first.editionId, 'screenscraper');
    expect(saved!.providerGameId, '42');
  });
  test('pause during snapshot creation prevents starting provider work',
      () async {
    final db = await controlsDatabase();
    final provider = ControlsProvider();
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        catalogueChanged: () {});
    await controls.load();
    final running = controls.refresh();
    await controls.pause();
    await running;
    expect(provider.calls, isEmpty);
    expect(controls.state.report!.state, 'paused');
    await controls.resume();
    expect(controls.state.report!.state, 'completed');
    await controls.close();
    controls.dispose();
    await db.close();
  });
  test('normal catalogue controls pause, restore and resume the same snapshot',
      () async {
    final db = await controlsDatabase();
    final secrets = MemorySecrets();
    final ss = ScreenScraperCredentialStore(storage: secrets);
    final igdb = IgdbCredentialStore(storage: secrets);
    final provider = ControlsProvider();
    var changes = 0;
    MetadataControlsController controller() => MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials: ss,
        igdbCredentials: igdb,
        catalogueChanged: () => changes++);
    var controls = controller();
    await controls.load();
    expect(controls.state.systems, ['psp', 'psx']);
    expect(provider.calls, isEmpty, reason: 'opening settings is cache only');
    await controls.saveScreenScraper(const ScreenScraperUserCredentials(
        username: 'fixture-user', password: 'fixture-password'));
    expect(controls.state.accountConfigured, isTrue);
    expect(controls.state.applicationConfigured, isFalse);
    expect(provider.calls, isEmpty,
        reason: 'saving does not silently authenticate');
    final started = Completer<void>();
    provider.reply = (request, token) async {
      started.complete();
      await token!.whenCancel;
      return MetadataLookupResult(
          status: MetadataLookupStatus.cancelled, message: 'Cancelled');
    };
    final running = controls.refresh(systemSlug: 'psx');
    await started.future;
    final id = controls.state.report!.id;
    expect(controls.state.busy, isTrue);
    await controls.pause();
    await running;
    expect(controls.state.report!.state, 'paused');
    expect(controls.state.report!.counts, {'pending': 1});
    await controls.close();
    controls.dispose();
    provider.reply = null;
    controls = controller();
    await controls.load();
    expect(controls.state.report!.id, id);
    await controls.resume();
    expect(controls.state.report!.id, id);
    expect(controls.state.report!.state, 'completed');
    expect(controls.state.report!.counts, {'unmatched': 1});
    expect(controls.state.report!.rated, 0,
        reason: 'completed traversal is not rated coverage');
    expect(provider.calls.every((r) => r.platformId == 'psx'), isTrue);
    await controls.retryUnresolved();
    expect(controls.state.report!.id, isNot(id));
    await controls.refresh(cacheRowId: 2, systemSlug: 'psp');
    expect(provider.calls.last.platformId, 'psp');
    expect(changes, greaterThan(0));
    await controls.close();
    controls.dispose();
    await db.close();
  });

  test('provider exception is redacted and shutdown joins its cancellation',
      () async {
    final db = await controlsDatabase();
    final provider = ControlsProvider();
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        catalogueChanged: () {});
    await controls.load();
    provider.reply =
        (_, __) async => throw StateError('password=private-secret');
    await controls.refresh(systemSlug: 'psx');
    expect(controls.state.error, isTrue);
    expect('${controls.state}', isNot(contains('private-secret')));
    expect(controls.state.report!.state, 'paused');
    final started = Completer<void>();
    final release = Completer<void>();
    provider.reply = (_, token) async {
      started.complete();
      await token!.whenCancel;
      await release.future;
      return MetadataLookupResult(
          status: MetadataLookupStatus.cancelled, message: 'Cancelled');
    };
    final run = controls.resume();
    await started.future;
    var joined = false;
    final close = controls.close().then((_) => joined = true);
    await Future<void>.value();
    expect(joined, isFalse);
    expect(provider.closed, isFalse);
    release.complete();
    await close;
    await run;
    expect(provider.closed, isTrue);
    controls.dispose();
    await db.close();
  });

  test('database diagnostics retain result codes but redact SQL and values',
      () async {
    final db = await controlsDatabase();
    final provider = ControlsProvider();
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        catalogueChanged: () {});
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await db.close();
    });
    await controls.load();
    final messages = <String>[];
    final previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() => debugPrint = previousPrint);
    provider.reply = (_, __) async {
      await db.rawQuery('SELECT * FROM PRIVATE_DIAGNOSTIC_MARKER');
      throw StateError('Unreachable');
    };
    await controls.refresh(systemSlug: 'psx');
    expect(controls.state.error, isTrue);
    expect(controls.state.report!.state, 'paused');
    expect(messages.join('\n'), contains('Metadata database result code: 1'));
    expect(messages.join('\n'), isNot(contains('PRIVATE_DIAGNOSTIC_MARKER')));
    expect(messages.join('\n'), isNot(contains('SELECT *')));
  });

  test('a failed lookup during pause still joins and closes provider resources',
      () async {
    final db = await controlsDatabase();
    final provider = ControlsProvider();
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        catalogueChanged: () {});
    await controls.load();
    final started = Completer<void>();
    provider.reply = (_, token) async {
      started.complete();
      await token!.whenCancel;
      throw StateError('private transport error');
    };
    final run = controls.refresh(systemSlug: 'psx');
    await started.future;
    await controls.pause();
    await run;
    expect(controls.state.error, isTrue);
    expect(controls.state.report!.state, 'paused');
    await controls.close();
    expect(provider.closed, isTrue);
    controls.dispose();
    await db.close();
  });
}
