import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/models/owned_removal_record.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';
import 'package:retro_eshop/services/drive/drive_media.dart';
import 'package:retro_eshop/services/drive/drive_transfer_engine.dart';
import 'package:retro_eshop/services/owned_storage.dart';
import 'package:retro_eshop/services/owned_installation_removal.dart';
import 'package:retro_eshop/services/transfer_journal.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/services/installation_index.dart';
import 'package:retro_eshop/services/ra_hash_service.dart';
import 'package:retro_eshop/services/owned_replacement.dart';
import 'package:retro_eshop/services/rom_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Only the remote protocol and native channel are fixtures. The coordinator,
// streaming verifier, identity codecs and real SQLite journal are production.
class _NativeFile {
  final int inode;
  List<int> bytes = [];
  int stamp = 0;
  _NativeFile(this.inode);
  Map<String, Object> get identity => {
        'device': '1',
        'inode': '$inode',
        'size': bytes.length,
        'modifiedSeconds': 100,
        'modifiedNanos': stamp,
      };
}

class _CompletionBarrierJournal extends TransferJournal {
  final entered = Completer<void>();
  final release = Completer<void>();
  _CompletionBarrierJournal(super.database);
  @override
  Future<TransferRecord> complete(
      TransferRecord record, InstalledArtifact installation,
      {void Function()? checkCancellation}) async {
    entered.complete();
    await release.future;
    return super
        .complete(record, installation, checkCancellation: checkCancellation);
  }
}

class _RetirementAckFailure extends TransferJournal {
  bool fail = true;
  _RetirementAckFailure(super.database);
  @override
  Future<TransferRecord> stageRetirementResult(TransferRecord record,
      {String? issue}) async {
    if (fail) {
      fail = false;
      throw StateError('fixture lost acknowledgement');
    }
    return super.stageRetirementResult(record, issue: issue);
  }
}

class _Session {
  final String stage;
  final String target;
  final _NativeFile source;
  bool published;
  _NativeFile? copy;
  _Session(this.stage, this.target, this.source, this.published);
}

