import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:g_shop/models/scraped_metadata.dart';
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
  test(
      'exact provider media reuse preserves member identity and rejects changed bytes',
      () async {
    final source = await Directory.systemTemp.createTemp('gshop-crawl-reuse-');
    final output =
        await Directory.systemTemp.createTemp('gshop-crawl-reuse-output-');
    addTearDown(() => source.delete(recursive: true));
    addTearDown(() => output.delete(recursive: true));
    final media = MetadataMedia.fromJson({
      'type': 'support-texture',
      'region': 'us',
      'memberIndex': 1,
      'providerReference': {
        'providerId': 'screenscraper',
        'providerGameId': '7',
        'providerPlatformId': 12,
        'mediaType': 'support-texture',
        'region': 'us',
        'memberIndex': 1,
        'bracketedMemberIndex': true
      }
    });
    final bytes = image.encodePng(image.Image(width: 16, height: 16));
    final digest = sha256.convert(bytes).toString();
    await File('${source.path}/$digest.png').writeAsBytes(bytes);
    final receipt = File('${source.path}/${'a' * 64}.artwork.json');
    await receipt.writeAsString(jsonEncode([
      {
        'media': media.toJson(),
        'status': 'matched',
        'sha256': digest,
        'file': '$digest.png',
        'bytes': bytes.length
      }
    ]));
    final index = await indexRetainedCrawlArtwork([source]);
    final reused = await reuseCrawlArtwork(media, output, index);
    expect(reused!['media'], media.toJson());
    expect(File(reused['reusedFromArtworkReceipt'] as String).absolute.uri,
        receipt.absolute.uri);
    expect(await File('${output.path}/$digest.png').readAsBytes(), bytes);
    final other = MetadataMedia.fromJson({
      ...media.toJson(),
      'region': 'eu',
      'providerReference': <String, dynamic>{
        ...(media.toJson()['providerReference'] as Map<String, dynamic>),
        'region': 'eu'
      }
    });
    expect(await reuseCrawlArtwork(other, output, index), isNull);
    final second = MetadataMedia.fromJson({
      ...media.toJson(),
      'memberIndex': 2,
      'providerReference': <String, dynamic>{
        ...(media.toJson()['providerReference'] as Map<String, dynamic>),
        'memberIndex': 2
      }
    });
    expect(await reuseCrawlArtwork(second, output, index), isNull);
    final changedBytes = image.encodePng(image.Image(width: 17, height: 16));
    final changedDigest = sha256.convert(changedBytes).toString();
    await File('${source.path}/$changedDigest.png').writeAsBytes(changedBytes);
    await File('${source.path}/${'b' * 64}.artwork.json')
        .writeAsString(jsonEncode([
      {
        'media': media.toJson(),
        'status': 'matched',
        'sha256': changedDigest,
        'bytes': changedBytes.length,
        'file': '$changedDigest.png'
      }
    ]));
    final ambiguous = await indexRetainedCrawlArtwork([source]);
    expect(await reuseCrawlArtwork(media, output, ambiguous), isNull);
    await File('${source.path}/$digest.png').writeAsBytes([1, 2, 3]);
    expect(
        () => reuseCrawlArtwork(media, output, index), throwsFormatException);
  });
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
