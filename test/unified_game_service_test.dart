import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/config/provider_config.dart';
import 'package:g_shop/models/config/system_config.dart';
import 'package:g_shop/models/config/drive_source_config.dart';
import 'package:g_shop/models/game_item.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/services/unified_game_service.dart';

void main() {
  const drive = DriveSourceConfig(
      accountId: 'account', rootFolderId: 'root', serverClientId: 'client');
  const first = ProviderConfig(
      type: ProviderType.drive,
      priority: 0,
      sourceId: 'one',
      path: 'gb',
      drive: drive);
  const second = ProviderConfig(
      type: ProviderType.drive,
      priority: 1,
      sourceId: 'two',
      path: 'gb',
      drive: drive);
  const old = ProviderConfig(
      type: ProviderType.web, priority: 2, url: 'https://example.invalid');
  SystemConfig system(List<ProviderConfig> providers) => SystemConfig(
      id: 'gb',
      name: 'Game Boy',
      targetFolder: '/preserved/gb',
      providers: providers);
  GameItem game(ProviderConfig config, {String account = 'account'}) =>
      GameItem(
          filename: 'same.gb',
          displayName: 'Same title',
          url: 'drive-artifact:opaque',
          providerConfig: config,
          remoteArtifact: RemoteArtifact(
              id: RemoteArtifactId(
                  providerId: 'drive',
                  accountId: account,
                  sourceId: config.sourceId!,
                  providerFileId: 'object'),
              displayPath: '/gb/same.gb',
              displayName: 'same.gb'));
  test(
      'production service keeps distinct scoped Drive identities and ignores retired adapters',
      () async {
    final called = <String>[];
    final service = UnifiedGameService(fetchProviderGames: (provider, _) async {
      called.add(provider.sourceId!);
      return [game(provider)];
    });
    final result =
        await service.fetchGamesForSystem(system([first, second, old]));
    expect(called, ['one', 'two']);
    expect(result.map((g) => g.identityKey).toSet().length, 2);
    expect(result.every((g) => g.alternativeSources.isEmpty), isTrue);
  });
  test(
      'a Drive failure rejects the complete refresh instead of publishing partial data',
      () async {
    final service = UnifiedGameService(fetchProviderGames: (provider, _) async {
      if (provider.sourceId == 'two') throw StateError('offline');
      return [game(provider)];
    });
    await expectLater(
        service.fetchGamesForSystem(system([first, second])), throwsStateError);
  });
  test('foreign-account records cannot be published as a configured collection',
      () async {
    final service = UnifiedGameService(
        fetchProviderGames: (provider, _) async =>
            [game(provider, account: 'foreign')]);
    await expectLater(
        service.fetchGamesForSystem(system([first])), throwsStateError);
  });
  test('one explicit sync session shares source preparation across consoles',
      () async {
    var preparations = 0;
    final service = UnifiedGameService(
        shareDrivePreparation: true,
        prepareDrive: (_) async {
          preparations++;
        },
        fetchProviderGames: (provider, _) async => [game(provider)]);
    await service.fetchGamesForSystem(system([first]));
    await service.fetchGamesForSystem(system([first]));
    expect(preparations, 1);
    await expectLater(
        service.fetchGamesForSystem(system([old])), throwsStateError);
  });
}
