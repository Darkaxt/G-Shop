import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';
import 'package:retro_eshop/services/drive/drive_media.dart';
import 'package:retro_eshop/services/drive/drive_transfer_engine.dart';
import 'package:retro_eshop/services/owned_storage.dart';
import 'package:retro_eshop/services/transfer_journal.dart';
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
        'stageMount': '10',
        'destinationFreeBytes': 1 << 30,
        'stageFreeBytes': 1 << 30
      };
    }
    final stage = a['stagePath'] as String?;
    final target = '${a['destinationRoot']}/${a['relativePath']}';
    if (call.method == 'ownedInspect') {
      return files[a['published'] == true ? target : stage]?.identity;
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
        if (published) {
          if (file.identity.toString() !=
              Map<String, Object>.from(a['expectedIdentity']).toString()) {
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
  RemoteArtifact artifact({Map<String, String>? hashes}) => RemoteArtifact(
      id: RemoteArtifactId(
          providerId: 'drive',
          sourceId: 'source',
          accountId: 'account',
          providerFileId: 'file'),
      parentId: 'folder',
      displayPath: 'fixture.chd',
      displayName: 'fixture.chd',
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
  Future<void> queue({RemoteArtifact? source}) async =>
      journal.create(TransferRecord(
          id: 'transfer',
          artifact: source ?? artifact(),
          destinationRoot: '/roms',
          relativePath: 'fixture.chd',
          stagePath: '/owned/transfer.partial'));
  Future<InstalledArtifact?> installed() => journal.installationForTarget(
      destinationRoot: '/roms', relativePath: 'fixture.chd');

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
      'unsupported rename uses journaled exclusive verified copy retaining source',
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
      }
    };
    final result = await engine().start('transfer').result;
    expect(result.lifecycle, TransferLifecycle.completed);
    expect(native.files['/owned/transfer.partial']!.bytes, payload);
    expect(native.files['/roms/fixture.chd']!.bytes, payload);
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
