import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/models/config/drive_source_config.dart';
import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/download_item.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';
import 'package:retro_eshop/services/drive/drive_catalogue.dart';
import 'package:retro_eshop/services/drive/drive_runtime.dart';
import 'package:retro_eshop/services/drive/drive_media.dart';
import 'package:retro_eshop/services/owned_storage.dart';
import 'package:retro_eshop/services/transfer_journal.dart';
import 'package:retro_eshop/services/download_queue_manager.dart';
import 'package:retro_eshop/services/storage_service.dart';
import 'package:retro_eshop/services/native_smb_service.dart';

class _Driver implements DriveAuthorizationDriver {
  final signedOut = Completer<void>();
  final finishSignOut = Completer<void>();
  bool? revoked;
  int grants = 0;
  @override
  Future<String?> authenticate({required bool interactive}) async => 'account';
  @override
  Future<String?> authorize(String accountId, List<String> scopes,
      {required bool interactive}) async {
    grants++;
    return 'synthetic-token';
  }

  @override
  Future<void> clearRejectedToken(String accountId, String token) async {}
  @override
  Future<void> signOut({required bool revoke}) async {
    revoked = revoke;
    signedOut.complete();
    await finishSignOut.future;
  }
}

class _Catalogue extends DriveCatalogue {
  final started = Completer<void>();
  final cancelled = Completer<void>();
  final finishRefresh = Completer<void>();
  bool exited = false;
  _Catalogue({Future<Database>? database})
      : super(database ?? Completer<Database>().future);

  @override
  Future<void> refresh(
      {required String sourceId,
      required String accountId,
      required String rootFolderId,
      required DriveCatalogueApi api,
      bool restart = false,
      CancelToken? cancelToken}) async {
    started.complete();
    await cancelToken!.whenCancel;
    cancelled.complete();
    await finishRefresh.future;
    exited = true;
    throw const DriveCatalogueException('cancelled');
  }
}

const _md5 = '7cfdd07889b3295d6a550914ab35e068';
const _transferConfig = ProviderConfig(
    type: ProviderType.drive,
    priority: 1,
    sourceId: 'source',
    path: 'folder',
    drive: DriveSourceConfig(
        accountId: 'account',
        rootFolderId: 'folder',
        serverClientId: 'public-client'));

RemoteArtifact _artifact() => RemoteArtifact(
    id: RemoteArtifactId(
        providerId: 'drive',
        sourceId: 'source',
        accountId: 'account',
        providerFileId: 'file'),
    parentId: 'folder',
    displayName: 'fixture.chd',
    displayPath: 'fixture.chd',
    sizeBytes: 5,
    version: '1',
    providerChecksums: const {'md5': _md5},
    canDownload: true);

class _Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool closed = false;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (closed) throw StateError('Transport already closed');
    if (options.queryParameters['alt'] == 'media') {
      return ResponseBody(
          Stream.value(Uint8List.fromList([1, 2, 3, 4, 5])), 200,
          headers: {
            'content-length': ['5']
          });
    }
    final file = {
      'id': 'file',
      'name': 'fixture.chd',
      'mimeType': 'application/octet-stream',
      'parents': ['folder'],
      'size': '5',
      'version': '1',
      'md5Checksum': _md5,
      'capabilities': {'canDownload': true}
    };
    final folder = {
      'id': 'folder',
      'name': 'Library',
      'mimeType': 'application/vnd.google-apps.folder',
      'parents': <String>[]
    };
    final Object response = options.path == 'files'
        ? {
            'files': [file]
          }
        : options.path.endsWith('/folder')
            ? folder
            : file;
    return ResponseBody.fromString(jsonEncode(response), 200, headers: {
      'content-type': ['application/json']
    });
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

