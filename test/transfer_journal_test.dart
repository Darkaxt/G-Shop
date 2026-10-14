import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/models/owned_removal_record.dart';
import 'package:retro_eshop/models/local_cloud_byte_observation.dart';
import 'package:retro_eshop/services/transfer_journal.dart';
import 'package:retro_eshop/services/rom_cache_store.dart';
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

NativeFileIdentity _fileIdentity(
        {String fileId = 'inode-42', int sizeBytes = 5, int nanoseconds = 0}) =>
    NativeFileIdentity(
      volumeId: 'sd-volume-1',
      fileId: fileId,
      sizeBytes: sizeBytes,
      modifiedAt: DateTime.utc(2026, 9, 9, 9)
          .add(Duration(microseconds: nanoseconds ~/ 1000)),
      modifiedNanoseconds: nanoseconds,
    );

TransferRecord _stage(TransferRecord record, int size,
        {String fileId = 'inode-42'}) =>
    TransferRecord.fromJson({
      ...record.toJson(),
      'durableOffset': size,
      'stageIdentity': _fileIdentity(fileId: fileId, sizeBytes: size).toJson(),
    });

TransferRecord _publication(
  TransferRecord record, {
  String method = 'rename',
  NativeFileIdentity? destination,
  bool confirmed = false,
  NativeFileIdentity? source,
}) =>
    TransferRecord.fromJson({
      ...record.toJson(),
      'lifecycle': TransferLifecycle.publishing.name,
      'publication': {
        'method': method,
        'sourceIdentity': (source ?? _fileIdentity()).toJson(),
        if (destination != null) 'destinationIdentity': destination.toJson(),
        'confirmed': confirmed,
      },
    });

