import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/models/config/drive_source_config.dart';
import 'package:g_shop/models/config/provider_config.dart';
import 'package:g_shop/models/config/source.dart';
import 'package:g_shop/models/config/system_config.dart';
import 'package:g_shop/services/drive/drive_api.dart';
import 'package:g_shop/services/drive/drive_catalogue.dart';
import 'package:g_shop/services/drive/drive_runtime.dart';
import 'package:g_shop/services/providers/drive_provider.dart';
import 'package:g_shop/services/provider_factory.dart';
import 'package:g_shop/services/database_service.dart';
import 'package:g_shop/services/unified_game_service.dart';

class _Files implements DriveCatalogueApi {
  final List<DriveFile> extraFiles;
  _Files({this.extraFiles = const []});
  @override
  Future<List<DriveFile>> getFolderBatch(List<String> ids,
          {CancelToken? cancelToken}) async =>
      [for (final id in ids) await getFile(id, cancelToken: cancelToken)];
  @override
  Future<DriveFile> getFile(String id, {CancelToken? cancelToken}) async =>
      DriveFile(
          id: id,
          name: 'ROMs',
          mimeType: DriveFile.folderMime,
          parents: ['my-drive']);
  @override
  Future<DriveFilePage> listChildren(String parentId,
          {String? pageToken,
          bool foldersOnly = false,
          CancelToken? cancelToken}) async =>
      DriveFilePage(files: [
        ...extraFiles,
        for (final id in ['first', 'second'])
          DriveFile(
              id: id,
              name: 'Same.chd',
              mimeType: 'application/octet-stream',
              parents: [parentId],
              sizeBytes: 100,
              version: '3'),
        DriveFile(
            id: 'not-game',
            name: 'Readme.txt',
            mimeType: 'text/plain',
            parents: [parentId]),
        DriveFile(
            id: 'shortcut',
            name: 'External games',
            mimeType: 'application/vnd.google-apps.shortcut',
            parents: [parentId]),
        DriveFile(
            id: 'document',
            name: 'Notes',
            mimeType: 'application/vnd.google-apps.document',
            parents: [parentId]),
      ]);
}

class _PatchFiles implements DriveCatalogueApi {
  final List<DriveFile> files = [
    DriveFile(
        id: 'folder',
        name: 'ROMs',
        mimeType: DriveFile.folderMime,
        parents: ['my-drive']),
    DriveFile(
        id: 'patches',
        name: 'Patches',
        mimeType: DriveFile.folderMime,
        parents: ['folder']),
    DriveFile(
        id: 'source',
        name: 'Source Code',
        mimeType: DriveFile.folderMime,
        parents: ['patches']),
    DriveFile(
        id: 'palettes',
        name: 'Palettes',
        mimeType: DriveFile.folderMime,
        parents: ['source']),
    DriveFile(
        id: 'translations',
        name: 'T-Eng',
        mimeType: DriveFile.folderMime,
        parents: ['folder']),
    DriveFile(
        id: 'slash',
        name: 'Archive/Patches',
        mimeType: DriveFile.folderMime,
        parents: ['folder']),
    for (final parent in ['folder', 'palettes', 'translations', 'slash'])
      DriveFile(
          id: 'rom-$parent',
          name: '74.bin',
          mimeType: 'application/octet-stream',
          parents: [parent],
          sizeBytes: parent == 'palettes' ? 32 : 1048576,
          version: '1'),
    // Exercise complete parent discovery over more than one provider page.
    for (var i = 0; i < 501; i++)
      DriveFile(
          id: 'padding-$i',
          name: 'Readme-$i.txt',
          mimeType: 'text/plain',
          parents: ['folder'],
          sizeBytes: 32,
          version: '1'),
  ];

  @override
  Future<DriveFile> getFile(String id, {CancelToken? cancelToken}) async =>
      files.singleWhere((file) => file.id == id);

  @override
  Future<List<DriveFile>> getFolderBatch(List<String> ids,
          {CancelToken? cancelToken}) async =>
      [for (final id in ids) await getFile(id)];

  @override
  Future<DriveFilePage> listChildren(String parentId,
          {String? pageToken,
          bool foldersOnly = false,
          CancelToken? cancelToken}) async =>
      DriveFilePage(
          files: files
              .where((file) =>
                  file.parents.contains(parentId) &&
                  (!foldersOnly || file.isFolder))
              .toList());
}

