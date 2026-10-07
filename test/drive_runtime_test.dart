import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as p;

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
import 'package:retro_eshop/models/owned_removal_record.dart';
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
import 'package:retro_eshop/services/installation_index.dart';
import 'package:retro_eshop/services/owned_installation_removal.dart';

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

class _HeldObservationJournal extends TransferJournal {
  final entered = Completer<void>(), release = Completer<void>();
  final bool fail;
  _HeldObservationJournal(super.database, {this.fail = false});
  @override
  Future<void> saveByteObservation(DriveLocalCloudObservation observation) async {
    entered.complete();
    await release.future;
    if (fail) throw StateError('Synthetic journal failure');
    await super.saveByteObservation(observation);
  }
}
const _transferConfig = ProviderConfig(
    type: ProviderType.drive,
    priority: 1,
    sourceId: 'source',
    path: 'folder',
    drive: DriveSourceConfig(
        accountId: 'account',
        rootFolderId: 'folder',
        serverClientId: 'public-client'));

RemoteArtifact _artifact({int size = 5, String name = 'fixture.chd'}) => RemoteArtifact(
    id: RemoteArtifactId(
        providerId: 'drive',
        sourceId: 'source',
        accountId: 'account',
        providerFileId: 'file'),
    parentId: 'folder',
    displayName: name,
    displayPath: name,
    sizeBytes: size,
    version: '1',
    providerChecksums: const {'md5': _md5},
    canDownload: true);

class _Transport implements HttpClientAdapter {
  final int size;
  final String name;
  String version = '1';
  Future<ResponseBody> Function(RequestOptions, Future<void>?)? mediaResponse;
  _Transport({this.size = 5, this.name = 'fixture.chd'});
  final requests = <RequestOptions>[];
  bool closed = false;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (closed) throw StateError('Transport already closed');
    if (options.queryParameters['alt'] == 'media') {
      if (mediaResponse != null) return mediaResponse!(options, cancelFuture);
      return ResponseBody(
          Stream.value(Uint8List.fromList([1, 2, 3, 4, 5])), 200,
          headers: {
            'content-length': ['5']
          });
    }
    final file = {
      'id': 'file',
      'name': name,
      'mimeType': 'application/octet-stream',
      'parents': ['folder'],
      'size': '$size',
      'version': version,
      'md5Checksum': _md5,
      'capabilities': {'canDownload': true}
    };
    final folder = {
      'id': 'folder',
      'name': 'Library',
      'mimeType': 'application/vnd.google-apps.folder',
      'parents': <String>[]
    };
    if (options.uri.toString() == 'https://www.googleapis.com/batch/drive/v3') {
      expect(options.method, 'POST');
      final body = options.data as String;
      final parts =
          RegExp(r'Content-ID: <folder-(\d+)>').allMatches(body).toList();
      expect(parts, hasLength(1));
      expect(body, contains('GET /drive/v3/files/folder?'));
      return ResponseBody.fromString(
          '${parts.map((part) => '--fixture_batch\r\n'
              'Content-Type: application/http\r\n'
              'Content-ID: <response-folder-${part.group(1)}>\r\n\r\n'
              'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n'
              '${jsonEncode(folder)}\r\n').join()}'
          '--fixture_batch--\r\n',
          200,
          headers: {
            'content-type': ['multipart/mixed; boundary=fixture_batch']
          });
    }
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
  Map<String, Object?> archiveObservation = {
    'container': {'sizeBytes': 5, 'md5': _md5},
    'raw': {
      'kind': 'rawRom',
      'filename': 'Game.z64',
      'sizeBytes': 8192,
      'crc32': '12345678',
      'md5': 'b' * 32,
      'sha1': 'c' * 40
    },
  };
  Future<void> Function()? onArchiveRead;
  String archivePlatform = 'n64';
  final channel = const MethodChannel('runtime-fixture-storage');
  final bytes = <int>[];
  final writeStarted = Completer<void>();
  Future<void>? finishWrite;
  bool published = false;
  bool invalidArchive = false;
  bool sessionOpen = false;
  bool targetChanged = false;
  bool copyOnly = false;
  bool stagePresent = false;
  final copiedBytes = <int>[];
  int copyStamp = 0;
  String? retirementFailure;
  Future<void>? finishRetirement;
  final retirementStarted = Completer<void>();
  void Function()? onRetirementStarted;
  Future<void>? finishClose;
  final closeStarted = Completer<void>();
  int stamp = 0;
  final calls = <String>[];
  bool quarantinePresent = false;
  final quarantineStarted = Completer<void>();
  Future<void>? finishQuarantineRetirement;
  final quarantineRetirementStarted = Completer<void>();
  Map<String, Object> get identity => {
        'device': '1',
        'inode': '42',
        'size': bytes.length,
        'modifiedSeconds': 100,
        'modifiedNanos': stamp
      };
  Map<String, Object> get copyIdentity => {
        'device': '1',
        'inode': '43',
        'size': copiedBytes.length,
        'modifiedSeconds': 100,
        'modifiedNanos': copyStamp
      };
  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    final args = Map<String, dynamic>.from(call.arguments as Map);
    switch (call.method) {
      case 'ownedReadArchiveIdentifier':
        expect(args['destinationRoot'], '/roms');
        expect(args['relativePath'], 'fixture.7z');
        expect(args['platformId'], archivePlatform);
        await onArchiveRead?.call();
        return archiveObservation;
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
        if (args['mode'] == 'quarantine') {
          expect(quarantinePresent, isTrue);
          expect(args['expectedIdentity'], identity);
        } else if (args['mode'] != 'published') {
          stagePresent = true;
        } else {
          expect(args['durableOffset'], bytes.length);
          expect(args['expectedIdentity'], identity);
        }
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
      case 'ownedValidateGameGearZip':
      case 'ownedValidateN64SevenZip':
      case 'ownedValidateN64Zip':
        expect(sessionOpen, isTrue);
        if (invalidArchive) throw PlatformException(code: 'unsupported_archive');
        return null;
      case 'ownedPublish':
        if (copyOnly) throw PlatformException(code: 'unsupported');
        published = true;
        return identity;
      case 'ownedCopyOpen':
        expect(sessionOpen, isTrue);
        expect(args['expectedIdentity'], identity);
        expect(args['durableOffset'], copiedBytes.length);
        if (args['destinationIdentity'] == null) {
          expect(published, isFalse);
        } else {
          expect(args['destinationIdentity'], copyIdentity);
        }
        published = true;
        return copyIdentity;
      case 'ownedCopyChunk':
        expect(sessionOpen, isTrue);
        expect(args['offset'], copiedBytes.length);
        final offset = args['offset'] as int;
        copiedBytes
            .addAll(bytes.sublist(offset, offset + (args['length'] as int)));
        copyStamp++;
        return copiedBytes.length;
      case 'ownedCopyCheckpoint':
        return copyIdentity;
      case 'ownedCopyRead':
        return Uint8List.fromList(copiedBytes.sublist(args['offset'] as int,
            (args['offset'] as int) + (args['length'] as int)));
      case 'ownedCopyFinish':
        expect(args['expectedIdentity'], copyIdentity);
        expect(copiedBytes, bytes);
        return copyIdentity;
      case 'ownedInspect':
        if ((args['stagePath'] as String).contains('removal-') &&
            args['published'] != true) {
          return quarantinePresent ? identity : null;
        }
        if (copyOnly) {
          if (args['published'] != true) return stagePresent ? identity : null;
          return published
              ? {...copyIdentity, if (targetChanged) 'inode': '99'}
              : null;
        }
        return published
            ? {...identity, if (targetChanged) 'inode': '99'}
            : null;
      case 'ownedRetireStage':
        if (!retirementStarted.isCompleted) retirementStarted.complete();
        onRetirementStarted?.call();
        await finishRetirement;
        if (retirementFailure != null) {
          throw PlatformException(code: retirementFailure!);
        }
        expect(sessionOpen, isFalse);
        expect(args['installedIdentity'], copyIdentity);
        if (stagePresent) expect(args['expectedIdentity'], identity);
        stagePresent = false;
        return null;
      case 'ownedQuarantine':
        expect(sessionOpen, isFalse);
        expect(args['expectedIdentity'], identity);
        if (!quarantinePresent) {
          expect(published, isTrue);
          published = false;
          quarantinePresent = true;
        }
        if (!quarantineStarted.isCompleted) quarantineStarted.complete();
        return identity;
      case 'ownedRetireQuarantine':
        expect(sessionOpen, isFalse);
        if (!quarantineRetirementStarted.isCompleted) {
          quarantineRetirementStarted.complete();
        }
        await finishQuarantineRetirement;
        expect(args['expectedIdentity'], identity);
        quarantinePresent = false;
        return null;
      case 'ownedClose':
        if (!closeStarted.isCompleted) closeStarted.complete();
        await finishClose;
        sessionOpen = false;
        return null;
      default:
        throw StateError('Unexpected native method ${call.method}');
    }
  }
}

