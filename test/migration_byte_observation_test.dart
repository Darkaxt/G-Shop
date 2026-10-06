import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/local_cloud_byte_observation.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/transfer_journal.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';

const _md5 = '7cfdd07889b3295d6a550914ab35e068';
DriveLocalCloudObservation _observation(
        {String account = 'account', String version = '1', int hour = 1}) =>
    DriveLocalCloudObservation(
        artifact: RemoteArtifact(
            id: RemoteArtifactId(
                providerId: 'drive',
                sourceId: 'source',
                accountId: account,
                providerFileId: 'file'),
            displayName: 'Fixture.chd',
            displayPath: 'psx/Fixture.chd',
            version: version,
            sizeBytes: 5,
            canDownload: true,
            providerChecksums: const {'md5': _md5}),
        destinationRoot: '/storage/roms/psx',
        relativePath: 'Fixture.chd',
        sizeBytes: 5,
        localIdentity: NativeFileIdentity(
            volumeId: 'volume',
            fileId: 'inode',
            sizeBytes: 5,
            modifiedAt: DateTime.utc(2026, 10, 6)),
        checksums: {'md5': _md5, 'sha256': 'a' * 64},
        observedAt: DateTime.utc(2026, 10, 6, hour));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  test(
      'production v35 upgrade preserves cache/jobs and observations survive reopen',
      () async {
    final prior = await databaseFactory.getDatabasesPath();
    final root = await Directory.systemTemp.createTemp('rshop-byte-migration-');
    Database? db;
    try {
      await databaseFactory.setDatabasesPath(root.path);
      DatabaseService.resetForTesting();
      final service = DatabaseService();
      db = await service.database;
      await service.saveGames('psx', [
        const GameItem(
            filename: 'Fixture.chd',
            displayName: 'Fixture',
            url: 'https://example.invalid/Fixture.chd')
      ]);
      await MetadataRefreshJobs(Future.value(db))
          .createFromCatalogue(providerId: 'screenscraper');
      await db.execute('DROP TABLE migration_byte_observations');
      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
      final before = <String, List<Map<String, Object?>>>{};
      for (final table in tables) {
        final name = table['name'] as String;
        before[name] = await db.query(name);
      }
      await db.setVersion(35);
      await db.close();
      DatabaseService.resetForTesting();
      db = await service.database;
      expect(await db.getVersion(), 37);
      for (final name in before.keys) {
        expect(await db.query(name), before[name], reason: name);
      }
      final journal = TransferJournal(Future.value(db));
      final first = _observation();
      await journal.saveByteObservation(first);
      await journal.saveByteObservation(_observation(version: '2', hour: 0));
      await db.close();
      DatabaseService.resetForTesting();
      db = await service.database;
      final reopened = TransferJournal(Future.value(db));
      final saved = await reopened.latestByteObservation(
          artifactId: first.artifact.id,
          destinationRoot: first.destinationRoot,
          relativePath: first.relativePath);
      // Insertion order is authoritative for "last check", not wall-clock order.
      expect(saved?.artifact.version, '2');
      expect(saved?.localIdentity.toJson(), first.localIdentity.toJson());
      expect(saved?.checksums, first.checksums);
      expect(await db.query('migration_byte_observations'), hasLength(2));
      expect(await db.query('transfer_records'), isEmpty);
      expect(await db.query('installed_artifacts'), isEmpty);
      expect(await db.query('owned_removals'), isEmpty);
      for (final target in [
        (
          id: _observation(account: 'other').artifact.id,
          root: first.destinationRoot,
          path: first.relativePath
        ),
        (
          id: RemoteArtifactId(
              providerId: 'drive',
              sourceId: 'other',
              accountId: 'account',
              providerFileId: 'file'),
          root: first.destinationRoot,
          path: first.relativePath
        ),
        (
          id: first.artifact.id,
          root: '/storage/other',
          path: first.relativePath
        ),
        (id: first.artifact.id, root: first.destinationRoot, path: 'Other.chd'),
      ]) {
        expect(
            await reopened.latestByteObservation(
                artifactId: target.id,
                destinationRoot: target.root,
                relativePath: target.path),
            isNull);
      }
    } finally {
      if (db?.isOpen == true) await db!.close();
      DatabaseService.resetForTesting();
      await databaseFactory.setDatabasesPath(prior);
      expect(root.parent.path, Directory.systemTemp.absolute.path);
      expect(root.path.split(Platform.pathSeparator).last,
          startsWith('rshop-byte-migration-'));
      await root.delete(recursive: true);
    }
  });

  test(
      'persisted evidence rejects malformed digests, paths, identity and schema',
      () {
    final json = _observation().toJson();
    for (final change in [
      {'schema': 2},
      {'destinationRoot': '/storage/../roms'},
      {'relativePath': '../Fixture.chd'},
      {'sizeBytes': 4},
      {
        'checksums': {'md5': _md5, 'sha256': 'broken'}
      },
      {
        'checksums': {'md5': 'b' * 32, 'sha256': 'a' * 64}
      },
    ]) {
      expect(() => DriveLocalCloudObservation.fromJson({...json, ...change}),
          throwsA(anything));
    }
  });
}
