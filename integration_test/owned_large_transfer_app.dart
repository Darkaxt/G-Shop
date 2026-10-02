// Isolated debug-only resource proof. Real engine/SQLite/native SD IO; synthetic
// streaming transport, no accounts/cloud/app DB/normal ROMs. Restore normal APK.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/services/drive/drive_media.dart';
import 'package:retro_eshop/services/drive/drive_transfer_engine.dart';
import 'package:retro_eshop/services/installation_index.dart';
import 'package:retro_eshop/services/owned_installation_removal.dart';
import 'package:retro_eshop/services/owned_storage.dart';
import 'package:retro_eshop/services/transfer_journal.dart';

final _status = ValueNotifier('Running isolated resource proof');
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
    debugPrint('RESOURCE_PROOF ${_status.value}');
  }));
}

/// Observe the actual native channel, retaining no byte arrays or event history.
class _MeasuredChannel extends MethodChannel {
  int maxArrayBytes = 0;
  int pending = 0;
  int maxPending = 0;
  _MeasuredChannel() : super('com.retro.rshop/storage');
  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    pending++;
    if (pending > maxPending) maxPending = pending;
    try {
      final input = arguments is Map ? arguments['bytes'] : null;
      if (input is Uint8List && input.length > maxArrayBytes) maxArrayBytes = input.length;
      final result = await super.invokeMethod<T>(method, arguments);
      if (result is Uint8List && result.length > maxArrayBytes) maxArrayBytes = result.length;
      return result;
    } finally { pending--; }
  }
}

class _MeasuredJournal extends TransferJournal {
  final Future<void> Function() measure;
  _MeasuredJournal(super.database, this.measure);
  @override
  Future<TransferRecord> save(TransferRecord record) async {
    final result = await super.save(record);
    await measure();
    return result;
  }
}

Stream<Uint8List> _payload(int size, int offset) async* {
  for (var at = offset; at < size; at += OwnedStorage.maxChunkBytes) {
    final length = size - at < OwnedStorage.maxChunkBytes
        ? size - at : OwnedStorage.maxChunkBytes;
    final chunk = Uint8List(length);
    for (var i = 0; i < length; i++) { chunk[i] = (at + i) % 251; }
    yield chunk; // Consumer backpressure; no ROM-sized allocation/list.
  }
}

Future<void> _probe() async {
  _require(kDebugMode && Platform.isAndroid, 'debug_android_only');
  _require((await PackageInfo.fromPlatform()).packageName ==
      'com.darkaxt.rshop.debug', 'isolated_package_only');
  const root = String.fromEnvironment('RSHOP_RESOURCE_TEST_ROOT');
  _require(RegExp(r'^/storage/[A-Za-z0-9-]+/RShopResourceProof-[A-Za-z0-9_-]+$')
      .hasMatch(root), 'invalid_probe_root');
  final support = await getApplicationSupportDirectory();
  final dbPath = '${support.path}/${root.split('/').last}.sqlite';
  _require(!await File(dbPath).exists() && !await Directory(root).exists(), 'preexisting_probe');
  await Directory(root).create();
  final db = await openDatabase(dbPath, version: 1,
      onCreate: (db, _) => TransferJournalSchema.install(db));
  final channel = _MeasuredChannel();
  final storage = OwnedStorage(channel: channel);
  final plan = await storage.prepare(root);
  final neighbor = File('$root/synthetic-save.sav');
  await neighbor.writeAsBytes([9, 8, 7], flush: true);
  for (final size in [8 * 1024 * 1024, 256 * 1024 * 1024]) {
    final id = 'resource-$size';
    final name = 'synthetic-$size.bin';
    final stage = File(plan.stagePath(id));
    final target = File('$root/$name');
    _require(!await stage.exists() && !await target.exists(), 'preexisting_case');
    var peakFileBytes = 0;
    var peakRss = ProcessInfo.currentRss;
    var maxTransportBytes = 0;
    final baselineRss = peakRss;
    Future<void> measure() async {
      var total = 0;
      for (final file in [stage, target]) {
        if (await file.exists()) total += await file.length();
      }
      if (total > peakFileBytes) peakFileBytes = total;
      final rss = ProcessInfo.currentRss;
      if (rss > peakRss) peakRss = rss;
    }
    final journal = _MeasuredJournal(Future.value(db), measure);
    final artifact = RemoteArtifact(id: RemoteArtifactId(providerId: 'drive',
        sourceId: 'synthetic', accountId: 'none', providerFileId: id),
        parentId: 'synthetic-folder', displayPath: name, displayName: name,
        sizeBytes: size, version: '1', canDownload: true,
        providerChecksums: {'md5': (await md5.bind(_payload(size, 0)).single).toString()});
    await journal.create(TransferRecord(id: id, artifact: artifact,
        destinationRoot: root, relativePath: name, stagePath: stage.path));
    final engine = DriveTransferEngine(journal: journal, storage: storage,
        revalidate: (_, __) async {}, openMedia: (_, offset, __) async {
      Stream<Uint8List> measured() async* {
        await for (final chunk in _payload(size, offset)) {
          if (chunk.length > maxTransportBytes) maxTransportBytes = chunk.length;
          yield chunk;
        }
      }
      return DriveMediaResponse(bytes: measured(), offset: offset,
          length: size - offset, total: size);
    });
    final result = await engine.start(id).result;
    _require(result.lifecycle == TransferLifecycle.completed && result.stageRetired,
        'transfer_${result.errorCode}');
    _require(result.publication?.method == PublicationMethod.copy, 'copy_route_not_exercised');
    _require(peakFileBytes == size * 2, 'peak_copy_space_not_observed');
    _require(maxTransportBytes <= OwnedStorage.maxChunkBytes &&
        channel.maxArrayBytes <= OwnedStorage.maxChunkBytes && channel.maxPending == 1,
        'unbounded_transport_or_native_queue');
    _require(await InstallationIndex(journal, storage: storage)
        .resolveArtifact(artifact, root) == target.path, 'installation_not_ready');
    final manifest = (await journal.installationForTarget(
        destinationRoot: root, relativePath: name))!;
    await OwnedInstallationRemoval(journal, storage: storage).remove(manifest);
    _require(!await stage.exists() && !await target.exists(), 'owned_cleanup_incomplete');
    _require(listEquals(await neighbor.readAsBytes(), [9, 8, 7]), 'neighbor_changed');
    debugPrint('RESOURCE_PROOF size=$size transport=$maxTransportBytes nativeArray=${channel.maxArrayBytes} '
        'pending=${channel.maxPending} peakFiles=$peakFileBytes baselineRss=$baselineRss peakRss=$peakRss');
  }
  await db.close();
  await neighbor.delete();
  await Directory(root).delete();
  for (final path in [dbPath, '$dbPath-journal', '$dbPath-wal', '$dbPath-shm']) {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
  _status.value = 'PASSED: bounded streams and measured SD copy space';
  debugPrint('RESOURCE_PROOF PASSED');
}
