import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/services/transfer_journal.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

RemoteArtifact _artifact({
  String fileId = 'file-1',
  String version = 'version-1',
  int sizeBytes = 5,
  Map<String, String> providerChecksums = const {
    'md5': '7cfdd07889b3295d6a550914ab35e068',
  },
}) =>
    RemoteArtifact(
      id: RemoteArtifactId(
        providerId: 'drive',
        sourceId: 'source-1',
        accountId: 'account-1',
        providerFileId: fileId,
      ),
      parentId: 'folder-1',
      displayPath: 'psx/Fixture.chd',
      displayName: 'Fixture.chd',
      sizeBytes: sizeBytes,
      modifiedAt: DateTime.utc(2026, 9, 9, 8, 30),
      version: version,
      providerChecksums: providerChecksums,
      canDownload: true,
    );

TransferRecord _queued({
  String id = 'transfer-1',
  String relativePath = 'Sony - PlayStation/Fixture.chd',
  Map<String, String> providerChecksums = const {
    'md5': '7cfdd07889b3295d6a550914ab35e068',
  },
}) =>
    TransferRecord(
      id: id,
      artifact: _artifact(
        fileId: '$id-file',
        providerChecksums: providerChecksums,
      ),
      destinationRoot: '/storage/roms',
      relativePath: relativePath,
      stagePath: '/storage/.r-shop-staging/$id.partial',
    );

NativeFileIdentity _fileIdentity({String fileId = 'inode-42'}) =>
    NativeFileIdentity(
      volumeId: 'sd-volume-1',
      fileId: fileId,
      sizeBytes: 5,
      modifiedAt: DateTime.utc(2026, 9, 9, 9),
    );

String get _fixtureSha256 => sha256.convert([1, 2, 3, 4, 5]).toString();

InstalledArtifact _installation(
  TransferRecord transfer, {
  String id = 'installation-1',
  String fileId = 'inode-42',
}) =>
    InstalledArtifact(
      id: id,
      transferId: transfer.id,
      artifact: transfer.artifact,
      destinationRoot: transfer.destinationRoot,
      relativePath: transfer.relativePath,
      sizeBytes: transfer.artifact.sizeBytes!,
      verifiedChecksums: transfer.verifiedChecksums.isEmpty
          ? {
              'md5': '7cfdd07889b3295d6a550914ab35e068',
              'sha256': _fixtureSha256,
            }
          : transfer.verifiedChecksums,
      fileIdentity: _fileIdentity(fileId: fileId),
      gameId: 'game-1',
      editionId: 'edition-1',
    );

Future<TransferRecord> _advanceToPublishing(
    TransferJournal journal, TransferRecord transfer,
    {Map<String, String>? verifiedChecksums}) async {
  var current = await journal.save(
    transfer.copyWith(lifecycle: TransferLifecycle.transferring),
  );
  current = await journal.save(current.copyWith(durableOffset: 5));
  current = await journal.save(
    current.copyWith(
      lifecycle: TransferLifecycle.verifying,
      verifiedChecksums: verifiedChecksums ??
          {
            'md5': '7cfdd07889b3295d6a550914ab35e068',
            'sha256': _fixtureSha256,
          },
    ),
  );
  return journal.save(
    current.copyWith(lifecycle: TransferLifecycle.publishing),
  );
}

