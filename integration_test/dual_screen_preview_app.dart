// Isolated real-window verification. No production bootstrap, ROM download,
// account chooser, save restore or production-data mutation.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:retro_eshop/core/input/input.dart';
import 'package:retro_eshop/core/theme/app_theme.dart';
import 'package:retro_eshop/features/library/library_screen.dart';
import 'package:retro_eshop/features/preview/dual_screen_preview_host.dart';
import 'package:retro_eshop/l10n/app_localizations.dart';
import 'package:retro_eshop/models/config/app_config.dart';
import 'package:retro_eshop/models/config/system_config.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/providers/game_providers.dart';
import 'package:retro_eshop/providers/library_providers.dart';
import 'package:retro_eshop/providers/installed_files_provider.dart';
import 'package:retro_eshop/providers/metadata_providers.dart';
import 'package:retro_eshop/providers/preview_providers.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/installation_index.dart';
import 'package:retro_eshop/services/owned_storage.dart';
import 'package:retro_eshop/services/drive/drive_transfer_engine.dart';
import 'package:retro_eshop/services/drive/drive_media.dart';
import 'package:retro_eshop/services/audio_manager.dart';
import 'package:retro_eshop/services/device_info_service.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/services/metadata/shared_metadata_store.dart';
import 'package:retro_eshop/services/socket_media_import.dart';
import 'package:retro_eshop/services/storage_service.dart';

export 'package:retro_eshop/features/preview/preview_screen.dart'
    show previewMain;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode ||
      !Platform.isAndroid ||
      (await PackageInfo.fromPlatform()).packageName !=
          'com.darkaxt.rshop.sharedproof') {
    throw StateError('Preview proof requires its isolated debug package');
  }
  installGamepadKeyFix();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft]);
  final root = await getApplicationSupportDirectory();
  final storage = StorageService();
  await storage.init();
  await storage.setRomPath('${root.path}/roms');
  await storage.setLibraryConsole('n64');
  await storage.setReducedMediaMotion(true);
  final store =
      await SharedMetadataStore.open(Directory('${root.path}/shared-preview'));
  final db = DatabaseService();
  await db.saveGames('n64', [
    const GameItem(
        filename: 'GoldenEye 007 (USA).z64',
        displayName: 'GoldenEye 007',
        url: ''),
    for (var i = 2; i <= 8; i++)
      GameItem(
          filename: 'Preview sample $i.z64',
          displayName: 'Preview sample $i',
          url: ''),
  ]);
  await SocketMediaImport.instance.initialize();
  final audio = AudioManager();
  await audio.init();
  audio.updateSettings(storage.getSoundSettings());
  await audio.startBgm();
  final memory = await DeviceInfoService.getDeviceMemory();
  final container = ProviderContainer(overrides: [
    deviceMemoryProvider.overrideWithValue(memory),
    audioManagerProvider.overrideWithValue(audio),
    storageServiceProvider.overrideWithValue(storage),
    socketMediaImportProvider.overrideWith((ref) => SocketMediaImport.instance),
    sharedMetadataStoreProvider.overrideWithValue(Future.value(store)),
    bootstrappedConfigProvider.overrideWith((ref) async => AppConfig.empty),
    installedFilesProvider.overrideWith((ref) async => InstalledFilesState()),
  ]);
  runApp(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          navigatorObservers: [previewRouteObserver],
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          home: const _PreviewProof())));
}

class _PreviewProof extends ConsumerStatefulWidget {
  const _PreviewProof();
  @override
  ConsumerState<_PreviewProof> createState() => _PreviewProofState();
}

