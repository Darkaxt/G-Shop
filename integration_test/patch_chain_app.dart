import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' show getCrc32;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:g_shop/models/config/drive_source_config.dart';
import 'package:g_shop/models/config/provider_config.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/patch_catalogue.dart';
import 'package:g_shop/models/system_model.dart';
import 'package:g_shop/models/transfer_record.dart';
import 'package:g_shop/services/database_service.dart';
import 'package:g_shop/services/drive/drive_media.dart';
import 'package:g_shop/services/drive/drive_patch_catalogue.dart';
import 'package:g_shop/services/drive/drive_runtime.dart';
import 'package:g_shop/services/drive/drive_transfer_engine.dart';
import 'package:g_shop/services/owned_storage.dart';
import 'package:g_shop/services/patch_build_service.dart';
import 'package:g_shop/services/transfer_journal.dart';
import 'package:g_shop/services/verified_file_publication.dart';

// Only remote input transport is synthetic. The Android channel, patch engines,
// SQLite, owned storage, intermediate checks, publication and reuse are real.
const _config = ProviderConfig(
    type: ProviderType.drive,
    priority: 1,
    sourceId: 'patch-chain-proof',
    path: 'gba-folder',
    drive: DriveSourceConfig(
        accountId: 'synthetic',
        rootFolderId: 'root',
        serverClientId: 'unused-fixture-client'));

class _Runtime extends DriveRuntime {
  final DriveTransferEngine engine;
  int requests = 0;
  _Runtime(TransferJournal journal, OwnedStorage storage,
      Map<String, Uint8List> payloads)
      : engine = DriveTransferEngine(
            journal: journal,
            storage: storage,
            revalidate: (_, __) async {},
            openMedia: (artifact, offset, _) async {
              final bytes = payloads[artifact.id.providerFileId]!;
              return DriveMediaResponse(
                  bytes: Stream.value(Uint8List.sublistView(bytes, offset)),
                  offset: offset,
                  length: bytes.length - offset,
                  total: bytes.length);
            }),
        super(journal: journal, storage: storage);
  @override
  Future<DriveTransferOperation> startTransfer(
      {required ProviderConfig config,
      required String transferId,
      void Function(TransferRecord)? onCheckpoint}) async {
    requests++;
    return engine.start(transferId, onCheckpoint: onCheckpoint);
  }
}

class _Catalogue extends DrivePatchCatalogue {
  final Map<String, RemoteArtifact> artifacts;
  _Catalogue(this.artifacts, _Runtime runtime)
      : super(_config, runtime: runtime);
  @override
  Future<RemoteArtifact> resolve(PatchRelativePath reference) async =>
      artifacts[reference.value]!;
}

void _require(bool condition, String code) {
  if (!condition) throw StateError(code);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
      home: Scaffold(body: Text('Isolated patch chain acceptance'))));
  unawaited(_probe().catchError((Object error, StackTrace stack) {
    debugPrint('GShopPatchChainProof ${jsonEncode({
          'state': 'failed',
          'type': error.runtimeType.toString(),
          if (error is StateError) 'code': error.message,
          if (error is PatchBuildException) 'code': error.code
        })}');
    debugPrintStack(stackTrace: stack);
  }));
}

