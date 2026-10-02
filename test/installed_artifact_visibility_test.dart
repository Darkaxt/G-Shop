import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/installation_index.dart';
import 'package:retro_eshop/services/installation_paths.dart';
import 'package:retro_eshop/services/owned_storage.dart';
import 'package:retro_eshop/features/game_detail/game_detail_controller.dart';
import 'package:retro_eshop/services/download_queue_manager.dart';
import 'package:retro_eshop/services/rom_manager.dart';
import 'package:retro_eshop/services/transfer_journal.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late TransferJournal journal;
  late Directory root;
  late _Storage storage;
  late InstallationIndex index;
  final system = SystemModel.supportedSystems.firstWhere((s) => s.id == 'psx');
  const game =
      GameItem(filename: 'Fixture.chd', displayName: 'Fixture', url: '');

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await TransferJournalSchema.install(db);
    DatabaseService.testDatabase = db;
    journal = TransferJournal(Future.value(db));
    storage = _Storage();
    index = InstallationIndex(journal, storage: storage);
    root = Directory.systemTemp.createTempSync('installation-visibility-');
  });
  tearDown(() async {
    DatabaseService.resetForTesting();
    await db.close();
    root.deleteSync(recursive: true);
  });

  Future<TransferRecord> publication() async {
    final artifact = RemoteArtifact(
      id: RemoteArtifactId(
          providerId: 'drive',
          sourceId: 'source',
          accountId: 'account',
          providerFileId: 'file'),
      parentId: 'folder',
      displayPath: 'Fixture.chd',
      displayName: 'Fixture.chd',
      sizeBytes: 5,
      modifiedAt: DateTime.utc(2026, 9, 9),
      version: 'v1',
      providerChecksums: const {'md5': '7cfdd07889b3295d6a550914ab35e068'},
      canDownload: true,
    );
    var record = await journal.create(TransferRecord(
        id: 'transfer',
        artifact: artifact,
        destinationRoot: root.path,
        relativePath: game.filename,
        stagePath: p.join(root.path, 'private', 'stage')));
    final identity = NativeFileIdentity(
        volumeId: 'volume',
        fileId: 'inode',
        sizeBytes: 5,
        modifiedAt: DateTime.utc(2026, 9, 9));
    record = await journal.save(record.copyWith(
        lifecycle: TransferLifecycle.transferring,
        durableOffset: 5,
        stageIdentity: identity));
    record = await journal.save(record.copyWith(
        lifecycle: TransferLifecycle.verifying,
        verifiedChecksums: const {
          'md5': '7cfdd07889b3295d6a550914ab35e068',
          'sha256':
              '74f81fe167d99b4cb41d6d0ccda82278caee9f3e2f25d5e5a3936ff3dcec60d0'
        }));
    return journal.save(TransferRecord.fromJson({
      ...record.toJson(),
      'lifecycle': 'publishing',
      'publication': {
        'method': 'copy',
        'sourceIdentity': identity.toJson(),
        'confirmed': false
      },
    }));
  }

  test('public copy before its first receipt is not locally discoverable',
      () async {
    await publication();
    File(p.join(root.path, game.filename)).writeAsBytesSync([1, 2]);
    expect(await RomManager.scanLocalGames(system, root.path), isEmpty);
    expect(await RomManager.scanLocalGamesIsolate(system, root.path), isEmpty);
  });

  test('paused and failed publication cannot be launched or shared as legacy',
      () async {
    var record = await publication();
    File(p.join(root.path, game.filename)).writeAsBytesSync([1, 2]);
    for (final state in [TransferLifecycle.paused, TransferLifecycle.failed]) {
      record = await journal.save(record.copyWith(lifecycle: state));
      expect(await RomManager.resolveInstalledPath(game, system, root.path),
          isNull);
      expect(
          await RomManager.resolveSharePath(game, system, root.path), isNull);
      expect(await RomManager().exists(game, system, root.path), isFalse);
    }
  });

  test('a legacy row cannot delete a publication or its containing directory',
      () async {
    await publication();
    final file = File(p.join(root.path, game.filename))
      ..writeAsBytesSync([1, 2]);
    await expectLater(
        RomManager().delete(game, system, root.path), throwsStateError);
    expect(file.readAsBytesSync(), [1, 2]);
    final parent = root.parent.path;
    final directoryGame = GameItem(
        filename: p.basename(root.path), displayName: 'Folder', url: '');
    await expectLater(
        RomManager().delete(directoryGame, system, parent), throwsStateError);
    expect(file.existsSync(), isTrue);
  });

  test('unmanaged neighboring ROM remains discoverable and playable', () async {
    await publication();
    File(p.join(root.path, game.filename)).writeAsBytesSync([1]);
    final other = File(p.join(root.path, 'Other.chd'))..writeAsBytesSync([9]);
    expect(
        (await RomManager.scanLocalGames(system, root.path))
            .map((g) => g.filename),
        ['Other.chd']);
    final path = await RomManager.resolveInstalledPath(
        const GameItem(filename: 'Other.chd', displayName: 'Other', url: ''),
        system,
        root.path);
    expect(p.equals(path!, other.path), isTrue);
  });

  Future<TransferRecord> confirmed() async {
    var record = await publication();
    final identity = NativeFileIdentity(
        volumeId: 'volume',
        fileId: 'destination',
        sizeBytes: 5,
        modifiedAt: DateTime.utc(2026, 9, 9));
    storage.identity = identity;
    record = await journal.save(TransferRecord.fromJson({
      ...record.toJson(),
      'publication': {
        ...record.publication!.toJson(),
        'destinationIdentity': identity.toJson(),
        'confirmed': true
      },
    }));
    File(p.join(root.path, game.filename)).writeAsBytesSync([1, 2, 3, 4, 5]);
    return record;
  }

  Future<TransferRecord> complete() async {
    final record = await confirmed();
    return journal.complete(
        record,
        InstalledArtifact(
            id: 'installation',
            transferId: record.id,
            artifact: record.artifact,
            destinationRoot: record.destinationRoot,
            relativePath: record.relativePath,
            sizeBytes: 5,
            verifiedChecksums: record.verifiedChecksums,
            fileIdentity: storage.identity!));
  }

  test('owned removal preview resolves only the reviewed exact artifact and root', () async {
    var record = await complete();
    record = await journal.stageRetirementResult(record);
    final exact = game.copyWith(remoteArtifact: record.artifact);
    final manager = RomManager(installations: index);
    final preview = await manager.previewOwnedRemoval(exact, root.path);
    expect(preview.transferId, record.id);
    expect(preview.relativePath, 'Fixture.chd');
    expect(preview.sizeBytes, 5);
    storage.crossMount = true;
    await expectLater(manager.previewOwnedRemoval(exact, root.path), throwsA(
        isA<OwnedStorageException>().having((e) => e.code, 'code', 'cross_volume')));
    expect(await journal.hasPendingRemoval(record.id), isFalse);
    expect(await index.resolveArtifact(record.artifact, root.path), isNotNull);
    storage.crossMount = false;
    await expectLater(manager.previewOwnedRemoval(game, root.path), throwsStateError);
    final other = RemoteArtifact.fromJson({...record.artifact.toJson(),
      'id': {...record.artifact.id.toJson(), 'providerFileId': 'other'}});
    await expectLater(manager.previewOwnedRemoval(game.copyWith(remoteArtifact: other), root.path),
        throwsA(isA<OwnedStorageException>()));
    final intent = await journal.beginRemoval(record, preview,
        id: 'preview-removal', quarantinePath: '/private/preview-removal.partial');
    expect(intent.installation.id, preview.id);
    expect(await index.resolveArtifact(record.artifact, root.path), isNull);
    expect((await index.scan(root.path)).protects(p.join(root.path, game.filename)), isTrue);
    await expectLater(manager.previewOwnedRemoval(exact, root.path), throwsA(isA<OwnedStorageException>()));
  });

  test('committed local discovery retains identity through root case aliases',
      () async {
    final record = await complete();
    final alias = root.path.toUpperCase();
    if (!Directory(alias).existsSync() ||
        !FileSystemEntity.identicalSync(root.path, alias)) {
      return;
    }
    final games =
        await RomManager.scanLocalGames(system, alias, installations: index);
    expect(games, hasLength(1));
    expect(games.single.remoteArtifact?.id.key, record.artifact.id.key);
  });

  test('confirmed publication is still hidden until installation commit',
      () async {
    final record = await confirmed();
    final snapshot = await index.scan(root.path);
    expect(snapshot.installed, isEmpty);
    expect(snapshot.allowsLegacy(p.join(root.path, game.filename)), isFalse);
    expect(snapshot.resolve(record.artifact), isNull);
    expect(storage.calls, 0);
  });

  test('committed installation is exact, offline and survives source rename',
      () async {
    final record = await complete();
    final renamed = RemoteArtifact.fromJson({
      ...record.artifact.toJson(),
      'displayName': 'Renamed.chd',
      'displayPath': 'other/Renamed.chd',
      'parentId': 'other'
    });
    final snapshot = await index.scan(root.path);
    expect(snapshot.resolve(renamed), p.join(root.path, game.filename));
    expect(snapshot.allowsLegacy(p.join(root.path, game.filename)), isFalse);
    final games = await RomManager.scanLocalGamesIsolate(system, root.path,
        installations: index);
    expect(games.single.remoteArtifact!.id.key, record.artifact.id.key);
    final remote = game.copyWith(remoteArtifact: renamed);
    expect(
        await RomManager.resolveInstalledPath(remote, system, root.path,
            installations: index),
        p.join(root.path, game.filename));
    expect(
        (await RomManager.resolveSharePath(remote, system, root.path,
                installations: index))!
            .isDirectory,
        false);
    expect(
        await RomManager.resolveInstalledPath(game, system, root.path,
            installations: index),
        isNull);
    await expectLater(
        RomManager(installations: index).delete(remote, system, root.path),
        throwsStateError);
    final controller = GameDetailController(
        game: remote,
        variants: [remote, game],
        system: system,
        targetFolder: root.path,
        romManager: RomManager(installations: index),
        queueManager: _UnusedQueue());
    await controller.checkInstallationStatus();
    expect(controller.state.installedStatus, {0: true, 1: false});
    controller.dispose();
  });

  test(
      'same filename with another account, source, ID, version or digest is not installed',
      () async {
    final record = await complete();
    final snapshot = await index.scan(root.path);
    for (final field in ['accountId', 'sourceId', 'providerFileId']) {
      final changed = RemoteArtifact.fromJson({
        ...record.artifact.toJson(),
        'id': {...record.artifact.id.toJson(), field: 'different'}
      });
      expect(snapshot.resolve(changed), isNull, reason: field);
    }
    for (final change in [
      {'version': 'v2'},
      {'sizeBytes': 6},
      {
        'providerChecksums': {'md5': '11111111111111111111111111111111'}
      }
    ]) {
      expect(
          snapshot.resolve(RemoteArtifact.fromJson(
              {...record.artifact.toJson(), ...change})),
          isNull);
    }
  });

  test(
      'external replacement, missing file and storage errors never become legacy games',
      () async {
    await complete();
    final original = storage.identity!;
    for (final identity in [
      NativeFileIdentity(
          volumeId: original.volumeId,
          fileId: 'replacement',
          sizeBytes: 5,
          modifiedAt: original.modifiedAt),
      null,
    ]) {
      storage.identity = identity;
      expect((await index.scan(root.path)).installed, isEmpty);
      expect(
          await RomManager.scanLocalGames(system, root.path,
              installations: index),
          isEmpty);
    }
    storage.error = const OwnedStorageException('access_denied');
    expect((await index.scan(root.path)).installed, isEmpty);
  });

  test('normalized and containing roots cannot expose an unfinished member',
      () async {
    await publication();
    File(p.join(root.path, game.filename)).writeAsBytesSync([1]);
    expect(
        (await index.scan('${root.path}${p.separator}.'))
            .allowsLegacy(p.join(root.path, game.filename)),
        false);
    final parent = await index.scan(root.parent.path);
    expect(parent.allowsLegacy(root.path), false);
    expect(
        await RomManager.resolveSharePath(
            GameItem(
                filename: p.basename(root.path),
                displayName: 'Folder',
                url: ''),
            system,
            root.parent.path),
        isNull);
  });

  test('a queued reservation is not an installed owner or visibility blacklist',
      () async {
    final record = await publication();
    // Use a distinct legitimate pristine reservation, not a publication reset.
    final queued = TransferRecord(
        id: 'queued',
        artifact: record.artifact,
        destinationRoot: root.path,
        relativePath: 'Existing.chd',
        stagePath: p.join(root.path, 'stage-2'));
    await journal.create(queued);
    final snapshot = await index.scan(root.path);
    expect(snapshot.allowsLegacy(p.join(root.path, 'Existing.chd')), true);
    expect(snapshot.resolve(record.artifact), isNull);
  });

  test('ownership query pages past 128 without losing or repeating targets',
      () async {
    final record = await publication();
    for (var i = 0; i < 130; i++) {
      await journal.create(TransferRecord(
          id: 'queued-$i',
          artifact: record.artifact,
          destinationRoot: root.path,
          relativePath: 'Existing-$i.chd',
          stagePath: p.join(root.path, 'stage-$i')));
    }
    final rows = await journal.targetsInRoot(root.path).toList();
    expect(rows, hasLength(131));
    expect(rows.map((r) => r.transfer.id).toSet(), hasLength(131));
    final snapshot = await index.scan(root.path);
    expect(snapshot.protects(p.join(root.path, 'Existing-129.chd')), true);
    expect(snapshot.allowsLegacy(p.join(root.path, 'Existing-129.chd')), true);
    expect(storage.calls, 0);
  });

  test('a missing committed manifest cannot fall back to file existence',
      () async {
    await complete();
    await db.delete('installed_artifacts');
    expect((await index.scan(root.path)).installed, isEmpty);
    expect(
        await RomManager.scanLocalGames(system, root.path,
            installations: index),
        isEmpty);
  });

  test('a root symlink cannot bypass the publication exclusion', () async {
    await publication();
    File(p.join(root.path, game.filename)).writeAsBytesSync([1]);
    final aliases = Directory.systemTemp.createTempSync('installation-alias-');
    addTearDown(() => aliases.deleteSync(recursive: true));
    final link = Link(p.join(aliases.path, 'alias'));
    try {
      link.createSync(root.path);
    } on FileSystemException {
      markTestSkipped('Host does not permit symlink creation');
      return;
    }
    expect(await RomManager.scanLocalGames(system, link.path), isEmpty);
    expect(
        await RomManager.resolveInstalledPath(game, system, link.path), isNull);
    await expectLater(
        RomManager().delete(game, system, link.path), throwsStateError);
    expect(File(p.join(root.path, game.filename)).readAsBytesSync(), [1]);
  });

  test('case aliases cannot bypass publication visibility or removal guards',
      () async {
    await publication();
    final file = File(p.join(root.path, game.filename))..writeAsBytesSync([1]);
    final alias = File(p.join(root.path, 'fixture.chd'));
    if (!alias.existsSync()) {
      // A case-sensitive volume must leave a genuinely distinct file usable.
      alias.writeAsBytesSync([9]);
      final snapshot = await index.scan(root.path);
      expect(snapshot.allowsLegacy(alias.path), true);
      expect(snapshot.protects(alias.path), false);
      return;
    }
    final snapshot = await index.scan(root.path);
    expect(snapshot.allowsLegacy(alias.path), false);
    expect(snapshot.protects(alias.path), true);
    final aliasGame = const GameItem(
        filename: 'fixture.chd', displayName: 'Fixture', url: '');
    expect(await RomManager.resolveInstalledPath(aliasGame, system, root.path),
        isNull);
    await expectLater(
        RomManager().delete(aliasGame, system, root.path), throwsStateError);
    expect(file.readAsBytesSync(), [1]);
  });

  test(
      'folder fallback cannot use a sibling while its managed member is pending',
      () async {
    final record = await publication();
    final child = Directory(p.join(root.path, 'Bundle'))..createSync();
    // Publish-intent fixture in a nested root, before its public file exists.
    var nested = await journal.create(TransferRecord(
        id: 'nested',
        artifact: record.artifact,
        destinationRoot: child.path,
        relativePath: 'Pending.chd',
        stagePath: p.join(root.path, 'private-stage')));
    nested = await journal.save(nested.copyWith(
        lifecycle: TransferLifecycle.transferring,
        durableOffset: 5,
        stageIdentity: record.stageIdentity));
    nested = await journal.save(nested.copyWith(
        lifecycle: TransferLifecycle.verifying,
        verifiedChecksums: record.verifiedChecksums));
    await journal.save(nested.copyWith(
        lifecycle: TransferLifecycle.publishing,
        publication: record.publication));
    File(p.join(child.path, 'Valid.chd')).writeAsBytesSync([9]);
    const folder = GameItem(filename: 'Bundle', displayName: 'Bundle', url: '');
    expect(await RomManager.resolveInstalledPath(folder, system, root.path),
        isNull);
    expect(await RomManager().checkMultipleExists([folder], system, root.path),
        {0: false});
  });

  test('new child reservation waits for a legacy folder removal to finish',
      () async {
    final record = await publication();
    final folder = Directory(p.join(root.path, 'Unmanaged'))..createSync();
    File(p.join(folder.path, 'Old.chd')).writeAsBytesSync([9]);
    final gate = _PausingIndex(journal);
    final removal = RomManager(installations: gate).delete(
        const GameItem(filename: 'Unmanaged', displayName: 'Folder', url: ''),
        system,
        root.path);
    await gate.entered.future;
    var reserved = false;
    final reservation = journal
        .create(TransferRecord(
            id: 'new-child',
            artifact: record.artifact,
            destinationRoot: folder.path,
            relativePath: 'New.chd',
            stagePath: p.join(root.path, 'private-new')))
        .then((value) {
      reserved = true;
      return value;
    });
    // Independent scopes can progress while the overlapping reservation waits.
    await InstallationMutations.run('${root.path}-unrelated', () async {});
    expect(reserved, false);
    gate.resume.complete();
    await removal;
    expect(folder.existsSync(), false);
    expect((await reservation).id, 'new-child');
    expect(reserved, true);
  });

  test('failed mutation releases its scope for subsequent work', () async {
    await expectLater(
        InstallationMutations.run(
            root.path, () async => throw StateError('fixture')),
        throwsStateError);
    expect(await InstallationMutations.run(root.path, () async => 42), 42);
  });

  test('a single lookup never native-inspects unrelated installations',
      () async {
    final record = await complete();
    final other = RemoteArtifact.fromJson({
      ...record.artifact.toJson(),
      'id': {...record.artifact.id.toJson(), 'providerFileId': 'other'}
    });
    expect(
        await RomManager.resolveInstalledPath(
            game.copyWith(remoteArtifact: other), system, root.path,
            installations: index),
        isNull);
    expect(storage.calls, 0);
    File(p.join(root.path, 'Neighbor.chd')).writeAsBytesSync([9]);
    expect(
        await RomManager.resolveInstalledPath(
            const GameItem(
                filename: 'Neighbor.chd', displayName: 'Neighbor', url: ''),
            system,
            root.path,
            installations: index),
        isNotNull);
    expect(storage.calls, 0);
    expect(
        await RomManager.resolveInstalledPath(
            game.copyWith(remoteArtifact: record.artifact), system, root.path,
            installations: index),
        isNotNull);
    expect(storage.calls, 1);
  });
}

