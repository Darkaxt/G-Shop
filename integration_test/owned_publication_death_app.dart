// Debug-only actual process-stop probe. No accounts, cloud, application DB or
// existing ROMs. Install -r, stop only at ARMED, relaunch the same APK, then
// restore the preserved normal APK. Each gate follows a real durable transition.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/transfer_record.dart';
import 'package:g_shop/services/drive/drive_media.dart';
import 'package:g_shop/services/drive/drive_transfer_engine.dart';
import 'package:g_shop/services/installation_index.dart';
import 'package:g_shop/services/owned_installation_removal.dart';
import 'package:g_shop/services/owned_storage.dart';
import 'package:g_shop/services/transfer_journal.dart';

final _status = ValueNotifier('Starting isolated publication probe');
const _boundaries = [
  'intent', 'copyProgress', 'finishReceipt', 'confirmed', 'committed',
  'createReceipt',
];

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
    _status.value = 'FAILED: ${error is StateError ? error.message : error.runtimeType}';
    debugPrint('PUBLICATION_PROOF ${_status.value}');
  }));
}

/// Intercepts only the receipt after the REAL native operation succeeded.
/// Production channel and filesystem code remain unmodified.
class _ReceiptChannel extends MethodChannel {
  final String boundary;
  final Future<void> Function() arm;
  const _ReceiptChannel(this.boundary, this.arm)
      : super('com.darkaxt.gshop/storage');

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    final result = await super.invokeMethod<T>(method, arguments);
    if ((boundary == 'createReceipt' && method == 'ownedCopyOpen') ||
        (boundary == 'finishReceipt' && method == 'ownedCopyFinish')) {
      await arm();
    }
    return result;
  }
}

class _GateJournal extends TransferJournal {
  final String boundary;
  final Future<void> Function() arm;
  _GateJournal(super.database, this.boundary, this.arm);

  @override
  Future<TransferRecord> save(TransferRecord record) async {
    final saved = await super.save(record);
    final publication = saved.publication;
    if ((boundary == 'intent' && publication?.method == PublicationMethod.rename) ||
        (boundary == 'copyProgress' && publication?.method == PublicationMethod.copy &&
            publication!.copiedOffset >= DriveMediaApi.maxChunkBytes && !publication.confirmed) ||
        (boundary == 'confirmed' && publication?.confirmed == true)) {
      await arm();
    }
    return saved;
  }

  @override
  Future<TransferRecord> complete(TransferRecord record,
      InstalledArtifact installation, {void Function()? checkCancellation}) async {
    final saved = await super.complete(record, installation,
        checkCancellation: checkCancellation);
    if (boundary == 'committed') await arm();
    return saved;
  }
}

