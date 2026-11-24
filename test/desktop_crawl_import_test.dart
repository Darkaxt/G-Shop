import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/providers/metadata_providers.dart';
import 'package:g_shop/services/library_store.dart';
import 'package:g_shop/services/metadata/metadata_artwork_cache.dart';
import 'package:g_shop/services/metadata/catalogue_publisher.dart';
import 'package:g_shop/services/metadata/metadata_credentials.dart';
import 'package:g_shop/services/metadata/metadata_provider.dart';
import 'package:g_shop/services/metadata/desktop_archive_evidence.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';
import 'package:g_shop/services/metadata/shared_metadata_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'metadata_controls_test.dart'
    show controlsDatabase, ControlsArtworkProvider, MemorySecrets;

class OfflineDesktopProvider extends ControlsArtworkProvider
    implements MetadataAccessProvider {
  int accessCalls = 0;
  @override
  Future<MetadataLookupResult> checkAccess({CancelToken? cancelToken}) async {
    accessCalls++;
    return MetadataLookupResult(
        status: MetadataLookupStatus.setupRequired,
        message: 'This import must use its captured Windows response');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final preparedRoot = Platform.environment['GSHOP_DESKTOP_PREPARATION'];
  final capturedCensus = Platform.environment['GSHOP_DESKTOP_CENSUS'];
  test(
      'actual prepared batches match captured canonical owners and artifact proof',
      () async {
    final manifestFiles = Directory(preparedRoot!)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.zip'))
        .toList();
    final entries = <Map>[];
    for (final file in manifestFiles) {
      final zip = ZipDecoder().decodeBytes(await file.readAsBytes());
      final manifest = jsonDecode(
          utf8.decode(zip.findFile('packaging.json')!.content as List<int>));
      expect(manifest['kind'], 'desktopArchiveEvidence');
      expect((manifest['games'] as List).length, inInclusiveRange(1, 25));
      entries.addAll((manifest['games'] as List).cast<Map>());
    }
    final games = <String, Map>{}, editions = <String, Map>{};
    await for (final line in File(capturedCensus!)
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final row = jsonDecode(line);
      if (row['kind'] == 'game')
        games[row['record']['id'] as String] = row['record'] as Map;
      if (row['kind'] == 'edition')
        editions[row['record']['id'] as String] = row['record'] as Map;
    }
    expect(entries, isNotEmpty);
    final uncaptured = <Map<String, dynamic>>[];
    for (final entry in entries) {
      expect(
          entry['identityKey'],
          LibraryStore.metadataIdentity({
            'game_json': jsonEncode(games[entry['gameId']]),
            'edition_json': jsonEncode(editions[entry['editionId']])
          }, providerId: 'screenscraper'));
      final raw = DesktopArchiveEvidence.validate(
          RemoteArtifact.fromJson(entry['artifact']),
          entry['platformId'] as String,
          entry['observation'] as Map);
      expect(raw.kind, RomIdentifierKind.rawRom);
      if (entry['lookup'] != null) {
        final response = DesktopArchiveEvidence.validateLookup(entry['lookup'],
            gameId: entry['gameId'],
            editionId: entry['editionId'],
            platform: entry['platformId'],
            raw: raw);
        expect(response.record!.ratings, isEmpty);
        final retained = {
          for (final outcome in entry['lookup']['artworkOutcomes'] as List)
            MetadataArtworkCache.key(MetadataMedia.fromJson(
                (outcome['media'] as Map).cast<String, dynamic>()))
        };
        final selected = MetadataArtworkCache.displayMedia(response.record!,
            regions: EditionIdentity.fromJson(
                    (editions[entry['editionId']]!).cast<String, dynamic>())
                .regions,
            includePhysicalLabel: true,
            includePackaging: true,
            includeVideo: true);
        for (final media in selected.where((m) => {
              'box-2D',
              'box-2D-back',
              'box-2D-side',
              'box-texture',
              'support-texture'
            }.contains(m.type))) {
          if (!retained.contains(MetadataArtworkCache.key(media))) {
            uncaptured.add({
              'editionId': entry['editionId'],
              'regions': editions[entry['editionId']]!['regions'],
              'capturedRequest': entry['lookup']['request'],
              'media': media.toJson(),
            });
          }
        }
      }
    }
    if (uncaptured.isNotEmpty) {
      // These advertised/derived selectors were never attempted by the desktop
      // crawl. They are gaps for fresh acquisition, not negative outcomes and
      // not part of this explicit offline import's artwork scope.
      // ignore: avoid_print
      print('Unattempted selected roles retained as gaps: '
          '${jsonEncode(uncaptured)}');
    }
  },
      skip: preparedRoot == null || capturedCensus == null
          ? 'Explicit private prepared-batch inputs only'
          : false);
  for (final scenario in [
    'valid',
    'changed artifact',
    'damaged image',
    'modified edition',
    'wrong media platform',
    'prepared response',
    'prepared wrong ROM',
    'prepared wrong game',
    'prepared rating',
    'prepared damaged outcome',
    'prepared missing response'
  ]) {
    test('desktop resource import: $scenario', () async {
      SharedPreferences.setMockInitialValues({});
      final root =
          await Directory.systemTemp.createTemp('gshop-desktop-import-');
      final db = await controlsDatabase();
      final artifact = RemoteArtifact(
          id: RemoteArtifactId(
              providerId: 'drive',
              sourceId: 'source',
              accountId: 'account',
              providerFileId: 'file'),
          displayName: 'Game.7z',
          displayPath: 'Game.7z',
          sizeBytes: 100,
          version: '1',
          canDownload: true,
          providerChecksums: {'md5': 'a' * 32, 'sha256': 'b' * 64});
      await db.update(
          'games',
          {
            'systemSlug': 'gba',
            'filename': 'Game.7z',
            'artifact_key': artifact.id.key,
            'remote_artifact': jsonEncode(artifact.toJson())
          },
          where: 'id=1');
      final editionId = (await db.transaction((txn) =>
              LibraryStore.catalogueEditions(txn, cacheRowId: 1).toList()))
          .single;
      final library = LibraryStore(Future.value(db));
      final edition = (await library.edition(editionId))!;
      final game = (await library.game(edition.gameId))!;
      final identity = {
        'game_json': jsonEncode(game.toJson()),
        'edition_json': jsonEncode(edition.toJson())
      };
      final raw = MetadataRomIdentifier(
          kind: RomIdentifierKind.rawRom,
          filename: 'Game.gba',
          sizeBytes: 200,
          md5: 'c' * 32,
          sha1: 'd' * 40);
      final media = [
        for (final role in ['box-2D', 'support-texture'])
          MetadataMedia(
              type: role,
              region: 'us',
              memberIndex: role == 'support-texture' ? 1 : null,
              providerReference: ScreenScraperMediaReference(
                  providerGameId: '42',
                  providerPlatformId: 12,
                  mediaType: role,
                  region: 'us',
                  memberIndex: role == 'support-texture' ? 1 : null,
                  bracketedMemberIndex: role == 'support-texture'))
      ];
      final provider = scenario.startsWith('prepared')
          ? OfflineDesktopProvider()
          : ControlsArtworkProvider();
      MetadataMedia capturedMedia(String role) => MetadataMedia(
          type: role,
          region: role == 'box-2D-back' ? 'us' : null,
          providerReference: ScreenScraperMediaReference(
              providerGameId: '42',
              providerPlatformId: 12,
              mediaType: role,
              region: role == 'box-2D-back' ? 'us' : null));
      MetadataLookupResult resultFor(MetadataLookupRequest request) {
        expect(request.romIdentifier!.toJson(), raw.toJson());
        final now = DateTime.now().toUtc();
        return MetadataLookupResult(
            status: MetadataLookupStatus.matched,
            message: 'Exact raw proof rechecked',
            record: MetadataRecord(
                gameId: request.gameId,
                editionId: request.editionId,
                platformId: 'gba',
                providerId: 'screenscraper',
                providerGameId: '42',
                refreshGeneration: request.refreshGeneration,
                retrievedAt: now,
                matchMethod: 'rawRomHashAndSize',
                titles: [
                  MetadataText(text: 'Game')
                ],
                media: [
                  ...media,
                  if (scenario.startsWith('prepared')) ...[
                    capturedMedia('box-2D-back'),
                    capturedMedia('box-texture'),
                    capturedMedia('ss'),
                    capturedMedia('fanart'),
                    capturedMedia('video')
                  ]
                ]),
            officialRomEvidence: IdentityEvidence(
                source: 'screenscraper',
                kind: 'exactRomOfficialRelease',
                value: jsonEncode({
                  'providerGameId': '42',
                  'identifier': raw.toJson(),
                  'flags': {
                    for (final key in ['hack', 'trad', 'demo', 'unl', 'beta'])
                      key: '0'
                  },
                  'notgame': false,
                  'regions': ['us'],
                  'languages': ['en'],
                  'retrievedAt': now.toIso8601String()
                })));
      }

      provider.reply = (request, _) async => resultFor(request);
      final bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==');
      final hash = sha256.convert(bytes).toString();
      final manifest = {
        'version': 1,
        'kind': 'desktopArchiveEvidence',
        'games': [
          {
            'gameId': game.id,
            'editionId': editionId,
            'platformId': 'gba',
            'identityKey': LibraryStore.metadataIdentity(identity,
                providerId: 'screenscraper'),
            'artifact': artifact.toJson(),
            'observation': {
              'container': {
                'sizeBytes': 100,
                'md5': 'a' * 32,
                'sha256': 'b' * 64
              },
              'raw': raw.toJson()
            },
            'artwork': [
              for (final m in media)
                {'media': m.toJson(), 'sha256': hash, 'bytes': bytes.length}
            ]
          }
        ]
      };
      final entry = (manifest['games'] as List).single as Map;
      final preparedResponse = scenario.startsWith('prepared');
      if (preparedResponse) {
        manifest['reuseProviderResponse'] = true;
        final captured = MetadataLookupRequest(
            gameId: game.id,
            editionId: editionId,
            platformId: 'gba',
            title: 'Game',
            romIdentifier: raw,
            refreshGeneration: 42);
        final reply = resultFor(captured);
        entry['lookup'] = {
          'request': captured.toJson(),
          'record': reply.record!.toJson(),
          'officialRomEvidence': reply.officialRomEvidence!.toJson(),
          'artworkOutcomes': [
            for (final m in media) {'media': m.toJson(), 'status': 'matched'},
            {
              'media': capturedMedia('box-2D-back').toJson(),
              'status': 'unmatched'
            }
          ]
        };
        if (scenario == 'prepared wrong ROM') {
          entry['lookup']['request']['romIdentifier']['md5'] = 'e' * 32;
        } else if (scenario == 'prepared wrong game') {
          entry['lookup']['record']['providerGameId'] = '99';
        } else if (scenario == 'prepared rating') {
          entry['lookup']['record']['ratings'] = [
            {'injected': true}
          ];
        } else if (scenario == 'prepared damaged outcome') {
          entry['lookup']['artworkOutcomes'].last['status'] = 'matched';
        } else if (scenario == 'prepared missing response') {
          entry.remove('lookup');
        }
      }
      if (scenario == 'changed artifact') {
        entry['artifact'] = {...artifact.toJson(), 'version': '2'};
      } else if (scenario == 'damaged image') {
        (entry['artwork'] as List).first['bytes'] = bytes.length + 1;
      } else if (scenario == 'wrong media platform') {
        (entry['artwork'] as List).first['media']['providerReference']
            ['providerPlatformId'] = 3;
      } else if (scenario == 'modified edition') {
        final updated = {
          ...edition.toJson(),
          'tags': ['Hack']
        };
        await db.update(
            'library_editions', {'record_json': jsonEncode(updated)},
            where: 'edition_id=?', whereArgs: [editionId]);
        entry['identityKey'] = LibraryStore.metadataIdentity(
            {...identity, 'edition_json': jsonEncode(updated)},
            providerId: 'screenscraper');
      }
      final zip = Archive();
      final json = utf8.encode(jsonEncode(manifest));
      zip.addFile(
          ArchiveFile('packaging.json', json.length, json)..compress = false);
      zip.addFile(ArchiveFile('images/$hash.png', bytes.length, bytes)
        ..compress = false);
      final file = File('${root.path}/pack.zip');
      await file.writeAsBytes(ZipEncoder().encode(zip)!);
      final shared = await SharedMetadataStore.open(
          Directory('${root.path}/shared'),
          factory: databaseFactoryFfiNoIsolate);
      final cache = MetadataArtworkCache(Future.value(db), shared.artworkRoot,
          sharedStore: shared);
      final controls = MetadataControlsController(
          database: Future.value(db),
          providers: {'screenscraper': provider},
          screenScraperCredentials:
              ScreenScraperCredentialStore(storage: MemorySecrets()),
          igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
          sharedStore: Future.value(shared),
          artworkCache: Future.value(cache),
          catalogueChanged: () {},
          readArchiveIdentifier: (_, __, ___) =>
              throw StateError('ROM must not be downloaded again'));
      final oldJob = await MetadataRefreshJobs(Future.value(db)).create(
          providerId: 'screenscraper',
          collectionGeneration: 'preserved-existing-job',
          editionIds: [editionId]);
      final oldRows = await db.query('metadata_refresh_jobs',
          where: 'id=?', whereArgs: [oldJob.id]);
      final oldItems = await db.query('metadata_refresh_items',
          where: 'job_id=?', whereArgs: [oldJob.id]);
      if (preparedResponse) {
        await db.insert('metadata_provider_backoff', {
          'provider_id': 'screenscraper',
          'reason': 'quotaExceeded',
          'not_before':
              DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch
        });
      }
      final oldBackoff = await db.query('metadata_provider_backoff');
      addTearDown(() async {
        await controls.close();
        controls.dispose();
        await shared.close();
        await db.close();
      });
      final imported = await controls.importPackagingResources(file);
      expect(await db.query('metadata_provider_backoff'), oldBackoff);
      expect(
          await db.query('metadata_refresh_jobs',
              where: 'id=?', whereArgs: [oldJob.id]),
          oldRows);
      expect(
          await db.query('metadata_refresh_items',
              where: 'job_id=?', whereArgs: [oldJob.id]),
          oldItems);
      if (scenario != 'valid' && scenario != 'prepared response') {
        expect(imported, 0);
        expect(controls.state.error, isTrue);
        expect(provider.calls, isEmpty);
        expect(await db.query('metadata_artwork_cache'), isEmpty);
        expect(
            await Directory('${shared.root.path}/desktop-archive-evidence')
                .exists(),
            isFalse);
        return;
      }
      expect(imported, 1);
      expect(controls.state.error, isFalse);
      expect(provider.calls, hasLength(preparedResponse ? 0 : 1));
      if (provider is OfflineDesktopProvider) expect(provider.accessCalls, 0);
      expect(provider.artworkCalls, 0,
          reason: 'Prepared exact media is already cached');
      expect((await library.edition(editionId))!.tags, {'official'});
      expect(
          (await cache.artworkForEdition(editionId)).supportTexture, isNotNull);
      if (preparedResponse) {
        expect(controls.state.artworkReport!.counts['unmatched'], 1);
        final committed = (await library.metadata(editionId, 'screenscraper'))!;
        expect(committed.retrievedAt.toIso8601String(),
            entry['lookup']['record']['retrievedAt']);
        expect(committed.refreshGeneration, isNot(42));
        // A fresh runner uses the durable receipt after the first instance has
        // returned; classification and source/artwork ownership stay normal.
        final restarted = MetadataRefreshJobs(Future.value(db),
            sharedStore: Future.value(shared),
            readArchiveIdentifier: (_, __, ___) =>
                throw StateError('No archive reacquisition on resume'));
        final explicitRetry =
            await restarted.retryArtworkForMetadata(controls.state.report!.id);
        expect(explicitRetry.collectionGeneration, 'desktop-evidence-import',
            reason: 'Explicit retry acquires afresh; resume keeps its capture');
        expect(explicitRetry.counts['pending'], 1);
        final blockedRetry = await restarted.run(explicitRetry.id, provider,
            artworkCache: cache);
        expect(blockedRetry.state, 'blocked');
        expect(await db.query('metadata_provider_backoff'), oldBackoff);
        final resumed = await restarted.create(
            providerId: 'screenscraper',
            collectionGeneration: 'desktop-provider-import',
            editionIds: [editionId]);
        final completed =
            await restarted.run(resumed.id, provider, artworkCache: cache);
        expect(completed.state, 'completed');
        expect(completed.counts['matched'], 1);
        expect(provider.calls, isEmpty);
        final disconnected = MetadataRefreshJobs(Future.value(db));
        final disconnectedJob = await disconnected.create(
            providerId: 'screenscraper',
            collectionGeneration: 'desktop-provider-import',
            editionIds: [editionId]);
        await expectLater(disconnected.run(disconnectedJob.id, provider),
            throwsA(isA<FormatException>()));
        expect(provider.calls, isEmpty,
            reason: 'Missing shared evidence must not start another lookup');
      }
      final catalogue = Directory('${root.path}/catalogue');
      await CataloguePublisher(store: shared, catalogue: catalogue).publish();
      expect(
          catalogue
              .listSync(recursive: true)
              .whereType<File>()
              .map((f) => f.uri.pathSegments.last),
          containsAll(['box.png', 'cartridge.png']));
    });
  }
}
