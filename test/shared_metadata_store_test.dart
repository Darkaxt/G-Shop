import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_eshop/providers/metadata_providers.dart';
import 'package:retro_eshop/providers/library_providers.dart';
import 'package:retro_eshop/providers/game_providers.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/services/storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/metadata/shared_metadata_store.dart';
import 'package:retro_eshop/services/metadata/effective_overall_rating.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi/src/database_factory_ffi_io.dart';
import 'package:sqflite_common_ffi/src/sqflite_import.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'metadata_controls_test.dart'
    show controlsDatabase, ControlsArtworkProvider, MemorySecrets;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('normal settings joins library recovery until catalogue invalidation',
      () async {
    sqfliteFfiInit();
    var passes = 0;
    Completer<void>? entered, release;
    final factory = buildDatabaseFactory(
        tag: 'shared-settings-recovery',
        invokeMethod: (method, [arguments]) async {
          if (arguments is Map &&
              (arguments['sql'] as String? ?? '')
                  .contains('CREATE TEMP TABLE shared_metadata_catalogue')) {
            passes++;
            if (entered != null && !entered.isCompleted) {
              entered.complete();
              await release!.future;
            }
          }
          return ffiMethodCallHandleNoIsolate(FfiMethodCall(method, arguments));
        });
    final db = await controlsDatabase(factory: factory);
    final root =
        await Directory.systemTemp.createTemp('rshop-settings-recovery-');
    final shared = await SharedMetadataStore.open(root, factory: factory);
    FlutterSecureStorage.setMockInitialValues({});
    final container = ProviderContainer(overrides: [
      libraryDbProvider.overrideWithValue(_SharedFixtureDatabase(db)),
      sharedMetadataStoreProvider.overrideWithValue(Future.value(shared)),
    ]);
    final subscription =
        container.listen(sharedMetadataProjectionProvider, (_, __) {});
    final controls = container.read(metadataControlsProvider.notifier);
    addTearDown(() async {
      await controls.close();
      subscription.close();
      container.dispose();
      await shared.close();
      await db.close();
      await root.delete(recursive: true);
    });
    await controls.load();
    await container.read(sharedMetadataProjectionProvider.future);
    await controls.load();
    expect(passes, 1,
        reason: 'Reopening settings must not repeat the library pass');
    entered = Completer<void>();
    release = Completer<void>();
    container.read(gameDbChangedProvider.notifier).state++;
    final firstChange = container.read(sharedMetadataProjectionProvider.future);
    await entered.future;
    // A second real catalogue notification while recovery is active must not
    // join its older pinned snapshot, even though unchanged settings do join it.
    container.read(gameDbChangedProvider.notifier).state++;
    final secondChange =
        container.read(sharedMetadataProjectionProvider.future);
    release.complete();
    await Future.wait([firstChange, secondChange]);
    await controls.load();
    expect(passes, 3,
        reason: 'Actual catalogue changes still require fresh recovery');
    expect(controls.state.loading, false);
    expect(controls.state.sharedStorageUnavailable, false);
  });

  test('artwork recovery publishes validated manifests in bounded transactions',
      () async {
    sqfliteFfiInit();
    var observe = false, uncommittedWrites = 0;
    final pageSizes = <int>[];
    final factory = buildDatabaseFactory(
        tag: 'shared-artwork-recovery',
        invokeMethod: (method, [arguments]) async {
          if (observe && method == 'batch' && arguments is Map) {
            final operations = arguments['operations'] as List;
            final artwork = operations.where((op) =>
                ((op as Map)['sql'] as String? ?? '')
                    .contains('INTO metadata_artwork_cache'));
            if (artwork.isNotEmpty) {
              expect(arguments['transactionId'], isNotNull);
              pageSizes.add(artwork.length);
            }
          }
          if (observe &&
              arguments is Map &&
              (arguments['sql'] as String? ?? '')
                  .contains('INTO metadata_artwork_cache') &&
              arguments['transactionId'] == null) {
            uncommittedWrites++;
          }
          return ffiMethodCallHandleNoIsolate(FfiMethodCall(method, arguments));
        });
    final db = await controlsDatabase(factory: factory);
    final root = await Directory.systemTemp.createTemp('rshop-artwork-pages-');
    final shared = await SharedMetadataStore.open(root, factory: factory);
    addTearDown(() async {
      await shared.close();
      await db.close();
      await root.delete(recursive: true);
    });
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==');
    final filename = '${sha256.convert(bytes)}.png';
    await shared.artworkRoot.create();
    await File(p.join(shared.artworkRoot.path, filename)).writeAsBytes(bytes);
    final retrievedAt = DateTime.utc(2026, 10, 7);
    for (var i = 0; i < 129; i++) {
      await shared.preserveBlob(
          MetadataArtworkBlob('fixture-$i', filename, bytes.length),
          retrievedAt);
    }
    // Seed a receipt while valid, then change its exact bytes without changing
    // length. Readers must still reject it, not weaken blob integrity.
    final damaged = List<int>.from(bytes)..[35] ^= 1;
    final damagedName = '${sha256.convert(damaged)}.png';
    final damagedFile = File(p.join(shared.artworkRoot.path, damagedName));
    await damagedFile.writeAsBytes(damaged);
    await shared.preserveBlob(
        MetadataArtworkBlob('damaged', damagedName, bytes.length), retrievedAt);
    await damagedFile.writeAsBytes(bytes);
    observe = true;
    expect(await shared.restore(db), 0);
    final restored = await db.query('metadata_artwork_cache');
    // Receipts are not advertised as available images. Integrity is checked on
    // consumption, without rereading every cached image while opening settings.
    expect(restored, hasLength(130));
    expect(
        restored
            .every((r) => r['retrieved_at'] == retrievedAt.toIso8601String()),
        true);
    expect(uncommittedWrites, 0,
        reason:
            'Per-image autocommit fsyncs must be replaced by bounded pages');
    expect(pageSizes, [128, 2]);
  });

  test('shared artwork consumption rejects same-size replacement bytes',
      () async {
    final db = await controlsDatabase();
    final root =
        await Directory.systemTemp.createTemp('rshop-artwork-integrity-');
    final shared = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate);
    final provider = ControlsArtworkProvider();
    final cache = MetadataArtworkCache(Future.value(db), shared.artworkRoot,
        sharedStore: shared);
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        artworkCache: Future.value(cache),
        sharedStore: Future.value(shared),
        catalogueChanged: () {});
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await shared.close();
      await db.close();
      await root.delete(recursive: true);
    });
    await controls.load();
    await controls.refresh(systemSlug: 'psx');
    final edition = provider.calls.single.editionId;
    final cover = (await cache.artworkForEdition(edition)).cover!;
    final file = File.fromUri(Uri.parse(cover));
    final bytes = await file.readAsBytes();
    final replacement = List<int>.from(bytes)..[35] ^= 1;
    await file.writeAsBytes(replacement);
    expect((await cache.artworkForEdition(edition)).cover, isNull,
        reason: 'Equal size alone cannot validate a shared image');
    await db.delete('metadata_artwork_cache');
    await shared.restore(db);
    expect((await cache.artworkForEdition(edition)).cover, isNull);
    expect(await cache.previewForEdition(edition), isNull);
    await file.writeAsBytes(bytes);
    expect((await cache.artworkForEdition(edition)).cover, cover);
    await file.delete();
    expect((await cache.artworkForEdition(edition)).cover, isNull);
    expect(provider.calls, hasLength(1));
    expect(provider.artworkCalls, 1,
        reason: 'Reading never repairs via network');
  });

  for (final version in [4, 5]) {
    test(
        'v$version shared mappings upgrade without losing launcher field ownership',
        () async {
      sqfliteFfiInit();
      final root = await Directory.systemTemp.createTemp('rshop-esde-v4-');
      var shared = await SharedMetadataStore.open(root,
          factory: databaseFactoryFfiNoIsolate);
      await shared.close();
      final old = await databaseFactoryFfiNoIsolate
          .openDatabase(p.join(root.path, 'metadata.sqlite'));
      if (version == 4) {
        await old.execute('DROP TABLE es_de_media_ownership');
        await old.execute('DROP TABLE es_de_media_publications');
        await old.execute('DROP TABLE es_de_media_reuse');
        await old.execute('ALTER TABLE es_de_mappings DROP COLUMN media_root');
      }
      await old.execute(
          'ALTER TABLE es_de_mappings DROP COLUMN installation_layout');
      await old.insert('es_de_ownership', {
        'target_path': 'gamelist.xml',
        'rom_path': './Game.chd',
        'ownership_json': '{"editionId":"edition","fields":{"desc":"owned"}}',
      });
      await old.insert('es_de_mappings', {
        'edition_id': 'edition',
        'provider_id': 'screenscraper',
        'identity_key': 'binding',
        'target_path': 'gamelist.xml',
        'system_id': 'psx',
        'install_root': 'ROMs',
        'rom_root': 'ROMs',
        'rom_path': './Game.chd',
      });
      await old.execute('PRAGMA user_version = $version');
      await old.close();
      shared = await SharedMetadataStore.open(root,
          factory: databaseFactoryFfiNoIsolate, existingOnly: true);
      await shared.close();
      final upgraded = await databaseFactoryFfiNoIsolate
          .openDatabase(p.join(root.path, 'metadata.sqlite'));
      try {
        expect((await upgraded.query('es_de_mappings')).single['identity_key'],
            'binding');
        expect((await upgraded.query('es_de_mappings')).single['media_root'],
            isNull);
        expect(
            (await upgraded.query('es_de_ownership')).single['ownership_json'],
            contains('owned'));
        expect(await upgraded.query('es_de_media_reuse'), isEmpty);
        expect(
            (await upgraded.rawQuery('PRAGMA user_version'))
                .single
                .values
                .single,
            7);
      } finally {
        await upgraded.close();
        await root.delete(recursive: true);
      }
    });
  }

  test('missing configured storage cannot create an empty replacement cache',
      () async {
    final root = await Directory.systemTemp.createTemp('rshop-missing-shared-');
    final missing = Directory('${root.path}/unmounted');
    addTearDown(() => root.delete(recursive: true));
    await expectLater(
        SharedMetadataStore.open(missing,
            factory: databaseFactoryFfiNoIsolate, existingOnly: true),
        throwsA(isA<FileSystemException>()));
    expect(await missing.exists(), false);
  });

  test('unmounted shared storage preserves cached browsing and blocks writes',
      () async {
    final db = await controlsDatabase();
    await LibraryQuery.install(db);
    await _setArtifact(db, _driveArtifact());
    final parent = await Directory.systemTemp.createTemp('rshop-remount-');
    final root = Directory(p.join(parent.path, 'RShopMetadata'));
    var shared = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate);
    final provider = ControlsArtworkProvider(includeScreenshot: true);
    final reply = provider.reply!;
    provider.reply = (request, cancel) async {
      final result = await reply(request, cancel);
      return MetadataLookupResult(
          status: result.status,
          message: result.message,
          record: MetadataRecord.fromJson({
            ...result.record!.toJson(),
            'matchMethod': 'verifiedProviderId',
            'descriptions': [
              MetadataText(text: 'Preserved description').toJson()
            ],
            'ratings': [
              SourcedRating.parse(
                      sourceId: 'screenscraper',
                      sourceLabel: 'ScreenScraper',
                      providerGameId: '42',
                      rawValue: 16,
                      scaleMinimum: 0,
                      scaleMaximum: 20,
                      kind: RatingKind.overallAggregate,
                      retrievedAt: result.record!.retrievedAt)!
                  .toJson()
            ]
          }));
    };
    final store = LibraryStore(Future.value(db));
    final reviewed = (await db.transaction((txn) =>
            LibraryStore.catalogueEditions(txn, cacheRowId: 1).toList()))
        .single;
    final reviewedEdition = (await store.edition(reviewed))!;
    final reviewedGame = (await store.game(reviewedEdition.gameId))!;
    await store.putGame(GameIdentity.fromJson({
      ...reviewedGame.toJson(),
      'providerIds': {'screenscraper': '42'},
      'matchStatus': 'manuallyMatched'
    }));
    await store.putEdition(EditionIdentity.fromJson({
      ...reviewedEdition.toJson(),
      'tags': ['official']
    }));
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        sharedStore: Future.value(shared),
        artworkCache: Future.value(MetadataArtworkCache(
            Future.value(db), shared.artworkRoot,
            sharedStore: shared)),
        catalogueChanged: () {});
    await controls.load();
    await controls.refresh(systemSlug: 'psx');
    final before = (await db.query('library_metadata')).single;
    final edition = provider.calls.single.editionId;
    final cover =
        (await MetadataArtworkCache(Future.value(db), shared.artworkRoot)
                .artworkForEdition(edition))
            .cover;
    expect(cover, isNotNull);
    await controls.close();
    controls.dispose();
    await shared.close();
    final moved = await root.rename(p.join(parent.path, 'unmounted'));
    SharedPreferences.setMockInitialValues(
        {sharedMetadataDirectoryKey: root.path});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      libraryDbProvider.overrideWithValue(_SharedFixtureDatabase(db)),
      sharedMetadataStoreProvider.overrideWith((ref) =>
          SharedMetadataStore.open(root,
              factory: databaseFactoryFfiNoIsolate, existingOnly: true)),
    ]);
    final cardSubscription =
        container.listen(cachedCoverRatingsProvider('psx'), (_, __) {});
    final coverSubscription =
        container.listen(cachedMetadataCoversProvider('psx'), (_, __) {});
    addTearDown(() async {
      cardSubscription.close();
      coverSubscription.close();
      container.dispose();
      await shared.close();
      await db.close();
      await parent.delete(recursive: true);
    });

    // Normal cache readers must still complete. Missing artwork is a null cover,
    // not a failure that also prevents reading the game's usable text/score.
    final cards =
        await container.read(cachedCoverRatingsProvider('psx').future);
    expect(cards, hasLength(1));
    expect(cards.values.single?.rating.normalizedValue, 80);
    final covers =
        await container.read(cachedMetadataCoversProvider('psx').future);
    expect(covers.values.single, isNull);
    final details = await container.read(gameMetadataProvider((
      filename: 'artifact:${_driveArtifact().id.key}',
      systemSlug: 'psx'
    )).future);
    expect(details?.providerMatches, {'screenscraper': 'verifiedProviderId'});
    expect(details?.summary, 'Preserved description');
    expect(details?.cachedCover, isNull);
    expect(await db.query('library_metadata'), [before]);
    await expectLater(container.read(sharedMetadataProjectionProvider.future),
        throwsA(isA<FileSystemException>()));
    await expectLater(container.read(metadataArtworkCacheProvider),
        throwsA(isA<FileSystemException>()));
    final unavailableControls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        sharedStore: container.read(sharedMetadataStoreProvider),
        artworkCache: container.read(metadataArtworkCacheProvider),
        catalogueChanged: () {});
    addTearDown(() async {
      await unavailableControls.close();
      unavailableControls.dispose();
    });
    await unavailableControls.load();
    expect(unavailableControls.state.error, true);
    expect(unavailableControls.state.sharedStorageUnavailable, true);
    expect(unavailableControls.state.sharedDirectory, root.path);
    expect(unavailableControls.state.systems, ['psp', 'psx']);
    expect(unavailableControls.state.report?.counts, {'matched': 1},
        reason: 'Storage failure cannot hide already committed job progress');
    expect(await root.exists(), false,
        reason:
            'Reads cannot replace absent shared storage with an empty cache');
    expect(provider.calls, hasLength(1));
    expect(provider.artworkCalls, 2);

    await moved.rename(root.path);
    // Ordinary settings regrant/reselection must not await the previously
    // failed worker futures or leave that failure permanently cached.
    await unavailableControls.selectSharedStorage(() async => parent,
        factory: databaseFactoryFfiNoIsolate);
    expect(unavailableControls.state.error, false);
    expect(unavailableControls.state.sharedStorageUnavailable, false);
    expect(unavailableControls.state.sharedDirectory, root.path);
    shared = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate, existingOnly: true);
    container.invalidate(sharedMetadataStoreProvider);
    expect(await container.read(sharedMetadataProjectionProvider.future), 0);
    expect(
        (await container.read(cachedMetadataCoversProvider('psx').future))
            .values
            .single,
        cover);
    expect(provider.calls, hasLength(1));
    expect(provider.artworkCalls, 2);
  });

  test('Android locale bookkeeping does not make a new store foreign',
      () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('rshop-android-locale-');
    addTearDown(() => root.delete(recursive: true));
    final path = p.join(root.path, 'metadata.sqlite');
    final nativeCreated = await databaseFactoryFfiNoIsolate.openDatabase(path);
    await nativeCreated.execute('CREATE TABLE android_metadata (locale TEXT)');
    await nativeCreated.insert('android_metadata', {'locale': 'en_US'});
    await nativeCreated.close();
    final shared = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate);
    await shared.close();
    final inspected = await databaseFactoryFfiNoIsolate.openDatabase(path);
    try {
      expect(await inspected.query('android_metadata'), [
        {'locale': 'en_US'}
      ]);
      expect(await inspected.query('records'), isEmpty);
      expect(
          (await inspected.rawQuery('PRAGMA application_id'))
              .single
              .values
              .single,
          0x52534d31);
      expect(
          (await inspected.rawQuery('PRAGMA user_version'))
              .single
              .values
              .single,
          7);
    } finally {
      await inspected.close();
    }
    final reopened = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate, existingOnly: true);
    await reopened.close();
  });

  test('selection rejects an unrelated SQLite file without changing its data',
      () async {
    sqfliteFfiInit();
    final root =
        await Directory.systemTemp.createTemp('rshop-unrelated-cache-');
    final path = p.join(root.path, 'metadata.sqlite');
    addTearDown(() => root.delete(recursive: true));
    final unrelated = await databaseFactoryFfiNoIsolate.openDatabase(path);
    await unrelated.execute('CREATE TABLE android_metadata (locale TEXT)');
    await unrelated.insert('android_metadata', {'locale': 'en_US'});
    await unrelated.execute('CREATE TABLE user_data(value TEXT)');
    await unrelated.insert('user_data', {'value': 'keep'});
    await unrelated.close();
    await expectLater(
        SharedMetadataStore.open(root, factory: databaseFactoryFfiNoIsolate),
        throwsFormatException);
    final inspected = await databaseFactoryFfiNoIsolate.openDatabase(path);
    try {
      expect(await inspected.query('user_data'), [
        {'value': 'keep'}
      ]);
      expect(
          (await inspected.rawQuery('PRAGMA user_version'))
              .single
              .values
              .single,
          0);
      expect(
          (await inspected.rawQuery('PRAGMA application_id'))
              .single
              .values
              .single,
          0);
    } finally {
      await inspected.close();
    }
  });

  test('normal remote refresh survives losing private metadata projections',
      () async {
    final db = await controlsDatabase();
    final artifact = RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: 'selected-source',
            accountId: 'account-a',
            providerFileId: 'exact-file'),
        parentId: 'selected-root',
        displayPath: 'Game 1.chd',
        displayName: 'Game 1.chd',
        sizeBytes: 1024,
        version: '1',
        providerChecksums: {'md5': '00000000000000000000000000000001'},
        canDownload: true);
    await db.update(
        'games',
        {
          'artifact_key': artifact.id.key,
          'remote_artifact': jsonEncode(artifact.toJson())
        },
        where: 'id = ?',
        whereArgs: [1]);
    final root =
        await Directory.systemTemp.createTemp('rshop-shared-metadata-');
    final shared = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate);
    final provider = ControlsArtworkProvider(includeScreenshot: true);
    final cache = MetadataArtworkCache(Future.value(db), shared.artworkRoot,
        sharedStore: shared);
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        artworkCache: Future.value(cache),
        sharedStore: Future.value(shared),
        catalogueChanged: () {});
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await shared.close();
      await db.close();
      await root.delete(recursive: true);
    });
    await controls.load();
    await controls.refresh(systemSlug: 'psx');
    expect(controls.state.error, false);
    expect(controls.state.report!.counts, {'matched': 1});
    await controls.refresh(systemSlug: 'psx');
    expect(provider.calls, hasLength(2),
        reason: 'A fresh generation must still request current facts');
    final editionId = provider.calls.first.editionId;
    final original = await LibraryStore(Future.value(db))
        .metadata(editionId, 'screenscraper');
    final originalCover = (await cache.artworkForEdition(editionId)).cover;
    expect(originalCover, isNotNull);
    await db.delete('library_metadata');
    await db.delete('metadata_artwork_cache');
    await shared.close();
    // The v1 shared cache used the same fact/blob schema but no image response
    // receipts. Upgrade in place must preserve both, without another request.
    final v1 = await databaseFactoryFfiNoIsolate
        .openDatabase(p.join(root.path, 'metadata.sqlite'));
    await v1.execute('DROP TABLE artwork_responses');
    await v1.execute('DROP TABLE identity_bindings');
    for (final table in [
      'es_de_mappings',
      'es_de_pending',
      'es_de_ownership',
      'es_de_publications',
      'es_de_media_ownership',
      'es_de_media_publications',
      'es_de_media_reuse'
    ]) {
      await v1.execute('DROP TABLE $table');
    }
    await v1.execute('PRAGMA user_version = 1');
    await v1.close();
    final reopened = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate);
    try {
      expect(await reopened.restore(db), 1);
      final recovered = await LibraryStore(Future.value(db))
          .metadata(editionId, 'screenscraper');
      expect(recovered!.toJson(), original!.toJson());
      expect((await cache.artworkForEdition(editionId)).cover, originalCover);
      expect(provider.calls, hasLength(2));
      expect(provider.artworkCalls, 4);
      expect(
          await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE name LIKE '%installation%'"),
          isEmpty,
          reason: 'Rebuild does not create installation ownership');
      final differentAccount = RemoteArtifact.fromJson({
        ...artifact.toJson(),
        'id': {...artifact.id.toJson(), 'accountId': 'account-b'}
      });
      await db.update(
          'games',
          {
            'artifact_key': differentAccount.id.key,
            'remote_artifact': jsonEncode(differentAccount.toJson())
          },
          where: 'id = ?',
          whereArgs: [1]);
      await db.delete('library_metadata');
      expect(await reopened.restore(db), 0,
          reason: 'Same filename/file ID is not ownership across accounts');
    } finally {
      await reopened.close();
    }
  });

  test(
      'private migration keeps facts and blobs; changed editions cannot restore',
      () async {
    final db = await controlsDatabase();
    final root = await Directory.systemTemp.createTemp('rshop-shared-migrate-');
    final privateRoot = Directory('${root.path}/private-artwork');
    final provider = ControlsArtworkProvider();
    final cache = MetadataArtworkCache(Future.value(db), privateRoot);
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        artworkCache: Future.value(cache),
        catalogueChanged: () {});
    await controls.load();
    await controls.refresh(systemSlug: 'psx');
    final shared = await SharedMetadataStore.open(
        Directory('${root.path}/shared'),
        factory: databaseFactoryFfiNoIsolate);
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await shared.close();
      await db.close();
      await root.delete(recursive: true);
    });
    expect(await shared.migrate(db, cache), 1);
    final id = provider.calls.single.editionId;
    final metadata = (await db.query('library_metadata')).single;
    final older =
        jsonDecode(metadata['record_json'] as String) as Map<String, dynamic>;
    older['refreshGeneration'] = 0;
    await db.update('library_metadata', {
      'generation_id': 0,
      'record_json': jsonEncode(older),
    });
    expect(await shared.migrate(db, cache), 1,
        reason: 'Reconnection must not regress or reject newer durable facts');
    expect(await shared.restore(db), 1);
    expect((await db.query('library_metadata')).single['generation_id'],
        metadata['generation_id']);
    final row = (await db.query('library_editions',
            where: 'edition_id = ?', whereArgs: [id]))
        .single;
    final json =
        jsonDecode(row['record_json'] as String) as Map<String, dynamic>;
    json['revision'] = 'different-release';
    await db.update('library_editions', {'record_json': jsonEncode(json)},
        where: 'edition_id = ?', whereArgs: [id]);
    await db.delete('library_metadata');
    expect(await shared.restore(db), 0);
    expect(await db.query('library_metadata'), isEmpty);
    expect(await privateRoot.exists(), true,
        reason: 'Migration is not deletion');
    expect(provider.calls, hasLength(1));
    expect(provider.artworkCalls, 1);
    // The normal settings action commits the path only after migration joins.
    await controls.selectSharedStorage(
        () async => Directory('${root.path}/selected'),
        factory: databaseFactoryFfiNoIsolate);
    expect(controls.state.error, false);
    final selectedPath = (await SharedPreferences.getInstance())
        .getString(sharedMetadataDirectoryKey);
    expect(selectedPath, p.join(root.path, 'selected', 'RShopMetadata'));
    final selected = await SharedMetadataStore.open(Directory(selectedPath!),
        factory: databaseFactoryFfiNoIsolate, existingOnly: true);
    await selected.close();
    final collision = Directory('${root.path}/collision');
    await collision.create();
    await File('${collision.path}/RShopMetadata').writeAsString('user-owned');
    await controls.selectSharedStorage(() async => collision,
        factory: databaseFactoryFfiNoIsolate);
    expect(controls.state.error, true);
    expect(
        (await SharedPreferences.getInstance())
            .getString(sharedMetadataDirectoryKey),
        selectedPath,
        reason: 'A failed migration must keep the selected root');
    expect(await File('${collision.path}/RShopMetadata').readAsString(),
        'user-owned');
  });

  test('resume recovers a durable response before repeating a provider lookup',
      () async {
    final db = await controlsDatabase();
    final root = await Directory.systemTemp.createTemp('rshop-shared-resume-');
    final shared = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate);
    final provider = ControlsArtworkProvider();
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        sharedStore: Future.value(shared),
        artworkCache: Future.value(MetadataArtworkCache(
            Future.value(db), shared.artworkRoot,
            sharedStore: shared)),
        catalogueChanged: () {});
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await shared.close();
      await db.close();
      await root.delete(recursive: true);
    });
    await controls.load();
    await controls.refresh(systemSlug: 'psx');
    final job = controls.state.report!.id;
    // Model the cross-database crash boundary: durable response survived but
    // the private transaction did not acknowledge metadata/item completion.
    await db.delete('library_metadata');
    await db.update('metadata_refresh_items', {'status': 'pending', 'rated': 0},
        where: 'job_id = ?', whereArgs: [job]);
    await db.update('metadata_refresh_jobs', {'state': 'paused'},
        where: 'id = ?', whereArgs: [job]);
    await controls.resume();
    expect(controls.state.error, false);
    expect(controls.state.report!.counts, {'matched': 1});
    expect(provider.calls, hasLength(1),
        reason: 'Same generation response is already durably committed');
  });

  for (final reselected in [false, true]) {
    test(
        'fresh private database recovers exact Drive facts (reselected=$reselected)',
        () async {
      final old = await controlsDatabase();
      final root =
          await Directory.systemTemp.createTemp('rshop-reinstall-cache-');
      final shared = await SharedMetadataStore.open(root,
          factory: databaseFactoryFfiNoIsolate);
      final artifact = _driveArtifact();
      await _setArtifact(old, artifact);
      final provider = ControlsArtworkProvider();
      final controls = MetadataControlsController(
          database: Future.value(old),
          providers: {'screenscraper': provider},
          screenScraperCredentials:
              ScreenScraperCredentialStore(storage: MemorySecrets()),
          igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
          sharedStore: Future.value(shared),
          artworkCache: Future.value(MetadataArtworkCache(
              Future.value(old), shared.artworkRoot,
              sharedStore: shared)),
          catalogueChanged: () {});
      await controls.load();
      await controls.refresh(systemSlug: 'psx');
      final id = provider.calls.single.editionId;
      final store = LibraryStore(Future.value(old));
      final game = (await store.game(provider.calls.single.gameId))!;
      final edition = (await store.edition(id))!;
      await store.putGame(GameIdentity.fromJson({
        ...game.toJson(),
        'providerIds': {'screenscraper': '42'},
        'matchStatus': 'manuallyMatched'
      }));
      await store.putEdition(EditionIdentity.fromJson({
        ...edition.toJson(),
        'revision': 'reviewed-v1',
        'tags': ['T-Eng', 'Undub']
      }));
      await controls.refresh(systemSlug: 'psx');
      final original = (await store.metadata(id, 'screenscraper'))!;
      // A later independent provider correction must not be discarded because
      // the older ScreenScraper snapshot was inserted first.
      final corrected = GameIdentity.fromJson({
        ...(await store.game(original.gameId))!.toJson(),
        'providerIds': {'screenscraper': '42', 'igdb': '7'}
      });
      await store.putGame(corrected);
      final aggregate = MetadataRecord(
          gameId: corrected.id,
          editionId: id,
          platformId: 'psx',
          providerId: 'igdb',
          providerGameId: '7',
          retrievedAt: original.retrievedAt,
          refreshGeneration: original.refreshGeneration + 1,
          matchMethod: 'verifiedProviderId',
          titles: [MetadataText(text: game.title)]);
      await store.putMetadata(aggregate);
      final owned = await old.rawQuery('''SELECT g.record_json AS game_json,
        e.record_json AS edition_json FROM library_editions e
        JOIN library_game_identities g ON g.game_id = e.game_id
        WHERE e.edition_id = ?''', [id]);
      await shared.preserve(aggregate, owned.single, old);
      await controls.close();
      controls.dispose();
      await old.close();

      // A newly created operational DB, not just cleared metadata tables.
      final fresh = await controlsDatabase();
      final container = ProviderContainer(overrides: [
        libraryDbProvider.overrideWithValue(_SharedFixtureDatabase(fresh)),
        sharedMetadataStoreProvider.overrideWithValue(Future.value(shared)),
      ]);
      expect(await container.read(sharedMetadataProjectionProvider.future), 0);
      await _setArtifact(
          fresh,
          _driveArtifact(
              source: reselected ? 'newly-selected-source' : 'selected-source',
              name: 'Renamed game.chd'));
      addTearDown(() async {
        container.dispose();
        await fresh.close();
        await shared.close();
        await root.delete(recursive: true);
      });
      expect(await fresh.query('library_editions'), isEmpty);
      // Ordinary discovery may have built unreviewed catalogue identities
      // before the selected durable store is reconnected.
      await fresh.transaction((txn) async {
        await for (final _
            in LibraryStore.catalogueEditions(txn, cacheRowId: 1)) {}
      });
      container.read(gameDbChangedProvider.notifier).state++;
      expect(await container.read(sharedMetadataProjectionProvider.future), 2);
      final newId = (await LibraryStore.cachedCatalogueEditionId(fresh, 1))!;
      final recovered = (await LibraryStore(Future.value(fresh))
          .metadata(newId, 'screenscraper'))!;
      expect({
        ...recovered.toJson(),
        'gameId': original.gameId,
        'editionId': original.editionId
      }, original.toJson());
      final recoveredEdition =
          (await LibraryStore(Future.value(fresh)).edition(newId))!;
      expect(recoveredEdition.revision, 'reviewed-v1');
      expect(recoveredEdition.tags, {'T-Eng', 'Undub'});
      expect(
          (await LibraryStore(Future.value(fresh)).game(recovered.gameId))!
              .providerIds,
          {'screenscraper': '42', 'igdb': '7'});
      expect(
          (await LibraryStore(Future.value(fresh)).metadata(newId, 'igdb'))!
              .providerGameId,
          '7');
      expect(
          (await MetadataArtworkCache(Future.value(fresh), shared.artworkRoot)
                  .artworkForEdition(newId))
              .cover,
          isNotNull);
      expect(provider.calls, hasLength(2));
      expect(provider.artworkCalls, 2);
      expect(await fresh.query('metadata_refresh_jobs'), isEmpty,
          reason: 'A cache is not a backup of work/transfer state');
      expect(await shared.restore(fresh), 0, reason: 'Recovery is idempotent');

      // Do not resurrect facts after the published object changes or disappears.
      for (final incompatible in [
        _driveArtifact(account: 'other-account'),
        _driveArtifact(checksum: '00000000000000000000000000000002'),
        _driveArtifact(size: 2048),
        _driveArtifact(file: 'different-file'),
      ]) {
        await _setArtifact(fresh, incompatible);
        await fresh.delete('library_metadata');
        expect(await shared.restore(fresh), 0);
      }
      if (reselected) {
        await _setArtifact(
            fresh, _driveArtifact(source: 'newly-selected-source'));
        final duplicate = _driveArtifact(source: 'second-selected-source');
        await fresh.insert('games', {
          'id': 99,
          'systemSlug': 'psx',
          'displayName': 'same object twice',
          'filename': 'another.chd',
          'artifact_key': duplicate.id.key,
          'remote_artifact': jsonEncode(duplicate.toJson())
        });
        expect(await shared.restore(fresh), 0,
            reason: 'Rebinding cannot choose between two current sources');
      }
      await fresh.delete('games');
      expect(await shared.restore(fresh), 0);
    });
  }

  for (final scenario in ['unchanged', 'all-reselected', 'base-reselected']) {
    test('Drive restores a bundle and its exact unscraped base ($scenario)',
        () async {
      final old = await controlsDatabase();
      Database? freshDb;
      final root =
          await Directory.systemTemp.createTemp('rshop-base-recovery-');
      var shared = await SharedMetadataStore.open(root,
          factory: databaseFactoryFfiNoIsolate);
      addTearDown(() async {
        await freshDb?.close();
        await old.close();
        await shared.close();
        await root.delete(recursive: true);
      });
      final patch = _driveArtifact(file: 'translated-disc-1');
      final base = _driveArtifact(file: 'original-release');
      final disc = _driveArtifact(file: 'translated-disc-2');
      await _setArtifact(old, patch);
      for (final entry in [(3, base), (4, disc)]) {
        await old.insert('games', {
          'id': entry.$1,
          'systemSlug': 'psx',
          'displayName': entry.$2.displayName,
          'filename': entry.$2.displayName,
          'artifact_key': entry.$2.id.key,
          'remote_artifact': jsonEncode(entry.$2.toJson())
        });
      }
      await old.transaction((txn) async {
        await for (final _ in LibraryStore.catalogueEditions(txn)) {}
      });
      final store = LibraryStore(Future.value(old));
      final patchId = (await LibraryStore.cachedCatalogueEditionId(old, 1))!;
      final baseId = (await LibraryStore.cachedCatalogueEditionId(old, 3))!;
      final patchEdition = (await store.edition(patchId))!;
      final baseEdition = (await store.edition(baseId))!;
      final baseGame = GameIdentity.fromJson({
        ...(await store.game(baseEdition.gameId))!.toJson(),
        'providerIds': {'igdb': '42'},
        'matchStatus': 'manuallyMatched'
      });
      await store.putGame(baseGame);
      await store.putEdition(EditionIdentity.fromJson({
        ...baseEdition.toJson(),
        'tags': ['official']
      }));
      final patchGame = GameIdentity.fromJson({
        ...(await store.game(patchEdition.gameId))!.toJson(),
        'baseGameId': baseGame.id,
        'providerIds': {'igdb': '42'},
        'matchStatus': 'manuallyMatched'
      });
      await store.putGame(patchGame);
      await store.putEdition(EditionIdentity.fromJson({
        ...patchEdition.toJson(),
        'tags': ['T-Eng', 'Undub'],
        'isTranslation': true,
        'translatedLanguages': ['en'],
        'patchId': 'reviewed-translation',
        'members': [
          EditionMember(artifactId: patch.id, discNumber: 1).toJson(),
          EditionMember(artifactId: disc.id, discNumber: 2).toJson()
        ]
      }));
      final record = MetadataRecord(
          gameId: patchGame.id,
          editionId: patchId,
          platformId: 'psx',
          providerId: 'igdb',
          providerGameId: '42',
          retrievedAt: DateTime.utc(2026, 10, 5),
          refreshGeneration: 7,
          matchMethod: 'verifiedProviderIdGlobalGame',
          titles: [const MetadataText(text: 'Original title')]);
      await store.putMetadata(record);
      final identity = (await old.rawQuery('''SELECT g.record_json AS game_json,
      e.record_json AS edition_json FROM library_editions e
      JOIN library_game_identities g ON g.game_id = e.game_id
      WHERE e.edition_id = ?''', [patchId])).single;
      // The base has no scrape of its own: its reviewed identity is still an
      // essential part of the translated edition's durable ownership evidence.
      expect(await old.query('library_metadata'), hasLength(1));
      await shared.preserve(record, identity, old);
      await shared.close();
      shared = await SharedMetadataStore.open(root,
          factory: databaseFactoryFfiNoIsolate, existingOnly: true);
      await old.close();
      final fresh = freshDb = await controlsDatabase();
      final newSource = scenario == 'all-reselected'
          ? 'reconnected-source'
          : 'selected-source';
      final newPatch =
          _driveArtifact(source: newSource, file: 'translated-disc-1');
      final newBase = _driveArtifact(
          source: scenario == 'unchanged'
              ? 'selected-source'
              : 'reconnected-source',
          file: 'original-release');
      final newDisc =
          _driveArtifact(source: newSource, file: 'translated-disc-2');
      await _setArtifact(fresh, newPatch);
      for (final entry in [(3, newBase), (4, newDisc)]) {
        await fresh.insert('games', {
          'id': entry.$1,
          'systemSlug': 'psx',
          'displayName': entry.$2.displayName,
          'filename': entry.$2.displayName,
          'artifact_key': entry.$2.id.key,
          'remote_artifact': jsonEncode(entry.$2.toJson())
        });
      }
      expect(await shared.restore(fresh), 1);
      final rebuilt = LibraryStore(Future.value(fresh));
      final newId = (await LibraryStore.cachedCatalogueEditionId(fresh, 1))!;
      final recoveredEdition = (await rebuilt.edition(newId))!;
      final recoveredGame = (await rebuilt.game(recoveredEdition.gameId))!;
      final newBaseId =
          (await LibraryStore.cachedCatalogueEditionId(fresh, 3))!;
      expect(recoveredGame.baseGameId,
          newBaseId.replaceFirst('catalogue-edition:', 'catalogue-game:'));
      final recoveredBaseEdition = (await rebuilt.edition(newBaseId))!;
      final recoveredBase = (await rebuilt.game(recoveredBaseEdition.gameId))!;
      expect(recoveredGame.baseGameId, recoveredBase.id);
      if (scenario != 'unchanged') {
        expect(recoveredGame.baseGameId, isNot(baseGame.id));
      }
      expect(recoveredBase.providerIds, {'igdb': '42'});
      expect(recoveredEdition.members.map((m) => m.artifactId),
          [newPatch.id, newDisc.id]);
      expect(recoveredEdition.members.map((m) => m.discNumber), [1, 2]);
      expect(recoveredEdition.patchId, 'reviewed-translation');
      final recoveredRecord = (await rebuilt.metadata(newId, 'igdb'))!;
      expect(
          metadataOverallOwnership(
              recoveredGame, recoveredEdition, recoveredRecord, recoveredBase),
          OverallRatingOwnership.originalGame);
      expect(await shared.restore(fresh), 0);
      await fresh.delete('library_metadata');
      await rebuilt.putGame(GameIdentity.fromJson({
        ...recoveredBase.toJson(),
        'providerIds': {'igdb': 'another-reviewed-original'}
      }));
      expect(await shared.restore(fresh), 0,
          reason:
              'Saved base evidence cannot overwrite a newer manual correction');
      expect((await rebuilt.game(recoveredBase.id))!.providerIds,
          {'igdb': 'another-reviewed-original'});
      await rebuilt.putGame(recoveredBase);
      // A replaced/missing bundle member or base cannot resurrect an old relation.
      for (final row in [3, 4]) {
        await fresh.delete('library_metadata');
        await fresh.update(
            'games',
            {
              'remote_artifact': jsonEncode(RemoteArtifact.fromJson({
                ...(row == 3 ? newBase : newDisc).toJson(),
                'providerChecksums': {'md5': 'changed'}
              }).toJson())
            },
            where: 'id = ?',
            whereArgs: [row]);
        expect(await shared.restore(fresh), 0);
        await fresh.update(
            'games',
            {
              'remote_artifact':
                  jsonEncode((row == 3 ? newBase : newDisc).toJson())
            },
            where: 'id = ?',
            whereArgs: [row]);
      }
      await fresh.delete('games', where: 'id = ?', whereArgs: [3]);
      expect(await shared.restore(fresh), 0);
    });
  }

  test(
      'v2 migration and catalogue rebuild cross the shared record page boundary',
      () async {
    final old = await controlsDatabase();
    Database? freshDb;
    final root = await Directory.systemTemp.createTemp('rshop-shared-pages-');
    var shared = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate);
    final provider = ControlsArtworkProvider();
    final controls = MetadataControlsController(
        database: Future.value(old),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        sharedStore: Future.value(shared),
        artworkCache: Future.value(MetadataArtworkCache(
            Future.value(old), shared.artworkRoot,
            sharedStore: shared)),
        catalogueChanged: () {});
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await freshDb?.close();
      await old.close();
      await shared.close();
      await root.delete(recursive: true);
    });
    Future<void> catalogue(Database db, String source) async {
      await db.transaction((txn) async {
        await txn.delete('games');
        for (var i = 1; i <= 129; i++) {
          final artifact = _driveArtifact(source: source, file: 'edition-$i');
          await txn.insert('games', {
            'id': i,
            'systemSlug': 'psx',
            'displayName': 'Game $i',
            'filename': artifact.displayName,
            'artifact_key': artifact.id.key,
            'remote_artifact': jsonEncode(artifact.toJson())
          });
        }
      });
    }

    await catalogue(old, 'original-source');
    await controls.load();
    await controls.refresh(systemSlug: 'psx');
    expect(controls.state.report!.counts, {'matched': 129});
    expect(provider.calls, hasLength(129));
    expect(provider.artworkCalls, 1);
    await controls.close();
    await shared.close();
    // An actual v2 reopen exercises the upgrade's bounded second page, not a
    // new empty v3 database or a manually supplied private identity map.
    final v2 = await databaseFactoryFfiNoIsolate
        .openDatabase(p.join(root.path, 'metadata.sqlite'));
    await v2.execute('DROP TABLE identity_bindings');
    for (final table in [
      'es_de_mappings',
      'es_de_pending',
      'es_de_ownership',
      'es_de_publications',
      'es_de_media_ownership',
      'es_de_media_publications',
      'es_de_media_reuse'
    ]) {
      await v2.execute('DROP TABLE $table');
    }
    await v2.execute('PRAGMA user_version = 2');
    await v2.close();
    shared = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate, existingOnly: true);
    await old.close();
    final fresh = freshDb = await controlsDatabase();
    await catalogue(fresh, 'reconnected-source');
    expect(await shared.restore(fresh), 129);
    expect(await fresh.query('library_metadata'), hasLength(129));
    expect(await shared.restore(fresh), 0);
    expect(provider.calls, hasLength(129));
    expect(provider.artworkCalls, 1);
    final store = LibraryStore(Future.value(fresh));
    for (final row in [1, 128, 129]) {
      final id = (await LibraryStore.cachedCatalogueEditionId(fresh, row))!;
      expect((await store.metadata(id, 'screenscraper'))!.refreshGeneration, 1);
      expect(
          (await MetadataArtworkCache(Future.value(fresh), shared.artworkRoot)
                  .artworkForEdition(id))
              .cover,
          isNotNull);
    }
  });

  test('artwork restart acknowledges its durable response without redownload',
      () async {
    final db = await controlsDatabase();
    final root =
        await Directory.systemTemp.createTemp('rshop-artwork-receipt-');
    final shared = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate);
    final provider = ControlsArtworkProvider();
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        sharedStore: Future.value(shared),
        artworkCache: Future.value(MetadataArtworkCache(
            Future.value(db), shared.artworkRoot,
            sharedStore: shared)),
        catalogueChanged: () {});
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await db.close();
      await shared.close();
      await root.delete(recursive: true);
    });
    await controls.load();
    await controls.refresh(systemSlug: 'psx');
    final artworkId = controls.state.artworkReport!.id;
    expect(provider.artworkCalls, 1);
    // Durable response committed, private acknowledgement rolled back.
    await db.delete('metadata_artwork_cache');
    await db.update('metadata_artwork_items', {'status': 'pending'},
        where: 'job_id = ?', whereArgs: [artworkId]);
    await db.update('metadata_refresh_jobs', {'state': 'paused'},
        where: 'id = ?', whereArgs: [artworkId]);
    await controls.resume();
    expect(controls.state.artworkReport!.counts, {'matched': 1});
    expect(provider.artworkCalls, 1,
        reason:
            'Replaying a committed same-generation image is not a fresh fetch');
    await controls.refresh(systemSlug: 'psx');
    expect(provider.artworkCalls, 2,
        reason: 'Explicit new metadata/artwork generations remain fresh');
  });
}

RemoteArtifact _driveArtifact(
        {String source = 'selected-source',
        String account = 'account-a',
        String file = 'exact-file',
        String name = 'Game 1.chd',
        int size = 1024,
        String checksum = '00000000000000000000000000000001'}) =>
    RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: source,
            accountId: account,
            providerFileId: file),
        parentId: 'selected-root',
        displayPath: name,
        displayName: name,
        sizeBytes: size,
        version: '1',
        providerChecksums: {'md5': checksum},
        canDownload: true);

Future<void> _setArtifact(Database db, RemoteArtifact artifact) => db.update(
    'games',
    {
      'artifact_key': artifact.id.key,
      'remote_artifact': jsonEncode(artifact.toJson()),
      'displayName': artifact.displayName
    },
    where: 'id = ?',
    whereArgs: [1]);

class _SharedFixtureDatabase extends DatabaseService {
  final Database db;
  _SharedFixtureDatabase(this.db);
  @override
  Future<Database> get database async => db;
}
