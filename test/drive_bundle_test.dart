import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/services/drive/drive_bundle.dart';
import 'package:g_shop/services/drive/drive_api.dart';
import 'package:g_shop/services/drive/drive_authorization.dart';
import 'package:g_shop/services/drive/drive_catalogue.dart';
import 'package:g_shop/services/drive/drive_runtime.dart';
import 'package:g_shop/services/drive/drive_media.dart';
import 'package:g_shop/services/owned_storage.dart';
import 'package:g_shop/services/transfer_journal.dart';
import 'package:g_shop/models/config/drive_source_config.dart';
import 'package:g_shop/models/config/provider_config.dart';

import '../integration_test/support/drive_bundle_protocol_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  const config = ProviderConfig(
      type: ProviderType.drive,
      priority: 1,
      sourceId: 'source',
      path: 'root-id',
      drive: DriveSourceConfig(
          accountId: 'account',
          rootFolderId: 'root-id',
          serverClientId: 'public-client'));
  Future<
      ({
        DriveRuntime runtime,
        BundleFixtureTransport transport,
        Database db
      })> fixture() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DriveCatalogueSchema.install(db);
    await TransferJournalSchema.install(db);
    final transport = BundleFixtureTransport();
    final auth = DriveAuthorization(BundleFixtureAccount());
    final catalogue = DriveCatalogue(Future.value(db));
    final api = DriveApi(
        authorization: auth,
        accountId: 'account',
        httpClientAdapter: transport);
    await catalogue.refresh(
        sourceId: 'source',
        accountId: 'account',
        rootFolderId: 'root-id',
        api: api);
    const channel = MethodChannel('bundle-planning-fixture');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ownedPrepare');
      return {
        'destinationRoot': '/roms',
        'stageRoot': '/owned',
        'destinationVolume': '1',
        'stageVolume': '1',
        'destinationMount': '1',
        'stageMount': '1',
        'destinationFreeBytes': 100000,
        'stageFreeBytes': 100000
      };
    });
    final runtime = DriveRuntime(
        catalogue: catalogue,
        journal: TransferJournal(Future.value(db)),
        storage: const OwnedStorage(channel: channel),
        createAuthorization: (_) => auth,
        createApi: (_, __) => api,
        createMediaApi: (_, __) => DriveMediaApi(
            authorization: auth,
            accountId: 'account',
            httpClientAdapter: transport));
    addTearDown(() async {
      await runtime.disconnect();
      await db.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    return (runtime: runtime, transport: transport, db: db);
  }

  test(
      'rooted exact planner reads only selected headers and resumes the durable graph offline',
      () async {
    final f = await fixture();
    final artifact = f.transport.nodes['playlist']!.artifact(
        sourceId: 'source', accountId: 'account', displayPath: 'game.m3u');
    final root = await f.runtime.reserveBundle(
        config: config,
        artifact: artifact,
        destinationRoot: '/roms',
        supportedExtensions: {'.chd', '.bin', '.cue'},
        cancellation: CancelToken());
    expect(root.bundleMembers.map((m) => m.artifact.id.providerFileId),
        ['disc1', 'track', 'cue']);
    expect(
        root.bundleMembers.map(
            (m) => m.relativePath.substring(m.relativePath.indexOf('/') + 1)),
        ['Disc 1.chd', 'Disc 2/track.bin', 'Disc 2/disc.cue']);
    expect(f.transport.media, ['playlist', 'cue']);
    final resumed = await f.runtime.reserveBundle(
        config: config,
        artifact: artifact,
        destinationRoot: '/roms',
        supportedExtensions: {'.chd', '.bin'},
        cancellation: CancelToken(),
        transferId: root.id);
    expect(resumed.toJson(), root.toJson());
    expect(f.transport.media, ['playlist', 'cue']);
  });
  test('missing dependency never reserves an installation target', () async {
    final f = await fixture();
    final artifact = f.transport.nodes['playlist']!.artifact(
        sourceId: 'source', accountId: 'account', displayPath: 'game.m3u');
    await f.db.delete('drive_catalogue_entries',
        where: 'file_id = ?', whereArgs: ['disc1']);
    await expectLater(
        f.runtime.reserveBundle(
            config: config,
            artifact: artifact,
            destinationRoot: '/roms',
            supportedExtensions: {'.chd', '.bin'},
            cancellation: CancelToken()),
        throwsA(isA<DriveCatalogueException>()));
    expect(await f.db.query('transfer_target_owners'), isEmpty);
  });
  test(
      'duplicate exact dependency names never choose the first catalogue entry',
      () async {
    final f = await fixture();
    f.transport.nodes['disc-duplicate'] = DriveFile.fromJson(
        {...f.transport.nodes['disc1']!.toJson(), 'id': 'disc-duplicate'});
    await f.runtime.catalogue.refresh(
        sourceId: 'source',
        accountId: 'account',
        rootFolderId: 'root-id',
        api: f.runtime.apiFor(config.drive!),
        restart: true);
    final artifact = f.transport.nodes['playlist']!.artifact(
        sourceId: 'source', accountId: 'account', displayPath: 'game.m3u');
    await expectLater(
        f.runtime.reserveBundle(
            config: config,
            artifact: artifact,
            destinationRoot: '/roms',
            supportedExtensions: {'.chd', '.bin'},
            cancellation: CancelToken()),
        throwsA(isA<DriveCatalogueException>()));
    expect(await f.db.query('transfer_target_owners'), isEmpty);
  });
  test(
      'cancelling header planning joins the original media request without reserving targets',
      () async {
    final f = await fixture();
    final artifact = f.transport.nodes['playlist']!.artifact(
        sourceId: 'source', accountId: 'account', displayPath: 'game.m3u');
    final token = CancelToken();
    f.transport.mediaEntered = Completer<void>();
    final future = f.runtime.reserveBundle(
        config: config,
        artifact: artifact,
        destinationRoot: '/roms',
        supportedExtensions: {'.chd', '.bin'},
        cancellation: token);
    final outcome = expectLater(future, throwsA(isA<DriveTransferException>()));
    await f.transport.mediaEntered!.future;
    token.cancel();
    await outcome;
    expect(await f.db.query('transfer_target_owners'), isEmpty);
  });
  test('playlist preserves ordered explicit relative disc dependencies', () {
    expect(
        BundleReferences.parse(
            'game.m3u',
            utf8.encode(
                '\uFEFF#EXTM3U\r\n#EXTINF:-1,Disc 1\r\n./Disc 1/game.chd\r\nDisc 2/game.cue\r\n')),
        ['Disc 1/game.chd', 'Disc 2/game.cue']);
  });
  test('cue keeps every distinct binary track and rejects unsupported types',
      () {
    expect(
        BundleReferences.parse(
            'disc.cue',
            utf8.encode(
                'FILE "Track 01.bin" BINARY\n TRACK 01 MODE2/2352\n INDEX 01 00:00:00\n'
                'FILE "Track 02.bin" BINARY\n TRACK 02 AUDIO\n INDEX 01 00:00:00\n')),
        ['Track 01.bin', 'Track 02.bin']);
    expect(
        () => BundleReferences.parse(
            'disc.cue', utf8.encode('FILE "sound.mp3" MP3\n')),
        throwsA(isA<BundleLayoutException>()));
  });
  test('paths cannot escape or be remotely substituted; empty layouts fail',
      () {
    for (final name in [
      '../secret.chd',
      '/secret.chd',
      'https://site/game.chd',
      'C:/game.chd',
      'dir\\game.chd',
      '',
      '# no discs'
    ]) {
      expect(() => BundleReferences.parse('game.m3u', utf8.encode(name)),
          throwsA(isA<BundleLayoutException>()));
    }
  });
  test('ambiguous folded paths and excessive protocol input are visible errors',
      () {
    expect(
        () => BundleReferences.parse('game.m3u', utf8.encode('A.chd\na.chd')),
        throwsA(isA<BundleLayoutException>()));
    expect(
        () => BundleReferences.parse(
            'game.m3u', List.filled(1024 * 1024 + 1, 65)),
        throwsA(isA<BundleLayoutException>()));
  });
}
