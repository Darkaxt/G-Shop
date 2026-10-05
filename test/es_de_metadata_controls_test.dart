import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/providers/metadata_providers.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/metadata/shared_metadata_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'metadata_controls_test.dart'
    show controlsDatabase, ControlsArtworkProvider, MemorySecrets;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  defineEsDeMetadataControlChecks();
}

/// The host and native entrypoints run this same normal controller contract.
/// A native caller may supply its newly reserved external fixture parent; no
/// owner's ES-DE directory or application database is opened here.
void defineEsDeMetadataControlChecks(
    {DatabaseFactory? factory,
    Directory? fixtureParent,
    bool nativeBinding = false,
    void Function(Map<String, Object?>)? report}) {
  if (factory == null) sqfliteFfiInit();
  final dbFactory = factory ?? databaseFactoryFfiNoIsolate;
  Future<void> check() async {
    SharedPreferences.setMockInitialValues({});
    final privateRoot =
        await Directory.systemTemp.createTemp('rshop-esde-private-');
    addTearDown(() => privateRoot.delete(recursive: true));
    final db = await controlsDatabase(
        factory: dbFactory, path: p.join(privateRoot.path, 'producer.sqlite'));
    addTearDown(db.close);
    final root = await (fixtureParent ?? Directory.systemTemp)
        .createTemp('rshop-esde-controls-');
    addTearDown(() => root.delete(recursive: true));
    final shared = await SharedMetadataStore.open(
        Directory(p.join(root.path, 'shared')),
        factory: dbFactory);
    addTearDown(shared.close);
    final artifact = RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: 'source',
            accountId: 'account',
            providerFileId: 'file'),
        displayName: 'Game 1.chd',
        displayPath: 'Game 1.chd',
        sizeBytes: 1024,
        version: '1',
        providerChecksums: {'md5': '00000000000000000000000000000001'});
    await db.update(
        'games',
        {
          'artifact_key': artifact.id.key,
          'remote_artifact': jsonEncode(artifact.toJson())
        },
        where: 'id = 1');
    final provider = ControlsArtworkProvider();
    final library = LibraryStore(Future.value(db));
    final seededEdition = (await db.transaction((txn) =>
            LibraryStore.catalogueEditions(txn, cacheRowId: 1).toList()))
        .single;
    final originalEdition = (await library.edition(seededEdition))!;
    final originalGame = (await library.game(originalEdition.gameId))!;
    await library.putEdition(EditionIdentity.fromJson({
      ...originalEdition.toJson(),
      'regions': ['USA'],
      'tags': ['official']
    }));
    await library.putGame(GameIdentity.fromJson({
      ...originalGame.toJson(),
      'matchStatus': 'manuallyMatched',
      'providerIds': {'igdb': '42'}
    }));
    var description = 'First fresh description';
    provider.reply = (request, _) async => MetadataLookupResult(
        status: MetadataLookupStatus.matched,
        message: 'Matched exact public fixture',
        record: MetadataRecord(
            gameId: request.gameId,
            editionId: request.editionId,
            platformId: request.platformId,
            providerId: 'screenscraper',
            providerGameId: '42',
            retrievedAt: DateTime.now().toUtc(),
            refreshGeneration: request.refreshGeneration,
            matchMethod: 'platformAndTitle',
            titles: [
              MetadataText(text: request.title)
            ],
            descriptions: [
              MetadataText(text: description, language: 'en')
            ],
            releaseDates: [
              const MetadataText(text: '2000-01-01', region: 'jp'),
              const MetadataText(text: '2001-02-03', region: 'us')
            ],
            media: [
              provider.media,
              provider.screenshot
            ]));
    final romRoot = Directory(p.join(root.path, 'ROMs'));
    final mediaRoot =
        await Directory(p.join(root.path, 'downloaded_media', 'psx'))
            .create(recursive: true);
    var destination = p.join(romRoot.path, 'remote');
    final target = File(p.join(root.path, 'gamelist.xml'));
    const before =
        '<gameList><!-- launcher comment --><game><path>./remote/Game 1.chd</path>'
        '<favorite>true</favorite><playcount>8</playcount><custom>untouched</custom></game></gameList>';
    await target.writeAsString(before);
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        sharedStore: Future.value(shared),
        artworkCache: Future.value(MetadataArtworkCache(
            Future.value(db), shared.artworkRoot,
            sharedStore: shared)),
        configuredTarget: (_) async => destination,
        catalogueChanged: () {});
    addTearDown(() async {
      await controls.close();
      controls.dispose();
    });
    await controls.load();
    await controls.refresh(systemSlug: 'psx');
    expect(controls.state.error, false);
    final edition = provider.calls.single.editionId;
    await controls.mapEsDeEdition(
        cacheRowId: 1,
        editionId: edition,
        romRoot: romRoot,
        gamelist: target,
        mediaRoot: mediaRoot);
    expect(controls.state.error, false);
    expect(await shared.esDePublication.pendingCount(target), 1);
    await controls.publishEsDe(target, esDeClosed: false);
    expect(controls.state.esDeReport!.status, 'esDeMustBeClosed');
    expect(await target.readAsString(), before);
    await controls.publishEsDe(target, esDeClosed: true);
    expect(controls.state.error, false);
    expect(controls.state.esDeReport!.status, 'published');
    expect(await target.readAsString(), contains('First fresh description'));
    expect(await target.readAsString(), contains('<favorite>true</favorite>'));
    expect(await target.readAsString(), contains('<custom>untouched</custom>'));
    expect(await target.readAsString(),
        contains('<releasedate>20010203T000000</releasedate>'));
    final cover =
        File(p.join(mediaRoot.path, 'covers', 'remote', 'Game 1.png'));
    expect(await cover.exists(), true,
        reason:
            'Normal remote-only publication must include validated artwork');
    final publishedCover = await cover.readAsBytes();
    expect(publishedCover, isNotEmpty);
    final screenshot =
        File(p.join(mediaRoot.path, 'screenshots', 'remote', 'Game 1.png'));
    expect(await screenshot.readAsBytes(), publishedCover,
        reason:
            'The normal selected screenshot uses the same exact ROM-relative layout');
    expect(await romRoot.exists(), false,
        reason:
            'Scraping/publication must not create ROM stubs or install state');
    final lookupCount = provider.calls.length;
    final imageCount = provider.artworkCalls;
    description = 'Second fresh description';
    await controls.refresh(systemSlug: 'psx');
    expect(await shared.esDePublication.pendingCount(target), 1,
        reason: 'Ordinary refresh queues the established mapping');
    expect(provider.calls.length, lookupCount + 1);
    destination = p.join(romRoot.path, 'changed-destination');
    await controls.publishEsDe(target, esDeClosed: true);
    expect(controls.state.esDeReport!.status, 'identityChanged');
    expect(await target.readAsString(), contains('First fresh description'));
    destination = p.join(romRoot.path, 'remote');
    await db.update('games', {'filename': 'Renamed.chd'}, where: 'id = 1');
    await controls.publishEsDe(target, esDeClosed: true);
    expect(controls.state.esDeReport!.status, 'identityChanged',
        reason: 'The expected queue destination filename must remain mapped');
    await db.update('games', {'filename': 'Game 1.chd'}, where: 'id = 1');
    await controls.publishEsDe(target, esDeClosed: true);
    expect(controls.state.esDeReport!.status, 'published');
    expect(await target.readAsString(), contains('Second fresh description'));
    expect(provider.calls.length, lookupCount + 1,
        reason: 'ES-DE publication never triggers another lookup');
    expect(provider.artworkCalls, imageCount + 2,
        reason: 'Only the requested fresh artwork generation fetches');
    expect(await cover.readAsBytes(), publishedCover);
    await cover.writeAsString('manual cover');
    await controls.publishEsDe(target, esDeClosed: true);
    expect(controls.state.esDeReport!.status, 'conflict');
    expect(await cover.readAsString(), 'manual cover',
        reason: 'A launcher/manual image must not be silently overwritten');
    await cover.writeAsBytes(publishedCover);
    await controls.reviewEsDeArtwork(editionId: edition, source: cover);
    expect(controls.state.error, false);
    await controls.reviewEsDeArtwork(editionId: edition, source: screenshot);
    expect(controls.state.error, false);
    final beforeReuse = provider.artworkCalls;
    await controls.refresh(systemSlug: 'psx');
    expect(controls.state.error, false);
    expect(provider.calls.length, lookupCount + 2,
        reason: 'Existing art never substitutes for the required fresh facts');
    expect(provider.artworkCalls, beforeReuse,
        reason: 'Exact explicitly reviewed artwork avoids a redundant body');
    await controls.publishEsDe(target, esDeClosed: true);
    expect(
        {'published', 'upToDate'}, contains(controls.state.esDeReport!.status));
    await cover.writeAsString('changed since review');
    await controls.refresh(systemSlug: 'psx');
    expect(provider.artworkCalls, beforeReuse + 1,
        reason:
            'Changed/unverified local images cannot satisfy reviewed reuse');
    final wrong =
        File(p.join(mediaRoot.path, 'covers', 'remote', 'Another game.png'));
    await wrong.writeAsBytes(publishedCover);
    await controls.reviewEsDeArtwork(editionId: edition, source: wrong);
    expect(controls.state.error, true,
        reason:
            'A plausible picture outside the exact mapped path is rejected');
    await cover.delete();
    final jpg = File('${p.withoutExtension(cover.path)}.jpg');
    final jpeg = img.encodeJpg(img.decodePng(publishedCover)!);
    await jpg.writeAsBytes(jpeg);
    await controls.reviewEsDeArtwork(editionId: edition, source: jpg);
    expect(controls.state.error, false);
    final beforeJpgReuse = provider.artworkCalls;
    await controls.refresh(systemSlug: 'psx');
    expect(provider.artworkCalls, beforeJpgReuse);
    await controls.publishEsDe(target, esDeClosed: true);
    expect(
        {'published', 'upToDate'}, contains(controls.state.esDeReport!.status));
    expect(await jpg.readAsBytes(), jpeg);
    expect(await cover.exists(), false,
        reason:
            'Reviewed JPG reuse does not claim/replace or duplicate launcher art');
    final currentEdition = (await library.edition(edition))!;
    final at = DateTime.now().toUtc();
    await library.putMetadata(MetadataRecord(
        gameId: currentEdition.gameId,
        editionId: edition,
        platformId: 'psx',
        providerId: 'igdb',
        providerGameId: '42',
        retrievedAt: at,
        refreshGeneration: 1,
        matchMethod: 'verifiedProviderIdGlobalGame',
        titles: const [
          MetadataText(text: 'Game 1')
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
        ]));
    expect(
        (await library.effectiveRatings([edition]))[edition]!
            .rating
            .normalizedValue,
        85);
    await controls.publishEsDe(target, esDeClosed: true);
    expect(await target.readAsString(), contains('<rating>0.85</rating>'),
        reason:
            'The accepted current score is shared with cards and dynamic Top');
    await target.writeAsString((await target.readAsString())
        .replaceFirst('<rating>0.85</rating>', '<rating>0.33</rating>'));
    final ratingRecord = (await library.metadata(edition, 'igdb'))!;
    await library.putMetadata(MetadataRecord.fromJson({
      ...ratingRecord.toJson(),
      'ratings': [
        {...ratingRecord.ratings.single.toJson(), 'rawValue': 86}
      ]
    }));
    await controls.publishEsDe(target, esDeClosed: true);
    expect(controls.state.esDeReport!.status, 'conflict');
    expect(controls.state.esDeReport!.conflicts.map((c) => c.field),
        contains('rating'));
    expect(await target.readAsString(), contains('<rating>0.33</rating>'),
        reason:
            'A current provider score cannot overwrite a manual launcher edit');
    expect(
        await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE '%install%'"),
        isEmpty);
    // A new private projection has no old facts, identities or artwork manifest.
    // Only the exact current remote catalogue is republished before recovery.
    final fresh = await controlsDatabase(
        factory: dbFactory, path: p.join(privateRoot.path, 'rebuilt.sqlite'));
    try {
      await fresh.update(
          'games',
          {
            'artifact_key': artifact.id.key,
            'remote_artifact': jsonEncode(artifact.toJson())
          },
          where: 'id = 1');
      expect(await fresh.query('library_metadata'), isEmpty);
      final lookupsBefore = provider.calls.length;
      final artworkBefore = provider.artworkCalls;
      expect(await shared.restore(fresh), 1);
      final recovered = LibraryStore(Future.value(fresh));
      final restoredId =
          (await LibraryStore.cachedCatalogueEditionId(fresh, 1))!;
      expect(
          (await recovered.metadata(restoredId, 'screenscraper'))!
              .descriptions
              .single
              .text,
          'Second fresh description');
      final restoredArtwork =
          await MetadataArtworkCache(Future.value(fresh), shared.artworkRoot)
              .artworkForEdition(restoredId);
      expect(restoredArtwork.cover, isNotNull);
      expect(restoredArtwork.screenshots, hasLength(1));
      expect(await shared.restore(fresh), 0);
      expect(provider.calls.length, lookupsBefore);
      expect(provider.artworkCalls, artworkBefore);
      report?.call({
        'remote_only': true,
        'rom_directory_created': await romRoot.exists(),
        'fresh_private_restored': 1,
        'restored_cover': true,
        'restored_screenshots': 1,
        'recovery_provider_requests': provider.calls.length - lookupsBefore,
        'recovery_artwork_requests': provider.artworkCalls - artworkBefore,
        'manual_fields_preserved': true,
        'manual_rating_conflict_preserved': true,
        'exact_media_reuse_verified': true
      });
    } finally {
      await fresh.close();
    }
  }

  const description =
      'normal remote refresh queues mapped ES-DE facts without ROM IO';
  if (nativeBinding) {
    // IntegrationTest captures failures through its widget binding's runTest.
    // Plain test() failures are not included in the driver's native result.
    testWidgets(description, (_) => check(), timeout: Timeout.none);
  } else {
    test(description, check, timeout: Timeout.none);
  }
}
