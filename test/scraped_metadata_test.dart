import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/scraped_metadata.dart';

void main() {
  final fetched = DateTime.utc(2026, 9, 8);

  SourcedRating? rating(Object? value, {int? votes}) => SourcedRating.parse(
        sourceId: 'screenscraper',
        sourceLabel: 'ScreenScraper',
        providerGameId: '42',
        rawValue: value,
        scaleMinimum: 0,
        scaleMaximum: 20,
        voteCount: votes,
        kind: RatingKind.unknownAggregate,
        retrievedAt: fetched,
      );

  test('preserves source, original scale, null votes and retrieval date', () {
    final score = rating('17')!;
    expect(score.rawValue, '17');
    expect(score.originalValue, 17);
    expect(score.scaleMaximum, 20);
    expect(score.normalizedValue, 85);
    expect(score.voteCount, isNull);
    expect(score.kind, RatingKind.unknownAggregate);
    expect(score.sourceId, 'screenscraper');
    expect(score.providerGameId, '42');
    expect(score.retrievedAt, fetched);
    expect(score.consensusValidated, isFalse);
    expect(SourcedRating.fromJson(score.toJson()).toJson(), score.toJson());
  });

  test('valid endpoints stay endpoints while absent or invalid stays absent',
      () {
    expect(rating('0')!.normalizedValue, 0);
    expect(rating('20')!.normalizedValue, 100);
    for (final value in [
      null,
      '',
      'not rated',
      '-1',
      '20.01',
      'NaN',
      'Infinity'
    ]) {
      expect(rating(value), isNull, reason: '$value is not a valid score');
    }
  });

  test('low vote extreme and imported approval cannot imply consensus', () {
    final score = rating('20', votes: 2)!;
    expect(score.voteCount, 2);
    expect(score.consensusValidated, isFalse);
    final imported = SourcedRating.fromJson({
      ...score.toJson(),
      'consensusValidated': true,
      'eligibleForRanking': true,
    });
    expect(imported.consensusValidated, isFalse);
    expect(rating('17', votes: -1)!.voteCount, isNull);
  });

  test(
      'media JSON cannot retain a credential URL or an arbitrary provider reference',
      () {
    expect(
        () => MetadataMedia.fromJson({
              'type': 'box-2D',
              'url':
                  'https://api.screenscraper.fr/api2/mediaJeu.php?sspassword=secret',
            }),
        throwsFormatException);
    expect(
        () => MetadataMedia.fromJson({
              'type': 'box-2D',
              'region': 'us',
              'providerReference': {
                'providerId': 'other-provider',
                'providerGameId': '42',
                'providerPlatformId': 4,
                'mediaType': 'box-2D',
                'region': 'us',
              },
            }),
        throwsFormatException);
    expect(
        () => MetadataMedia.fromJson({
              'type': 'box-2D',
              'region': 'us',
              'providerReference': {
                'providerId': 'screenscraper',
                'providerGameId': '42',
                'providerPlatformId': 4,
                'mediaType': 'box-2D?sspassword=secret',
                'region': 'us',
              },
            }),
        throwsFormatException);
  });
}