class _NativeStorage {
  final channel = const MethodChannel('runtime-fixture-storage');
  final bytes = <int>[];
  final writeStarted = Completer<void>();
  Future<void>? finishWrite;
  bool published = false;
  bool sessionOpen = false;
  bool targetChanged = false;
  int stamp = 0;
  final calls = <String>[];
  Map<String, Object> get identity => {
        'device': '1',
        'inode': '42',
        'size': bytes.length,
        'modifiedSeconds': 100,
        'modifiedNanos': stamp
      };
  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    final args = Map<String, dynamic>.from(call.arguments as Map);
    switch (call.method) {
      case 'ownedPrepare':
        return {
          'destinationRoot': '/roms',
          'stageRoot': '/owned',
          'destinationVolume': '1',
          'stageVolume': '1',
          'destinationMount': '1',
          'stageMount': '1',
          'destinationFreeBytes': 10000,
          'stageFreeBytes': 10000
        };
      case 'ownedOpen':
        sessionOpen = true;
        return {'session': 'session', 'identity': identity};
      case 'ownedWrite':
        if (!writeStarted.isCompleted) writeStarted.complete();
        await finishWrite;
        expect(args['offset'], bytes.length);
        bytes.addAll(args['bytes'] as Uint8List);
        stamp++;
        return null;
      case 'ownedRead':
        return Uint8List.fromList(bytes.sublist(args['offset'] as int,
            (args['offset'] as int) + (args['length'] as int)));
      case 'ownedCheckpoint':
        return identity;
      case 'ownedPublish':
        published = true;
        return identity;
      case 'ownedInspect':
        return published
            ? {...identity, if (targetChanged) 'inode': '99'}
            : null;
      case 'ownedClose':
        sessionOpen = false;
        return null;
      default:
        throw StateError('Unexpected native method ${call.method}');
    }
  }
}

class _LoadingJournal extends TransferJournal {
  final loading = Completer<void>();
  final finishLoad = Completer<void>();
  _LoadingJournal(super.database);
  @override
  Future<TransferRecord?> transfer(String id) async {
    if (!loading.isCompleted) {
      loading.complete();
      await finishLoad.future;
    }
    return super.transfer(id);
  }
}

class _TransferFixture {
  final Database db;
  final _Driver driver = _Driver();
  final _Transport metadata = _Transport();
  final _Transport media = _Transport();
  final _NativeStorage native = _NativeStorage();
  late final DriveAuthorization authorization = DriveAuthorization(driver);
  late final TransferJournal journal;
  late final DriveCatalogue catalogue;
  _TransferFixture._(this.db);
  static Future<_TransferFixture> create(
      {bool loading = false,
      bool drainRefresh = false,
      bool reserve = true}) async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final fixture = _TransferFixture._(db);
    await TransferJournalSchema.install(db);
    await DriveCatalogueSchema.install(db);
    fixture.journal = loading
        ? _LoadingJournal(Future.value(db))
        : TransferJournal(Future.value(db));
    fixture.catalogue = drainRefresh
        ? _Catalogue(database: Future.value(db))
        : DriveCatalogue(Future.value(db));
    final seed = DriveApi(
        authorization: fixture.authorization,
        accountId: 'account',
        httpClientAdapter: _Transport());
    try {
      await DriveCatalogue(Future.value(db)).refresh(
          sourceId: 'source',
          accountId: 'account',
          rootFolderId: 'folder',
          api: seed);
    } finally {
      seed.close();
    }
    if (reserve) {
      await fixture.journal.create(TransferRecord(
          id: 'transfer',
          artifact: _artifact(),
          destinationRoot: '/roms',
          relativePath: 'fixture.chd',
          stagePath: '/owned/transfer.partial'));
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            fixture.native.channel, fixture.native.handle);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(fixture.native.channel, null);
      await db.close();
    });
    return fixture;
  }

  DriveRuntime runtime() => DriveRuntime(
      catalogue: catalogue,
      journal: journal,
      storage: OwnedStorage(channel: native.channel),
      createAuthorization: (_) => authorization,
      createApi: (auth, account) => DriveApi(
          authorization: auth, accountId: account, httpClientAdapter: metadata),
      createMediaApi: (auth, account) => DriveMediaApi(
          authorization: auth, accountId: account, httpClientAdapter: media));
}

class _QueueStorage extends StorageService {
  String? savedQueue;
  int concurrent = 1;
  bool failWrites = false;
  @override
  int getMaxConcurrentDownloads() => concurrent;
  @override
  Future<void> setMaxConcurrentDownloads(int value) async {
    concurrent = value;
  }

  @override
  String? getDownloadQueue() => savedQueue;
  @override
  Future<void> setDownloadQueue(String json) async {
    if (failWrites) throw StateError('Synthetic preference failure');
    savedQueue = json;
  }

  @override
  Future<void> clearDownloadQueue() async {
    savedQueue = null;
  }
}

