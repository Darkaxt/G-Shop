import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/services/metadata/metadata_png.dart';
import 'package:g_shop/services/metadata/metadata_provider.dart';
import 'package:g_shop/services/metadata/metadata_artwork_selection.dart';

Future<void> writeCrawlJson(File file, Object data) async {
  final staged = File('${file.path}.next');
  await staged.writeAsString(jsonEncode(data), flush: true);
  await staged.rename(file.path);
}

bool crawlStatusBlocks(String status) => !{
      'matched',
      'needsReview',
      'ambiguous',
      'unmatched',
      'unsupportedPlatform',
      'invalidRequest'
    }.contains(status);

Future<void> verifyRetainedCrawlArtwork(Map resource, Directory output) async {
  if (resource['status'] != 'matched') {
    if (crawlStatusBlocks(resource['status'] as String)) {
      throw const FormatException('Nonterminal resource');
    }
    return;
  }
  final digest = resource['sha256'];
  if (digest is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
      resource['file'] != '$digest.png') {
    throw const FormatException('Invalid retained artwork path');
  }
  final file = File('${output.path}/$digest.png');
  if (await file.length() != resource['bytes'] ||
      (await sha256.bind(file.openRead()).first).toString() != digest) {
    throw const FormatException('Retained artwork changed');
  }
}

Future<void> verifyRetainedCrawlResult(
    Map result, String manifest, String key, Directory output) async {
  if (result['version'] != 2 ||
      result['manifestSha256'] != manifest ||
      result['key'] != key ||
      crawlStatusBlocks(result['status'] as String)) {
    throw const FormatException('Invalid retained result');
  }
  for (final resource in result['artwork'] as List) {
    await verifyRetainedCrawlArtwork(resource as Map, output);
  }
}

String crawlItemKey(Map<String, dynamic> item) =>
    sha256.convert(utf8.encode(jsonEncode(item))).toString();

List<Map<String, dynamic>> parseCrawlManifest(dynamic value) {
  if (value is! Map ||
      value['version'] != 1 ||
      value['items'] is! List ||
      (value['items'] as List).isEmpty) {
    throw const FormatException('Invalid crawl manifest');
  }
  final seen = <String>{};
  final items = <Map<String, dynamic>>[];
  for (final raw in value['items'] as List) {
    final item = (raw as Map).cast<String, dynamic>();
    final request = MetadataLookupRequest.fromJson(item['request']);
    final archive = (item['archive'] as Map).cast<String, dynamic>();
    final artifact = RemoteArtifact.fromJson(archive['artifact']);
    if (!seen.add(request.editionId) ||
        !File(archive['path']).isAbsolute ||
        artifact.id.providerId != 'drive' ||
        artifact.version?.isNotEmpty != true ||
        artifact.sizeBytes == null ||
        artifact.providerChecksums.isEmpty ||
        !{'nes', 'gba', 'gb', 'gbc', 'snes', 'n64', 'nds'}
            .contains(request.platformId) ||
        !artifact.displayName.toLowerCase().endsWith('.7z') ||
        Uri.file(archive['path'], windows: Platform.isWindows)
                .pathSegments
                .last !=
            artifact.displayName ||
        request.romIdentifier != null ||
        item['allowRawBinding'] is! bool) {
      throw const FormatException('Invalid archive or edition binding');
    }
    items.add(item);
  }
  return items;
}

void validateCrawlObservation(
    Map<String, dynamic> item, Map<String, dynamic> observation) {
  final artifact = RemoteArtifact.fromJson(item['archive']['artifact']);
  final container = observation['container'] as Map;
  final raw = MetadataRomIdentifier.fromJson(
      (observation['raw'] as Map).cast<String, dynamic>());
  if (container['sizeBytes'] != artifact.sizeBytes ||
      raw.kind != RomIdentifierKind.rawRom ||
      raw.sizeBytes <= 0 ||
      raw.md5 == null ||
      raw.sha1 == null ||
      !artifact.providerChecksums.entries
          .any((e) => {'md5', 'sha1', 'sha256'}.contains(e.key))) {
    throw const FormatException('Container/raw boundary mismatch');
  }
  for (final hash in artifact.providerChecksums.entries) {
    if ({'md5', 'sha1', 'sha256'}.contains(hash.key) &&
        container[hash.key]?.toString().toLowerCase() !=
            hash.value.toLowerCase()) {
      throw const FormatException(
          'Container differs from exact Drive artifact');
    }
  }
}

Map<String, dynamic> retainedCrawlObservation(
    Map receipt, Map<String, dynamic> item, String manifestHash, String key) {
  if (receipt['version'] != 2 ||
      receipt['manifestSha256'] != manifestHash ||
      receipt['key'] != key ||
      item['allowRawBinding'] != true) {
    throw const FormatException('Retained raw evidence binding changed');
  }
  final observation = (receipt['observation'] as Map).cast<String, dynamic>();
  validateCrawlObservation(item, observation);
  return observation;
}

Map<String, int> crawlOutcomeCounts(Map<String, dynamic> completed) {
  final counts = <String, int>{};
  for (final status in completed.values) {
    counts.update(status as String, (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
}

Iterable<MetadataMedia> crawlArtworkSelection(
    MetadataRecord record, String? region) sync* {
  final regions = [if (region != null) region, 'us', 'eu', 'wor', 'jp'];
  for (final role in ['box-2D', 'box-2D-back', 'box-2D-side', 'box-texture']) {
    final candidates = record.media.where((m) => m.type == role).toList();
    if (candidates.isEmpty) continue;
    int rank(MetadataMedia media) {
      final i = regions.indexOf(media.region ?? 'wor');
      return i < 0 ? regions.length : i;
    }

    candidates.sort((a, b) => rank(a).compareTo(rank(b)));
    yield candidates.first;
  }
  yield* metadataPhysicalLabels(record, regions: [if (region != null) region]);
}

void validateCrawlPng(List<int> bytes) {
  final data = Uint8List.fromList(bytes);
  if (!validMetadataPng(data) || image.decodePng(data) == null) {
    throw const FormatException('Invalid PNG body');
  }
}

Future<Map<String, String>> readCrawlCredentials(File file) async {
  final result = <String, String>{};
  if (await file.exists()) {
    for (final line in await file.readAsLines()) {
      final match =
          RegExp(r'^\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*)$').firstMatch(line);
      if (match == null) continue;
      var value = match[2]!;
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      result[match[1]!] = value;
    }
  }
  result.addAll(Platform.environment);
  return result;
}
