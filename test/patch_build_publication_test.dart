import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/transfer_record.dart';
import 'package:g_shop/services/installation_index.dart';
import 'package:g_shop/services/owned_storage.dart';
import 'package:g_shop/services/verified_file_publication.dart';
import 'package:g_shop/services/transfer_journal.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/owned_storage_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Database db;
  late TransferJournal journal;
  late OwnedStorageFixture native;
  late VerifiedFilePublication publisher;
  late File output;
  final bytes = Uint8List.fromList(List.generate(131085, (i) => i % 251));
  RemoteArtifact artifact({String id = 'recipe'}) => RemoteArtifact(
      id: RemoteArtifactId(
          providerId: 'patch-build',
          sourceId: 'generated-patches',
          providerFileId: id),
      displayPath: 'Hacks/result.gba',
      displayName: 'result.gba',
      sizeBytes: bytes.length,
      version: 'recipe:${sha256.convert(bytes)}',
      canDownload: false,
      providerChecksums: {'sha256': sha256.convert(bytes).toString()});
  Future<TransferRecord> publish(
          {String id = 'build', CancelToken? cancellation}) =>
      publisher.publish(
          transferId: 'patch-$id',
          artifact: artifact(),
          output: output,
          targetRoot: '/roms',
          filename: 'result.gba',
          cancellation: cancellation ?? CancelToken());
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await TransferJournalSchema.install(db);
    journal = TransferJournal(Future.value(db));
    native = OwnedStorageFixture()..install();
    publisher = VerifiedFilePublication(journal,
        storage: OwnedStorage(channel: native.channel));
    final root =
        await Directory.systemTemp.createTemp('rshop-patch-publication-');
    output = File('${root.path}/result.raw');
    await output.writeAsBytes(bytes);
  });
  tearDown(() async {
    expect(native.sessions, isEmpty);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native.channel, null);
    await db.close();
    // The task's registered scratch root owns these bounded host fixture files.
  });
  test('streaming raw fingerprint verifies CRC and strong hashes across chunks',
      () async {
    final value = '123456789'.codeUnits;
    final result = await fingerprintPatchBytes(
        Stream.fromIterable([value.take(4).toList(), value.skip(4).toList()]),
        CancelToken(),
        expectedSize: 9,
        expected: {'crc32': 'cbf43926'});
    expect(result.hashes['sha256'], sha256.convert(value).toString());
    await expectLater(
        fingerprintPatchBytes(Stream.value(value), CancelToken(),
            expected: {'crc32': '00000000'}),
        throwsA(isA<PatchBuildException>()
            .having((e) => e.code, 'code', 'input_fingerprint_mismatch')));
    await expectLater(
        fingerprintPatchBytes(Stream.value(value), CancelToken()..cancel()),
        throwsA(isA<PatchBuildException>()
            .having((e) => e.code, 'code', 'cancelled')));
  });
  test(
      'generated result uses verified journal installation and exact second-use receipt',
      () async {
    final original = NativeFileFixture(999)..bytes = [4, 3, 2, 1];
    native.files['/roms/original.gba'] = original;
    final first = await publish();
    expect(first.lifecycle, TransferLifecycle.completed);
    final installed = await journal.installationForTarget(
        destinationRoot: '/roms', relativePath: 'result.gba');
    await InstallationIndex(journal, storage: publisher.storage)
        .requireInstallation(first, installed);
    expect(native.files['/roms/result.gba']!.bytes, bytes);
    expect(native.files['/roms/original.gba'], same(original));
    final writes = native.methods.where((m) => m == 'ownedWrite').length;
    expect((await publish()).id, first.id);
    expect(native.methods.where((m) => m == 'ownedWrite').length, writes);
    expect(await output.readAsBytes(), bytes);
  });
  test('cross-volume copy completes and retires its owned private stage',
      () async {
    native.copyOnly = true;
    final result = await publish();
    expect(result.lifecycle, TransferLifecycle.completed);
    expect(result.publication!.method, PublicationMethod.copy);
    expect(result.stageRetired, isTrue);
    expect(native.files.containsKey(result.stagePath), isFalse);
    expect(native.files['/roms/result.gba']!.bytes, bytes);
  });
  test(
      'failed close keeps recoverable publication, restart does not repatch or rewrite',
      () async {
    var failClose = true;
    native.after = (call) async {
      if (call.method == 'ownedClose' && failClose) {
        failClose = false;
        throw PlatformException(code: 'io_error');
      }
    };
    await expectLater(publish(), throwsA(isA<OwnedStorageException>()));
    expect(
        await journal.installationForTarget(
            destinationRoot: '/roms', relativePath: 'result.gba'),
        isNull);
    expect((await journal.transfer('patch-build'))!.publication!.confirmed,
        isTrue);
    final writes = native.methods.where((m) => m == 'ownedWrite').length;
    publisher = VerifiedFilePublication(TransferJournal(Future.value(db)),
        storage: publisher.storage);
    final result = await publish();
    expect(result.lifecycle, TransferLifecycle.completed);
    expect(native.methods.where((m) => m == 'ownedWrite').length, writes);
  });
  test(
      'cancelled receive resumes the same private stage and preserves the original',
      () async {
    final cancellation = CancelToken();
    native.after = (call) async {
      if (call.method == 'ownedWrite') cancellation.cancel();
    };
    await expectLater(publish(cancellation: cancellation),
        throwsA(isA<PatchBuildException>()));
    expect((await journal.transfer('patch-build'))!.lifecycle,
        TransferLifecycle.paused);
    expect(native.files.containsKey('/roms/result.gba'), isFalse);
    native.after = null;
    final resumed = await publish();
    expect(resumed.lifecycle, TransferLifecycle.completed);
    expect(native.files['/roms/result.gba']!.bytes, bytes);
  });
  test(
      'collision never overwrites a prior valid result or registers its namesake',
      () async {
    final prior = NativeFileFixture(999)..bytes = [7, 8, 9];
    native.files['/roms/result.gba'] = prior;
    await expectLater(
        publish(),
        throwsA(isA<OwnedStorageException>()
            .having((e) => e.code, 'code', 'collision')));
    expect(native.files['/roms/result.gba'], same(prior));
    expect(prior.bytes, [7, 8, 9]);
    expect(
        await journal.installationForTarget(
            destinationRoot: '/roms', relativePath: 'result.gba'),
        isNull);
  });
}
