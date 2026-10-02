// Isolated debug-only SD proof. Synthetic payloads, separate SQLite/root, no
// accounts, network calls, normal database or existing ROMs. Actual am force-stop
// at each observed gate supplies process death; no sleep decides success.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:retro_eshop/models/config/drive_source_config.dart';
import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/services/drive/drive_media.dart';
import 'package:retro_eshop/services/drive/drive_runtime.dart';
import 'package:retro_eshop/services/drive/drive_transfer_engine.dart';
import 'package:retro_eshop/services/installation_index.dart';
import 'package:retro_eshop/services/owned_installation_removal.dart';
import 'package:retro_eshop/services/owned_storage.dart';
import 'package:retro_eshop/services/transfer_journal.dart';

void require(bool condition, String code) {
  if (!condition) throw StateError(code);
}

class _Journal extends TransferJournal {
  final Future<void> Function(String) gate;
  final String initialGate;
  _Journal(super.database, this.gate, this.initialGate);
  @override
  Future<TransferRecord> complete(
      TransferRecord record, InstalledArtifact installation,
      {void Function()? checkCancellation}) async {
    final committed = await super
        .complete(record, installation, checkCancellation: checkCancellation);
    if (record.artifact.version == '3' && initialGate != 'committed3') {
      await gate('committed3');
    }
    return committed;
  }
}

class _Storage extends OwnedStorage {
  final Future<void> Function(String) gate;
  final String initialGate;
  String? gatedOldPath;
  _Storage(this.gate, this.initialGate);
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
    if (relativePath == gatedOldPath && initialGate != 'quarantined4') {
      await gate('quarantined4');
    }
    return moved;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
      home: Scaffold(body: Text('Isolated replacement proof'))));
  unawaited(probe().catchError((Object error) {
    debugPrint(
        'REPLACEMENT_PROOF FAILED ${error is OwnedStorageException ? error.code : error is StateError ? error.message : error.runtimeType}');
  }));
}

