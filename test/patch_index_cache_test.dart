import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/services/drive/drive_catalogue.dart';

void main() {
  test(
      'cached indexes and base links are bound to source, content and snapshot',
      () async {
    sqfliteFfiInit();
    final db =
        await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await DriveCatalogueSchema.installPatchIndexCache(db);
    final cache = DriveCatalogue(Future.value(db));
    RemoteArtifact artifact(String source, String version) => RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: source,
            accountId: 'a',
            providerFileId: 'index'),
        displayName: 'index.json',
        displayPath: 'Patches/index.json',
        version: version,
        sizeBytes: 9,
        providerChecksums: {'md5': 'a' * 32});
    await cache.cachePatchIndex(artifact('one', '1'), {'schema_version': 2});
    expect(await cache.cachedPatchIndex(artifact('one', '1')),
        {'schema_version': 2});
    expect(await cache.cachedPatchIndex(artifact('one', '2')), isNull);
    expect(await cache.cachedPatchIndex(artifact('two', '1')), isNull);
    await cache.cachePatchBaseLinks(
        scope: 'one',
        generation: 1,
        folderId: 'gba',
        indexPath: 'GBA/Patches/game.json',
        gameId: '1',
        title: 'Original',
        baseFileIds: {'base'});
    Future<List<Map<String, Object?>>> links(
            {String scope = 'one', int generation = 1, String id = 'base'}) =>
        cache.cachedPatchGames(
            scope: scope,
            generation: generation,
            folderId: 'gba',
            baseFileId: id);
    expect(await links(), hasLength(1));
    expect(await links(scope: 'two'), isEmpty);
    expect(await links(generation: 2), isEmpty);
    expect(await links(id: 'same-title-other-revision'), isEmpty);
  });
}