Future<void> _probe() async {
  _require(kDebugMode && Platform.isAndroid, 'debug_android_only');
  _require((await PackageInfo.fromPlatform()).packageName ==
      'com.darkaxt.rshop.debug', 'isolated_package_only');
  const root = String.fromEnvironment('RSHOP_PUBLICATION_TEST_ROOT');
  _require(RegExp(r'^/storage/[A-Za-z0-9-]+/RShopPublicationProof-[A-Za-z0-9_-]+$')
      .hasMatch(root), 'invalid_probe_root');
  final support = await getApplicationSupportDirectory();
  final dbPath = '${support.path}/${root.split('/').last}.sqlite';
  final first = !await File(dbPath).exists();
  if (first) {
    _require(!await Directory(root).exists(), 'preexisting_root');
    await Directory(root).create();
  }
  final db = await openDatabase(dbPath, version: 1, onCreate: (db, _) async {
    await TransferJournalSchema.install(db);
    await db.execute('CREATE TABLE probe_state (boundary INTEGER NOT NULL, armed INTEGER NOT NULL)');
    await db.insert('probe_state', {'boundary': 0, 'armed': 0});
  });
  const native = OwnedStorage();
  final plan = await native.prepare(root);
  final neighbor = File('$root/synthetic-save.sav');
  if (first) await neighbor.writeAsBytes([9, 8, 7], flush: true);
  // Small bounded fixture; not the large-file resource acceptance test.
  final bytes = Uint8List.fromList(List.generate(
      DriveMediaApi.maxChunkBytes * 2 + 131085, (i) => i % 251));
  var position = (await db.query('probe_state')).single['boundary'] as int;
  while (position < _boundaries.length) {
    final boundary = _boundaries[position];
    final armed = (await db.query('probe_state')).single['armed'] == 1;
    Future<void> arm() async {
      await db.update('probe_state', {'armed': 1});
      _status.value = 'ARMED $boundary: stop process and relaunch';
      debugPrint('PUBLICATION_PROOF ARMED $boundary');
      await Completer<void>().future; // OS process stop is the only release.
    }
    final storage = armed ? native : OwnedStorage(channel: _ReceiptChannel(boundary, arm));
    final journal = armed ? TransferJournal(Future.value(db))
        : _GateJournal(Future.value(db), boundary, arm);
    final id = 'publication-$boundary';
    final name = 'synthetic-$boundary.bin';
    final stage = plan.stagePath(id);
    final target = File('$root/$name');
    final artifact = RemoteArtifact(id: RemoteArtifactId(providerId: 'drive',
        sourceId: 'synthetic', accountId: 'none', providerFileId: id),
        parentId: 'synthetic-folder',
        displayPath: name, displayName: name, sizeBytes: bytes.length,
        version: '1', canDownload: true,
        providerChecksums: {'md5': md5.convert(bytes).toString()});
    if (!armed) {
      _require(!await target.exists() && !await File(stage).exists(), 'preexisting_case');
      await journal.create(TransferRecord(id: id, artifact: artifact,
          destinationRoot: root, relativePath: name, stagePath: stage));
    }
    final before = await journal.transfer(id);
    _require(before != null, 'missing_case');
    if (armed && boundary != 'committed') {
      _require(await InstallationIndex(journal, storage: native)
          .resolveArtifact(artifact, root) == null, 'precommit_visible');
    }
    var mediaRequests = 0;
    final engine = DriveTransferEngine(journal: journal, storage: storage,
        revalidate: (_, __) async {}, openMedia: (_, offset, __) async {
      mediaRequests++;
      Stream<Uint8List> payload() async* {
        for (var at = offset; at < bytes.length; at += OwnedStorage.maxChunkBytes) {
          final end = at + OwnedStorage.maxChunkBytes < bytes.length
              ? at + OwnedStorage.maxChunkBytes : bytes.length;
          yield Uint8List.sublistView(bytes, at, end);
        }
      }
      return DriveMediaResponse(bytes: payload(), offset: offset,
          length: bytes.length - offset, total: bytes.length);
    });
    final result = await engine.start(id).result;
    _require(armed, 'publication_gate_not_reached_${result.errorCode}');
    _require(armed && mediaRequests == 0, 'recovery_downloaded_again');
    if (boundary == 'createReceipt') {
      // No recorded destination identity: an empty namesake must remain a
      // preserved conflict, never adopted. This is a test-owned exact file.
      _require(result.lifecycle == TransferLifecycle.failed &&
          result.errorCode == 'storage_collision', 'unrecorded_create_not_conflict');
      _require(await target.length() == 0 && await File(stage).length() == bytes.length,
          'conflict_bytes_changed');
      _require(await InstallationIndex(journal, storage: native)
          .resolveArtifact(artifact, root) == null, 'conflict_installed');
      await target.delete();
      await File(stage).delete();
    } else {
      _require(result.lifecycle == TransferLifecycle.completed && result.stageRetired,
          'recovery_${result.errorCode}');
      _require(await InstallationIndex(journal, storage: native)
          .resolveArtifact(artifact, root) == target.path, 'recovery_not_ready');
      _require(listEquals(await target.readAsBytes(), bytes), 'wrong_payload');
      final manifest = (await journal.installationForTarget(
          destinationRoot: root, relativePath: name))!;
      await OwnedInstallationRemoval(journal, storage: native).remove(manifest);
      _require(!await target.exists() && !await File(stage).exists(), 'cleanup_incomplete');
    }
    _require(listEquals(await neighbor.readAsBytes(), [9, 8, 7]), 'neighbor_changed');
    debugPrint('PUBLICATION_PROOF RECOVERED $boundary');
    position++;
    await db.update('probe_state', {'boundary': position, 'armed': 0});
  }
  await db.close();
  await neighbor.delete();
  await Directory(root).delete();
  for (final path in [dbPath, '$dbPath-journal', '$dbPath-wal', '$dbPath-shm']) {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
  _status.value = 'PASSED: publication process-stop recovery and preserved create conflict';
  debugPrint('PUBLICATION_PROOF PASSED');
}
