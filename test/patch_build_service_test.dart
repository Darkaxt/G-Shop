import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:g_shop/models/config/drive_source_config.dart';
import 'package:g_shop/models/config/provider_config.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/patch_catalogue.dart';
import 'package:g_shop/models/portable_patch_recipe.dart';
import 'package:g_shop/models/system_model.dart';
import 'package:g_shop/models/transfer_record.dart';
import 'package:g_shop/services/database_service.dart';
import 'package:g_shop/services/drive/drive_patch_catalogue.dart';
import 'package:g_shop/services/drive/drive_runtime.dart';
import 'package:g_shop/services/drive/drive_transfer_engine.dart';
import 'package:g_shop/services/drive/drive_media.dart';
import 'package:g_shop/services/library_store.dart';
import 'package:g_shop/services/metadata/shared_metadata_store.dart';
import 'package:g_shop/services/owned_storage.dart';
import 'package:g_shop/services/owned_emulator_launcher.dart';
import 'package:g_shop/services/verified_file_publication.dart';
import 'package:g_shop/services/patch_build_service.dart';
import 'package:g_shop/services/transfer_journal.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/owned_storage_fixture.dart';

const _config = ProviderConfig(
    type: ProviderType.drive,
    priority: 1,
    sourceId: 'source',
    path: 'gba-folder',
    drive: DriveSourceConfig(
        accountId: 'account',
        rootFolderId: 'root',
        serverClientId: 'fixture-client'));
const _revision = 'fixture-reviewed-engine';

class _Catalogue extends DrivePatchCatalogue {
  final Map<String, RemoteArtifact> artifacts;
  _Catalogue(super.config, this.artifacts, {required super.runtime});
  @override
  Future<RemoteArtifact> resolve(PatchRelativePath reference) async =>
      artifacts[reference.value]!;
}

