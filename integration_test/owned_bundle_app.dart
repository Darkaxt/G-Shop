import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:g_shop/models/config/drive_source_config.dart';
import 'package:g_shop/models/config/provider_config.dart';
import 'package:g_shop/models/download_item.dart';
import 'package:g_shop/models/game_item.dart';
import 'package:g_shop/models/system_model.dart';
import 'package:g_shop/models/transfer_record.dart';
import 'package:g_shop/services/drive/drive_api.dart';
import 'package:g_shop/services/drive/drive_authorization.dart';
import 'package:g_shop/services/drive/drive_catalogue.dart';
import 'package:g_shop/services/drive/drive_runtime.dart';
import 'package:g_shop/services/drive/drive_media.dart';
import 'package:g_shop/services/download_queue_manager.dart';
import 'package:g_shop/services/installation_index.dart';
import 'package:g_shop/services/owned_installation_removal.dart';
import 'package:g_shop/services/owned_storage.dart';
import 'package:g_shop/services/storage_service.dart';
import 'package:g_shop/services/transfer_journal.dart';
import 'package:g_shop/utils/rom_share_helper.dart';
import 'support/drive_bundle_protocol_fixture.dart';

void require(bool condition, String code) {
  if (!condition) throw StateError(code);
}

class _Journal extends TransferJournal {
  final Future<void> Function(String) gate;
  final String initial;
  _Journal(super.database, this.gate, this.initial);
  @override
  Future<TransferRecord> complete(
      TransferRecord record, InstalledArtifact installation,
      {void Function()? checkCancellation}) async {
    final result = await super
        .complete(record, installation, checkCancellation: checkCancellation);
    if (initial == 'created' && record.artifact.id.providerFileId == 'disc1') {
      await gate('disc_committed');
    }
    return result;
  }
}

class _Storage extends OwnedStorage {
  final Future<void> Function(String) gate;
  final String initial;
  _Storage(this.gate, this.initial);
  @override
  Future<NativeFileIdentity> quarantine(
      {required String destinationRoot,
      required String relativePath,
      required String stagePath,
      required NativeFileIdentity expectedIdentity}) async {
    final moved = await super.quarantine(
        destinationRoot: destinationRoot,
        relativePath: relativePath,
        stagePath: stagePath,
        expectedIdentity: expectedIdentity);
    if (initial == 'disc_committed' && relativePath.endsWith('/track.bin')) {
      await gate('member_quarantined');
    }
    return moved;
  }
}

class _QueueStorage extends StorageService {
  final Database db;
  String? saved;
  _QueueStorage(this.db, this.saved);
  @override
  int getMaxConcurrentDownloads() => 1;
  @override
  String? getDownloadQueue() => saved;
  @override
  Future<void> setDownloadQueue(String value) async {
    await db.update('proof_state', {'queue_json': value});
    saved = value;
  }

  @override
  Future<void> clearDownloadQueue() async {
    await db.update('proof_state', {'queue_json': null});
    saved = null;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
      const MaterialApp(home: Scaffold(body: Text('Isolated bundle proof'))));
  unawaited(probe().catchError((Object error, StackTrace stack) {
    debugPrint(
        'BUNDLE_PROOF FAILED ${error is OwnedStorageException ? error.code : error}');
    debugPrintStack(stackTrace: stack);
  }));
}

