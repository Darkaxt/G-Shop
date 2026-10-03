import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';

MetadataLookupRequest _request({
  MetadataRomIdentifier? romIdentifier,
  Set<String> contentTags = const {'Hack', 'T-Eng'},
  int refreshGeneration = 7,
}) =>
    MetadataLookupRequest(
      gameId: 'game-1',
      editionId: 'edition-1',
      platformId: 'snes',
      title: 'Example Game',
      verifiedProviderGameId: 'trusted-local-id',
      baseProviderGameId: 'base-1',
      contentTags: contentTags,
      region: 'US',
      language: 'en',
      revision: 'Rev 1',
      romIdentifier: romIdentifier,
      refreshGeneration: refreshGeneration,
    );

void main() {
  test('request aliases canonicalize without interpreting unfamiliar labels',
      () {
    final request = _request(contentTags: {
      ' T-En ',
      'T-ENG',
      'dubbed',
      'Undubbed',
      'UNCENSORED',
      'Translation'
    });
    expect(request.contentTags,
        {'T-Eng', 'Dub', 'Undub', 'Uncensor', 'Translation'});
    final restored = MetadataLookupRequest.fromJson({
      ...request.toJson(),
      'contentTags': ['T-En', 'T-ENG', 'Dubbed', 'Translation'],
    });
    expect(restored.toJson()['contentTags'], ['Dub', 'T-Eng', 'Translation']);
    expect(() => restored.contentTags.add('Hack'), throwsUnsupportedError);
  });
  test(
      'round trips every request and raw-ROM identifier field deterministically',
      () {
    final request = _request(
      romIdentifier: const MetadataRomIdentifier(
        kind: RomIdentifierKind.rawRom,
        filename: 'Example Game.sfc',
        sizeBytes: 1024,
        crc32: 'A1B2C3D4',
        md5: '0123456789abcdef0123456789abcdef',
        sha1: '0123456789abcdef0123456789abcdef01234567',
      ),
      contentTags: {'T-Eng', 'Hack'},
    );

    final json = request.toJson();
    final restored = MetadataLookupRequest.fromJson(json);

    expect(restored.toJson(), json);
    expect(json['contentTags'], ['Hack', 'T-Eng']);
    expect(jsonEncode(restored.toJson()), jsonEncode(json));
    expect(restored.romIdentifier!.kind, RomIdentifierKind.rawRom);
    expect(restored.romIdentifier!.sha1,
        '0123456789abcdef0123456789abcdef01234567');
  });

  test(
      'round trips absence of optional request and container identifier fields',
      () {
    final request = MetadataLookupRequest(
      gameId: 'game-2',
      editionId: 'edition-2',
      platformId: 'psx',
      title: 'Optional Fields',
      refreshGeneration: 0,
    );

    final restored = MetadataLookupRequest.fromJson(request.toJson());

    expect(restored.verifiedProviderGameId, isNull);
    expect(restored.baseProviderGameId, isNull);
    expect(restored.romIdentifier, isNull);
    expect(restored.contentTags, isEmpty);
  });

  test('canonicalizes content tags as an immutable sorted set', () {
    final restored = MetadataLookupRequest.fromJson({
      ..._request(contentTags: {'Uncensor', 'Dub'}).toJson(),
      'contentTags': ['Uncensor', 'Dub'],
    });

    expect(restored.contentTags.toList(), ['Dub', 'Uncensor']);
    expect(() => restored.contentTags.add('Hack'), throwsUnsupportedError);
    expect(restored.toJson()['contentTags'], ['Dub', 'Uncensor']);
  });

  test('rejects malformed persisted request fields', () {
    final valid = _request(
      romIdentifier: const MetadataRomIdentifier(
        kind: RomIdentifierKind.rawIso,
        filename: 'Example Game.iso',
        sizeBytes: 2048,
      ),
    ).toJson();
    final invalid = [
      {...valid, 'gameId': ''},
      {...valid, 'platformId': 4},
      {...valid, 'title': '   '},
      {...valid, 'refreshGeneration': -1},
      {
        ...valid,
        'contentTags': ['Hack', 1]
      },
      {
        ...valid,
        'contentTags': ['Hack', 'Hack']
      },
      {...valid, 'providerToken': 'must-not-persist'},
      {
        ...valid,
        'romIdentifier': {
          ...(valid['romIdentifier'] as Map<String, dynamic>),
          'kind': 'not-a-kind',
        },
      },
      {
        ...valid,
        'romIdentifier': {
          ...(valid['romIdentifier'] as Map<String, dynamic>),
          'sizeBytes': -1,
        },
      },
    ];

    for (final json in invalid) {
      expect(() => MetadataLookupRequest.fromJson(json), throwsFormatException);
    }
  });

  test(
      'withRefreshGeneration retains identity evidence and validates generation',
      () {
    final request = _request(
      romIdentifier: const MetadataRomIdentifier(
        kind: RomIdentifierKind.container,
        filename: 'Example Game.chd',
        sizeBytes: 2048,
        sha1: '0123456789abcdef0123456789abcdef01234567',
      ),
    );

    final refreshed = request.withRefreshGeneration(8);

    expect(refreshed.toJson(), {...request.toJson(), 'refreshGeneration': 8});
    expect(() => request.withRefreshGeneration(-1), throwsArgumentError);
    expect(
        () => MetadataLookupRequest(
              gameId: 'game-3',
              editionId: 'edition-3',
              platformId: 'snes',
              title: '',
              refreshGeneration: 0,
            ).withRefreshGeneration(1),
        throwsFormatException);
  });
}
