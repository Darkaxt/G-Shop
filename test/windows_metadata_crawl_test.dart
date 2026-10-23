import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/services/metadata/metadata_provider.dart';
import '../scripts/metadata_crawl_support.dart';

Map<String, dynamic> item() {
  final artifact = RemoteArtifact(
      id: RemoteArtifactId(
          providerId: 'drive',
          sourceId: 'source',
          accountId: 'account',
          providerFileId: 'file'),
      displayName: 'Game.7z',
      displayPath: 'Game.7z',
      sizeBytes: 100,
      version: '2',
      providerChecksums: {'md5': 'a' * 32, 'sha256': 'b' * 64});
  return {
    'request': MetadataLookupRequest(
            gameId: 'game',
            editionId: 'edition',
            platformId: 'gba',
            title: 'Game',
            refreshGeneration: 1)
        .toJson(),
    'archive': {
      'path': '${Directory.current.path}${Platform.pathSeparator}Game.7z',
      'artifact': artifact.toJson()
    },
    'allowRawBinding': true
  };
}

void main() {
  test('manifest rejects duplicate editions and preasserted raw identities',
      () {
    final i = item();
    expect(
        parseCrawlManifest({
          'version': 1,
          'items': [i]
        }),
        hasLength(1));
    expect(
        () => parseCrawlManifest({
              'version': 1,
              'items': [i, i]
            }),
        throwsFormatException);
    i['request']['romIdentifier'] = MetadataRomIdentifier(
            kind: RomIdentifierKind.rawRom,
            filename: 'Game.gba',
            sizeBytes: 200,
            md5: 'f' * 32)
        .toJson();
    expect(
        () => parseCrawlManifest({
              'version': 1,
              'items': [i]
            }),
        throwsFormatException);
  });
  test('all known container checksums must agree; raw member remains separate',
      () {
    final observation = {
      'container': {'sizeBytes': 100, 'md5': 'a' * 32, 'sha256': 'b' * 64},
      'raw': MetadataRomIdentifier(
              kind: RomIdentifierKind.rawRom,
              filename: 'Game.gba',
              sizeBytes: 200,
              md5: 'c' * 32,
              sha1: 'd' * 40)
          .toJson()
    };
    validateCrawlObservation(item(), observation);
    (observation['container'] as Map)['sha256'] = 'e' * 64;
    expect(() => validateCrawlObservation(item(), observation),
        throwsFormatException);
  });
  test('artwork rejects a corrupt PNG or trailing bytes before acquisition',
      () {
    final png = image.encodePng(image.Image(width: 2, height: 2));
    validateCrawlPng(png);
    expect(() => validateCrawlPng([...png, 0]), throwsFormatException);
    png[png.length - 5] ^= 1;
    expect(() => validateCrawlPng(png), throwsFormatException);
  });
  test('resumed raw evidence retains exact artifact binding without a ROM read',
      () {
    final i = item();
    final receipt = {
      'version': 2,
      'manifestSha256': 'manifest',
      'key': crawlItemKey(i),
      'observation': {
        'container': {'sizeBytes': 100, 'md5': 'a' * 32, 'sha256': 'b' * 64},
        'raw': MetadataRomIdentifier(
                kind: RomIdentifierKind.rawRom,
                filename: 'Game.gba',
                sizeBytes: 200,
                md5: 'c' * 32,
                sha1: 'd' * 40)
            .toJson()
      }
    };
    // This fixture's ROM path does not exist: validated evidence is sufficient.
    expect(retainedCrawlObservation(receipt, i, 'manifest', crawlItemKey(i)),
        receipt['observation']);
    expect(() => retainedCrawlObservation(receipt, i, 'other', crawlItemKey(i)),
        throwsFormatException);
    i['archive']['artifact']['sizeBytes'] = 101;
    expect(
        () => retainedCrawlObservation(
            receipt, i, 'manifest', receipt['key'] as String),
        throwsFormatException);
  });
  test('progress counts outcomes rather than API calls', () {
    expect(
        crawlOutcomeCounts(
            {'a': 'matched', 'b': 'needsReview', 'c': 'matched'}),
        {'matched': 2, 'needsReview': 1});
  });
}
