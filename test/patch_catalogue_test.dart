import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/patch_catalogue.dart';

const digest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const otherDigest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, dynamic> sourceIndex({String version = '1.0'}) => {
      'schema_version': 2,
      'source': 'Fixture source',
      'source_game_id': 1379,
      'sections': {
        'hacks': [
          {
            'source_id': 7013,
            'source_fields': {'hacktitle': 'Balance', 'version': version},
            'rom_files': [
              {
                'rom_root_relative_path': 'GBA/Advance Wars.7z',
                'archive_member': 'Advance Wars.gba',
                'member_size': 4,
                'member_hashes': {'sha256': digest, 'crc32': '12345678'}
              }
            ]
          }
        ],
        'utilities': [
          {
            'source_id': 10,
            'source_fields': {'title': 'Editor'}
          }
        ]
      },
      'payloads': [
        {
          'section': 'hacks',
          'source_id': 7013,
          'role': 'package',
          'patch_folder_relative_path':
              'GBA/Patches/Advance Wars/Source/Balance',
          'extraction': {
            'status': 'extracted',
            'files': [
              {
                'relative_path': 'balance.ips',
                'size': 14,
                'sha256': otherDigest
              },
              {'relative_path': 'readme.txt', 'size': 10, 'sha256': digest},
              {'relative_path': 'installer.exe', 'size': 10, 'sha256': digest}
            ]
          }
        }
      ]
    };

void main() {
  test('schema 2 binds extracted patches to exact base member, not utilities',
      () {
    final catalogue = PatchSourceIndex.fromJson(sourceIndex());
    final patch = catalogue.patches.single;
    expect(patch.title, 'Balance');
    expect(patch.bases.single.archiveMember!.value, 'Advance Wars.gba');
    expect(patch.bases.single.checksums['sha256'], digest);
    expect(patch.payloads.single.relativePath,
        'GBA/Patches/Advance Wars/Source/Balance/balance.ips');
    expect(patch.payloads.single.format, PatchFormat.ips);
    expect(patch.unavailableReason, isNull);
  });

  test('translation extraction without package role uses the same parser', () {
    final json = sourceIndex();
    final payload = (json['payloads'] as List).single as Map;
    payload.remove('role');
    expect(
        PatchSourceIndex.fromJson(json).patches.single.payloads, hasLength(1));
  });

  test('installer-only patch is visible but cannot be built', () {
    final json = sourceIndex();
    ((json['payloads'] as List).single['extraction']['files'] as List)
        .removeAt(0);
    final patch = PatchSourceIndex.fromJson(json).patches.single;
    expect(patch.payloads, isEmpty);
    expect(patch.unavailableReason, 'no_supported_patch_payload');
  });

  test('root/member traversal and malformed fingerprints are rejected', () {
    for (final path in [
      '../outside.ips',
      '/absolute.ips',
      'C:/file.ips',
      r'bad\file.ips'
    ]) {
      expect(() => PatchRelativePath(path), throwsFormatException);
    }
    final json = sourceIndex();
    (json['sections']['hacks'] as List).single['rom_files'][0]
        ['member_hashes'] = {'sha256': 'not-a-hash'};
    expect(() => PatchSourceIndex.fromJson(json), throwsFormatException);
  });

  test('unrecognized schema is not silently treated as schema 2', () {
    final json = sourceIndex()..['schema_version'] = 99;
    expect(() => PatchSourceIndex.fromJson(json), throwsFormatException);
  });

  test('recipe identity survives restart and excludes source/device paths', () {
    final patch = PatchSourceIndex.fromJson(sourceIndex()).patches.single;
    final recipe = PatchRecipe(
        platformId: 'gba',
        base: patch.bases.single,
        steps: [PatchRecipeStep.fromPatch(patch, patch.payloads.single)],
        engineRevision: 'reviewed-engine');
    expect(PatchRecipe.fromJson(recipe.toJson()).id, recipe.id);
    final movedBase = IndexedPatchBase(
        relativePath: PatchRelativePath('Different root/renamed.7z'),
        archiveMember: PatchRelativePath('renamed.gba'),
        sizeBytes: 4,
        checksums: {'crc32': '12345678', 'sha256': digest});
    expect(
        PatchRecipe(
                platformId: 'gba',
                base: movedBase,
                steps: recipe.steps,
                engineRevision: 'reviewed-engine')
            .id,
        recipe.id);
    final changed =
        PatchSourceIndex.fromJson(sourceIndex(version: '2.0')).patches.single;
    expect(
        PatchRecipe(
                platformId: 'gba',
                base: recipe.base,
                steps: [
                  PatchRecipeStep.fromPatch(changed, changed.payloads.single)
                ],
                engineRevision: 'reviewed-engine')
            .id,
        isNot(recipe.id));
  });
}