Future<void> _seedLegacy(Database db, TransferRecord record) async {
  final json = record.toJson()
    ..remove('stageIdentity')
    ..remove('publication');
  await db.update(
      'transfer_records',
      {
        'durable_offset': record.durableOffset,
        'lifecycle': record.lifecycle.name,
        'record_json': jsonEncode(json),
      },
      where: 'transfer_id = ?',
      whereArgs: [record.id]);
}

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
    {Map<String, String>? verifiedChecksums, bool confirm = true}) async {
  var current = await journal.save(
    transfer.copyWith(lifecycle: TransferLifecycle.transferring),
  );
  current = await journal.save(_stage(current, 5));
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
  current = await journal.save(_publication(current));
  if (confirm) {
    return journal.save(
        _publication(current, destination: _fileIdentity(), confirmed: true));
  }
  return current;
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

  test('adoption atomically owns exact public bytes with truthful provenance', () async {
    final observation = DriveLocalCloudObservation(artifact: _artifact(),
        destinationRoot: '/storage/roms', relativePath: 'Fixture.chd',
        localIdentity: _fileIdentity(), sizeBytes: 5,
        checksums: {'md5': '7cfdd07889b3295d6a550914ab35e068', 'sha256': _fixtureSha256},
        observedAt: DateTime.utc(2026,10,6));
    final installed = await journal.adoptVerifiedFile(observation,
        id: 'adopt-one', stagePath: '/private/review.partial', checkCancellation: () {});
    final reopened = TransferJournal(Future.value(db));
    final record = (await reopened.transfer(installed.transferId))!;
    expect(record.publication!.method, PublicationMethod.adopt);
    expect(record.stageIdentity, isNull);
    expect(record.stageRetired, isTrue);
    expect(record.lifecycle, TransferLifecycle.completed);
    expect((await reopened.installationForTarget(destinationRoot: observation.destinationRoot,
        relativePath: observation.relativePath))!.toJson(), installed.toJson());
    await expectLater(journal.adoptVerifiedFile(observation, id: 'adopt-two',
        stagePath: '/private/other.partial', checkCancellation: () {}), throwsStateError);
    expect(await db.query('transfer_records'), hasLength(1));
    expect(await db.query('transfer_target_owners'), hasLength(1));
    expect(await db.query('owned_removals'), isEmpty);
  });
  for (final failure in ['cancel', 'database']) {
    test('adoption $failure rolls back all ownership writes', () async {
      final observation = DriveLocalCloudObservation(artifact: _artifact(),
          destinationRoot: '/storage/roms', relativePath: 'Fixture.chd',
          localIdentity: _fileIdentity(), sizeBytes: 5,
          checksums: {'md5': '7cfdd07889b3295d6a550914ab35e068', 'sha256': _fixtureSha256},
          observedAt: DateTime.utc(2026,10,6));
      if (failure == 'database') {
        await db.execute('''CREATE TRIGGER fail_adoption
          BEFORE INSERT ON transfer_target_owners BEGIN SELECT RAISE(ABORT, 'fixture'); END''');
      }
      var checks = 0;
      await expectLater(journal.adoptVerifiedFile(observation, id: 'adopt-one',
          stagePath: '/private/review.partial', checkCancellation: () {
            if (++checks == 2 && failure == 'cancel') throw StateError('cancelled');
          }), throwsA(anything));
      expect(await db.query('transfer_records'), isEmpty);
      expect(await db.query('installed_artifacts'), isEmpty);
      expect(await db.query('transfer_target_owners'), isEmpty);
    });
  }

  test('replacement holds its old owner until verified new commit and retirement', () async {
    final oldPublishing = await _advanceToPublishing(journal, await journal.create(_queued()));
    final old = _installation(oldPublishing);
    final oldRecord = await journal.complete(oldPublishing, old);
    final next = TransferRecord.fromJson({
      ..._queued(id: 'next', relativePath: 'next.chd').toJson(),
      'artifact': {...old.artifact.toJson(), 'version': 'version-2'},
      'replacesInstallation': old.toJson(),
    });
    await journal.create(next);
    await expectLater(journal.beginRemoval(oldRecord, old, id: 'user-remove',
        quarantinePath: '/private/user-remove.partial'), throwsStateError);
    // A second version cannot claim the same old installation, even at a new path.
    final competing = TransferRecord.fromJson({...next.toJson(), 'id': 'competing',
      'relativePath': 'competing.chd', 'stagePath': '/private/competing.partial'});
    await expectLater(journal.create(competing), throwsStateError);
    expect(await journal.transfer('competing'), isNull);
    var replacement = await _advanceToPublishing(journal, next);
    final installed = _installation(replacement, id: 'new-installation');
    replacement = await journal.complete(replacement, installed);
    expect(await journal.installationForTarget(destinationRoot: old.destinationRoot,
        relativePath: old.relativePath), isNotNull);
    final removal = await journal.beginRemoval(oldRecord, old, id: 'replacement-next',
        quarantinePath: '/private/replacement-next.partial', replacementTransferId: replacement.id);
    final quarantined = await journal.advanceRemoval(removal, OwnedRemovalPhase.quarantined);
    final deleting = await journal.advanceRemoval(quarantined, OwnedRemovalPhase.deleting);
    await journal.finishRemoval(deleting);
    await journal.finishReplacement(replacement);
    expect(await journal.transfer(oldRecord.id), isNull);
    expect(await journal.transfer(replacement.id), isNotNull);
    expect(await journal.pendingReplacements().toList(), isEmpty);
  });

  test('replacement cannot retire old bytes before new commit or borrow a namesake', () async {
    final publishing = await _advanceToPublishing(journal, await journal.create(_queued()));
    final old = _installation(publishing);
    final completed = await journal.complete(publishing, old);
    final invalid = TransferRecord.fromJson({..._queued(id: 'bad', relativePath: 'bad.chd').toJson(),
      'replacesInstallation': old.toJson()});
    await expectLater(journal.create(invalid), throwsStateError);
    final next = TransferRecord.fromJson({...invalid.toJson(),
      'artifact': {...old.artifact.toJson(), 'version': 'version-2'}});
    await journal.create(next);
    await expectLater(journal.beginRemoval(completed, old, id: 'replacement-bad',
      quarantinePath: '/private/replacement-bad.partial', replacementTransferId: next.id), throwsStateError);
    await expectLater(journal.finishReplacement(next), throwsStateError);
    await journal.save(next.copyWith(lifecycle: TransferLifecycle.paused));
    expect(await journal.installationForTarget(destinationRoot: old.destinationRoot,
      relativePath: old.relativePath), isNotNull);
  });

  test('removal intent, deletion and owner release are durable separate phases', () async {
    final publishing = await _advanceToPublishing(journal, await journal.create(_queued()));
    final manifest = _installation(publishing);
    final completed = await journal.complete(publishing, manifest);
    final intent = await journal.beginRemoval(completed, manifest,
        id: 'remove-1', quarantinePath: '/private/remove-1.partial');
    expect(intent.phase, OwnedRemovalPhase.intent);
    expect(await journal.hasPendingRemoval(completed.id), isTrue);
    expect(await journal.installationForTarget(destinationRoot: completed.destinationRoot,
        relativePath: completed.relativePath), isNotNull);
    await expectLater(journal.finishRemoval(intent), throwsStateError);
    await expectLater(journal.advanceRemoval(intent, OwnedRemovalPhase.deleting), throwsStateError);
    final quarantined = await journal.advanceRemoval(intent, OwnedRemovalPhase.quarantined);
    await expectLater(journal.advanceRemoval(intent, OwnedRemovalPhase.quarantined), throwsStateError);
    final deleting = await journal.advanceRemoval(quarantined, OwnedRemovalPhase.deleting);
    await journal.finishRemoval(deleting);
    expect((await journal.removal('remove-1'))!.phase, OwnedRemovalPhase.completed);
    expect(await journal.hasPendingRemoval(completed.id), isFalse);
    expect(await journal.transfer(completed.id), isNull);
    expect(await journal.targetOwner(destinationRoot: completed.destinationRoot,
        relativePath: completed.relativePath), isNull);
    expect(await journal.installationForTarget(destinationRoot: completed.destinationRoot,
        relativePath: completed.relativePath), isNull);
    // New download reservation is allowed only after removal commit.
    await journal.create(_queued());
  });

  test('cache removal retires usage so identical reinstallation starts a fresh persistence window', () async {
    final publishing=await _advanceToPublishing(journal,await journal.create(_queued()));
    final manifest=_installation(publishing);
    final completed=await journal.complete(publishing,manifest);
    final store=RomCacheStore(Future.value(db));
    final oldUse=DateTime.now().toUtc();
    await store.recordSuccessfulUse(manifest.id,oldUse);
    final intent=await journal.beginRemoval(completed,manifest,id:'cache-usage-removal',quarantinePath:'/private/cache-usage-removal.partial',policyDriven:true);
    final quarantined=await journal.advanceRemoval(intent,OwnedRemovalPhase.quarantined);
    await journal.finishRemoval(await journal.advanceRemoval(quarantined,OwnedRemovalPhase.deleting));
    expect(await store.usage(manifest.id),isNull);
    final again=await _advanceToPublishing(journal,await journal.create(_queued()));
    await journal.complete(again,_installation(again));
    final usage=(await store.usage(manifest.id))!;
    expect(usage.installedAt!.isBefore(oldUse),isFalse);
    expect(usage.lastUsedAt,isNull);
  });

  test('pending removal cannot be rewritten or duplicated and survives reopen', () async {
    final publishing = await _advanceToPublishing(journal, await journal.create(_queued()));
    final manifest = _installation(publishing);
    final completed = await journal.complete(publishing, manifest);
    final intent = await journal.beginRemoval(completed, manifest,
        id: 'remove-1', quarantinePath: '/private/remove-1.partial');
    await expectLater(journal.beginRemoval(completed, manifest,
        id: 'remove-2', quarantinePath: '/private/remove-2.partial'), throwsStateError);
    final reopened = TransferJournal(Future.value(db));
    expect((await reopened.removal(intent.id))!.toJson(), intent.toJson());
    expect((await reopened.pendingRemovals().toList()).single.id, intent.id);
    final conflicted = await reopened.removalIssue(intent, 'changed');
    expect(conflicted.issue, 'changed');
    expect(await reopened.pendingRemovals().toList(), isEmpty);
    expect(await reopened.hasPendingRemoval(completed.id), isTrue);
    expect(await reopened.transfer(completed.id), isNotNull);
  });

  test('v19 index migration retains ownership and permits a later removal attempt', () async {
    await db.execute('DROP INDEX idx_active_removal');
    await db.execute("CREATE UNIQUE INDEX idx_active_removal ON owned_removals(transfer_id) WHERE phase != 'completed'");
    final publishing = await _advanceToPublishing(journal, await journal.create(_queued()));
    final manifest = _installation(publishing);
    final completed = await journal.complete(publishing, manifest);
    final intent = await journal.beginRemoval(completed, manifest,
        id: 'retained-attempt', quarantinePath: '/private/retained-attempt.partial');
    await TransferJournalSchema.installRemovalRetention(db);
    await journal.retainUnmovedRemoval(intent);
    final retained = (await journal.removal(intent.id))!;
    expect(retained.phase, OwnedRemovalPhase.retained);
    expect(retained.issue, 'cross_volume');
    expect(await journal.hasPendingRemoval(completed.id), isFalse);
    expect(await journal.pendingRemovals().toList(), isEmpty);
    expect(await journal.transfer(completed.id), isNotNull);
    expect(await journal.installationForTarget(destinationRoot: completed.destinationRoot,
        relativePath: completed.relativePath), isNotNull);
    await expectLater(journal.finishRemoval(retained), throwsStateError);
    await expectLater(journal.advanceRemoval(retained, OwnedRemovalPhase.quarantined), throwsStateError);
    final next = await journal.beginRemoval(completed, manifest,
        id: 'next-attempt', quarantinePath: '/private/next-attempt.partial');
    final moved = await journal.advanceRemoval(next, OwnedRemovalPhase.quarantined);
    await expectLater(journal.retainUnmovedRemoval(moved), throwsStateError);
  });

  test('completed copy cannot forget a retained private stage during removal', () async {
    final publishing = await _advanceToPublishing(journal, await journal.create(_queued()), confirm: false);
    final intent = await journal.save(_publication(publishing, method: 'copy'));
    final copied = await journal.save(_publication(intent, method: 'copy',
        destination: _fileIdentity(fileId: 'copy-42'), confirmed: true));
    final manifest = _installation(copied, fileId: 'copy-42');
    final completed = await journal.complete(copied, manifest);
    await expectLater(journal.beginRemoval(completed, manifest,
        id: 'remove-1', quarantinePath: '/private/remove-1.partial'), throwsStateError);
    expect(await journal.hasPendingRemoval(completed.id), isFalse);
  });

  test(
      'pending private retirement scans completed copies in bounded keyset pages',
      () async {
    // Seed persisted snapshots to exercise enumeration independently of the
    // separately tested publication protocol. Include older JSON defaults.
    final expected = <String>[];
    await db.transaction((txn) async {
      for (var i = 0; i < 137; i++) {
        final id = 'pending-${i.toString().padLeft(3, '0')}';
        final pending = i % 4 == 0;
        final record = _publication(_stage(_queued(id: id), 5),
                method: i % 4 == 1 ? 'rename' : 'copy',
                destination: _fileIdentity(fileId: 'copy-$i'),
                confirmed: true)
            .copyWith(
                lifecycle: i % 4 == 2
                    ? TransferLifecycle.publishing
                    : TransferLifecycle.completed,
                stageRetired: i % 4 == 3);
        if (pending) expected.add(id);
        final json = record.toJson();
        if (pending) json.remove('stageRetired');
        await txn.insert('transfer_records', {
          'transfer_id': id,
          'artifact_key': record.artifact.id.key,
          'destination_root': record.destinationRoot,
          'relative_path': id,
          'lifecycle': record.lifecycle.name,
          'durable_offset': record.durableOffset,
          'revision': record.revision,
          'record_json': jsonEncode(json),
        });
      }
    });
    var continuePass = true;
    final stopped = <String>[];
    await for (final record in journal.pendingStageRetirements(
        batchSize: 7, shouldContinue: () => continuePass)) {
      stopped.add(record.id);
      continuePass = false;
    }
    expect(stopped, expected.take(1));
    final actual = <String>[];
    await for (final record in journal.pendingStageRetirements(batchSize: 7)) {
      actual.add(record.id);
      // Updating a visited row cannot shift the cursor or repeat its attempt.
      final json = record.copyWith(stageRetired: true).toJson();
      await db.update('transfer_records', {'record_json': jsonEncode(json)},
          where: 'transfer_id = ?', whereArgs: [record.id]);
    }
    expect(actual, expected);
    expect(await journal.pendingStageRetirements().toList(), isEmpty);
    final queryPlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT record_json '
        'FROM transfer_records WHERE lifecycle = ? AND transfer_id > ? '
        'ORDER BY transfer_id LIMIT 7',
        ['completed', 'pending-000']);
    expect(queryPlan.map((r) => r['detail']).join(' '),
        contains('idx_transfer_lifecycle'));
  });

  test('retirement page size cannot request unbounded history', () async {
    await expectLater(journal.pendingStageRetirements(batchSize: 0).toList(),
        throwsArgumentError);
    await expectLater(journal.pendingStageRetirements(batchSize: 129).toList(),
        throwsArgumentError);
  });

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

  test('archive mapping persists immutably without upgrading legacy intents', () async {
    final legacy = TransferRecord.fromJson({..._queued().toJson(), 'relativePath': 'Game.zip'});
    expect(legacy.archivePlatformId, isNull);
    expect(legacy.toJson().containsKey('archivePlatformId'), isFalse);
    final typed = TransferRecord.fromJson({...legacy.toJson(), 'archivePlatformId': 'gamegear'});
    await journal.create(typed);
    expect((await journal.transfer(typed.id))!.archivePlatformId, 'gamegear');
    expect(typed.copyWith(lifecycle: TransferLifecycle.paused).archivePlatformId, 'gamegear');
    await expectLater(journal.save(TransferRecord.fromJson({...typed.toJson()}..remove('archivePlatformId'))), throwsStateError);
    expect(() => TransferRecord.fromJson({...legacy.toJson(), 'archivePlatformId': 'psp'}), throwsArgumentError);
  });

  test('N64 archive mapping persists without approving untyped seven zip', () async {
    for (final extension in ['7z', 'zip']) {
      final legacy = TransferRecord.fromJson({..._queued(id: 'n64-$extension').toJson(),
        'relativePath': 'Game.$extension'});
      expect(legacy.archivePlatformId, isNull);
      final typed = TransferRecord.fromJson({...legacy.toJson(), 'archivePlatformId': 'n64'});
      await journal.create(typed);
      expect((await journal.transfer(typed.id))!.archivePlatformId, 'n64');
      expect(typed.copyWith(lifecycle: TransferLifecycle.paused).archivePlatformId, 'n64');
      await expectLater(journal.save(TransferRecord.fromJson({...typed.toJson()}..remove('archivePlatformId'))), throwsStateError);
    }
    expect(() => TransferRecord.fromJson({..._queued().toJson(),
      'relativePath': 'Game.chd', 'archivePlatformId': 'n64'}), throwsArgumentError);
  });

  test('new reservations reject preexisting stage or publication evidence',
      () async {
    await expectLater(journal.create(_stage(_queued(), 0)), throwsStateError);
    final withPublication = TransferRecord.fromJson({
      ..._publication(_queued()).toJson(),
      'lifecycle': 'queued',
    });
    await expectLater(journal.create(withPublication), throwsStateError);
    expect(await db.query('transfer_target_owners'), isEmpty);
  });

  test(
      'native identity distinguishes object ownership from exact byte evidence',
      () {
    final source = _fileIdentity();
    expect(source.sameObject(_fileIdentity(sizeBytes: 3)), isTrue);
    expect(source.matches(_fileIdentity(sizeBytes: 3)), isFalse);
    expect(source.matches(_fileIdentity(nanoseconds: 1)), isFalse);
    expect(source.sameObject(_fileIdentity(fileId: 'other')), isFalse);
    expect(
        source.matches(NativeFileIdentity.fromJson(source.toJson())), isTrue);
    final intent = TransferPublication(
        method: PublicationMethod.copy, sourceIdentity: source);
    expect(intent.confirmed, isFalse);
    expect(intent.copiedOffset, 0);
    final checkpoint = TransferPublication.fromJson({
      ...intent.toJson(),
      'destinationIdentity':
          _fileIdentity(fileId: 'copy', sizeBytes: 3).toJson()
    });
    expect(checkpoint.copiedOffset, 3);
  });

  test('durable checkpoints require the same stage object and exact size',
      () async {
    var current = await journal.create(_queued());
    current = await journal
        .save(current.copyWith(lifecycle: TransferLifecycle.transferring));
    await expectLater(
        journal.save(current.copyWith(durableOffset: 1)), throwsStateError);
    current = await journal.save(_stage(current, 0));
    final zero = current;
    current = await journal.save(_stage(current, 3));
    await expectLater(journal.save(_stage(current, 4, fileId: 'replacement')),
        throwsStateError);
    await expectLater(
        journal.save(_stage(current, 4).copyWith(durableOffset: 3)),
        throwsStateError);
    final cleared = current.toJson()..remove('stageIdentity');
    await expectLater(
        journal.save(TransferRecord.fromJson(cleared)), throwsStateError);
    await expectLater(journal.save(_stage(zero, 5)), throwsStateError);
    expect((await journal.transfer(current.id))!.toJson(), current.toJson());
  });

  test(
      'legacy unowned progress is readable but cannot acquire ownership or complete',
      () async {
    final created = await journal.create(_queued());
    final legacy = created.copyWith(
        durableOffset: 5,
        lifecycle: TransferLifecycle.publishing,
        verifiedChecksums: {
          'md5': '7cfdd07889b3295d6a550914ab35e068',
          'sha256': _fixtureSha256
        });
    await _seedLegacy(db, legacy);
    final restored =
        (await TransferJournal(Future.value(db)).transfer(legacy.id))!;
    expect(restored.durableOffset, 5);
    expect(restored.toJson()['stageIdentity'], isNull);
    await expectLater(
        journal.complete(restored, _installation(restored)), throwsStateError);
    await expectLater(journal.save(_stage(restored, 5)), throwsStateError);
    final paused = await journal
        .save(restored.copyWith(lifecycle: TransferLifecycle.paused));
    final reset = await journal.resetPartial(paused);
    expect(reset.durableOffset, 0);
    expect(reset.verifiedChecksums, isEmpty);
  });

  test(
      'native resume rebinds only the unverified stage timestamp at its durable offset',
      () async {
    var current = await journal.create(_queued());
    current = await journal
        .save(current.copyWith(lifecycle: TransferLifecycle.transferring));
    current = await journal.save(_stage(current, 3));
    current = await journal
        .save(current.copyWith(lifecycle: TransferLifecycle.paused));
    current = await journal
        .save(current.copyWith(lifecycle: TransferLifecycle.transferring));
    final resumedIdentity = _fileIdentity(sizeBytes: 3, nanoseconds: 1);
    await expectLater(
        journal.save(current.copyWith(stageIdentity: resumedIdentity)),
        throwsStateError);

    final resumed =
        await journal.resumeStageCheckpoint(current, resumedIdentity);
    expect(resumed.revision, current.revision + 1);
    expect(resumed.durableOffset, 3);
    expect(resumed.stageIdentity!.matches(resumedIdentity), isTrue);
    expect(resumed.verifiedChecksums, isEmpty);
    expect(resumed.publication, isNull);
    expect(resumed.lifecycle, TransferLifecycle.transferring);
    expect(
        (await TransferJournal(Future.value(db)).transfer(current.id))!
            .toJson(),
        resumed.toJson());
    await expectLater(journal.resumeStageCheckpoint(current, resumedIdentity),
        throwsStateError);
  });

  test(
      'native resume permits rechecking an unverified complete stage in verifying',
      () async {
    var current = await journal.create(_queued());
    current = await journal
        .save(current.copyWith(lifecycle: TransferLifecycle.transferring));
    current = await journal.save(_stage(current, 5));
    current = await journal
        .save(current.copyWith(lifecycle: TransferLifecycle.verifying));
    final identity = _fileIdentity(nanoseconds: 2);
    final resumed = await journal.resumeStageCheckpoint(current, identity);
    expect(resumed.durableOffset, 5);
    expect(resumed.lifecycle, TransferLifecycle.verifying);
    expect(resumed.stageIdentity!.matches(identity), isTrue);
  });

  test('native resume cannot rebind a verified stage timestamp', () async {
    var current = await journal.create(_queued());
    current = await journal
        .save(current.copyWith(lifecycle: TransferLifecycle.transferring));
    current = await journal.save(_stage(current, 5));
    current = await journal.save(current.copyWith(
        lifecycle: TransferLifecycle.verifying,
        verifiedChecksums: {
          'md5': '7cfdd07889b3295d6a550914ab35e068',
          'sha256': _fixtureSha256
        }));
    await expectLater(
        journal.resumeStageCheckpoint(current, _fileIdentity(nanoseconds: 1)),
        throwsStateError);
    final resumed =
        await journal.resumeStageCheckpoint(current, _fileIdentity());
    expect(resumed.revision, current.revision + 1);
    expect(resumed.stageIdentity!.matches(current.stageIdentity!), isTrue);
    expect(resumed.verifiedChecksums, current.verifiedChecksums);
  });

  test(
      'native resume requires existing ownership and an exact unchanged transfer record',
      () async {
    var current = await journal.create(_queued());
    current = await journal
        .save(current.copyWith(lifecycle: TransferLifecycle.transferring));
    await expectLater(
        journal.resumeStageCheckpoint(current, _fileIdentity(sizeBytes: 0)),
        throwsStateError);
    current = await journal.save(_stage(current, 3));
    for (final identity in [
      _fileIdentity(sizeBytes: 0),
      _fileIdentity(sizeBytes: 2),
      _fileIdentity(sizeBytes: 4),
      _fileIdentity(fileId: 'other', sizeBytes: 3),
      NativeFileIdentity.fromJson({
        ..._fileIdentity(sizeBytes: 3).toJson(),
        'volumeId': 'other-volume'
      }),
    ]) {
      await expectLater(
          journal.resumeStageCheckpoint(current, identity), throwsStateError);
    }
    await expectLater(
        journal.resumeStageCheckpoint(
            current.copyWith(durableOffset: 2), _fileIdentity(sizeBytes: 2)),
        throwsStateError);
    await expectLater(
        journal.resumeStageCheckpoint(current.copyWith(errorCode: 'changed'),
            _fileIdentity(sizeBytes: 3)),
        throwsStateError);
    expect((await journal.transfer(current.id))!.toJson(), current.toJson());
  });

  test('native resume refuses inactive and publication lifecycles', () async {
    var current = await journal.create(_queued());
    current = await journal.save(_stage(current, 0));
    await expectLater(
        journal.resumeStageCheckpoint(current, _fileIdentity(sizeBytes: 0)),
        throwsStateError);
    for (final lifecycle in [
      TransferLifecycle.paused,
      TransferLifecycle.failed,
      TransferLifecycle.awaitingAuthorization
    ]) {
      current = await journal.save(current.copyWith(lifecycle: lifecycle));
      await expectLater(
          journal.resumeStageCheckpoint(current, _fileIdentity(sizeBytes: 0)),
          throwsStateError);
    }
    current = await _advanceToPublishing(journal, current);
    await expectLater(journal.resumeStageCheckpoint(current, _fileIdentity()),
        throwsStateError);
    current = await journal.complete(current, _installation(current));
    await expectLater(journal.resumeStageCheckpoint(current, _fileIdentity()),
        throwsStateError);
  });

  test(
      'native resume database failure rolls back the identity and revision together',
      () async {
    var current = await journal.create(_queued());
    current = await journal
        .save(current.copyWith(lifecycle: TransferLifecycle.transferring));
    current = await journal.save(_stage(current, 3));
    await db
        .execute('''CREATE TRIGGER fail_resume BEFORE UPDATE ON transfer_records
      BEGIN SELECT RAISE(ABORT, 'synthetic resume fault'); END''');
    final identity = _fileIdentity(sizeBytes: 3, nanoseconds: 1);
    await expectLater(journal.resumeStageCheckpoint(current, identity),
        throwsA(isA<DatabaseException>()));
    expect((await journal.transfer(current.id))!.toJson(), current.toJson());
    await db.execute('DROP TRIGGER fail_resume');
    final resumed = await journal.resumeStageCheckpoint(current, identity);
    expect(resumed.revision, current.revision + 1);
    expect(resumed.stageIdentity!.matches(identity), isTrue);
  });

  test('verified bytes cannot change their stage evidence or lose digests',
      () async {
    final current =
        await _advanceToPublishing(journal, await journal.create(_queued()));
    final changed = TransferRecord.fromJson({
      ...current.toJson(),
      'stageIdentity': _fileIdentity(nanoseconds: 1).toJson()
    });
    await expectLater(journal.save(changed), throwsStateError);
    await expectLater(journal.save(current.copyWith(verifiedChecksums: {})),
        throwsStateError);
    final cleared = current.toJson()..remove('publication');
    await expectLater(
        journal.save(TransferRecord.fromJson(cleared)), throwsStateError);
    expect((await journal.transfer(current.id))!.toJson(), current.toJson());
  });

  test('publication intent requires exact verified stage before side effects',
      () async {
    var current = await journal.create(_queued());
    current = await journal
        .save(current.copyWith(lifecycle: TransferLifecycle.transferring));
    current = await journal.save(_stage(current, 5));
    current = await journal.save(current.copyWith(
        lifecycle: TransferLifecycle.verifying,
        verifiedChecksums: {
          'md5': '7cfdd07889b3295d6a550914ab35e068',
          'sha256': _fixtureSha256
        }));
    await expectLater(
        journal.save(current.copyWith(lifecycle: TransferLifecycle.publishing)),
        throwsStateError);
    await expectLater(
        journal.save(
            _publication(current, source: _fileIdentity(fileId: 'other'))),
        throwsStateError);
    await expectLater(
        journal.save(_publication(current,
            destination: _fileIdentity(), confirmed: true)),
        throwsStateError);
    expect((await journal.transfer(current.id))!.lifecycle,
        TransferLifecycle.verifying);
  });

  test('rename confirmation requires exact source identity and is immutable',
      () async {
    var current = await _advanceToPublishing(
        journal, await journal.create(_queued()),
        confirm: false);
    await expectLater(
        journal.complete(current, _installation(current)), throwsStateError);
    await expectLater(
        journal.save(_publication(current, confirmed: true)), throwsStateError);
    await expectLater(
        journal.save(_publication(current,
            destination: _fileIdentity(fileId: 'other'), confirmed: true)),
        throwsStateError);
    await expectLater(
        journal.save(_publication(current,
            destination: _fileIdentity(nanoseconds: 1), confirmed: true)),
        throwsStateError);
    current = await journal.save(
        _publication(current, destination: _fileIdentity(), confirmed: true));
    await expectLater(
        journal.save(_publication(current, destination: _fileIdentity())),
        throwsStateError);
    await expectLater(
        journal.save(_publication(current, method: 'copy')), throwsStateError);
    await expectLater(
        journal.complete(current, _installation(current, fileId: 'other')),
        throwsStateError);
    expect(await db.query('installed_artifacts'), isEmpty);
    expect((await journal.complete(current, _installation(current))).lifecycle,
        TransferLifecycle.completed);
  });

  test(
      'copy checkpoints retain source and destination objects until atomic completion',
      () async {
    var current = await _advanceToPublishing(
        journal, await journal.create(_queued()),
        confirm: false);
    current = await journal.save(_publication(current, method: 'copy'));
    final intent = current;
    current = await journal.save(_publication(current,
        method: 'copy',
        destination: _fileIdentity(fileId: 'copy', sizeBytes: 0)));
    current = await journal.save(_publication(current,
        method: 'copy',
        destination: _fileIdentity(fileId: 'copy', sizeBytes: 3)));
    expect(
        current.toJson()['publication']['destinationIdentity']['sizeBytes'], 3);
    await expectLater(
        journal.save(_publication(current,
            method: 'copy',
            destination:
                _fileIdentity(fileId: 'copy', sizeBytes: 3, nanoseconds: 1))),
        throwsStateError);
    await expectLater(
        journal.save(_publication(intent,
            method: 'copy',
            destination: _fileIdentity(fileId: 'copy', sizeBytes: 4))),
        throwsStateError);
    for (final destination in [
      _fileIdentity(fileId: 'other', sizeBytes: 4),
      _fileIdentity(fileId: 'copy', sizeBytes: 2),
      _fileIdentity(fileId: 'copy', sizeBytes: 6),
    ]) {
      await expectLater(
          journal.save(
              _publication(current, method: 'copy', destination: destination)),
          throwsStateError);
    }
    await expectLater(
        journal.save(_publication(current, method: 'copy')), throwsStateError);
    await expectLater(
        journal.save(_publication(current,
            method: 'rename',
            destination: _fileIdentity(fileId: 'copy', sizeBytes: 3))),
        throwsStateError);
    await expectLater(
        journal.save(_publication(current,
            method: 'copy',
            destination: _fileIdentity(fileId: 'copy', sizeBytes: 3),
            confirmed: true)),
        throwsStateError);
    current = await journal.save(_publication(current,
        method: 'copy',
        destination: _fileIdentity(fileId: 'copy'),
        confirmed: true));
    await expectLater(
        journal.save(_publication(current,
            method: 'copy',
            destination: _fileIdentity(fileId: 'copy', nanoseconds: 1),
            confirmed: true)),
        throwsStateError);
    final completed =
        await journal.complete(current, _installation(current, fileId: 'copy'));
    expect(completed.lifecycle, TransferLifecycle.completed);
    expect(completed.toJson()['stageIdentity'], _fileIdentity().toJson());
    expect(completed.toJson()['publication']['confirmed'], isTrue);
  });

  test(
      'resuming verification and publication requires matching durable evidence',
      () async {
    for (final state in [
      TransferLifecycle.paused,
      TransferLifecycle.failed,
      TransferLifecycle.awaitingAuthorization
    ]) {
      var current = await journal
          .create(_queued(id: state.name, relativePath: '${state.name}.chd'));
      current = await journal.save(current.copyWith(lifecycle: state));
      await expectLater(
          journal
              .save(current.copyWith(lifecycle: TransferLifecycle.verifying)),
          throwsStateError);
      await expectLater(
          journal
              .save(current.copyWith(lifecycle: TransferLifecycle.publishing)),
          throwsStateError);
      current = await journal
          .save(current.copyWith(lifecycle: TransferLifecycle.transferring));
      current = await journal.save(_stage(current, 5));
      current = await journal.save(current.copyWith(lifecycle: state));
      current = await journal
          .save(current.copyWith(lifecycle: TransferLifecycle.verifying));
      current = await journal.save(current.copyWith(verifiedChecksums: {
        'md5': '7cfdd07889b3295d6a550914ab35e068',
        'sha256': _fixtureSha256
      }));
      current = await journal.save(_publication(current));
      current = await journal.save(current.copyWith(lifecycle: state));
      final lateConfirmation = TransferRecord.fromJson({
        ..._publication(current, destination: _fileIdentity(), confirmed: true)
            .toJson(),
        'lifecycle': state.name,
      });
      await expectLater(journal.save(lateConfirmation), throwsStateError);
      await expectLater(
          journal.save(
              current.copyWith(lifecycle: TransferLifecycle.transferring)),
          throwsStateError);
      current = await journal
          .save(current.copyWith(lifecycle: TransferLifecycle.publishing));
      expect(current.toJson()['publication']['method'], 'rename');
    }
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
      _stage(
          transferring.copyWith(
            lifecycle: TransferLifecycle.paused,
          ),
          3),
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

  test(
      'owned durable offsets cannot decrease or reset without a reset protocol',
      () async {
    var current = await journal.create(_queued());
    current = await journal.save(
      current.copyWith(lifecycle: TransferLifecycle.transferring),
    );
    current = await journal.save(_stage(current, 4));

    await expectLater(
      journal.save(current.copyWith(durableOffset: 0)),
      throwsStateError,
    );
    await expectLater(journal.resetPartial(current), throwsStateError);

    current = await journal.save(
      current.copyWith(lifecycle: TransferLifecycle.paused),
    );
    await expectLater(journal.resetPartial(current), throwsStateError);
    expect((await journal.transfer(current.id))!.toJson(), current.toJson());
  });

  test(
      'failed partial reset is explicit and never an ordinary save side effect',
      () async {
    var current = await journal.create(_queued());
    current = await journal.save(
      current.copyWith(lifecycle: TransferLifecycle.transferring),
    );
    current = current.copyWith(
      durableOffset: 2,
      lifecycle: TransferLifecycle.failed,
      errorCode: 'truncated_response',
    );
    await _seedLegacy(db, current);

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
    current = await journal.save(_stage(current, 5));
    current = await journal.save(
      current.copyWith(lifecycle: TransferLifecycle.verifying),
    );
    await expectLater(journal.save(_publication(current)), throwsStateError);
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
    await expectLater(
        _advanceToPublishing(
          journal,
          await journal.create(_queued(
            providerChecksums: const {'crc32': '01020304'},
          )),
          verifiedChecksums: {
            'crc32': '01020304',
            'sha256': _fixtureSha256,
          },
        ),
        throwsStateError);
    expect(await db.query('installed_artifacts'), isEmpty);
    expect((await journal.transfer('transfer-1'))!.lifecycle,
        TransferLifecycle.verifying);
  });

  test('malformed recognized provider evidence is not silently ignored',
      () async {
    await expectLater(
        _advanceToPublishing(
            journal,
            await journal.create(_queued(providerChecksums: {
              'md5': '7cfdd07889b3295d6a550914ab35e068',
              'sha1': 'not-a-digest',
            }))),
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

  for (final cancellationCheck in [1, 2]) {
    test(
        'completion cancellation at transaction guard $cancellationCheck rolls back all writes',
        () async {
      final publishing =
          await _advanceToPublishing(journal, await journal.create(_queued()));
      var checks = 0;
      final cancellation = StateError('synthetic cancellation');
      await expectLater(
          journal.complete(publishing, _installation(publishing),
              checkCancellation: () {
            checks++;
            if (checks == cancellationCheck) throw cancellation;
          }),
          throwsA(same(cancellation)));
      expect(checks, cancellationCheck);
      expect((await journal.transfer(publishing.id))!.toJson(),
          publishing.toJson());
      expect(await db.query('installed_artifacts'), isEmpty);
      final owner = (await db.query('transfer_target_owners')).single;
      expect(owner['installation_id'], isNull);
      expect(owner['transfer_id'], publishing.id);
      final completed =
          await journal.complete(publishing, _installation(publishing));
      expect(completed.lifecycle, TransferLifecycle.completed);
    });
  }

  test('successful completion observes both transaction cancellation guards',
      () async {
    final publishing =
        await _advanceToPublishing(journal, await journal.create(_queued()));
    var checks = 0;
    final completed = await journal
        .complete(publishing, _installation(publishing), checkCancellation: () {
      checks++;
    });
    expect(checks, 2);
    expect(completed.lifecycle, TransferLifecycle.completed);
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
      _stage(
          current.copyWith(
            lifecycle: TransferLifecycle.paused,
          ),
          3),
    );
    final legacy = (await diskJournal
            .create(_queued(id: 'legacy-reopen', relativePath: 'legacy.chd')))
        .copyWith(durableOffset: 2, lifecycle: TransferLifecycle.failed);
    await _seedLegacy(diskDb, legacy);
    var publication = await _advanceToPublishing(
        diskJournal,
        await diskJournal.create(
            _queued(id: 'publication-reopen', relativePath: 'publication.chd')),
        confirm: false);
    publication =
        await diskJournal.save(_publication(publication, method: 'copy'));
    publication = await diskJournal.save(_publication(publication,
        method: 'copy',
        destination: _fileIdentity(fileId: 'copy', sizeBytes: 3)));
    await diskDb.close();

    diskDb = await databaseFactoryFfi.openDatabase(databasePath);
    addTearDown(diskDb.close);
    diskJournal = TransferJournal(Future.value(diskDb));
    final restored = await diskJournal.transfer(current.id);

    expect(restored!.toJson(), current.toJson());
    expect(restored.lifecycle, TransferLifecycle.paused);
    expect(restored.durableOffset, 3);
    expect(restored.artifact.version, 'version-1');
    final restoredLegacy = (await diskJournal.transfer(legacy.id))!;
    expect(restoredLegacy.durableOffset, 2);
    expect(restoredLegacy.toJson()['stageIdentity'], isNull);
    expect((await diskJournal.resetPartial(restoredLegacy)).durableOffset, 0);
    expect((await diskJournal.transfer(publication.id))!.toJson(),
        publication.toJson());
  });
}