Future<void> probe() async {
  require(
      kDebugMode &&
          Platform.isAndroid &&
          (await PackageInfo.fromPlatform()).packageName ==
              'com.darkaxt.rshop.debug',
      'debug_android_only');
  const root = String.fromEnvironment('RSHOP_BUNDLE_TEST_ROOT');
  require(
      RegExp(r'^/storage/[A-Za-z0-9-]+/RShopBundleProof-[A-Za-z0-9_-]+$')
          .hasMatch(root),
      'isolated_root_required');
  final dbPath =
      '${(await getApplicationSupportDirectory()).path}/${root.split('/').last}.sqlite';
  final exists = await File(dbPath).exists();
  require(await Directory(root).exists() == exists, 'unexpected_fixture_state');
  if (!exists) await Directory(root).create();
  final db = await openDatabase(dbPath, version: 1, onCreate: (db, _) async {
    await TransferJournalSchema.install(db);
    await DriveCatalogueSchema.install(db);
    await db.execute(
        'CREATE TABLE proof_state (gate TEXT NOT NULL, queue_json TEXT)');
    await db.insert('proof_state', {'gate': 'created'});
  });
  final state = (await db.query('proof_state')).single;
  final initial = state['gate'] as String;
  require(['created', 'disc_committed', 'member_quarantined'].contains(initial),
      'invalid_gate');
  Future<void> gate(String label) async {
    await db.update('proof_state', {'gate': label});
    debugPrint('BUNDLE_PROOF GATE $label');
    await Completer<void>()
        .future; // Host force-stop is the explicit gate event.
  }

  final journal = _Journal(Future.value(db), gate, initial);
  final storage = _Storage(gate, initial);
  final index = InstallationIndex(journal, storage: storage);
  final protocol = BundleFixtureTransport();
  final auth = DriveAuthorization(BundleFixtureAccount());
  final catalogue = DriveCatalogue(Future.value(db));
  final api = DriveApi(
      authorization: auth, accountId: 'account', httpClientAdapter: protocol);
  final runtime = DriveRuntime(
      catalogue: catalogue,
      journal: journal,
      storage: storage,
      createAuthorization: (_) => auth,
      createApi: (_, __) => api,
      createMediaApi: (_, __) => DriveMediaApi(
          authorization: auth,
          accountId: 'account',
          httpClientAdapter: protocol));
  const config = ProviderConfig(
      type: ProviderType.drive,
      priority: 1,
      sourceId: 'source',
      path: 'root-id',
      drive: DriveSourceConfig(
          accountId: 'account',
          rootFolderId: 'root-id',
          serverClientId: 'unused-public-client'));
  final artifact = protocol.nodes['playlist']!.artifact(
      sourceId: 'source', accountId: 'account', displayPath: 'game.m3u');
  final game = GameItem(
      filename: 'game.m3u',
      displayName: 'Synthetic bundle',
      url: 'drive-artifact:fixture',
      providerConfig: config,
      remoteArtifact: artifact);
  final system = SystemModel.supportedSystems.singleWhere((s) => s.id == 'psx');
  if (initial == 'created') {
    await catalogue.refresh(
        sourceId: 'source',
        accountId: 'account',
        rootFolderId: 'root-id',
        api: api);
  }
  TransferRecord? rootTransfer;
  await for (final row
      in journal.targetsInRoot(root, artifactKey: artifact.id.key)) {
    if (row.transfer.bundleOwner == null) rootTransfer = row.transfer;
  }
  final removalStarted = rootTransfer != null &&
      (await db.query('owned_removals',
              where: 'transfer_id = ?', whereArgs: [rootTransfer.id]))
          .isNotEmpty;
  if (initial != 'member_quarantined' && !removalStarted) {
    require(await index.resolveArtifact(artifact, root) == null,
        'partial_bundle_marked_ready');
    final queue = DownloadQueueManager(
        _QueueStorage(db, state['queue_json'] as String?),
        driveRuntime: runtime);
    final completion = Completer<DownloadItem>();
    queue.onItemCompleted = completion.complete;
    queue.addListener(() {
      final failed = queue.state.queue
          .where((item) => item.status == DownloadStatus.error);
      if (failed.isNotEmpty && !completion.isCompleted) {
        completion.completeError(
            StateError(failed.first.error ?? 'unknown_queue_error'));
      }
    });
    if (initial == 'created') {
      queue.addToQueue(game, system, root);
    } else {
      queue.restoreQueue([system]);
      final item = queue.state.queue.single;
      require(
          item.status == DownloadStatus.paused &&
              item.transferId == rootTransfer!.id,
          'queue_restore_wrong');
      queue.retryDownload(item.id);
    }
    final completed = await completion.future;
    await queue.close();
    queue.dispose();
    rootTransfer = (await journal.transfer(completed.transferId!))!;
    require(
        completed.receivedBytes ==
            protocol.payloads.values
                .fold<int>(0, (n, bytes) => n + bytes.length),
        'queue_bytes_wrong');
    require(
        !protocol.media.contains('disc1'), 'completed_disc_downloaded_again');
    require(
        protocol.media.toString() == ['track', 'cue', 'playlist'].toString(),
        'wrong_remaining_requests');
  }
  require(rootTransfer != null, 'missing_root_transfer');
  final record = rootTransfer!;
  final manifest = (await journal.installationForTarget(
      destinationRoot: root, relativePath: record.relativePath))!;
  final namespace = record.relativePath.split('/').first;
  final save = File('$root/$namespace/user-save.sav');
  final saveBytes = utf8.encode('bundle neighbor save; never a ROM member');
  if (initial == 'disc_committed' && !removalStarted) {
    require(manifest.dependencies.length == 3 && record.stageRetired,
        'bundle_incomplete');
    await index.requireInstallation(record, manifest);
    for (final member in [manifest, ...manifest.dependencies]) {
      final expected = protocol.payloads[member.artifact.id.providerFileId]!;
      require(
          (await File('$root/${member.relativePath}').readAsBytes())
                  .toString() ==
              expected.toString(),
          'member_bytes_wrong');
    }
    final disc = File('$root/${manifest.dependencies.first.relativePath}');
    final missing = await disc.rename('${disc.path}.missing-proof');
    require(await index.resolveArtifact(artifact, root) == null,
        'missing_disc_still_ready');
    await missing.rename(disc.path);
    await index.requireInstallation(record, manifest);
    require(!await save.exists(), 'unexpected_save_fixture');
    await save.writeAsBytes(saveBytes, flush: true);
    final archiveFiles = await RomShareHelper.prepareShareFiles(
        game: game, system: system, targetFolder: root, installations: index);
    require(archiveFiles.length == 1, 'share_not_bundle');
    final archive = ZipDecoder()
        .decodeBytes(await File(archiveFiles.single.path).readAsBytes());
    require(
        archive.files
            .where((file) => file.isFile)
            .map((file) => file.name)
            .toSet()
            .containsAll([
          'game.m3u',
          'Disc 1.chd',
          'Disc 2/disc.cue',
          'Disc 2/track.bin'
        ]),
        'share_missing_member');
    require(
        archive.files.where((file) => file.isFile).length == 4 &&
            !archive.files.any((file) => file.name.endsWith('.sav')),
        'share_included_neighbor');
    await File(archiveFiles.single.path).delete();
    await OwnedInstallationRemoval(journal, storage: storage).remove(manifest);
  } else if (initial == 'member_quarantined' || removalStarted) {
    require(await index.resolveArtifact(artifact, root) == null,
        'removing_bundle_ready');
    final intent = (await db.query('owned_removals',
            where: 'transfer_id = ?', whereArgs: [record.id]))
        .single;
    await OwnedInstallationRemoval(journal, storage: storage)
        .recover(intent['removal_id'] as String);
  } else {
    throw StateError('first_process_should_have_stopped');
  }
  require(await db.query('installed_artifacts').then((rows) => rows.isEmpty),
      'installed_rows_remain');
  for (final member in [manifest, ...manifest.dependencies]) {
    require(!await File('$root/${member.relativePath}').exists(),
        'owned_member_remains');
  }
  require(sha256.convert(await save.readAsBytes()) == sha256.convert(saveBytes),
      'save_changed');
  await save.delete();
  await Directory('$root/$namespace/Disc 2').delete();
  await Directory('$root/$namespace').delete();
  await Directory(root).delete();
  await runtime.disconnect();
  await db.close();
  for (final path in [
    dbPath,
    '$dbPath-journal',
    '$dbPath-wal',
    '$dbPath-shm'
  ]) {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
  debugPrint(
      'BUNDLE_PROOF PASSED normal queue, process resume, missing-disc gate, exact share/removal/save');
}