Future<void> probe() async {
  require(
      kDebugMode &&
          Platform.isAndroid &&
          (await PackageInfo.fromPlatform()).packageName ==
              'com.darkaxt.rshop.debug',
      'debug_android_only');
  const root = String.fromEnvironment('RSHOP_REPLACEMENT_TEST_ROOT');
  require(
      RegExp(r'^/storage/[A-Za-z0-9-]+/RShopReplacementProof-[A-Za-z0-9_-]+$')
          .hasMatch(root),
      'isolated_root_required');
  final dbPath =
      '${(await getApplicationSupportDirectory()).path}/${root.split('/').last}.sqlite';
  final exists = await File(dbPath).exists();
  require(await Directory(root).exists() == exists, 'unexpected_fixture_state');
  if (!exists) await Directory(root).create();
  final db = await openDatabase(dbPath, version: 1, onCreate: (db, _) async {
    await TransferJournalSchema.install(db);
    await db.execute('CREATE TABLE proof_state (gate TEXT NOT NULL)');
    await db.insert('proof_state', {'gate': 'created'});
    await db.execute(
        'CREATE TABLE proof_history (version INTEGER PRIMARY KEY, transfer_id TEXT, stage_path TEXT, relative_path TEXT)');
  });
  final initial = (await db.query('proof_state')).single['gate'] as String;
  require(
      ['created', 'published2', 'committed3', 'quarantined4'].contains(initial),
      'invalid_fixture_gate');
  Future<void> gate(String label) async {
    await db.update('proof_state', {'gate': label});
    debugPrint('REPLACEMENT_PROOF GATE $label');
    await Completer<void>()
        .future; // Host force-stop is the explicit gate event.
  }

  final journal = _Journal(Future.value(db), gate, initial);
  final storage = _Storage(gate, initial);
  final runtime = DriveRuntime(journal: journal, storage: storage);
  final plan = await storage.prepare(root);
  require(plan.sameMountHint, 'supported_sd_quarantine_required');
  const config = ProviderConfig(
      type: ProviderType.drive,
      priority: 0,
      sourceId: 'synthetic',
      path: 'fixture',
      drive: DriveSourceConfig(
          accountId: 'none',
          rootFolderId: 'fixture',
          serverClientId: 'unused-public-client'));
  Uint8List payload(int version) =>
      Uint8List.fromList(List.generate(65549, (i) => (i + version * 13) % 251));
  RemoteArtifact artifact(int version) => RemoteArtifact(
      id: RemoteArtifactId(
          providerId: 'drive',
          sourceId: 'synthetic',
          accountId: 'none',
          providerFileId: 'replacement'),
      parentId: 'fixture',
      displayName: 'synthetic.gg',
      displayPath: 'synthetic.gg',
      sizeBytes: 65549,
      version: '$version',
      canDownload: true,
      providerChecksums: {'md5': md5.convert(payload(version)).toString()});
  final save = File('$root/neighbor.sav');
  final saveBytes =
      'Synthetic neighboring save: must survive every replacement.'.codeUnits;
  if (!exists) {
    await save.create(exclusive: true);
    await save.writeAsBytes(saveBytes, flush: true);
  }
  require((await save.readAsBytes()).toString() == saveBytes.toString(),
      'save_changed');
  String? activeId;
  final engine = DriveTransferEngine(
      journal: journal,
      storage: storage,
      revalidate: (source, _) async {
        if (source.version == '2' &&
            initial == 'created' &&
            activeId != null &&
            (await journal.transfer(activeId))?.publication?.confirmed ==
                true) {
          await gate('published2');
        }
      },
      openMedia: (source, offset, _) async {
        final data = payload(int.parse(source.version!));
        Stream<Uint8List> chunks() async* {
          for (var at = offset;
              at < data.length;
              at += OwnedStorage.maxChunkBytes) {
            final end = at + OwnedStorage.maxChunkBytes < data.length
                ? at + OwnedStorage.maxChunkBytes
                : data.length;
            yield Uint8List.sublistView(data, at, end);
          }
        }

        return DriveMediaResponse(
            bytes: chunks(),
            offset: offset,
            length: data.length - offset,
            total: data.length);
      });
  var first =
      switch (initial) { 'committed3' => 3, 'quarantined4' => 4, _ => 1 };
  if (initial == 'published2') first = 2;
  for (var version = first; version <= 4; version++) {
    final next = await runtime.reserveTransfer(
        config: config,
        artifact: artifact(version),
        destinationRoot: root,
        relativePath: 'synthetic.gg');
    activeId = next.id;
    final history = await db
        .query('proof_history', where: 'version = ?', whereArgs: [version]);
    if (history.isEmpty) {
      await db.insert('proof_history', {
        'version': version,
        'transfer_id': next.id,
        'relative_path': next.relativePath,
        'stage_path': next.stagePath
      });
    } else {
      require(
          history.single['transfer_id'] == next.id &&
              history.single['relative_path'] == next.relativePath,
          'changed_fixture_preserved');
    }
    if (version == 4) {
      storage.gatedOldPath = next.replacesInstallation?.relativePath;
    }
    final completed = await engine.start(next.id).result;
    require(completed.lifecycle == TransferLifecycle.completed,
        'transfer_${completed.errorCode}');
    require(
        await journal.replacementIssue(next.id) == null, 'retirement_pending');
    final installed = (await journal.installationForTarget(
        destinationRoot: root, relativePath: completed.relativePath))!;
    await InstallationIndex(journal, storage: storage)
        .requireInstallation(completed, installed);
    require(
        (await File('$root/${completed.relativePath}').readAsBytes())
                .toString() ==
            payload(version).toString(),
        'wrong_public_bytes');
    require((await save.readAsBytes()).toString() == saveBytes.toString(),
        'save_changed');
    if (next.replacesInstallation case final old?) {
      require(
          !await File('$root/${old.relativePath}').exists() &&
              await journal.transfer(old.transferId) == null &&
              await journal.replacementPhase(next.id) == 'retired',
          'old_owner_not_retired');
    }
    if (version == 4) {
      await OwnedInstallationRemoval(journal, storage: storage)
          .remove(installed);
    }
  }
  for (final row in await db.query('proof_history')) {
    require(
        !await File(row['stage_path'] as String).exists() &&
            !await File('$root/${row['relative_path']}').exists(),
        'fixture_files_remain');
  }
  await save.delete();
  await db.close();
  await Directory(root).delete();
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
      'REPLACEMENT_PROOF PASSED publication/commit/quarantine process-stop recovery');
}