void main() {
  late Database db;
  late TransferJournal journal;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.transaction(TransferJournalSchema.install);
    journal = TransferJournal(Future.value(db));
  });
  tearDown(() => db.close());

  test('schema is additive and idempotent', () async {
    await db.execute('CREATE TABLE legacy_queue(id TEXT PRIMARY KEY)');
    await db.insert('legacy_queue', {'id': 'keep-me'});

    await db.transaction(TransferJournalSchema.install);
    await db.transaction(TransferJournalSchema.install);

    expect((await db.query('legacy_queue')).single['id'], 'keep-me');
    expect(await db.query('transfer_records'), isEmpty);
    expect(await db.query('installed_artifacts'), isEmpty);
  });

  test('create persists an exact immutable artifact snapshot', () async {
    final source = _queued();
    final created = await journal.create(source);

    expect(created.revision, 0);
    expect(created.lifecycle, TransferLifecycle.queued);
    expect(created.durableOffset, 0);
    expect((await journal.transfer(source.id))!.toJson(), source.toJson());

    final changedCatalogueArtifact = _artifact(
      fileId: 'transfer-1-file',
      version: 'version-2',
      sizeBytes: 99,
    );
    expect(changedCatalogueArtifact.toJson(), isNot(created.artifact.toJson()));
    expect((await journal.transfer(source.id))!.artifact.toJson(),
        created.artifact.toJson());
    expect(
      () => created.artifact.providerChecksums['md5'] = 'changed',
      throwsUnsupportedError,
    );
  });

  test('unsafe relative targets are rejected before reaching SQLite', () {
    for (final path in [
      '../escape.chd',
      'psx/../../escape.chd',
      '/absolute.chd',
      r'C:\absolute.chd',
      r'psx\backslash.chd',
      'psx//empty.chd',
      './Fixture.chd',
      'Fixture.chd\u0000suffix',
    ]) {
      expect(
        () => _queued(relativePath: path),
        throwsArgumentError,
        reason: path,
      );
    }
  });

  test('target reservation rejects a second owner and preserves the first',
      () async {
    final first = await journal.create(_queued(id: 'first'));

    await expectLater(
      journal.create(_queued(id: 'second')),
      throwsStateError,
    );

    expect((await journal.transfer(first.id))!.id, 'first');
    expect(await journal.transfer('second'), isNull);
    expect(
        await journal.targetOwner(
          destinationRoot: first.destinationRoot,
          relativePath: first.relativePath,
        ),
        'first');
  });

  test('save validates transitions and rejects completion declarations',
      () async {
    final created = await journal.create(_queued());

    await expectLater(
      journal.save(
        created.copyWith(lifecycle: TransferLifecycle.publishing),
      ),
      throwsStateError,
    );
    await expectLater(
      journal.save(
        created.copyWith(lifecycle: TransferLifecycle.completed),
      ),
      throwsStateError,
    );

    final transferring = await journal.save(
      created.copyWith(lifecycle: TransferLifecycle.transferring),
    );
    final paused = await journal.save(
      transferring.copyWith(
        lifecycle: TransferLifecycle.paused,
        durableOffset: 3,
      ),
    );
    expect(paused.revision, 2);
    expect(paused.durableOffset, 3);
    expect(paused.lifecycle, TransferLifecycle.paused);
  });

  test('compare-and-swap rejects late callbacks without changing state',
      () async {
    final created = await journal.create(_queued());
    final transferring = await journal.save(
      created.copyWith(lifecycle: TransferLifecycle.transferring),
    );

    await expectLater(
      journal.save(
        created.copyWith(
          lifecycle: TransferLifecycle.failed,
          errorCode: 'late_transport_failure',
        ),
      ),
      throwsStateError,
    );

    final restored = await journal.transfer(created.id);
    expect(restored!.revision, transferring.revision);
    expect(restored.lifecycle, TransferLifecycle.transferring);
    expect(restored.errorCode, isNull);
  });

  test('durable offsets are monotonic unless explicit paused reset is used',
      () async {
    var current = await journal.create(_queued());
    current = await journal.save(
      current.copyWith(lifecycle: TransferLifecycle.transferring),
    );
    current = await journal.save(current.copyWith(durableOffset: 4));

    await expectLater(
      journal.save(current.copyWith(durableOffset: 0)),
      throwsStateError,
    );
    await expectLater(journal.resetPartial(current), throwsStateError);

    current = await journal.save(
      current.copyWith(lifecycle: TransferLifecycle.paused),
    );
    final reset = await journal.resetPartial(current);
    expect(reset.durableOffset, 0);
    expect(reset.verifiedChecksums, isEmpty);
    expect(reset.lifecycle, TransferLifecycle.paused);
    expect(reset.revision, current.revision + 1);
  });

  test(
      'failed partial reset is explicit and never an ordinary save side effect',
      () async {
    var current = await journal.create(_queued());
    current = await journal.save(
      current.copyWith(lifecycle: TransferLifecycle.transferring),
    );
    current = await journal.save(current.copyWith(durableOffset: 2));
    current = await journal.save(
      current.copyWith(
        lifecycle: TransferLifecycle.failed,
        errorCode: 'truncated_response',
      ),
    );

    final reset = await journal.resetPartial(current);
    expect(reset.durableOffset, 0);
    expect(reset.lifecycle, TransferLifecycle.failed);
    expect(reset.errorCode, 'truncated_response');
  });

  test('error codes cannot persist exception text, URLs, or bearer tokens', () {
    for (final unsafe in [
      'Bearer secret-token',
      'https://example.invalid/?access_token=secret',
      'SocketException: raw transport detail',
      'UPPER_CASE',
    ]) {
      expect(
        () => _queued().copyWith(
          lifecycle: TransferLifecycle.failed,
          errorCode: unsafe,
        ),
        throwsArgumentError,
      );
    }
    expect(
      _queued()
          .copyWith(
            lifecycle: TransferLifecycle.failed,
            errorCode: 'source_changed',
          )
          .errorCode,
      'source_changed',
    );
  });

  test('supported verified digests require their exact hexadecimal length', () {
    for (final malformed in [
      {'md5': 'x'},
      {'sha1': '0' * 39},
      {'sha256': 'g' * 64},
    ]) {
      expect(
        () => _queued().copyWith(verifiedChecksums: malformed),
        throwsArgumentError,
        reason: malformed.toString(),
      );
    }
  });

  test('completion atomically commits exact installation then truthful state',
      () async {
    final publishing = await _advanceToPublishing(
      journal,
      await journal.create(_queued()),
    );
    final installation = _installation(publishing);

    final completed = await journal.complete(publishing, installation);

    expect(completed.lifecycle, TransferLifecycle.completed);
    expect(completed.revision, publishing.revision + 1);
    expect((await journal.transfer(publishing.id))!.lifecycle,
        TransferLifecycle.completed);
    expect(
      (await journal.installationForTarget(
        destinationRoot: publishing.destinationRoot,
        relativePath: publishing.relativePath,
      ))!
          .toJson(),
      installation.toJson(),
    );
  });

  test('completion requires publishing, all bytes, and verified hashes',
      () async {
    final created = await journal.create(_queued());
    await expectLater(
      journal.complete(created, _installation(created)),
      throwsStateError,
    );

    var current = await journal.save(
      created.copyWith(lifecycle: TransferLifecycle.transferring),
    );
    current = await journal.save(current.copyWith(durableOffset: 5));
    current = await journal.save(
      current.copyWith(lifecycle: TransferLifecycle.verifying),
    );
    current = await journal.save(
      current.copyWith(lifecycle: TransferLifecycle.publishing),
    );
    await expectLater(
      journal.complete(current, _installation(current)),
      throwsStateError,
    );
    expect(
        await journal.installationForTarget(
          destinationRoot: current.destinationRoot,
          relativePath: current.relativePath,
        ),
        isNull);
  });

  test('unknown-only provider checksums cannot authorize completion', () async {
    final publishing = await _advanceToPublishing(
      journal,
      await journal.create(_queued(
        providerChecksums: const {'crc32': '01020304'},
      )),
      verifiedChecksums: {
        'crc32': '01020304',
        'sha256': _fixtureSha256,
      },
    );

    await expectLater(
      journal.complete(publishing, _installation(publishing)),
      throwsStateError,
    );
    expect(
        await journal.installationForTarget(
          destinationRoot: publishing.destinationRoot,
          relativePath: publishing.relativePath,
        ),
        isNull);
    expect((await journal.transfer(publishing.id))!.lifecycle,
        TransferLifecycle.publishing);
  });

  test('malformed recognized provider evidence is not silently ignored',
      () async {
    final publishing = await _advanceToPublishing(
        journal,
        await journal.create(_queued(providerChecksums: {
          'md5': '7cfdd07889b3295d6a550914ab35e068',
          'sha1': 'not-a-digest',
        })));
    await expectLater(journal.complete(publishing, _installation(publishing)),
        throwsStateError);
    expect(await db.query('installed_artifacts'), isEmpty);
  });

  test('stale completion is rejected before an installation is inserted',
      () async {
    final publishing = await _advanceToPublishing(
      journal,
      await journal.create(_queued()),
    );
    final newer = await journal.save(publishing.copyWith());

    await expectLater(
      journal.complete(publishing, _installation(publishing)),
      throwsStateError,
    );

    expect((await journal.transfer(publishing.id))!.revision, newer.revision);
    expect((await journal.transfer(publishing.id))!.lifecycle,
        TransferLifecycle.publishing);
    expect(await db.query('installed_artifacts'), isEmpty);
  });

  for (final failingTable in ['transfer_records', 'transfer_target_owners']) {
    test('failed $failingTable commit rolls back every completion write',
        () async {
      final publishing =
          await _advanceToPublishing(journal, await journal.create(_queued()));
      await db.execute(
          '''CREATE TRIGGER fail_completion BEFORE UPDATE ON $failingTable
        BEGIN SELECT RAISE(ABORT, 'synthetic commit fault'); END''');
      await expectLater(journal.complete(publishing, _installation(publishing)),
          throwsA(isA<DatabaseException>()));
      expect(await db.query('installed_artifacts'), isEmpty);
      expect((await journal.transfer(publishing.id))!.toJson(),
          publishing.toJson());
      final owner = (await db.query('transfer_target_owners')).single;
      expect(owner['installation_id'], isNull);
      expect(owner['transfer_id'], publishing.id);
      await db.execute('DROP TRIGGER fail_completion');
      final completed =
          await journal.complete(publishing, _installation(publishing));
      expect(completed.lifecycle, TransferLifecycle.completed);
      expect(await db.query('installed_artifacts'), hasLength(1));
    });
  }

  test('completion conflict preserves a different existing target owner',
      () async {
    final publishing = await _advanceToPublishing(
      journal,
      await journal.create(_queued()),
    );
    final other = InstalledArtifact(
      id: 'existing-installation',
      transferId: 'older-transfer',
      artifact: _artifact(fileId: 'older-file', version: 'older-version'),
      destinationRoot: publishing.destinationRoot,
      relativePath: publishing.relativePath,
      sizeBytes: 5,
      verifiedChecksums: const {
        'md5': '7cfdd07889b3295d6a550914ab35e068',
      },
      fileIdentity: _fileIdentity(fileId: 'older-inode'),
    );
    await db.update(
      'transfer_target_owners',
      {
        'transfer_id': other.transferId,
        'installation_id': other.id,
      },
      where: 'destination_root = ? AND relative_path = ?',
      whereArgs: [publishing.destinationRoot, publishing.relativePath],
    );
    await db.insert('installed_artifacts', {
      'installation_id': other.id,
      'transfer_id': other.transferId,
      'destination_root': other.destinationRoot,
      'relative_path': other.relativePath,
      'record_json': jsonEncode(other.toJson()),
    });

    await expectLater(
      journal.complete(publishing, _installation(publishing)),
      throwsStateError,
    );

    expect(
      (await journal.installationForTarget(
        destinationRoot: publishing.destinationRoot,
        relativePath: publishing.relativePath,
      ))!
          .id,
      other.id,
    );
    expect((await journal.transfer(publishing.id))!.lifecycle,
        TransferLifecycle.publishing);
    expect(await db.query('installed_artifacts'), hasLength(1));
  });

  test('journal state survives database close and reopen', () async {
    final tempRoot = Directory(r'D:\Temp').existsSync()
        ? Directory(r'D:\Temp')
        : Directory.systemTemp;
    final tempDirectory = await tempRoot.createTemp('r-shop-transfer-journal-');
    final databasePath = p.join(tempDirectory.path, 'journal.sqlite');
    addTearDown(() async {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    var diskDb = await databaseFactoryFfi.openDatabase(databasePath);
    await diskDb.transaction(TransferJournalSchema.install);
    var diskJournal = TransferJournal(Future.value(diskDb));
    var current = await diskJournal.create(_queued(id: 'reopen-transfer'));
    current = await diskJournal.save(
      current.copyWith(lifecycle: TransferLifecycle.transferring),
    );
    current = await diskJournal.save(
      current.copyWith(
        lifecycle: TransferLifecycle.paused,
        durableOffset: 3,
      ),
    );
    await diskDb.close();

    diskDb = await databaseFactoryFfi.openDatabase(databasePath);
    addTearDown(diskDb.close);
    diskJournal = TransferJournal(Future.value(diskDb));
    final restored = await diskJournal.transfer(current.id);

    expect(restored!.toJson(), current.toJson());
    expect(restored.lifecycle, TransferLifecycle.paused);
    expect(restored.durableOffset, 3);
    expect(restored.artifact.version, 'version-1');
  });
}
