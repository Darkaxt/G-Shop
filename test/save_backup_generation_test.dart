import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/save_backup_manifest.dart';
import 'package:g_shop/services/drive/drive_authorization.dart';
import 'package:g_shop/services/saves/drive_save_backup_generation.dart';

class _Auth implements DriveAuthorizationDriver {
  final scopes = <List<String>>[];
  @override
  Future<String?> authenticate({required bool interactive}) async => 'account';
  @override
  Future<String?> authorize(String accountId, List<String> scopes,
      {required bool interactive}) async {
    this.scopes.add(scopes);
    return 'private-token';
  }

  @override
  Future<void> clearRejectedToken(String accountId, String token) async {}
  @override
  Future<void> signOut({required bool revoke}) async {}
}

ResponseBody _json(Object value, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(value), status);

class _Drive implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final metadata = <String, Map<String, dynamic>>{};
  final bytes = <String, List<int>>{};
  final verified = <String>[];
  final committed = <String>[];
  String? corruptRead, loseResponse, foreignLocation;
  CancelToken? cancelDuringRead;
  bool changeVersionOnRead = false;
  bool changeViewMetadataOnRead = false;
  int largestChunk = 0;
  final listPages = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions request, Stream<Uint8List>? body,
      Future<void>? cancelFuture) async {
    requests.add(request);
    expect(request.uri.origin, 'https://www.googleapis.com');
    expect(request.followRedirects, isFalse);
    expect(request.headers['Authorization'], 'Bearer private-token');
    if (request.method == 'GET' && request.uri.path == '/drive/v3/files') {
      expect(request.uri.queryParameters['q'], contains("'area' in parents"));
      expect(request.uri.queryParameters['q'], contains("value='generation'"));
      return _json(listPages.removeAt(0));
    }
    if (request.method == 'POST') {
      expect(request.uri.path, '/upload/drive/v3/files');
      expect(request.uri.queryParameters['uploadType'], 'resumable');
      final data = jsonDecode(utf8
              .decode(await body!.fold<List<int>>([], (a, b) => a..addAll(b))))
          as Map<String, dynamic>;
      final id = data['id'] as String;
      metadata[id] = {
        ...data,
        'ownedByMe': true,
        'isAppAuthorized': true,
        'trashed': false,
        'shared': false
      };
      return ResponseBody.fromString('', 200, headers: {
        'location': [
          foreignLocation ??
              'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=$id'
        ]
      });
    }
    if (request.method == 'PUT') {
      final id = request.uri.queryParameters['upload_id']!;
      final value = <int>[];
      await for (final chunk in body!) {
        largestChunk =
            chunk.length > largestChunk ? chunk.length : largestChunk;
        value.addAll(chunk);
      }
      bytes[id] = value;
      metadata[id]!['size'] = value.length.toString();
      metadata[id]!['version'] = '1';
      metadata[id]!['headRevisionId'] = 'revision-1';
      metadata[id]!['md5Checksum'] = md5.convert(value).toString();
      committed.add(id);
      if (id == 'generation-a') {
        expect(verified, containsAll(['member-a', 'member-b']));
      }
      if (loseResponse == id) {
        loseResponse = null;
        throw StateError('response lost after commit');
      }
      return _json(metadata[id]!);
    }
    final id = request.uri.path.split('/').last;
    if (id == 'area') {
      return _json({
        'id': id,
        'mimeType': 'application/vnd.google-apps.folder',
        'ownedByMe': true,
        'isAppAuthorized': true,
        'shared': false,
        'trashed': false,
        'appProperties': {'rshopSaveBackup': '1', 'kind': 'area'}
      });
    }
    if (!bytes.containsKey(id)) return _json({}, 404);
    if (request.uri.queryParameters['alt'] == 'media') {
      verified.add(id);
      if (changeVersionOnRead) {
        metadata[id]!['version'] = 'changed';
        metadata[id]!['headRevisionId'] = 'revision-changed';
      }
      if (changeViewMetadataOnRead) {
        metadata[id]!['version'] = 'viewed';
        metadata[id]!['viewedByMeTime'] = '2026-10-09T14:00:00Z';
      }
      final value = id == corruptRead ? [1, 2, 3] : bytes[id]!;
      return ResponseBody(Stream<Uint8List>.multi((controller) {
        controller.add(Uint8List.fromList(value));
        cancelDuringRead?.cancel();
        controller.close();
      }), 200);
    }
    return _json(metadata[id]!);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory directory;
  late _Drive drive;
  late _Auth auth;
  late DriveSaveBackupGenerationApi api;
  late SaveBackupManifest generation;
  late Map<String, File> files;
  setUp(() async {
    final preferred = Directory(r'D:\Temp');
    final temporaryRoot = Platform.isWindows && await preferred.exists()
        ? preferred
        : Directory.systemTemp;
    directory = await temporaryRoot.createTemp('rshop-save-test-');
    files = {
      'member-a': File('${directory.path}/one.srm'),
      'member-b': File('${directory.path}/one.rtc')
    };
    await files['member-a']!
        .writeAsBytes(List.generate(150000, (i) => i % 251));
    await files['member-b']!.writeAsBytes([1, 2, 3, 4]);
    generation = SaveBackupManifest(
        generationId: 'generation-a',
        binding: SaveBackupBinding(
            accountId: 'account',
            deviceId: 'device',
            emulatorPackage: 'com.retroarch.aarch64',
            emulatorVersion: '1.22.2',
            coreId: 'mgba',
            coreVersion: '0.10.5',
            platformId: 'gba',
            editions: [
              SaveBackupEdition(gameId: 'game-a', editionId: 'edition-a')
            ],
            kind: SaveBackupKind.save,
            formatId: 'gba-save-ram'),
        parentGenerationIds: [],
        createdAt: DateTime.utc(2026, 10, 9),
        members: [
          for (final entry in files.entries)
            SaveBackupMember(
                relativePath: entry.key == 'member-a' ? 'one.srm' : 'one.rtc',
                cloudFileId: entry.key,
                sizeBytes: await entry.value.length(),
                sha256: (await sha256.bind(entry.value.openRead()).first)
                    .toString())
        ]);
    drive = _Drive();
    auth = _Auth();
    api = DriveSaveBackupGenerationApi(
        authorization: DriveAuthorization(auth),
        accountId: 'account',
        transport: drive);
  });
  tearDown(() async {
    api.close();
    // Only exact files generated by this fixture; no recursive/global cleanup.
    for (final file in files.values) {
      await file.delete();
    }
    await directory.delete();
  });

  test('streams verified members before publishing the complete manifest',
      () async {
    await api.publish(areaId: 'area', generation: generation, captures: files);
    expect(drive.committed, ['member-b', 'member-a', 'generation-a']);
    expect(drive.largestChunk, lessThanOrEqualTo(65536));
    expect(
        auth.scopes.every((s) =>
            s.length == 1 && s.single == DriveAuthorization.backupFileScope),
        isTrue);
    expect(
        SaveBackupManifest.decode(drive.bytes['generation-a']!).contentDigest,
        generation.contentDigest);
    expect(
        drive.requests.every((r) => ['GET', 'POST', 'PUT'].contains(r.method)),
        isTrue);
  });

  test(
      'resumes and restores byte-backed objects with Drive-detected MIME types',
      () async {
    drive.loseResponse = 'member-a';
    await expectLater(
        api.publish(areaId: 'area', generation: generation, captures: files),
        throwsA(isA<SaveBackupGenerationException>()));
    // Observed on Thor: Drive classified the PS1 card as a TeX font metric,
    // although the resumable upload requested application/octet-stream.
    drive.metadata['member-a']!['mimeType'] = 'application/x-tex-tfm';
    await api.publish(areaId: 'area', generation: generation, captures: files);
    drive.metadata['generation-a']!['mimeType'] = 'application/json';
    final restored = await api.loadGeneration(
        areaId: 'area',
        generationId: 'generation-a',
        target: generation.binding);
    final restoredBytes = await api
        .memberBytes(areaId: 'area', generation: restored, memberId: 'member-a')
        .fold<List<int>>([], (result, chunk) => result..addAll(chunk));
    expect(
        sha256.convert(restoredBytes).toString(),
        generation.members
            .singleWhere((member) => member.cloudFileId == 'member-a')
            .sha256);
    expect(drive.committed.where((id) => id == 'member-a'), hasLength(1));
  });

  for (final mime in [
    'application/vnd.google-apps.document',
    'application/vnd.google-apps.folder',
    'application/vnd.google-apps.shortcut',
    '',
    null,
  ]) {
    test('rejects non-byte-backed MIME $mime before downloading content',
        () async {
      await api.publish(
          areaId: 'area', generation: generation, captures: files);
      drive.metadata['generation-a']!['mimeType'] = mime;
      drive.verified.clear();
      await expectLater(
          api.loadGeneration(
              areaId: 'area',
              generationId: 'generation-a',
              target: generation.binding),
          throwsA(isA<SaveBackupGenerationException>()));
      expect(drive.verified, isEmpty);
    });
  }

  test('discovers complete generations across pages and origin devices',
      () async {
    await api.publish(areaId: 'area', generation: generation, captures: files);
    drive.listPages.addAll([
      {'files': [], 'nextPageToken': 'next'},
      {
        'files': [
          {'id': generation.generationId}
        ]
      }
    ]);
    final target = SaveBackupBinding.fromJson(
        {...generation.binding.toJson(), 'deviceId': 'another-device'});
    final discovered =
        await api.discoverGenerations(areaId: 'area', target: target);
    expect(discovered.single.generationId, generation.generationId);
    expect(drive.listPages, isEmpty);
  });

  for (final policy in SaveCompanionCompatibility.values) {
    test('companion ${policy.name} publication enforces import compatibility',
        () async {
      final binding = SaveBackupBinding.fromJson({
        ...generation.binding.toJson(),
        'kind': 'companion',
        'formatId': 'rom-companion-v1',
        'companionCompatibility': policy.name,
      });
      final companion = SaveBackupManifest(
          generationId: generation.generationId,
          binding: binding,
          parentGenerationIds: [],
          createdAt: generation.createdAt,
          members: [
            for (final member in generation.members)
              SaveBackupMember(
                  relativePath: policy == SaveCompanionCompatibility.runtime
                      ? 'cache/${member.cloudFileId}.dat'
                      : 'screenshots/${member.cloudFileId}.png',
                  cloudFileId: member.cloudFileId,
                  sizeBytes: member.sizeBytes,
                  sha256: member.sha256),
          ]);
      await api.publish(areaId: 'area', generation: companion, captures: files);
      final target = SaveBackupBinding.fromJson({
        ...binding.toJson(),
        'deviceId': 'another-device',
      });
      final loaded = await api.loadGeneration(
          areaId: 'area', generationId: companion.generationId, target: target);
      expect(loaded.binding.kind, SaveBackupKind.companion);
      expect(loaded.binding.companionCompatibility, policy);
      expect(loaded.encode(), companion.encode());
      for (final member in loaded.members) {
        final received = await api
            .memberBytes(
                areaId: 'area',
                generation: loaded,
                memberId: member.cloudFileId)
            .fold<List<int>>([], (result, chunk) => result..addAll(chunk));
        expect(sha256.convert(received).toString(), member.sha256);
      }

      Future<List<SaveBackupManifest>> discover(SaveBackupBinding requested) {
        drive.listPages.add({
          'files': [
            {'id': companion.generationId},
          ],
        });
        return api.discoverGenerations(areaId: 'area', target: requested);
      }

      expect(await discover(target), hasLength(1));
      final changedRuntime = SaveBackupBinding.fromJson({
        ...target.toJson(),
        'emulatorVersion': 'next-runtime',
        'coreVersion': 'next-core',
      });
      expect(
          await discover(changedRuntime),
          policy == SaveCompanionCompatibility.portable
              ? hasLength(1)
              : isEmpty);
      if (policy == SaveCompanionCompatibility.runtime) {
        await expectLater(
            api.loadGeneration(
                areaId: 'area',
                generationId: companion.generationId,
                target: changedRuntime),
            throwsA(isA<SaveBackupGenerationException>().having(
                (error) => error.issue,
                'issue',
                SaveBackupGenerationIssue.invalidBinding)));
      }
      // No companion publication can become an in-game save, a different
      // edition, or a publication with a different portability policy.
      expect(await discover(generation.binding), isEmpty);
      expect(
          await discover(SaveBackupBinding.fromJson({
            ...target.toJson(),
            'editions': [
              {'gameId': 'game-a', 'editionId': 'another-edition'},
            ],
          })),
          isEmpty);
      expect(
          await discover(SaveBackupBinding.fromJson({
            ...target.toJson(),
            'companionCompatibility':
                policy == SaveCompanionCompatibility.portable
                    ? 'runtime'
                    : 'portable',
          })),
          isEmpty);
      expect(drive.committed.where((id) => id == companion.generationId),
          hasLength(1));
    });
  }

  test(
      'shared PS1 publication is discoverable from another game but not another card',
      () async {
    final file = files['member-a']!;
    await file.writeAsBytes(List<int>.generate(131072, (index) => index % 251));
    final binding = SaveBackupBinding.fromJson({
      ...generation.binding.toJson(),
      'platformId': 'psx',
      'coreId': 'pcsx_rearmed',
      'formatId': 'pcsx-shared-card2-v1',
      'sharedCard': {
        'directory': '/storage/emulated/0/RetroArch/saves/PCSX-ReARMed',
        'slot': 2
      }
    });
    final shared = SaveBackupManifest(
        generationId: 'shared-generation',
        binding: binding,
        parentGenerationIds: [],
        createdAt: DateTime.utc(2026, 10, 12),
        members: [
          SaveBackupMember(
              relativePath: 'pcsx-card2.mcd',
              cloudFileId: 'member-a',
              sizeBytes: 131072,
              sha256: (await sha256.bind(file.openRead()).first).toString())
        ]);
    await api.publish(
        areaId: 'area', generation: shared, captures: {'member-a': file});
    final target = SaveBackupBinding.fromJson({
      ...binding.toJson(),
      'editions': [
        {'gameId': 'another-game', 'editionId': 'another-edition'}
      ]
    });
    for (final selected in [
      target,
      SaveBackupBinding.fromJson({
        ...target.toJson(),
        'formatId': 'pcsx-shared-card1-v1',
        'sharedCard': {
          'directory': '/storage/emulated/0/RetroArch/saves/PCSX-ReARMed',
          'slot': 1
        }
      })
    ]) {
      drive.listPages.add({
        'files': [
          {'id': shared.generationId}
        ]
      });
      final found =
          await api.discoverGenerations(areaId: 'area', target: selected);
      if (selected == target) {
        expect(found.single.binding.editions.single.editionId, 'edition-a');
        final recovered = await api
            .memberBytes(
                areaId: 'area', generation: found.single, memberId: 'member-a')
            .fold<int>(0, (size, chunk) => size + chunk.length);
        expect(recovered, 131072);
      } else {
        expect(found, isEmpty);
      }
    }
    expect(drive.committed, ['member-a', 'shared-generation']);
    expect(
        drive.requests
            .every((request) => !['DELETE', 'PATCH'].contains(request.method)),
        isTrue);
  });

  test('incomplete listing cannot authorize a conflict-free upload', () async {
    drive.listPages.add({'files': [], 'incompleteSearch': true});
    await expectLater(
        api.discoverGenerations(areaId: 'area', target: generation.binding),
        throwsA(isA<SaveBackupGenerationException>()));
    expect(drive.committed, isEmpty);
  });

  test('changed capture and corrupt readback never publish a generation',
      () async {
    await files['member-a']!.writeAsBytes([9]);
    await expectLater(
        api.publish(areaId: 'area', generation: generation, captures: files),
        throwsA(isA<SaveBackupGenerationException>()));
    expect(drive.committed, isEmpty);
    await files['member-a']!
        .writeAsBytes(List.generate(150000, (i) => i % 251));
    drive.corruptRead = 'member-b';
    await expectLater(
        api.publish(areaId: 'area', generation: generation, captures: files),
        throwsA(isA<SaveBackupGenerationException>()));
    expect(drive.committed, ['member-b']);
    expect(drive.bytes.containsKey('generation-a'), isFalse);
  });

  test('ambiguous commit resumes with the same reserved IDs, without rewriting',
      () async {
    drive.loseResponse = 'member-a';
    await expectLater(
        api.publish(areaId: 'area', generation: generation, captures: files),
        throwsA(isA<SaveBackupGenerationException>()));
    expect(drive.committed, ['member-b', 'member-a']);
    await api.publish(areaId: 'area', generation: generation, captures: files);
    expect(drive.committed, ['member-b', 'member-a', 'generation-a']);
    await api.publish(areaId: 'area', generation: generation, captures: files);
    expect(drive.committed, ['member-b', 'member-a', 'generation-a']);
  });

  test('foreign session location cannot receive authorization or payload bytes',
      () async {
    drive.foreignLocation = 'https://example.invalid/upload';
    await expectLater(
        api.publish(areaId: 'area', generation: generation, captures: files),
        throwsA(isA<SaveBackupGenerationException>()));
    expect(drive.requests.any((r) => r.method == 'PUT'), isFalse);
    expect(drive.committed, isEmpty);
  });

  test('cancellation during readback preserves an unpublished generation',
      () async {
    final cancellation = CancelToken();
    drive.cancelDuringRead = cancellation;
    await expectLater(
        api.publish(
            areaId: 'area',
            generation: generation,
            captures: files,
            cancellation: cancellation),
        throwsA(isA<SaveBackupGenerationException>()));
    expect(drive.committed, ['member-b']);
    expect(drive.bytes.containsKey('generation-a'), isFalse);
  });

  test('foreign account and unexpected capture members fail before networking',
      () async {
    final other = DriveSaveBackupGenerationApi(
        authorization: DriveAuthorization(auth),
        accountId: 'other',
        transport: drive);
    await expectLater(
        other.publish(areaId: 'area', generation: generation, captures: files),
        throwsA(isA<SaveBackupGenerationException>()));
    other.close();
    await expectLater(
        api.publish(
            areaId: 'area',
            generation: generation,
            captures: {...files, 'extra': files.values.first}),
        throwsA(isA<SaveBackupGenerationException>()));
    expect(drive.requests, isEmpty);
  });

  test(
      'complete cloud generation can be read independently of the local capture',
      () async {
    await api.publish(areaId: 'area', generation: generation, captures: files);
    final restored = await api.loadGeneration(
        areaId: 'area',
        generationId: 'generation-a',
        target: generation.binding);
    expect(restored.contentDigest, generation.contentDigest);
    final bytes = await api
        .memberBytes(areaId: 'area', generation: restored, memberId: 'member-a')
        .fold<List<int>>([], (a, b) => a..addAll(b));
    expect(sha256.convert(bytes).toString(),
        restored.members.firstWhere((m) => m.cloudFileId == 'member-a').sha256);
    drive.corruptRead = 'member-a';
    await expectLater(
        api
            .memberBytes(
                areaId: 'area', generation: restored, memberId: 'member-a')
            .drain<void>(),
        throwsA(isA<SaveBackupGenerationException>()));
  });

  test('load and read reject foreign objects and never write cloud data',
      () async {
    await api.publish(areaId: 'area', generation: generation, captures: files);
    final before = drive.committed.length;
    drive.metadata['generation-a']!['shared'] = true;
    await expectLater(
        api.loadGeneration(
            areaId: 'area',
            generationId: 'generation-a',
            target: generation.binding),
        throwsA(isA<SaveBackupGenerationException>()));
    await expectLater(
        api
            .memberBytes(
                areaId: 'area', generation: generation, memberId: 'unlisted-id')
            .drain<void>(),
        throwsA(isA<SaveBackupGenerationException>()));
    expect(drive.committed.length, before);
  });

  test('failed newer publication preserves the previous complete generation',
      () async {
    await api.publish(areaId: 'area', generation: generation, captures: files);
    final previousBytes = List<int>.of(drive.bytes['generation-a']!);
    final next = SaveBackupManifest(
        generationId: 'generation-next',
        binding: generation.binding,
        parentGenerationIds: ['generation-a'],
        createdAt: DateTime.utc(2026, 10, 10),
        members: [
          for (final member in generation.members)
            SaveBackupMember(
                relativePath: member.relativePath,
                cloudFileId: '${member.cloudFileId}-next',
                sizeBytes: member.sizeBytes,
                sha256: member.sha256)
        ]);
    drive.corruptRead = 'member-a-next';
    await expectLater(
        api.publish(areaId: 'area', generation: next, captures: {
          for (final entry in files.entries) '${entry.key}-next': entry.value
        }),
        throwsA(isA<SaveBackupGenerationException>()));
    expect(drive.bytes['generation-a'], previousBytes);
    expect(drive.bytes.containsKey('generation-next'), isFalse);
    expect(
        drive.requests
            .every((r) => r.method != 'DELETE' && r.method != 'PATCH'),
        isTrue);
    final recovered = await api.loadGeneration(
        areaId: 'area',
        generationId: 'generation-a',
        target: generation.binding);
    expect(recovered.contentDigest, generation.contentDigest);
  });

  test('a content revision change during readback prevents publication',
      () async {
    drive.changeVersionOnRead = true;
    await expectLater(
        api.publish(areaId: 'area', generation: generation, captures: files),
        throwsA(isA<SaveBackupGenerationException>()));
    expect(drive.bytes.containsKey('generation-a'), isFalse);
  });

  test('view metadata changes do not invalidate verified binary content',
      () async {
    drive.changeViewMetadataOnRead = true;
    await api.publish(areaId: 'area', generation: generation, captures: files);
    expect(drive.committed, ['member-b', 'member-a', 'generation-a']);
    final restored = await api.loadGeneration(
        areaId: 'area',
        generationId: 'generation-a',
        target: generation.binding);
    expect(restored.contentDigest, generation.contentDigest);
  });

  test('missing content revision cannot authorize a verified generation',
      () async {
    await api.publish(areaId: 'area', generation: generation, captures: files);
    drive.metadata['generation-a']!.remove('headRevisionId');
    final diagnostics = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) diagnostics.add(message);
    };
    try {
      await expectLater(
          api.loadGeneration(
              areaId: 'area',
              generationId: 'generation-a',
              target: generation.binding),
          throwsA(isA<SaveBackupGenerationException>()));
    } finally {
      debugPrint = previous;
    }
    expect(diagnostics.single, contains('revision_valid=false'));
    expect(diagnostics.single, contains('markers_equal=true'));
    for (final privateValue in ['generation-a', 'account', 'private-token']) {
      expect(diagnostics.single, isNot(contains(privateValue)));
    }
  });
}
