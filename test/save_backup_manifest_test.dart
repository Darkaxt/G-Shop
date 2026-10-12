import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/save_backup_manifest.dart';

SaveBackupBinding binding({
  String account = 'account',
  String device = 'device-a',
  String edition = 'edition-a',
  String emulator = 'com.retroarch.aarch64',
  String version = '1.22.2',
  SaveBackupKind kind = SaveBackupKind.save,
}) =>
    SaveBackupBinding(
        accountId: account,
        deviceId: device,
        emulatorPackage: emulator,
        emulatorVersion: version,
        coreId: 'mgba',
        coreVersion: '0.10.5',
        platformId: 'gba',
        editions: [SaveBackupEdition(gameId: 'game-a', editionId: edition)],
        kind: kind,
        formatId:
            kind == SaveBackupKind.save ? 'gba-save-ram' : 'mgba-state-v1');

SaveBackupMember member(String path, String id, {String digest = 'a'}) =>
    SaveBackupMember(
        relativePath: path,
        cloudFileId: id,
        sizeBytes: 8192,
        sha256: List.filled(64, digest).join());

SaveBackupManifest manifest({
  SaveBackupBinding? forBinding,
  List<SaveBackupMember>? members,
  List<String> parents = const [],
}) =>
    SaveBackupManifest(
        generationId: 'generation-a',
        binding: forBinding ?? binding(),
        parentGenerationIds: parents,
        createdAt: DateTime.utc(2026, 10, 9),
        members: members ?? [member('Pokemon.srm', 'member-a')]);

void main() {
  test(
      'portable groups preserve empty companions but an empty state is invalid',
      () {
    final empty = SaveBackupMember(
        relativePath: 'ULUS10001DATA00/EMPTY',
        cloudFileId: 'empty-companion',
        sizeBytes: 0,
        sha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    final group = manifest(
        members: [member('ULUS10001DATA00/PARAM.SFO', 'metadata'), empty]);
    final decoded = SaveBackupManifest.decode(group.encode());
    expect(decoded.members.first.relativePath, 'ULUS10001DATA00/EMPTY');
    expect(decoded.members.first.sizeBytes, 0);
    expect(decoded.contentDigest, group.contentDigest);
    expect(
        () => manifest(
            forBinding: binding(kind: SaveBackupKind.state), members: [empty]),
        throwsFormatException);
    expect(
        () => SaveBackupMember(
            relativePath: 'negative',
            cloudFileId: 'negative',
            sizeBytes: -1,
            sha256: empty.sha256),
        throwsFormatException);
  });
  test(
      'complete manifest round trip retains exact binding, members and ancestry',
      () {
    final original = manifest(parents: ['previous-generation']);
    final restored = SaveBackupManifest.decode(original.encode());
    expect(restored.binding.key, original.binding.key);
    expect(restored.generationId, 'generation-a');
    expect(restored.parentGenerationIds, ['previous-generation']);
    expect(restored.members.single.relativePath, 'Pokemon.srm');
    expect(restored.contentDigest, original.contentDigest);
    expect(
        jsonDecode(utf8.decode(original.encode())), isNot(contains('token')));
  });

  test(
      'content digest is order independent but detects changed bytes and paths',
      () {
    final one = member('Pokemon.srm', 'member-a');
    final two = member('Pokemon.rtc', 'member-b', digest: 'b');
    final first = manifest(members: [one, two]);
    expect(manifest(members: [two, one]).contentDigest, first.contentDigest);
    expect(
        manifest(members: [member('Pokemon.srm', 'member-c'), two])
            .contentDigest,
        first.contentDigest); // A re-upload is not a changed save.
    expect(manifest(members: [one]).contentDigest, isNot(first.contentDigest));
    expect(
        manifest(members: [member('Other.srm', 'member-a'), two]).contentDigest,
        isNot(first.contentDigest));
  });

  test('malformed, aliased and escaping members cannot form a restore manifest',
      () {
    for (final path in [
      '../Pokemon.srm',
      '/Pokemon.srm',
      'folder/../Pokemon.srm',
      r'folder\Pokemon.srm',
      'folder//Pokemon.srm',
      'Pokemon.srm.',
      'C:Pokemon.srm',
      'Pokemon\u0000.srm',
    ]) {
      expect(() => member(path, 'member-a'), throwsFormatException,
          reason: path);
    }
    expect(() => manifest(members: []), throwsFormatException);
    expect(
        () => manifest(members: [
              member('Pokemon.srm', 'member-a'),
              member('pokemon.srm', 'member-b')
            ]),
        throwsFormatException);
    expect(
        () => manifest(members: [
              member('Pokemon.srm', 'member-a'),
              member('Other.srm', 'member-a')
            ]),
        throwsFormatException);
    expect(() => manifest(members: [member('Pokemon.srm', 'generation-a')]),
        throwsFormatException);
    expect(
        () => SaveBackupMember(
            relativePath: 'empty.sav',
            cloudFileId: 'member-a',
            sizeBytes: 0,
            sha256: 'a' * 64),
        throwsFormatException);
  });

  test('decode rejects oversized, foreign schema and altered group digests',
      () {
    expect(() => SaveBackupManifest.decode(List.filled(1024 * 1024 + 1, 32)),
        throwsFormatException);
    final data = jsonDecode(utf8.decode(manifest().encode())) as Map;
    for (final change in [
      {'schema': 2},
      {'contentDigest': 'b' * 64},
      {'accessToken': 'must-never-be-accepted'},
      {
        'parentGenerationIds': ['generation-a']
      },
    ]) {
      expect(
          () => SaveBackupManifest.decode(
              utf8.encode(jsonEncode({...data, ...change}))),
          throwsFormatException);
    }
  });

  test('restore comparison isolates account, edition, format and state runtime',
      () {
    final save = binding();
    expect(save.restoreIssue(binding(device: 'new-device')), isNull);
    expect(save.restoreIssue(binding(account: 'other')), 'accountMismatch');
    expect(save.restoreIssue(binding(edition: 'translation-edition')),
        'editionMismatch');
    expect(save.restoreIssue(binding(kind: SaveBackupKind.state)),
        'formatMismatch');
    expect(save.restoreIssue(binding(version: 'new-runtime')), isNull);
    final state = binding(kind: SaveBackupKind.state);
    expect(
        state.restoreIssue(binding(kind: SaveBackupKind.state, device: 'new')),
        isNull);
    expect(
        state.restoreIssue(
            binding(kind: SaveBackupKind.state, version: 'different')),
        'stateCompatibility');
    expect(
        state.restoreIssue(
            binding(kind: SaveBackupKind.state, emulator: 'other.emulator')),
        'stateCompatibility');
  });

  test('ancestry reconciliation uses content, never modification time', () {
    final a = 'a' * 64, b = 'b' * 64, c = 'c' * 64;
    expect(
        reconcileSaveBackup(local: a, cloud: a), SaveBackupRelation.identical);
    expect(reconcileSaveBackup(local: a, cloud: b, base: a),
        SaveBackupRelation.cloudChanged);
    expect(reconcileSaveBackup(local: b, cloud: a, base: a),
        SaveBackupRelation.localChanged);
    expect(reconcileSaveBackup(local: b, cloud: c, base: a),
        SaveBackupRelation.conflict);
    expect(
        reconcileSaveBackup(local: b, cloud: a), SaveBackupRelation.conflict);
  });
}
