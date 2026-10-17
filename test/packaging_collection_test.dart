import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:retro_eshop/services/metadata/metadata_cloud_library.dart';
import 'package:retro_eshop/services/metadata/screenscraper_provider.dart';
import 'package:retro_eshop/providers/metadata_providers.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/shared_metadata_store.dart';
import 'metadata_cloud_library_test.dart' show MemoryMetadataDrive;
import 'metadata_controls_test.dart' show controlsDatabase, MemorySecrets;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('normal resource collection retains same-edition extra faces and pages',
      () {
    MetadataMedia media(String type, {String region = 'us', int? page}) =>
        MetadataMedia(
            type: type,
            region: region,
            memberIndex: page,
            url: 'https://example.org/$region/$type-${page ?? 0}.png');
    final record = MetadataRecord(
        gameId: 'g',
        editionId: 'e',
        platformId: 'gba',
        providerId: 'screenscraper',
        providerGameId: '42',
        retrievedAt: DateTime.utc(2026),
        refreshGeneration: 1,
        matchMethod: 'verifiedProviderId',
        titles: [],
        media: [
          media('box-2D', region: 'jp'),
          media('box-2D'),
          media('box-2D-back'),
          media('box-2D-side'),
          media('box-texture'),
          media('manual-page', page: 2),
          media('manual-page', page: 1),
          media('fanart'),
          media('box-2D-back', region: 'jp')
        ]);
    final selected = MetadataArtworkCache.displayMedia(record,
        regions: ['us'], includePackaging: true);
    expect(
        MetadataArtworkCache.displayMedia(record, regions: ['us'])
            .map((m) => m.type),
        isNot(contains('manual-page')),
        reason: 'Browsing a cover does not download a manual');
    expect(
        selected.map((m) => m.type).toSet(),
        containsAll([
          'box-2D-back',
          'box-2D-side',
          'box-texture',
          'manual-page',
          'fanart'
        ]));
    expect(selected.every((m) => m.region == 'us'), isTrue);
    expect(
        selected
            .where((m) => m.type == 'manual-page')
            .map((m) => m.memberIndex),
        [1, 2]);
  });

  test(
      'cloud resource names preserve distinct packaging roles and manual order',
      () {
    expect(MetadataCloudLibrary.resourceName('box-2D-back', 'gba'),
        'box-back.png');
    expect(MetadataCloudLibrary.resourceName('box-2D-side', 'gba'),
        'box-spine.png');
    expect(MetadataCloudLibrary.resourceName('outer-box-top', 'gba'),
        'outer-box-top.png');
    expect(MetadataCloudLibrary.resourceName('manual-page', 'gba', index: 12),
        'manual-page-012.png');
    expect(ScreenScraperProvider.imageTypes,
        containsAll(['box-2D-back', 'box-2D-side']));
  });

  test(
      'classified pack enters fresh controls, reaches Drive and reloads its gallery',
      () async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('rshop-packaging-test-');
    final db = await controlsDatabase(factory: databaseFactoryFfi);
    await LibrarySchema.install(db);
    await MetadataArtworkCache.install(db);
    final shared = await SharedMetadataStore.open(
        Directory('${root.path}/shared'),
        factory: databaseFactoryFfi);
    final library = LibraryStore(Future.value(db));
    final game = GameIdentity(
        id: 'g',
        platformId: 'gba',
        title: 'Fixture',
        matchStatus: IdentityMatchStatus.manuallyMatched);
    final edition = EditionIdentity(
        id: 'e', gameId: 'g', regions: ['us'], tags: {'official'});
    await library.putGame(game);
    await library.putEdition(edition);
    final cache = MetadataArtworkCache(Future.value(db), shared.artworkRoot,
        sharedStore: shared);
    final body = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==');
    final digest = sha256.convert(body).toString();
    final media = [
      for (final pair in [
        ('box-2D', null),
        ('box-2D-back', null),
        ('box-2D-side', null),
        ('manual-page', 1),
        ('manual-page', 2)
      ])
        MetadataMedia(
            type: pair.$1,
            region: 'us',
            memberIndex: pair.$2,
            importReference: ImportedArtworkReference(
                sourceId: 'launchbox',
                assetId: '42/face',
                sourceUrl: 'https://images.launchbox-app.com/fixture.png',
                sha256: digest))
    ];
    final identity = {
      'game_json': jsonEncode(game.toJson()),
      'edition_json': jsonEncode(edition.toJson())
    };
    final manifest = {
      'version': 1,
      'platform': 'gba',
      'games': [
        {
          'gameId': 'g',
          'editionId': 'e',
          'identityKey':
              LibraryStore.metadataIdentity(identity, providerId: 'packaging'),
          'resources': media.map((m) => m.toJson()).toList()
        }
      ]
    };
    final zip = Archive();
    final json = utf8.encode(jsonEncode(manifest));
    zip.addFile(
        ArchiveFile('packaging.json', json.length, json)..compress = false);
    zip.addFile(
        ArchiveFile('images/$digest.png', body.length, body)..compress = false);
    final pack = File('${root.path}/pack.zip');
    await pack.writeAsBytes(ZipEncoder().encode(zip)!);
    final remote = MemoryMetadataDrive();
    final cloud = MetadataCloudLibrary(
        store: shared, remote: remote, accountId: 'a', rootId: 'root');
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        catalogueChanged: () {},
        artworkCache: Future.value(cache),
        sharedStore: Future.value(shared));
    try {
      expect(controls.state.loading, isTrue);
      expect(await controls.importPackagingResources(pack), 1);
      expect(controls.state.error, isFalse);
      await cloud.open();
      await cloud.sync(Future.value(db), pull: false);
      expect(
          remote.files.values.map((f) => f.name),
          containsAll([
            'box.png',
            'box-back.png',
            'box-spine.png',
            'manual-page-001.png',
            'manual-page-002.png'
          ]));
      final gallery = await cache.galleryForEdition('e');
      expect(gallery['manual-page'], hasLength(2));
      await cloud.trim(0);
      expect(await cache.galleryForEdition('e'), isEmpty);
      final restored = await cache.galleryForEdition('e', hydrate: true);
      expect(restored['box-2D-back'], hasLength(1));
      expect(restored['manual-page'], hasLength(2));
      expect(remote.downloads, greaterThan(0));
      expect((await library.metadata('e', 'packaging'))!.ratings, isEmpty);
      expect((await library.edition('e'))!.regions, ['us']);
    } finally {
      await controls.close();
      await cloud.close();
      await shared.close();
      await db.close();
      await root.delete(recursive: true);
    }
  });
}
