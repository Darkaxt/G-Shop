// Standalone debug-only device probe. Install with `adb install -r`, never
// uninstall the user's debug setup. Stop the process only at a visible ARMED
// state, then relaunch the same APK. No cloud or application database access.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/transfer_record.dart';
import 'package:g_shop/services/drive/drive_media.dart';
import 'package:g_shop/services/drive/drive_runtime.dart';
import 'package:g_shop/services/drive/drive_transfer_engine.dart';
import 'package:g_shop/services/installation_index.dart';
import 'package:g_shop/services/owned_storage.dart';
import 'package:g_shop/services/transfer_journal.dart';

final _status = ValueNotifier('Starting isolated process-death probe');
void _require(bool value, String code) {
  if (!value) throw StateError(code);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(home: Scaffold(body: Center(child:
      ValueListenableBuilder(valueListenable: _status,
          builder: (_, value, __) => Text(value,
              textDirection: TextDirection.ltr))))));
  unawaited(_probe().catchError((Object error) {
    // Bounded diagnostic, no account/config/payload information.
    _status.value = 'FAILED: ${error is StateError ? error.message : error.runtimeType}';
    debugPrint(_status.value);
  }));
}

Future<void> _probe() async {
  _require(kDebugMode && Platform.isAndroid, 'debug_android_only');
  _require((await PackageInfo.fromPlatform()).packageName ==
      'com.darkaxt.rshop.debug', 'isolated_package_only');
  const root = String.fromEnvironment('RSHOP_PROCESS_TEST_ROOT');
  // An explicit new direct child of the reviewed SD test parent, never Roms.
  _require(RegExp(r'^/storage/[A-Za-z0-9-]+/RShopProcessProof-[A-Za-z0-9_-]+$')
      .hasMatch(root), 'invalid_probe_root');
  final support = await getApplicationSupportDirectory();
  final dbPath = '${support.path}/${root.split('/').last}.sqlite';
  const storage = OwnedStorage();
  final first = !await File(dbPath).exists();
  if (first) {
    _require(!await Directory(root).exists(), 'preexisting_root');
    await Directory(root).create();
  }
  final db = await openDatabase(dbPath, version: 1, onCreate: (db, _) async {
    await TransferJournalSchema.install(db);
    await db.execute('CREATE TABLE probe_state (phase TEXT NOT NULL)');
    await db.insert('probe_state', {'phase': 'transfer'});
  });
  final journal = TransferJournal(Future.value(db));
  final plan = await storage.prepare(root);
  const id = 'process-proof';
  const name = 'synthetic-owned.bin';
  const removalId = 'process-proof-removal';
  final stage = plan.stagePath(id);
  final quarantine = plan.stagePath(removalId);
  final target = '$root/$name';
  final neighbor = '$root/synthetic-save.sav';
  const checkpointBytes = DriveMediaApi.maxChunkBytes;
  final bytes = Uint8List.fromList(List.generate(checkpointBytes + 131085, (i) => i % 251));
  final artifact = RemoteArtifact(id: RemoteArtifactId(providerId: 'drive',
      sourceId: 'synthetic', accountId: 'none', providerFileId: id),
      parentId: 'synthetic-folder', displayPath: name, displayName: name,
      sizeBytes: bytes.length, version: '1', canDownload: true,
      providerChecksums: {'md5': md5.convert(bytes).toString()});
  if (first) {
    _require(!await File(stage).exists() && !await File(quarantine).exists(),
        'preexisting_stage');
    await File(neighbor).writeAsBytes([9, 8, 7], flush: true);
    await journal.create(TransferRecord(id: id, artifact: artifact,
        destinationRoot: root, relativePath: name, stagePath: stage));
  }
  final phase = (await db.query('probe_state')).single['phase'];
  final requestedOffsets = <int>[];
  final engine = DriveTransferEngine(journal: journal, storage: storage,
      revalidate: (_, __) async {}, openMedia: (_, offset, __) async {
    requestedOffsets.add(offset);
    Stream<Uint8List> payload() async* {
      if (first) {
        yield Uint8List.sublistView(bytes, 0, checkpointBytes);
        // Event gate, not a deadline. Android process stop closes actual FDs.
        await Completer<void>().future;
      } else {
        for (var at = offset; at < bytes.length; at += 65536) {
          final end = at + 65536 < bytes.length ? at + 65536 : bytes.length;
          yield Uint8List.sublistView(bytes, at, end);
        }
      }
    }
    return DriveMediaResponse(bytes: payload(), offset: offset,
        length: bytes.length - offset, total: bytes.length);
  });
  final index = InstallationIndex(journal, storage: storage);
  if (phase == 'transfer') {
    final completed = await engine.start(id, onCheckpoint: (record) {
      if (first && record.durableOffset == checkpointBytes) {
        _status.value = 'ARMED TRANSFER: durable $checkpointBytes; stop and relaunch';
        debugPrint('PROCESS_PROOF ARMED_TRANSFER');
      }
    }).result;
    _require(completed.lifecycle == TransferLifecycle.completed,
        'transfer_${completed.errorCode}');
    _require(requestedOffsets.length == 1 && requestedOffsets.single == checkpointBytes,
        'resume_range_not_exact');
    _require(await index.resolveArtifact(artifact, root) == target,
        'installation_not_ready');
    _require(listEquals(await File(target).readAsBytes(), bytes), 'wrong_payload');
    final manifest = (await journal.installationForTarget(
        destinationRoot: root, relativePath: name))!;
    await journal.beginRemoval(completed, manifest, id: removalId,
        quarantinePath: quarantine);
    await db.update('probe_state', {'phase': 'removal'});
    await storage.quarantine(destinationRoot: root, relativePath: name,
        stagePath: quarantine, expectedIdentity: manifest.fileIdentity);
    _require(!await File(target).exists() && await File(quarantine).exists(),
        'move_not_observed');
    _status.value = 'ARMED REMOVAL: moved; receipt absent; stop and relaunch';
    debugPrint('PROCESS_PROOF ARMED_REMOVAL');
    // Leave DB/session lifecycle to the real process stop, no graceful cleanup.
    return;
  }
  _require(phase == 'removal', 'unexpected_phase');
  _require((await journal.removal(removalId))!.phase.name == 'intent',
      'receipt_not_lost');
  final recovered = await DriveRuntime(journal: journal, storage: storage)
      .recoverPendingRemovals();
  _require(recovered.removed == 1 && recovered.pending == 0 &&
      recovered.issues.isEmpty, 'removal_not_recovered');
  _require(!await File(target).exists() && !await File(quarantine).exists(),
      'removal_incomplete');
  _require(listEquals(await File(neighbor).readAsBytes(), [9, 8, 7]),
      'neighbor_changed');
  await journal.create(TransferRecord(id: id, artifact: artifact,
      destinationRoot: root, relativePath: name, stagePath: stage));
  _require((await engine.start(id).result).lifecycle == TransferLifecycle.completed,
      'reinstall_failed');
  _require(requestedOffsets.length == 1 && requestedOffsets.single == 0,
      'reinstall_not_fresh');
  _require(listEquals(await File(target).readAsBytes(), bytes), 'reinstall_bytes');
  _require(listEquals(await File(neighbor).readAsBytes(), [9, 8, 7]),
      'neighbor_changed_after_reinstall');
  await db.close();
  // Exact reviewed synthetic paths only, never recursive or suffix scans.
  for (final path in [target, neighbor, stage, quarantine, dbPath,
      '$dbPath-journal', '$dbPath-wal', '$dbPath-shm']) {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
  await Directory(root).delete();
  _status.value = 'PASSED: real transfer/removal process stops, exact resume, reinstall, save preserved';
  debugPrint('PROCESS_PROOF PASSED');
}
