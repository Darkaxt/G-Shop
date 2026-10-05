import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:sqflite/sqflite.dart';

import '../metadata_controls_test.dart'
    show controlsDatabase, ControlsArtworkProvider, MemorySecrets;

const sharedLifecyclePhases = {
  'seed',
  'restart',
  'denied',
  'regrant',
  'reinstalled'
};

RemoteArtifact _artifact(String source) => RemoteArtifact(
    id: RemoteArtifactId(
        providerId: 'drive',
        sourceId: source,
        accountId: 'synthetic-account',
        providerFileId: 'synthetic-file'),
    displayName: 'Game 1.chd',
    displayPath: 'Game 1.chd',
    sizeBytes: 1024,
    version: '1',
    providerChecksums: {'md5': '00000000000000000000000000000001'});

Future<void> _catalogue(Database db, String source) async {
  final artifact = _artifact(source);
  await db.update(
      'games',
      {
        'artifact_key': artifact.id.key,
        'remote_artifact': jsonEncode(artifact.toJson())
      },
      where: 'id = 1');
}

Future<Map<String, String>> _snapshot(Directory root) async {
  final hashes = <String, String>{};
  await for (final entry in root.list(recursive: true, followLinks: false)) {
    expect(entry, isNot(isA<Link>()));
    if (entry is! File || p.basename(entry.path) == 'proof.json') continue;
    hashes[p.relative(entry.path, from: root.path)] =
        (await sha256.bind(entry.openRead()).first).toString();
  }
  return hashes;
}

