import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:g_shop/services/metadata/es_de_metadata_projection.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/services/metadata/effective_overall_rating.dart';

void main() {
  test('plain ES-DE ratings do not mislabel original-game translation scores',
      () {
    final game = GameIdentity(
        id: 'g',
        platformId: 'psx',
        title: 'Fixture',
        providerIds: {'igdb': '42'},
        matchStatus: IdentityMatchStatus.manuallyMatched);
    final at = DateTime.utc(2026, 10, 5);
    final record = MetadataRecord(
        gameId: 'g',
        editionId: 'e',
        platformId: 'psx',
        providerId: 'igdb',
        providerGameId: '42',
        retrievedAt: at,
        refreshGeneration: 1,
        matchMethod: 'verifiedProviderIdGlobalGame',
        titles: const [
          MetadataText(text: 'Fixture')
        ],
        ratings: [
          SourcedRating.parse(
              sourceId: 'igdb',
              sourceLabel: 'IGDB',
              providerGameId: '42',
              rawValue: 85,
              scaleMinimum: 0,
              scaleMaximum: 100,
              voteCount: 100,
              kind: RatingKind.communityAggregate,
              retrievedAt: at)!
        ]);
    EffectiveOverallRating? selected(EditionIdentity edition,
            {Set<String> stale = const {}}) =>
        selectEffectiveOverallRating(
            game: game,
            edition: edition,
            records: [record],
            staleProviderIds: stale,
            assessedBases: productionOverallScoreBases);
    final official = EditionIdentity(id: 'e', gameId: 'g', tags: {'official'});
    expect(EsDeMetadataProjection.rating(selected(official)), '0.85');
    expect(EsDeMetadataProjection.rating(selected(official, stale: {'igdb'})),
        isNull);
    expect(EsDeMetadataProjection.rating(null), isNull);
    final lowVote = selectEffectiveOverallRating(
        game: game,
        edition: official,
        assessedBases: productionOverallScoreBases,
        records: [
          MetadataRecord.fromJson({
            ...record.toJson(),
            'ratings': [
              {
                ...record.ratings.single.toJson(),
                'rawValue': 100,
                'voteCount': 1
              }
            ]
          })
        ]);
    expect(EsDeMetadataProjection.rating(lowVote), isNull,
        reason: 'A low-vote extreme is not a trusted export score');
    final translated = EditionIdentity(
        id: 'e',
        gameId: 'g',
        tags: {'T-Eng'},
        isTranslation: true,
        translatedLanguages: ['en']);
    final originalScore = selected(translated)!;
    expect(originalScore.rankingEligible, true);
    expect(originalScore.ownership, OverallRatingOwnership.originalGame);
    expect(EsDeMetadataProjection.rating(originalScore), isNull,
        reason: 'ES-DE has no original-game ownership label for this number');
  });
  const original = '''<?xml version="1.0"?>
<gameList>
  <!-- keep launcher annotations -->
  <game id="77"><path>./Remote/Game.chd</path><name>Old name</name>
    <desc>Previous provider text</desc><favorite>true</favorite>
    <playcount>12</playcount><lastplayed>20261001T120000</lastplayed>
    <altemulator>custom</altemulator><customField>keep</customField>
  </game>
  <game><path>./Unrelated.chd</path><name>Unrelated</name></game>
</gameList>''';
  EsDeMetadataUpdate update(Map<String, String> fields,
          {String edition = 'remote-edition'}) =>
      EsDeMetadataUpdate(
          editionId: edition,
          relativeRomPath: './Remote/Game.chd',
          fields: fields);

  test('remote-only update preserves launcher state and unrelated XML', () {
    final result = EsDeMetadataProjection.merge(original, [
      update({'desc': 'Current provider text', 'genre': 'Adventure'})
    ], previousOwnership: {
      './Remote/Game.chd': EsDeFieldOwnership(
          editionId: 'remote-edition',
          fields: {'desc': 'Previous provider text'})
    });
    expect(result.conflicts, isEmpty);
    final xml = XmlDocument.parse(result.xml);
    final game = xml.findAllElements('game').first;
    expect(game.getElement('desc')!.innerText, 'Current provider text');
    expect(game.getElement('genre')!.innerText, 'Adventure');
    expect(game.getElement('name')!.innerText, 'Old name');
    expect(game.getElement('favorite')!.innerText, 'true');
    expect(game.getElement('playcount')!.innerText, '12');
    expect(game.getElement('lastplayed')!.innerText, '20261001T120000');
    expect(game.getElement('altemulator')!.innerText, 'custom');
    expect(game.getElement('customField')!.innerText, 'keep');
    expect(game.getAttribute('id'), '77');
    expect(xml.findAllElements('game').length, 2);
    expect(result.xml, contains('keep launcher annotations'));
    expect(result.ownership['./Remote/Game.chd']!.fields,
        {'desc': 'Current provider text', 'genre': 'Adventure'});
  });

  test('manual edit is a conflict, not overwritten or newly claimed', () {
    final result = EsDeMetadataProjection.merge(original, [
      update({'desc': 'New scrape', 'name': 'New name'})
    ], previousOwnership: {
      './Remote/Game.chd': EsDeFieldOwnership(
          editionId: 'remote-edition', fields: {'desc': 'Before manual edit'})
    });
    expect(result.conflicts.map((c) => c.reason), everyElement('manualField'));
    expect(result.conflicts.map((c) => c.field), containsAll(['desc', 'name']));
    final game = XmlDocument.parse(result.xml).findAllElements('game').first;
    expect(game.getElement('desc')!.innerText, 'Previous provider text');
    expect(game.getElement('name')!.innerText, 'Old name');
    expect(result.ownership['./Remote/Game.chd']!.fields['desc'],
        'Before manual edit');
  });

  test('missing local ROM can get metadata without creating a ROM or URL path',
      () {
    final result = EsDeMetadataProjection.merge(null, [
      update({'name': 'Remote & Game', 'desc': 'Fresh <text>'})
    ]);
    expect(result.conflicts, isEmpty);
    final game = XmlDocument.parse(result.xml).findAllElements('game').single;
    expect(game.getElement('path')!.innerText, './Remote/Game.chd');
    expect(game.getElement('name')!.innerText, 'Remote & Game');
    expect(game.getElement('desc')!.innerText, 'Fresh <text>');
    expect(result.ownership['./Remote/Game.chd']!.editionId, 'remote-edition');
  });

  test('a different edition cannot inherit path ownership', () {
    final result = EsDeMetadataProjection.merge(original, [
      update({'desc': 'Wrong release'}, edition: 'different-release')
    ], previousOwnership: {
      './Remote/Game.chd': EsDeFieldOwnership(
          editionId: 'remote-edition',
          fields: {'desc': 'Previous provider text'})
    });
    expect(result.xml, original);
    expect(result.conflicts.single.reason, 'editionChanged');
  });

  test('duplicate game paths or conflicting requested editions never merge',
      () {
    final duplicate = '<gameList><game><path>./Remote/Game.chd</path></game>'
        '<game><path>./Remote/Game.chd</path></game></gameList>';
    final result = EsDeMetadataProjection.merge(duplicate, [
      update({'desc': 'New scrape'})
    ]);
    expect(result.xml, duplicate);
    expect(result.conflicts.single.reason, 'ambiguousPath');
    final requests = EsDeMetadataProjection.merge(original, [
      update({'desc': 'One'}),
      update({'desc': 'Two'}, edition: 'another-edition')
    ]);
    expect(requests.xml, original);
    expect(requests.conflicts.single.reason, 'ambiguousPath');
  });

  test('only safe mapped ROM paths and supported scraped fields are accepted',
      () {
    for (final path in [
      '../Game.chd',
      './a/../Game.chd',
      '/sdcard/Game.chd',
      'https://example.test/Game.chd',
      'content://tree/file',
      './',
      './a//b'
    ]) {
      expect(
          () => EsDeMetadataUpdate(
              editionId: 'e', relativeRomPath: path, fields: {'name': 'Game'}),
          throwsFormatException);
    }
    for (final field in [
      'favorite',
      'playcount',
      'path',
      'altemulator',
      'token'
    ]) {
      expect(() => update({field: 'overwrite'}), throwsFormatException);
    }
    expect(() => update({'rating': '85'}), throwsFormatException);
    expect(() => update({'rating': '0.85'}), returnsNormally);
    expect(() => EsDeMetadataProjection.merge('<broken>', []),
        throwsFormatException);
  });

  test('malformed duplicate path fields cannot cause a second game entry', () {
    const brokenEntry = '<gameList><game>'
        '<path>./Remote/Game.chd</path><path>./Other.chd</path>'
        '<name>Keep</name></game></gameList>';
    final result = EsDeMetadataProjection.merge(brokenEntry, [
      update({'desc': 'Do not attach here'})
    ]);
    expect(result.xml, brokenEntry);
    expect(result.conflicts.single.reason, 'ambiguousPath');
  });
}