class _PreviewProofState extends ConsumerState<_PreviewProof>
    with WidgetsBindingObserver {
  final _library = GlobalKey();
  Future<void>? _operation;
  bool _reloadExtensionRegistered = false;
  AppConfig? _launchConfig;
  DualScreenPreviewHostState? _host() {
    DualScreenPreviewHostState? found;
    void visit(Element element) {
      if (element is StatefulElement &&
          element.state is DualScreenPreviewHostState) {
        found = element.state as DualScreenPreviewHostState;
      } else {
        element.visitChildElements(visit);
      }
    }

    (_library.currentContext as Element?)?.visitChildElements(visit);
    return found;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    developer.registerExtension('ext.rshop.previewProof', _proofRequest);
  }

  @override
  void reassemble() {
    super.reassemble();
    if (!_reloadExtensionRegistered) {
      developer.registerExtension('ext.rshop.previewReload', _proofRequest);
      _reloadExtensionRegistered = true;
    }
  }

  Future<developer.ServiceExtensionResponse> _proofRequest(
      String method, Map<String, String> args) async {
    try {
      final command = args['command'] ?? 'status';
      if (_operation != null)
        throw StateError('Original operation still active');
      if (command == 'prepare-launch') {
        _operation = _prepareLaunch(args['romSource']);
        try {
          await _operation;
        } finally {
          _operation = null;
        }
        return developer.ServiceExtensionResponse.result(
            jsonEncode({'prepared': true}));
      }
      if (command == 'media-info') {
        final db = await ref.read(libraryDbProvider).database;
        final rows = await db.query('games',
            columns: ['id'],
            where: 'filename=?',
            whereArgs: ['GoldenEye 007 (USA).z64']);
        final edition = await LibraryStore.cachedCatalogueEditionId(
            db, rows.single['id'] as int);
        final record = edition == null
            ? null
            : await LibraryStore(Future.value(db))
                .metadata(edition, 'screenscraper');
        return developer.ServiceExtensionResponse.result(jsonEncode({
          'types': record?.media.map((m) => m.type).toSet().toList(),
          'videos': [
            for (final media in record?.media ?? [])
              if (media.type.contains('video'))
                {
                  'type': media.type,
                  'reference': media.providerReference != null,
                  'host':
                      media.url == null ? null : Uri.tryParse(media.url!)?.host,
                  'path':
                      media.url == null ? null : Uri.tryParse(media.url!)?.path,
                }
          ],
        }));
      }
      if (command == 'review') {
        final items = await ref
            .read(metadataControlsProvider.notifier)
            .reviewQueue(systemSlug: 'n64', limit: 2);
        return developer.ServiceExtensionResponse.result(jsonEncode({
          'reviews': [
            for (final item in items)
              {
                'title': item.request?.title,
                'tags': item.request?.contentTags.toList(),
                'candidates': [
                  for (final candidate in item.candidates)
                    {
                      'id': candidate.providerGameId,
                      'platform': candidate.platformId,
                      'titles': candidate.titles.map((t) => t.text).toList(),
                      'matched': candidate.titleMatched,
                      'evidence': candidate.evidence,
                    }
                ],
              }
          ],
        }));
      }
      if (command == 'accept-fixture-match') {
        final controls = ref.read(metadataControlsProvider.notifier);
        final items = await controls.reviewQueue(systemSlug: 'n64', limit: 2);
        if (items.length != 1 ||
            items.single.request?.title != 'GoldenEye 007' ||
            items.single.candidates.length != 1 ||
            items.single.candidates.single.platformId != 'n64' ||
            !items.single.candidates.single.titleMatched) {
          throw StateError('Known isolated fixture match is not unique');
        }
        _operation = controls.acceptReview(items.single,
            providerGameId: items.single.candidates.single.providerGameId,
            contentTags: {'official'},
            reviewedRegion: 'us');
        try {
          await _operation;
        } finally {
          _operation = null;
        }
      } else if (command == 'media') {
        // Private authenticated VM request; credential values are never echoed.
        final values =
            (jsonDecode(args['credentials']!) as Map).cast<String, dynamic>();
        final controls = ref.read(metadataControlsProvider.notifier);
        _operation = () async {
          await controls.load();
          await controls.saveScreenScraper(
              ScreenScraperUserCredentials(
                  username: values['SCREENSCRAPER_USERNAME'] as String,
                  password: values['SCREENSCRAPER_PASSWORD'] as String),
              application: ScreenScraperDeveloperCredentials(
                  developerId: values['SCREENSCRAPER_DEVID'] as String,
                  developerPassword:
                      values['SCREENSCRAPER_DEVPASSWORD'] as String,
                  softwareName: values['SCREENSCRAPER_SOFTNAME'] as String));
          await controls.selectProvider('screenscraper');
          final db = await ref.read(libraryDbProvider).database;
          final id = (await db.query('games',
                  columns: ['id'],
                  where: 'filename=?',
                  whereArgs: ['GoldenEye 007 (USA).z64']))
              .single['id'] as int;
          await controls.refresh(systemSlug: 'n64', cacheRowId: id);
        }();
        try {
          await _operation;
        } finally {
          _operation = null;
        }
      } else if (command == 'download-video') {
        final host = _host();
        if (host == null) throw StateError('No selected preview');
        _operation = host.downloadMedia();
        try {
          await _operation;
        } finally {
          _operation = null;
        }
      } else if (command == 'details') {
        _host()?.activateDetails();
      } else if (command == 'flat') {
        if (ref.read(mediaPresentationProvider).enabled)
          await ref.read(mediaPresentationProvider.notifier).toggleMedia();
      } else if (command == '3d') {
        if (!SocketMediaImport.instance.available)
          throw StateError('Import is missing');
        if (!ref.read(mediaPresentationProvider).enabled)
          await ref.read(mediaPresentationProvider.notifier).toggleMedia();
      } else if (command == 'disable') {
        await ref
            .read(previewSettingsProvider.notifier)
            .change('enabled', false);
      } else if (command == 'enable') {
        await ref
            .read(previewSettingsProvider.notifier)
            .change('enabled', true);
      } else if (command == 'playback') {
        final host = _host();
        if (host == null) throw StateError('No selected preview');
        await ref.read(secondaryPreviewProvider).togglePlayback(host);
      } else if (command == 'await-view' || command == 'await-video') {
        await const MethodChannel('com.retro.rshop/preview')
            .invokeMethod<dynamic>('awaitRendered', {'video': command == 'await-video'});
      } else if (command != 'status') {
        throw ArgumentError('Unknown preview proof action');
      }
      final diagnostics = await const MethodChannel('com.retro.rshop/preview')
          .invokeMethod<dynamic>('diagnostics');
      return developer.ServiceExtensionResponse.result(jsonEncode({
        'command': command,
        'window': diagnostics,
        'audio': ref.read(audioManagerProvider).previewDebugState,
        'metadataError': ref.read(metadataControlsProvider).error,
        'metadataBusy': ref.read(metadataControlsProvider).busy,
        'metadataState': ref.read(metadataControlsProvider).report?.state,
        'metadataCounts': ref.read(metadataControlsProvider).report?.counts,
        'metadataBlocked':
            ref.read(metadataControlsProvider).report?.blockedStatus,
        'imported': SocketMediaImport.instance.available
      }));
    } catch (error) {
      return developer.ServiceExtensionResponse.result(
          jsonEncode({'errorType': error.runtimeType.toString(),
            'errorCode': error is OwnedStorageException ? error.code : null}));
    }
  }

  Future<void> _prepareLaunch(String? sourcePath) async {
    // Real existing ROM bytes, read-only source. The source identifiers below
    // are explicitly synthetic; this is not evidence of a live Drive transfer.
    const name = 'GoldenEye 007 (USA).7z';
    final segments = sourcePath?.split('/');
    if (sourcePath == null ||
        !sourcePath.startsWith('/storage/') ||
        segments!.contains('..') ||
        segments.last != name) {
      throw ArgumentError('An explicit existing fixture ROM path is required');
    }
    final source = File(sourcePath);
    final size = await source.length();
    final digest = (await md5.bind(source.openRead()).first).toString();
    final requestedRoot = '${(await getApplicationSupportDirectory()).path}/roms/n64';
    await Directory(requestedRoot).create(recursive: true);
    const native = OwnedStorage();
    final index = InstallationIndex.application();
    final plan = await native.prepare(requestedRoot);
    final root = plan.destinationRoot;
    const id = 's22-real-rom-launch-canonical';
    final artifact = RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: 's22-local-fixture',
            accountId: 'synthetic-source',
            providerFileId: id),
        parentId: 'synthetic-folder',
        displayName: name,
        displayPath: name,
        sizeBytes: size,
        version: '1',
        canDownload: true,
        providerChecksums: {'md5': digest});
    if (await index.journal.transfer(id) == null) {
      await index.journal.create(TransferRecord(
          id: id,
          artifact: artifact,
          destinationRoot: root,
          relativePath: name,
          stagePath: plan.stagePath(id),
          archivePlatformId: 'n64'));
    }
    final engine = DriveTransferEngine(
        journal: index.journal,
        storage: native,
        revalidate: (_, __) async {
          if (await source.length() != size ||
              (await md5.bind(source.openRead()).first).toString() != digest) {
            throw StateError('Fixture source changed');
          }
        },
        openMedia: (_, offset, __) async => DriveMediaResponse(
            bytes: source.openRead(offset).map(Uint8List.fromList),
            offset: offset,
            length: size - offset,
            total: size));
    final result = await engine.start(id).result;
    if (result.lifecycle != TransferLifecycle.completed) {
      throw OwnedStorageException(result.errorCode ?? 'fixture_publication_failed');
    }
    final db = ref.read(libraryDbProvider);
    final database = await db.database;
    await database.delete('games',
        where: 'filename=?', whereArgs: ['GoldenEye 007 (USA).z64']);
    await db.saveGames('n64', [
      GameItem(
          filename: name,
          displayName: 'GoldenEye 007',
          url: '',
          remoteArtifact: artifact)
    ]);
    setState(() => _launchConfig = AppConfig(systems: [
          SystemConfig(
              id: 'n64',
              name: 'Nintendo 64',
              targetFolder: root,
              providers: const [])
        ]));
    ref.read(gameDbChangedProvider.notifier).state++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final audio = ref.read(audioManagerProvider);
    if (state == AppLifecycleState.resumed) {
      audio.resume();
    } else {
      audio.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ref.read(audioManagerProvider).dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _launchConfig == null
      ? LibraryScreen(key: _library)
      : ProviderScope(overrides: [
          bootstrappedConfigProvider
              .overrideWith((ref) async => _launchConfig!),
          installedFilesProvider.overrideWith((ref) async {
            final snapshot = await InstallationIndex.application()
                .scan(_launchConfig!.systems.single.targetFolder);
            return InstalledFilesState(exactBySystem: {
              'n64': snapshot.installed.values.map((i) => i.artifact).toList()
            }, managedBytesBySystem: {
              'n64':
                  snapshot.installed.values.fold(0, (n, i) => n + i.sizeBytes)
            });
          }),
        ], child: LibraryScreen(key: _library));
}
