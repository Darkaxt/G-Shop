import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/models/game_item.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/local_cloud_byte_observation.dart';
import 'package:g_shop/models/transfer_record.dart';
import 'package:g_shop/services/installation_index.dart';
import 'package:g_shop/services/owned_storage.dart';
import 'package:g_shop/services/owned_emulator_launcher.dart';
import 'package:g_shop/services/rom_manager.dart';
import 'package:g_shop/models/system_model.dart';
import 'package:g_shop/services/transfer_journal.dart';

class _ReadOnlyStorage extends OwnedStorage {
  NativeFileIdentity? current;
  @override
  Future<NativeFileIdentity?> inspectExisting(
          {required String destinationRoot,
          required String relativePath}) async =>
      current;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late TransferJournal journal;
  late _ReadOnlyStorage storage;
  late InstallationIndex index;
  final identity = NativeFileIdentity(
      volumeId: '1',
      fileId: '42',
      sizeBytes: 5,
      modifiedAt: DateTime.utc(2026, 10, 8));
  RemoteArtifact artifact({String file = 'file', String version = '1'}) =>
      RemoteArtifact(
          id: RemoteArtifactId(
              providerId: 'drive',
              sourceId: 'source',
              accountId: 'account',
              providerFileId: file),
          displayName: 'Game.7z',
          displayPath: 'Game.7z',
          parentId: 'folder',
          version: version,
          sizeBytes: 5,
          canDownload: true,
          providerChecksums: {'md5': 'a' * 32});
  Future<void> observe(RemoteArtifact remote) =>
      journal.saveByteObservation(DriveLocalCloudObservation(
          artifact: remote,
          destinationRoot: '/roms',
          relativePath: 'Game.7z',
          localIdentity: identity,
          sizeBytes: 5,
          checksums: {'md5': 'a' * 32, 'sha256': 'b' * 64},
          observedAt: DateTime.utc(2026, 10, 8)));

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await TransferJournalSchema.install(db);
    journal = TransferJournal(Future.value(db));
    storage = _ReadOnlyStorage()..current = identity;
    index = InstallationIndex(journal, storage: storage);
  });
  tearDown(() => db.close());

  test('an exact read-only copy opens without creating installation ownership',
      () async {
    final remote = artifact();
    await observe(remote);
    const channel = MethodChannel('observed-emulator');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final game = GameItem(
        filename: 'Game.7z',
        displayName: 'Game',
        url: '',
        remoteArtifact: remote);
    final system =
        SystemModel.supportedSystems.singleWhere((s) => s.id == 'gb');
    final roms = RomManager(installations: index);
    final launcher = OwnedEmulatorLauncher(romManager: roms, channel: channel);
    await launcher.open(game, system, '/roms');
    expect(calls.single.method, 'launchOwnedRetroArchGameBoy');
    expect(calls.single.arguments,
        {'observationId': 1, 'platformId': 'gb', 'filename': 'Game.7z'});
    await expectLater(roms.previewOwnedRemoval(game, '/roms'),
        throwsA(isA<OwnedStorageException>()));
    storage.current = null;
    await expectLater(launcher.open(game, system, '/roms'),
        throwsA(isA<OwnedStorageException>()));
    expect(calls, hasLength(1));
    for (final table in [
      'transfer_records',
      'installed_artifacts',
      'transfer_target_owners',
      'owned_removals'
    ]) {
      expect(await db.query(table), isEmpty);
    }
  });

  test(
      'root-paged observation lookup has an additive index without altering evidence',
      () async {
    await observe(artifact());
    final before = await db.query('migration_byte_observations');
    await TransferJournalSchema.installByteObservationRootIndex(db);
    await TransferJournalSchema.installByteObservationRootIndex(db);
    expect(await db.query('migration_byte_observations'), before);
    final plan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT MAX(observation_id) '
        'FROM migration_byte_observations WHERE destination_root = ?',
        ['/roms']);
    expect(plan.map((row) => row['detail']).join(' '),
        contains('idx_migration_byte_root'));
  });

  test('current byte-bound local copy resolves offline without becoming owned',
      () async {
    final remote = artifact();
    await observe(remote);
    final snapshot = await index.scan('/roms');
    expect(snapshot.installed, isEmpty);
    expect(snapshot.localCopies, hasLength(1));
    expect(snapshot.resolve(remote), isNotNull);
    expect(await index.resolveArtifact(remote, '/roms'), isNotNull);
    final local = snapshot.filterLocal(
        [const GameItem(filename: 'Game.7z', displayName: 'Game', url: '')],
        '/roms');
    expect(local.single.remoteArtifact?.id, remote.id);
    for (final table in [
      'transfer_records',
      'installed_artifacts',
      'transfer_target_owners',
      'owned_removals'
    ]) {
      expect(await db.query(table), isEmpty);
    }
    expect(
        await index.resolveArtifact(artifact(version: '2'), '/roms'), isNull);
  });
  test('missing copy keeps its historical alias but cannot claim availability',
      () async {
    final remote = artifact();
    await observe(remote);
    storage.current = null;
    final snapshot = await index.scan('/roms');
    expect(snapshot.localCopies, isEmpty);
    expect(snapshot.legacyAliases.values.single.id, remote.id);
    expect(snapshot.resolve(remote), isNull);
    expect(await index.resolveArtifact(remote, '/roms'), isNull);
  });
  test('changed object is neither an exact local copy nor a legacy alias',
      () async {
    await observe(artifact());
    storage.current = NativeFileIdentity(
        volumeId: '1',
        fileId: '43',
        sizeBytes: 5,
        modifiedAt: identity.modifiedAt);
    final snapshot = await index.scan('/roms');
    expect(snapshot.localCopies, isEmpty);
    expect(snapshot.legacyAliases, isEmpty);
    expect(await index.resolveArtifact(artifact(), '/roms'), isNull);
  });
  test('two provider identities at one path cannot select an arbitrary copy',
      () async {
    await observe(artifact());
    await observe(artifact(file: 'another'));
    final snapshot = await index.scan('/roms');
    expect(snapshot.localCopies, isEmpty);
    expect(snapshot.legacyAliases, isEmpty);
    expect(await index.resolveArtifact(artifact(), '/roms'), isNull);
  });
  test('a reserved target cannot borrow historical unmanaged-copy evidence',
      () async {
    await observe(artifact());
    await journal.create(TransferRecord(
        id: 'new-owner',
        artifact: artifact(file: 'new'),
        destinationRoot: '/roms',
        relativePath: 'Game.7z',
        stagePath: '/private/new.partial'));
    final snapshot = await index.scan('/roms');
    expect(snapshot.localCopies, isEmpty);
    expect(snapshot.legacyAliases, isEmpty);
    expect(await index.resolveArtifact(artifact(), '/roms'), isNull);
  });
  test(
      'latest observations are paged without falling back through invalid newer evidence',
      () async {
    await observe(artifact());
    await observe(artifact(version: '2'));
    await observe(artifact(file: 'another'));
    final latest =
        await journal.byteObservationsInRoot('/roms', batchSize: 1).toList();
    expect(latest, hasLength(2));
    expect(latest.first.observation.artifact.version, '2');
    await db.insert('migration_byte_observations', {
      'artifact_key': artifact().id.key,
      'destination_root': '/roms',
      'relative_path': 'Game.7z',
      'record_json': 'x' * 20000,
    });
    final bounded =
        await journal.byteObservationsInRoot('/roms', batchSize: 1).toList();
    expect(bounded, hasLength(1));
    expect(bounded.single.observation.artifact.id.providerFileId, 'another');
    expect(
        (await index.scan('/roms'))
            .localCopies
            .values
            .single
            .observation
            .artifact
            .id
            .providerFileId,
        'another');
  });
}
