import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/services/metadata/catalogue_publisher.dart';
import 'package:g_shop/services/metadata/shared_metadata_store.dart';
import 'package:g_shop/services/metadata/metadata_cloud_library.dart';
import 'package:g_shop/services/metadata/drive_metadata_api.dart';
import 'package:g_shop/services/metadata/metadata_artwork_cache.dart';
import 'package:g_shop/services/metadata/metadata_credentials.dart';
import 'package:g_shop/providers/metadata_providers.dart';
import 'package:g_shop/services/drive/drive_authorization.dart';
import 'drive_authorization_test.dart' show FakeDriveAuthorizationDriver;
import 'metadata_controls_test.dart'
    show controlsDatabase, ControlsArtworkProvider, MemorySecrets;

/// A Drive view of a directory written by the Windows publisher. Ids are
/// relative paths; digests are computed from the bytes like Drive's own
/// sha256Checksum, so nothing here depends on who wrote the files.
class DirectoryCatalogueDrive implements MetadataCloudRemote {
  final Directory root;
  int downloads = 0, listings = 0;
  bool online = true;
  DirectoryCatalogueDrive(this.root);
  void _check() {
    if (!online) throw const FileSystemException('Offline fixture');
  }

  MetadataCloudFile _describe(FileSystemEntity entity) {
    final id = p.relative(entity.path, from: root.parent.path);
    final parent = p.dirname(id);
    final name = p.basename(entity.path);
    if (entity is Directory) {
      return MetadataCloudFile(
          id: id,
          name: name,
          kind: 'folder',
          parent: id == p.basename(root.path) ? null : parent);
    }
    final bytes = (entity as File).readAsBytesSync();
    final digest = sha256.convert(bytes).toString();
    return MetadataCloudFile(
        id: id,
        name: name,
        parent: parent,
        kind: name.endsWith('.png')
            ? 'artwork'
            : name.endsWith('.mp4')
                ? 'video'
                : 'records',
        digest: digest,
        checksum: digest,
        bytes: bytes.length);
  }

  @override
  Future<MetadataCloudFile?> findRoot() async {
    _check();
    return root.existsSync() ? _describe(root) : null;
  }

  @override
  Future<MetadataCloudFile?> get(String id) async {
    _check();
    final path = p.join(root.parent.path, id);
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) return null;
    return _describe(
        type == FileSystemEntityType.directory ? Directory(path) : File(path));
  }

  @override
  Future<List<MetadataCloudFile>> children(String parent) async {
    _check();
    listings++;
    return Directory(p.join(root.parent.path, parent))
        .listSync()
        .where((e) => !e.path.endsWith('.tmp'))
        .map(_describe)
        .toList();
  }

  @override
  Future<void> download(MetadataCloudFile remote, File target) async {
    _check();
    downloads++;
    await File(p.join(root.parent.path, remote.id)).copy(target.path);
  }
}

class MetadataTransport implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) response;
  final requests = <RequestOptions>[];
  MetadataTransport(this.response);
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancel) async {
    requests.add(options);
    return response(options);
  }

  @override
  void close({bool force = false}) {}
}

