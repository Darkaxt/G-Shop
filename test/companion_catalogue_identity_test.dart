import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('catalogue replacement and rename preserve exact companion bindings',
      () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games(id INTEGER PRIMARY KEY,
      systemSlug TEXT, displayName TEXT, filename TEXT, artifact_key TEXT,
      remote_artifact TEXT, is_folder INTEGER DEFAULT 0)''');
    await LibraryQuery.install(db);
    final query = LibraryQuery(Future.value(db));

    RemoteArtifact artifact(String file, String name, String version) =>
        RemoteArtifact(
            id: RemoteArtifactId(
                providerId: 'drive',
                sourceId: 'source',
                accountId: 'account',
                providerFileId: file),
            displayName: name,
            displayPath: 'sg-1000/$name',
            sizeBytes: 42,
            version: version,
            providerChecksums: const {'md5': 'same-bytes'});

    Future<String> cache(int row, RemoteArtifact remote) async {
      await db.insert('games', {
        'id': row,
        'systemSlug': 'sg-1000',
        'displayName': remote.displayName,
        'filename': remote.displayName,
        'artifact_key': remote.id.key,
        'remote_artifact': jsonEncode(remote.toJson()),
      });
      return (await db.transaction((txn) =>
              LibraryStore.catalogueEditions(txn, cacheRowId: row).toList()))
          .single;
    }

    final first = artifact('one', 'Same name.zip', '1');
    final second = artifact('two', 'Same name.zip', '1');
    final firstEdition = await cache(1, first);
    final secondEdition = await cache(2, second);
    expect(firstEdition, isNot(secondEdition));
    await storage.setCompanion(firstEdition, 'com.example.reader/.Main');
    await storage.setCompanion(secondEdition, 'com.example.notes/.Main');

    // Real catalogue identities and the UI's metadata lookup, not filename keys.
    await db.delete('games');
    final renamed = artifact('one', 'Renamed edition.zip', '2');
    expect(await cache(101, renamed), firstEdition);
    expect(await cache(102, second), secondEdition);
    final restored = StorageService();
    await restored.init();
    final firstInfo =
        await query.cachedMetadata('artifact:${renamed.id.key}', 'sg-1000');
    final secondInfo =
        await query.cachedMetadata('artifact:${second.id.key}', 'sg-1000');
    expect(firstInfo?.editionId, firstEdition);
    expect(secondInfo?.editionId, secondEdition);
    expect(restored.getCompanion(firstInfo!.editionId!),
        'com.example.reader/.Main');
    expect(restored.getCompanion(secondInfo!.editionId!),
        'com.example.notes/.Main');
  });
}
