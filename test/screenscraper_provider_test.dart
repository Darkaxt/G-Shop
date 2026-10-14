import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/metadata/screenscraper_provider.dart';

// Synthetic wire fixture shaped after the documented API v2 fields. This is
// contract evidence, not a captured or authenticated live response.
Map<String, dynamic> _game({String id = '42', String system = '4'}) => {
      'id': id,
      'systeme': {'id': system, 'text': 'Super Nintendo'},
      'noms': [
        {'region': 'us', 'text': 'Fixture: Adventure!'},
        {'region': 'jp', 'text': 'Fixture Monogatari'},
      ],
      'synopses': [
        {'langue': 'en', 'text': 'Synthetic adventure description.'}
      ],
      'dates': [
        {'region': 'us', 'text': '1994-10-18'}
      ],
      'developpeur': {'id': '7', 'text': 'Fixture Studio'},
      'editeur': {'id': '8', 'text': 'Fixture Publisher'},
      'genres': [
        {
          'id': '1',
          'noms': [
            {'langue': 'en', 'text': 'Adventure'}
          ]
        }
      ],
      'note': {'text': '17'},
      'medias': [
        {
          'type': 'box-2D',
          'region': 'us',
          'url': 'https://www.screenscraper.fr/image/fixture.png'
        },
        {'type': 'ss', 'url': 'https://www.screenscraper.fr/image/screen.png'},
      ],
      'rom': {
        'id': '90',
        'romfilename': 'Fixture Adventure (USA).sfc',
        'romsize': '1024',
        'romcrc': 'ABCDEF12',
        'romregions': 'us',
        'romlangues': 'en',
        'hack': '0',
        'trad': '0',
      },
    };

class _Wire implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Object? body;
  int status;
  Map<String, List<String>> headers;
  bool fail = false;
  Completer<void>? started;
  _Wire(this.body, {this.status = 200, this.headers = const {}});

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (started != null) {
      started!.complete();
      await cancelFuture;
      throw DioException.requestCancelled(
          requestOptions: options, reason: 'fixture');
    }
    if (fail) {
      throw DioException.connectionError(
          requestOptions: options, reason: options.uri.toString());
    }
    return ResponseBody.fromString(
        body is String ? body as String : jsonEncode(body), status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          ...headers
        });
  }

  @override
  void close({bool force = false}) {}
}

const _developer = ScreenScraperDeveloperCredentials(
  developerId: 'fixture-dev',
  developerPassword: 'fixture-dev-secret',
  softwareName: 'R-Shop-fixture',
);
const _user = ScreenScraperUserCredentials(
  username: 'fixture-user',
  password: 'fixture-user-secret',
);

String _authenticatedMedia(
        {String gameId = '42',
        String platformId = '4',
        String media = 'box-2D(us)'}) =>
    Uri.https('api.screenscraper.fr', '/api2/mediaJeu.php', {
      'devid': 'fixture-dev',
      'devpassword': 'fixture-dev-secret',
      'softname': 'R-Shop-fixture',
      'ssid': 'fixture-user',
      'sspassword': 'fixture-user-secret',
      'jeuid': gameId,
      'systemeid': platformId,
      'media': media
    }).toString();

MetadataLookupRequest _request({
  String platform = 'snes',
  String? verifiedProviderGameId = '42',
  Set<String> tags = const {'official'},
  String? baseProviderGameId,
  String? title,
  String? region,
  String? language,
  String? revision,
  MetadataRomIdentifier? identifier,
}) =>
    MetadataLookupRequest(
      gameId: 'game-fixture',
      editionId: 'edition-fixture',
      platformId: platform,
      title: title ?? 'Fixture Adventure',
      verifiedProviderGameId: verifiedProviderGameId,
      baseProviderGameId: baseProviderGameId,
      contentTags: tags,
      region: region,
      language: language,
      revision: revision,
      romIdentifier: identifier,
      refreshGeneration: 3,
    );

ScreenScraperProvider _provider(_Wire wire, {bool configured = true}) =>
    ScreenScraperProvider(
        httpClientAdapter: wire,
        readDeveloperCredentials: () async => configured ? _developer : null,
        readUserCredentials: () async => configured ? _user : null,
        clock: () => DateTime.utc(2026, 9, 8));

