import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/models/config/drive_source_config.dart';
import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';
import 'package:retro_eshop/services/drive/drive_catalogue.dart';
import 'package:retro_eshop/services/drive/drive_runtime.dart';
import 'package:retro_eshop/services/drive/drive_media.dart';
import 'package:retro_eshop/services/owned_storage.dart';
import 'package:retro_eshop/services/transfer_journal.dart';

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
        return published ? identity : null;
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
      {bool loading = false, bool drainRefresh = false}) async {
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
    await fixture.journal.create(TransferRecord(
        id: 'transfer',
        artifact: _artifact(),
        destinationRoot: '/roms',
        relativePath: 'fixture.chd',
        stagePath: '/owned/transfer.partial'));
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
