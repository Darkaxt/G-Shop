import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/providers/metadata_providers.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
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

Future<Database> controlsDatabase({DatabaseFactory? factory}) async {
  if (factory == null) sqfliteFfiInit();
  final db = await (factory ?? databaseFactoryFfiNoIsolate)
      .openDatabase(inMemoryDatabasePath);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
