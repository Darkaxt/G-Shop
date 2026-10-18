import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/services/metadata/shared_metadata_store.dart';
import 'package:retro_eshop/services/metadata/metadata_cloud_library.dart';
import 'package:retro_eshop/services/metadata/drive_metadata_api.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:retro_eshop/services/metadata/preview_video_cache.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/providers/metadata_providers.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';
import 'drive_authorization_test.dart' show FakeDriveAuthorizationDriver;
import 'metadata_controls_test.dart'
    show controlsDatabase, ControlsArtworkProvider, MemorySecrets;
import 'preview_media_test.dart' show movie;

class ResourceProvider extends ControlsArtworkProvider {
  ResourceProvider() : super(includeScreenshot: true);
  @override
  Future<MetadataLookupResult> fetchArtwork(MetadataMedia media,
      {required Future<void> Function(List<int>) write,
      CancelToken? cancelToken}) async {
    if ({'video', 'video-normalized'}.contains(media.type)) {
      await write(movie(1));
      return MetadataLookupResult(
          status: MetadataLookupStatus.matched, message: 'Fixture trailer');
    }
    return super.fetchArtwork(media, write: write, cancelToken: cancelToken);
  }
}

class MemoryMetadataDrive implements MetadataCloudRemote {
  final files = <String, MetadataCloudFile>{};
  final bodies = <String, Uint8List>{};
  int next = 0, downloads = 0, reads = 0, childListings = 0;
  bool online = true, failUpload = false;
  void check() {
    if (!online) throw const FileSystemException('Offline fixture');
  }

  @override
  Future<String> reserveId() async {
    check();
    return 'id-${++next}';
  }

  @override
  Future<MetadataCloudFile?> get(String id) async {
    reads++;
    check();
    return files[id];
  }

  @override
  Future<List<MetadataCloudFile>> children(String? parent) async {
    reads++;
    childListings++;
    check();
    return files.values.where((f) => f.parent == parent).toList();
  }

  @override
  Future<void> folder(String id, String? parent, String name) async {
    check();
    files.putIfAbsent(
        id,
        () => MetadataCloudFile(
            id: id, parent: parent, name: name, kind: 'folder'));
  }

  @override
  Future<void> upload(String id, String parent, String name, String kind,
      File file, String digest, int bytes,
      {String? replacesDigest}) async {
    check();
    if (failUpload) throw const FileSystemException('Upload interrupted');
    final existing = files[id];
    if (existing != null &&
        existing.digest != digest &&
        existing.digest != replacesDigest) {
      throw const FormatException('Changed remote publication');
    }
    bodies[id] = await file.readAsBytes();
    files[id] = MetadataCloudFile(
        id: id,
        parent: parent,
        name: name,
        kind: kind,
        digest: digest,
        checksum: digest,
        bytes: bytes);
  }

  @override
  Future<void> download(MetadataCloudFile remote, File target) async {
    check();
    downloads++;
    await target.writeAsBytes(bodies[remote.id]!, flush: true);
  }

  @override
  Future<void> relocate(MetadataCloudFile file, String parent) async {
    check();
    final current = files[file.id]!;
    if (current.parent != file.parent && current.parent != parent)
      throw const FormatException('Changed parent');
    files[file.id] = MetadataCloudFile(
        id: file.id,
        name: file.name,
        kind: file.kind,
        parent: parent,
        digest: file.digest,
        checksum: file.checksum,
        bytes: file.bytes);
  }