/// A Windows-side store with collected media, published into a catalogue
/// directory, and an empty client store that only reads that catalogue.
Future<
    ({
      Directory catalogue,
      SharedMetadataStore source,
      SharedMetadataStore client,
      Database db,
      ControlsArtworkProvider provider
    })> publishedCatalogue({String rootName = 'R-Shop Metadata'}) async {
  final root = await Directory.systemTemp.createTemp('gshop-reader-');
  final db = await controlsDatabase(path: '${root.path}/projection.sqlite');
  final source = await SharedMetadataStore.open(
      Directory('${root.path}/windows'),
      factory: databaseFactoryFfiNoIsolate,
      verifyAccess: () async {});
  final provider = ControlsArtworkProvider(includeScreenshot: true);
  final controls = MetadataControlsController(
      database: Future.value(db),
      providers: {'screenscraper': provider},
      screenScraperCredentials:
          ScreenScraperCredentialStore(storage: MemorySecrets()),
      igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
      artworkCache: Future.value(MetadataArtworkCache(
          Future.value(db), source.artworkRoot,
          sharedStore: source)),
      sharedStore: Future.value(source),
      catalogueChanged: () {});
  await controls.load();
  await controls.refresh(systemSlug: 'psx');
  await controls.close();
  controls.dispose();
  final catalogue = Directory('${root.path}/drive/$rootName');
  await CataloguePublisher(store: source, catalogue: catalogue).publish();
  final client = await SharedMetadataStore.open(
      Directory('${root.path}/client'),
      factory: databaseFactoryFfiNoIsolate,
      verifyAccess: () async {});
  addTearDown(() async {
    await client.close();
    await source.close();
    await db.close();
    await root.delete(recursive: true);
  });
  return (
    catalogue: catalogue,
    source: source,
    client: client,
    db: db,
    provider: provider
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  for (final name in ['R-Shop Metadata', 'G-Shop Metadata']) {
    test('a client reads a Windows-published catalogue under $name', () async {
      final f = await publishedCatalogue(rootName: name);
      final remote = DirectoryCatalogueDrive(f.catalogue);
      final root = (await remote.findRoot())!;
      final cloud = MetadataCloudLibrary(
          store: f.client, remote: remote, accountId: 'a', rootId: root.id);
      addTearDown(cloud.close);
      await cloud.open();
      await cloud.sync(Future.value(f.db));
      expect((await f.client.cloudIndex.query('records')).length,
          (await f.source.cloudIndex.query('records')).length);
      final key = MetadataArtworkCache.key(f.provider.media);
      final box = await cloud.ensureMedia(key, userRequested: true);
      expect(box, isNotNull);
      final published = File(p.join(
          Directory('${f.catalogue.path}/psx').listSync().single.path,
          'box.png'));
      expect(await box!.readAsBytes(), await published.readAsBytes());

      // A second read does not download unchanged game records again.
      final downloads = remote.downloads;
      await cloud.sync(Future.value(f.db));
      expect(remote.downloads, downloads);
    });
  }

  test('a resource whose bytes do not match its record stays absent',
      () async {
    final f = await publishedCatalogue();
    final game = Directory('${f.catalogue.path}/psx').listSync().single.path;
    await File('$game/box.png').writeAsBytes([1, 2, 3]);
    final remote = DirectoryCatalogueDrive(f.catalogue);
    final cloud = MetadataCloudLibrary(
        store: f.client,
        remote: remote,
        accountId: 'a',
        rootId: (await remote.findRoot())!.id);
    addTearDown(cloud.close);
    await cloud.open();
    await cloud.sync(Future.value(f.db));
    expect(await f.client.cloudIndex.query('records'), isNotEmpty,
        reason: 'The game text still arrives; only the tampered body is held');
    expect(
        await cloud.ensureMedia(MetadataArtworkCache.key(f.provider.media),
            userRequested: true),
        isNull);
  });

  test('verified media can be evicted and is fetched again from the catalogue',
      () async {
    final f = await publishedCatalogue();
    final remote = DirectoryCatalogueDrive(f.catalogue);
    final cloud = MetadataCloudLibrary(
        store: f.client,
        remote: remote,
        accountId: 'a',
        rootId: (await remote.findRoot())!.id);
    addTearDown(cloud.close);
    await cloud.open();
    await cloud.sync(Future.value(f.db));
    final key = MetadataArtworkCache.key(f.provider.media);
    final first = await cloud.ensureMedia(key, userRequested: true);
    expect(first, isNotNull);
    await cloud.trim(0);
    expect(await first!.exists(), isFalse);
    final downloads = remote.downloads;
    expect(await cloud.ensureMedia(key, userRequested: true), isNotNull);
    expect(remote.downloads, downloads + 1);
  });

  test('default media budget is two GiB, separate from ROMs and text', () {
    expect(MetadataCloudLibrary.defaultBudgetBytes, 2 * 1024 * 1024 * 1024);
  });
  test('visible game folders have typed resource names, not mixed hash images',
      () {
    expect(MetadataCloudLibrary.resourceName('box-2D', 'gb'), 'box.png');
    expect(MetadataCloudLibrary.resourceName('support-texture', 'gb'),
        'cartridge.png');
    expect(MetadataCloudLibrary.resourceName('support-texture', 'ps2'),
        'disc.png');
    expect(MetadataCloudLibrary.resourceName('ss', 'gb', index: 2),
        'screenshot-02.png');
    expect(MetadataCloudLibrary.resourceName('video-normalized', 'gb'),
        'trailer.mp4');
    expect(MetadataCloudLibrary.resourceName('fanart', 'gb'), 'fanart-001.png');
    expect(MetadataCloudLibrary.gameFolderName('Tetris: Deluxe / Test'),
        'Tetris - Deluxe - Test');
  });

  test(
      'Drive reader uses read-only access and trusts files it did not create',
      () async {
    final driver = FakeDriveAuthorizationDriver();
    final transport = MetadataTransport((options) {
      if (driver.calls.where((c) => c.startsWith('clear:')).isEmpty)
        return ResponseBody.fromString('', 401);
      if (options.uri.path == '/drive/v3/files') {
        return ResponseBody.fromString(
            jsonEncode({
              'files': [
                {
                  'id': 'box',
                  'name': 'box.png',
                  'parents': ['game'],
                  'mimeType': 'image/png',
                  'trashed': false,
                  'size': '80',
                  'sha256Checksum': 'a' * 64
                },
                {
                  'id': 'note',
                  'name': 'desktop.ini',
                  'parents': ['game'],
                  'mimeType': 'text/plain',
                  'size': '3',
                  'sha256Checksum': 'b' * 64
                },
                {
                  'id': 'partial',
                  'name': 'box-back.png',
                  'parents': ['game'],
                  'mimeType': 'image/png',
                  'size': '9'
                },
              ]
            }),
            200);
      }
      return ResponseBody.fromString('{}', 404);
    });
    final api = DriveMetadataApi(
        authorization: DriveAuthorization(driver),
        accountId: 'account-a',
        adapter: transport);
    addTearDown(api.close);
    final files = await api.children('game');
    expect(files.map((f) => f.name), ['box.png'],
        reason: 'Unknown types and files without a Drive checksum are absent');
    expect(files.single.digest, 'a' * 64);
    expect(files.single.kind, 'artwork');
    expect(
        driver.calls.where((c) => c.startsWith('authorize:')).every((c) =>
            c.contains('drive.readonly') && !c.contains('drive.file')),
        isTrue);
    expect(transport.requests.every((r) => r.method == 'GET'), isTrue,
        reason: 'The catalogue reader never writes Drive');
    expect(
        transport.requests.every((r) =>
            r.uri.host == 'www.googleapis.com' && r.followRedirects == false),
        isTrue);
  });

  test('catalogue root lookup refuses two candidate roots', () async {
    final transport = MetadataTransport((options) => ResponseBody.fromString(
        jsonEncode({
          'files': [
            for (final n in ['G-Shop Metadata', 'R-Shop Metadata'])
              {
                'id': n.substring(0, 1),
                'name': n,
                'parents': ['drive-root'],
                'mimeType': 'application/vnd.google-apps.folder',
                'trashed': false
              }
          ]
        }),
        200));
    final api = DriveMetadataApi(
        authorization: DriveAuthorization(FakeDriveAuthorizationDriver()),
        accountId: 'account-a',
        adapter: transport);
    addTearDown(api.close);
    await expectLater(api.findRoot(), throwsFormatException);
    expect(transport.requests.single.queryParameters['q'],
        contains("'root' in parents"));
  });

  test('Drive rejection diagnostics retain only bounded provider reason codes',
      () async {
    final messages = <String>[];
    final originalPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message ?? '');
    addTearDown(() => debugPrint = originalPrint);
    var payload = jsonEncode({
      'error': {
        'message': 'Private name and credential must not be logged',
        'errors': [
          {'reason': 'insufficientPermissions', 'location': 'private-object-id'}
        ]
      }
    });
    final transport =
        MetadataTransport((_) => ResponseBody.fromString(payload, 403));
    final api = DriveMetadataApi(
        authorization: DriveAuthorization(FakeDriveAuthorizationDriver()),
        accountId: 'account-a',
        adapter: transport);
    addTearDown(api.close);
    await expectLater(
        api.get('private-object-id'), throwsA(isA<FileSystemException>()));
    expect(messages.single, contains('reason=insufficientPermissions'));
    expect(messages.single, isNot(contains('private')));
    messages.clear();
    payload = 'x' * 9000;
    await expectLater(
        api.get('private-object-id'), throwsA(isA<FileSystemException>()));
    expect(messages.single, contains('reason=unknown'));
    expect(transport.requests, hasLength(2),
        reason: 'Provider denials must not trigger speculative retries');
  });
}
