import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/models/config/drive_source_config.dart';
import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/models/config/source.dart';
import 'package:retro_eshop/models/config/system_config.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';
import 'package:retro_eshop/services/drive/drive_catalogue.dart';
import 'package:retro_eshop/services/drive/drive_runtime.dart';
import 'package:retro_eshop/services/providers/drive_provider.dart';
import 'package:retro_eshop/services/provider_factory.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/unified_game_service.dart';

class _Files implements DriveCatalogueApi {
  final List<DriveFile> extraFiles;
  _Files({this.extraFiles = const []});
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

  test('Drive cannot bypass forthcoming verified transfer with ordinary HTTP',
      () async {
    final provider = DriveProvider(config, runtime: runtime);
    final game = (await provider.fetchGames(system)).first;
    await expectLater(
        provider.resolveDownload(game),
        throwsA(isA<DriveCatalogueException>()
            .having((e) => e.code, 'blocker', 'verifiedTransferNotAvailable')));
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