  @override
  Future<void> trash(MetadataCloudFile file) async {
    check();
    for (final child
        in files.values.where((f) => f.parent == file.id).toList()) {
      await trash(child);
    }
    files.remove(file.id);
    bodies.remove(file.id);
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

Map<String, dynamic> mutationView(
        RequestOptions request, Map<String, dynamic> modern,
        {String etag = '"version-1"'}) =>
    !request.uri.path.contains('/v2/')
        ? modern
        : {
            ...modern,
            'title': modern['name'],
            'etag': etag,
            'fileSize': modern['size'],
            'parents': [
              for (final parent in modern['parents'] as List) {'id': parent}
            ],
            'labels': {'trashed': modern['trashed']},
            'properties': [
              for (final property in (modern['appProperties'] as Map).entries)
                {
                  'key': property.key,
                  'value': property.value,
                  'visibility': 'PRIVATE'
                }
            ],
          };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  test(
      'reintroduced artwork uses the latest owned receipt and rejects foreign changes',
      () async {
    final root = await Directory.systemTemp.createTemp('rshop-reintroduced-');
    final db = await controlsDatabase(path: '${root.path}/projection.sqlite');
    final store = await SharedMetadataStore.open(
        Directory('${root.path}/shared'),
        factory: databaseFactoryFfiNoIsolate);
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
    final remote = MemoryMetadataDrive();
    await remote.folder('root', null, 'R-Shop Metadata');
    final cloud = MetadataCloudLibrary(
        store: store, remote: remote, accountId: 'account', rootId: 'root');
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await cloud.close();
      await store.close();
      await db.close();
      // Exact task-owned scratch is reviewed by transactional cleanup.
    });
    await controls.load();
    await controls.refresh(systemSlug: 'psx');
    await cloud.open();
    await cloud.sync(Future.value(db), pull: false);
    final key = MetadataArtworkCache.key(provider.media);
    final original = (await store.cloudIndex.query('metadata_artwork_cache',
            where: 'media_key=?', whereArgs: [key]))
        .single;
    final first = File('${store.artworkRoot.path}/${original['filename']}');
    final changed = Uint8List.fromList([...await first.readAsBytes(), 0]);
    final changedName = '${sha256.convert(changed)}.png';
    await File('${store.artworkRoot.path}/$changedName').writeAsBytes(changed);
    final replacement = MetadataArtworkBlob(key, changedName, changed.length);
    final originalBlob = MetadataArtworkBlob(
        key, original['filename'] as String, original['byte_length'] as int);
    await store.preserveBlob(replacement, DateTime.now().toUtc());
    await cloud.sync(Future.value(db), pull: false);
    await store.preserveBlob(originalBlob, DateTime.now().toUtc());
    await cloud.sync(Future.value(db), pull: false);
    final box = remote.files.values.singleWhere((f) => f.name == 'box.png');
    expect(box.digest, originalBlob.filename.substring(0, 64));
    await store.preserveBlob(replacement, DateTime.now().toUtc());
    // A real external edit must still fail closed, even with an owned predecessor.
    remote.files[box.id] = MetadataCloudFile(
        id: box.id,
        parent: box.parent,
        name: box.name,
        kind: box.kind,
        digest: 'f' * 64,
        bytes: box.bytes);
    await expectLater(
        cloud.sync(Future.value(db), pull: false), throwsFormatException);
    expect(remote.files[box.id]!.digest, 'f' * 64);
  });
  test('backup-only sync does not traverse the remote collection', () async {
    final root = await Directory.systemTemp.createTemp('rshop-local-backup-');
    final store = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate);
    final db = await controlsDatabase();
    final remote = MemoryMetadataDrive();
    final cloud = MetadataCloudLibrary(
        store: store,
        remote: remote,
        accountId: 'account',
        rootId: 'metadata-root');
    addTearDown(() async {
      await cloud.close();
      await store.close();
      await db.close();
    });
    await cloud.open();
    await cloud.sync(Future.value(db), pull: false);
    expect(remote.childListings, 0,
        reason: 'Startup publication must not list every remote console/game');
    expect(remote.downloads, 0);
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
      'metadata transport renews app-file access once and rejects unowned media',
      () async {
    final driver = FakeDriveAuthorizationDriver();
    var shared = false;
    final transport = MetadataTransport((options) {
      if (driver.calls.where((c) => c.startsWith('clear:')).isEmpty)
        return ResponseBody.fromString('', 401);
      return ResponseBody.fromString(
          jsonEncode({
            'id': 'object',
            'name': '${'a' * 64}.png',
            'parents': ['artwork'],
            'mimeType': 'image/png',
            'ownedByMe': true,
            'isAppAuthorized': true,
            'trashed': false,
            'shared': shared,
            'size': '80',
            'appProperties': {
              'rshopMetadata': '1',
              'kind': 'artwork',
              'sha256': 'a' * 64
            }
          }),
          200);
    });
    final api = DriveMetadataApi(
        authorization: DriveAuthorization(driver),
        accountId: 'account-a',
        adapter: transport);
    addTearDown(api.close);
    expect((await api.get('object'))!.bytes, 80);
    expect(
        driver.calls.where((c) => c.startsWith('clear:')), ['clear:account-a']);
    expect(
        driver.calls
            .where((c) => c.startsWith('authorize:'))
            .every((c) => c.contains('drive.file:false')),
        isTrue);
    expect(
        transport.requests.every((r) =>
            r.uri.host == 'www.googleapis.com' && r.followRedirects == false),
        isTrue);
    shared = true;
    await expectLater(api.get('object'), throwsFormatException);
  });
  test(
      'typed media updates use the v2 PUT upload URI, ETag and expected digest',
      () async {
    final root = await Directory.systemTemp.createTemp('rshop-cloud-update-');
    final body = File('${root.path}/body.png');
    await body.writeAsBytes([1, 2, 3]);
    addTearDown(() => root.delete(recursive: true));
    var observed = 'a' * 64;
    final transport = MetadataTransport((request) => ResponseBody.fromString(
        request.uri.path.startsWith('/upload/')
            ? request.method == 'PUT'
                ? '{"id":"object"}'
                : '{"error":{"errors":[{"reason":"notFound"}]}}'
            : jsonEncode(mutationView(request, {
                'id': 'object',
                'name': 'box.png',
                'parents': ['game'],
                'mimeType': 'image/png',
                'ownedByMe': true,
                'isAppAuthorized': true,
                'trashed': false,
                'shared': false,
                'size': '3',
                'appProperties': {
                  'rshopMetadata': '1',
                  'kind': 'artwork',
                  'sha256': observed
                }
              })),
        request.uri.path.startsWith('/upload/') && request.method != 'PUT'
            ? 404
            : 200));
    final api = DriveMetadataApi(
        authorization: DriveAuthorization(FakeDriveAuthorizationDriver()),
        accountId: 'account-a',
        adapter: transport);
    addTearDown(api.close);
    await api.upload('object', 'game', 'box.png', 'artwork', body, 'b' * 64, 3,
        replacesDigest: 'a' * 64);
    expect(transport.requests.last.method, 'PUT');
    expect(transport.requests.last.uri.path, '/upload/drive/v2/files/object');
    expect(transport.requests.last.headers['If-Match'], '"version-1"');
    observed = 'c' * 64;
    await expectLater(
        api.upload('object', 'game', 'box.png', 'artwork', body, 'b' * 64, 3,
            replacesDigest: 'a' * 64),
        throwsFormatException);
    expect(transport.requests.where((r) => r.method == 'PUT'), hasLength(1));
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
          {'reason': 'cannotTrashFile', 'location': 'private-object-id'}
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
    expect(messages.single, contains('reason=cannotTrashFile'));
    expect(messages.single, isNot(contains('private')));
    messages.clear();
    payload = 'x' * 9000;
    await expectLater(
        api.get('private-object-id'), throwsA(isA<FileSystemException>()));
    expect(messages.single, contains('reason=unknown'));
    expect(transport.requests, hasLength(2),
        reason: 'Provider denials must not trigger speculative retries');
  });
  test('explicit media rebuild trashes only unchanged owned non-root targets',
      () async {
    var parent = 'root';
    var hasEtag = true;
    final transport = MetadataTransport((request) => ResponseBody.fromString(
        request.uri.path == '/drive/v3/files'
            ? '{"files":[]}'
            : request.method == 'PATCH'
                ? '{"id":"console","labels":{"trashed":true}}'
                : jsonEncode(mutationView(
                    request,
                    {
                      'id': 'console',
                      'name': 'ps2',
                      'parents': [parent],
                      'mimeType': 'application/vnd.google-apps.folder',
                      'ownedByMe': true,
                      'isAppAuthorized': true,
                      'trashed': false,
                      'shared': false,
                      'appProperties': {'rshopMetadata': '1', 'kind': 'folder'}
                    },
                    etag: '"observed"')),
        200,
        headers: hasEtag
            ? {
                'etag': ['"observed"']
              }
            : {}));
    final api = DriveMetadataApi(
        authorization: DriveAuthorization(FakeDriveAuthorizationDriver()),
        accountId: 'account-a',
        adapter: transport);
    addTearDown(api.close);
    const console = MetadataCloudFile(
        id: 'console', name: 'ps2', kind: 'folder', parent: 'root');
    await api.trash(console);
    expect(transport.requests.last.headers['If-Match'], '"observed"');
    expect(jsonDecode(transport.requests.last.data as String), {
      'labels': {'trashed': true}
    });
    hasEtag = false;
    await api.trash(console);
    expect(transport.requests.last.headers['If-Match'], '"observed"',
        reason:
            'Conditional writes use the v2 resource, not an assumed HTTP header');
    expect(transport.requests.last.uri.path, '/drive/v2/files/console');
    parent = 'foreign';
    await expectLater(api.trash(console), throwsFormatException);
    expect(transport.requests.where((r) => r.method == 'PATCH'), hasLength(2));
  });
  test('rebuild trashes verified descendants before populated Drive folders',
      () async {
    final objects = <String, Map<String, dynamic>>{
      for (final row in [
        ('console', 'root', true),
        ('game', 'console', true),
        ('box', 'game', false),
        ('old', 'game', false),
      ])
        row.$1: {
          'id': row.$1,
          'name': row.$1,
          'parents': [row.$2],
          'mimeType':
              row.$3 ? 'application/vnd.google-apps.folder' : 'image/png',
          'ownedByMe': true,
          'isAppAuthorized': true,
          'trashed': row.$1 == 'old',
          'shared': false,
          if (!row.$3) 'size': '3',
          'appProperties': {
            'rshopMetadata': '1',
            'kind': row.$3 ? 'folder' : 'artwork',
            if (!row.$3) 'sha256': 'a' * 64,
          }
        }
    };
    final removed = <String>[];
    final transport = MetadataTransport((request) {
      if (request.uri.path == '/drive/v3/files') {
        final parent = RegExp(r"'([^']+)' in parents")
            .firstMatch(request.queryParameters['q'] as String)!
            .group(1);
        return ResponseBody.fromString(
            jsonEncode({
              'files': [
                for (final item in objects.values)
                  if ((item['parents'] as List).single == parent &&
                      (!(request.queryParameters['q'] as String)
                              .contains('trashed = false') ||
                          item['trashed'] == false))
                    item
              ]
            }),
            200);
      }
      final id = request.uri.pathSegments.last;
      final item = objects[id]!;
      if (request.method == 'PATCH') {
        if (request.queryParameters['addParents'] != null) {
          expect(request.queryParameters['removeParents'],
              (item['parents'] as List).single);
          item['parents'] = [request.queryParameters['addParents']];
          return ResponseBody.fromString(jsonEncode({'id': id}), 200);
        }
        if (objects.values
            .any((other) => (other['parents'] as List).single == id)) {
          return ResponseBody.fromString(
              '{"error":{"errors":[{"reason":"childAccessCheckLimitExceeded"}]}}',
              403);
        }
        item['trashed'] = true;
        removed.add(id);
        return ResponseBody.fromString(
            jsonEncode({
              'id': id,
              'labels': {'trashed': true}
            }),
            200);
      }
      return ResponseBody.fromString(
          jsonEncode(mutationView(request, item)), 200);
    });
    final api = DriveMetadataApi(
        authorization: DriveAuthorization(FakeDriveAuthorizationDriver()),
        accountId: 'account-a',
        adapter: transport);
    addTearDown(api.close);
    await api.trash(const MetadataCloudFile(
        id: 'console', name: 'console', kind: 'folder', parent: 'root'));
    expect(removed, ['box', 'game', 'console']);
    expect(
        objects.values.every((f) =>
            (f['parents'] as List).single == 'root' && f['trashed'] == true),
        isTrue,
        reason: 'Trashed children must not remain attached to retired folders');
    expect(
        transport.requests
            .where((r) => r.method == 'PATCH')
            .every((r) => r.headers['If-Match'] == '"version-1"'),
        isTrue);
    removed.clear();
    objects['console']!['trashed'] = false;
    objects['box']!['trashed'] = false;
    objects['box']!['parents'] = ['console'];
    objects['box']!['ownedByMe'] = false;
    await expectLater(
        api.trash(const MetadataCloudFile(
            id: 'console', name: 'console', kind: 'folder', parent: 'root')),
        throwsFormatException);
    expect(removed, isEmpty,
        reason: 'A visible foreign child prevents cascading parent removal');
    expect(transport.requests.last.queryParameters['q'],
        isNot(contains('appProperties')));
  });
  test(
      'publication, owned eviction, lazy recovery and offline hits share one cache',
      () async {
    final root = await Directory.systemTemp.createTemp('rshop-cloud-');
    final store =
        await SharedMetadataStore.open(root, factory: databaseFactoryFfi);
    final remote = MemoryMetadataDrive();
    final cloud = MetadataCloudLibrary(
        store: store,
        remote: remote,
        accountId: 'account',
        rootId: 'root',
        budgetBytes: 100);
    addTearDown(() async {
      await cloud.close();
      await store.close();
      await root.delete(recursive: true);
    });
    await remote.folder('root', null, 'R-Shop Metadata');
    await cloud.open();
    Future<String> publish(int marker) async {
      final bytes = Uint8List(80)..[0] = marker;
      final digest = sha256.convert(bytes).toString();
      final video = marker == 2;
      final directory =
          video ? Directory('${root.path}/preview-videos') : store.artworkRoot;
      await directory.create(recursive: true);
      final file = File('${directory.path}/$digest.${video ? 'mp4' : 'png'}');
      await file.writeAsBytes(bytes);
      final path =
          'gba/${video ? 'preview-videos' : 'artwork'}/$digest.${video ? 'mp4' : 'png'}';
      await cloud.publishFile(
          path: path,
          mediaKey: 'media-$marker',
          file: file,
          kind: video ? 'video' : 'artwork');
      return path;
    }

    final first = await publish(1);
    final second = await publish(2);
    expect(await cloud.localFile(first), isNull);
    expect(await cloud.localFile(second), isNotNull);
    final fetched = await cloud.ensure(first);
    expect(fetched, isNotNull);
    expect(remote.downloads, 1);
    remote.online = false;
    expect((await cloud.ensure(first))!.path, fetched!.path);
    expect(remote.downloads, 1);
    expect(await cloud.cachedBytes(), lessThanOrEqualTo(100));
  });
  test('unverified originals and leased media cannot be evicted', () async {
    final root = await Directory.systemTemp.createTemp('rshop-cloud-lease-');
    final store =
        await SharedMetadataStore.open(root, factory: databaseFactoryFfi);
    final remote = MemoryMetadataDrive();
    await remote.folder('root', null, 'R-Shop Metadata');
    final cloud = MetadataCloudLibrary(
        store: store,
        remote: remote,
        accountId: 'account',
        rootId: 'root',
        budgetBytes: 200);
    addTearDown(() async {
      await cloud.close();
      await store.close();
      await root.delete(recursive: true);
    });
    await cloud.open();
    await store.artworkRoot.create(recursive: true);
    final bytes = Uint8List(80)..[0] = 7;
    final digest = sha256.convert(bytes).toString();
    final file = File('${store.artworkRoot.path}/$digest.png');
    await file.writeAsBytes(bytes);
    final path = 'gba/artwork/$digest.png';
    remote.failUpload = true;
    await expectLater(
        cloud.publishFile(
            path: path, mediaKey: 'm', file: file, kind: 'artwork'),
        throwsA(isA<FileSystemException>()));
    await cloud.trim(0);
    expect(await file.exists(), isTrue);
    remote.failUpload = false;
    await cloud.publishFile(
        path: path, mediaKey: 'm', file: file, kind: 'artwork');
    final owner = Object();
    cloud.hold(owner, {file.path});
    await cloud.trim(0);
    expect(await file.exists(), isTrue);
    cloud.release(owner);
    await cloud.trim(0);
    expect(await file.exists(), isFalse);
    expect(await File('${root.path}/metadata.sqlite').exists(), isTrue);
  });
  test('historical unbound artwork is preserved in Drive before cache removal',
      () async {
    final root = await Directory.systemTemp.createTemp('rshop-cloud-history-');
    final store = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate);
    final db = await controlsDatabase(path: '${root.path}/projection.sqlite');
    final remote = MemoryMetadataDrive();
    await remote.folder('root', null, 'R-Shop Metadata');
    final cloud = MetadataCloudLibrary(
        store: store, remote: remote, accountId: 'account', rootId: 'root');
    addTearDown(() async {
      await cloud.close();
      await store.close();
      await db.close();
      await root.delete(recursive: true);
    });
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==');
    final name = '${sha256.convert(bytes)}.png';
    await store.artworkRoot.create();
    final image = File('${store.artworkRoot.path}/$name');
    await image.writeAsBytes(bytes);
    await cloud.open();
    expect(await cloud.cachedBytes(), bytes.length);
    await cloud.trim(0);
    expect(await image.exists(), isTrue);
    await cloud.sync(Future.value(db));
    expect(remote.files.values.where((f) => f.kind == 'artwork'), hasLength(1));
    expect(remote.files.values.where((f) => f.kind == 'records'), hasLength(1));
    await cloud.trim(0);
    expect(await image.exists(), isFalse);
    expect(remote.bodies.values.any((body) => body.length == bytes.length),
        isTrue);
  });
  test(
      'fresh device recovers exact text without media and lazily reads both artwork aliases',
      () async {
    final root = await Directory.systemTemp.createTemp('rshop-cloud-recovery-');
    final source = await controlsDatabase(path: '${root.path}/source.sqlite');
    final destination =
        await controlsDatabase(path: '${root.path}/destination.sqlite');
    final oldStore = await SharedMetadataStore.open(
        Directory('${root.path}/old'),
        factory: databaseFactoryFfiNoIsolate);
    final newStore = await SharedMetadataStore.open(
        Directory('${root.path}/new'),
        factory: databaseFactoryFfiNoIsolate);
    final provider = ResourceProvider();
    final controls = MetadataControlsController(
        database: Future.value(source),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: MemorySecrets()),
        igdbCredentials: IgdbCredentialStore(storage: MemorySecrets()),
        artworkCache: Future.value(MetadataArtworkCache(
            Future.value(source), oldStore.artworkRoot,
            sharedStore: oldStore)),
        sharedStore: Future.value(oldStore),
        catalogueChanged: () {});
    final remote = MemoryMetadataDrive();
    await remote.folder('root', null, 'R-Shop Metadata');
    final oldCloud = MetadataCloudLibrary(
        store: oldStore, remote: remote, accountId: 'account', rootId: 'root');
    final newCloud = MetadataCloudLibrary(
        store: newStore, remote: remote, accountId: 'account', rootId: 'root');
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await oldCloud.close();
      await newCloud.close();
      await oldStore.close();
      await newStore.close();
      await source.close();
      await destination.close();
      await root.delete(recursive: true);
    });
    await controls.load();
    await controls.refresh(systemSlug: 'psx');
    final edition = provider.calls.single.editionId;
    await oldCloud.open();
    final requested = {
      MetadataArtworkCache.key(provider.media),
      MetadataArtworkCache.key(provider.screenshot)
    };
    await oldCloud.publishSelection(edition, requested);
    final reads = remote.reads;
    await oldCloud.publishSelection(edition, requested);
    expect(remote.reads, reads,
        reason: 'An already published focus remains local-only');
    await oldCloud.sync(Future.value(source));
    expect(remote.files.values.where((f) => f.kind == 'artwork'), hasLength(2),
        reason:
            'Each visible game resource has its typed name; the local body remains deduplicated');
    expect(
        remote.files.values
            .where((f) => f.kind == 'artwork')
            .map((f) => f.name)
            .toSet(),
        {'box.png', 'screenshot-01.png'});
    expect(
        remote.files.values
            .where((f) => f.kind == 'records')
            .every((f) => f.name == 'metadata.json'),
        isTrue);
    await destination.transaction(
        (txn) => LibraryStore.catalogueEditions(txn, cacheRowId: 1).toList());
    await newCloud.open();
    await newCloud.sync(Future.value(destination));
    final recovered = await LibraryStore(Future.value(destination))
        .metadata(edition, 'screenscraper');
    expect(recovered!.titles.single.text, 'Game 1');
    expect(await newStore.artworkRoot.exists(), isFalse);
    final cache = MetadataArtworkCache(
        Future.value(destination), newStore.artworkRoot,
        sharedStore: newStore);
    expect((await cache.artworkForEdition(edition)).cover, isNull);
    final before = remote.downloads;
    final cover =
        await newCloud.ensureMedia(MetadataArtworkCache.key(provider.media));
    final screenshot = await newCloud
        .ensureMedia(MetadataArtworkCache.key(provider.screenshot));
    expect(cover!.path, screenshot!.path);
    expect(remote.downloads, before + 1);
    final images = await cache.artworkForEdition(edition);
    expect(images.cover, cover.uri.toString());
    expect(images.screenshots, [cover.uri.toString()]);
    remote.online = false;
    expect(
        (await newCloud.ensureMedia(MetadataArtworkCache.key(provider.media)))!
            .path,
        cover.path);
    expect(
        (await LibraryStore(Future.value(destination))
                .metadata(edition, 'screenscraper'))!
            .titles
            .single
            .text,
        'Game 1');
    final packets = remote.bodies.values.map((body) {
      try {
        return utf8.decode(body);
      } catch (_) {
        return '';
      }
    }).join();
    expect(packets, isNot(contains('fixture-password')));
    remote.online = true;
    final oldReply = provider.reply!;
    provider.reply = (request, cancel) async {
      final reply = await oldReply(request, cancel);
      return MetadataLookupResult(
          status: reply.status,
          message: reply.message,
          record: MetadataRecord.fromJson({
            ...reply.record!.toJson(),
            'media': [
              ...reply.record!.media.map((m) => m.toJson()),
              for (final member in [1, 2])
                MetadataMedia(
                        type: 'support-texture',
                        region: 'us',
                        memberIndex: member,
                        providerReference: ScreenScraperMediaReference(
                            providerGameId: '42',
                            providerPlatformId: 57,
                            mediaType: 'support-texture',
                            region: 'us',
                            memberIndex: member))
                    .toJson(),
              MetadataMedia(
                      type: 'video-normalized',
                      providerReference: ScreenScraperMediaReference(
                          providerGameId: '42',
                          providerPlatformId: 57,
                          mediaType: 'video-normalized'))
                  .toJson()
            ]
          }));
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.retro.rshop/storage'),
            (_) async => {'ready': true});
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.retro.rshop/storage'), null));
    await controls.refresh(systemSlug: 'psx');
    await oldCloud.sync(Future.value(source), pull: false);
    expect(
        remote.files.values
            .where((f) => f.kind == 'artwork')
            .map((f) => f.name),
        containsAll(['disc-01.png', 'disc-02.png']));
    expect(
        remote.files.values.where((f) => f.kind == 'video').map((f) => f.name),
        ['trailer.mp4'],
        reason: 'Normal Drive-backed resource collection includes its trailer');
    final lookups = provider.calls.length;
    final downloads = provider.artworkCalls;
    await controls.collectResources(systemSlug: 'psx');
    expect(controls.state.error, isFalse);
    expect(controls.state.report!.kind, 'artwork');
    expect(controls.state.report!.state, 'completed');
    expect(provider.calls.length, lookups,
        reason: 'Collecting resources does not search titles again');
    expect(provider.artworkCalls, downloads,
        reason: 'Valid local resources are reused');
    final resourceJob = controls.state.report!.id;
    expect((await controls.savedJobs()).first.id, resourceJob);
    await controls.load();
    expect(controls.state.report!.id, resourceJob);
    final legacyPacket = await oldStore.cloudPackets(editionId: edition).single;
    legacyPacket['assets'] = <Object>[];
    final legacyBody = utf8.encode(jsonEncode(legacyPacket));
    final legacyDigest = sha256.convert(legacyBody).toString();
    final platformFolder = remote.files.values
        .singleWhere((f) => f.kind == 'folder' && f.name == 'psx');
    await remote.folder('legacy-records', platformFolder.id, 'records');
    remote.files['legacy-packet'] = MetadataCloudFile(
        id: 'legacy-packet',
        parent: 'legacy-records',
        name: '$legacyDigest.json',
        kind: 'records',
        digest: legacyDigest,
        checksum: legacyDigest,
        bytes: legacyBody.length);
    remote.bodies['legacy-packet'] = Uint8List.fromList(legacyBody);
    await oldCloud.sync(Future.value(source));
    final legacy = remote.files.values.singleWhere((f) => f.name == '_legacy');
    final archivedConsole = remote.files.values
        .singleWhere((f) => f.parent == legacy.id && f.name == 'psx');
    expect(remote.files['legacy-records']!.parent, archivedConsole.id);
    expect(remote.files['legacy-packet']!.parent, 'legacy-records');
    await newCloud.sync(Future.value(destination));
    expect(
        (await LibraryStore(Future.value(destination))
                .metadata(edition, 'screenscraper'))!
            .media
            .where((m) => m.type == 'support-texture')
            .length,
        2);
    final recordsBefore = await oldStore.cloudIndex.query('records');
    final userFile = File('${oldStore.artworkRoot.path}/user-note.txt');
    await userFile.writeAsString('Not a collected cache body');
    remote.online = false;
    await expectLater(
        oldCloud.discardCollectedMedia(), throwsA(isA<FileSystemException>()));
    await expectLater(oldCloud.sync(Future.value(source)), throwsStateError);
    await oldCloud.publishSelection(edition, {'discarded-resource'});
    expect(await oldCloud.cachedBytes(), greaterThan(0),
        reason:
            'Offline reset preserves resources until its explicit intent resumes');
    remote.online = true;
    await oldCloud.discardCollectedMedia();
    expect(await remote.children('root'), isEmpty);
    expect(await oldCloud.cachedBytes(), 0);
    expect(await oldStore.cloudIndex.query('metadata_artwork_cache'), isEmpty);
    expect(await oldStore.cloudIndex.query('records'), recordsBefore,
        reason: 'Media rebuild preserves every matched fact and rating');
    expect(await userFile.readAsString(), 'Not a collected cache body');
    final beforeFresh = provider.artworkCalls;
    await controls.collectResources(systemSlug: 'psx');
    expect(controls.state.error, isFalse);
    expect(controls.state.report!.state, 'completed');
    expect(provider.calls.length, lookups,
        reason: 'Fresh resources reuse game matches, not discarded media');
    expect(provider.artworkCalls, greaterThan(beforeFresh));
    await oldCloud.sync(Future.value(source), pull: false);
    expect(
        remote.files.values
            .where((f) => f.kind == 'artwork')
            .map((f) => f.name),
        containsAll(['box.png', 'disc-01.png']));
    expect(
        remote.files.values.where((f) => f.kind == 'video').map((f) => f.name),
        ['trailer.mp4']);
  });

  test('legacy trailer collection publishes and recovers without title lookup',
      () async {
    final root = await Directory.systemTemp.createTemp('rshop-legacy-trailer-');
    final db = await controlsDatabase(path: '${root.path}/projection.sqlite');
    final store = await SharedMetadataStore.open(
        Directory('${root.path}/shared'),
        factory: databaseFactoryFfiNoIsolate);
    final provider = ResourceProvider();
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
    final remote = MemoryMetadataDrive();
    await remote.folder('root', null, 'R-Shop Metadata');
    var mediaChanges = 0;
    final cloud = MetadataCloudLibrary(
        store: store,
        remote: remote,
        accountId: 'account',
        rootId: 'root',
        changed: () => mediaChanges++);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.retro.rshop/storage'),
            (_) async => {'ready': true});
    addTearDown(() async {
      await controls.close();
      controls.dispose();
      await cloud.close();
      await store.close();
      await db.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('com.retro.rshop/storage'), null);
      // Exact task-owned scratch remains for transactional cleanup.
    });
    await controls.load();
    await controls.refresh(systemSlug: 'psx');
    final edition = provider.calls.single.editionId;
    final record = (await LibraryStore(Future.value(db))
        .metadata(edition, 'screenscraper'))!;
    expect(record.media.any((m) => m.type.startsWith('video')), isFalse);
    await cloud.open();
    await controls.collectResources(systemSlug: 'psx');
    expect(controls.state.report!.counts, {'matched': 3});
    expect(provider.calls, hasLength(1));
    await cloud.sync(Future.value(db), pull: false);
    expect(mediaChanges, 1,
        reason: 'Remote publication is not a local media change per game');
    final publishedChanges = mediaChanges;
    await cloud.publishSelection(edition, {});
    expect(mediaChanges, publishedChanges,
        reason:
            'Publishing a focused game must not restart its own media read');
    expect(
        remote.files.values.where((f) => f.kind == 'video').map((f) => f.name),
        ['trailer.mp4']);
    final video = MetadataArtworkCache.displayMedia(record, includeVideo: true)
        .singleWhere((m) => m.type == 'video');
    final cache = PreviewVideoCache(store);
    final original = await cache.find(video);
    expect(original, isNotNull);
    await cloud.trim(0);
    expect(await File(original!).exists(), isFalse);
    final downloads = remote.downloads;
    expect(await cache.find(video), original);
    expect(remote.downloads, downloads + 1);
    remote.online = false;
    expect(await cache.find(video), original);
  });
  final livePacket = Platform.environment['RSHOP_LIVE_METADATA_PACKET'];
  test('real published Drive packet recovers into an empty isolated store',
      () async {
    final packet = (jsonDecode(await File(livePacket!).readAsString()) as Map)
        .cast<String, dynamic>();
    final root = await Directory.systemTemp.createTemp('rshop-live-packet-');
    final store = await SharedMetadataStore.open(root,
        factory: databaseFactoryFfiNoIsolate);
    addTearDown(() async {
      await store.close();
      await root.delete(recursive: true);
    });
    await store.importCloudPacket(packet);
    final rows = await store.cloudIndex.query('records');
    expect(rows.length, (packet['records'] as List).length);
    expect(await store.artworkRoot.exists(), isFalse);
    final recovered = await store.cloudPackets().toList();
    expect(recovered.expand((p) => p['records'] as List).length, rows.length);
    expect(recovered.expand((p) => p['artwork'] as List).length,
        (packet['artwork'] as List).length);
  },
      skip:
          livePacket == null ? 'Explicit private live packet required' : false);
}
