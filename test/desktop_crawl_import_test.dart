import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/providers/metadata_providers.dart';
import 'package:g_shop/services/library_store.dart';
import 'package:g_shop/services/metadata/metadata_artwork_cache.dart';
import 'package:g_shop/services/metadata/metadata_cloud_library.dart';
import 'package:g_shop/services/metadata/metadata_credentials.dart';
import 'package:g_shop/services/metadata/metadata_provider.dart';
import 'package:g_shop/services/metadata/desktop_archive_evidence.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';
import 'package:g_shop/services/metadata/shared_metadata_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'metadata_controls_test.dart'
    show controlsDatabase, ControlsArtworkProvider, MemorySecrets;
import 'metadata_cloud_library_test.dart' show MemoryMetadataDrive;

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
    'wrong media platform'
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
      final provider = ControlsArtworkProvider();
      provider.reply = (request, _) async {
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
                titles: [MetadataText(text: 'Game')],
                media: media),
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
      };
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
      final remote = MemoryMetadataDrive();
      final cloud = MetadataCloudLibrary(
          store: shared, remote: remote, accountId: 'account', rootId: 'root');
      addTearDown(() async {
        await controls.close();
        controls.dispose();
        await cloud.close();
        await shared.close();
        await db.close();
      });
      final imported = await controls.importPackagingResources(file);
      expect(
          await db.query('metadata_refresh_jobs',
              where: 'id=?', whereArgs: [oldJob.id]),
          oldRows);
      expect(
          await db.query('metadata_refresh_items',
              where: 'job_id=?', whereArgs: [oldJob.id]),
          oldItems);
      if (scenario != 'valid') {
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
      expect(provider.calls, hasLength(1));
      expect(provider.artworkCalls, 0,
          reason: 'Prepared exact media is already cached');
      expect((await library.edition(editionId))!.tags, {'official'});
      expect(
          (await cache.artworkForEdition(editionId)).supportTexture, isNotNull);
      await cloud.open();
      await cloud.sync(Future.value(db), pull: false);
      expect(remote.files.values.map((f) => f.name),
          containsAll(['box.png', 'cartridge.png']));
    });
  }
}
