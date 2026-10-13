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
  SaveBackupBinding companion({
    String compatibility = 'portable',
    String version = '1.22.2',
    String coreVersion = '0.10.5',
    String edition = 'edition-a',
    String device = 'device-a',
  }) =>
      SaveBackupBinding.fromJson({
        ...binding(version: version, edition: edition, device: device).toJson(),
        'coreVersion': coreVersion,
        'kind': 'companion',
        'formatId': 'rom-companion-v1',
        'companionCompatibility': compatibility,
      });

  test('portable ROM companions retain their own identity and explicit policy',
      () {
    final original = manifest(
        forBinding: companion(),
        members: [member('screenshots/Game.png', 'image')]);
    final decoded = SaveBackupManifest.decode(original.encode());
    expect(decoded.binding.kind.name, 'companion');
    expect(decoded.binding.toJson()['companionCompatibility'], 'portable');
    expect(decoded.binding.restoreIssue(companion(version: 'next')), isNull);
    expect(decoded.binding.restoreIssue(companion(device: 'other')), isNull);
    expect(decoded.binding.restoreIssue(companion(edition: 'other')),
        'editionMismatch');
    expect(decoded.binding.restoreIssue(binding()), 'formatMismatch');
    expect(binding().toJson(), isNot(contains('companionCompatibility')));
    expect(binding(kind: SaveBackupKind.state).toJson(),
        isNot(contains('companionCompatibility')));
  });

  test('runtime companions reject cache format runtime or policy mismatches',
      () {
    final cached = companion(compatibility: 'runtime');
    expect(cached.restoreIssue(companion(compatibility: 'runtime')), isNull);
    expect(
        cached
            .restoreIssue(companion(compatibility: 'runtime', version: 'next')),
        'companionCompatibility');
    expect(
        cached.restoreIssue(
            companion(compatibility: 'runtime', coreVersion: 'next')),
        'companionCompatibility');
    expect(cached.restoreIssue(companion()), 'companionCompatibility');
    expect(companion().restoreIssue(cached), 'companionCompatibility');
    for (final change in [
      {'companionCompatibility': null},
      {'companionCompatibility': 'unknown'},
      {'kind': 'save'},
      {'kind': 'state'},
    ]) {
      expect(() => SaveBackupBinding.fromJson({...cached.toJson(), ...change}),
          throwsFormatException);
    }
    final missing = {...cached.toJson()}..remove('companionCompatibility');
    expect(() => SaveBackupBinding.fromJson(missing), throwsFormatException);
  });

  test('shared PS1 card history survives different initiating game editions',
      () {
    Map<String, dynamic> card(String edition,
            {int slot = 2,
            String directory =
                '/storage/emulated/0/RetroArch/saves/PCSX-ReARMed'}) =>
        {
          ...binding(edition: edition).toJson(),
          'platformId': 'psx',
          'coreId': 'pcsx_rearmed',
          'formatId': 'pcsx-shared-card$slot-v1',
          'sharedCard': {'directory': directory, 'slot': slot},
        };
    final first = SaveBackupBinding.fromJson(card('edition-a'));
    final second = SaveBackupBinding.fromJson(card('edition-b'));
    expect(first.restoreIssue(second), isNull);
    expect(first.editions.single.editionId, 'edition-a');
    expect(second.editions.single.editionId, 'edition-b');
    final restored =
        SaveBackupManifest.decode(manifest(forBinding: first).encode());
    expect(restored.binding.toJson(), first.toJson());
    expect(
        first.restoreIssue(
            SaveBackupBinding.fromJson(card('edition-a', slot: 1))),
        'editionMismatch');
    expect(
        first.restoreIssue(SaveBackupBinding.fromJson(
            card('edition-a', directory: '/storage/emulated/0/Other'))),
        'editionMismatch');
    final privateCard = card('edition-a')..remove('sharedCard');
    expect(first.restoreIssue(SaveBackupBinding.fromJson(privateCard)),
        'editionMismatch');
    for (final change in [
      {'platformId': 'gba'},
      {'coreId': 'mgba'},
      {'emulatorPackage': 'other'},
      {'kind': 'state'},
      {'formatId': 'pcsx-libretro-card1-v1'},
      {
        'sharedCard': {'directory': '/storage/emulated/0/../Other', 'slot': 2}
      },
      {
        'sharedCard': {'directory': '/storage/emulated/0/Other', 'slot': 3}
      },
      {
        'sharedCard': {
          'directory': '/storage/emulated/0/Other',
          'slot': 2,
          'extra': true
        }
      },
    ]) {
      expect(
          () => SaveBackupBinding.fromJson({...card('edition-a'), ...change}),
          throwsFormatException);
    }
    expect(
        first.restoreIssue(SaveBackupBinding.fromJson(
            {...card('edition-a'), 'accountId': 'other'})),
        'accountMismatch');
    // Existing bindings retain their byte-for-byte metadata/hash representation.
    expect(binding().toJson(), isNot(contains('sharedCard')));
  });
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