class _UnusedQueue implements DownloadQueueManager {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected queue work');
}

class _PausingIndex extends InstallationIndex {
  final entered = Completer<void>();
  final resume = Completer<void>();
  _PausingIndex(super.journal);
  @override
  Future<InstallationSnapshot> scan(String root,
      {bool verifyInstalled = true}) async {
    final snapshot = await super.scan(root, verifyInstalled: verifyInstalled);
    entered.complete();
    await resume.future;
    return snapshot;
  }
}

class _Storage extends OwnedStorage {
  bool crossMount = false;
  @override
  Future<OwnedStoragePlan> prepare(String destinationRoot) async => OwnedStoragePlan(
      destinationRoot: destinationRoot, stageRoot: '/private',
      destinationVolume: 'volume', stageVolume: 'volume',
      destinationMount: 'mount', stageMount: crossMount ? 'other' : 'mount',
      destinationFreeBytes: 1000, stageFreeBytes: 1000);
  NativeFileIdentity? identity;
  OwnedStorageException? error;
  int calls = 0;
  @override
  Future<NativeFileIdentity?> inspect(
      {required String destinationRoot,
      required String relativePath,
      required String stagePath,
      bool published = false}) async {
    expect(published, true);
    calls++;
    if (error != null) throw error!;
    return identity;
  }
}