void main() {
  late Database db;
  late DriveRuntime runtime;
  const drive = DriveSourceConfig(
      accountId: 'a', rootFolderId: 'folder', serverClientId: 'public-client');
  const config = ProviderConfig(
      type: ProviderType.drive,
      priority: 1,
      sourceId: 's',
      drive: drive,
      path: 'folder');
  const system = SystemConfig(
      id: 'psx', name: 'PlayStation', targetFolder: 'psx', providers: [config]);
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DriveCatalogueSchema.install(db);
    runtime = DriveRuntime(catalogue: DriveCatalogue(Future.value(db)));
    await runtime.catalogue.refresh(
        sourceId: 's', accountId: 'a', rootFolderId: 'folder', api: _Files());
  });
  tearDown(() => db.close());

  test(
      'normal factory registers Drive and cached mapped catalogue preserves IDs',
      () async {
    expect(ProviderFactory.getProvider(config), isA<DriveProvider>());
    final games =
        await DriveProvider(config, runtime: runtime).fetchGames(system);
    expect(games.length, 2);
    expect(games.map((e) => e.filename), ['Same.chd', 'Same.chd']);
    expect(games.map((e) => e.remoteArtifact!.id.providerFileId),
        ['first', 'second']);
    expect(games.first.remoteArtifact!.version, '3');
    expect(games.first.url.startsWith('drive-artifact:'), isTrue);
    expect(games.first.url.contains('Bearer'), isFalse);
  });

  test(
      'wrong account and foreign mapping cannot silently publish an empty list',
      () async {
    await expectLater(
        DriveProvider(config.copyWith(path: 'outside'), runtime: runtime)
            .fetchGames(system),
        throwsA(isA<DriveCatalogueException>()));
    await expectLater(
        DriveProvider(
                config.copyWith(drive: drive.copyWith(accountId: 'other')),
                runtime: runtime)
            .fetchGames(system),
        throwsA(isA<DriveCatalogueException>()));
  });

  test('mapped console includes normal archives without reading their bodies',
      () async {
    await runtime.catalogue.refresh(
        sourceId: 's',
        accountId: 'a',
        rootFolderId: 'folder',
        api: _Files(extraFiles: [
          for (final extension in ['zip', '7z', 'rar', 'gg', 'png', 'ips'])
            DriveFile(
                id: extension,
                name: 'Game.$extension',
                mimeType: 'application/octet-stream',
                parents: ['folder'],
                sizeBytes: 100,
                version: '3'),
        ]));
    const gameGear = SystemConfig(
        id: 'gamegear',
        name: 'Game Gear',
        targetFolder: 'gamegear',
        providers: [config]);
    final games =
        await DriveProvider(config, runtime: runtime).fetchGames(gameGear);
    expect(games.map((game) => game.filename).toSet(),
        {'Game.zip', 'Game.7z', 'Game.rar', 'Game.gg'});
    expect(games.map((game) => game.remoteArtifact!.id.providerFileId).toSet(),
        {'zip', '7z', 'rar', 'gg'});
    expect(
        games.every((game) => game.url.startsWith('drive-artifact:')), isTrue);
  });

  test('selected single-console root itself is available as a mapping',
      () async {
    final folders = await runtime.folders(const Source(
        id: 's', name: 'Cloud', type: SourceType.drive, drive: drive));
    expect(folders.map((e) => e.id), ['folder']);
  });

  test(
      'mapped game projection excludes patch resources by real folder ancestry',
      () async {
    await runtime.catalogue.refresh(
        sourceId: 's',
        accountId: 'a',
        rootFolderId: 'folder',
        api: _PatchFiles());
    const megaDrive = SystemConfig(
        id: 'megadrive',
        name: 'Mega Drive',
        targetFolder: 'megadrive',
        providers: [config]);
    final games =
        await DriveProvider(config, runtime: runtime).fetchGames(megaDrive);
    expect(games.map((game) => game.remoteArtifact!.id.providerFileId).toSet(),
        {'rom-folder', 'rom-translations', 'rom-slash'});
    // The source snapshot is not purged and remains usable for explicit mappings.
    final patchEntries = await runtime.catalogue.entries(
        sourceId: 's',
        accountId: 'a',
        rootFolderId: 'folder',
        folderId: 'patches');
    expect(
        patchEntries.any((entry) => entry.file.id == 'rom-palettes'), isTrue);
    final explicit =
        await DriveProvider(config.copyWith(path: 'source'), runtime: runtime)
            .fetchGames(megaDrive);
    expect(explicit.map((game) => game.remoteArtifact!.id.providerFileId),
        ['rom-palettes']);
  });

  test(
      'source exclusion report surfaces unsupported records from cached snapshot',
      () async {
    final counts = await runtime.unsupportedCounts(const Source(
        id: 's', name: 'Cloud', type: SourceType.drive, drive: drive));
    expect(counts, {'shortcut': 1, 'workspaceDocument': 1});
    // No new native authorization was configured or attempted to read the report.
    expect(
        (await DriveProvider(config, runtime: runtime).fetchGames(system))
            .length,
        2);
  });

  test('Drive exposes an opaque exact artifact, never a generic download URL',
      () async {
    final game =
        (await DriveProvider(config, runtime: runtime).fetchGames(system))
            .first;
    expect(game.url, startsWith('drive-artifact:'));
    expect(game.hasDownloadSource, isTrue);
    expect(game.remoteArtifact?.id.providerId, 'drive');
  });

  test(
      'ordinary library reads use the published snapshot without authorization',
      () async {
    DatabaseService.testDatabase = db;
    try {
      // Real factory/runtime/database path: no native sign-in is available in
      // this test. Any implicit network preparation fails instead of being mocked.
      final service = UnifiedGameService();
      for (var read = 0; read < 2; read++) {
        final games = await service.fetchGamesForSystem(system);
        expect(games.map((game) => game.remoteArtifact!.id.providerFileId),
            ['first', 'second']);
      }
      await expectLater(
          service.fetchGamesForSystem(system.copyWith(providers: [
            config.copyWith(path: 'outside'),
          ])),
          throwsA(isA<DriveCatalogueException>()));
    } finally {
      DatabaseService.resetForTesting();
    }
  });
}
