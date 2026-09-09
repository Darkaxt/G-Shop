import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/features/game_detail/game_detail_controller.dart';
import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/models/config/system_config.dart';
import 'package:retro_eshop/models/download_item.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/services/download_queue_manager.dart';
import 'package:retro_eshop/services/unified_game_service.dart';
import 'package:retro_eshop/services/rom_manager.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/transfer_journal.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/utils/game_merge_helper.dart';

GameItem exactGame(String fileId,
        {String account = 'account-a', String name = 'Game.nes'}) =>
    GameItem(
      filename: name,
      displayName: name,
      url: '',
      remoteArtifact: RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: 'source',
            accountId: account,
            providerFileId: fileId),
        parentId: 'folder',
        displayPath: 'nes/$name',
        displayName: name,
        sizeBytes: 42,
        version: 'v1',
        providerChecksums: {'md5': 'abc'},
        canDownload: true,
      ),
    );

class _NoLegacyRomAccess extends RomManager {
  int calls = 0;
  @override
  Future<void> delete(
      GameItem game, SystemModel system, String targetFolder) async {
    calls++;
    throw StateError('Exact artifact reached legacy removal');
  }
}

class _UnusedQueue implements DownloadQueueManager {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected queue access');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await TransferJournalSchema.install(db);
    DatabaseService.testDatabase = db;
  });
  tearDown(() async {
    DatabaseService.resetForTesting();
    await db.close();
  });
  final system = SystemModel.supportedSystems.firstWhere((s) => s.id == 'nes');
  test('exact detail status and removal never inspect a local namesake',
      () async {
    final game = exactGame('file');
    final roms = _NoLegacyRomAccess();
    final controller = GameDetailController(
        game: game,
        variants: [game],
        system: system,
        targetFolder: '/roms',
        romManager: roms,
        queueManager: _UnusedQueue());
    await controller.checkInstallationStatus();
    expect(controller.state.isVariantInstalled, isFalse);
    await controller.deleteRom();
    expect(roms.calls, 0);
    expect(controller.state.error, contains('Verified remote artifact'));
    controller.dispose();
  });
  test('exact artifact survives game copy and JSON and queue restart', () {
    final game = exactGame('file');
    final copied = GameItem.fromJson(
        jsonDecode(jsonEncode(game.copyWith(hasThumbnail: true).toJson()))
            as Map<String, dynamic>);
    expect(copied.remoteArtifact!.toJson(), game.remoteArtifact!.toJson());
    final queued = DownloadItem(
        id: DownloadQueueManager.idFor(game, system),
        game: copied,
        system: system,
        targetFolder: '/roms');
    final restored = DownloadItem.fromJson(
        jsonDecode(jsonEncode(queued.toJson())) as Map<String, dynamic>,
        system);
    expect(
        restored.game.remoteArtifact!.toJson(), game.remoteArtifact!.toJson());
    expect(restored.id, queued.id);
  });

  test('queue identity survives rename and isolates files and accounts', () {
    final original = exactGame('file');
    expect(
        DownloadQueueManager.idFor(original, system),
        DownloadQueueManager.idFor(
            exactGame('file', name: 'Renamed.nes'), system));
    expect(
        DownloadQueueManager.idFor(original, system),
        isNot(DownloadQueueManager.idFor(
            exactGame('file', account: 'account-b'), system)));
    expect(DownloadQueueManager.idFor(original, system),
        isNot(DownloadQueueManager.idFor(exactGame('other'), system)));
    const legacy = GameItem(filename: 'Game.nes', displayName: 'Game', url: '');
    expect(
        DownloadQueueManager.idFor(legacy, system), '${system.name}_Game.nes');
    expect(original.selectionKey,
        exactGame('file', name: 'Renamed.nes').selectionKey);
    expect(legacy.selectionKey, 'Game.nes');
  });

  test('remote duplicates remain distinct and do not adopt a local namesake',
      () {
    final games = GameMergeHelper.merge(
        [exactGame('a'), exactGame('b'), exactGame('a', account: 'account-b')],
        [const GameItem(filename: 'Game.nes', displayName: 'Game', url: '')],
        system);
    expect(games, hasLength(4));
  });

  test('an installed exact artifact is not hidden by a legacy archive target', () {
    final installed = exactGame('installed');
    final remote = const GameItem(filename: 'Game.zip', displayName: 'Game', url: 'https://example.test/Game.zip');
    final games = GameMergeHelper.merge([remote], [installed], system);
    expect(games, hasLength(2));
    expect(games.any((game) => game.identityKey == installed.identityKey), true);
    expect(GameMergeHelper.merge([installed], [installed], system), hasLength(1));
  });

  test(
      'real unified merge retains exact artifacts without filename alternatives',
      () async {
    const first = ProviderConfig(
        type: ProviderType.web, priority: 0, url: 'https://example.test/a');
    const second = ProviderConfig(
        type: ProviderType.ftp, priority: 1, host: 'example.test');
    final service = UnifiedGameService(
        fetchProviderGames: (provider, system) async =>
            provider == first ? [exactGame('a')] : [exactGame('b')]);
    final games = await service.fetchGamesForSystem(const SystemConfig(
        id: 'nes',
        name: 'NES',
        targetFolder: '/roms',
        providers: [first, second]));
    expect(games, hasLength(2));
    expect(games.every((g) => g.alternativeSources.isEmpty), isTrue);
  });

  test('failed Drive refresh cannot publish another providers empty success',
      () async {
    const web = ProviderConfig(
        type: ProviderType.web, priority: 0, url: 'https://example.test');
    const drive = ProviderConfig(
        type: ProviderType.drive, priority: 1, sourceId: 'drive-source');
    final service =
        UnifiedGameService(fetchProviderGames: (provider, system) async {
      if (provider.type == ProviderType.drive) {
        throw StateError('Access revoked');
      }
      return [];
    });
    await expectLater(
        service.fetchGamesForSystem(const SystemConfig(
            id: 'nes',
            name: 'NES',
            targetFolder: '/roms',
            providers: [web, drive])),
        throwsStateError);
  });

  test(
      'Drive source preparation runs once per sync session and remembers failure',
      () async {
    const drive = ProviderConfig(
        type: ProviderType.drive, priority: 0, sourceId: 'drive-source');
    var preparations = 0;
    final service = UnifiedGameService(
        shareDrivePreparation: true,
        prepareDrive: (_) async {
          preparations++;
        },
        fetchProviderGames: (_, system) async => []);
    for (final slug in ['nes', 'snes']) {
      await service.fetchGamesForSystem(SystemConfig(
          id: slug,
          name: slug,
          targetFolder: '/roms',
          providers: const [drive]));
    }
    expect(preparations, 1);
    final failed = UnifiedGameService(
        shareDrivePreparation: true,
        prepareDrive: (_) async {
          preparations++;
          throw StateError('Interrupted');
        },
        fetchProviderGames: (_, system) async => []);
    for (final slug in ['nes', 'snes']) {
      await expectLater(
          failed.fetchGamesForSystem(SystemConfig(
              id: slug,
              name: slug,
              targetFolder: '/roms',
              providers: const [drive])),
          throwsStateError);
    }
    expect(preparations, 2);
  });

  test('ordinary repeated fetches each refresh Drive on a long-lived service',
      () async {
    const config =
        SystemConfig(id: 'nes', name: 'NES', targetFolder: '/roms', providers: [
      ProviderConfig(type: ProviderType.drive, priority: 0, sourceId: 'source')
    ]);
    var preparations = 0;
    final service = UnifiedGameService(
        prepareDrive: (_) async {
          preparations++;
        },
        fetchProviderGames: (_, system) async => []);
    await service.fetchGamesForSystem(config);
    await service.fetchGamesForSystem(config);
    expect(preparations, 2);
  });

  test('ordinary refresh can recover after a previous preparation failed',
      () async {
    const config =
        SystemConfig(id: 'nes', name: 'NES', targetFolder: '/roms', providers: [
      ProviderConfig(type: ProviderType.drive, priority: 0, sourceId: 'source')
    ]);
    var preparations = 0;
    var reads = 0;
    final service = UnifiedGameService(prepareDrive: (_) async {
      preparations++;
      if (preparations == 1) throw StateError('Access temporarily unavailable');
    }, fetchProviderGames: (_, system) async {
      reads++;
      return [];
    });
    await expectLater(service.fetchGamesForSystem(config), throwsStateError);
    expect(await service.fetchGamesForSystem(config), isEmpty);
    expect(preparations, 2);
    expect(reads, 1);
  });
}
