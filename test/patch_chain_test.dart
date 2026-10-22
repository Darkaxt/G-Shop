import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/patch_catalogue.dart';
import 'package:g_shop/models/patch_chain.dart';
import 'package:g_shop/models/portable_patch_recipe.dart';
import 'package:g_shop/services/drive/drive_patch_catalogue.dart';

IndexedRomPatch patch(String id, {PatchDependency? requires}) =>
    IndexedRomPatch(
        source: 'fixture',
        section: 'hacks',
        sourceId: id,
        title: id,
        version: '1',
        description: '',
        bases: requires == null
            ? [
                IndexedPatchBase(
                    relativePath: PatchRelativePath('GBA/original.gba'),
                    sizeBytes: 4,
                    checksums: {'sha256': 'a' * 64})
              ]
            : [],
        payloads: [
          IndexedPatchPayload(
              relativePath: 'GBA/Patches/$id.ips',
              sizeBytes: 8,
              sha256: id.padRight(64, 'a'),
              format: PatchFormat.ips)
        ],
        unsupportedFiles: [],
        requires: requires);

PatchDependency dependency(IndexedRomPatch parent) => PatchDependency(
    step: PatchRecipeStep.fromPatch(parent, parent.payloads.single),
    outputSize: 4,
    outputHashes: {'sha256': 'e' * 64});

void main() {
  test('nested prerequisites resolve root first and bind intermediate bytes',
      () {
    final first = patch('1');
    final second = patch('2', requires: dependency(first));
    final third = patch('3', requires: dependency(second));
    final chain = PatchChain.resolve(
        [third, first, second], third, third.payloads.single);
    expect(chain.steps.map((s) => s.patch.sourceId), ['1', '2', '3']);
    expect(chain.bases.single.relativePath.value, 'GBA/original.gba');
    final steps = chain.recipeSteps;
    expect(steps[1].inputSize, 4);
    expect(steps[1].inputHashes, {'sha256': 'e' * 64});
    expect(PatchRecipeStep.fromJson(steps[1].toJson()).toJson(),
        steps[1].toJson());
    final recipe = PatchRecipe(
        platformId: 'gba',
        base: chain.bases.single,
        steps: steps,
        engineRevision: 'fixture');
    final portable = PortablePatchRecipe(
        recipe: recipe,
        sourceGameId: '1',
        gameTitle: 'Original',
        gameIndexPath: PatchRelativePath('GBA/Patches/game.json'),
        title: 'Third');
    final restored = PortablePatchRecipe.decode(portable.encode());
    final resolved = DrivePatchCatalogue.matchRecipe(
        restored,
        IndexedPatchGame(
            '1', 'Original', PatchRelativePath('OtherRoot/game.json')),
        [third, second, first]);
    expect(resolved?.patch.sourceId, '3');
    expect(resolved?.availablePatches, hasLength(3));
    expect(
        DrivePatchCatalogue.matchRecipe(
            restored,
            IndexedPatchGame(
                '1', 'Original', PatchRelativePath('OtherRoot/game.json')),
            [third, first]),
        isNull);
  });
  test('missing, changed-version, ambiguous and cyclic prerequisites reject',
      () {
    final first = patch('1');
    final second = patch('2', requires: dependency(first));
    expect(() => PatchChain.resolve([second], second, second.payloads.single),
        throwsFormatException);
    expect(
        () => PatchChain.resolve(
            [first, first, second], second, second.payloads.single),
        throwsFormatException);
    final self = patch('1', requires: dependency(first));
    expect(() => PatchChain.resolve([self], self, self.payloads.single),
        throwsFormatException);
    final changed = IndexedRomPatch(
        source: first.source,
        section: first.section,
        sourceId: first.sourceId,
        title: first.title,
        version: '2',
        description: '',
        bases: first.bases,
        payloads: first.payloads,
        unsupportedFiles: []);
    expect(
        () => PatchChain.resolve(
            [changed, second], second, second.payloads.single),
        throwsFormatException);
  });
}
