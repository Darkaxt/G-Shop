import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/services/metadata/catalogue_publisher.dart';
import 'package:g_shop/services/metadata/metadata_artwork_cache.dart';
import 'package:g_shop/services/metadata/metadata_cloud_library.dart';
import 'package:g_shop/services/metadata/metadata_credentials.dart';
import 'package:g_shop/services/metadata/shared_metadata_store.dart';
import 'package:g_shop/providers/metadata_providers.dart';
import 'metadata_controls_test.dart'
    show controlsDatabase, ControlsArtworkProvider, MemorySecrets;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  Future<({SharedMetadataStore store, Directory root, ControlsArtworkProvider provider})>
      fixture() async {
    final root = await Directory.systemTemp.createTemp('gshop-catalogue-');
    final db = await controlsDatabase(path: '${root.path}/projection.sqlite');
    final store = await SharedMetadataStore.open(
        Directory('${root.path}/shared'),
        factory: databaseFactoryFfiNoIsolate,
        verifyAccess: () async {});
    final provider = ControlsArtworkProvider();
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        artworkCache: Future.value(MetadataArtworkCache(
            Future.value(db), store.artworkRoot,
            sharedStore: store)),
        sharedStore: Future.value(store),
        catalogueChanged: () {});
    await controls.load();
    await controls.refresh(systemSlug: 'psx');
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await store.close();
      await db.close();
      await root.delete(recursive: true);
    });
    return (store: store, root: root, provider: provider);
  }

  Future<CataloguePublishSummary> run(SharedMetadataStore store, Directory t) =>
      CataloguePublisher(store: store, catalogue: t).publish();

  test('publishes, is idempotent, and archives a replaced body', () async {
    final f = await fixture();
    final target = Directory('${f.root.path}/catalogue');
    final first = await run(f.store, target);
    expect(first.games, greaterThan(0));
    expect(first.filesWritten, greaterThan(1));
    final folders = Directory('${target.path}/psx').listSync();
    expect(folders, hasLength(1));
    final folder = folders.single.path;
    final manifest = jsonDecode(
        File('$folder/metadata.json').readAsStringSync()) as Map;
    final box = File('$folder/box.png');
    expect(box.existsSync(), isTrue);
    expect(manifest['resources']['box.png']['sha256'],
        sha256.convert(box.readAsBytesSync()).toString());
    expect((manifest['assets'] as List).first.containsKey('file_id'), isFalse);

    final second = await run(f.store, target);
    expect(second.filesWritten, 0);
    expect(second.archived, 0);

    final key = MetadataArtworkCache.key(f.provider.media);
    final original = (await f.store.cloudIndex.query('metadata_artwork_cache',
            where: 'media_key=?', whereArgs: [key]))
        .single;
    final old =
        File('${f.store.artworkRoot.path}/${original['filename']}');
    final changed = Uint8List.fromList([...await old.readAsBytes(), 0]);
    final name = '${sha256.convert(changed)}.png';
    await File('${f.store.artworkRoot.path}/$name').writeAsBytes(changed);
    await f.store.preserveBlob(MetadataArtworkBlob(key, name, changed.length),
        DateTime.now().toUtc());
    final third = await run(f.store, target);
    expect(third.filesWritten, greaterThan(0));
    final replaced = (await Directory(folder).list().toList())
        .whereType<File>()
        .where((x) => x.readAsBytesSync().length == changed.length &&
            x.path.endsWith('.png'));
    expect(replaced, isNotEmpty);
    final previous = Directory('$folder/_previous').listSync();
    expect(previous, isNotEmpty);
    expect((await run(f.store, target)).filesWritten, 0);
  });

  test('reuses an existing folder_path from metadata_cloud_games', () async {
    final f = await fixture();
    final target = Directory('${f.root.path}/catalogue');
    final edition = (await f.store.cloudIndex.query('records')).first;
    final key =
        MetadataCloudLibrary.editionKey(edition['edition_id'] as String);
    await f.store.cloudIndex.execute(
        '''CREATE TABLE IF NOT EXISTS metadata_cloud_games (
      account TEXT NOT NULL, edition_key TEXT NOT NULL, folder_path TEXT NOT NULL,
      PRIMARY KEY(account,edition_key))''');
    await f.store.cloudIndex.insert('metadata_cloud_games',
        {'account': 'other', 'edition_key': key, 'folder_path': 'psx/Chosen'});
    await run(f.store, target);
    expect(File('${target.path}/psx/Chosen/metadata.json').existsSync(),
        isTrue);
    final manifest = jsonDecode(
        File('${target.path}/psx/Chosen/metadata.json').readAsStringSync());
    expect(manifest['folder'], 'Chosen');
  });
}
