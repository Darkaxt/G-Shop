import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/patch_catalogue.dart';
import 'package:g_shop/models/portable_patch_recipe.dart';

PatchRecipe portableRecipeFixture({String root = 'GBA'}) => PatchRecipe(
    platformId: 'gba',
    base: IndexedPatchBase(
        relativePath: PatchRelativePath('$root/original.7z'),
        archiveMember: PatchRelativePath('Original.gba'),
        sizeBytes: 4,
        checksums: {'sha256': 'a' * 64}),
    steps: [
      PatchRecipeStep(
          source: 'Synthetic',
          section: 'hacks',
          sourceId: '42',
          version: '1.0',
          format: PatchFormat.ips,
          patchSha256: 'b' * 64)
    ],
    engineRevision: 'reviewed-engine');

PortablePatchRecipe portableFixture({String root = 'GBA', String? output}) =>
    PortablePatchRecipe(
        recipe: portableRecipeFixture(root: root),
        sourceGameId: '1379',
        gameTitle: 'Original',
        gameIndexPath: PatchRelativePath('$root/Patches/Original/game.json'),
        title: 'Original — Balance',
        outputSize: output == null ? null : 4,
        outputSha256: output);

void main() {
  test('portable share excludes residency and credentials but retains content',
      () {
    final portable = PortablePatchRecipe.fromBuild({
      'recipe': portableRecipeFixture().toJson(),
      'sourceGameId': '1379',
      'gameTitle': 'Original',
      'gameIndexPath': 'GBA/Patches/Original/game.json',
      'title': 'Original — Balance',
      'state': 'ready',
      'jobRoot': '/data/user/0/private',
      'targetRoot': '/storage/PRIVATE/Roms',
      'providerSourceId': 'private-cloud-source',
      'inputTransfers': ['private-transfer'],
      'credentials': 'private-api-secret',
      'outputArtifact': {
        'id': {'accountId': 'private-account'},
        'sizeBytes': 4,
        'providerChecksums': {'sha256': 'c' * 64}
      }
    });
    final json = portable.encode();
    for (final private in [
      'private',
      'jobRoot',
      'targetRoot',
      'providerSourceId',
      'inputTransfers',
      'credentials',
      'accountId',
      'installationId',
      'state'
    ]) {
      expect(json, isNot(contains(private)));
    }
    final restored = PortablePatchRecipe.decode(json);
    expect(restored.recipe.id, portable.recipe.id);
    expect(restored.outputSha256, 'c' * 64);
    expect(restored.outputSize, 4);
    expect(portableFixture(root: 'Renamed collection').recipe.id,
        portable.recipe.id);
  });

  test('unsafe or altered public recipes fail before storage or resolution',
      () {
    final json = portableFixture().toJson();
    for (final altered in [
      {...json, 'schema': 'unknown'},
      {...json, 'recipeId': 'f' * 64},
      {...json, 'accountId': 'private'},
      {...json, 'gameIndexPath': '../private/game.json'},
      {...json, 'outputSize': 4},
      {
        ...json,
        'recipe': {...json['recipe'] as Map, 'credentials': 'secret'}
      },
    ]) {
      expect(() => PortablePatchRecipe.decode(jsonEncode(altered)),
          throwsFormatException);
    }
    expect(() => PortablePatchRecipe.decode(' ' * (256 * 1024 + 1)),
        throwsFormatException);
  });
}
