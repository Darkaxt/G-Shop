import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/models/config/drive_source_config.dart';
import 'package:g_shop/models/config/provider_config.dart';
import 'package:g_shop/services/drive/drive_api.dart';
import 'package:g_shop/services/drive/drive_catalogue.dart';
import 'package:g_shop/services/drive/drive_download_boundary.dart';
import 'package:g_shop/services/drive/drive_media.dart';

DriveFile folder(String id, String parent) => DriveFile(
    id: id, name: id, mimeType: DriveFile.folderMime, parents: [parent]);
DriveFile binary({String parent = 'nested', String version = '1'}) => DriveFile(
    id: 'file',
    name: 'fixture.chd',
    mimeType: 'application/octet-stream',
    parents: [parent],
    sizeBytes: 5,
    version: version,
    canDownload: true,
    checksums: {'md5': '0123456789abcdef0123456789abcdef'});

class _Api implements DriveCatalogueApi {
  final nodes = <String, DriveFile>{
    'root-id': folder('root-id', 'my-drive'),
    'mapped': folder('mapped', 'root-id'),
    'nested': folder('nested', 'mapped'),
    'other': folder('other', 'root-id'),
    'file': binary(),
  };
  final reads = <String>[];
  @override
  Future<List<DriveFile>> getFolderBatch(List<String> ids,
          {CancelToken? cancelToken}) async =>
      [for (final id in ids) await getFile(id, cancelToken: cancelToken)];
  @override
  Future<DriveFile> getFile(String id, {CancelToken? cancelToken}) async {
    reads.add(id);
    return nodes[id]!;
  }

  @override
  Future<DriveFilePage> listChildren(String parentId,
          {String? pageToken,
          bool foldersOnly = false,
          CancelToken? cancelToken}) async =>
      DriveFilePage(
          files:
              nodes.values.where((f) => f.parents.contains(parentId)).toList());
}

void main() {
  late Database db;
  late DriveCatalogue catalogue;
  late _Api api;
  const config = ProviderConfig(
      type: ProviderType.drive,
      priority: 0,
      sourceId: 'source',
      path: 'mapped',
      drive: DriveSourceConfig(
          accountId: 'account',
          rootFolderId: 'root-id',
          serverClientId: 'public-client'));
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DriveCatalogueSchema.install(db);
    catalogue = DriveCatalogue(Future.value(db));
    api = _Api();
    await catalogue.refresh(
        sourceId: 'source',
        accountId: 'account',
        rootFolderId: 'root-id',
        api: api);
    api.reads.clear();
  });
  tearDown(() => db.close());
  DriveDownloadBoundary boundary({ProviderConfig selected = config}) =>
      DriveDownloadBoundary(
          config: selected,
          artifact: binary().artifact(
              sourceId: 'source',
              accountId: 'account',
              displayPath: 'mapped/nested/fixture.chd'),
          catalogue: catalogue,
          api: api);

  test('only exact file and observed ancestors through selected root are read',
      () async {
    final lineage = await boundary().revalidate(cancellation: CancelToken());
    expect(lineage.map((folder) => folder.id), ['nested', 'mapped', 'root-id']);
    expect(() => lineage.clear(), throwsUnsupportedError);
    expect(api.reads, unorderedEquals(['file', 'nested', 'mapped', 'root-id']));
    expect(api.reads, isNot(contains('my-drive')));
  });
  test('file move or version change cannot escape the recorded boundary',
      () async {
    for (final node in [binary(parent: 'outside'), binary(version: '2')]) {
      api.nodes['file'] = node;
      await expectLater(boundary().revalidate(cancellation: CancelToken()),
          throwsA(isA<DriveTransferException>()));
      expect(api.reads, isNot(contains('outside')));
    }
  });
  test('moved ancestor fails without following it outside the selected subtree',
      () async {
    api.nodes['mapped'] = folder('mapped', 'outside');
    await expectLater(boundary().revalidate(cancellation: CancelToken()),
        throwsA(isA<DriveTransferException>()));
    expect(api.reads, isNot(contains('outside')));
  });
  test('foreign mapping or source is rejected before any live file request',
      () async {
    for (final changed in [
      config.copyWith(path: 'other'),
      config.copyWith(sourceId: 'foreign')
    ]) {
      await expectLater(
          boundary(selected: changed).revalidate(cancellation: CancelToken()),
          throwsA(isA<DriveTransferException>()));
      expect(api.reads, isEmpty);
    }
  });
  test('cancelled validation makes no network requests', () async {
    await expectLater(
        boundary().revalidate(cancellation: CancelToken()..cancel()),
        throwsA(isA<DriveTransferException>()));
    expect(api.reads, isEmpty);
  });
}
