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

class _QueryTraceDatabase implements Database {
  final Database inner;
  final plans = <List<String>>[];
  final statements = <String>[];
  _QueryTraceDatabase(this.inner);
  @override
  Future<T> transaction<T>(Future<T> Function(Transaction) action,
          {bool? exclusive}) =>
      inner.transaction(
          (txn) => action(_QueryTraceTransaction(txn, statements, plans)),
          exclusive: exclusive);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QueryTraceTransaction implements Transaction {
  final Transaction inner;
  final List<String> statements;
  final List<List<String>> plans;
  _QueryTraceTransaction(this.inner, this.statements, this.plans);
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) async {
    statements.add(sql);
    plans.add((await inner.rawQuery('EXPLAIN QUERY PLAN $sql', arguments))
        .map((row) => row['detail'] as String)
        .toList());
    return inner.rawQuery(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> query(String table,
          {bool? distinct,
          List<String>? columns,
          String? where,
          List<Object?>? whereArgs,
          String? groupBy,
          String? having,
          String? orderBy,
          int? limit,
          int? offset}) =>
      inner.query(table,
          distinct: distinct,
          columns: columns,
          where: where,
          whereArgs: whereArgs,
          groupBy: groupBy,
          having: having,
          orderBy: orderBy,
          limit: limit,
          offset: offset);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  test('published root page does not rebuild the observed subtree', () async {
    api.nodes['console'] = folder('console', 'root-id');
    api.pages['root-id:'] = DriveFilePage(files: [api.nodes['console']!]);
    api.pages['console:'] = DriveFilePage(files: [rom('game', 'console')]);
    await refresh();
    final trace = _QueryTraceDatabase(db);
    final page = await DriveCatalogue(Future.value(trace)).entries(
        sourceId: 'source',
        accountId: 'account',
        rootFolderId: 'root-id',
        folderId: 'root-id',
        generation: 1,
        limit: 1,
        offset: 1);
    expect(page.map((entry) => entry.file.id), ['game']);
    expect(trace.statements.single, isNot(contains('WITH RECURSIVE')));
    expect(trace.plans.single, contains(contains('scope=? AND generation=?')));
  });

  test('subfolder traversal uses the parent index for each descendant',
      () async {
    api.nodes['console'] = folder('console', 'root-id');
    api.nodes['nested'] = folder('nested', 'console');
    api.pages['root-id:'] = DriveFilePage(
        files: [api.nodes['console']!, rom('outside-console', 'root-id')]);
    api.pages['console:'] = DriveFilePage(files: [api.nodes['nested']!]);
    api.pages['nested:'] = DriveFilePage(files: [rom('game', 'nested')]);
    await refresh();
    final trace = _QueryTraceDatabase(db);
    final page = await DriveCatalogue(Future.value(trace)).entries(
        sourceId: 'source',
        accountId: 'account',
        rootFolderId: 'root-id',
        folderId: 'console',
        generation: 1);
    expect(page.map((entry) => entry.file.id), ['game', 'nested']);
    expect(
        trace.plans.single,
        contains(contains(
            'drive_catalogue_parent (scope=? AND generation=? AND parent_id=?)')));
    // Both the anchor and result row must be exact file lookups. A parent-index
    // recursive step alone does not protect the outer join from a scope scan.
    expect(
        trace.plans.single.where((step) => step.startsWith('SEARCH e ') &&
            step.contains('scope=? AND generation=? AND file_id=?')),
        hasLength(2), reason: trace.plans.single.join('\n'));
    expect(trace.plans.single,
        contains(anyOf(contains('CO-ROUTINE page'), contains('MATERIALIZE page'))),
        reason: 'Select the bounded page before reading record_json payloads');
    final nextPage = await DriveCatalogue(Future.value(trace)).entries(
        sourceId: 'source', accountId: 'account', rootFolderId: 'root-id',
        folderId: 'console', generation: 1, limit: 1, offset: 1);
    expect(nextPage.map((entry) => entry.file.id), ['nested']);
  });

  test('root indexed page still requires its supported root record', () async {
    api.pages['root-id:'] = DriveFilePage(files: [rom('game', 'root-id')]);
    await refresh();
    expect((await entries()).single.file.id, 'game');
    await db.update('drive_catalogue_entries', {'is_folder': 0},
        where: 'scope=? AND generation=? AND file_id=?',
        whereArgs: [
          DriveCatalogue.scopeKey('source', 'account', 'root-id'),
          1,
          'root-id'
        ]);
    expect(await entries(), isEmpty);
  });

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
