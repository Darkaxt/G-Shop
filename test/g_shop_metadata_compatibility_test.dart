import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/services/metadata/metadata_cloud_library.dart';
import 'package:g_shop/services/metadata/shared_metadata_store.dart';
import 'metadata_cloud_library_test.dart' show MemoryMetadataDrive;
import 'metadata_controls_test.dart' show controlsDatabase;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  for (final name in ['R-Shop Metadata', 'G-Shop Metadata']) {
    test('metadata rebrand reconnects $name without replacing it', () async {
      final root = await Directory.systemTemp.createTemp('gshop-root-');
      final store = await SharedMetadataStore.open(root,
          factory: databaseFactoryFfiNoIsolate);
      final db = await controlsDatabase();
      final remote = MemoryMetadataDrive();
      await remote.folder('existing-root', null, name);
      final cloud = MetadataCloudLibrary(
          store: store, remote: remote, accountId: 'account',
          rootId: 'existing-root');
      addTearDown(() async {
        await cloud.close();
        await store.close();
        await db.close();
      });
      await cloud.open();
      await cloud.sync(Future.value(db));
      expect(remote.files['existing-root']!.name, name);
      expect(remote.files.values.where((file) => file.parent == null),
          hasLength(1));
    });
  }
}