class _RetirementAckFailure extends TransferJournal {
  int acknowledgements = 0;
  _RetirementAckFailure(super.database);
  @override
  Future<TransferRecord> stageRetirementResult(TransferRecord record,
      {String? issue}) async {
    acknowledgements++;
    if (acknowledgements == 1) {
      throw StateError(
          'Synthetic postcommit retirement acknowledgement failure');
    }
    return super.stageRetirementResult(record, issue: issue);
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

class _RecoveryJournal extends TransferJournal {
  int recoveryPasses = 0;
  int removalPasses = 0;
  Object? enumerationError;
  _RecoveryJournal(super.database);
  @override
  Stream<OwnedRemovalRecord> pendingRemovals(
      {bool Function()? shouldContinue}) async* {
    removalPasses++;
    if (enumerationError != null) throw enumerationError!;
    yield* super.pendingRemovals(shouldContinue: shouldContinue);
  }

  @override
  Stream<TransferRecord> pendingStageRetirements(
      {int batchSize = 128, bool Function()? shouldContinue}) async* {
    recoveryPasses++;
    if (enumerationError != null) throw enumerationError!;
    yield* super.pendingStageRetirements(
        batchSize: batchSize, shouldContinue: shouldContinue);
  }
}

class _TransferFixture {
  final Database db;
  final _Driver driver = _Driver();
  final _Transport metadata;
  final _Transport media;
  final _NativeStorage native = _NativeStorage();
  late final DriveAuthorization authorization = DriveAuthorization(driver);
  late final TransferJournal journal;
  late final DriveCatalogue catalogue;
  _TransferFixture._(this.db, int size, String name)
      : metadata = _Transport(size: size, name: name),
        media = _Transport(size: size, name: name);
  static Future<_TransferFixture> create(
      {int size = 5,
      String name = 'fixture.chd',
      bool loading = false,
      bool drainRefresh = false,
      bool retirementAckFailure = false,
      TransferJournal Function(Future<Database>)? createJournal,
      bool reserve = true}) async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final fixture = _TransferFixture._(db, size, name);
    await TransferJournalSchema.install(db);
    await DriveCatalogueSchema.install(db);
    fixture.journal = createJournal?.call(Future.value(db)) ??
        (loading
            ? _LoadingJournal(Future.value(db))
            : retirementAckFailure
                ? _RetirementAckFailure(Future.value(db))
                : TransferJournal(Future.value(db)));
    fixture.catalogue = drainRefresh
        ? _Catalogue(database: Future.value(db))
        : DriveCatalogue(Future.value(db));
    final seed = DriveApi(
        authorization: fixture.authorization,
        accountId: 'account',
        httpClientAdapter: _Transport(size: size, name: name));
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
          artifact: _artifact(name: name),
          destinationRoot: '/roms',
          relativePath: name,
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

Future<({DriveRuntime runtime, TransferRecord record})> _pendingStage(
    _TransferFixture fixture) async {
  fixture.native.copyOnly = true;
  fixture.native.retirementFailure = 'access_denied';
  final runtime = fixture.runtime();
  final operation = await runtime.startTransfer(
      config: _transferConfig, transferId: 'transfer');
  final record = await operation.result;
  expect(record.lifecycle, TransferLifecycle.completed);
  expect(record.stageRetired, isFalse);
  return (runtime: runtime, record: record);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  test('explicit adoption compares current bytes and commits a reusable owner', () async {
    final fixture = await _TransferFixture.create(reserve: false);
    fixture.native.bytes.addAll([1,2,3,4,5]);
    fixture.native.published = true;
    final runtime = fixture.runtime();
    final installed = await runtime.adoptLocalCloudBytes(
        config: _transferConfig, artifact: _artifact(), destinationRoot: '/roms',
        relativePath: 'fixture.chd', supportedExtensions: {'.chd'},
        cancellation: CancelToken());
    final record = (await fixture.journal.transfer(installed.transferId))!;
    expect(record.lifecycle, TransferLifecycle.completed);
    expect(record.publication!.method.name, 'adopt');
    expect(record.stageIdentity, isNull);
    expect(record.stageRetired, isTrue);
    expect(fixture.native.bytes, [1,2,3,4,5]);
    expect(fixture.native.sessionOpen, isFalse);
    expect(fixture.native.stagePresent, isFalse);
    expect(fixture.media.requests, hasLength(1));
    expect(await fixture.db.query('owned_removals'), isEmpty);
    expect(await InstallationIndex(fixture.journal,
        storage: OwnedStorage(channel: fixture.native.channel))
        .resolveArtifact(_artifact(), '/roms'), p.normalize(p.absolute('/roms/fixture.chd')));
    // Existing durable owned removal, not an alternate migration delete engine.
    await OwnedInstallationRemoval(fixture.journal,
        storage: OwnedStorage(channel: fixture.native.channel)).remove(installed);
    expect(fixture.native.published, isFalse);
    expect(fixture.native.quarantinePresent, isFalse);
    expect(await fixture.db.query('installed_artifacts'), isEmpty);
  });
  test('an existing transfer owner prevents adoption without file changes', () async {
    final fixture = await _TransferFixture.create();
    fixture.native.bytes.addAll([1,2,3,4,5]);
    fixture.native.published = true;
    await expectLater(fixture.runtime().adoptLocalCloudBytes(
        config: _transferConfig, artifact: _artifact(), destinationRoot: '/roms',
        relativePath: 'fixture.chd', supportedExtensions: {'.chd'},
        cancellation: CancelToken()), throwsStateError);
    expect(await fixture.db.query('transfer_records'), hasLength(1));
    expect(await fixture.db.query('installed_artifacts'), isEmpty);
    expect(fixture.native.bytes, [1,2,3,4,5]);
    expect(fixture.native.published, isTrue);
    expect(fixture.media.requests, isEmpty);
  });
  for (final change in ['cancel', 'namespace', 'cloud']) {
    test('adoption rejects $change after closed comparison without claiming ownership', () async {
      late _HeldObservationJournal held;
      final fixture = await _TransferFixture.create(reserve: false,
          createJournal: (db) => held = _HeldObservationJournal(db));
      fixture.native.bytes.addAll([1,2,3,4,5]);
      fixture.native.published = true;
      final token = CancelToken();
      final adoption = fixture.runtime().adoptLocalCloudBytes(
          config: _transferConfig, artifact: _artifact(), destinationRoot: '/roms',
          relativePath: 'fixture.chd', supportedExtensions: {'.chd'}, cancellation: token);
      final failed = expectLater(adoption, throwsA(anything));
      await held.entered.future;
      expect(fixture.native.sessionOpen, isFalse);
      if (change == 'cancel') token.cancel();
      if (change == 'namespace') fixture.native.targetChanged = true;
      if (change == 'cloud') fixture.metadata.version = '2';
      held.release.complete();
      await failed;
      expect(await fixture.db.query('installed_artifacts'), isEmpty);
      expect(await fixture.db.query('transfer_records'), isEmpty);
      expect(fixture.native.stagePresent, isFalse);
      expect(fixture.native.published, isTrue);
      expect(fixture.native.bytes, [1,2,3,4,5]);
    });
  }
  test('explicit Game Gear mapping admits a ZIP without admitting other archive layouts', () {
    expect(DriveRuntime.supportsStandaloneAdoption('Game.zip', {'.gg'}), isTrue);
    expect(DriveRuntime.supportsStandaloneAdoption('Game.zip', {'.z64', '.n64', '.v64'}), isTrue);
    expect(DriveRuntime.supportsStandaloneAdoption('Game.7z', {'.z64', '.n64', '.v64'}), isTrue);
    expect(DriveRuntime.supportsStandaloneAdoption('Game.7z', {'.z64'}), isFalse);
    expect(DriveRuntime.supportsStandaloneAdoption('Game.7z', {'.gg'}), isFalse);
    expect(DriveRuntime.supportsStandaloneAdoption('Game.rar', {'.gg'}), isFalse);
  });

  for (final invalid in [false, true]) {
    test('Game Gear ZIP adoption ${invalid ? 'rejects invalid layout' : 'preserves exact bytes and validates handoff'}', () async {
      final fixture = await _TransferFixture.create(reserve: false, name: 'fixture.zip');
      fixture.native.bytes.addAll([1, 2, 3, 4, 5]);
      fixture.native.published = true;
      fixture.native.invalidArchive = invalid;
      final runtime = fixture.runtime();
      final adoption = runtime.adoptLocalCloudBytes(
          config: _transferConfig, artifact: _artifact(name: 'fixture.zip'),
          destinationRoot: '/roms', relativePath: 'fixture.zip',
          supportedExtensions: {'.gg'}, cancellation: CancelToken());
      if (invalid) {
        await expectLater(adoption, throwsA(isA<OwnedStorageException>()));
        expect(await fixture.db.query('installed_artifacts'), isEmpty);
        expect(await fixture.db.query('transfer_records'), isEmpty);
      } else {
        final installed = await adoption;
        final record = (await fixture.journal.transfer(installed.transferId))!;
        expect(record.archivePlatformId, 'gamegear');
        expect(installed.relativePath, 'fixture.zip');
        await runtime.requireInstalledTransfer(record);
        expect(fixture.native.calls.where((c) => c == 'ownedValidateGameGearZip'), hasLength(2));
      }
      expect(fixture.native.bytes, [1, 2, 3, 4, 5]);
      expect(fixture.native.published, isTrue);
      expect(fixture.native.sessionOpen, isFalse);
    });
  }

  test('normal Game Gear ZIP queue persists explicit intent before verified publication', () async {
    final fixture = await _TransferFixture.create(reserve: false, name: 'fixture.zip');
    final runtime = fixture.runtime();
    final queue = DownloadQueueManager(_QueueStorage(), NativeSmbService(), driveRuntime: runtime);
    const system = SystemModel(id: 'gamegear', name: 'Game Gear', manufacturer: 'Sega', releaseYear: 1990, romExtensions: ['.gg']);
    final terminal = _queueTerminal(queue);
    queue.addToQueue(GameItem(filename: 'fixture.zip', displayName: 'Fixture',
        url: 'drive-artifact:synthetic', providerConfig: _transferConfig,
        remoteArtifact: _artifact(name: 'fixture.zip')), system, '/roms');
    final item = await terminal;
    expect(item.status, DownloadStatus.completed, reason: item.error);
    final record = (await fixture.journal.transfer(item.transferId!))!;
    expect(record.archivePlatformId, 'gamegear');
    expect(record.relativePath, 'fixture.zip');
    expect(fixture.native.calls.indexOf('ownedValidateGameGearZip'), lessThan(fixture.native.calls.indexOf('ownedPublish')));
    expect(await fixture.db.query('installed_artifacts'), hasLength(1));
    await queue.close();
    queue.dispose();
    fixture.driver.finishSignOut.complete();
    await runtime.disconnect();
  });
  for (final extension in ['7z', 'zip']) {
    test('normal N64 $extension queue publishes typed bytes and revalidates offline', () async {
      final name = 'fixture.$extension';
      final fixture = await _TransferFixture.create(reserve: false, name: name);
      final runtime = fixture.runtime();
      final queue = DownloadQueueManager(_QueueStorage(), NativeSmbService(), driveRuntime: runtime);
      final n64 = SystemModel.supportedSystems.singleWhere((s) => s.id == 'n64');
      final terminal = _queueTerminal(queue);
      queue.addToQueue(GameItem(filename: name, displayName: 'Fixture',
          url: 'drive-artifact:synthetic', providerConfig: _transferConfig,
          remoteArtifact: _artifact(name: name)), n64, '/roms');
      final item = await terminal;
      expect(item.status, DownloadStatus.completed, reason: item.error);
      final record = (await fixture.journal.transfer(item.transferId!))!;
      expect(record.archivePlatformId, 'n64');
      expect(record.relativePath, name);
      await runtime.requireInstalledTransfer(record);
      final method = extension == '7z' ? 'ownedValidateN64SevenZip' : 'ownedValidateN64Zip';
      expect(fixture.native.calls.where((m) => m == method), hasLength(2));
      expect(fixture.native.calls.indexOf(method), lessThan(fixture.native.calls.indexOf('ownedPublish')));
      expect(fixture.native.calls, isNot(contains('ownedValidateGameGearZip')));
      fixture.native.invalidArchive = true;
      await expectLater(runtime.requireInstalledTransfer(record), throwsA(isA<OwnedStorageException>()));
      expect(fixture.native.sessionOpen, isFalse);
      await queue.close(); queue.dispose();
      fixture.driver.finishSignOut.complete(); await runtime.disconnect();
    });
    test('N64 $extension adoption validates without downloading or mutating local bytes', () async {
      final name = 'fixture.$extension';
      final fixture = await _TransferFixture.create(reserve: false, name: name);
      fixture.native.bytes.addAll([1, 2, 3, 4, 5]); fixture.native.published = true;
      final runtime = fixture.runtime();
      final installed = await runtime.adoptLocalCloudBytes(config: _transferConfig,
          artifact: _artifact(name: name), destinationRoot: '/roms', relativePath: name,
          supportedExtensions: {'.z64', '.n64', '.v64'}, cancellation: CancelToken());
      final record = (await fixture.journal.transfer(installed.transferId))!;
      expect(record.archivePlatformId, 'n64');
      await runtime.requireInstalledTransfer(record);
      expect(fixture.native.bytes, [1, 2, 3, 4, 5]);
      expect(fixture.native.calls, isNot(contains('ownedPublish')));
      expect(fixture.native.sessionOpen, isFalse);
    });
  }

  test('standalone adoption rejects unsupported archives and dependency manifests before IO', () async {
    for (final name in ['fixture.7z', 'fixture.cue', 'fixture.m3u', 'fixture.gdi', 'fixture.unknown']) {
      final fixture = await _TransferFixture.create(reserve: false);
      final artifact = RemoteArtifact.fromJson({..._artifact().toJson(), 'displayName': name});
      await expectLater(fixture.runtime().adoptLocalCloudBytes(
          config: _transferConfig, artifact: artifact, destinationRoot: '/roms',
          relativePath: name, supportedExtensions: {'.chd', '.7z', '.cue', '.m3u', '.gdi'},
          cancellation: CancelToken()), throwsA(anything));
      expect(fixture.native.calls, isEmpty);
      expect(fixture.media.requests, isEmpty);
      expect(await fixture.db.query('installed_artifacts'), isEmpty);
    }
  });
  test('recovery review proves current local/cloud bytes without ownership',
      () async {
    final fixture = await _TransferFixture.create(reserve: false);
    fixture.native.bytes.addAll([1, 2, 3, 4, 5]);
    fixture.native.published = true;
    final runtime = fixture.runtime();
    final result = await runtime.verifyLocalCloudBytes(
        config: _transferConfig,
        artifact: _artifact(),
        destinationRoot: '/roms',
        relativePath: 'fixture.chd',
        cancellation: CancelToken());
    expect(result.sizeBytes, 5);
    expect(result.checksums['md5'], _md5);
    expect(result.checksums['sha256'], hasLength(64));
    expect(fixture.metadata.requests.where((r) => r.path.endsWith('/file')),
        hasLength(2));
    expect(fixture.media.requests, hasLength(1));
    expect(fixture.native.sessionOpen, isFalse);
    expect(fixture.native.stagePresent, isFalse);
    expect(fixture.native.calls.where((c) => !{
      'ownedPrepare', 'ownedInspect', 'ownedOpen', 'ownedRead',
      'ownedCheckpoint', 'ownedClose'
    }.contains(c)), isEmpty);
    expect(await fixture.db.query('transfer_records'), isEmpty);
    expect(await fixture.db.query('installed_artifacts'), isEmpty);
    final saved = (await fixture.db.query('migration_byte_observations')).single;
    final evidence = jsonDecode(saved['record_json'] as String) as Map;
    expect(evidence['artifact']['version'], '1');
    expect(evidence['checksums']['sha256'], result.checksums['sha256']);
    expect(evidence['localIdentity']['fileId'], result.localIdentity.fileId);
    // A new runtime over the existing durable journal performs only a local read.
    final reopened = fixture.runtime();
    final prior = await reopened.savedLocalCloudObservation(
        artifact: _artifact(), destinationRoot: '/roms', relativePath: 'fixture.chd');
    expect(prior?.observedAt, result.observedAt);
    expect(fixture.media.requests, hasLength(1));
  });
  for (final fail in [false, true]) {
    test('byte observation waits for closed reads and durable journal: failure=$fail', () async {
      late _HeldObservationJournal held;
      final fixture = await _TransferFixture.create(reserve: false,
          createJournal: (db) => held = _HeldObservationJournal(db, fail: fail));
      fixture.native.bytes.addAll([1,2,3,4,5]);
      fixture.native.published = true;
      final token = CancelToken();
      final review = fixture.runtime().verifyLocalCloudBytes(config: _transferConfig,
          artifact: _artifact(), destinationRoot: '/roms', relativePath: 'fixture.chd',
          cancellation: token);
      final failed = expectLater(review, fail ? throwsStateError :
          throwsA(isA<DriveTransferException>().having((e) => e.issue, 'issue', DriveTransferIssue.cancelled)));
      await held.entered.future;
      expect(fixture.native.sessionOpen, isFalse);
      expect(await fixture.db.query('migration_byte_observations'), isEmpty);
      token.cancel();
      held.release.complete();
      await failed;
      // A cancellation cannot undo an atomic past-observation commit or claim
      // a current success. Neither outcome grants transfer/removal ownership.
      expect(await fixture.db.query('migration_byte_observations'), hasLength(fail ? 0 : 1));
      expect(await fixture.db.query('installed_artifacts'), isEmpty);
      expect(await fixture.db.query('owned_removals'), isEmpty);
    });
  }
  for (final corruption in ['local', 'cloud', 'version', 'namespace', 'overwrite']) {
    test('recovery review rejects $corruption change and drains native reads', () async {
      final fixture = await _TransferFixture.create(reserve: false);
      fixture.native.bytes.addAll(corruption == 'local' ? [5,4,3,2,1] : [1,2,3,4,5]);
      fixture.native.published = true;
      fixture.media.mediaResponse = (_, __) async {
        if (corruption == 'version') fixture.metadata.version = '2';
        if (corruption == 'namespace') fixture.native.targetChanged = true;
        // Same inode, size and timestamp: only a second byte pass catches this.
        if (corruption == 'overwrite') fixture.native.bytes[0] = 9;
        return ResponseBody(Stream.value(Uint8List.fromList(
            corruption == 'cloud' ? [5,4,3,2,1] : [1,2,3,4,5])), 200,
            headers: {'content-length': ['5']});
      };
      await expectLater(fixture.runtime().verifyLocalCloudBytes(
          config: _transferConfig, artifact: _artifact(), destinationRoot: '/roms',
          relativePath: 'fixture.chd', cancellation: CancelToken()),
          corruption == 'namespace'
              ? throwsA(isA<OwnedStorageException>().having((e) => e.code, 'code', 'changed'))
              : throwsA(isA<DriveTransferException>().having((e) => e.issue, 'issue',
                  corruption == 'version' ? DriveTransferIssue.sourceChanged
                      : DriveTransferIssue.checksumMismatch)));
      expect(fixture.native.sessionOpen, isFalse);
      expect(fixture.native.stagePresent, isFalse);
      expect(await fixture.db.query('installed_artifacts'), isEmpty);
      expect(await fixture.db.query('migration_byte_observations'), isEmpty);
    });
  }
  test('missing local file makes no cloud request and creates no stage', () async {
    final fixture = await _TransferFixture.create(reserve: false);
    await expectLater(fixture.runtime().verifyLocalCloudBytes(config: _transferConfig,
        artifact: _artifact(), destinationRoot: '/roms', relativePath: 'fixture.chd',
        cancellation: CancelToken()),
        throwsA(isA<OwnedStorageException>().having((e) => e.code, 'code', 'not_found')));
    expect(fixture.media.requests, isEmpty);
    expect(fixture.metadata.requests, isEmpty);
    expect(fixture.native.stagePresent, isFalse);
    expect(await fixture.db.query('transfer_records'), isEmpty);
    expect(await fixture.db.query('migration_byte_observations'), isEmpty);
  });
  test('disconnect joins recovery cancellation before native/transport teardown', () async {
    final fixture = await _TransferFixture.create(reserve: false);
    fixture.native.bytes.addAll([1,2,3,4,5]);
    fixture.native.published = true;
    final entered = Completer<void>(), cancelled = Completer<void>(), drain = Completer<void>();
    fixture.media.mediaResponse = (options, cancellation) async {
      entered.complete();
      await cancellation;
      cancelled.complete();
      await drain.future;
      throw DioException(requestOptions: options, type: DioExceptionType.cancel);
    };
    final runtime = fixture.runtime();
    final review = runtime.verifyLocalCloudBytes(config: _transferConfig,
        artifact: _artifact(), destinationRoot: '/roms', relativePath: 'fixture.chd',
        cancellation: CancelToken());
    final failed = expectLater(review, throwsA(isA<DriveTransferException>()));
    await entered.future;
    await expectLater(runtime.verifyLocalCloudBytes(config: _transferConfig,
        artifact: _artifact(), destinationRoot: '/roms', relativePath: 'fixture.chd',
        cancellation: CancelToken()), throwsA(isA<DriveTransferException>()));
    final disconnect = runtime.disconnect();
    await cancelled.future;
    expect(fixture.native.sessionOpen, isTrue);
    expect(fixture.media.closed, isFalse);
    fixture.driver.finishSignOut.complete();
    drain.complete();
    await failed;
    await disconnect;
    expect(fixture.native.sessionOpen, isFalse);
    expect(fixture.media.closed, isTrue);
    expect(await fixture.db.query('migration_byte_observations'), isEmpty);
  });
  test(
      'metadata archive reads bind separate local raw hashes without ROM media requests',
      () async {
    final fixture =
        await _TransferFixture.create(name: 'fixture.7z', reserve: false);
    final raw = await fixture.runtime().readMetadataArchive(
        config: _transferConfig,
        artifact: _artifact(name: 'fixture.7z'),
        platformId: 'n64',
        destinationRoot: '/roms',
        cancellation: CancelToken());
    expect(raw!.sha1, 'c' * 40);
    expect(raw.md5, 'b' * 32);
    expect(raw.sizeBytes, 8192);
    expect(fixture.media.requests, isEmpty);
    expect(fixture.native.calls, ['ownedReadArchiveIdentifier']);
    expect(fixture.metadata.requests.where((r) => r.path.endsWith('/file')),
        hasLength(2));
    expect(await fixture.db.query('transfer_records'), isEmpty);
    expect(await fixture.db.query('installed_artifacts'), isEmpty);
    expect(await fixture.db.query('transfer_target_owners'), isEmpty);
    expect(fixture.native.stagePresent, isFalse);
  });
  for (final platform in ['gb', 'gbc']) {
    test('$platform ZIP is not silently promoted to the 7z metadata profile',
        () async {
      final fixture =
          await _TransferFixture.create(name: 'fixture.zip', reserve: false);
      expect(
          await fixture.runtime().readMetadataArchive(
              config: _transferConfig,
              artifact: _artifact(name: 'fixture.zip'),
              platformId: platform,
              destinationRoot: '/roms',
              cancellation: CancelToken()),
          isNull);
      expect(fixture.native.calls, isEmpty);
      expect(fixture.metadata.requests, isEmpty);
      expect(fixture.media.requests, isEmpty);
    });
    test(
        '$platform local 7z metadata reads use raw hashes without installation',
        () async {
      final fixture =
          await _TransferFixture.create(name: 'fixture.7z', reserve: false);
      fixture.native.archivePlatform = platform;
      final member = platform == 'gb' ? 'fixture.gb' : 'fixture.gbc';
      fixture.native.archiveObservation['raw'] = {
        ...((fixture.native.archiveObservation['raw'] as Map)
            .cast<String, Object?>()),
        'filename': member,
      };
      final raw = await fixture.runtime().readMetadataArchive(
          config: _transferConfig,
          artifact: _artifact(name: 'fixture.7z'),
          platformId: platform,
          destinationRoot: '/roms',
          cancellation: CancelToken());
      expect(raw, isNotNull);
      expect(raw!.filename, member);
      expect(raw.sha1, 'c' * 40);
      expect(raw.md5, 'b' * 32);
      expect(fixture.native.calls, ['ownedReadArchiveIdentifier']);
      expect(fixture.metadata.requests.where((r) => r.path.endsWith('/file')),
          hasLength(2));
      expect(fixture.media.requests, isEmpty);
      expect(await fixture.db.query('transfer_records'), isEmpty);
      expect(await fixture.db.query('installed_artifacts'), isEmpty);
      expect(fixture.native.stagePresent, isFalse);
    });
    test('$platform 7z rejects a raw member from another mapped platform',
        () async {
      final fixture =
          await _TransferFixture.create(name: 'fixture.7z', reserve: false);
      fixture.native.archivePlatform = platform;
      await expectLater(
          fixture.runtime().readMetadataArchive(
              config: _transferConfig,
              artifact: _artifact(name: 'fixture.7z'),
              platformId: platform,
              destinationRoot: '/roms',
              cancellation: CancelToken()),
          throwsA(isA<DriveTransferException>().having(
              (e) => e.issue, 'issue', DriveTransferIssue.invalidResponse)));
      expect(fixture.media.requests, isEmpty);
    });
  }

  test('metadata archive container mismatch cannot supply raw evidence',
      () async {
    final fixture =
        await _TransferFixture.create(name: 'fixture.7z', reserve: false);
    fixture.native.archiveObservation['container'] = {
      'sizeBytes': 5,
      'md5': 'a' * 32
    };
    expect(
        await fixture.runtime().readMetadataArchive(
            config: _transferConfig,
            artifact: _artifact(name: 'fixture.7z'),
            platformId: 'n64',
            destinationRoot: '/roms',
            cancellation: CancelToken()),
        isNull);
    expect(fixture.media.requests, isEmpty);
  });
  test('metadata archive changed cloud binding rejects after local observation',
      () async {
    final fixture =
        await _TransferFixture.create(name: 'fixture.7z', reserve: false);
    fixture.native.onArchiveRead = () async {
      fixture.metadata.version = '2';
    };
    await expectLater(
        fixture.runtime().readMetadataArchive(
            config: _transferConfig,
            artifact: _artifact(name: 'fixture.7z'),
            platformId: 'n64',
            destinationRoot: '/roms',
            cancellation: CancelToken()),
        throwsA(isA<DriveTransferException>().having(
            (e) => e.issue, 'issue', DriveTransferIssue.sourceChanged)));
    expect(fixture.media.requests, isEmpty);
  });
  test('disconnect cancels and joins native metadata archive observation',
      () async {
    final fixture =
        await _TransferFixture.create(name: 'fixture.7z', reserve: false);
    final entered = Completer<void>(), drain = Completer<void>();
    fixture.native.onArchiveRead = () async {
      entered.complete();
      await drain.future;
    };
    final runtime = fixture.runtime();
    final read = runtime.readMetadataArchive(
        config: _transferConfig,
        artifact: _artifact(name: 'fixture.7z'),
        platformId: 'n64',
        destinationRoot: '/roms',
        cancellation: CancelToken());
    final failed = expectLater(
        read,
        throwsA(isA<DriveTransferException>()
            .having((e) => e.issue, 'issue', DriveTransferIssue.cancelled)));
    await entered.future;
    final disconnect = runtime.disconnect();
    await fixture.driver.signedOut.future;
    fixture.driver.finishSignOut.complete();
    expect(fixture.metadata.closed, isFalse);
    drain.complete();
    await failed;
    await disconnect;
    expect(fixture.metadata.closed, isTrue);
    expect(fixture.media.requests, isEmpty);
  });
  test('metadata header reads exactly 140 bytes without staging a large ROM',
      () async {
    const size = 4294967296;
    final fixture = await _TransferFixture.create(size: size, reserve: false);
    fixture.media.mediaResponse = (options, _) async {
      expect(options.headers['Range'], 'bytes=0-139');
      return ResponseBody(Stream.value(Uint8List(140)), 206, headers: {
        'content-length': ['140'],
        'content-range': ['bytes 0-139/$size']
      });
    };
    final runtime = fixture.runtime();
    final bytes = await runtime.readMetadataHeader(
        config: _transferConfig,
        artifact: _artifact(size: size),
        cancellation: CancelToken());
    expect(bytes, hasLength(140));
    expect(fixture.media.requests, hasLength(1));
    expect(fixture.metadata.requests.where((r) => r.path.endsWith('/file')),
        hasLength(2));
    expect(fixture.native.calls, isEmpty);
    expect(await fixture.db.query('transfer_records'), isEmpty);
  });

  test('disconnect joins a cancelled metadata header before closing transport',
      () async {
    final fixture = await _TransferFixture.create(size: 1024, reserve: false);
    final entered = Completer<void>();
    final cancelled = Completer<void>();
    final drained = Completer<void>();
    fixture.media.mediaResponse = (options, cancel) async {
      entered.complete();
      await cancel;
      cancelled.complete();
      await drained.future;
      throw DioException(
          requestOptions: options, type: DioExceptionType.cancel);
    };
    final runtime = fixture.runtime();
    final read = runtime.readMetadataHeader(
        config: _transferConfig,
        artifact: _artifact(size: 1024),
        cancellation: CancelToken());
    final failed = expectLater(read, throwsA(isA<DriveTransferException>()));
    await entered.future;
    final disconnect = runtime.disconnect();
    await cancelled.future;
    await fixture.driver.signedOut.future;
    expect(fixture.media.closed, isFalse);
    fixture.driver.finishSignOut.complete();
    drained.complete();
    await failed;
    await disconnect;
    expect(fixture.media.closed, isTrue);
  });
  test('metadata header rejects a source version changed by the media read',
      () async {
    final fixture = await _TransferFixture.create(size: 1024, reserve: false);
    fixture.media.mediaResponse = (_, __) async {
      fixture.metadata.version = '2';
      return ResponseBody(Stream.value(Uint8List(140)), 206, headers: {
        'content-length': ['140'],
        'content-range': ['bytes 0-139/1024']
      });
    };
    await expectLater(
        fixture.runtime().readMetadataHeader(
            config: _transferConfig,
            artifact: _artifact(size: 1024),
            cancellation: CancelToken()),
        throwsA(isA<DriveTransferException>().having(
            (e) => e.issue, 'issue', DriveTransferIssue.sourceChanged)));
    expect(fixture.native.calls, isEmpty);
    expect(await fixture.db.query('transfer_records'), isEmpty);
  });
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
    // Catalogue setup already obtained this account's reusable grant. The
    // transfer must authorize its media request without another sign-in.
    expect(grantsBefore, greaterThan(0));
    expect(fixture.driver.grants, grantsBefore);
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

  test('replacement reservation is exact, distinct-path and restart stable',
      () async {
    final fixture = await _TransferFixture.create();
    final runtime = fixture.runtime();
    expect(
        (await (await runtime.startTransfer(
                    config: _transferConfig, transferId: 'transfer'))
                .result)
            .lifecycle,
        TransferLifecycle.completed);
    final changed =
        RemoteArtifact.fromJson({..._artifact().toJson(), 'version': '2'});
    final next = await runtime.reserveTransfer(
        config: _transferConfig,
        artifact: changed,
        destinationRoot: '/roms',
        relativePath: changed.displayName);
    expect(next.relativePath, isNot('fixture.chd'));
    expect(next.relativePath.endsWith('.chd'), isTrue);
    expect(next.replacesInstallation!.transferId, 'transfer');
    final again = await fixture.runtime().reserveTransfer(
        config: _transferConfig,
        artifact: changed,
        destinationRoot: '/roms',
        relativePath: changed.displayName);
    expect(jsonEncode(again.toJson()), jsonEncode(next.toJson()));
    expect(await fixture.journal.transfer('transfer'), isNotNull);
    expect(fixture.native.published, isTrue);
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

  test(
      'normal queue preserves completion when private retirement acknowledgement fails',
      () async {
    final fixture = await _TransferFixture.create(
        reserve: false, retirementAckFailure: true);
    fixture.native.copyOnly = true;
    final runtime = fixture.runtime();
    final queue = DownloadQueueManager(_QueueStorage(), NativeSmbService(),
        driveRuntime: runtime);
    final hooks = <DownloadItem>[];
    queue.onItemCompleted = hooks.add;
    try {
      final terminal = _queueTerminal(queue);
      queue.addToQueue(_game(), _system, '/roms');
      final item = await terminal;
      await queue.close();
      final journal = fixture.journal as _RetirementAckFailure;
      expect(journal.acknowledgements, greaterThanOrEqualTo(1));
      expect(item.status, DownloadStatus.completed, reason: item.error);
      expect(queue.state.queue.single.status, DownloadStatus.completed);
      expect(hooks, hasLength(1));
      expect(hooks.single.status, DownloadStatus.completed);
      final pending = (await journal.transfer(item.transferId!))!;
      expect(pending.lifecycle, TransferLifecycle.completed);
      expect(pending.stageRetired, isFalse);
      expect(await fixture.db.query('installed_artifacts'), hasLength(1));
      expect(fixture.native.stagePresent, isFalse);
      expect(fixture.native.sessionOpen, isFalse);
      expect(fixture.native.copiedBytes, [1, 2, 3, 4, 5]);

      final mediaRequests = fixture.media.requests.length;
      final metadataRequests = fixture.metadata.requests.length;
      final acknowledgements = journal.acknowledgements;
      final replayed = await runtime.finishRetainedStage(pending);
      expect(replayed.lifecycle, TransferLifecycle.completed);
      expect(replayed.stageRetired, isTrue);
      expect(replayed.stageRetirementIssue, isNull);
      expect((await journal.transfer(pending.id))!.stageRetired, isTrue);
      expect(journal.acknowledgements, acknowledgements + 1);
      expect(fixture.native.calls.where((call) => call == 'ownedRetireStage'),
          hasLength(2));
      expect(fixture.media.requests, hasLength(mediaRequests));
      expect(fixture.metadata.requests, hasLength(metadataRequests));
      expect(hooks, hasLength(1));
      expect(fixture.native.copiedBytes, [1, 2, 3, 4, 5]);
    } finally {
      await queue.close();
      queue.dispose();
      fixture.driver.finishSignOut.complete();
      await runtime.disconnect();
    }
  });

  test(
      'empty restored queue recovers journal stages once without account access',
      () async {
    final fixture =
        await _TransferFixture.create(createJournal: _RecoveryJournal.new);
    final seeded = await _pendingStage(fixture);
    final journal = fixture.journal as _RecoveryJournal;
    fixture.native.retirementFailure = null;
    final recoveryRuntime = fixture.runtime();
    final storage = _QueueStorage();
    final queue = DownloadQueueManager(storage, NativeSmbService(),
        driveRuntime: recoveryRuntime);
    final hooks = <DownloadItem>[];
    queue.onItemCompleted = hooks.add;
    try {
      expect(storage.savedQueue, isNull);
      expect(journal.recoveryPasses, 0,
          reason: 'Construction must not start recovery');
      final mediaRequests = fixture.media.requests.length;
      final metadataRequests = fixture.metadata.requests.length;
      final grants = fixture.driver.grants;
      queue.restoreQueue([_system]);
      final recovery = queue.recoverPendingStageRetirements();
      final report = await recovery;
      expect(report.examined, 1);
      expect(report.retired, 1);
      expect(report.pending, 0);
      expect(report.issues, isEmpty);
      expect(queue.state.queue, isEmpty);
      expect(hooks, isEmpty);
      expect((await journal.transfer(seeded.record.id))!.stageRetired, isTrue);
      expect(fixture.native.stagePresent, isFalse);
      queue.restoreQueue([_system]);
      expect(
          identical(queue.recoverPendingStageRetirements(), recovery), isTrue);
      expect(journal.recoveryPasses, 1);
      expect(fixture.media.requests, hasLength(mediaRequests));
      expect(fixture.metadata.requests, hasLength(metadataRequests));
      expect(fixture.driver.grants, grants);
    } finally {
      await queue.close();
      queue.dispose();
      await recoveryRuntime.disconnect();
      fixture.driver.finishSignOut.complete();
      await seeded.runtime.disconnect();
    }
  });

  test('empty restored queue completes interrupted removal once offline',
      () async {
    final fixture =
        await _TransferFixture.create(createJournal: _RecoveryJournal.new);
    final runtime = fixture.runtime();
    final operation = await runtime.startTransfer(
        config: _transferConfig, transferId: 'transfer');
    final installed = await operation.result;
    final manifest = (await fixture.journal.installationForTarget(
        destinationRoot: '/roms', relativePath: 'fixture.chd'))!;
    final removal = await fixture.journal.beginRemoval(installed, manifest,
        id: 'removal-startup',
        quarantinePath: '/owned/removal-startup.partial');
    // Native move committed, but its receipt was lost with the old process.
    await OwnedStorage(channel: fixture.native.channel).quarantine(
        destinationRoot: '/roms',
        relativePath: 'fixture.chd',
        stagePath: removal.quarantinePath,
        expectedIdentity: manifest.fileIdentity);
    final queue = DownloadQueueManager(_QueueStorage(), NativeSmbService(),
        driveRuntime: fixture.runtime());
    final journal = fixture.journal as _RecoveryJournal;
    final grants = fixture.driver.grants;
    final metadataRequests = fixture.metadata.requests.length;
    final payloadRequests = fixture.media.requests.length;
    try {
      expect(journal.removalPasses, 0);
      queue.restoreQueue([_system]);
      final recovery = queue.recoverPendingRemovals();
      final report = await recovery;
      expect(report.removed, 1);
      expect(report.pending, 0);
      expect(report.issues, isEmpty);
      expect((await journal.removal(removal.id))!.phase,
          OwnedRemovalPhase.completed);
      expect(await journal.transfer(installed.id), isNull);
      expect(fixture.native.quarantinePresent, isFalse);
      expect(fixture.native.published, isFalse);
      expect(queue.state.queue, isEmpty);
      queue.restoreQueue([_system]);
      expect(identical(queue.recoverPendingRemovals(), recovery), isTrue);
      expect(journal.removalPasses, 1);
      expect(fixture.driver.grants, grants);
      expect(fixture.metadata.requests, hasLength(metadataRequests));
      expect(fixture.media.requests, hasLength(payloadRequests));
    } finally {
      await queue.close();
      queue.dispose();
      fixture.driver.finishSignOut.complete();
      await runtime.disconnect();
    }
  });

  test('queue shutdown joins native removal instead of leaving an orphan',
      () async {
    final fixture =
        await _TransferFixture.create(createJournal: _RecoveryJournal.new);
    final runtime = fixture.runtime();
    final operation = await runtime.startTransfer(
        config: _transferConfig, transferId: 'transfer');
    final installed = await operation.result;
    final manifest = (await fixture.journal.installationForTarget(
        destinationRoot: '/roms', relativePath: 'fixture.chd'))!;
    final removal = await fixture.journal.beginRemoval(installed, manifest,
        id: 'removal-shutdown',
        quarantinePath: '/owned/removal-shutdown.partial');
    final release = Completer<void>();
    fixture.native.finishQuarantineRetirement = release.future;
    final queue = DownloadQueueManager(_QueueStorage(), NativeSmbService(),
        driveRuntime: fixture.runtime());
    try {
      queue.restoreQueue([_system]);
      await fixture.native.quarantineRetirementStarted.future;
      var closed = false;
      final closing = queue.close().then((_) => closed = true);
      expect((await fixture.journal.removal(removal.id))!.phase,
          OwnedRemovalPhase.deleting);
      expect(closed, isFalse);
      release.complete();
      await closing;
      final report = await queue.recoverPendingRemovals();
      expect(report.removed, 1);
      expect(report.stopped, isTrue);
      expect(fixture.native.quarantinePresent, isFalse);
    } finally {
      if (!release.isCompleted) release.complete();
      await queue.close();
      queue.dispose();
      fixture.driver.finishSignOut.complete();
      await runtime.disconnect();
    }
  });

  test('queue close joins in-progress retirement and stops the startup pass',
      () async {
    final fixture =
        await _TransferFixture.create(createJournal: _RecoveryJournal.new);
    final seeded = await _pendingStage(fixture);
    fixture.native.retirementFailure = null;
    final entered = Completer<void>();
    final release = Completer<void>();
    fixture.native.onRetirementStarted = entered.complete;
    fixture.native.finishRetirement = release.future;
    final queue = DownloadQueueManager(_QueueStorage(), NativeSmbService(),
        driveRuntime: seeded.runtime);
    try {
      queue.restoreQueue([_system]);
      await entered.future;
      var closed = false;
      final closing = queue.close().then((_) => closed = true);
      final pending = (await fixture.journal.transfer(seeded.record.id))!;
      expect(pending.stageRetired, isFalse);
      expect(closed, isFalse);
      release.complete();
      await closing;
      final report = await queue.recoverPendingStageRetirements();
      expect(report.retired, 1);
      expect(report.stopped, isTrue);
      expect(fixture.native.stagePresent, isFalse);
    } finally {
      if (!release.isCompleted) release.complete();
      await queue.close();
      queue.dispose();
      fixture.driver.finishSignOut.complete();
      await seeded.runtime.disconnect();
    }
  });

  test('startup retirement failure stays pending without a busy retry',
      () async {
    final fixture =
        await _TransferFixture.create(createJournal: _RecoveryJournal.new);
    final seeded = await _pendingStage(fixture);
    final queue = DownloadQueueManager(_QueueStorage(), NativeSmbService(),
        driveRuntime: seeded.runtime);
    try {
      final before = fixture.native.calls
          .where((call) => call == 'ownedRetireStage')
          .length;
      queue.restoreQueue([_system]);
      final report = await queue.recoverPendingStageRetirements();
      expect(report.retired, 0);
      expect(report.pending, 1);
      expect(report.issues, {'access_denied': 1});
      expect(fixture.native.calls.where((call) => call == 'ownedRetireStage'),
          hasLength(before + 1));
      expect(queue.state.queue, isEmpty);
      expect((await fixture.journal.transfer(seeded.record.id))!.lifecycle,
          TransferLifecycle.completed);
      expect((await fixture.journal.transfer(seeded.record.id))!.stageRetired,
          isFalse);
      await queue.recoverPendingStageRetirements();
      expect((fixture.journal as _RecoveryJournal).recoveryPasses, 1);
    } finally {
      await queue.close();
      queue.dispose();
      fixture.driver.finishSignOut.complete();
      await seeded.runtime.disconnect();
    }
  });

  test('recovery query failure exposes only bounded machine-code diagnostics',
      () async {
    final fixture =
        await _TransferFixture.create(createJournal: _RecoveryJournal.new);
    (fixture.journal as _RecoveryJournal).enumerationError =
        StateError('synthetic-token /private/library-name');
    final runtime = fixture.runtime();
    final report = await runtime.recoverPendingStageRetirements();
    expect(report.examined, 0);
    expect(report.issues, {'journal_unavailable': 1});
    expect(jsonEncode(report.issues), isNot(contains('synthetic-token')));
    expect(jsonEncode(report.issues), isNot(contains('library-name')));
    expect(fixture.native.calls, isEmpty);
    await runtime.disconnect();
  });

  test('recovery stopped before entry performs no journal or native work',
      () async {
    final fixture =
        await _TransferFixture.create(createJournal: _RecoveryJournal.new);
    final runtime = fixture.runtime();
    final report = await runtime.recoverPendingStageRetirements(
        shouldContinue: () => false);
    expect(report.stopped, isTrue);
    expect(report.examined, 0);
    expect((fixture.journal as _RecoveryJournal).recoveryPasses, 0);
    expect(fixture.native.calls, isEmpty);
    await runtime.disconnect();
  });

  test(
      'startup recovery leaves an active completed transfer to its inline cleanup',
      () async {
    final fixture = await _TransferFixture.create();
    fixture.native.copyOnly = true;
    final release = Completer<void>();
    fixture.native.finishClose = release.future;
    final runtime = fixture.runtime();
    final operation = await runtime.startTransfer(
        config: _transferConfig, transferId: 'transfer');
    try {
      await fixture.native.closeStarted.future;
      expect((await fixture.journal.transfer('transfer'))!.lifecycle,
          TransferLifecycle.completed);
      final report = await runtime.recoverPendingStageRetirements();
      expect(report.skippedActive, 1);
      expect(report.retired, 0);
      expect(fixture.native.calls, isNot(contains('ownedRetireStage')));
      release.complete();
      expect((await operation.result).stageRetired, isTrue);
    } finally {
      if (!release.isCompleted) release.complete();
      await operation.result;
      fixture.driver.finishSignOut.complete();
      await runtime.disconnect();
    }
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
