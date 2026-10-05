import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/shared_metadata_store.dart';
import 'package:retro_eshop/services/transfer_journal.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'metadata_controls_test.dart' show controlsDatabase;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (bundle, declared) in [
    (true, true),
    (true, false),
    (false, false)
  ]) {
    test(
        'recorded installation path without ROM IO (bundle=$bundle, members=$declared)',
        () async {
      final db = await controlsDatabase();
      await TransferJournalSchema.install(db);
      final root = await Directory.systemTemp.createTemp('rshop-esde-bundle-');
      var shared = await SharedMetadataStore.open(
          Directory(p.join(root.path, 'shared')),
          factory: databaseFactoryFfiNoIsolate);
      final library = LibraryStore(Future.value(db));
      RemoteArtifact artifact(String id, String name) => RemoteArtifact(
          id: RemoteArtifactId(
              providerId: 'drive',
              sourceId: 'source',
              accountId: 'account',
              providerFileId: id),
          displayName: name,
          displayPath: name,
          version: '1',
          sizeBytes: 1024,
          providerChecksums: {'md5': '00000000000000000000000000000001'});
      final entry = artifact('entry', bundle ? 'Game.m3u' : 'Game.chd');
      final first = artifact('disc-1', 'Disc 1.chd');
      final second = artifact('disc-2', 'Disc 2.chd');
      for (final (row, member) in [(1, entry), (3, first), (4, second)]) {
        await db.insert(
            'games',
            {
              'id': row,
              'systemSlug': 'psx',
              'displayName': member.displayName,
              'filename': member.displayName,
              'artifact_key': member.id.key,
              'remote_artifact': jsonEncode(member.toJson()),
              'is_folder': 0
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      final editionId = (await db.transaction((txn) =>
              LibraryStore.catalogueEditions(txn, cacheRowId: 1).toList()))
          .single;
      final old = (await library.edition(editionId))!;
      await library.putArtifact(first);
      await library.putArtifact(second);
      if (declared) {
        await library.putEdition(EditionIdentity.fromJson({
          ...old.toJson(),
          'members': [
            EditionMember(artifactId: entry.id),
            EditionMember(artifactId: first.id, discNumber: 1),
            EditionMember(artifactId: second.id, discNumber: 2)
          ].map((m) => m.toJson()).toList()
        }));
      }
      await library.putMetadata(MetadataRecord(
          gameId: old.gameId,
          editionId: editionId,
          platformId: 'psx',
          providerId: 'screenscraper',
          providerGameId: '42',
          retrievedAt: DateTime.utc(2026, 10, 5),
          refreshGeneration: 1,
          matchMethod: 'platformAndTitle',
          titles: const [MetadataText(text: 'Bundle fixture')]));
      final roms = Directory(p.join(root.path, 'ROMs'));
      final destination = Directory(p.join(roms.path, 'psx'));
      final gamelist = File(p.join(root.path, 'gamelist.xml'));
      await gamelist.writeAsString('<gameList/>');
      Future<void> map() => shared.mapEsDeEdition(db,
          cacheRowId: 1,
          editionId: editionId,
          providerId: 'screenscraper',
          installRoot: destination,
          romRoot: roms,
          gamelist: gamelist);
      addTearDown(() async {
        await shared.close();
        await db.close();
        await root.delete(recursive: true);
      });
      if (bundle) {
        await expectLater(map(), throwsStateError,
            reason:
                'A playlist namespace must never be guessed from its filename');
      } else {
        await map();
      }
      final journal = TransferJournal(Future.value(db));
      final entryPath =
          bundle ? 'rshop-bundle-fixture/Game.m3u' : 'Game.rshop-fixture.chd';
      await journal.create(TransferRecord(
          id: 'bundle-plan',
          artifact: entry,
          destinationRoot: destination.path,
          relativePath: entryPath,
          stagePath: '/private/never-export-stage',
          bundleMembers: bundle
              ? [
                  TransferBundleMember(
                      transferId: 'member-1',
                      artifact: first,
                      relativePath: 'rshop-bundle-fixture/Disc 1.chd'),
                  TransferBundleMember(
                      transferId: 'member-2',
                      artifact: second,
                      relativePath: 'rshop-bundle-fixture/Disc 2.chd')
                ]
              : []));
      await map();
      Future<String> publish() async => (await shared.publishEsDe(db, gamelist,
              esDeClosed: true,
              configuredTarget: (_) async => destination.path))
          .status;
      expect(await publish(), 'published');
      expect(await gamelist.readAsString(),
          contains('<path>./psx/$entryPath</path>'));
      expect(await roms.exists(), false);
      final valid = await gamelist.readAsString();
      await journal.create(TransferRecord(
          id: 'ambiguous-plan',
          artifact: entry,
          destinationRoot: destination.path,
          relativePath: 'Other/${entry.displayName}',
          stagePath: '/private/other-stage'));
      expect(await publish(), 'identityChanged');
      await expectLater(map(), throwsStateError);
      expect(await gamelist.readAsString(), valid,
          reason:
              'Two exact-content plans cannot silently select a winning path');
      // Operational transfer state may be lost/recreated independently of the
      // durable metadata expected layout. It must never be restored from it.
      await db.delete('transfer_target_owners');
      await db.delete('transfer_records');
      await shared.close();
      final inspected = await databaseFactoryFfiNoIsolate
          .openDatabase(p.join(root.path, 'shared', 'metadata.sqlite'));
      final layout = (await inspected.query('es_de_mappings'))
          .single['installation_layout'] as String;
      expect(layout, contains(entryPath));
      expect(layout, isNot(contains('/private/')));
      expect(layout, isNot(contains('transferId')));
      expect(
          await inspected.rawQuery(
              "SELECT name FROM sqlite_master WHERE name IN ('transfer_records', 'installed_artifacts')"),
          isEmpty);
      await inspected.close();
      shared = await SharedMetadataStore.open(
          Directory(p.join(root.path, 'shared')),
          factory: databaseFactoryFfiNoIsolate,
          existingOnly: true);
      expect({'published', 'upToDate'}, contains(await publish()));
      expect(await db.query('transfer_records'), isEmpty);
      final before = await gamelist.readAsString();
      await db.update(
          'games',
          {
            'remote_artifact': jsonEncode(RemoteArtifact.fromJson(
                    {...(bundle ? second : entry).toJson(), 'version': '2'})
                .toJson())
          },
          where: 'id = ?',
          whereArgs: [bundle ? 4 : 1]);
      expect(await publish(), 'identityChanged',
          reason:
              'Every planned dependency must still match the remote catalogue');
      expect(await gamelist.readAsString(), before);
      expect(await roms.exists(), false);
    });
  }
}
