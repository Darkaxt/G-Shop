import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/scraped_metadata.dart';

void main() {
  Map<String, dynamic> corrected() => {
        'sourceId': 'launchbox',
        'assetId': 'fixture/front',
        'sourceUrl': 'https://images.launchbox-app.com/fixture.png',
        'sha256': List.filled(64, 'a').join(),
        'sourceSha256': List.filled(64, 'b').join(),
        'colourCorrection': {
          'method': 'rgb-affine-v1',
          'referenceSha256': List.filled(64, 'c').join(),
          'referenceSourceId': 'screenscraper',
          'matrix': [
            [1, 0, 0],
            [0, 1.2, 0],
            [0, 0, 1],
            [0, -.05, 0]
          ],
          'errorBefore': .2,
          'errorAfter': .08,
        }
      };
  test('derived colour provenance survives normal metadata serialization', () {
    final value = corrected();
    expect(ImportedArtworkReference.fromJson(value).toJson(), value);
  });
  test('composite donor provenance preserves an unknown printing region', () {
    final value = corrected()..remove('colourCorrection');
    value['reconstruction'] = 'composite';
    final media = MetadataMedia.fromJson({
      'type': 'outer-box-left',
      'region': 'us',
      'importReference': value,
    });
    expect(media.region, 'us');
    expect(media.importReference!.sourceRegion, isNull);
    expect(media.importReference!.toJson(), value);
    expect(() => ImportedArtworkReference.fromJson({
      ...value, 'reconstruction': 'regionalPackaging',
    }), throwsFormatException);
  });
  test('a Cover Project wrap panel is always marked as a fan cover', () {
    final value = {
      'sourceId': 'thecoverproject',
      'assetId': 'cover/7205',
      'sourceUrl':
          'https://coverproject.sfo2.cdn.digitaloceanspaces.com/nes/fixture.jpg',
      'sha256': List.filled(64, 'a').join(),
      'sourceSha256': List.filled(64, 'b').join(),
      'panel': [1829, 0, 1537, 2100],
      'reconstruction': 'fanCover',
    };
    expect(ImportedArtworkReference.fromJson(value).toJson(), value);
    expect(() => ImportedArtworkReference.fromJson({...value}..remove('reconstruction')),
        throwsFormatException);
    expect(() => ImportedArtworkReference.fromJson({...corrected(), 'reconstruction': 'fanCover'}),
        throwsFormatException);
  });
  test('a translation sticker is recorded as an overlay on original art', () {
    final value = corrected()
      ..remove('colourCorrection')
      ..['overlay'] = 'translationSticker';
    expect(ImportedArtworkReference.fromJson(value).toJson(), value);
    final dendy = {...value, 'overlay': 'dendySticker'};
    expect(ImportedArtworkReference.fromJson(dendy).toJson(), dendy);
    expect(() => ImportedArtworkReference.fromJson({...value, 'overlay': 'logo'}),
        throwsFormatException);
  });
  test('nonfinite or malformed colour transforms cannot enter metadata', () {
    for (final matrix in [
      [
        [double.nan, 0, 0],
        [0, 1, 0],
        [0, 0, 1],
        [0, 0, 0]
      ],
      [
        [1, 0, 0]
      ],
    ]) {
      final value = corrected();
      (value['colourCorrection'] as Map)['matrix'] = matrix;
      expect(() => ImportedArtworkReference.fromJson(value),
          throwsFormatException);
    }
  });
}
