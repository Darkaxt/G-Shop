import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:retro_eshop/services/metadata/shared_metadata_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'metadata_controls_test.dart' show controlsDatabase;
import 'support/shared_metadata_lifecycle_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('revoked access blocks reachable shared data without replacing it',
      () async {
    final root = await Directory.systemTemp.createTemp('rshop-permission-');
    addTearDown(() => root.delete(recursive: true));
    final external = Directory(p.join(root.path, 'shared'));
    final privateRoot = Directory(p.join(root.path, 'private'));
    await verifySharedMetadataLifecycle(
        factory: databaseFactoryFfiNoIsolate,
        external: external,
        privateRoot: privateRoot,
        phase: 'seed');
    final sharedRoot = Directory(p.join(external.path, 'RShopMetadata'));
    final durable = File(p.join(sharedRoot.path, 'metadata.sqlite'));
    final before = await sha256.bind(durable.openRead()).first;
    var granted = true;
    Future<void> verifyAccess() async {
      if (!granted) {
        throw const FileSystemException('Shared permission revoked');
      }
    }

    final store = await SharedMetadataStore.open(sharedRoot,
        factory: databaseFactoryFfiNoIsolate,
        existingOnly: true,
        verifyAccess: verifyAccess);
    final privateDb = await databaseFactoryFfiNoIsolate
        .openDatabase(p.join(privateRoot.path, 'projection.sqlite'));
    final freshDb =
        await controlsDatabase(factory: databaseFactoryFfiNoIsolate);
    try {
      final facts = await privateDb.query('library_metadata');
      final id = facts.single['edition_id'] as String;
      final cache = MetadataArtworkCache(
          Future.value(privateDb), store.artworkRoot,
          sharedStore: store);
      expect((await cache.artworkForEdition(id)).cover, isNotNull);
      granted = false;
      expect(await durable.exists(), true,
          reason:
              'Denial must be respected even when a file remains reachable');
      await expectLater(
          store.maximumGeneration(), throwsA(isA<FileSystemException>()));
      await expectLater(
          store.restore(freshDb), throwsA(isA<FileSystemException>()));
      await expectLater(
          store.esDeTargets(), throwsA(isA<FileSystemException>()));
      expect((await cache.artworkForEdition(id)).cover, isNull);
      expect(await freshDb.query('library_metadata'), isEmpty);
      expect(await privateDb.query('library_metadata'), facts);
      await expectLater(
          SharedMetadataStore.open(sharedRoot,
              factory: databaseFactoryFfiNoIsolate,
              existingOnly: true,
              verifyAccess: verifyAccess),
          throwsA(isA<FileSystemException>()));
      granted = true;
      expect(await store.maximumGeneration(), greaterThan(0));
      expect((await cache.artworkForEdition(id)).cover, isNotNull);
    } finally {
      await store.close();
      await freshDb.close();
      await privateDb.close();
    }
    expect(await sha256.bind(durable.openRead()).first, before);
  }, timeout: Timeout.none);
}
