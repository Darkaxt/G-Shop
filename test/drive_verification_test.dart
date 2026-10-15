import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';
import 'package:retro_eshop/services/drive/drive_media.dart';
import 'package:retro_eshop/services/drive/drive_verification.dart';

final _bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
Map<String, String> get _hashes => {
      'md5': md5.convert(_bytes).toString(),
      'sha1': sha1.convert(_bytes).toString(),
      'sha256': sha256.convert(_bytes).toString(),
    };

RemoteArtifact snapshot(
        {Map<String, String>? hashes,
        int? size = 5,
        String? version = '1',
        String? parent = 'folder',
        bool? canDownload = true}) =>
    RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: 'source',
            accountId: 'account',
            providerFileId: 'file'),
        parentId: parent,
        displayName: 'fixture.chd',
        displayPath: 'fixture.chd',
        sizeBytes: size,
        version: version,
        canDownload: canDownload,
        providerChecksums: hashes ?? _hashes);

DriveFile current(
        {String id = 'file',
        int size = 5,
        String version = '1',
        String parent = 'folder',
        Map<String, String>? hashes,
        bool canDownload = true,
        String mime = 'application/octet-stream',
        bool trashed = false}) =>
    DriveFile(
        id: id,
        name: 'fixture.chd',
        mimeType: mime,
        parents: [parent],
        version: version,
        sizeBytes: size,
        checksums: hashes ?? _hashes,
        canDownload: canDownload,
        trashed: trashed);

Matcher issue(DriveTransferIssue value) =>
    isA<DriveTransferException>().having((e) => e.issue, 'issue', value);

void main() {
  test('snapshot rejection identifies changed fields without private values',
      () {
    final messages = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() => debugPrint = original);
    expect(
        () =>
            DriveVerification(snapshot()).requireCurrent(current(version: '2')),
        throwsA(issue(DriveTransferIssue.sourceChanged)));
    expect(messages.single, contains('version=true'));
    expect(messages.single, contains('size=false'));
    expect(messages.single, isNot(contains('fixture.chd')));
    expect(messages.single, isNot(contains(_hashes['md5']!)));
  });
  test('verifies exact bytes and returns local sha256 with provider checksums',
      () async {
    final verification =
        DriveVerification(snapshot(hashes: {'md5': _hashes['md5']!}));
    verification.requireCurrent(current());
    final result = await verification.verifyBytes(
        Stream.fromIterable([
          Uint8List.sublistView(_bytes, 0, 2),
          Uint8List.sublistView(_bytes, 2),
        ]),
        cancellation: CancelToken());
    expect(result['md5'], _hashes['md5']);
    expect(result['sha256'], _hashes['sha256']);
  });

  test('missing checksum or invalid download/version/size cannot be verified',
      () {
    for (final item in [
      snapshot(hashes: {}),
      snapshot(hashes: {'crc32': 'abcd'}),
    ]) {
      expect(() => DriveVerification(item),
          throwsA(issue(DriveTransferIssue.missingChecksum)));
    }
    for (final item in [
      snapshot(size: null),
      snapshot(version: null),
      snapshot(parent: null),
      snapshot(canDownload: null),
      snapshot(canDownload: false),
      snapshot(hashes: {'md5': 'malformed'})
    ]) {
      expect(() => DriveVerification(item),
          throwsA(issue(DriveTransferIssue.invalidSource)));
    }
  });

  test('source changes before or after transfer invalidate verification', () {
    final verification = DriveVerification(snapshot());
    for (final item in [
      current(id: 'other'),
      current(size: 6),
      current(version: '2'),
      current(parent: 'outside'),
      current(hashes: {}),
      current(hashes: {
        'md5': '0' * 32,
        'sha1': _hashes['sha1']!,
        'sha256': _hashes['sha256']!
      }),
      current(canDownload: false),
      current(trashed: true),
      current(mime: 'application/vnd.google-apps.shortcut')
    ]) {
      expect(() => verification.requireCurrent(item),
          throwsA(issue(DriveTransferIssue.sourceChanged)));
    }
  });

  test('wrong bytes, wrong length and cancellation cannot be verified',
      () async {
    final verification = DriveVerification(snapshot());
    for (final bytes in [
      Uint8List.fromList([1, 2, 3, 4, 6]),
      Uint8List(4),
      Uint8List(6)
    ]) {
      await expectLater(
          verification.verifyBytes(Stream.value(bytes),
              cancellation: CancelToken()),
          throwsA(isA<DriveTransferException>()));
    }
    await expectLater(
        verification.verifyBytes(Stream.value(_bytes),
            cancellation: CancelToken()..cancel()),
        throwsA(issue(DriveTransferIssue.cancelled)));
  });

  test('stream failures are sanitized and close verification without a result',
      () async {
    await expectLater(
        DriveVerification(snapshot()).verifyBytes(
            Stream.error(StateError('private/path/account-info')),
            cancellation: CancelToken()),
        throwsA(issue(DriveTransferIssue.unavailable)));
  });

  for (final fixture in {
    33554432:
        '83ee47245398adee79bd9c0a8bc57b821e92aba10f5f9ade8a5d1fae4d8c4302',
    268435456:
        'a6d72ac7690f53be6ae46ba88506bd97302a093f7108472bd9efc3cefda06484',
  }.entries) {
    test('bounded streaming hash for ${fixture.key} generated zero bytes',
        () async {
      // Digests independently computed using .NET IncrementalHash (SHA256).
      // This generates one fresh 64 KiB chunk per demand, never a whole ROM.
      var chunks = 0;
      var maxChunk = 0;
      var sampledRss = ProcessInfo.currentRss;
      Stream<Uint8List> input() async* {
        for (var offset = 0; offset < fixture.key; offset += 65536) {
          final chunk = Uint8List(65536);
          chunks++;
          if (chunk.length > maxChunk) maxChunk = chunk.length;
          if (chunks % 256 == 0 && ProcessInfo.currentRss > sampledRss) {
            sampledRss = ProcessInfo.currentRss;
          }
          yield chunk;
        }
      }

      final results = await DriveVerification(
              snapshot(size: fixture.key, hashes: {'sha256': fixture.value}))
          .verifyBytes(input(), cancellation: CancelToken());
      expect(results, {'sha256': fixture.value});
      expect(chunks * maxChunk, fixture.key);
      expect(maxChunk, 65536);
      // Whole-process RSS includes the test runtime/JIT/GC, not just transfer
      // buffers. Record samples; do not disguise these as a measured hard cap.
      stdout.writeln(
          'streamFixture bytes=${fixture.key} chunks=$chunks maxChunk=$maxChunk sampledRss=$sampledRss');
    });
  }
}