/// Same assertions on host/native. Only the native supervisor can prove that
/// Android actually restarted, revoked permission or removed the expendable app.
/// No cleanup here: immutable external evidence must survive those boundaries.
Future<Map<String, Object?>> verifySharedMetadataLifecycle({
  required DatabaseFactory factory,
  required Directory external,
  required Directory privateRoot,
  required String phase,
}) async {
  expect(sharedLifecyclePhases, contains(phase));
  expect(p.isWithin(external.path, privateRoot.path), false);
  expect(p.isWithin(privateRoot.path, external.path), false);
  final sentinel = File(p.join(privateRoot.path, 'sentinel.json'));
  final databasePath = p.join(privateRoot.path, 'projection.sqlite');
  final proofFile = File(p.join(external.path, 'proof.json'));
  final sharedRoot = Directory(p.join(external.path, 'RShopMetadata'));
  Database? db;
  SharedMetadataStore? shared;
  Map<String, Object?>? nextProof;
  try {
    if (phase == 'seed') {
      expect(await external.exists(), false,
          reason: 'Reserve a new exact external proof directory');
      expect(await privateRoot.exists(), false);
      await external.create();
      await privateRoot.create();
      db = await controlsDatabase(factory: factory, path: databasePath);
      await _catalogue(db, 'original-source');
      shared = await SharedMetadataStore.open(sharedRoot, factory: factory);
      final library = LibraryStore(Future.value(db));
      final id = (await db.transaction((txn) =>
              LibraryStore.catalogueEditions(txn, cacheRowId: 1).toList()))
          .single;
      final edition = (await library.edition(id))!;
      final game = (await library.game(edition.gameId))!;
      await library.putGame(GameIdentity.fromJson({
        ...game.toJson(),
        'providerIds': {'screenscraper': '42'},
        'matchStatus': 'manuallyMatched'
      }));
      final provider = ControlsArtworkProvider(includeScreenshot: true);
      final initialReply = provider.reply!;
      provider.reply = (request, cancel) async {
        final reply = await initialReply(request, cancel);
        return MetadataLookupResult(
            status: reply.status,
            message: reply.message,
            record: MetadataRecord.fromJson({
              ...reply.record!.toJson(),
              'matchMethod': 'verifiedProviderId',
              'descriptions': [
                MetadataText(text: 'Fresh synthetic fact').toJson()
              ]
            }));
      };
      SharedPreferences.setMockInitialValues({});
      final romRoot = Directory(p.join(external.path, 'ROMs'));
      final target = File(p.join(external.path, 'gamelist.xml'));
      await target.writeAsString(
          '<gameList><game><path>./Game 1.chd</path>'
          '<favorite>true</favorite><custom>keep</custom></game></gameList>',
          flush: true);
      final mediaRoot =
          await Directory(p.join(external.path, 'media')).create();
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
          configuredTarget: (_) async => romRoot.path,
          catalogueChanged: () {});
      try {
        await controls.load();
        await controls.refresh(systemSlug: 'psx');
        expect(controls.state.error, false);
        expect(provider.calls, hasLength(1));
        expect(provider.artworkCalls, 2);
        await controls.mapEsDeEdition(
            cacheRowId: 1,
            editionId: id,
            romRoot: romRoot,
            gamelist: target,
            mediaRoot: mediaRoot);
        await controls.publishEsDe(target, esDeClosed: true);
        expect(controls.state.error, false);
        expect(controls.state.esDeReport!.status, 'published');
        expect(await target.readAsString(), contains('Fresh synthetic fact'));
        expect(
            await target.readAsString(), contains('<favorite>true</favorite>'));
        expect(await target.readAsString(), contains('<custom>keep</custom>'));
        expect(await romRoot.exists(), false);
      } finally {
        await controls.close();
        controls.dispose();
      }
      nextProof = {'schema': 1, 'root': external.path, 'phase': 'seed'};
    } else {
      if (phase == 'reinstalled') {
        expect(await privateRoot.exists(), false,
            reason: 'OS uninstall must remove the private proof namespace');
      } else {
        expect(await sentinel.exists(), true);
        final privateProof = jsonDecode(await sentinel.readAsString()) as Map;
        expect(privateProof['root'], external.path);
        expect(
            privateProof['phase'],
            switch (phase) {
              'restart' => 'seed',
              'denied' => 'restart',
              'regrant' => 'denied',
              _ => throw StateError('Unexpected lifecycle phase')
            });
        expect(await File(databasePath).exists(), true);
      }
      if (phase == 'denied') {
        // Do not open/create a replacement shared store, and do not inspect the
        // external marker through a bypass. Private cached facts remain usable.
        db = await factory.openDatabase(databasePath);
        final before = await db.query('library_metadata');
        expect(before, hasLength(1));
        await expectLater(
            SharedMetadataStore.open(sharedRoot,
                    factory: factory, existingOnly: true)
                .then((unexpected) async {
              await unexpected.close();
              fail('Unavailable shared storage unexpectedly opened');
            }),
            throwsA(
                anyOf(isA<FileSystemException>(), isA<DatabaseException>())));
        final id = before.single['edition_id'] as String;
        expect(
            (await LibraryStore(Future.value(db))
                    .metadata(id, 'screenscraper'))!
                .descriptions
                .single
                .text,
            'Fresh synthetic fact');
        expect(
            (await MetadataArtworkCache(Future.value(db),
                        Directory(p.join(sharedRoot.path, 'artwork')))
                    .artworkForEdition(id))
                .cover,
            isNull);
        expect(await db.query('library_metadata'), before);
      } else {
        final proof = jsonDecode(await proofFile.readAsString()) as Map;
        expect(proof['schema'], 1);
        expect(proof['root'], external.path);
        expect(
            proof['phase'],
            switch (phase) {
              'restart' => 'seed',
              'regrant' => 'restart',
              'reinstalled' => 'regrant',
              _ => throw StateError('Invalid phase')
            });
        expect(await _snapshot(external), proof['hashes'],
            reason:
                'All durable facts, artwork and launcher files must survive');
        if (phase == 'reinstalled') {
          await privateRoot.create();
          db = await controlsDatabase(factory: factory, path: databasePath);
          await _catalogue(db, 'reselected-source');
          expect(await db.query('library_metadata'), isEmpty);
        } else {
          db = await factory.openDatabase(databasePath);
        }
        shared = await SharedMetadataStore.open(sharedRoot,
            factory: factory, existingOnly: true);
        expect(await shared.restore(db), phase == 'reinstalled' ? 1 : 0);
        final id = (await LibraryStore.cachedCatalogueEditionId(db, 1))!;
        expect(
            (await LibraryStore(Future.value(db))
                    .metadata(id, 'screenscraper'))!
                .descriptions
                .single
                .text,
            'Fresh synthetic fact');
        final artwork =
            await MetadataArtworkCache(Future.value(db), shared.artworkRoot)
                .artworkForEdition(id);
        expect(artwork.cover, isNotNull);
        expect(artwork.screenshots, hasLength(1));
        expect(await shared.restore(db), 0);
        nextProof = Map<String, Object?>.from(proof)..['phase'] = phase;
      }
    }
  } finally {
    await shared?.close();
    await db?.close();
  }
  // Advance only after all assertions and handles have completed successfully.
  if (nextProof != null) {
    final hashes = await _snapshot(external);
    if (phase != 'seed') expect(hashes, nextProof['hashes']);
    nextProof['hashes'] = hashes;
    await proofFile.writeAsString(jsonEncode(nextProof), flush: true);
  }
  await sentinel.writeAsString(
      jsonEncode({'root': external.path, 'phase': phase}),
      flush: true);
  return {
    'phase': phase,
    'remote_only': true,
    'restored_records': phase == 'reinstalled' ? 1 : 0,
    'permission_unavailable_asserted': phase == 'denied',
    'durable_hashes_verified': phase != 'denied',
    'rom_requests': 0,
    'recovery_provider_requests': 0,
    'recovery_artwork_requests': 0,
    'owner_application_uninstalled': false
  };
}