// Only protocol bytes and native calls are fixtures. Reservations, streaming
// transfer, recipe, DB migration/projection, publication and reuse are production.
class _Runtime extends DriveRuntime {
  final Map<String, Uint8List> payloads;
  final DriveTransferEngine engine;
  int requests = 0;
  _Runtime(TransferJournal journal, OwnedStorage storage, this.payloads)
      : engine = DriveTransferEngine(
            journal: journal,
            storage: storage,
            revalidate: (_, __) async {},
            openMedia: (artifact, offset, _) async {
              final bytes = payloads[artifact.id.providerFileId]!;
              return DriveMediaResponse(
                  bytes: Stream.value(Uint8List.sublistView(bytes, offset)),
                  offset: offset,
                  length: bytes.length - offset,
                  total: bytes.length);
            }),
        super(journal: journal, storage: storage);
  @override
  Future<DriveTransferOperation> startTransfer(
      {required ProviderConfig config,
      required String transferId,
      void Function(TransferRecord)? onCheckpoint}) async {
    requests++;
    return engine.start(transferId, onCheckpoint: onCheckpoint);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  late Database db;
  late String previousDbPath;
  late Directory scratch;
  late OwnedStorageFixture boundary;
  late OwnedStorage storage;
  late _Runtime runtime;
  late _Catalogue catalogue;
  late IndexedRomPatch patch;
  late PatchBuildService service;
  late TransferJournal journal;
  var applications = 0;
  Future<void> Function()? beforeApply;
  const native = MethodChannel('patch-test-native');
  final original = Uint8List.fromList([1, 2, 3, 4]);
  final patched = Uint8List.fromList([1, 9, 3, 4]);
  final patchBytes = Uint8List.fromList('fixture-reviewed-ips'.codeUnits);
  final system = SystemModel.supportedSystems.singleWhere((s) => s.id == 'gba');
  final game = IndexedPatchGame(
      '1379', 'Advance Wars', PatchRelativePath('GBA/Patches/AW/game.json'));
  Future<PatchBuildResult> build({String? retryId}) => service.build(
      catalogue: catalogue,
      indexedGame: game,
      patch: patch,
      payload: patch.payloads.single,
      base: patch.bases.single,
      system: system,
      targetFolder: p.join(scratch.path, 'roms'),
      retryBuildId: retryId);

  IndexedRomPatch dependent({String? expectedHash}) => IndexedRomPatch(
      source: patch.source, section: 'hacks', sourceId: 'second', title: 'After Balance',
      version: '1', description: '', bases: [], payloads: patch.payloads,
      unsupportedFiles: [], requires: PatchDependency(
        step: PatchRecipeStep.fromPatch(patch, patch.payloads.single),
        outputSize: patched.length,
        outputHashes: {'sha256': expectedHash ?? sha256.convert(patched).toString()}));

  test('ordered dependency verifies intermediate bytes and reuses the entire recipe', () async {
    final second = dependent();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'revision') return _revision;
      final args = call.arguments as Map;
      final root = p.join(scratch.path, 'jobs', args['jobId'] as String);
      if (call.method == 'prepare') { await Directory(root).create(recursive: true); return root; }
      if (call.method == 'reopen') return root;
      if (call.method == 'copy') await File(args['input'] as String).copy(args['output'] as String);
      if (call.method == 'apply') {
        expect(await File(args['input'] as String).readAsBytes(), applications == 0 ? original : patched);
        applications++;
        await File(args['output'] as String).writeAsBytes(patched);
      }
      return {'engineRevision': _revision};
    });
    Future<PatchBuildResult> chain() => service.build(catalogue: catalogue,
        indexedGame: game, patch: second, availablePatches: [second, patch],
        payload: second.payloads.single, base: patch.bases.single, system: system,
        targetFolder: p.join(scratch.path, 'roms'));
    final first = await chain();
    expect(first.recipe.steps.map((s) => s.sourceId), ['7013', 'second']);
    expect(applications, 2);
    expect((await chain()).reused, isTrue);
    expect(applications, 2);
    expect(await File(p.join(first.targetRoot, first.game.filename)).readAsBytes(), patched);
    expect(Directory(p.join(scratch.path, 'jobs')).listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('wrong prerequisite output stops before second application/publication', () async {
    final second = dependent(expectedHash: '0' * 64);
    await expectLater(service.build(catalogue: catalogue, indexedGame: game,
        patch: second, availablePatches: [patch, second], payload: second.payloads.single,
        base: patch.bases.single, system: system, targetFolder: p.join(scratch.path, 'roms')),
        throwsA(isA<PatchBuildException>().having((e) => e.code, 'code', 'input_fingerprint_mismatch')));
    expect(applications, 1);
    expect((await service.store.localForPlatform('gba')).single['state'], 'failed');
    expect((await DatabaseService().getGames('gba')), isEmpty);
  });

  setUp(() async {
    previousDbPath = await databaseFactory.getDatabasesPath();
    scratch = await Directory.systemTemp.createTemp('rshop-patch-workflow-');
    await databaseFactory.setDatabasesPath(p.join(scratch.path, 'database'));
    DatabaseService.resetForTesting();
    db = await DatabaseService().database;
    journal = TransferJournal(Future.value(db));
    boundary = OwnedStorageFixture()..install();
    storage = OwnedStorage(channel: boundary.channel);
    runtime =
        _Runtime(journal, storage, {'base': original, 'patch': patchBytes});
    RemoteArtifact artifact(String id, String name, Uint8List bytes) =>
        RemoteArtifact(
            id: RemoteArtifactId(
                providerId: 'drive',
                sourceId: 'source',
                accountId: 'account',
                providerFileId: id),
            parentId: 'gba-folder',
            displayName: name,
            displayPath: name,
            version: '1',
            sizeBytes: bytes.length,
            canDownload: true,
            providerChecksums: {'md5': md5.convert(bytes).toString()});
    catalogue = _Catalogue(
        _config,
        {
          'GBA/base.gba': artifact('base', 'base.gba', original),
          'GBA/Patches/balance.ips':
              artifact('patch', 'balance.ips', patchBytes)
        },
        runtime: runtime);
    patch = IndexedRomPatch(
        source: 'Fixture',
        section: 'hacks',
        sourceId: '7013',
        title: 'Balance',
        version: '1',
        description: 'Synthetic integration fixture',
        bases: [
          IndexedPatchBase(
              relativePath: PatchRelativePath('GBA/base.gba'),
              sizeBytes: 4,
              checksums: {'sha256': sha256.convert(original).toString()})
        ],
        payloads: [
          IndexedPatchPayload(
              relativePath: 'GBA/Patches/balance.ips',
              sizeBytes: patchBytes.length,
              sha256: sha256.convert(patchBytes).toString(),
              format: PatchFormat.ips)
        ],
        unsupportedFiles: []);
    applications = 0;
    beforeApply = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (call) async {
      final args = call.arguments as Map?;
      if (call.method == 'revision') return _revision;
      final root = p.join(scratch.path, 'jobs', args!['jobId'] as String);
      if (call.method == 'prepare') {
        await Directory(root).create(recursive: true);
        return root;
      }
      if (call.method == 'reopen') return root;
      if (call.method == 'copy') {
        await File(args['input'] as String).copy(args['output'] as String);
      }
      if (call.method == 'apply') {
        await beforeApply?.call();
        applications++;
        expect(await File(args['input'] as String).readAsBytes(), original);
        expect(await File(args['patch'] as String).readAsBytes(), patchBytes);
        await File(args['output'] as String).writeAsBytes(patched);
      }
      return {'engineRevision': _revision};
    });
    boundary.after = (call) async {
      // Mirror only fixture publication into test-private host files so that
      // production raw-file fingerprinting/native input calls see actual bytes.
      if (call.method == 'ownedPublish') {
        final a = call.arguments as Map;
        final session = boundary.sessions[a['session']]!;
        final target = File(session.target);
        await target.parent.create(recursive: true);
        await target.writeAsBytes(boundary.files[session.target]!.bytes);
      }
      if (call.method == 'ownedRetireQuarantine') {
        final a = call.arguments as Map;
        final file = File(p.join(
            a['destinationRoot'] as String, a['relativePath'] as String));
        if (await file.exists()) await file.delete();
      }
    };
    service = PatchBuildService(
        database: Future.value(db),
        runtime: runtime,
        storage: storage,
        native: native);
  });
  tearDown(() async {
    expect(boundary.sessions, isEmpty);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(boundary.channel, null);
    await db.close();
    DatabaseService.resetForTesting();
    await databaseFactory.setDatabasesPath(previousDbPath);
  });
  test(
      'normal build publishes portable receipt; imported result is enforced before installation',
      () async {
    final shared = await SharedMetadataStore.open(
        Directory(p.join(scratch.path, 'shared')),
        factory: databaseFactoryFfiNoIsolate);
    addTearDown(shared.close);
    service = PatchBuildService(
        database: Future.value(db),
        runtime: runtime,
        storage: storage,
        native: native,
        sharedStore: Future.value(shared));
    final recipe = PatchRecipe(
        platformId: 'gba',
        base: patch.bases.single,
        steps: [PatchRecipeStep.fromPatch(patch, patch.payloads.single)],
        engineRevision: _revision);
    PortablePatchRecipe imported(String hash) => PortablePatchRecipe(
        recipe: recipe,
        sourceGameId: game.sourceGameId,
        gameTitle: game.title,
        gameIndexPath: game.indexPath,
        title: 'Balance',
        outputSize: 4,
        outputSha256: hash);
    Future<PatchBuildResult> buildImported(PortablePatchRecipe portable) =>
        service.build(
            catalogue: catalogue,
            indexedGame: game,
            patch: patch,
            payload: patch.payloads.single,
            base: patch.bases.single,
            system: system,
            targetFolder: p.join(scratch.path, 'roms'),
            importedRecipe: portable);
    await expectLater(
        buildImported(imported('f' * 64)),
        throwsA(isA<PatchBuildException>()
            .having((e) => e.code, 'code', 'recipe_output_conflict')));
    expect(await shared.patchRecipes('gba'), isEmpty);
    expect(
        await db.query('installed_artifacts',
            where: 'destination_root=?',
            whereArgs: [p.join(scratch.path, 'roms', 'Hacks')]),
        isEmpty);
    final result = await build();
    final published = (await shared.patchRecipes('gba')).single;
    expect(published.recipe.id, result.recipe.id);
    expect(published.outputSha256, sha256.convert(patched).toString());
    final requests = runtime.requests, applies = applications;
    final reused =
        await buildImported(PortablePatchRecipe.decode(published.encode()));
    expect(reused.reused, isTrue);
    expect(runtime.requests, requests);
    expect(applications, applies);
    await expectLater(
        buildImported(imported('e' * 64)),
        throwsA(isA<PatchBuildException>()
            .having((e) => e.code, 'code', 'recipe_output_conflict')));
    expect((await shared.patchRecipes('gba')).single.outputSha256,
        published.outputSha256);
  });
  test(
      'build uses native canonical input and output roots before reserving transfers',
      () async {
    String canonical(String root) =>
        {'base-download', 'patch-download', 'Hacks'}.contains(p.basename(root))
            ? '$root-canonical'
            : root;
    boundary.canonicalRoot = canonical;
    boundary.before = (call) async {
      if (call.method == 'ownedPrepare') {
        final requested = (call.arguments as Map)['destinationRoot'] as String;
        final resolved = canonical(requested);
        if (resolved != requested &&
            await Directory(requested).exists() &&
            !await Directory(resolved).exists()) {
          // Model one native directory, not two different physical fixtures.
          expect(await Directory(requested).list().isEmpty, isTrue);
          await Directory(requested).rename(resolved);
        } else {
          await Directory(resolved).create(recursive: true);
        }
      }
    };
    final result = await build();
    expect(result.targetRoot, endsWith('Hacks-canonical'));
    final row = (await service.store.forGame('gba', '1379')).single;
    expect(row['targetRoot'], result.targetRoot);
    expect(row['state'], 'ready');
    expect(row['scratchCleanup'], 'complete');
    expect(applications, 1);
    expect(runtime.requests, 2);
    final reused = await build();
    expect(reused.reused, isTrue);
    expect(runtime.requests, 2);
    expect(applications, 1);
  });
  test(
      'build registers independent modified edition, survives service restart and reuses exact bytes',
      () async {
    final result = await build();
    expect(result.reused, isFalse);
    expect(applications, 1);
    expect(result.game.remoteArtifact!.canDownload, isFalse);
    expect(OwnedEmulatorLauncher.supports(result.game, system), isTrue);
    final saved = (await service.store.forGame('gba', '1379')).single;
    expect(saved['state'], 'ready');
    expect(saved['scratchCleanup'], 'complete');
    final cacheRows = await db.query('games',
        where: 'artifact_key=?',
        whereArgs: [result.game.remoteArtifact!.id.key]);
    final editionId = await LibraryStore.catalogueEditions(db,
            cacheRowId: cacheRows.single['id'] as int)
        .single;
    final edition = (await LibraryStore(Future.value(db)).edition(editionId))!;
    expect(edition.patchId, result.recipe.id);
    expect(edition.collectionCategory, 'hacks');
    expect(edition.tags, contains('Hack'));
    final requests = runtime.requests;
    service = PatchBuildService(
        database: Future.value(db),
        runtime: runtime,
        storage: storage,
        native: native);
    final reused = await build();
    expect(reused.reused, isTrue);
    expect(reused.game.identityKey, result.game.identityKey);
    expect(applications, 1);
    expect(runtime.requests, requests);
    final file =
        boundary.files['${result.targetRoot}/${result.game.filename}']!;
    file.bytes[0] = 44;
    file.stamp++;
    expect(await service.existing(result.recipe, CancelToken()), isNull);
    expect((await service.store.forGame('gba', '1379')).single['state'],
        'unavailable');
  });
  test(
      'failed publication resumes stored output without another download or patch invocation',
      () async {
    final mirror = boundary.after;
    var fail = true;
    boundary.after = (call) async {
      await mirror!(call);
      if (call.method == 'ownedClose' && fail && applications > 0) {
        fail = false;
        throw PlatformException(code: 'io_error');
      }
    };
    await expectLater(build(), throwsA(isA<OwnedStorageException>()));
    final row = (await service.store.forGame('gba', '1379')).single;
    expect(row['state'], 'failed');
    final requests = runtime.requests;
    final result = await service.resumePublication(row['buildId'] as String);
    expect(result.game.remoteArtifact!.id.providerId, 'patch-build');
    expect(applications, 1);
    expect(runtime.requests, requests);
    expect(
        (await service.store.get(row['buildId'] as String))!['state'], 'ready');
  });
  test('wrong selected payload or raw base rejects before result publication',
      () async {
    await expectLater(
        service.build(
            catalogue: catalogue,
            indexedGame: game,
            patch: patch,
            payload: IndexedPatchPayload(
                relativePath: 'another.ips',
                sizeBytes: patchBytes.length,
                sha256: sha256.convert(patchBytes).toString(),
                format: PatchFormat.ips),
            base: patch.bases.single,
            system: system,
            targetFolder: p.join(scratch.path, 'roms')),
        throwsA(isA<PatchBuildException>()
            .having((e) => e.code, 'code', 'incompatible_selection')));
    expect(applications, 0);
    expect(await service.store.forPlatform('gba'), isEmpty);
    patch = IndexedRomPatch(
        source: patch.source,
        section: patch.section,
        sourceId: patch.sourceId,
        title: patch.title,
        version: patch.version,
        description: patch.description,
        payloads: patch.payloads,
        unsupportedFiles: [],
        bases: [
          IndexedPatchBase(
              relativePath: patch.bases.single.relativePath,
              sizeBytes: original.length,
              checksums: {'sha256': '0' * 64})
        ]);
    await expectLater(
        build(),
        throwsA(isA<PatchBuildException>()
            .having((e) => e.code, 'code', 'input_fingerprint_mismatch')));
    expect(applications, 0);
    expect((await service.store.forPlatform('gba')).single['state'], 'failed');
  });

