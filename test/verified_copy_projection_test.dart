import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/config/provider_config.dart';
import 'package:g_shop/models/game_item.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/utils/game_merge_helper.dart';

RemoteArtifact artifact({String version = '1', String file = 'file'}) =>
    RemoteArtifact(
      id: RemoteArtifactId(
          providerId: 'drive',
          sourceId: 'source',
          accountId: 'account',
          providerFileId: file),
      parentId: 'folder',
      displayName: 'Renamed.7z',
      displayPath: 'Renamed.7z',
      version: version,
      sizeBytes: 5,
      providerChecksums: {'md5': 'a' * 32},
      canDownload: true,
    );

GameItem cloud(RemoteArtifact remote) => GameItem(
    filename: 'Renamed.7z',
    displayName: 'Game',
    url: '',
    remoteArtifact: remote,
    providerConfig:
        const ProviderConfig(type: ProviderType.drive, priority: 0));

void main() {
  const local = GameItem(filename: 'Old.7z', displayName: 'Game', url: '');
  test(
      'verified current or missing copy projects to its sourced stable identity',
      () {
    final remote = cloud(artifact());
    final input = [local, remote];
    final aliases = {'Old.7z': artifact()};
    expect(GameMergeHelper.verifiedSelectionAliases(input, aliases),
        {'Old.7z': remote.selectionKey});
    expect(GameMergeHelper.coalesceVerifiedCopies(input, aliases), [remote]);
    // Projection does not mutate historical cache membership or captured jobs.
    expect(input, [local, remote]);
  });
  test('namesakes, changed versions and foreign identities stay separate', () {
    final remote = cloud(artifact(version: '2'));
    expect(
        GameMergeHelper.coalesceVerifiedCopies(
            [local, remote], {'Old.7z': artifact()}),
        [local, remote]);
    expect(
        GameMergeHelper.coalesceVerifiedCopies(
            [local, cloud(artifact())], const {}),
        hasLength(2));
    expect(
        GameMergeHelper.coalesceVerifiedCopies(
            [local, cloud(artifact(file: 'hack'))], {'Old.7z': artifact()}),
        hasLength(2));
  });
  test(
      'another provider source cannot be hidden by a local filename observation',
      () {
    final other = local.copyWith(
        providerConfig: const ProviderConfig(
            type: ProviderType.web,
            priority: 0,
            url: 'https://example.invalid/'));
    final remote = cloud(artifact());
    expect(
        GameMergeHelper.verifiedSelectionAliases(
            [other, remote], {'Old.7z': artifact()}),
        isEmpty);
    expect(
        GameMergeHelper.coalesceVerifiedCopies(
            [other, remote], {'Old.7z': artifact()}),
        [other, remote]);
  });
  test('an exact local scan cannot replace the sourced cloud card or artwork',
      () {
    final remote = cloud(artifact()).copyWith(cachedCoverUrl: 'cached-cover');
    final exactLocal = local.copyWith(remoteArtifact: artifact());
    expect(
        GameMergeHelper.coalesceVerifiedCopies([exactLocal, remote], const {}),
        [remote]);
    expect(
        GameMergeHelper.coalesceVerifiedCopies([remote, exactLocal], const {}),
        [remote]);
  });
}
