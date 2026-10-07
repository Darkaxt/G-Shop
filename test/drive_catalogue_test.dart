import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';
import 'package:retro_eshop/services/drive/drive_catalogue.dart';

DriveFile folder(String id, String parent) => DriveFile(
    id: id, name: id, mimeType: DriveFile.folderMime, parents: [parent]);
DriveFile rom(String id, String parent, {String name = 'Same.chd'}) =>
    DriveFile(
        id: id,
        name: name,
        mimeType: 'application/octet-stream',
        parents: [parent],
        sizeBytes: 42,
        version: '1',
        canDownload: true);

class _Api implements DriveCatalogueApi {
  final nodes = <String, DriveFile>{'root-id': folder('root-id', 'my-drive')};
  final pages = <String, DriveFilePage>{};
  final listed = <String>[];
  final folderBatches = <List<String>>[];
  String? fail;
  void Function(String)? beforeList;
  void Function()? beforeBatch;
  bool failBatch = false;
  List<DriveFile> Function(List<DriveFile>)? batchResult;
  @override
  Future<DriveFile> getFile(String id, {CancelToken? cancelToken}) async =>
      nodes[id] ?? (throw const DriveApiException(DriveApiIssue.notFound));
  @override
  Future<List<DriveFile>> getFolderBatch(List<String> ids,
      {CancelToken? cancelToken}) async {
    folderBatches.add(List.of(ids));
    beforeBatch?.call();
    if (failBatch) throw const DriveApiException(DriveApiIssue.quota);
    final result = [
      for (final id in ids) await getFile(id, cancelToken: cancelToken)
    ];
    return batchResult?.call(result) ?? result;
  }

  @override
  Future<DriveFilePage> listChildren(String parentId,
      {String? pageToken,
      bool foldersOnly = false,
      CancelToken? cancelToken}) async {
    final key = '$parentId:${pageToken ?? ''}';
    beforeList?.call(key);
    listed.add(key);
    if (key == fail) throw const DriveApiException(DriveApiIssue.unavailable);
    return pages[key] ?? DriveFilePage(files: []);
  }
}