const _system = SystemModel(
    id: 'psx',
    name: 'PlayStation',
    manufacturer: 'Sony',
    releaseYear: 1994,
    romExtensions: ['.chd']);
GameItem _game() => GameItem(
    filename: 'fixture.chd',
    displayName: 'Fixture',
    url: 'drive-artifact:synthetic',
    providerConfig: _transferConfig,
    remoteArtifact: _artifact());

Future<DownloadItem> _queueTerminal(DownloadQueueManager queue) {
  final result = Completer<DownloadItem>();
  void changed() {
    final item = queue.state.queue
        .where((i) => !i.isActive && i.status != DownloadStatus.queued)
        .firstOrNull;
    if (item != null &&
        !item.isActive &&
        item.status != DownloadStatus.queued &&
        !result.isCompleted) {
      result.complete(item);
    }
  }

  queue.addListener(changed);
  changed();
  return result.future.whenComplete(() => queue.removeListener(changed));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  const config = ProviderConfig(
      type: ProviderType.drive,
      priority: 1,
      sourceId: 'source',
      drive: DriveSourceConfig(
          accountId: 'account',
          rootFolderId: 'folder',
          serverClientId: 'public-client'));

  for (final revoke in [false, true]) {
    test(
        'disconnect revoke=$revoke waits for cancelled refresh and native exit',
        () async {
      final driver = _Driver();
      final catalogue = _Catalogue();
      final runtime = DriveRuntime(
          catalogue: catalogue,
          createAuthorization: (_) => DriveAuthorization(driver));
      final refresh = expectLater(
          runtime.refreshConfig(config),
          throwsA(isA<DriveCatalogueException>()
              .having((e) => e.code, 'code', 'cancelled')));
      await catalogue.started.future;

      var disconnected = false;
      final disconnect = runtime.disconnect(revoke: revoke).then((_) {
        disconnected = true;
      });
      await catalogue.cancelled.future;
      await driver.signedOut.future;
      expect(driver.revoked, revoke);
      expect(disconnected, isFalse);
      expect(() => runtime.authorizationFor('public-client'),
          throwsA(isA<DriveAuthorizationException>()));
      await expectLater(runtime.refreshConfig(config),
          throwsA(isA<DriveAuthorizationException>()));

      driver.finishSignOut.complete();
      expect(disconnected, isFalse);
      catalogue.finishRefresh.complete();
      await refresh;
      await disconnect;
      expect(catalogue.exited, isTrue);
      expect(disconnected, isTrue);
      expect(
          runtime.authorizationFor('public-client'), isA<DriveAuthorization>());
      expect(config.drive!.rootFolderId, 'folder');
    });
  }

  test('disconnect before setup requires no database or native initialization',
      () async {
    final runtime = DriveRuntime(
        createAuthorization: (_) => throw StateError('not expected'));
    await runtime.disconnect();
  });

  test(
      'runtime routes exact transfer through real boundary and request-time media authorization',
      () async {
    final fixture = await _TransferFixture.create();
    final runtime = fixture.runtime();
    final grantsBefore = fixture.driver.grants;
    final operation = await runtime.startTransfer(
        config: _transferConfig, transferId: 'transfer');
    final completed = await operation.result;
    expect(completed.lifecycle, TransferLifecycle.completed);
    expect(fixture.native.bytes, [1, 2, 3, 4, 5]);
    expect(fixture.native.sessionOpen, isFalse);
    expect(fixture.driver.grants, greaterThan(grantsBefore));
    expect(fixture.media.requests.single.path, 'files/file');
    expect(fixture.media.requests.single.headers['Authorization'],
        'Bearer synthetic-token');
    expect(
        fixture.metadata.requests.every((request) =>
            request.path == 'files/file' || request.path == 'files/folder'),
        isTrue);
    expect(jsonEncode(completed.toJson()), isNot(contains('synthetic-token')));
    fixture.driver.finishSignOut.complete();
    await runtime.disconnect();
    expect(fixture.metadata.closed, isTrue);
    expect(fixture.media.closed, isTrue);
    expect((await fixture.journal.transfer('transfer'))!.lifecycle,
        TransferLifecycle.completed);
  });

  test('queue reservation is restart-stable and creates no payload or stage',
      () async {
    final fixture = await _TransferFixture.create();
    // The fixture pre-reserves its legacy test target; use an independent name.
    final artifact = RemoteArtifact.fromJson({
      ..._artifact().toJson(),
      'displayName': 'reserved.chd',
      'displayPath': 'reserved.chd'
    });
    final runtime = fixture.runtime();
    final first = await runtime.reserveTransfer(
        config: _transferConfig,
        artifact: artifact,
        destinationRoot: '/roms',
        relativePath: 'reserved.chd');
    final second = await runtime.reserveTransfer(
        config: _transferConfig,
        artifact: artifact,
        destinationRoot: '/roms',
        relativePath: 'reserved.chd');
    expect(second.id, first.id);
    expect(first.stagePath, '/owned/${first.id}.partial');
    expect(first.lifecycle, TransferLifecycle.queued);
    expect(fixture.native.calls, ['ownedPrepare', 'ownedPrepare']);
    expect(fixture.media.requests, isEmpty);
    expect(fixture.metadata.requests, isEmpty);
    expect(
        (await fixture.journal.transfer(first.id))!.artifact.id, artifact.id);
  });

  test('reservation rejects a mismatched filename before native storage',
      () async {
    final fixture = await _TransferFixture.create();
    final runtime = fixture.runtime();
    await expectLater(
        runtime.reserveTransfer(
            config: _transferConfig,
            artifact: _artifact(),
            destinationRoot: '/roms',
            relativePath: '../escape.chd'),
        throwsA(isA<DriveTransferException>()));
    expect(fixture.native.calls, isEmpty);
    expect(fixture.media.requests, isEmpty);
  });

  test('checkpoint notifications describe committed journal revisions',
      () async {
    final fixture = await _TransferFixture.create();
    final runtime = fixture.runtime();
    final checkpoints = <TransferRecord>[];
    final operation = await runtime.startTransfer(
        config: _transferConfig,
        transferId: 'transfer',
        onCheckpoint: checkpoints.add);
    final completed = await operation.result;
    expect(
        checkpoints.map((r) => r.lifecycle),
        containsAllInOrder([
          TransferLifecycle.queued,
          TransferLifecycle.transferring,
          TransferLifecycle.verifying,
          TransferLifecycle.publishing,
          TransferLifecycle.completed
        ]));
    expect(checkpoints.last.revision, completed.revision);
    expect(checkpoints.last.durableOffset, 5);
    expect((await fixture.db.query('installed_artifacts')), hasLength(1));
    fixture.driver.finishSignOut.complete();
    await runtime.disconnect();
  });

  test('normal queue completes only after real journal installation commit',
      () async {
    final fixture = await _TransferFixture.create(reserve: false);
    final runtime = fixture.runtime();
    final storage = _QueueStorage();
    final queue = DownloadQueueManager(storage, NativeSmbService(),
        driveRuntime: runtime);
    final complete = _queueTerminal(queue);
    final hooks = <DownloadItem>[];
    queue.onItemCompleted = hooks.add;
    queue.addToQueue(_game(), _system, '/roms');
    final item = await complete;
    expect(item.status, DownloadStatus.completed, reason: item.error);
    expect(item.transferId, isNotNull);
    expect((await fixture.journal.transfer(item.transferId!))!.lifecycle,
        TransferLifecycle.completed);
    expect(await fixture.db.query('installed_artifacts'), hasLength(1));
    expect(hooks, hasLength(1));
    expect(fixture.native.sessionOpen, isFalse);
    await queue.close();
    queue.dispose();
    fixture.driver.finishSignOut.complete();
    await runtime.disconnect();
  });

  test('synchronous pause listener joins an attempt before preparation begins',
      () async {
    final fixture = await _TransferFixture.create(reserve: false);
    final runtime = fixture.runtime();
    final queue = DownloadQueueManager(_QueueStorage(), NativeSmbService(),
        driveRuntime: runtime);
    Future<void>? pause;
    queue.addListener(() {
      if (queue.state.activeCount == 1 && pause == null) {
        pause = queue.pauseDownload(queue.state.queue.single.id);
      }
    });
    queue.addToQueue(_game(), _system, '/roms');
    await pause;
    expect(queue.state.queue.single.status, DownloadStatus.paused);
    expect(fixture.native.calls, isEmpty);
    await queue.close();
    queue.dispose();
  });

  test('completion observer failure cannot undo the committed installation',
      () async {
    final fixture = await _TransferFixture.create(reserve: false);
    final runtime = fixture.runtime();
    final queue = DownloadQueueManager(_QueueStorage(), NativeSmbService(),
        driveRuntime: runtime);
    final terminal = _queueTerminal(queue);
    final observerErrors = <Object>[];
    queue.onItemCompleted =
        (_) => throw StateError('Synthetic observer failure');
    runZonedGuarded(() => queue.addToQueue(_game(), _system, '/roms'),
        (error, _) => observerErrors.add(error));
    final item = await terminal;
    await queue.close();
    expect(observerErrors.single, isA<StateError>());
    expect(queue.state.queue.single.status, DownloadStatus.completed);
    expect((await fixture.journal.transfer(item.transferId!))!.lifecycle,
        TransferLifecycle.completed);
    expect(fixture.native.sessionOpen, isFalse);
    queue.dispose();
    fixture.driver.finishSignOut.complete();
    await runtime.disconnect();
  });

  test('a completion listener may clear its row without corrupting the hook',
      () async {
    final fixture = await _TransferFixture.create(reserve: false);
    final runtime = fixture.runtime();
    final queue = DownloadQueueManager(_QueueStorage(), NativeSmbService(),
        driveRuntime: runtime);
    final hook = Completer<DownloadItem>();
    queue.onItemCompleted = hook.complete;
    queue.addListener(() {
      if (queue.state.completedItems.isNotEmpty) queue.clearCompleted();
    });
    queue.addToQueue(_game(), _system, '/roms');
    final item = await hook.future;
    await queue.close();
    expect(item.status, DownloadStatus.completed);
    expect(item.transferId, isNotNull);
    expect(queue.state.queue, isEmpty);
    expect(await fixture.db.query('installed_artifacts'), hasLength(1));
    queue.dispose();
    fixture.driver.finishSignOut.complete();
    await runtime.disconnect();
  });

  test('failed queue persistence blocks reservation and payload work',
      () async {
    final fixture = await _TransferFixture.create(reserve: false);
    final storage = _QueueStorage()..failWrites = true;
    final queue = DownloadQueueManager(storage, NativeSmbService(),
        driveRuntime: fixture.runtime());
    final terminal = _queueTerminal(queue);
    queue.addToQueue(_game(), _system, '/roms');
    expect((await terminal).status, DownloadStatus.error);
    expect(await fixture.db.query('transfer_records'), isEmpty);
    expect(fixture.native.calls, isEmpty);
    expect(fixture.media.requests, isEmpty);
    await queue.close();
    queue.dispose();
  });

  test(
      'restoring paused and authorization-needed Drive entries does not auto-retry',
      () async {
    final fixture = await _TransferFixture.create(reserve: false);
    final storage = _QueueStorage();
    storage.savedQueue = jsonEncode([
      DownloadItem(
              id: 'paused',
              game: _game(),
              system: _system,
              targetFolder: '/roms',
              status: DownloadStatus.paused,
              transferId: 'durable-id',
              receivedBytes: 3,
              totalBytes: 5)
          .toJson(),
      DownloadItem(
              id: 'auth',
              game: _game(),
              system: _system,
              targetFolder: '/roms',
              status: DownloadStatus.awaitingAuthorization)
          .toJson(),
      DownloadItem(
              id: 'publishing',
              game: _game(),
              system: _system,
              targetFolder: '/roms',
              status: DownloadStatus.publishing,
              transferId: 'publication-id',
              receivedBytes: 5)
          .toJson(),
    ]);
    final queue = DownloadQueueManager(storage, NativeSmbService(),
        driveRuntime: fixture.runtime());
    queue.restoreQueue([_system]);
    expect(queue.state.queue.map((i) => i.status), [
      DownloadStatus.paused,
      DownloadStatus.awaitingAuthorization,
      DownloadStatus.paused
    ]);
    expect(queue.state.queue.first.transferId, 'durable-id');
    expect(queue.state.queue.first.receivedBytes, 3);
    expect(queue.state.activeCount, 0);
    expect(fixture.native.calls, isEmpty);
    expect(fixture.media.requests, isEmpty);
    await queue.close();
    queue.dispose();
  });

  test(
      'mixed-source queued reorder is persisted without starting or moving the active attempt',
      () async {
    final fixture = await _TransferFixture.create(reserve: false);
    final finishWrite = Completer<void>();
    fixture.native.finishWrite = finishWrite.future;
    final runtime = fixture.runtime();
    final storage = _QueueStorage();
    final queue = DownloadQueueManager(storage, NativeSmbService(),
        driveRuntime: runtime);
    final terminal = _queueTerminal(queue);
    final active = queue.addToQueue(_game(), _system, '/roms');
    await Future.any([fixture.native.writeStarted.future, terminal]);
    expect(fixture.native.writeStarted.isCompleted, isTrue);
    GameItem web(String name) => GameItem(
        filename: '$name.chd',
        displayName: name,
        url: 'https://example.invalid/$name.chd',
        providerConfig: const ProviderConfig(
            type: ProviderType.web,
            priority: 1,
            url: 'https://example.invalid'));
    final older = queue.addToQueue(web('older'), _system, '/roms');
    final newer = queue.addToQueue(web('newer'), _system, '/roms');
    expect(queue.state.queuedItems.map((i) => i.id), [newer, older]);
    queue.moveQueued(older, 0);
    expect(queue.state.queuedItems.map((i) => i.id), [older, newer]);
    expect(queue.state.activeDownloads.single.id, active);
    final close = queue.close();
    finishWrite.complete();
    await close;
    await terminal;
    final saved = (jsonDecode(storage.savedQueue!) as List).cast<Map>();
    expect(saved.where((i) => i['status'] == 'queued').map((i) => i['id']),
        [older, newer]);
    expect(fixture.media.requests, hasLength(1));
    queue.dispose();
    fixture.driver.finishSignOut.complete();
    await runtime.disconnect();
  });

  test(
      're-enqueue cannot claim completion from an externally replaced installed file',
      () async {
    final fixture = await _TransferFixture.create(reserve: false);
    final runtime = fixture.runtime();
    final queue = DownloadQueueManager(_QueueStorage(), NativeSmbService(),
        driveRuntime: runtime);
    final first = _queueTerminal(queue);
    final id = queue.addToQueue(_game(), _system, '/roms');
    expect((await first).status, DownloadStatus.completed);
    await queue.removeDownload(id);
    fixture.native.targetChanged = true;
    final second = _queueTerminal(queue);
    queue.addToQueue(_game(), _system, '/roms');
    expect((await second).status, DownloadStatus.error);
    expect(fixture.media.requests, hasLength(1));
    expect(fixture.native.targetChanged, isTrue);
    await queue.close();
    queue.dispose();
    fixture.driver.finishSignOut.complete();
    await runtime.disconnect();
  });

  test(
      'queue pause joins native write, retains reservation and resumes without redownload',
      () async {
    final fixture = await _TransferFixture.create(reserve: false);
    final finishWrite = Completer<void>();
    fixture.native.finishWrite = finishWrite.future;
    final runtime = fixture.runtime();
    final storage = _QueueStorage();
    final queue = DownloadQueueManager(storage, NativeSmbService(),
        driveRuntime: runtime);
    final earlyTerminal = _queueTerminal(queue);
    final id = queue.addToQueue(_game(), _system, '/roms');
    await Future.any([fixture.native.writeStarted.future, earlyTerminal]);
    expect(fixture.native.writeStarted.isCompleted, isTrue,
        reason: queue.state.queue.single.error);
    var stopped = false;
    final pause = queue.pauseDownload(id).then((_) {
      stopped = true;
    });
    expect(stopped, isFalse);
    expect(queue.state.activeCount, 1);
    finishWrite.complete();
    await pause;
    final paused = await earlyTerminal;
    expect(paused.status, DownloadStatus.paused);
    expect(paused.receivedBytes, 5);
    expect(fixture.native.sessionOpen, isFalse);
    expect(await fixture.db.query('installed_artifacts'), isEmpty);
    expect(jsonDecode(storage.savedQueue!).single['transferId'],
        paused.transferId);
    final complete = Completer<DownloadItem>();
    queue.onItemCompleted = complete.complete;
    queue.retryDownload(id);
    final installed = await complete.future;
    expect(installed.transferId, paused.transferId);
    expect(fixture.media.requests, hasLength(1));
    await queue.close();
    queue.dispose();
    fixture.driver.finishSignOut.complete();
    await runtime.disconnect();
  });

  test(
      'disconnect joins mixed active refresh and transfer before closing transports',
      () async {
    final fixture = await _TransferFixture.create(drainRefresh: true);
    final finishWrite = Completer<void>();
    fixture.native.finishWrite = finishWrite.future;
    final runtime = fixture.runtime();
    final operation = await runtime.startTransfer(
        config: _transferConfig, transferId: 'transfer');
    await fixture.native.writeStarted.future;
    final catalogue = fixture.catalogue as _Catalogue;
    final refresh = expectLater(runtime.refreshConfig(_transferConfig),
        throwsA(isA<DriveCatalogueException>()));
    await catalogue.started.future;
    var disconnected = false;
    final disconnect = runtime.disconnect().then((_) {
      disconnected = true;
    });
    await catalogue.cancelled.future;
    await fixture.driver.signedOut.future;
    expect(disconnected, isFalse);
    expect(fixture.media.closed, isFalse);
    expect(fixture.metadata.closed, isFalse);
    await expectLater(
        runtime.startTransfer(config: _transferConfig, transferId: 'transfer'),
        throwsA(isA<DriveAuthorizationException>()));
    fixture.driver.finishSignOut.complete();
    catalogue.finishRefresh.complete();
    await refresh;
    expect(disconnected, isFalse);
    expect(fixture.native.sessionOpen, isTrue);
    finishWrite.complete();
    final paused = await operation.result;
    await disconnect;
    expect(paused.lifecycle, TransferLifecycle.paused);
    expect(paused.durableOffset, 5);
    expect(fixture.native.bytes, [1, 2, 3, 4, 5]);
    expect(fixture.native.published, isFalse);
    expect(fixture.native.sessionOpen, isFalse);
    expect(fixture.media.closed, isTrue);
    expect(fixture.metadata.closed, isTrue);
    expect(await fixture.db.query('installed_artifacts'), isEmpty);
  });

  test(
      'pending start reserves transfer ID and cannot cross a completed disconnect',
      () async {
    final fixture = await _TransferFixture.create(loading: true);
    final runtime = fixture.runtime();
    final loading = fixture.journal as _LoadingJournal;
    final pending = runtime
        .startTransfer(config: _transferConfig, transferId: 'transfer')
        .then<Object>((operation) => operation,
            onError: (Object error, StackTrace _) => error);
    await Future.any<Object?>([loading.loading.future, pending]);
    expect(loading.loading.isCompleted, isTrue);
    await expectLater(
        runtime.startTransfer(config: _transferConfig, transferId: 'transfer'),
        throwsStateError);
    await runtime.disconnect();
    loading.finishLoad.complete();
    expect(await pending, isA<DriveAuthorizationException>());
    expect(fixture.native.calls, isEmpty);
    expect(fixture.metadata.requests, isEmpty);
    expect(fixture.media.requests, isEmpty);
    expect((await fixture.journal.transfer('transfer'))!.lifecycle,
        TransferLifecycle.queued);
  });

  test(
      'wrong source account and configured subtree cannot route transfer bytes',
      () async {
    final fixture = await _TransferFixture.create();
    final runtime = fixture.runtime();
    final wrongSource = ProviderConfig(
        type: ProviderType.drive,
        priority: 1,
        sourceId: 'different',
        path: 'folder',
        drive: _transferConfig.drive);
    await expectLater(
        runtime.startTransfer(config: wrongSource, transferId: 'transfer'),
        throwsA(isA<DriveTransferException>()));
    final wrongAccount = ProviderConfig(
        type: ProviderType.drive,
        priority: 1,
        sourceId: 'source',
        path: 'folder',
        drive: const DriveSourceConfig(
            accountId: 'different',
            rootFolderId: 'folder',
            serverClientId: 'public-client'));
    await expectLater(
        runtime.startTransfer(config: wrongAccount, transferId: 'transfer'),
        throwsA(isA<DriveTransferException>()));
    final wrongFolder = ProviderConfig(
        type: ProviderType.drive,
        priority: 1,
        sourceId: 'source',
        path: 'outside',
        drive: _transferConfig.drive);
    final operation = await runtime.startTransfer(
        config: wrongFolder, transferId: 'transfer');
    final failed = await operation.result;
    expect(failed.lifecycle, TransferLifecycle.failed);
    expect(fixture.native.calls, isEmpty);
    expect(fixture.media.requests, isEmpty);
    fixture.driver.finishSignOut.complete();
    await runtime.disconnect();
  });
}
