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