void main() {
  late Database db;
  late DriveCatalogue store;
  late _Api api;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DriveCatalogueSchema.install(db);
    store = DriveCatalogue(Future.value(db));
    api = _Api();
  });
  tearDown(() => db.close());
  Future<void> refresh({bool restart = false, CancelToken? cancel}) =>
      store.refresh(
          sourceId: 'source',
          accountId: 'account',
          rootFolderId: 'root-id',
          api: api,
          restart: restart,
          cancelToken: cancel);
  Future<List<DriveCatalogueEntry>> entries({String folderId = 'root-id'}) =>
      store.entries(
          sourceId: 'source',
          accountId: 'account',
          rootFolderId: 'root-id',
          folderId: folderId);

  test('publication rechecks every folder in bounded metadata batches',
      () async {
    final children = [
      for (var i = 0; i < 204; i++)
        folder('folder-${i.toString().padLeft(3, '0')}', 'root-id')
    ];
    for (final child in children) {
      api.nodes[child.id] = child;
    }
    api.pages['root-id:'] =
        DriveFilePage(files: children.sublist(0, 100), nextPageToken: 'p2');
    api.pages['root-id:p2'] =
        DriveFilePage(files: children.sublist(100, 200), nextPageToken: 'p3');
    api.pages['root-id:p3'] = DriveFilePage(files: children.sublist(200));
    await refresh();
    expect(api.folderBatches.map((batch) => batch.length), [100, 100, 5]);
    expect(api.folderBatches.expand((batch) => batch).toSet(),
        api.nodes.keys.toSet());
    expect(api.folderBatches.expand((batch) => batch).length, 205);
    expect((await db.query('drive_catalogue_state')).single['pending'], isNull);
    expect((await db.query('drive_catalogue_state')).single['active'], 1);
  });

  test('failed final batch preserves snapshot and resumes the same generation',
      () async {
    api.pages['root-id:'] = DriveFilePage(files: [rom('old', 'root-id')]);
    await refresh();
    api.pages['root-id:'] = DriveFilePage(files: [rom('new', 'root-id')]);
    api.failBatch = true;
    await expectLater(refresh(), throwsA(isA<DriveApiException>()));
    expect((await entries()).single.file.id, 'old');
    final before = (await db.query('drive_catalogue_state')).single;
    expect(before['active'], 1);
    expect(before['pending'], 2);
    api.failBatch = false;
    api.listed.clear();
    await refresh();
    final after = (await db.query('drive_catalogue_state')).single;
    expect(api.listed, isEmpty);
    expect(after['active'], 2);
    expect(after['pending'], isNull);
    expect(after['next_generation'], before['next_generation']);
    expect((await entries()).single.file.id, 'new');
  });

  test('cancellation during final batch preserves checkpoint and old snapshot',
      () async {
    api.pages['root-id:'] = DriveFilePage(files: [rom('old', 'root-id')]);
    await refresh();
    api.pages['root-id:'] = DriveFilePage(files: [rom('new', 'root-id')]);
    final cancel = CancelToken();
    api.beforeBatch = () => cancel.cancel();
    await expectLater(
        refresh(cancel: cancel), throwsA(isA<DriveCatalogueException>()));
    expect((await entries()).single.file.id, 'old');
    expect((await db.query('drive_catalogue_state')).single['pending'], 2);
  });

  test('short batch cannot publish, changed folder rejects pending generation',
      () async {
    api.pages['root-id:'] = DriveFilePage(files: [rom('old', 'root-id')]);
    await refresh();
    api.pages['root-id:'] = DriveFilePage(files: [rom('new', 'root-id')]);
    api.batchResult = (_) => [];
    await expectLater(refresh(), throwsA(isA<DriveApiException>()));
    expect((await entries()).single.file.id, 'old');
    api.batchResult = (_) => [folder('root-id', 'outside')];
    await expectLater(refresh(), throwsA(isA<DriveCatalogueException>()));
    expect((await entries()).single.file.id, 'old');
    expect((await db.query('drive_catalogue_state')).single['pending'], isNull);
  });

  test('pages, nested folders and duplicate names preserve exact IDs',
      () async {
    api.nodes['nested'] = folder('nested', 'root-id');
    api.pages['root-id:'] = DriveFilePage(
        files: [api.nodes['nested']!, rom('a', 'root-id')],
        nextPageToken: 'p2');
    api.pages['root-id:p2'] = DriveFilePage(files: [rom('b', 'root-id')]);
    api.pages['nested:'] = DriveFilePage(files: [rom('c', 'nested')]);
    await refresh();
    expect(
        (await entries())
            .where((e) => e.file.isSupportedBinary)
            .map((e) => e.file.id),
        unorderedEquals(['a', 'b', 'c']));
    expect((await entries(folderId: 'nested')).map((e) => e.file.id), ['c']);
    expect(api.listed, ['root-id:', 'root-id:p2', 'nested:']);
    expect(
        await store.entries(
            sourceId: 'source',
            accountId: 'other',
            rootFolderId: 'root-id',
            folderId: 'root-id'),
        isEmpty);
  });

  test('failed refresh preserves old snapshot; new instance resumes next page',
      () async {
    api.pages['root-id:'] = DriveFilePage(files: [rom('old', 'root-id')]);
    await refresh();
    api.pages['root-id:'] =
        DriveFilePage(files: [rom('new', 'root-id')], nextPageToken: 'p2');
    api.fail = 'root-id:p2';
    await expectLater(refresh(), throwsA(isA<DriveApiException>()));
    expect((await entries()).single.file.id, 'old');
    store = DriveCatalogue(Future.value(db));
    api.listed.clear();
    api.fail = null;
    api.pages['root-id:p2'] = DriveFilePage(files: [rom('last', 'root-id')]);
    await refresh();
    expect(api.listed, ['root-id:p2']);
    expect((await entries()).map((e) => e.file.id),
        unorderedEquals(['new', 'last']));
  });

  test('successful rename/move/deletion replaces snapshot, not account or IDs',
      () async {
    api.pages['root-id:'] = DriveFilePage(
        files: [rom('keep', 'root-id'), rom('delete', 'root-id')]);
    await refresh();
    api.nodes['nested'] = folder('nested', 'root-id');
    api.pages['root-id:'] = DriveFilePage(files: [api.nodes['nested']!]);
    api.pages['nested:'] =
        DriveFilePage(files: [rom('keep', 'nested', name: 'Renamed.chd')]);
    await refresh();
    final binaries =
        (await entries()).where((e) => e.file.isSupportedBinary).toList();
    expect(binaries.single.file.id, 'keep');
    expect(binaries.single.displayPath, 'nested/Renamed.chd');
  });

  test('foreign parent and folder moved outside root fail without publication',
      () async {
    api.pages['root-id:'] = DriveFilePage(files: [rom('old', 'root-id')]);
    await refresh();
    api.pages['root-id:'] = DriveFilePage(files: [rom('foreign', 'outside')]);
    await expectLater(refresh(), throwsA(isA<DriveCatalogueException>()));
    expect((await entries()).single.file.id, 'old');
    api.nodes['nested'] = folder('nested', 'root-id');
    api.pages['root-id:'] = DriveFilePage(files: [api.nodes['nested']!]);
    api.beforeList = (key) {
      if (key == 'nested:') api.nodes['nested'] = folder('nested', 'outside');
    };
    await expectLater(
        refresh(restart: true), throwsA(isA<DriveCatalogueException>()));
    expect((await entries()).single.file.id, 'old');
  });

  test('unsupported entries remain visible but never traversed', () async {
    final shortcut = DriveFile(
        id: 'shortcut',
        name: 'Outside',
        parents: ['root-id'],
        mimeType: 'application/vnd.google-apps.shortcut');
    api.pages['root-id:'] = DriveFilePage(files: [shortcut]);
    await refresh();
    expect((await entries()).single.file.unsupportedReason, 'shortcut');
    expect(api.listed, ['root-id:']);
  });

  test('cancel before publish retains checkpoint without empty publication',
      () async {
    api.pages['root-id:'] = DriveFilePage(files: [rom('old', 'root-id')]);
    await refresh();
    final cancel = CancelToken();
    api.pages['root-id:'] = DriveFilePage(files: [rom('new', 'root-id')]);
    api.beforeList = (_) => cancel.cancel();
    await expectLater(
        refresh(cancel: cancel), throwsA(isA<DriveCatalogueException>()));
    expect((await entries()).single.file.id, 'old');
  });

  test('repeated page token stops deterministically instead of looping',
      () async {
    api.pages['root-id:'] = DriveFilePage(files: [], nextPageToken: 'p');
    api.pages['root-id:p'] = DriveFilePage(files: [], nextPageToken: 'p');
    await expectLater(refresh(), throwsA(isA<DriveCatalogueException>()));
    expect(api.listed, hasLength(2));
    expect(await entries(), isEmpty);
  });

  test(
      'structural failure discards only pending checkpoint; next normal refresh recovers',
      () async {
    api.pages['root-id:'] = DriveFilePage(files: [rom('old', 'root-id')]);
    await refresh();
    api.pages['root-id:'] = DriveFilePage(files: [rom('foreign', 'outside')]);
    await expectLater(refresh(), throwsA(isA<DriveCatalogueException>()));
    api.pages['root-id:'] = DriveFilePage(files: [rom('new', 'root-id')]);
    await refresh();
    expect((await entries()).single.file.id, 'new');
  });

  test(
      'paged readers reject replaced generation rather than a partial empty page',
      () async {
    api.pages['root-id:'] = DriveFilePage(files: [rom('old', 'root-id')]);
    await refresh();
    final generation = await store.activeGeneration(
        sourceId: 'source', accountId: 'account', rootFolderId: 'root-id');
    api.pages['root-id:'] = DriveFilePage(files: [rom('new', 'root-id')]);
    await refresh();
    await expectLater(
        store.entries(
            sourceId: 'source',
            accountId: 'account',
            rootFolderId: 'root-id',
            folderId: 'root-id',
            generation: generation),
        throwsA(isA<DriveCatalogueException>()));
  });

  test('deleted child invalidates checkpoint; next ordinary refresh removes it',
      () async {
    api.pages['root-id:'] = DriveFilePage(files: [rom('old', 'root-id')]);
    await refresh();
    api.nodes['nested'] = folder('nested', 'root-id');
    api.pages['root-id:'] = DriveFilePage(files: [api.nodes['nested']!]);
    api.fail = 'nested:';
    await expectLater(refresh(), throwsA(isA<DriveApiException>()));
    api.nodes.remove('nested');
    api.pages['root-id:'] = DriveFilePage(files: [rom('new', 'root-id')]);
    api.fail = null;
    await expectLater(refresh(), throwsA(isA<DriveApiException>()));
    expect((await entries()).single.file.id, 'old');
    await refresh();
    expect((await entries()).single.file.id, 'new');
  });
}
