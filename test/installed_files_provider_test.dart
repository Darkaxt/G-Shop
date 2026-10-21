import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:g_shop/models/config/app_config.dart';
import 'package:g_shop/models/config/system_config.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/local_cloud_byte_observation.dart';
import 'package:g_shop/models/transfer_record.dart';
import 'package:g_shop/providers/game_providers.dart';
import 'package:g_shop/providers/installed_files_provider.dart';
import 'package:g_shop/services/database_service.dart';
import 'package:g_shop/services/owned_storage.dart';
import 'package:g_shop/services/transfer_journal.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.darkaxt.gshop/storage');
  const filename = 'Fixture.chd';
  const hashes = {
    'md5': '7cfdd07889b3295d6a550914ab35e068',
    'sha256':
        '74f81fe167d99b4cb41d6d0ccda82278caee9f3e2f25d5e5a3936ff3dcec60d0',
  };
  late Database db;
  late TransferJournal journal;
  late Directory temporary;
  late Directory root;
  late ProviderContainer container;
  NativeFileIdentity? observed;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await TransferJournalSchema.install(db);
    DatabaseService.testDatabase = db;
    journal = TransferJournal(Future.value(db));
    temporary =
        Directory.systemTemp.createTempSync('installed-files-provider-');
    root = Directory(p.join(temporary.path, 'psx'))..createSync();
    final other = Directory(p.join(temporary.path, 'nes'))..createSync();
    container = ProviderContainer(overrides: [
      bootstrappedConfigProvider
          .overrideWith((ref) async => AppConfig(systems: [
                SystemConfig(
                    id: 'psx',
                    name: 'PlayStation',
                    targetFolder: root.path,
                    providers: []),
                SystemConfig(
                    id: 'nes',
                    name: 'NES',
                    targetFolder: other.path,
                    providers: []),
              ])),
    ]);
    observed = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, anyOf('ownedInspect', 'localCopyInspect'));
      if (call.method == 'ownedInspect') {
        expect((call.arguments as Map)['published'], isTrue);
      }
      return observed == null ? null : OwnedStorage.nativeIdentity(observed!);
    });
  });

  tearDown(() async {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    DatabaseService.resetForTesting();
    await db.close();
    temporary.deleteSync(recursive: true);
  });

  Future<TransferRecord> publication(
      {bool committed = false, String relativePath = filename}) async {
    final artifact = RemoteArtifact(
      id: RemoteArtifactId(
          providerId: 'drive',
          sourceId: 'source',
          accountId: 'account',
          providerFileId: 'file'),
      parentId: 'folder',
      displayPath: filename,
      displayName: filename,
      sizeBytes: 5,
      version: 'v1',
      providerChecksums: {'md5': hashes['md5']!},
      canDownload: true,
    );
    final identity = NativeFileIdentity(
        volumeId: 'volume',
        fileId: 'inode',
        sizeBytes: 5,
        modifiedAt: DateTime.utc(2026, 9, 9));
    var record = await journal.create(TransferRecord(
        id: 'transfer',
        artifact: artifact,
        destinationRoot: root.path,
        relativePath: relativePath,
        stagePath: p.join(temporary.path, 'private-stage')));
    record = await journal.save(record.copyWith(
        lifecycle: TransferLifecycle.transferring,
        durableOffset: 5,
        stageIdentity: identity));
    record = await journal.save(record.copyWith(
        lifecycle: TransferLifecycle.verifying, verifiedChecksums: hashes));
    record = await journal.save(record.copyWith(
        lifecycle: TransferLifecycle.publishing,
        publication: TransferPublication(
            method: PublicationMethod.copy, sourceIdentity: identity)));
    final file = File(p.join(root.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync([1, 2, 3, 4, 5]);
    if (!committed) return record;
    final destination = NativeFileIdentity(
        volumeId: 'volume',
        fileId: 'destination',
        sizeBytes: 5,
        modifiedAt: identity.modifiedAt);
    record = await journal.save(record.copyWith(
        publication: TransferPublication(
            method: PublicationMethod.copy,
            sourceIdentity: identity,
            destinationIdentity: destination,
            confirmed: true)));
    observed = destination;
    return journal.complete(
        record,
        InstalledArtifact(
            id: 'installation',
            transferId: record.id,
            artifact: artifact,
            destinationRoot: root.path,
            relativePath: relativePath,
            sizeBytes: 5,
            verifiedChecksums: hashes,
            fileIdentity: destination));
  }

  test(
      'uncommitted public file is excluded while a legacy neighbor is retained',
      () async {
    await publication();
    File(p.join(root.path, 'Neighbor.chd')).writeAsBytesSync([9]);
    final state = await container.read(installedFilesProvider.future);
    expect(state.bySystem['psx'], {'Neighbor.chd'});
    expect(state.all, {'Neighbor.chd'});
    expect(state.exactBySystem['psx'], isEmpty);
    expect(state.managedBytesBySystem['psx'], 0);
  });

  test('verified installation is exact per-system evidence, never a filename',
      () async {
    final record = await publication(committed: true);
    final state = await container.read(installedFilesProvider.future);
    expect(state.bySystem['psx'], isEmpty);
    expect(state.all, isEmpty);
    expect(state.hasExactArtifact('psx', record.artifact), isTrue);
    expect(state.hasExactArtifact('nes', record.artifact), isFalse);
    expect(state.managedBytesBySystem['psx'], 5);
    final renamed = RemoteArtifact.fromJson({
      ...record.artifact.toJson(),
      'displayName': 'Renamed.chd',
      'displayPath': 'elsewhere/Renamed.chd'
    });
    expect(state.hasExactArtifact('psx', renamed), isTrue);
  });

  test(
      'a directory containing an uncommitted publication is not legacy evidence',
      () async {
    await publication(relativePath: 'Bundle/$filename');
    File(p.join(root.path, 'Bundle', 'Neighbor.chd')).writeAsBytesSync([9]);
    final state = await container.read(installedFilesProvider.future);
    expect(state.bySystem['psx'], isEmpty);
    expect(state.all, isEmpty);
  });

  test(
      'changed managed identity removes exact evidence without legacy fallback',
      () async {
    final record = await publication(committed: true);
    final before = await container.read(installedFilesProvider.future);
    expect(before.hasExactArtifact('psx', record.artifact), isTrue);
    observed = NativeFileIdentity(
        volumeId: 'volume',
        fileId: 'replacement',
        sizeBytes: 5,
        modifiedAt: DateTime.utc(2026, 9, 9));
    container.invalidate(installedFilesProvider);
    final after = await container.read(installedFilesProvider.future);
    expect(after.hasExactArtifact('psx', record.artifact), isFalse);
    expect(after.all, isEmpty);
    expect(after.managedBytesBySystem['psx'], 0);
  });

  test(
      'read-only copies supply exact availability and durable cache aliases, not owned bytes',
      () async {
    final artifact = RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: 'source',
            accountId: 'account',
            providerFileId: 'observed'),
        parentId: 'folder',
        displayName: filename,
        displayPath: filename,
        version: 'v1',
        sizeBytes: 5,
        providerChecksums: {'md5': hashes['md5']!},
        canDownload: true);
    observed = NativeFileIdentity(
        volumeId: '1',
        fileId: '42',
        sizeBytes: 5,
        modifiedAt: DateTime.utc(2026, 10, 8));
    // The native namespace is Android-only. Use a channel fixture rather than
    // weakening observation validation to accept a Windows path.
    container.dispose();
    container = ProviderContainer(overrides: [
      bootstrappedConfigProvider
          .overrideWith((ref) async => AppConfig(systems: [
                SystemConfig(
                    id: 'psx',
                    name: 'PlayStation',
                    targetFolder: '/roms/psx',
                    providers: [])
              ]))
    ]);
    await journal.saveByteObservation(DriveLocalCloudObservation(
        artifact: artifact,
        destinationRoot: '/roms/psx',
        relativePath: filename,
        localIdentity: observed!,
        sizeBytes: 5,
        checksums: hashes,
        observedAt: DateTime.utc(2026, 10, 8)));
    final before = await container.read(installedFilesProvider.future);
    expect(before.hasExactArtifact('psx', artifact), isTrue);
    expect(before.bySystem['psx'], isEmpty);
    expect(before.managedBytesBySystem['psx'], 0);
    expect(before.legacyAliasesBySystem['psx']?[filename]?.id, artifact.id);
    observed = null;
    container.invalidate(installedFilesProvider);
    final missing = await container.read(installedFilesProvider.future);
    expect(missing.hasExactArtifact('psx', artifact), isFalse);
    expect(missing.legacyAliasesBySystem['psx']?[filename]?.id, artifact.id);
    expect(await db.query('installed_artifacts'), isEmpty);
  });
}
