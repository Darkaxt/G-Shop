import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/services/metadata/metadata_cloud_library.dart';

// COVERAGE-FACTS-01: a digital re-release shows the retail carton as a
// reference. The reference record wins every role it carries, ignores the
// re-release's region, and leaves other roles to the edition's own records.
void main() {
  MetadataRecord record(String provider, List<MetadataMedia> media) =>
      MetadataRecord(
          gameId: 'game',
          editionId: 'vc',
          platformId: 'gba',
          providerId: provider,
          providerGameId: '1',
          retrievedAt: DateTime.utc(2026, 11, 24),
          refreshGeneration: 1,
          matchMethod: 'test',
          titles: const [],
          media: media);
  Map<String, Object?> row(MetadataRecord r) => {
        'edition_id': 'vc',
        'provider_id': r.providerId,
        'record_json': jsonEncode(r.toJson()),
        'edition_json': jsonEncode({
          'id': 'vc',
          'gameId': 'game',
          'providerIds': {},
          'regions': ['Europe'],
          'languages': [],
          'tags': [],
          'translatedLanguages': [],
          'members': [],
          'evidence': [],
        }),
      };

  test('retail reference supplies its roles whole, ahead of own media', () {
    final own = record('screenscraper', [
      MetadataMedia(type: 'box-2D', url: 'https://x/own-front', region: 'eu'),
      MetadataMedia(type: 'ss', url: 'https://x/own-shot', region: 'eu'),
    ]);
    final reference = record('reference', [
      MetadataMedia(type: 'box-2D', url: 'https://x/front', region: 'us'),
      MetadataMedia(type: 'box-2D-back', url: 'https://x/back', region: 'us'),
      MetadataMedia(type: 'box-2D-side', url: 'https://x/side', region: 'us'),
      MetadataMedia(
          type: 'support-texture', url: 'https://x/label', region: 'us'),
    ]);
    final resources = MetadataCloudLibrary.resources({
      'platform': 'gba',
      'records': [row(own), row(reference)],
    });
    expect(resources['box.png']?.url, 'https://x/front');
    expect(resources['box-back.png']?.url, 'https://x/back');
    expect(resources['box-spine.png']?.url, 'https://x/side');
    expect(resources['cartridge.png']?.url, 'https://x/label');
    expect(resources['screenshot-01.png']?.url, 'https://x/own-shot');
  });
}
