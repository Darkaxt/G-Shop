import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:g_shop/models/patch_catalogue.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/portable_patch_recipe.dart';
import 'package:g_shop/services/drive/drive_patch_catalogue.dart';
import 'package:g_shop/services/metadata/shared_metadata_store.dart';
import 'package:g_shop/services/patch_build_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'portable_patch_recipe_test.dart' show portableFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('version six metadata survives adding shared recipes', () async {
    final root = await Directory.systemTemp.createTemp('rshop-recipe-upgrade-');
    final old = await databaseFactoryFfiNoIsolate.openDatabase(
        p.join(root.path, 'metadata.sqlite'),
        options: OpenDatabaseOptions(
            version: 6,
            onCreate: (db, _) async {
              await db.execute('PRAGMA application_id = 1381190961');
              await db.execute('''CREATE TABLE records (
                edition_id TEXT NOT NULL, provider_id TEXT NOT NULL,
                identity_key TEXT NOT NULL, generation INTEGER NOT NULL,
                game_json TEXT NOT NULL, edition_json TEXT NOT NULL,
                artifacts_json TEXT NOT NULL, record_json TEXT NOT NULL,
                PRIMARY KEY (edition_id, provider_id))''');
              await db.insert('records', {
                'edition_id': 'existing',
                'provider_id': 'igdb',
                'identity_key': 'existing',
                'generation': 1,
                'game_json': jsonEncode(GameIdentity(
                        id: 'existing', platformId: 'gba', title: 'Synthetic')
                    .toJson()),
                'edition_json': '{}',
                'artifacts_json': '[]',
                'record_json': 'existing scraped metadata',
              });
            }));
    await old.close();
    final shared = await SharedMetadataStore.open(root,
        existingOnly: true, factory: databaseFactoryFfiNoIsolate);
    await shared.putPatchRecipe(portableFixture());
    expect((await shared.patchRecipes('gba')).single.recipe.id,
        portableFixture().recipe.id);
    await shared.close();
    final reopened = await databaseFactoryFfiNoIsolate
        .openDatabase(p.join(root.path, 'metadata.sqlite'));
    expect((await reopened.query('records')).single['record_json'],
        'existing scraped metadata');
    expect(await reopened.getVersion(), 8);
    await reopened.close();
  });

  test('independent app roots import/reconnect without copying residency',
      () async {
    final root = await Directory.systemTemp.createTemp('rshop-shared-recipes-');
    final a = await databaseFactoryFfiNoIsolate
        .openDatabase(p.join(root.path, 'a.db'));
    final b = await databaseFactoryFfiNoIsolate
        .openDatabase(p.join(root.path, 'b.db'));
    await PatchBuildSchema.install(a);
    await PatchBuildSchema.install(b);
    final sharedA = await SharedMetadataStore.open(
        Directory(p.join(root.path, 'shared-a')),
        factory: databaseFactoryFfiNoIsolate);
    var sharedB = await SharedMetadataStore.open(
        Directory(p.join(root.path, 'shared-b')),
        factory: databaseFactoryFfiNoIsolate);
    addTearDown(() async {
      await sharedA.close();
      await sharedB.close();
      await a.close();
      await b.close();
    });
    final ownerA =
        PatchBuildStore(Future.value(a), sharedStore: Future.value(sharedA));
    final portable = portableFixture(output: 'c' * 64);
    await ownerA.begin(
        buildId: 'sender-build',
        recipe: portable.recipe,
        sourceGameId: portable.sourceGameId,
        gameTitle: portable.gameTitle,
        gameIndexPath: portable.gameIndexPath.value,
        providerSourceId: 'sender-private-source',
        title: portable.title,
        jobRoot: '/sender/private',
        targetRoot: '/sender/sd',
        filename: 'result.gba');
    await ownerA.update(
        'sender-build',
        {
          'outputArtifact': {
            'sizeBytes': 4,
            'providerChecksums': {'sha256': 'c' * 64}
          }
        },
        state: 'ready');
    expect(await ownerA.hasForPlatform('gba'), isTrue);
    expect(await ownerA.hasForPlatform('gameandwatch'), isFalse);
    expect(await sharedA.patchRecipes('gba'), isEmpty,
        reason: 'Navigation availability never publishes ready builds');
    await ownerA.forGame('gba', '1379');
    final exported = (await sharedA.patchRecipes('gba')).single.encode();
    final ownerB =
        PatchBuildStore(Future.value(b), sharedStore: Future.value(sharedB));
    await ownerB.importRecipe(PortablePatchRecipe.decode(exported));
    expect(await ownerB.hasForPlatform('gba'), isTrue,
        reason: 'Shared recipes retain the patch entry without a local build');
    expect(await b.query('patch_builds'), isEmpty);
    final restored = (await ownerB.forGame('gba', '1379')).single;
    expect(restored['state'], 'recipe');
    for (final key in [
      'buildId',
      'jobRoot',
      'targetRoot',
      'game',
      'transferId',
      'inputTransfers'
    ]) {
      expect(restored.containsKey(key), isFalse);
    }
    expect(await b.query('patch_builds'), isEmpty);
    expect((await a.query('patch_builds')).single['state'], 'ready');
    await sharedB.close();
    sharedB = await SharedMetadataStore.open(
        Directory(p.join(root.path, 'shared-b')),
        existingOnly: true,
        factory: databaseFactoryFfiNoIsolate);
    final reopened =
        PatchBuildStore(Future.value(b), sharedStore: Future.value(sharedB));
    final recipe = (await reopened.forPlatform('gba')).single;
    expect(
        PatchRecipe.fromJson((recipe['recipe'] as Map).cast<String, dynamic>())
            .id,
        portable.recipe.id);
    await expectLater(reopened.importRecipe(portableFixture(output: 'd' * 64)),
        throwsFormatException);
    expect((await sharedB.patchRecipes('gba')).single.outputSha256, 'c' * 64);
  });

  test(
      'unavailable shared publication preserves ready and resumes on reconnect',
      () async {
    final root =
        await Directory.systemTemp.createTemp('rshop-recipe-reconnect-');
    final db =
        await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    await PatchBuildSchema.install(db);
    final shared = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate);
    addTearDown(() async {
      await shared.close();
      await db.close();
    });
    final store =
        PatchBuildStore(Future.value(db), sharedStore: Future.value(null));
    final portable = portableFixture(output: 'c' * 64);
    await store.begin(
        buildId: 'local',
        recipe: portable.recipe,
        sourceGameId: portable.sourceGameId,
        gameTitle: portable.gameTitle,
        gameIndexPath: portable.gameIndexPath.value,
        providerSourceId: 'local-only',
        title: portable.title,
        jobRoot: '/private/job',
        targetRoot: '/sd/Hacks',
        filename: 'result.gba');
    await store.update(
        'local',
        {
          'outputArtifact': {
            'sizeBytes': 4,
            'providerChecksums': {'sha256': 'c' * 64}
          }
        },
        state: 'ready');
    await store.publishReady('local');
    expect((await store.get('local'))!['state'], 'ready');
    expect((await store.get('local'))!['shareIssue'],
        'shared_storage_unavailable');
    final reconnected =
        PatchBuildStore(Future.value(db), sharedStore: Future.value(shared));
    await reconnected.forPlatform('gba');
    expect((await shared.patchRecipes('gba')).single.recipe.id,
        portable.recipe.id);
    expect((await reconnected.get('local'))!['shareIssue'], isNull);
  });

  test('destination index resolves by complete content, not sender names', () {
    final portable = portableFixture();
    final game = IndexedPatchGame('1379', 'Renamed title',
        PatchRelativePath('Other/Patches/New name/game.json'));
    IndexedRomPatch patch(String digest) => IndexedRomPatch(
            source: 'Synthetic',
            section: 'hacks',
            sourceId: '42',
            title: 'Balance',
            version: '1.0',
            description: '',
            bases: [
              IndexedPatchBase(
                  relativePath: PatchRelativePath('Other/Renamed.7z'),
                  archiveMember: PatchRelativePath('Renamed.gba'),
                  sizeBytes: 4,
                  checksums: {'sha256': digest})
            ],
            payloads: [
              IndexedPatchPayload(
                  relativePath: 'Other/Patches/renamed.ips',
                  sizeBytes: 14,
                  sha256: 'b' * 64,
                  format: PatchFormat.ips)
            ],
            unsupportedFiles: []);
    final resolved =
        DrivePatchCatalogue.matchRecipe(portable, game, [patch('a' * 64)]);
    expect(resolved!.base.relativePath.value, 'Other/Renamed.7z');
    expect(resolved.base.archiveMember!.value, 'Renamed.gba');
    expect(DrivePatchCatalogue.matchRecipe(portable, game, [patch('f' * 64)]),
        isNull);
    expect(() => PortablePatchRecipe(
        recipe: PatchRecipe(
            platformId: 'gba',
            base: portable.recipe.base,
            steps: [...portable.recipe.steps, ...portable.recipe.steps],
            engineRevision: portable.recipe.engineRevision),
        sourceGameId: '1379',
        gameTitle: 'Original',
        gameIndexPath: game.indexPath,
        title: 'Undeclared chain'), throwsFormatException);
  });
}
