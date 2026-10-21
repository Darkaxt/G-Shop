import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/features/game_detail/game_detail_controller.dart';
import 'package:g_shop/features/game_detail/game_detail_state.dart';
import 'package:g_shop/models/config/provider_config.dart';
import 'package:g_shop/models/game_item.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/system_model.dart';
import 'package:g_shop/services/download_queue_manager.dart';
import 'package:g_shop/services/rom_manager.dart';

const local = GameItem(filename: 'Game.nes', displayName: 'Game', url: '');
const web = ProviderConfig(type: ProviderType.web, priority: 0);
const drive = ProviderConfig(type: ProviderType.drive, priority: 0);

class _Queue implements DownloadQueueManager {
  int access = 0;
  final added = <GameItem>[];
  @override
  DownloadQueueState get state {
    access++;
    return const DownloadQueueState();
  }

  @override
  String addToQueue(GameItem game, SystemModel system, String targetFolder,
      {bool autoExtract = false}) {
    access++;
    added.add(game);
    return 'fixture';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unused queue');
}

class _Roms extends RomManager {
  final bool installed;
  _Roms({this.installed = false});
  @override
  Future<Map<int, bool>> checkMultipleExists(List<GameItem> variants,
          SystemModel system, String targetFolder) async =>
      {for (var i = 0; i < variants.length; i++) i: installed};
}

RemoteArtifact artifact({bool downloadable = true}) => RemoteArtifact(
    id: RemoteArtifactId(
        providerId: 'drive',
        sourceId: 'source',
        accountId: 'account',
        providerFileId: 'file'),
    parentId: 'folder',
    displayPath: 'Game.nes',
    displayName: 'Game.nes',
    sizeBytes: 42,
    version: 'v1',
    providerChecksums: const {'md5': 'abc'},
    canDownload: downloadable);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final system = SystemModel.supportedSystems.firstWhere((s) => s.id == 'nes');
  GameDetailController controller(_Queue queue, List<GameItem> variants,
          {bool installed = false, bool localOnly = false}) =>
      GameDetailController(
          game: variants.first,
          variants: variants,
          system: system,
          targetFolder: '/fixture',
          queueManager: queue,
          romManager: _Roms(installed: installed),
          isLocalOnly: localOnly);

  test('an installed exact copy opens instead of attempting unowned removal',
      () async {
    final queue = _Queue();
    final remote = GameItem(
        filename: 'Game.7z',
        displayName: 'Game',
        url: '',
        providerConfig: drive,
        remoteArtifact: artifact());
    final detail = controller(queue, [remote], installed: true);
    addTearDown(detail.dispose);
    var opens = 0;
    detail.onOpenLocal = () async {
      opens++;
    };
    await detail.checkInstallationStatus();
    expect(detail.canOpenSelected, isTrue);
    expect(detail.canRemoveSelected, isFalse);
    expect(detail.canShareSelected, isFalse);
    await detail.performAction();
    expect(opens, 1);
    expect(detail.state.showDeleteDialog, isFalse);
    expect(queue.access, 0);
  });

  test('a missing local ROM in a remote-enabled console never enters the queue',
      () async {
    final queue = _Queue();
    final detail = controller(queue, [local]);
    addTearDown(detail.dispose);
    await detail.checkInstallationStatus();
    await detail.performAction();
    expect(await detail.addToQueue(), isFalse);
    expect(await detail.addVariantToQueue(0), isFalse);
    expect(queue.access, 0);
    expect(detail.state.error, isNull);
  });

  test('a mixed variant picker queues only the selected downloadable source',
      () async {
    final queue = _Queue();
    final remote = local.copyWith(
        providerConfig: web, url: 'https://example.invalid/game');
    final detail = controller(queue, [local, remote]);
    addTearDown(detail.dispose);
    await detail.checkInstallationStatus();
    await detail.performAction();
    expect(detail.state.activeOverlay, ActiveOverlay.variantPicker);
    expect(await detail.addVariantToQueue(0), isFalse);
    expect(queue.access, 0);
    await detail.addVariantToQueue(1);
    expect(queue.added, [same(remote)]);
  });

  test('an installed local ROM remains manageable without a download source',
      () async {
    final queue = _Queue();
    final detail = controller(queue, [local], installed: true);
    addTearDown(detail.dispose);
    await detail.checkInstallationStatus();
    await detail.performAction();
    expect(detail.state.showDeleteDialog, isTrue);
    expect(detail.canShareSelected, isTrue);
    detail.setSharing(true);
    expect(detail.canShareSelected, isFalse);
    detail.setSharing(false);
    expect(detail.canShareSelected, isTrue);
    expect(queue.access, 0);
  });

  test(
      'Drive eligibility requires its exact artifact and downloadable capability',
      () async {
    for (final game in [
      local.copyWith(providerConfig: drive),
      local.copyWith(
          providerConfig: drive, remoteArtifact: artifact(downloadable: false)),
      local.copyWith(remoteArtifact: artifact())
    ]) {
      final queue = _Queue();
      final detail = controller(queue, [game]);
      await detail.checkInstallationStatus();
      expect(await detail.addToQueue(), isFalse);
      expect(queue.access, 0);
      detail.dispose();
    }
    final queue = _Queue();
    final remote =
        local.copyWith(providerConfig: drive, remoteArtifact: artifact());
    final detail = controller(queue, [remote]);
    addTearDown(detail.dispose);
    await detail.checkInstallationStatus();
    await detail.addToQueue();
    expect(queue.added, [same(remote)]);
  });

  test('explicit local-only mode still prevents direct variant queue calls',
      () async {
    final queue = _Queue();
    final detail = controller(queue, [local.copyWith(providerConfig: web)],
        localOnly: true);
    addTearDown(detail.dispose);
    await detail.checkInstallationStatus();
    expect(await detail.addVariantToQueue(0), isFalse);
    expect(await detail.addToQueue(), isFalse);
    expect(queue.access, 0);
  });
}
