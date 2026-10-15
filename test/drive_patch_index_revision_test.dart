import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/config/drive_source_config.dart';
import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';
import 'package:retro_eshop/services/drive/drive_catalogue.dart';
import 'package:retro_eshop/services/drive/drive_media.dart';
import 'package:retro_eshop/services/drive/drive_runtime.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Driver implements DriveAuthorizationDriver {
  @override
  Future<String?> authenticate({required bool interactive}) async => 'account';
  @override
  Future<String?> authorize(String id, List<String> scopes,
          {required bool interactive}) async =>
      'synthetic';
  @override
  Future<void> clearRejectedToken(String id, String token) async {}
  @override
  Future<void> signOut({required bool revoke}) async {}
}

class _Api extends DriveApi {
  final Uint8List bytes;
  String version = '1', name = 'index.json', parent = 'folder';
  bool movedFolder = false, changedBytes = false;
  int listings = 0;
  _Api(DriveAuthorization authorization, this.bytes)
      : super(authorization: authorization, accountId: 'account');
  DriveFile get file => DriveFile(
      id: 'index',
      name: name,
      mimeType: 'application/json',
      parents: [parent],
      sizeBytes: bytes.length,
      version: version,
      canDownload: true,
      checksums: {
        'md5': changedBytes ? '0' * 32 : md5.convert(bytes).toString()
      });
  @override
  Future<DriveFile> getFile(String id, {CancelToken? cancelToken}) async =>
      id == 'index'
          ? file
          : DriveFile(
              id: id,
              name: id,
              mimeType: DriveFile.folderMime,
              parents:
                  id == 'root-id' ? [] : [movedFolder ? 'outside' : 'root-id']);
  @override
  Future<List<DriveFile>> getFolderBatch(List<String> ids,
          {CancelToken? cancelToken}) async =>
      [for (final id in ids) await getFile(id)];
  @override
  Future<DriveFilePage> listChildren(String parentId,
      {String? pageToken,
      bool foldersOnly = false,
      CancelToken? cancelToken}) async {
    listings++;
    return DriveFilePage(
        files: parentId == 'root-id' ? [await getFile('folder')] : [file]);
  }
}

class _Media extends DriveMediaApi {
  final Uint8List bytes;
  int reads = 0;
  _Media(DriveAuthorization authorization, this.bytes)
      : super(authorization: authorization, accountId: 'account');
  @override
  Future<DriveMediaResponse> open(RemoteArtifact artifact,
      {required int offset,
      int? endInclusive,
      required CancelToken cancelToken}) async {
    reads++;
    return DriveMediaResponse(
        bytes: Stream.value(bytes),
        offset: 0,
        length: bytes.length,
        total: bytes.length);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  const config = ProviderConfig(
      type: ProviderType.drive,
      priority: 1,
      sourceId: 'source',
      path: 'folder',
      drive: DriveSourceConfig(
          accountId: 'account',
          rootFolderId: 'root-id',
          serverClientId: 'client'));
  late Database db;
  late DriveCatalogue catalogue;
  late DriveRuntime runtime;
  late _Api api;
  late _Media media;
  late RemoteArtifact original;
  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    await DriveCatalogueSchema.install(db);
    catalogue = DriveCatalogue(Future.value(db));
    final auth = DriveAuthorization(_Driver());
    final bytes =
        Uint8List.fromList(utf8.encode('{"schema_version":2,"games":[]}'));
    api = _Api(auth, bytes);
    media = _Media(auth, bytes);
    await catalogue.refresh(
        sourceId: 'source',
        accountId: 'account',
        rootFolderId: 'root-id',
        api: api);
    original = api.file.artifact(
        sourceId: 'source',
        accountId: 'account',
        displayPath: 'folder/index.json');
    runtime = DriveRuntime(
        catalogue: catalogue,
        createAuthorization: (_) => auth,
        createApi: (_, __) => api,
        createMediaApi: (_, __) => media);
    api.listings = 0;
  });
  tearDown(() => db.close());
  Future<DriveFile> cached() => catalogue.requireBinary(
      sourceId: 'source',
      accountId: 'account',
      rootFolderId: 'root-id',
      fileId: 'index',
      generation: 1);

  test('patch index reconciles version-only drift without a source rescan',
      () async {
    api.version = '2';
    final result = await runtime.readPatchIndex(
        config: config, artifact: original, cancellation: CancelToken());
    expect(result['schema_version'], 2);
    expect((await cached()).version, '2');
    expect(media.reads, 1);
    expect(api.listings, 0);
  });

  for (final change in ['bytes', 'parent', 'ancestor', 'name', 'rollback']) {
    test('patch index rejects $change without publication or media', () async {
      api.version = change == 'rollback' ? '0' : '2';
      api.changedBytes = change == 'bytes';
      api.parent = change == 'parent' ? 'outside' : 'folder';
      api.movedFolder = change == 'ancestor';
      api.name = change == 'name' ? 'other.json' : 'index.json';
      await expectLater(
          runtime.readPatchIndex(
              config: config, artifact: original, cancellation: CancelToken()),
          throwsA(isA<DriveTransferException>()));
      expect((await cached()).version, '1');
      expect(media.reads, 0);
      expect(api.listings, 0);
    });
  }
}