class _Native {
  final files = <String, _NativeFile>{};
  final sessions = <String, _Session>{};
  final methods = <String>[];
  final MethodChannel channel = const MethodChannel('engine-fixture-storage');
  bool copyOnly = false;
  bool invalidArchive = false;
  bool crossMount = false;
  int next = 0;
  Future<void> Function(MethodCall)? before;
  Future<void> Function(MethodCall)? after;
  void install() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handle);
  Future<Object?> handle(MethodCall call) async {
    methods.add(call.method);
    await before?.call(call);
    final result = execute(call);
    await after?.call(call);
    return result;
  }

  Never fail(String code) => throw PlatformException(code: code);
  Object? execute(MethodCall call) {
    final a = Map<String, dynamic>.from(call.arguments as Map);
    if (call.method == 'ownedPrepare') {
      return {
        'destinationRoot': '/roms',
        'stageRoot': '/owned',
        'destinationVolume': '1',
        'stageVolume': '1',
        'destinationMount': '10',
        'stageMount': crossMount ? '11' : '10',
        'destinationFreeBytes': 1 << 30,
        'stageFreeBytes': 1 << 30
      };
    }
    final stage = a['stagePath'] as String?;
    final target = '${a['destinationRoot']}/${a['relativePath']}';
    if (call.method == 'ownedInspect') {
      return files[a['published'] == true ? target : stage]?.identity;
    }
    if (call.method == 'ownedQuarantine' ||
        call.method == 'ownedRetireQuarantine') {
      if (sessions.values.any((s) => s.stage == stage || s.target == target)) {
        fail('collision');
      }
      final existing = files[stage];
      if (call.method == 'ownedRetireQuarantine' && existing == null) {
        return null;
      }
      final file = existing ?? files[target] ?? fail('changed');
      if (file.identity.toString() !=
          Map<String, Object>.from(a['expectedIdentity']).toString()) {
        fail('changed');
      }
      if (call.method == 'ownedRetireQuarantine') {
        files.remove(stage);
        return null;
      }
      if (existing == null) files[stage!] = files.remove(target)!;
      return file.identity;
    }
    if (call.method == 'ownedRetireStage') {
      if (sessions.values.any((s) => s.stage == stage || s.target == target)) {
        fail('collision');
      }
      final installed = files[target] ?? fail('changed');
      if (installed.identity.toString() !=
          Map<String, Object>.from(a['installedIdentity']).toString()) {
        fail('changed');
      }
      final pending = files[stage];
      if (pending != null &&
          pending.identity.toString() !=
              Map<String, Object>.from(a['expectedIdentity']).toString()) {
        fail('changed');
      }
      files.remove(stage);
      return null;
    }
    if (call.method == 'ownedOpen') {
      final published = a['mode'] == 'published';
      final path = published ? target : stage!;
      if (a['mode'] == 'create') {
        if (files.containsKey(path)) fail('collision');
        files[path] = _NativeFile(++next);
      }
      final file = files[path] ?? fail('not_found');
      if (a['expectedIdentity'] != null) {
        if (file.identity['inode'] != a['expectedIdentity']['inode'] ||
            file.bytes.length < (a['durableOffset'] as int)) {
          fail('changed');
        }
        if (published || a['mode'] == 'quarantine') {
          if (file.identity.toString() !=
                  Map<String, Object>.from(a['expectedIdentity']).toString() ||
              a['durableOffset'] != file.bytes.length) {
            fail('changed');
          }
        } else if (file.bytes.length != a['durableOffset']) {
          file.bytes = file.bytes.sublist(0, a['durableOffset'] as int);
          file.stamp++;
        }
      }
      final id = 'session-${++next}';
      sessions[id] = _Session(stage!, target, file, published);
      return {'session': id, 'identity': file.identity};
    }
    if (call.method == 'ownedClose') {
      sessions.remove(a['session']);
      return null;
    }
    final s = sessions[a['session']] ?? fail('closed');
    switch (call.method) {
      case 'ownedValidateGameGearZip':
        if (invalidArchive) fail('unsupported_archive');
        return null;
      case 'ownedWrite':
        if (s.published || s.source.bytes.length != a['offset']) {
          fail('changed');
        }
        s.source.bytes.addAll(a['bytes'] as Uint8List);
        s.source.stamp++;
        return null;
      case 'ownedCheckpoint':
        return s.source.identity;
      case 'ownedRead':
        return Uint8List.fromList(s.source.bytes.sublist(
            a['offset'] as int, (a['offset'] as int) + (a['length'] as int)));
      case 'ownedPublish':
        if (copyOnly) fail('unsupported');
        if (files.containsKey(s.target)) fail('collision');
        files[s.target] = files.remove(s.stage)!;
        s.published = true;
        return s.source.identity;
      case 'ownedCopyOpen':
        if (a['destinationIdentity'] == null) {
          if (files.containsKey(s.target)) fail('collision');
          files[s.target] = _NativeFile(++next);
        }
        final copy = files[s.target] ?? fail('not_found');
        if (copy.bytes.length != a['durableOffset'] ||
            (a['destinationIdentity'] != null &&
                copy.identity['inode'] != a['destinationIdentity']['inode'])) {
          fail('changed');
        }
        s.copy = copy;
        return copy.identity;
      case 'ownedCopyValidatePrefix':
        final end = (a['offset'] as int) + (a['length'] as int);
        if (s.copy!.bytes.sublist(0, end).toString() !=
            s.source.bytes.sublist(0, end).toString()) {
          fail('changed');
        }
        return end;
      case 'ownedCopyChunk':
        final end = (a['offset'] as int) + (a['length'] as int);
        s.copy!.bytes.addAll(s.source.bytes.sublist(a['offset'] as int, end));
        s.copy!.stamp++;
        return end;
      case 'ownedCopyCheckpoint':
      case 'ownedCopyFinish':
        return s.copy!.identity;
      case 'ownedCopyRead':
        return Uint8List.fromList(s.copy!.bytes.sublist(
            a['offset'] as int, (a['offset'] as int) + (a['length'] as int)));
      default:
        fail('invalid_arguments');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final payload = Uint8List.fromList(List.generate(131085, (i) => i % 251));
  RemoteArtifact artifact({Map<String, String>? hashes, String name = 'fixture.chd'}) => RemoteArtifact(
      id: RemoteArtifactId(
          providerId: 'drive',
          sourceId: 'source',
          accountId: 'account',
          providerFileId: 'file'),
      parentId: 'folder',
      displayPath: name,
      displayName: name,
      version: '1',
      sizeBytes: payload.length,
      canDownload: true,
      providerChecksums: hashes ?? {'md5': md5.convert(payload).toString()});
  late Database db;
  late TransferJournal journal;
  late _Native native;
  late List<int> requests;
  late int checks;
  late List<RemoteArtifact> validated;
  late Future<void> Function(CancelToken) revalidate;
  late Future<DriveMediaResponse> Function(RemoteArtifact, int, CancelToken)
      media;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await TransferJournalSchema.install(db);
    journal = TransferJournal(Future.value(db));
    native = _Native()..install();
    requests = [];
    checks = 0;
    validated = [];
    revalidate = (_) async {
      checks++;
    };
    media = (source, offset, token) async {
      requests.add(offset);
      return DriveMediaResponse(
          bytes: Stream.value(Uint8List.sublistView(payload, offset)),
          offset: offset,
          length: payload.length - offset,
          total: payload.length);
    };
  });
  tearDown(() async {
    expect(native.sessions, isEmpty,
        reason: 'Every outcome must close native handles');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native.channel, null);
    await db.close();
  });
  DriveTransferEngine engine() => DriveTransferEngine(
      journal: journal,
      storage: OwnedStorage(channel: native.channel),
      revalidate: (source, token) {
        validated.add(source);
        return revalidate(token);
      },
      openMedia: (source, offset, token) => media(source, offset, token));
  Future<void> queue(
          {RemoteArtifact? source, String name = 'fixture.chd', String? archivePlatformId}) async =>
      journal.create(TransferRecord(
          id: 'transfer',
          artifact: source ?? artifact(),
          destinationRoot: '/roms',
          relativePath: name,
          archivePlatformId: archivePlatformId,
          stagePath: '/owned/transfer.partial'));
  Future<InstalledArtifact?> installed() => journal.installationForTarget(
      destinationRoot: '/roms', relativePath: 'fixture.chd');

  test('typed Game Gear ZIP is validated before publication and stays a ZIP', () async {
    await queue(source: artifact(name: 'fixture.zip'), name: 'fixture.zip', archivePlatformId: 'gamegear');
    final result = await engine().start('transfer').result;
    expect(result.lifecycle, TransferLifecycle.completed);
    expect(native.methods.indexOf('ownedValidateGameGearZip'), lessThan(native.methods.indexOf('ownedPublish')));
    expect(native.files['/roms/fixture.zip']!.bytes, payload);
    expect(result.archivePlatformId, 'gamegear');
  });
  test('malformed archive cannot publish or obtain ownership', () async {
    await queue(source: artifact(name: 'fixture.zip'), name: 'fixture.zip', archivePlatformId: 'gamegear');
    native.invalidArchive = true;
    final result = await engine().start('transfer').result;
    expect(result.lifecycle, TransferLifecycle.failed);
    expect(result.errorCode, 'storage_unsupported_archive');
    expect(native.methods, isNot(contains('ownedPublish')));
    expect(await journal.installationForTarget(destinationRoot: '/roms', relativePath: 'fixture.zip'), isNull);
  });
  test('legacy untyped ZIP remains rejected before network IO', () async {
    await queue(source: artifact(name: 'fixture.zip'), name: 'fixture.zip');
    final result = await engine().start('transfer').result;
    expect(result.lifecycle, TransferLifecycle.failed);
    expect(requests, isEmpty);
    expect(native.methods, isEmpty);
  });
  test('cancellation during archive validation joins closure and prevents publication', () async {
    await queue(source: artifact(name: 'fixture.zip'), name: 'fixture.zip', archivePlatformId: 'gamegear');
    final entered = Completer<void>(), release = Completer<void>();
    native.before = (call) async {
      if (call.method == 'ownedValidateGameGearZip') { entered.complete(); await release.future; }
    };
    final operation = engine().start('transfer');
    await entered.future;
    operation.pause();
    release.complete();
    expect((await operation.result).lifecycle, TransferLifecycle.paused);
    expect(native.methods, isNot(contains('ownedPublish')));
  });
  test('renamed archive recovery validates its pinned published object again', () async {
    await queue(source: artifact(name: 'fixture.zip'), name: 'fixture.zip', archivePlatformId: 'gamegear');
    native.after = (call) async { if (call.method == 'ownedPublish') throw StateError('lost receipt'); };
    expect((await engine().start('transfer').result).lifecycle, TransferLifecycle.failed);
    native.after = null;
    native.invalidArchive = true;
    expect((await engine().start('transfer').result).lifecycle, TransferLifecycle.failed);
    expect(await journal.installationForTarget(destinationRoot: '/roms', relativePath: 'fixture.zip'), isNull);
    native.invalidArchive = false;
    expect((await engine().start('transfer').result).lifecycle, TransferLifecycle.completed);
    expect(requests, [0]);
    expect(native.methods.where((m) => m == 'ownedValidateGameGearZip'), hasLength(3));
  });

  OwnedInstallationRemoval remover() => OwnedInstallationRemoval(journal,
      storage: OwnedStorage(channel: native.channel));

  final gg =
      SystemModel.supportedSystems.singleWhere((s) => s.id == 'gamegear');
  Future<GameItem> installRaw(
      {String name = 'fixture.gg', Uint8List? bytes}) async {
    final data = bytes ?? payload;
    final source = RemoteArtifact.fromJson({
      ...artifact().toJson(),
      'displayName': name,
      'displayPath': name,
      'sizeBytes': data.length,
      'providerChecksums': {'md5': md5.convert(data).toString()}
    });
    media = (_, offset, __) async => DriveMediaResponse(
        bytes: Stream.value(Uint8List.sublistView(data, offset)),
        offset: offset,
        length: data.length - offset,
        total: data.length);
    await queue(source: source, name: name);
    expect((await engine().start('transfer').result).lifecycle,
        TransferLifecycle.completed);
    return GameItem(
        filename: name,
        displayName: 'Fixture',
        url: '',
        remoteArtifact: source);
  }

  InstallationIndex index() => InstallationIndex(journal,
      storage: OwnedStorage(channel: native.channel));
  Future<TransferRecord> queueReplacement() async {
    await queue();
    expect((await engine().start('transfer').result).lifecycle,
        TransferLifecycle.completed);
    final old = (await installed())!;
    final bytes = Uint8List.fromList([9, 8, 7, 6, 5]);
    final source = RemoteArtifact.fromJson({
      ...old.artifact.toJson(),
      'version': '2',
      'sizeBytes': bytes.length,
      'providerChecksums': {'md5': md5.convert(bytes).toString()}
    });
    media = (_, offset, __) async => DriveMediaResponse(
        bytes: Stream.value(Uint8List.sublistView(bytes, offset)),
        offset: offset,
        length: bytes.length - offset,
        total: bytes.length);
    return journal.create(TransferRecord(
        id: 'replacement',
        artifact: source,
        destinationRoot: '/roms',
        relativePath: 'fixture.v2.chd',
        stagePath: '/owned/replacement.partial',
        replacesInstallation: old));
  }

  test(
      'replacement commits a distinct verified target before retiring exact old bytes',
      () async {
    native.copyOnly = true;
    final next = await queueReplacement();
    var sawCommit = false;
    native.before = (call) async {
      if (call.method == 'ownedQuarantine') {
        sawCommit = true;
        expect((await journal.transfer(next.id))!.lifecycle,
            TransferLifecycle.completed);
        expect(native.files['/roms/fixture.chd']!.bytes, payload);
        expect(native.files['/roms/fixture.v2.chd']!.bytes, [9, 8, 7, 6, 5]);
      }
    };
    final result = await engine().start(next.id).result;
    expect(result.lifecycle, TransferLifecycle.completed,
        reason: result.errorCode);
    expect(sawCommit, isTrue);
    expect(native.files['/roms/fixture.chd'], isNull);
    expect(await journal.transfer('transfer'), isNull);
    expect(await journal.replacementPhase(next.id), 'retired');
  });
  test('paused replacement leaves old verified target and owner intact',
      () async {
    final next = await queueReplacement();
    final entered = Completer<void>(), release = Completer<void>();
    revalidate = (_) async {
      entered.complete();
      await release.future;
    };
    final operation = engine().start(next.id);
    await entered.future;
    final paused = operation.pause();
    release.complete();
    expect((await paused).lifecycle, TransferLifecycle.paused);
    expect(native.files['/roms/fixture.chd']!.bytes, payload);
    expect(await installed(), isNotNull);
    expect(native.files['/roms/fixture.v2.chd'], isNull);
  });
  test('changed old owner blocks new commit without overwriting either file',
      () async {
    final next = await queueReplacement();
    native.files['/roms/fixture.chd']!.stamp++;
    final result = await engine().start(next.id).result;
    expect(result.lifecycle, TransferLifecycle.failed);
    expect(native.files['/roms/fixture.chd']!.bytes, payload);
    expect(await installed(), isNotNull);
    expect(
        await journal.installationForTarget(
            destinationRoot: '/roms', relativePath: next.relativePath),
        isNull);
  });
  test('lost old-quarantine receipt recovers without another media download',
      () async {
    final next = await queueReplacement();
    native.after = (call) async {
      if (call.method == 'ownedQuarantine') {
        native.after = null;
        throw PlatformException(code: 'io_error');
      }
    };
    final result = await engine().start(next.id).result;
    expect(result.lifecycle, TransferLifecycle.completed);
    expect(await journal.replacementIssue(next.id), 'io_error');
    final requestsBefore = requests.length;
    expect(
        await retireReplacedInstallation(
            journal, OwnedStorage(channel: native.channel), result),
        isNull);
    expect(await journal.replacementPhase(next.id), 'retired');
    expect(requests.length, requestsBefore);
    expect(await installed(), isNull);
  });
  test(
      'changed new bytes after commit preserve old installation during cleanup',
      () async {
    native.copyOnly = true;
    final next = await queueReplacement();
    native.after = (call) async {
      if (call.method == 'ownedRetireStage' &&
          call.arguments['relativePath'] == next.relativePath) {
        native.files['/roms/fixture.v2.chd']!.bytes[0] ^= 1;
      }
    };
    final result = await engine().start(next.id).result;
    expect(result.lifecycle, TransferLifecycle.completed);
    expect(await journal.replacementIssue(next.id), 'changed');
    expect(native.files['/roms/fixture.chd']!.bytes, payload);
    expect(await installed(), isNotNull);
  });
  test(
      'owned achievement hash uses exact pinned committed bytes with bounded reads',
      () async {
    final game = await installRaw();
    final reads = <int>[];
    native.before = (call) async {
      if (call.method == 'ownedRead') {
        reads.add(call.arguments['length'] as int);
      }
    };
    expect(
        await RaHashService.computeInstalledHash(game, gg, '/roms',
            installations: index()),
        md5.convert(payload).toString());
    expect(reads, isNotEmpty);
    expect(
        reads.every((length) => length <= OwnedStorage.maxChunkBytes), isTrue);
  });
  test(
      'owned achievement hash rejects changed bytes even with unchanged native stat',
      () async {
    final game = await installRaw();
    native.files['/roms/fixture.gg']!.bytes[0] ^= 1;
    await expectLater(
        RaHashService.computeInstalledHash(game, gg, '/roms',
            installations: index()),
        throwsA(isA<OwnedStorageException>()));
  });
  test('owned achievement hash never borrows a namesake or container checksum',
      () async {
    final game = await installRaw();
    final other = game.copyWith(
        remoteArtifact: RemoteArtifact.fromJson(
            {...game.remoteArtifact!.toJson(), 'version': '2'}));
    await expectLater(
        RaHashService.computeInstalledHash(other, gg, '/roms',
            installations: index()),
        throwsA(isA<OwnedStorageException>()));
    final archive = GameItem(
        filename: 'fixture.7z',
        displayName: 'Fixture',
        url: '',
        remoteArtifact: game.remoteArtifact);
    final before = native.methods.length;
    expect(
        await RaHashService.computeInstalledHash(archive, gg, '/roms',
            installations: index()),
        isNull);
    expect(native.methods.length, before);
  });
  test(
      'owned achievement hash strips the actual NES header without buffering the ROM',
      () async {
    final data = Uint8List.fromList(
        [0x4e, 0x45, 0x53, 0x1a, ...List.filled(12, 0), 9, 8, 7, 6]);
    final game = await installRaw(name: 'fixture.nes', bytes: data);
    expect(
        await RaHashService.computeInstalledHash(
            game,
            SystemModel.supportedSystems.singleWhere((s) => s.id == 'nes'),
            '/roms',
            installations: index()),
        md5.convert([9, 8, 7, 6]).toString());
  });
  test('owned achievement hash strips SNES copier header using full file size',
      () async {
    final data = Uint8List.fromList(
        [...List.filled(512, 0xaa), ...List.filled(1024, 7)]);
    final game = await installRaw(name: 'fixture.smc', bytes: data);
    expect(
        await RaHashService.computeInstalledHash(
            game,
            SystemModel.supportedSystems.singleWhere((s) => s.id == 'snes'),
            '/roms',
            installations: index()),
        md5.convert(List.filled(1024, 7)).toString());
  });
  test(
      'owned achievement hash reads NDS ARM sections in hash order, not disk order',
      () async {
    final data = Uint8List(0xE00);
    final words = ByteData.sublistView(data);
    words.setUint32(0x20, 0x300, Endian.little);
    words.setUint32(0x2c, 16, Endian.little);
    words.setUint32(0x30, 0x200, Endian.little);
    words.setUint32(0x3c, 8, Endian.little);
    words.setUint32(0x68, 0x400, Endian.little);
    data.fillRange(0x300, 0x310, 9);
    data.fillRange(0x200, 0x208, 7);
    data.fillRange(0x400, 0xE00, 6);
    final expected = md5.convert([
      ...data.sublist(0, 0x160),
      ...List.filled(16, 9),
      ...List.filled(8, 7),
      ...List.filled(0xA00, 6)
    ]).toString();
    final game = await installRaw(name: 'fixture.nds', bytes: data);
    expect(
        await RaHashService.computeInstalledHash(
            game,
            SystemModel.supportedSystems.singleWhere((s) => s.id == 'nds'),
            '/roms',
            installations: index()),
        expected);
  });

  test('cross-mount removal leaves installation ready without a pending intent',
      () async {
    await queue();
    await engine().start('transfer').result;
    final manifest = (await installed())!;
    native.crossMount = true;
    await expectLater(
        remover().remove(manifest),
        throwsA(isA<OwnedStorageException>()
            .having((e) => e.code, 'code', 'cross_volume')));
    expect(await journal.hasPendingRemoval('transfer'), isFalse);
    expect(native.methods, isNot(contains('ownedQuarantine')));
    expect(native.files['/roms/fixture.chd'], isNotNull);
    expect((await installed())!.toJson(), manifest.toJson());
  });

  test('EXDEV recovery retains an unmoved installation and its audit record',
      () async {
    await queue();
    await engine().start('transfer').result;
    final manifest = (await installed())!;
    final intent = await journal.beginRemoval(
        (await journal.transfer('transfer'))!, manifest,
        id: 'old-intent', quarantinePath: '/owned/old-intent.partial');
    native.before = (call) async {
      if (call.method == 'ownedQuarantine') native.fail('cross_volume');
    };
    await remover().recover(intent.id);
    expect((await journal.removal(intent.id))!.phase.name, 'retained');
    expect((await journal.removal(intent.id))!.issue, 'cross_volume');
    expect(await journal.hasPendingRemoval('transfer'), isFalse);
    expect(await journal.pendingRemovals().toList(), isEmpty);
    expect(native.files['/roms/fixture.chd'], isNotNull);
    expect((await installed())!.toJson(), manifest.toJson());
    expect(native.methods, isNot(contains('ownedRetireQuarantine')));
    await remover().recover(intent.id); // terminal replay, no second attempt
    native.before = null;
    await remover().remove(
        manifest); // retained audit does not block a later supported attempt
    expect(await installed(), isNull);
  });

  for (final privateConflict in [false, true]) {
    test(
        'EXDEV preserves ambiguous ${privateConflict ? 'private' : 'public'} state',
        () async {
      await queue();
      await engine().start('transfer').result;
      final manifest = (await installed())!;
      final intent = await journal.beginRemoval(
          (await journal.transfer('transfer'))!, manifest,
          id: 'ambiguous-intent',
          quarantinePath: '/owned/ambiguous-intent.partial');
      native.before = (call) async {
        if (call.method == 'ownedQuarantine') {
          if (privateConflict) {
            native.files[intent.quarantinePath] = _NativeFile(999)..bytes = [9];
          } else {
            native.files['/roms/fixture.chd']!.stamp++;
          }
          native.fail('cross_volume');
        }
      };
      await expectLater(
          remover().recover(intent.id), throwsA(isA<OwnedStorageException>()));
      expect(await journal.hasPendingRemoval('transfer'), isTrue);
      expect((await journal.removal(intent.id))!.phase.name, 'intent');
      expect(native.methods, isNot(contains('ownedRetireQuarantine')));
    });
  }

  test(
      'verified installation removal keeps cloud entry and supports re-download',
      () async {
    await queue();
    await engine().start('transfer').result;
    final manifest = (await installed())!;
    final remote = manifest.artifact.toJson();
    native.before = (call) async {
      if (call.method == 'ownedQuarantine') {
        expect((await journal.pendingRemovals().toList()).single.phase,
            OwnedRemovalPhase.intent);
      }
      if (call.method == 'ownedRetireQuarantine') {
        expect((await journal.pendingRemovals().toList()).single.phase,
            OwnedRemovalPhase.deleting);
        expect(native.sessions, isEmpty);
      }
    };
    await remover().remove(manifest);
    expect(await installed(), isNull);
    expect(native.files, isEmpty);
    expect(manifest.artifact.toJson(), remote);
    expect(requests, [0]);
    native.before = null;
    await queue();
    await engine().start('transfer').result;
    expect(await installed(), isNotNull);
    expect(requests, [0, 0]);
  });

  for (final phase in ['ownedQuarantine', 'ownedRetireQuarantine']) {
    test(
        'lost $phase acknowledgement recovers without repeating download or deleting neighbor',
        () async {
      await queue();
      await engine().start('transfer').result;
      native.after = (call) async {
        if (call.method == phase) {
          native.after = null;
          throw PlatformException(code: 'io_error');
        }
      };
      await expectLater(remover().remove((await installed())!),
          throwsA(isA<OwnedStorageException>()));
      final pending = (await journal.pendingRemovals().toList()).single;
      final neighbor = _NativeFile(999)..bytes = [9, 9];
      native.files['/roms/fixture.chd'] = neighbor;
      await remover().recover(pending.id);
      expect(native.files['/roms/fixture.chd'], same(neighbor));
      expect(await installed(), isNull);
      expect(await journal.pendingRemovals().toList(), isEmpty);
      expect(requests, [0]);
    });
  }

  test(
      'changed installation and changed quarantine bytes are preserved conflicts',
      () async {
    await queue();
    await engine().start('transfer').result;
    final manifest = (await installed())!;
    final original = native.files['/roms/fixture.chd']!;
    original.stamp++;
    await expectLater(
        remover().remove(manifest), throwsA(isA<OwnedStorageException>()));
    expect(native.files['/roms/fixture.chd'], same(original));
    expect(await journal.pendingRemovals().toList(), isEmpty);
    original.stamp--;
    native.after = (call) async {
      if (call.method == 'ownedQuarantine') original.bytes[0] ^= 1;
    };
    await expectLater(
        remover().remove(manifest), throwsA(isA<OwnedStorageException>()));
    expect(native.files.values, contains(same(original)));
    expect(native.methods, isNot(contains('ownedRetireQuarantine')));
    expect(await installed(), isNotNull);
    expect(await journal.hasPendingRemoval('transfer'), isTrue);
  });

  test('commits only after journaled verified rename and closes the session',
      () async {
    await queue();
    native.before = (call) async {
      if (call.method == 'ownedPublish') {
        final stored = (await journal.transfer('transfer'))!.toJson();
        expect(stored['publication'], isNotNull);
        expect(stored['verifiedChecksums'], contains('sha256'));
        expect(await installed(), isNull);
      }
    };
    final result = await engine().start('transfer').result;
    expect(result.lifecycle, TransferLifecycle.completed);
    expect((await installed())!.verifiedChecksums['sha256'],
        sha256.convert(payload).toString());
    expect(native.files['/roms/fixture.chd']!.bytes, payload);
    expect(requests, [0]);
    expect(checks, greaterThanOrEqualTo(2));
    expect(validated.every((source) => source.id.key == artifact().id.key),
        isTrue);
  });
  test(
      'verified copy retires private source only after installation commit and close',
      () async {
    native.copyOnly = true;
    await queue();
    native.before = (call) async {
      final stored = (await journal.transfer('transfer'))!.toJson();
      if (call.method == 'ownedCopyOpen') {
        expect((stored['publication'] as Map)['method'], 'copy');
      }
      if (call.method == 'ownedCopyChunk') {
        expect(
            (stored['publication'] as Map)['destinationIdentity'], isNotNull);
        expect(native.files['/owned/transfer.partial'], isNotNull);
      }
      if (call.method == 'ownedRetireStage') {
        expect(stored['lifecycle'], 'completed');
        expect(await installed(), isNotNull);
        expect(native.sessions, isEmpty);
      }
    };
    final result = await engine().start('transfer').result;
    expect(result.lifecycle, TransferLifecycle.completed);
    expect(native.files.containsKey('/owned/transfer.partial'), isFalse);
    expect(result.toJson()['stageRetired'], true);
    expect(native.files['/roms/fixture.chd']!.bytes, payload);
  });
  test(
      'retirement failure keeps installation and retries offline after restart',
      () async {
    native.copyOnly = true;
    await queue();
    native.before = (call) async {
      if (call.method == 'ownedRetireStage') {
        throw PlatformException(code: 'access_denied');
      }
    };
    final first = await engine().start('transfer').result;
    expect(first.lifecycle, TransferLifecycle.completed);
    expect(first.stageRetired, false);
    expect(first.stageRetirementIssue, 'access_denied');
    expect(await installed(), isNotNull);
    expect(native.files['/owned/transfer.partial']!.bytes, payload);
    native.before = null;
    revalidate = (_) async => throw StateError('cleanup must not authorize');
    final retried = await engine().start('transfer').result;
    expect(retried.stageRetired, true);
    expect(retried.stageRetirementIssue, isNull);
    expect(requests, [0]);
    expect(native.files['/roms/fixture.chd']!.bytes, payload);
  });

  test('failed acknowledgement preserves completion and replays absent stage',
      () async {
    native.copyOnly = true;
    journal = _RetirementAckFailure(Future.value(db));
    await queue();
    final outcome = await engine().start('transfer').result;
    expect(outcome.lifecycle, TransferLifecycle.completed);
    expect(outcome.stageRetired, false);
    final persisted = (await journal.transfer('transfer'))!;
    expect(persisted.lifecycle, TransferLifecycle.completed);
    expect(persisted.stageRetired, false);
    expect(native.files.containsKey('/owned/transfer.partial'), false);
    expect(await installed(), isNotNull);
    journal = TransferJournal(Future.value(db));
    revalidate = (_) async => throw StateError('cleanup must stay offline');
    expect((await engine().start('transfer').result).stageRetired, true);
    expect(requests, [0]);
  });

  test('failed native directory sync replays deletion without touching ROM',
      () async {
    native.copyOnly = true;
    await queue();
    native.after = (call) async {
      if (call.method == 'ownedRetireStage') {
        throw PlatformException(code: 'io_error');
      }
    };
    final first = await engine().start('transfer').result;
    expect(first.stageRetirementIssue, 'io_error');
    expect(first.stageRetired, false);
    expect(native.files.containsKey('/owned/transfer.partial'), false);
    native.after = null;
    expect((await engine().start('transfer').result).stageRetired, true);
    expect(native.files['/roms/fixture.chd']!.bytes, payload);
  });

  test(
      'postcommit close failure defers retirement without failing installation',
      () async {
    native.copyOnly = true;
    await queue();
    native.after = (call) async {
      if (call.method == 'ownedClose') {
        expect(await installed(), isNotNull);
        throw PlatformException(code: 'io_error');
      }
    };
    final outcome = await engine().start('transfer').result;
    expect(outcome.lifecycle, TransferLifecycle.completed);
    expect(outcome.stageRetired, false);
    expect(outcome.stageRetirementIssue, 'close_unconfirmed');
    expect(native.methods, isNot(contains('ownedRetireStage')));
    expect(native.files['/owned/transfer.partial']!.bytes, payload);
    native.after = null;
    expect((await engine().start('transfer').result).stageRetired, true);
    expect(requests, [0]);
    expect(native.files['/roms/fixture.chd']!.bytes, payload);
  });

  test('changed private stage is preserved despite completed installation',
      () async {
    native.copyOnly = true;
    await queue();
    native.before = (call) async {
      if (call.method == 'ownedRetireStage') {
        native.files['/owned/transfer.partial'] = _NativeFile(999)..bytes = [9];
      }
    };
    final result = await engine().start('transfer').result;
    expect(result.stageRetirementIssue, 'changed');
    expect(result.stageRetired, false);
    expect(native.files['/owned/transfer.partial']!.bytes, [9]);
    expect(native.files['/roms/fixture.chd']!.bytes, payload);
  });

  test('changed installed object keeps the retained source', () async {
    native.copyOnly = true;
    await queue();
    native.before = (call) async {
      if (call.method == 'ownedRetireStage') {
        native.files['/roms/fixture.chd'] = _NativeFile(999)..bytes = [9];
      }
    };
    final result = await engine().start('transfer').result;
    expect(result.stageRetirementIssue, 'changed');
    expect(native.files['/owned/transfer.partial']!.bytes, payload);
    expect(native.files['/roms/fixture.chd']!.bytes, [9]);
  });

  for (final copy in [false, true]) {
    test('completed engine reuse checks installed identity (copy=$copy)',
        () async {
      native.copyOnly = copy;
      await queue();
      expect((await engine().start('transfer').result).lifecycle,
          TransferLifecycle.completed);
      native.files['/roms/fixture.chd'] = _NativeFile(999)..bytes = [9];
      revalidate = (_) async => throw StateError('reuse must stay offline');
      await expectLater(
          engine().start('transfer').result,
          throwsA(isA<OwnedStorageException>()
              .having((error) => error.code, 'code', 'changed')));
      expect((await journal.transfer('transfer'))!.lifecycle,
          TransferLifecycle.completed);
      expect(requests, [0]);
      expect(native.files['/roms/fixture.chd']!.bytes, [9]);
    });
  }

  test('retirement cannot be acknowledged before commit or forged through save',
      () async {
    await queue();
    final queued = (await journal.transfer('transfer'))!;
    await expectLater(journal.stageRetirementResult(queued), throwsStateError);
    await expectLater(
        journal.save(queued.copyWith(stageRetired: true)), throwsStateError);
    await expectLater(
        journal.save(queued.copyWith(stageRetirementIssue: 'changed')),
        throwsStateError);
    expect(native.methods, isEmpty);
  });

  test('retirement acknowledgements require the current immutable snapshot',
      () async {
    native.copyOnly = true;
    await queue();
    native.before = (call) async {
      if (call.method == 'ownedRetireStage') {
        throw PlatformException(code: 'access_denied');
      }
    };
    final old = await engine().start('transfer').result;
    final next = await journal.stageRetirementResult(old, issue: 'changed');
    await expectLater(journal.stageRetirementResult(old), throwsStateError);
    await expectLater(
        journal.stageRetirementResult(next.copyWith(stageRetired: true)),
        throwsStateError);
    expect((await journal.transfer('transfer'))!.stageRetired, false);
  });

  test('a shared engine revalidates each exact queued artifact', () async {
    await queue();
    final second = RemoteArtifact.fromJson({
      ...artifact().toJson(),
      'id': RemoteArtifactId(
              providerId: 'drive',
              sourceId: 'source',
              accountId: 'account',
              providerFileId: 'second')
          .toJson(),
      'displayPath': 'second.chd',
      'displayName': 'second.chd'
    });
    await journal.create(TransferRecord(
        id: 'second-transfer',
        artifact: second,
        destinationRoot: '/roms',
        relativePath: 'second.chd',
        stagePath: '/owned/second-transfer.partial'));
    final shared = engine();
    expect((await shared.start('transfer').result).lifecycle,
        TransferLifecycle.completed);
    final firstChecks = validated.length;
    expect((await shared.start('second-transfer').result).lifecycle,
        TransferLifecycle.completed);
    expect(
        validated
            .take(firstChecks)
            .every((source) => source.id.key == artifact().id.key),
        isTrue);
    expect(
        validated
            .skip(firstChecks)
            .every((source) => source.id.key == second.id.key),
        isTrue);
  });
  test(
      'cancellation joins a pending write and checkpoints before reporting paused',
      () async {
    await queue();
    final entered = Completer<void>();
    final release = Completer<void>();
    native.before = (call) async {
      if (call.method == 'ownedWrite' && !entered.isCompleted) {
        entered.complete();
        await release.future;
      }
    };
    final operation = engine().start('transfer');
    await entered.future;
    var drained = false;
    final cancellation = operation.pause().then((value) {
      drained = true;
      return value;
    });
    expect(drained, isFalse);
    expect(await installed(), isNull);
    release.complete();
    final paused = await cancellation;
    expect(paused.lifecycle, TransferLifecycle.paused);
    expect(paused.durableOffset, 65536);
    expect((await journal.transfer('transfer'))!.durableOffset, 65536);
    expect(await installed(), isNull);
    native.before = null;
    final resumed = await engine().start('transfer').result;
    expect(resumed.lifecycle, TransferLifecycle.completed);
    expect(requests, [0, 65536]);
  });
  test(
      'cancel during namespace publication does not commit; relaunch verifies target without download',
      () async {
    await queue();
    final entered = Completer<void>();
    final release = Completer<void>();
    native.after = (call) async {
      if (call.method == 'ownedPublish') {
        entered.complete();
        await release.future;
      }
    };
    final operation = engine().start('transfer');
    await entered.future;
    final paused = operation.pause();
    release.complete();
    expect((await paused).lifecycle, TransferLifecycle.paused);
    expect(await installed(), isNull);
    native.after = null;
    expect((await engine().start('transfer').result).lifecycle,
        TransferLifecycle.completed);
    expect(requests, [0]);
  });
  test('a rename without a saved receipt is recovered from identity and hashes',
      () async {
    await queue();
    native.after = (call) async {
      if (call.method == 'ownedPublish') {
        throw PlatformException(code: 'io_error');
      }
    };
    final failed = await engine().start('transfer').result;
    expect(failed.lifecycle, TransferLifecycle.failed);
    expect(failed.publication!.confirmed, isFalse);
    expect(failed.publication!.destinationIdentity, isNull);
    expect(await installed(), isNull);
    // Emulate the process-death durable lifecycle without treating the returned
    // native success/error as a publication receipt.
    await journal
        .save(failed.copyWith(lifecycle: TransferLifecycle.publishing));
    native.after = null;
    final recovered = await engine().start('transfer').result;
    expect(recovered.lifecycle, TransferLifecycle.completed);
    expect(requests, [0]);
    expect(native.methods.where((m) => m == 'ownedPublish').length, 1);
  });
  test('an existing target is preserved and never adopted by filename',
      () async {
    await queue();
    final existing = _NativeFile(999)..bytes = [9, 8, 7];
    native.files['/roms/fixture.chd'] = existing;
    final failed = await engine().start('transfer').result;
    expect(failed.lifecycle, TransferLifecycle.failed);
    expect(failed.errorCode, 'storage_collision');
    expect(native.files['/roms/fixture.chd'], same(existing));
    expect(existing.bytes, [9, 8, 7]);
    expect(await installed(), isNull);
  });
  test('unrecorded private stage identity is not guessed on a retry', () async {
    await queue();
    final unowned = _NativeFile(999);
    native.files['/owned/transfer.partial'] = unowned;
    final failed = await engine().start('transfer').result;
    expect(failed.errorCode, 'storage_collision');
    expect(failed.stageIdentity, isNull);
    expect(requests, isEmpty);
    expect(native.files['/owned/transfer.partial'], same(unowned));
    expect(await installed(), isNull);
  });
  test(
      'changed destination identity between publication and commit is preserved',
      () async {
    await queue();
    final replaced = _NativeFile(999)..bytes = [1, 2, 3];
    revalidate = (_) async {
      if (++checks == 3) native.files['/roms/fixture.chd'] = replaced;
    };
    final failed = await engine().start('transfer').result;
    expect(failed.errorCode, 'storage_changed');
    expect(await installed(), isNull);
    expect(native.files['/roms/fixture.chd'], same(replaced));
  });
  test('checksum mismatch preserves stage and never publishes', () async {
    await queue(
        source: artifact(hashes: {'md5': '00000000000000000000000000000000'}));
    final result = await engine().start('transfer').result;
    expect(result.lifecycle, TransferLifecycle.failed);
    expect(result.errorCode, 'checksum_mismatch');
    expect(native.methods, isNot(contains('ownedPublish')));
    expect(await installed(), isNull);
  });
  test('interrupted verifying lifecycle resumes hashing without network',
      () async {
    await queue();
    native.before = (call) async {
      if (call.method == 'ownedRead') {
        throw PlatformException(code: 'io_error');
      }
    };
    final failed = await engine().start('transfer').result;
    expect(failed.lifecycle, TransferLifecycle.failed);
    // The durable state at process death can be verifying without hashes yet.
    await journal.save(failed.copyWith(lifecycle: TransferLifecycle.verifying));
    native.before = null;
    final recovered = await engine().start('transfer').result;
    expect(recovered.lifecycle, TransferLifecycle.completed);
    expect(requests, [0]);
  });
  test(
      'private uncommitted tail is truncated and its new timestamp checkpointed',
      () async {
    await queue();
    final entered = Completer<void>();
    final release = Completer<void>();
    native.before = (call) async {
      if (call.method == 'ownedWrite' && !entered.isCompleted) {
        entered.complete();
        await release.future;
      }
    };
    final operation = engine().start('transfer');
    await entered.future;
    final stop = operation.pause();
    release.complete();
    final paused = await stop;
    expect(paused.durableOffset, 65536);
    // Bytes written after the last SQLite checkpoint, before process death.
    final stage = native.files['/owned/transfer.partial']!;
    stage.bytes.addAll([1, 2, 3]);
    stage.stamp++;
    native.before = null;
    final recovered = await engine().start('transfer').result;
    expect(recovered.lifecycle, TransferLifecycle.completed);
    expect(requests, [0, 65536]);
    expect(native.files['/roms/fixture.chd']!.bytes, payload);
  });
  test('stream close failure is observed while a native write still drains',
      () async {
    await queue();
    final entered = Completer<void>();
    final release = Completer<void>();
    native.before = (call) async {
      if (call.method == 'ownedWrite' && !entered.isCompleted) {
        entered.complete();
        await release.future;
      }
    };
    late StreamController<Uint8List> input;
    input = StreamController<Uint8List>(
        onListen: () => input.add(payload),
        onCancel: () =>
            Future<void>.error(StateError('fixture close failure')));
    media = (source, offset, token) async => DriveMediaResponse(
        bytes: input.stream,
        offset: offset,
        length: payload.length,
        total: payload.length);
    final errors = <Object>[];
    final finished = Completer<TransferRecord>();
    runZonedGuarded(() async {
      try {
        final operation = engine().start('transfer');
        await entered.future;
        final stop = operation.pause();
        try {
          // A real asynchronous state query also verifies pause has not returned
          // before the native write finishes. No timer drives this boundary.
          expect((await journal.transfer('transfer'))!.lifecycle,
              TransferLifecycle.transferring);
        } finally {
          release.complete();
        }
        finished.complete(await stop);
      } catch (error, stack) {
        finished.completeError(error, stack);
      }
    }, (error, stack) {
      errors.add(error);
    });
    final result = await finished.future;
    expect(errors, isEmpty);
    expect(result.lifecycle, TransferLifecycle.failed);
    expect(result.durableOffset, 65536);
    expect(await installed(), isNull);
    await input.close();
  });
  test('cancellation during verified copy resumes only its remaining bytes',
      () async {
    native.copyOnly = true;
    await queue();
    final entered = Completer<void>();
    final release = Completer<void>();
    native.after = (call) async {
      if (call.method == 'ownedCopyChunk' && !entered.isCompleted) {
        entered.complete();
        await release.future;
      }
    };
    final operation = engine().start('transfer');
    await entered.future;
    final cancellation = operation.pause();
    release.complete();
    final paused = await cancellation;
    expect(paused.lifecycle, TransferLifecycle.paused);
    expect(paused.publication!.copiedOffset, 65536);
    expect(await installed(), isNull);
    native.after = null;
    expect((await engine().start('transfer').result).lifecycle,
        TransferLifecycle.completed);
    expect(requests, [0]);
    expect(native.files['/roms/fixture.chd']!.bytes, payload);
  });
  test('confirmed copy recovers after final revalidation needs authorization',
      () async {
    native.copyOnly = true;
    await queue();
    revalidate = (_) async {
      if (++checks == 3) {
        throw const DriveAuthorizationException(
            DriveAuthorizationIssue.interactionRequired);
      }
    };
    final failed = await engine().start('transfer').result;
    expect(failed.lifecycle, TransferLifecycle.awaitingAuthorization);
    expect(failed.publication!.confirmed, isTrue);
    expect(await installed(), isNull);
    revalidate = (_) async {};
    final recovered = await engine().start('transfer').result;
    expect(recovered.lifecycle, TransferLifecycle.completed);
    expect(requests, [0]);
  });
  test('cancellation closes a stalled input and joins its disposal', () async {
    await queue();
    final listened = Completer<void>();
    final cancelled = Completer<void>();
    final release = Completer<void>();
    final input = StreamController<Uint8List>(
        onListen: () => listened.complete(),
        onCancel: () async {
          cancelled.complete();
          await release.future;
        });
    media = (source, offset, token) async => DriveMediaResponse(
        bytes: input.stream,
        offset: offset,
        length: payload.length,
        total: payload.length);
    final operation = engine().start('transfer');
    await listened.future;
    var drained = false;
    final pause = operation.pause().then((value) {
      drained = true;
      return value;
    });
    await cancelled.future;
    expect(drained, isFalse);
    release.complete();
    expect((await pause).lifecycle, TransferLifecycle.paused);
    expect(await installed(), isNull);
    await input.close();
  });
  test(
      'cancellation joins the current prefix read without scanning the remainder',
      () async {
    native.copyOnly = true;
    await queue();
    final first = Completer<void>();
    final releaseFirst = Completer<void>();
    native.after = (call) async {
      if (call.method == 'ownedCopyFinish') {
        first.complete();
        await releaseFirst.future;
      }
    };
    final original = engine().start('transfer');
    await first.future;
    final paused = original.pause();
    releaseFirst.complete();
    await paused;
    final read = Completer<void>();
    final releaseRead = Completer<void>();
    var prefixReads = 0;
    native.after = (call) async {
      if (call.method == 'ownedCopyValidatePrefix') {
        prefixReads++;
        if (!read.isCompleted) {
          read.complete();
          await releaseRead.future;
        }
      }
    };
    final resumed = engine().start('transfer');
    await read.future;
    final stop = resumed.pause();
    releaseRead.complete();
    expect((await stop).lifecycle, TransferLifecycle.paused);
    expect(prefixReads, 1);
    expect(await installed(), isNull);
  });
  test('API cancellation during revalidation is durably paused', () async {
    await queue();
    final entered = Completer<void>();
    revalidate = (token) async {
      entered.complete();
      await token.whenCancel;
      throw const DriveApiException(DriveApiIssue.cancelled);
    };
    final operation = engine().start('transfer');
    await entered.future;
    expect((await operation.pause()).lifecycle, TransferLifecycle.paused);
    expect(native.methods, isEmpty);
  });
  test('native authorization cancellation joins into the requested pause',
      () async {
    await queue();
    final entered = Completer<void>();
    revalidate = (token) async {
      entered.complete();
      await token.whenCancel;
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.cancelled);
    };
    final operation = engine().start('transfer');
    await entered.future;
    expect((await operation.pause()).lifecycle, TransferLifecycle.paused);
    expect(native.methods, isEmpty);
  });
  test('publication recovery verifies the persisted local SHA256 too',
      () async {
    await queue();
    native.before = (call) async {
      if (call.method == 'ownedPublish') {
        throw PlatformException(code: 'io_error');
      }
    };
    final failed = await engine().start('transfer').result;
    expect(failed.lifecycle, TransferLifecycle.failed);
    final json = failed.toJson();
    json['verifiedChecksums'] = {
      ...failed.verifiedChecksums,
      'sha256': '0' * 64
    };
    // Simulate inconsistent persisted evidence, not a new journal API that can
    // weaken verified digests. Recovery must not trust this local digest blindly.
    await db.update('transfer_records', {'record_json': jsonEncode(json)},
        where: 'transfer_id = ?', whereArgs: ['transfer']);
    native.before = null;
    final recovered = await engine().start('transfer').result;
    expect(recovered.lifecycle, TransferLifecycle.failed);
    expect(recovered.errorCode, 'checksum_mismatch');
    expect(await installed(), isNull);
  });
  test('pause while installation transaction is queued rolls back completion',
      () async {
    final barrier = _CompletionBarrierJournal(Future.value(db));
    journal = barrier;
    await queue();
    final operation = engine().start('transfer');
    await barrier.entered.future;
    final stop = operation.pause();
    barrier.release.complete();
    final result = await stop;
    expect(result.lifecycle, TransferLifecycle.paused);
    expect(result.publication!.confirmed, isTrue);
    expect(await installed(), isNull);
    journal = TransferJournal(Future.value(db));
    expect((await engine().start('transfer').result).lifecycle,
        TransferLifecycle.completed);
    expect(requests, [0]);
  });
  Future<TransferRecord> queueBundle() async {
    const namespace = 'rshop-bundle-test';
    final members = [
      for (var i = 1; i <= 2; i++)
        TransferBundleMember(
            transferId: 'disc-$i-${'a' * 64}',
            artifact: RemoteArtifact.fromJson({
              ...artifact().toJson(),
              'id': {...artifact().id.toJson(), 'providerFileId': 'disc-$i'},
              'displayName': 'Disc $i.chd'
            }),
            relativePath: '$namespace/Disc $i.chd')
    ];
    return journal.create(TransferRecord(
        id: 'playlist',
        artifact: artifact(),
        destinationRoot: '/roms',
        relativePath: '$namespace/game.m3u',
        stagePath: '/owned/playlist.partial',
        bundleMembers: members));
  }

  test(
      'bundle cannot commit with missing discs; exact children never independently ready',
      () async {
    native.copyOnly = true;
    final root = await queueBundle();
    expect((await engine().start(root.id).result).lifecycle,
        TransferLifecycle.failed);
    final index = InstallationIndex(journal,
        storage: OwnedStorage(channel: native.channel));
    expect(await index.resolveArtifact(root.artifact, '/roms'), isNull);
    for (final member in root.bundleMembers) {
      await journal.create(TransferRecord(
          id: member.transferId,
          artifact: member.artifact,
          destinationRoot: '/roms',
          relativePath: member.relativePath,
          stagePath: '/owned/${member.transferId}.partial',
          bundleOwner: root.id));
      final result = await engine().start(member.transferId).result;
      expect(result.lifecycle, TransferLifecycle.completed);
      expect(result.stageRetired, isTrue);
      expect(await index.resolveArtifact(member.artifact, '/roms'), isNull);
    }
    final completed = await engine().start(root.id).result;
    expect(completed.lifecycle, TransferLifecycle.completed);
    expect(completed.stageRetired, isTrue);
    final manifest = await journal.installationForTarget(
        destinationRoot: '/roms', relativePath: root.relativePath);
    expect(manifest!.dependencies.map((m) => m.transferId),
        root.bundleMembers.map((m) => m.transferId));
    expect(await index.resolveArtifact(root.artifact, '/roms'),
        p.normalize(p.absolute('/roms/${root.relativePath}')));
    final save = _NativeFile(990)..bytes = [42];
    native.files['/roms/rshop-bundle-test/user-save.sav'] = save;
    await expectLater(remover().remove(manifest.dependencies.first),
        throwsA(isA<OwnedStorageException>()));
    await remover().remove(manifest);
    expect(await index.resolveArtifact(root.artifact, '/roms'), isNull);
    expect(native.files, {'/roms/rshop-bundle-test/user-save.sav': save});
    expect((await db.query('installed_artifacts')), isEmpty);
  });

  test(
      'bundle removal resumes after child quarantine receipt loss, preserving its save',
      () async {
    final root = await queueBundle();
    for (final member in root.bundleMembers) {
      await journal.create(TransferRecord(
          id: member.transferId,
          artifact: member.artifact,
          destinationRoot: '/roms',
          relativePath: member.relativePath,
          stagePath: '/owned/${member.transferId}.partial',
          bundleOwner: root.id));
      expect((await engine().start(member.transferId).result).lifecycle,
          TransferLifecycle.completed);
    }
    expect((await engine().start(root.id).result).lifecycle,
        TransferLifecycle.completed);
    final manifest = (await journal.installationForTarget(
        destinationRoot: '/roms', relativePath: root.relativePath))!;
    var lost = false;
    native.after = (call) async {
      if (call.method == 'ownedQuarantine' &&
          (call.arguments as Map)['relativePath'] ==
              root.bundleMembers.first.relativePath &&
          !lost) {
        lost = true;
        throw StateError('lost child quarantine receipt');
      }
    };
    await expectLater(
        remover().remove(manifest), throwsA(isA<OwnedStorageException>()));
    expect(lost, isTrue);
    expect(
        await InstallationIndex(journal,
                storage: OwnedStorage(channel: native.channel))
            .resolveArtifact(root.artifact, '/roms'),
        isNull);
    native.after = null;
    final rootRemoval = (await db.query('owned_removals',
            where: 'transfer_id = ?', whereArgs: [root.id]))
        .single;
    await remover().recover(rootRemoval['removal_id'] as String);
    expect(await db.query('installed_artifacts'), isEmpty);
    expect(native.files, isEmpty);
  });

  test('committed bundle update wins over retained same-version playlist',
      () async {
    final old = await queueBundle();
    Future<void> installBundle(TransferRecord root) async {
      for (final member in root.bundleMembers) {
        await journal.create(TransferRecord(
            id: member.transferId,
            artifact: member.artifact,
            destinationRoot: root.destinationRoot,
            relativePath: member.relativePath,
            stagePath: '/owned/${member.transferId}.partial',
            bundleOwner: root.id));
        expect((await engine().start(member.transferId).result).lifecycle,
            TransferLifecycle.completed);
      }
      expect((await engine().start(root.id).result).lifecycle,
          TransferLifecycle.completed);
    }

    await installBundle(old);
    final previous = (await journal.installationForTarget(
        destinationRoot: '/roms', relativePath: old.relativePath))!;
    final next = await journal.create(TransferRecord(
        id: 'updated-playlist',
        artifact: old.artifact,
        destinationRoot: '/roms',
        relativePath: 'rshop-bundle-updated/game.m3u',
        stagePath: '/owned/updated-playlist.partial',
        replacesInstallation: previous,
        bundleMembers: [
          for (final member in old.bundleMembers)
            TransferBundleMember(
                transferId: 'updated-${member.transferId}',
                artifact: RemoteArtifact.fromJson(
                    {...member.artifact.toJson(), 'version': '2'}),
                relativePath: member.relativePath
                    .replaceFirst('rshop-bundle-test', 'rshop-bundle-updated'))
        ]));
    native.before = (call) async {
      if (call.method == 'ownedQuarantine') {
        throw PlatformException(code: 'io_error');
      }
    };
    await installBundle(next);
    expect(await journal.replacementIssue(next.id), 'io_error');
    expect(native.files['/roms/${old.relativePath}'], isNotNull);
    expect(await journal.transfer(old.id), isNotNull);
    expect(await index().resolveArtifact(old.artifact, '/roms'),
        p.normalize(p.absolute('/roms/${next.relativePath}')));
    final game = GameItem(
        filename: 'game.m3u',
        displayName: 'Fixture',
        url: '',
        remoteArtifact: old.artifact);
    expect(
        (await RomManager(installations: index())
                .requireInstalledArtifact(game, '/roms'))
            .transferId,
        next.id);
    expect((await index().scan('/roms')).installed.length, 1);
  });

  test('missing checksum fails before any storage or network work', () async {
    await queue(source: artifact(hashes: {}));
    final result = await engine().start('transfer').result;
    expect(result.errorCode, 'missing_checksum');
    expect(requests, isEmpty);
    expect(native.methods, isEmpty);
    expect(await installed(), isNull);
  });
  test('post-transfer source change cannot commit installation', () async {
    await queue();
    revalidate = (_) async {
      if (++checks == 2) {
        throw const DriveTransferException(DriveTransferIssue.sourceChanged);
      }
    };
    final result = await engine().start('transfer').result;
    expect(result.errorCode, 'source_changed');
    expect(await installed(), isNull);
  });
  test('authorization need is a resumable explicit state, not completion',
      () async {
    await queue();
    revalidate = (_) async {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.interactionRequired);
    };
    final result = await engine().start('transfer').result;
    expect(result.lifecycle, TransferLifecycle.awaitingAuthorization);
    expect(await installed(), isNull);
    expect(requests, isEmpty);
  });
}