void main() {
  test('physical support texture has its own exact regional selection',
      () async {
    final game = _game();
    game['medias'] = [
      ...(game['medias'] as List),
      for (final region in ['jp', 'us'])
        {
          'type': 'support-texture',
          'region': region,
          'url': _authenticatedMedia(media: 'support-texture($region)')
        }
    ];
    final api = _provider(_Wire({
      'response': {'jeu': game}
    }));
    addTearDown(api.close);
    final result = await api.lookup(_request(region: 'USA'));
    final labels =
        result.record!.media.where((m) => m.type == 'support-texture');
    expect(labels, hasLength(1));
    expect(labels.single.region, 'us');
    expect(result.record!.media.where((m) => m.type == 'box-2D'), hasLength(1));
  });
  test('DSi uses verified provider alias without changing app identity',
      () async {
    final wire = _Wire({
      'response': {'jeu': _game(system: '15')}
    });
    final provider = _provider(wire);
    addTearDown(provider.close);
    final request = _request(platform: 'dsi');
    final captured = jsonEncode(request.toJson());
    final result = await provider.lookup(request);
    expect(result.status, MetadataLookupStatus.matched);
    expect(wire.requests.single.queryParameters['systemeid'], '15');
    expect(result.record!.platformId, 'dsi');
    expect(result.record!.gameId, request.gameId);
    expect(result.record!.editionId, request.editionId);
    expect(jsonEncode(request.toJson()), captured);
    expect(result.officialRomEvidence, isNull);
  });

  test('DSi alias still rejects another provider system', () async {
    final provider = _provider(_Wire({
      'response': {'jeu': _game(system: '17')}
    }));
    addTearDown(provider.close);
    final result = await provider.lookup(_request(platform: 'dsi'));
    expect(result.status, MetadataLookupStatus.unmatched);
    expect(result.record, isNull);
  });

  test('DSi title discovery does not classify unknown editions', () async {
    final game = _game(system: '15')..['notgame'] = 'false';
    final wire = _Wire({
      'response': {
        'jeux': [game]
      }
    });
    final provider = _provider(wire);
    addTearDown(provider.close);
    final request = _request(
        platform: 'dsi', verifiedProviderGameId: null, region: 'us', tags: {});
    final result = await provider.lookup(request);
    expect(result.status, MetadataLookupStatus.needsReview);
    expect(wire.requests.single.queryParameters['systemeid'], '15');
    expect(result.record, isNull);
    expect(result.officialRomEvidence, isNull);
    expect(result.candidates.single.titleMatched, isTrue);
  });

  test('NDS catalogue numbers are not part of provider title discovery',
      () async {
    for (final prefix in ['6280', 'z491']) {
      for (final tags in [
        <String>{},
        {'official'},
        {'Hack'},
        {'T-Eng'}
      ]) {
        final game = _game(system: '15')..['notgame'] = 'false';
        final wire = _Wire({
          'response': {
            'jeux': [game]
          }
        });
        final api = _provider(wire);
        final request = _request(
            platform: 'nds',
            verifiedProviderGameId: null,
            title: '$prefix - Fixture Adventure',
            region: 'us',
            tags: tags);
        final captured = jsonEncode(request.toJson());
        final result = await api.lookup(request);
        api.close();
        expect(wire.requests.single.queryParameters['recherche'],
            'Fixture Adventure');
        expect(result.candidates.single.titleMatched, isTrue);
        expect(jsonEncode(request.toJson()), captured);
        expect(result.officialRomEvidence, isNull);
        expect(
            result.status,
            tags.contains('official')
                ? MetadataLookupStatus.matched
                : MetadataLookupStatus.needsReview);
        if (result.record != null) {
          expect(result.record!.matchEvidence['title'], request.title);
          expect(
              result.record!.matchEvidence['searchTitle'], 'Fixture Adventure');
          expect(result.record!.matchEvidence['titleNormalization'],
              'ndsCatalogueNumberV1');
        }
      }
    }
  });

  test('NDS discovery preserves game numbers, other consoles and raw names',
      () async {
    for (final (platform, title) in [
      ('nds', '42 - All-Time Classics'),
      ('nds', '100 Classic Games'),
      ('nds', '1234 Adventures'),
      ('nds', 'z491 Adventures'),
      ('snes', '6280 - Fixture Adventure'),
      ('psp', 'z491 - Fixture Adventure'),
    ]) {
      final wire = _Wire({
        'response': {'jeux': <Object>[]}
      });
      final api = _provider(wire);
      await api.lookup(_request(
          platform: platform, title: title, verifiedProviderGameId: null));
      api.close();
      expect(wire.requests.single.queryParameters['recherche'], title);
    }
    final wire = _Wire({
      'response': {'jeu': _game(system: '15')}
    });
    final api = _provider(wire);
    final request = _request(
        platform: 'nds',
        title: '6280 - Fixture Adventure',
        verifiedProviderGameId: null,
        identifier: const MetadataRomIdentifier(
            kind: RomIdentifierKind.rawRom,
            filename: '6280 - Fixture Adventure (USA).nds',
            sizeBytes: 1024,
            crc32: 'ABCDEF12'));
    final captured = jsonEncode(request.toJson());
    await api.lookup(request);
    api.close();
    expect(wire.requests.single.queryParameters['romnom'],
        '6280 - Fixture Adventure (USA).nds');
    expect(
        wire.requests.single.queryParameters.containsKey('recherche'), isFalse);
    expect(jsonEncode(request.toJson()), captured);
  });

  test('reviewed edition region selects its cover instead of provider order',
      () async {
    final game = _game();
    game['medias'] = [
      {
        'type': 'box-2D',
        'region': 'jp',
        'url': _authenticatedMedia(media: 'box-2D(jp)')
      },
      {
        'type': 'box-2D',
        'region': 'wor',
        'url': _authenticatedMedia(media: 'box-2D(wor)')
      },
      {
        'type': 'box-3D',
        'region': 'us',
        'url': _authenticatedMedia(media: 'box-3D(us)')
      },
      {'type': 'ss', 'url': 'https://www.screenscraper.fr/image/screen.png'},
    ];
    final result = await _provider(_Wire({
      'response': {'jeu': game}
    })).lookup(_request(region: 'USA'));
    expect(result.status, MetadataLookupStatus.matched);
    final covers = result.record!.media
        .where((m) => {'box-2D', 'box-3D', 'cover'}.contains(m.type));
    expect(covers.map((m) => m.region), ['us']);
    expect(result.record!.media.any((m) => m.type == 'ss'), isTrue);
  });

  test('missing regional cover keeps neutral media, not another release',
      () async {
    final game = _game();
    game['medias'] = [
      {
        'type': 'box-2D',
        'region': 'jp',
        'url': _authenticatedMedia(media: 'box-2D(jp)')
      },
      {
        'type': 'box-2D',
        'region': 'wor',
        'url': _authenticatedMedia(media: 'box-2D(wor)')
      },
    ];
    final result = await _provider(_Wire({
      'response': {'jeu': game}
    })).lookup(_request(region: 'us'));
    expect(result.status, MetadataLookupStatus.matched);
    expect(result.record!.media.map((m) => m.region), ['wor']);
    game['medias'] = [(game['medias'] as List).first];
    final foreignOnly = await _provider(_Wire({
      'response': {'jeu': game}
    })).lookup(_request(region: 'us'));
    expect(foreignOnly.record!.media, isEmpty);
  });

  test('explicit access check reads only documented account quota fields',
      () async {
    final wire = _Wire({
      'response': {
        'ssuser': {
          'id': 'fixture-user',
          'maxthreads': '1',
          'requeststoday': '1',
          'maxrequestsperday': '100',
          'requestskotoday': '0',
          'maxrequestskoperday': '10',
          'maxrequestspermin': '2'
        }
      }
    });
    final provider = _provider(wire);
    addTearDown(provider.close);
    final result = await provider.checkAccess();
    expect(result.status, MetadataLookupStatus.matched);
    expect(result.record, isNull);
    expect(result.candidates, isEmpty);
    expect(result.quota!.maxRequestsPerMinute, 2);
    expect(result.quota!.requestsToday, 1);
    expect(wire.requests, hasLength(1));
    expect(wire.requests.single.uri.path, '/api2/ssuserInfos.php');
    expect(wire.requests.single.queryParameters.containsKey('gameid'), isFalse);
    expect(
        wire.requests.single.queryParameters.containsKey('recherche'), isFalse);
  });

  test('access check rejects missing counters instead of claiming recovery',
      () async {
    final wire = _Wire({
      'response': {
        'ssuser': {'maxthreads': '1'}
      }
    });
    final provider = _provider(wire);
    addTearDown(provider.close);
    expect((await provider.checkAccess()).status,
        MetadataLookupStatus.invalidResponse);
  });

  test('access check preserves HTTP guidance and does not expose credentials',
      () async {
    final wire = _Wire('provider failure', status: 429, headers: {
      'retry-after': ['12']
    });
    final provider = _provider(wire);
    addTearDown(provider.close);
    final result = await provider.checkAccess();
    expect(result.status, MetadataLookupStatus.throttled);
    expect(result.retryAfter, const Duration(seconds: 12));
    expect(result.message, isNot(contains('fixture-user-secret')));
    final missing = _provider(_Wire(null), configured: false);
    addTearDown(missing.close);
    expect((await missing.checkAccess()).status,
        MetadataLookupStatus.setupRequired);
  });

  test(
      'verified ID lookup parses provenance and never fetches ROM/media bodies',
      () async {
    final wire = _Wire({
      'response': {
        'jeu': _game(),
        'ssuser': {
          'maxthreads': '2',
          'requeststoday': '12',
          'maxrequestsperday': '1000',
          'maxrequestsperdmin': '20',
          'requestskotoday': '2',
          'maxrequestskoperday': '100',
        }
      }
    });
    final provider = _provider(wire);
    final result = await provider.lookup(_request());
    expect(result.status, MetadataLookupStatus.matched);
    final record = result.record!;
    expect(record.gameId, 'game-fixture');
    expect(record.editionId, 'edition-fixture');
    expect(record.providerGameId, '42');
    expect(record.refreshGeneration, 3);
    expect(record.descriptions.single.text, 'Synthetic adventure description.');
    expect(record.developer, 'Fixture Studio');
    expect(record.publisher, 'Fixture Publisher');
    expect(record.genres.single.names.single.text, 'Adventure');
    expect(record.releaseDates.single.text, '1994-10-18');
    expect(record.media.length, 2);
    expect(record.ratings.single.normalizedValue, 85);
    expect(record.ratings.single.voteCount, isNull);
    expect(record.ratings.single.consensusValidated, isFalse);
    expect(record.fieldProvenance['description']!.providerId, 'screenscraper');
    expect(record.fieldProvenance['description']!.retrievedAt,
        DateTime.utc(2026, 9, 8));
    expect(result.quota!.maxThreads, 2);
    expect(result.quota!.requestsToday, 12);
    expect(wire.requests, hasLength(1));
    final request = wire.requests.single;
    expect(request.uri.origin, 'https://api.screenscraper.fr');
    expect(request.uri.path, '/api2/jeuInfos.php');
    expect(request.queryParameters, {
      'devid': 'fixture-dev',
      'devpassword': 'fixture-dev-secret',
      'softname': 'R-Shop-fixture',
      'ssid': 'fixture-user',
      'sspassword': 'fixture-user-secret',
      'output': 'json',
      'systemeid': '4',
      'gameid': '42',
    });
    expect(request.followRedirects, isFalse);
    expect(MetadataRecord.fromJson(record.toJson()).toJson(), record.toJson());
    expect(jsonEncode(record.toJson()), isNot(contains('fixture-user')));
    provider.close();
  });

  test(
      'maps only supported canonical app systems and rejects unknown before network',
      () async {
    final provider = _provider(_Wire(null));
    final supported =
        SystemModel.supportedSystems.map((system) => system.id).toSet();
    expect(ScreenScraperProvider.platformIds.keys.every(supported.contains),
        isTrue);
    expect(ScreenScraperProvider.platformIds['snes'], 4);
    expect(ScreenScraperProvider.platformIds['psx'], 57);
    expect(ScreenScraperProvider.platformIds['megadrive'], 1);
    expect((await provider.lookup(_request(platform: 'xbox'))).status,
        MetadataLookupStatus.unsupportedPlatform);
  });

  test(
      'setup is explicit and no credentials are required for offline construction',
      () async {
    final wire = _Wire(null);
    final result = await _provider(wire, configured: false).lookup(_request());
    expect(result.status, MetadataLookupStatus.setupRequired);
    expect(wire.requests, isEmpty);
  });

  test('wrong platform and mismatched verified ID are rejected', () async {
    for (final game in [_game(system: '3'), _game(id: '99')]) {
      final result = await _provider(_Wire({
        'response': {'jeu': game}
      })).lookup(_request());
      expect(result.status, MetadataLookupStatus.unmatched);
      expect(result.record, isNull);
    }
  });

  test(
      'title localization is reviewable but ambiguity does not publish metadata',
      () async {
    final wire = _Wire({
      'response': {
        'jeux': [_game(), _game(id: '99')]
      }
    });
    final result = await _provider(wire).lookup(
        _request(verifiedProviderGameId: null, title: 'Fixture: Adventure!'));
    expect(result.status, MetadataLookupStatus.ambiguous);
    expect(result.record, isNull);
    expect(result.candidates, hasLength(2));
    expect(wire.requests.single.uri.path, '/api2/jeuRecherche.php');
    final localized = await _provider(_Wire({
      'response': {
        'jeux': [_game()]
      }
    })).lookup(
        _request(verifiedProviderGameId: null, title: 'Fixture Monogatari'));
    expect(localized.status, MetadataLookupStatus.needsReview);
    expect(localized.candidates.single.titleMatched, isTrue);
  });

  test(
      'requested conflicting release remains unresolved even with verified game ID',
      () async {
    final result = await _provider(_Wire({
      'response': {'jeu': _game()}
    })).lookup(_request(region: 'jp'));
    expect(result.status, MetadataLookupStatus.unmatched);
    expect(result.record, isNull);
  });

  test('unique regional official title excludes fuzzy search neighbours',
      () async {
    final exact = _game()..['notgame'] = 'false';
    final neighbour = _game(id: '99')
      ..['noms'] = [
        {'region': 'us', 'text': 'Fixture Adventure 2'}
      ];
    final provider = _provider(_Wire({
      'response': {
        'jeux': [neighbour, exact]
      }
    }));
    addTearDown(provider.close);
    final result = await provider
        .lookup(_request(verifiedProviderGameId: null, region: 'us'));
    expect(result.status, MetadataLookupStatus.matched);
    expect(result.record!.providerGameId, '42');
    expect(result.record!.matchMethod, 'exactRegionalOfficialTitle');
    expect(result.officialRomEvidence, isNull,
        reason: 'Title confidence is not cryptographic classification proof.');
  });

  test(
      'regional title confidence keeps conflicts and unknown editions reviewable',
      () async {
    final exact = _game()..['notgame'] = 'false';
    final duplicate = _game(id: '99')..['notgame'] = 'false';
    for (final request in [
      _request(verifiedProviderGameId: null),
      _request(verifiedProviderGameId: null, region: 'jp'),
      _request(verifiedProviderGameId: null, region: 'us', tags: {'unknown'}),
      _request(verifiedProviderGameId: null, region: 'us', tags: {'T-Eng'}),
      _request(verifiedProviderGameId: null, region: 'us', revision: 'Rev 1'),
    ]) {
      final provider = _provider(_Wire({
        'response': {
          'jeux': [exact]
        }
      }));
      final result = await provider.lookup(request);
      provider.close();
      expect(result.record, isNull);
    }
    final provider = _provider(_Wire({
      'response': {
        'jeux': [exact, duplicate]
      }
    }));
    addTearDown(provider.close);
    expect(
        (await provider
                .lookup(_request(verifiedProviderGameId: null, region: 'us')))
            .status,
        MetadataLookupStatus.ambiguous);
  });

  test('regional search does not require omitted raw-classification fields',
      () async {
    for (final notGame in [null, false, true]) {
      // Real jeuRecherche omits ROM/notgame fields; these are required to infer
      // unknown raw classification, not to match an already official edition.
      final game = _game()..remove('rom');
      if (notGame != null) game['notgame'] = notGame;
      final api = _provider(_Wire({
        'response': {
          'jeux': [game]
        }
      }));
      final result = await api
          .lookup(_request(verifiedProviderGameId: null, region: 'us'));
      api.close();
      expect(result.record != null, notGame != true);
      expect(result.officialRomEvidence, isNull);
    }
  });

  test('title confidence cannot override raw conflicts or truncated search',
      () async {
    final exact = _game()..['notgame'] = 'false';
    final truncated = _provider(_Wire({
      'response': {
        'jeux': [
          exact,
          for (var n = 0; n < 29; n++)
            _game(id: '${100 + n}')
              ..['noms'] = [
                {'region': 'us', 'text': 'Neighbour $n'}
              ]
        ]
      }
    }));
    addTearDown(truncated.close);
    expect(
        (await truncated
                .lookup(_request(verifiedProviderGameId: null, region: 'us')))
            .record,
        isNull);
    final rawConflict = _provider(_Wire({
      'response': {'jeu': exact}
    }));
    addTearDown(rawConflict.close);
    expect(
        (await rawConflict.lookup(_request(
                verifiedProviderGameId: null,
                region: 'us',
                identifier: const MetadataRomIdentifier(
                    kind: RomIdentifierKind.rawRom,
                    filename: 'Fixture.sfc',
                    sizeBytes: 1024,
                    md5: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'))))
            .record,
        isNull);
  });

  test('container checksum is never sent as raw-ROM identifier', () async {
    final wire = _Wire({
      'response': {
        'jeux': [_game()]
      }
    });
    final result = await _provider(wire).lookup(_request(
        verifiedProviderGameId: null,
        identifier: const MetadataRomIdentifier(
            kind: RomIdentifierKind.container,
            filename: 'Fixture.chd',
            sizeBytes: 1024,
            crc32: 'ABCDEF12')));
    expect(result.status, MetadataLookupStatus.needsReview);
    final query = wire.requests.single.queryParameters;
    expect(query.containsKey('crc'), isFalse);
    expect(query.containsKey('romtaille'), isFalse);
    expect(query.containsKey('romnom'), isFalse);
  });

  test(
      'unverified candidate offers a sanitized cover selector without publishing facts',
      () async {
    final game = _game();
    game['medias'] = [
      {'type': 'box-2D', 'region': 'us', 'url': _authenticatedMedia()}
    ];
    final wire = _Wire({
      'response': {
        'jeux': [game]
      }
    });
    final provider = _provider(wire);
    addTearDown(provider.close);
    final result =
        await provider.lookup(_request(verifiedProviderGameId: null));
    expect(result.status, MetadataLookupStatus.needsReview);
    expect(result.record, isNull);
    final media = result.candidates.single.previewMedia!;
    expect(result.candidates.single.previewDescriptions.single.text,
        'Synthetic adventure description.');
    expect(result.candidates.single.previewDescriptions.single.language, 'en');
    expect(media.url, isNull);
    expect(media.providerReference!.providerGameId, '42');
    expect(media.providerReference!.providerPlatformId, 4);
    expect(media.providerReference!.mediaSelector, 'box-2D(us)');
    expect(jsonEncode(media.toJson()), isNot(contains('fixture-user')));
    expect(wire.requests, hasLength(1),
        reason: 'parsing adds no game/image requests');
  });

  test('known container extension cannot be mislabeled as a raw ROM', () async {
    final wire = _Wire({
      'response': {
        'jeux': [_game()]
      }
    });
    final result = await _provider(wire).lookup(_request(
        verifiedProviderGameId: null,
        identifier: const MetadataRomIdentifier(
            kind: RomIdentifierKind.rawRom,
            filename: 'Fixture.zip',
            sizeBytes: 1024,
            crc32: 'ABCDEF12')));
    expect(result.status, MetadataLookupStatus.needsReview);
    expect(wire.requests.single.queryParameters.containsKey('crc'), isFalse);
  });

  test('malformed raw hash and path names do not reach the provider', () async {
    for (final identifier in [
      const MetadataRomIdentifier(
          kind: RomIdentifierKind.rawRom,
          filename: 'Fixture.sfc',
          sizeBytes: 1024,
          crc32: 'not-a-crc'),
      const MetadataRomIdentifier(
          kind: RomIdentifierKind.rawRom,
          filename: '../Fixture.sfc',
          sizeBytes: 1024,
          crc32: 'ABCDEF12'),
    ]) {
      final wire = _Wire(null);
      final result = await _provider(wire).lookup(
          _request(verifiedProviderGameId: null, identifier: identifier));
      expect(result.status, MetadataLookupStatus.invalidRequest);
      expect(wire.requests, isEmpty);
    }
  });

  test('compatible raw-ROM evidence must match returned hash and size',
      () async {
    final wire = _Wire({
      'response': {'jeu': _game()}
    });
    final request = _request(
        verifiedProviderGameId: null,
        identifier: const MetadataRomIdentifier(
            kind: RomIdentifierKind.rawRom,
            filename: 'Fixture.sfc',
            sizeBytes: 1024,
            crc32: 'abcdef12'));
    final result = await _provider(wire).lookup(request);
    expect(result.status, MetadataLookupStatus.matched);
    expect(wire.requests.single.queryParameters['crc'], 'ABCDEF12');
    expect(wire.requests.single.queryParameters['romtype'], 'rom');
    final wrong = _game();
    (wrong['rom'] as Map)['romcrc'] = '11111111';
    final rejected = await _provider(_Wire({
      'response': {'jeu': wrong}
    })).lookup(request);
    expect(rejected.status, MetadataLookupStatus.unmatched);
  });

  test('exact ROM and explicit unmodified flags resolve unclassified release',
      () async {
    final game = _game();
    game['notgame'] = false;
    (game['rom'] as Map).addAll(<String, String>{
      'demo': '0',
      'unl': '0',
      'beta': '0',
      'romsha1': 'a' * 40
    });
    final api = _provider(_Wire({
      'response': {'jeu': game}
    }));
    addTearDown(api.close);
    final result = await api.lookup(_request(
        tags: {},
        verifiedProviderGameId: null,
        identifier: MetadataRomIdentifier(
            kind: RomIdentifierKind.rawRom,
            filename: 'Fixture.sfc',
            sizeBytes: 1024,
            sha1: 'a' * 40)));
    expect(result.status, MetadataLookupStatus.matched);
    expect(result.record!.matchMethod, 'rawRomHashAndSize');
    expect(result.officialRomEvidence!.kind, 'exactRomOfficialRelease');
  });

  test('classification requires every positive flag and exact ROM evidence',
      () async {
    for (final boundary in [
      'missingFlag',
      'modifiedFlag',
      'notGame',
      'missingNotGame',
      'titleOnly',
      'translation',
      'hack',
      'base',
      'crcOnly',
      'zeroHash'
    ]) {
      final game = _game();
      if (boundary != 'missingNotGame') game['notgame'] = boundary == 'notGame';
      (game['rom'] as Map).addAll(<String, String>{
        'demo': '0',
        'unl': '0',
        'beta': '0',
        'romsha1': 'a' * 40
      });
      if (boundary == 'missingFlag') (game['rom'] as Map).remove('beta');
      if (boundary == 'modifiedFlag') (game['rom'] as Map)['trad'] = '1';
      if (boundary == 'zeroHash') (game['rom'] as Map)['romsha1'] = '0' * 40;
      final api = _provider(_Wire({
        'response': boundary == 'titleOnly'
            ? {
                'jeux': [game]
              }
            : {'jeu': game}
      }));
      addTearDown(api.close);
      final result = await api.lookup(_request(
          tags: boundary == 'translation'
              ? {'T-Eng'}
              : boundary == 'hack'
                  ? {'Hack'}
                  : {},
          verifiedProviderGameId: null,
          baseProviderGameId: boundary == 'base' ? '42' : null,
          identifier: boundary == 'titleOnly'
              ? null
              : MetadataRomIdentifier(
                  kind: RomIdentifierKind.rawRom,
                  filename: 'Fixture.sfc',
                  sizeBytes: 1024,
                  crc32: boundary == 'crcOnly' ? 'ABCDEF12' : null,
                  sha1: boundary == 'crcOnly'
                      ? null
                      : (boundary == 'zeroHash' ? '0' : 'a') * 40)));
      expect(result.status, MetadataLookupStatus.needsReview, reason: boundary);
      expect(result.record, isNull, reason: boundary);
    }
  });

  test('large ISO SHA-1 match records the provider capped-size limitation',
      () async {
    final game = _game(system: '58');
    (game['rom'] as Map).addAll(<String, String>{
      'romsize': '2147483647',
      'romsha1': 'b' * 40,
    });
    final wire = _Wire({
      'response': {'jeu': game}
    });
    final api = _provider(wire);
    addTearDown(api.close);
    final result = await api.lookup(_request(
        platform: 'ps2',
        verifiedProviderGameId: null,
        identifier: MetadataRomIdentifier(
            kind: RomIdentifierKind.rawIso,
            filename: 'Fixture.iso',
            sizeBytes: 4440719360,
            sha1: 'b' * 40)));
    expect(result.status, MetadataLookupStatus.matched);
    expect(result.record!.matchMethod, 'rawRomSha1AndCappedSize');
    expect(result.candidates.single.evidence, 'rawRomSha1AndCappedSize');
    expect(result.message, contains('size'));
    expect(wire.requests.single.queryParameters['romtaille'], '4440719360');
  });

  test('capped size never excuses a weaker hash or conflicting evidence',
      () async {
    for (final failure in [
      'crcOnly',
      'md5Only',
      'wrongSha1',
      'wrongMd5',
      'rawRom',
      'wrongSize',
      'smallIso',
      'wrongPlatform',
      'unknownTags',
      'hack',
      'zeroSha1'
    ]) {
      final game = _game(system: failure == 'wrongPlatform' ? '61' : '58');
      (game['rom'] as Map).addAll(<String, String>{
        'romsize': failure == 'wrongSize' ? '2147483646' : '2147483647',
        'romsha1': failure == 'wrongSha1'
            ? 'c' * 40
            : failure == 'zeroSha1'
                ? '0' * 40
                : 'b' * 40,
        'rommd5': failure == 'wrongMd5' ? 'c' * 32 : 'a' * 32,
        'hack': failure == 'hack' ? '1' : '0',
      });
      final api = _provider(_Wire({
        'response': {'jeu': game}
      }));
      addTearDown(api.close);
      final result = await api.lookup(_request(
          platform: 'ps2',
          verifiedProviderGameId: null,
          tags: failure == 'unknownTags' ? {} : {'official'},
          identifier: MetadataRomIdentifier(
              kind: failure == 'rawRom'
                  ? RomIdentifierKind.rawRom
                  : RomIdentifierKind.rawIso,
              filename: 'Fixture.iso',
              sizeBytes: failure == 'smallIso' ? 1024 : 4440719360,
              crc32: failure == 'crcOnly' ? 'ABCDEF12' : null,
              md5: {'md5Only', 'wrongMd5'}.contains(failure) ? 'a' * 32 : null,
              sha1: {'crcOnly', 'md5Only'}.contains(failure)
                  ? null
                  : failure == 'zeroSha1'
                      ? '0' * 40
                      : 'b' * 40)));
      expect(result.record, isNull, reason: failure);
      expect(
          result.status,
          {'unknownTags', 'hack'}.contains(failure)
              ? MetadataLookupStatus.needsReview
              : MetadataLookupStatus.unmatched,
          reason: failure);
    }
  });

  test('reviewed game ID cannot override supplied raw release evidence',
      () async {
    final raw = MetadataRomIdentifier(
        kind: RomIdentifierKind.rawRom,
        filename: 'Fixture.sfc',
        sizeBytes: 1024,
        crc32: 'ABCDEF12',
        md5: 'a' * 32,
        sha1: 'b' * 40);
    for (final wrongField in ['romcrc', 'rommd5', 'romsha1', 'romsize', 'id']) {
      final game = _game();
      (game['rom'] as Map)
          .addAll(<String, String>{'rommd5': 'a' * 32, 'romsha1': 'b' * 40});
      if (wrongField == 'id') {
        game['id'] = '99';
      } else {
        (game['rom'] as Map)[wrongField] = switch (wrongField) {
          'romcrc' => '11111111',
          'rommd5' => 'c' * 32,
          'romsha1' => 'd' * 40,
          _ => '2048'
        };
      }
      final wire = _Wire({
        'response': {'jeu': game}
      });
      final api = _provider(wire);
      addTearDown(api.close);
      final result = await api.lookup(_request(identifier: raw));
      expect(result.status, MetadataLookupStatus.unmatched, reason: wrongField);
      expect(result.record, isNull);
    }
  });

  test('exact raw release resolves revision without an ID-only ROM request',
      () async {
    const raw = MetadataRomIdentifier(
        kind: RomIdentifierKind.rawRom,
        filename: 'Fixture (Rev 1).sfc',
        sizeBytes: 1024,
        crc32: 'ABCDEF12');
    for (final id in [null, '42']) {
      final wire = _Wire({
        'response': {'jeu': _game()}
      });
      final api = _provider(wire);
      addTearDown(api.close);
      final result = await api.lookup(_request(
          verifiedProviderGameId: id,
          identifier: raw,
          revision: 'Rev 1',
          region: 'USA',
          language: 'en'));
      expect(result.status, MetadataLookupStatus.matched);
      expect(result.record!.matchMethod, 'rawRomHashAndSize');
      expect(
          wire.requests.single.queryParameters.containsKey('gameid'), isFalse);
      expect(wire.requests.single.queryParameters['crc'], 'ABCDEF12');
      expect(wire.requests.single.queryParameters['romtaille'], '1024');
      expect(wire.requests.single.uri.path, '/api2/jeuInfos.php');
    }
    final api = _provider(_Wire({
      'response': {'jeu': _game()}
    }));
    addTearDown(api.close);
    final unresolved = await api.lookup(_request(revision: 'Rev 1'));
    expect(unresolved.status, MetadataLookupStatus.needsReview);
    expect(unresolved.record, isNull);
  });

  test('base rating is not assigned to hacks, translations or unknown editions',
      () async {
    for (final tags in [
      <String>{'hack'},
      <String>{'T-Eng'},
      <String>{}
    ]) {
      final result = await _provider(_Wire({
        'response': {'jeu': _game()}
      })).lookup(_request(tags: tags, baseProviderGameId: '42'));
      expect(result.record, isNull);
      expect(result.status, MetadataLookupStatus.needsReview);
    }
  });

  test('credential-bearing media references are not persisted', () async {
    final game = _game();
    (game['medias'] as List).add({
      'type': 'box-2D',
      'url':
          'https://api.screenscraper.fr/api2/mediaJeu.php?ssid=fixture-user&sspassword=fixture-user-secret'
    });
    final result = await _provider(_Wire({
      'response': {'jeu': game}
    })).lookup(_request());
    expect(result.record!.media, hasLength(2));
    expect(jsonEncode(result.record!.toJson()),
        isNot(contains('fixture-user-secret')));
  });

  test(
      'authenticated artwork persists a typed reference without URL or credentials',
      () async {
    final game = _game();
    (game['medias'] as List)
        .add({'type': 'box-2D', 'region': 'us', 'url': _authenticatedMedia()});
    final wire = _Wire({
      'response': {'jeu': game}
    });
    final result = await _provider(wire).lookup(_request());
    expect(result.status, MetadataLookupStatus.matched);
    expect(result.record!.media, hasLength(3));
    final media = result.record!.media.last;
    expect(media.url, isNull);
    expect(media.providerReference!.providerId, 'screenscraper');
    expect(media.providerReference!.providerGameId, '42');
    expect(media.providerReference!.providerPlatformId, 4);
    expect(media.providerReference!.mediaType, 'box-2D');
    expect(media.providerReference!.region, 'us');
    final persisted = jsonEncode(result.record!.toJson());
    for (final forbidden in [
      'fixture-user',
      'fixture-dev',
      'ssid',
      'sspassword',
      'devid',
      'devpassword',
      'mediaJeu.php'
    ]) {
      expect(persisted, isNot(contains(forbidden)));
    }
    final restored = MetadataRecord.fromJson(result.record!.toJson());
    expect(restored.media.last.toJson(), media.toJson());
    expect(restored.media.first.url,
        'https://www.screenscraper.fr/image/fixture.png');
    expect(wire.requests, hasLength(1),
        reason: 'No media body is fetched here');
  });

  test('live media shard keeps identity without retaining credentials',
      () async {
    final game = _game();
    game['medias'] = [
      {
        'type': 'box-2D',
        'region': 'us',
        'url': Uri.parse(_authenticatedMedia())
            .replace(host: 'neoclone.screenscraper.fr')
            .toString(),
      }
    ];
    final wire = _Wire({
      'response': {'jeu': game}
    });
    final provider = _provider(wire);
    addTearDown(provider.close);
    final result = await provider.lookup(_request());
    expect(result.record!.media, hasLength(1));
    final media = result.record!.media.single;
    expect(media.url, isNull);
    expect(media.providerReference!.mediaSelector, 'box-2D(us)');
    final persisted = jsonEncode(media.toJson());
    expect(persisted, isNot(contains('fixture-dev-secret')));
    expect(persisted, isNot(contains('fixture-user-secret')));
    expect(persisted, isNot(contains('neoclone')));
    expect(wire.requests, hasLength(1));
  });

  test('unrecognized media shards cannot become provider references', () async {
    for (final host in [
      'neoclone.screenscraper.fr.attacker.invalid',
      'attacker.screenscraper.fr',
      'neoclone-screenscraper.fr',
    ]) {
      final game = _game();
      game['medias'] = [
        {
          'type': 'box-2D',
          'region': 'us',
          'url':
              Uri.parse(_authenticatedMedia()).replace(host: host).toString(),
        }
      ];
      final provider = _provider(_Wire({
        'response': {'jeu': game}
      }));
      final result = await provider.lookup(_request());
      expect(result.record!.media, isEmpty);
      provider.close();
    }
  });

  test(
      'documented grouped media objects retain covers, screenshots and member identity',
      () async {
    final game = _game();
    game['medias'] = {
      'media_screenshot': 'https://www.screenscraper.fr/image/screen.png',
      'media_boitiers': {
        'media_boitiers_2d': {
          'media_boitier_2d_us': _authenticatedMedia(),
        }
      },
      'media_wheels': {
        'media_wheel_wor': _authenticatedMedia(media: 'wheel(wor)')
      },
      'media_supports': {
        'media_supports_2d': {
          'media_support_2d_eu2': _authenticatedMedia(media: 'support-2D(eu2)'),
        }
      },
      'undocumented': {'media_boitier_2d_us': _authenticatedMedia()},
    };
    final result = await _provider(_Wire({
      'response': {'jeu': game}
    })).lookup(_request());
    expect(result.record!.media, hasLength(4));
    expect(result.record!.media.map((media) => media.type),
        containsAll(['ss', 'box-2D', 'wheel', 'support-2D']));
    final support =
        result.record!.media.singleWhere((media) => media.type == 'support-2D');
    expect(support.providerReference!.region, 'eu');
    expect(support.providerReference!.memberIndex, 2);
    expect(support.providerReference!.mediaSelector, 'support-2D(eu2)');
    expect(jsonEncode(result.record!.toJson()),
        isNot(contains('fixture-user-secret')));
  });

  test(
      'media references reject other endpoints, identities and ambiguous selectors',
      () async {
    final valid = _authenticatedMedia();
    final badUrls = [
      valid.replaceFirst(
          'api.screenscraper.fr', 'api.screenscraper.fr.evil.example'),
      valid.replaceFirst('/api2/mediaJeu.php', '/api2/botNote.php'),
      valid.replaceFirst('https:', 'http:'),
      valid.replaceFirst('api.screenscraper.fr', 'api.screenscraper.fr:444'),
      '$valid&jeuid=99',
      '$valid&media=ss',
      '$valid#fragment',
      _authenticatedMedia(gameId: '99'),
      _authenticatedMedia(platformId: '3'),
      _authenticatedMedia(media: 'ss'),
      _authenticatedMedia(media: 'box-2D(jp)'),
      _authenticatedMedia(media: 'box-2D(us)&ssid=secret'),
      valid.replaceFirst('/api2/mediaJeu.php', '/api2/mediaJeu.php/extra'),
    ];
    for (final url in badUrls) {
      final game = _game();
      game['medias'] = [
        {'type': 'box-2D', 'region': 'us', 'url': url}
      ];
      final result = await _provider(_Wire({
        'response': {'jeu': game}
      })).lookup(_request());
      expect(result.status, MetadataLookupStatus.matched);
      expect(result.record!.media, isEmpty);
    }
  });

  for (final status in [401, 403, 423, 426, 429, 430, 431, 500]) {
    test('HTTP $status becomes an actionable sanitized state without retry',
        () async {
      final wire = _Wire('fixture-user-secret in provider diagnostic',
          status: status,
          headers: {
            'retry-after': ['120']
          });
      final result = await _provider(wire).lookup(_request());
      expect(
          result.status,
          switch (status) {
            401 => MetadataLookupStatus.authenticationRequired,
            403 || 426 => MetadataLookupStatus.developerAccessRequired,
            429 => MetadataLookupStatus.throttled,
            430 || 431 => MetadataLookupStatus.quotaExceeded,
            _ => MetadataLookupStatus.unavailable,
          });
      expect(
          '${result.message} $result', isNot(contains('fixture-user-secret')));
      expect(wire.requests, hasLength(1));
      if (status == 429) {
        expect(result.retryAfter, const Duration(seconds: 120));
      }
    });
  }

  test('transport exception cannot expose credential query strings', () async {
    final wire = _Wire(null)..fail = true;
    final result = await _provider(wire).lookup(_request());
    expect(result.status, MetadataLookupStatus.unavailable);
    expect('${result.message} $result', isNot(contains('fixture-dev-secret')));
    expect('${result.message} $result', isNot(contains('sspassword')));
  });

  test('provider HTTP-date retry guidance is returned without sleeping',
      () async {
    final wire = _Wire('', status: 429, headers: {
      'retry-after': ['Tue, 08 Sep 2026 00:02:00 GMT']
    });
    final result = await _provider(wire).lookup(_request());
    expect(result.retryAfter, const Duration(minutes: 2));
    expect(wire.requests, hasLength(1));
  });

  test('malformed JSON is a sanitized invalid response', () async {
    final result = await _provider(_Wire('<html>fixture-user-secret</html>'))
        .lookup(_request());
    expect(result.status, MetadataLookupStatus.invalidResponse);
    expect(result.message, isNot(contains('fixture-user-secret')));
  });

  test('oversized response cannot create an unbounded metadata record',
      () async {
    final wire = _Wire('x' * (ScreenScraperProvider.maxResponseBytes + 1));
    final result = await _provider(wire).lookup(_request());
    expect(result.status, MetadataLookupStatus.invalidResponse);
    expect(result.record, isNull);
  });

  test('cancellation follows the transport event and cannot return a record',
      () async {
    final wire = _Wire(null)..started = Completer<void>();
    final token = CancelToken();
    final pending = _provider(wire).lookup(_request(), cancelToken: token);
    await wire.started!.future;
    token.cancel();
    final result = await pending;
    expect(result.status, MetadataLookupStatus.cancelled);
    expect(result.record, isNull);
  });
}