Future<void> _probe() async {
  _require(
      kDebugMode &&
          Platform.isAndroid &&
          (await PackageInfo.fromPlatform()).packageName ==
              'com.darkaxt.rshop.sharedproof',
      'isolated_debug_package_required');
  final root = p.join(
      (await getApplicationSupportDirectory()).path, 'patch-chain-proof');
  _require(!await Directory(root).exists(), 'fresh_fixture_required');
  await Directory(root).create();
  final db = await DatabaseService().database;
  const storage = OwnedStorage();
  final original = Uint8List.fromList([1, 2, 3, 4]);
  final intermediate = Uint8List.fromList([1, 9, 3, 4]);
  final expected = Uint8List.fromList([1, 9, 7, 4]);
  final ips = Uint8List.fromList(
      [...ascii.encode('PATCH'), 0, 0, 1, 0, 1, 9, ...ascii.encode('EOF')]);
  Uint8List le(int value) =>
      (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();
  final bpsBody = [
    ...ascii.encode('BPS1'),
    0x84,
    0x84,
    0x80,
    0x8d,
    ...expected,
    ...le(getCrc32(intermediate)),
    ...le(getCrc32(expected))
  ];
  final bps = Uint8List.fromList([...bpsBody, ...le(getCrc32(bpsBody))]);
  final corrupt = Uint8List.fromList(bps)..[bps.length - 1] ^= 1;
  final inputs = {
    'base': original,
    'first': ips,
    'second': bps,
    'corrupt': corrupt
  };
  final journal = TransferJournal(Future.value(db));
  final runtime = _Runtime(journal, storage, inputs);
  final artifacts = <String, RemoteArtifact>{};
  for (final entry in inputs.entries) {
    final filename = entry.key == 'base'
        ? 'base.gba'
        : entry.key == 'first'
            ? 'first.ips'
            : '${entry.key}.bps';
    artifacts['GBA/$filename'] = RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: _config.sourceId!,
            accountId: 'synthetic',
            providerFileId: entry.key),
        parentId: 'gba-folder',
        displayName: filename,
        displayPath: filename,
        version: '1',
        sizeBytes: entry.value.length,
        canDownload: true,
        providerChecksums: {'md5': md5.convert(entry.value).toString()});
  }
  final catalogue = _Catalogue(artifacts, runtime);
  IndexedPatchPayload payload(
          String filename, Uint8List bytes, PatchFormat format) =>
      IndexedPatchPayload(
          relativePath: 'GBA/$filename',
          sizeBytes: bytes.length,
          sha256: sha256.convert(bytes).toString(),
          format: format);
  final base = IndexedPatchBase(
      relativePath: PatchRelativePath('GBA/base.gba'),
      sizeBytes: original.length,
      checksums: {'sha256': sha256.convert(original).toString()});
  final first = IndexedRomPatch(
      source: 'Synthetic',
      section: 'hacks',
      sourceId: 'first',
      title: 'First',
      version: '1',
      description: '',
      bases: [base],
      payloads: [payload('first.ips', ips, PatchFormat.ips)],
      unsupportedFiles: []);
  IndexedRomPatch second({bool badContract = false, bool badPayload = false}) =>
      IndexedRomPatch(
          source: 'Synthetic',
          section: 'hacks',
          sourceId: badPayload ? 'corrupt' : 'second',
          title: 'Dependent',
          version: '1',
          description: '',
          bases: [],
          unsupportedFiles: [],
          payloads: [
            payload(badPayload ? 'corrupt.bps' : 'second.bps',
                badPayload ? corrupt : bps, PatchFormat.bps)
          ],
          requires: PatchDependency(
              step: PatchRecipeStep.fromPatch(first, first.payloads.single),
              outputSize: intermediate.length,
              outputHashes: {
                'sha256': badContract
                    ? '0' * 64
                    : sha256.convert(intermediate).toString()
              }));
  final service = PatchBuildService(
      database: Future.value(db), runtime: runtime, storage: storage);
  final game = IndexedPatchGame('synthetic-chain', 'Synthetic chain',
      PatchRelativePath('GBA/Patches/chain/game.json'));
  final system = SystemModel.supportedSystems.singleWhere((s) => s.id == 'gba');
  Future<PatchBuildResult> build(IndexedRomPatch selected) => service.build(
      catalogue: catalogue,
      indexedGame: game,
      patch: selected,
      availablePatches: [selected, first],
      payload: selected.payloads.single,
      base: base,
      system: system,
      targetFolder: root);
  final result = await build(second());
  final installed = File(p.join(result.targetRoot, result.game.filename));
  _require(listEquals(await installed.readAsBytes(), expected), 'final_bytes');
  _require(
      result.recipe.steps.map((s) => s.sourceId).join(',') == 'first,second',
      'ordered_recipe');
  final requests = runtime.requests;
  _require((await build(second())).reused && runtime.requests == requests,
      'verified_reuse');
  final before = (await db.query('installed_artifacts')).length;
  for (final selected in [
    second(badContract: true),
    second(badPayload: true)
  ]) {
    Object? failure;
    try {
      await build(selected);
    } catch (error) {
      failure = error;
    }
    _require(failure != null, 'expected_rejection');
    if (selected.sourceId == 'second') {
      _require(
          failure is PatchBuildException &&
              failure.code == 'input_fingerprint_mismatch',
          'intermediate_rejection');
    }
    _require(listEquals(await installed.readAsBytes(), expected),
        'existing_output_preserved');
    _require(
        (await service.store.localForPlatform('gba'))
                .where((r) => r['state'] == 'ready')
                .length ==
            1,
        'only_final_published');
  }
  final rows = await service.store.localForPlatform('gba');
  final ready = rows.singleWhere((r) => r['state'] == 'ready');
  _require(ready['scratchCleanup'] == 'complete', 'success_scratch_retired');
  _require((await db.query('installed_artifacts')).length >= before,
      'ownership_preserved');
  debugPrint('GShopPatchChainProof ${jsonEncode({
        'state': 'passed',
        'syntheticInputs': true,
        'nativeEngines': ['ips', 'bps'],
        'steps': 2,
        'sha256': sha256.convert(await installed.readAsBytes()).toString(),
        'verifiedReuse': true,
        'intermediateMismatchRejected': true,
        'corruptNativePatchRejected': true,
        'readyBuilds': 1,
        'failedBuilds': rows.where((r) => r['state'] == 'failed').length,
        'successScratchRetired': true
      })}');
  await db.close();
}