  test('cancellation joins actual native completion and prevents publication',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    beforeApply = () async {
      entered.complete();
      await release.future;
    };
    final result = build();
    final failed = expectLater(
        result,
        throwsA(isA<PatchBuildException>()
            .having((e) => e.code, 'code', 'cancelled')));
    await entered.future;
    var finished = false;
    final cancelled = service.cancel().then((_) => finished = true);
    await Future<void>.value();
    expect(finished, isFalse);
    release.complete();
    await cancelled;
    await failed;
    final row = (await service.store.forPlatform('gba')).single;
    expect(row['state'], 'cancelled');
    expect(row['outputArtifact'], isNull);
    expect(await journal.transfer('patch-${row['buildId']}'), isNull);
    expect(row['scratchCleanup'], 'retained_for_retry');
    beforeApply = null;
    final resumed = await build(retryId: row['buildId'] as String);
    expect(resumed.reused, isFalse);
    expect(
        (await service.store.get(row['buildId'] as String))!['state'], 'ready');
    expect((await service.store.forPlatform('gba')), hasLength(1));
  });

  test('real v39 upgrade adds recipes without deleting the existing game cache',
      () async {
    await db.insert('games', {
      'systemSlug': 'gba',
      'filename': 'old.gba',
      'displayName': 'Existing game',
      'url': ''
    });
    await db.execute('DROP TABLE patch_builds');
    await db.setVersion(39);
    await db.close();
    DatabaseService.resetForTesting();
    db = await DatabaseService().database;
    expect(await db.getVersion(), 44);
    expect((await db.query('games')).single['displayName'], 'Existing game');
    expect(await db.query('patch_builds'), isEmpty);
  });
  test(
      'real v40 upgrade preserves existing jobs and adds nullable selection coverage',
      () async {
    await db.insert('metadata_refresh_jobs', {
      'generation': 1,
      'provider_id': 'screenscraper',
      'collection_generation': 'existing',
      'state': 'paused'
    });
    await db.execute(
        'ALTER TABLE metadata_refresh_jobs DROP COLUMN selection_json');
    await db.setVersion(40);
    await db.close();
    DatabaseService.resetForTesting();
    db = await DatabaseService().database;
    expect(await db.getVersion(), 44);
    final row = (await db.query('metadata_refresh_jobs')).single;
    expect(row['collection_generation'], 'existing');
    expect(row['selection_json'], isNull);
    expect(await db.query('patch_builds'), isEmpty);
  });
  test('v42 upgrade adds local patch metadata without changing a paused collector', () async {
    await db.insert('metadata_refresh_jobs', {'generation': 1,
      'provider_id': 'screenscraper', 'collection_generation': 'preserved', 'state': 'paused'});
    final before = await db.query('metadata_refresh_jobs');
    await db.execute('DROP TABLE drive_patch_index_cache');
    await db.execute('DROP TABLE drive_patch_base_links');
    await db.setVersion(42);
    await db.close(); DatabaseService.resetForTesting();
    db = await DatabaseService().database;
    expect(await db.getVersion(), 44);
    expect(await db.query('metadata_refresh_jobs'), before);
    expect(await db.query('drive_patch_index_cache'), isEmpty);
    expect(await db.query('drive_patch_base_links'), isEmpty);
  });
  test('v43 upgrade indexes observed names and preserves recipes and checkpoints', () async {
    await build();
    await db.insert('metadata_refresh_jobs', {'generation': 1,
      'provider_id': 'screenscraper', 'collection_generation': 'preserved', 'state': 'paused'});
    await db.insert('drive_catalogue_state', {
      'scope': 'preserved', 'active': 1, 'pending': 2, 'next_generation': 3,
    });
    for (var i = 0; i < 300; i++) {
      final generation = i.isEven ? 1 : 2;
      final name = i < 2 ? (i == 0 ? "雪's Game.gba" : "雪's game.gba") : 'Other $i.gba';
      await db.insert('drive_catalogue_entries', {
        'scope': 'preserved', 'generation': generation, 'file_id': 'observed-$i',
        'file_name': name, 'parent_id': 'root', 'display_path': name,
        'is_folder': 0, 'record_json': jsonEncode({'name': name}),
      });
    }
    await db.insert('drive_catalogue_work', {
      'scope': 'preserved', 'generation': 2, 'file_id': 'pending-folder',
      'page_token': 'resume-cursor', 'done': 0,
    });
    final tables = ['metadata_refresh_jobs', 'patch_builds', 'installed_artifacts',
      'drive_catalogue_state', 'drive_catalogue_work', 'drive_catalogue_pages',
      'drive_patch_index_cache', 'drive_patch_base_links'];
    final before = {for (final table in tables) table: await db.query(table)};
    final entries = await db.query('drive_catalogue_entries');
    await db.execute('DROP INDEX drive_catalogue_name');
    await db.execute('ALTER TABLE drive_catalogue_entries DROP COLUMN file_name');
    await db.setVersion(43);
    await db.close(); DatabaseService.resetForTesting();
    db = await DatabaseService().database;
    expect(await db.getVersion(), 44);
    expect(await db.query('drive_catalogue_entries'), entries);
    for (final table in tables) {
      expect(await db.query(table), before[table], reason: table);
    }
    expect(await db.rawQuery("SELECT name FROM sqlite_master WHERE name='drive_catalogue_name'"), hasLength(1));
  });
}
