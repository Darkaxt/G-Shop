import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/game_item.dart';
import '../../models/console_model.dart';
import '../../models/nes_cartridge_model.dart';
import '../../models/nes_launch_scene.dart';
import '../../models/scene_launch_presentation.dart';
import '../../models/game_watch_hardware_info.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/game_metadata_info.dart';
import '../../models/preview_settings.dart';
import '../../models/scraped_metadata.dart';
import '../../models/system_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/download_providers.dart';
import '../../providers/game_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/metadata_providers.dart';
import '../../providers/metadata_cloud_providers.dart';
import '../../providers/preview_providers.dart';
import '../../providers/rom_status_providers.dart';
import '../../services/library_store.dart';
import '../../services/owned_emulator_launcher.dart';
import '../../services/secondary_preview.dart';
import '../../services/metadata/metadata_artwork_cache.dart';
import '../../services/metadata/preview_video_cache.dart';
import '../game_detail/game_detail_controller.dart';
import '../game_detail/open_managed_game.dart';
import '../../widgets/quick_menu.dart';

final previewRouteObserver = RouteObserver<ModalRoute<void>>();

class PreviewSelection {
  final GameItem game;
  final List<GameItem> variants;
  final SystemModel system;
  final String target;
  final bool localOnly, autoExtract;
  const PreviewSelection(
      {required this.game,
      required this.variants,
      required this.system,
      required this.target,
      this.localOnly = false,
      this.autoExtract = false});
  String get identity => '${system.id}:${game.selectionKey}';
}

/// Main-engine owner of selection and actions. Secondary engine receives only
/// local rendering facts, never credentials, DB handles or installation state owners.
class DualScreenPreviewHost extends ConsumerStatefulWidget {
  final ValueNotifier<int> selection;
  final PreviewSelection? Function(int) itemAt;
  final Widget child;
  const DualScreenPreviewHost(
      {super.key,
      required this.selection,
      required this.itemAt,
      required this.child});
  @override
  ConsumerState<DualScreenPreviewHost> createState() =>
      DualScreenPreviewHostState();
}

class DualScreenPreviewHostState extends ConsumerState<DualScreenPreviewHost>
    with RouteAware, WidgetsBindingObserver {
  GameDetailController? _controller;
  PreviewSelection? _selection;
  SecondaryPreview? _bridge;
  ModalRoute<void>? _route;
  GameMetadataInfo? _metadata;
  MetadataMedia? _videoMedia;
  String? _video, _notice, _sent;
  bool _details = false, _visible = true, _working = false;
  bool _gallery = false;
  bool _cartridgeInspected = false;
  bool _galleryManual = false;
  bool _galleryLoading = false;
  int _galleryRequest = 0;
  Map<String, List<String>>? _openedGallery;
  bool _clipLoading = false;
  int _clipRequest = 0;
  int _generation = 0;
  List<GameWatchModelVariant> _hardwareModels = const [];
  String? _hardwareFilename;
  int? _inspectedHardware;
  bool _hardwareInformationVisible = false;
  int _hardwareRequest = 0;
  Future<void> _loadHardware(String filename) async {
    final request = ++_hardwareRequest;
    final generation = _generation;
    try {
      final models = await ConsoleModel.findGameWatchVariants(filename);
      if (!mounted ||
          request != _hardwareRequest ||
          generation != _generation ||
          _hardwareFilename != filename) {
        return;
      }
      setState(() => _hardwareModels = models);
    } catch (_) {
      // The existing lower-preview import owner reports import failures.
      // No imported model means no speculative controller inspection entry.
    }
  }

  bool? _clipPreference;
  String? _bindingSignature;
  final _launcher = OwnedEmulatorLauncher();
  final _sceneLaunch = SceneLaunchPresentation();
  String? _launchConsoleGeneration;
  String? _launchDisplayGeneration;
  String? _nesReferenceStyle;
  bool get _sceneView =>
      ref.read(mediaPresentationProvider).enabled &&
      _selection?.system.id == 'nes';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sceneLaunch.addListener(_sceneLaunchChanged);
    widget.selection.addListener(_selected);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != route) {
      previewRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) previewRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didUpdateWidget(DualScreenPreviewHost old) {
    super.didUpdateWidget(old);
    if (widget.selection != old.selection) {
      old.selection.removeListener(_selected);
      widget.selection.addListener(_selected);
    }
  }

  @override
  void didPushNext() {
    _sceneLaunch.cancel();
    _visible = false;
    unawaited(_bridge?.hide(this));
  }

  @override
  void didPopNext() {
    _visible = true;
    _sent = null;
    _controller?.checkInstallationStatus();
    if (mounted) setState(() {});
  }

  void _selected() {
    _sceneLaunch.cancel();
    if (mounted) setState(() {});
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _sceneLaunchChanged() {
    debugPrint('GShopSceneLaunch ${jsonEncode({
          'token': _sceneLaunch.token,
          'phase': _sceneLaunch.phase.name,
          'console': _sceneLaunch.consoleId,
          'view': 'secondary',
          'skip': _sceneLaunch.skipRequested,
          'visualAvailable': _sceneLaunch.visualAvailable,
        })}');
    _changed();
  }

  void _bind(PreviewSelection selection) {
    final signature = jsonEncode([
      selection.identity,
      selection.target,
      selection.localOnly,
      selection.autoExtract,
      for (final variant in selection.variants)
        [
          variant.selectionKey,
          variant.raMatchKey,
          variant.filename,
          variant.url
        ]
    ]);
    final previous = _selection;
    if (_bindingSignature == signature &&
        previous != null &&
        previous.variants.length == selection.variants.length &&
        Iterable.generate(selection.variants.length).every((i) => identical(
            previous.variants[i].providerConfig,
            selection.variants[i].providerConfig))) {
      _selection = selection;
      return;
    }
    _bindingSignature = signature;
    _sceneLaunch.reset(notify: false);
    _launchConsoleGeneration = null;
    _launchDisplayGeneration = null;
    _nesReferenceStyle =
        NesCartridgeModel.referencesFor(selection.game.filename).firstOrNull;
    _generation++;
    _hardwareRequest++;
    _hardwareModels = const [];
    _hardwareFilename = null;
    _inspectedHardware = null;
    _hardwareInformationVisible = false;
    _details = false;
    _cartridgeInspected = false;
    _gallery = false;
    _galleryManual = false;
    _galleryLoading = false;
    _openedGallery = null;
    _galleryRequest++;
    _video = null;
    _videoMedia = null;
    _metadata = null;
    _notice = null;
    _sent = null;
    _clipPreference = null;
    _controller?.removeListener(_changed);
    _controller?.dispose();
    _selection = selection;
    _controller = GameDetailController(
        game: selection.game,
        variants: selection.variants,
        system: selection.system,
        targetFolder: selection.target,
        isLocalOnly: selection.localOnly,
        autoExtract: selection.autoExtract,
        queueManager: ref.read(downloadQueueManagerProvider),
        databaseService: ref.read(libraryDbProvider));
    _controller!.onOpenLocal = () => _action('launch', null);
    _controller!.addListener(_changed);
  }

  bool activateDetails() {
    if (!ref.read(dualScreenPreviewProvider) ||
        !_visible ||
        _controller == null) return false;
    if (_sceneLaunch.canInterrupt) {
      _sceneLaunch.confirm();
      return true;
    }
    if (_sceneView) {
      unawaited(
          _action(_controller!.canOpenSelected ? 'launch' : 'download', null));
      return true;
    }
    if (_inspectedHardware != null) {
      setState(
          () => _hardwareInformationVisible = !_hardwareInformationVisible);
      return true;
    }
    if (_details) {
      unawaited(
          _action(_controller!.canOpenSelected ? 'launch' : 'download', null));
    } else {
      setState(() => _details = true);
    }
    return true;
  }

  bool closeDetails() {
    if (_sceneLaunch.cancel()) return true;
    if (_sceneView && _details) {
      setState(() => _details = false);
      return true;
    }
    if (_sceneView && _cartridgeInspected) {
      setState(() => _cartridgeInspected = false);
      return true;
    }
    if (_hardwareInformationVisible) {
      setState(() => _hardwareInformationVisible = false);
      return true;
    }
    if (_inspectedHardware != null) {
      setState(() => _inspectedHardware = null);
      return true;
    }
    if (!_details) return false;
    setState(() => _details = false);
    return true;
  }

  QuickMenuItem? get actionsMenu {
    final controller = _controller;
    if (!ref.read(dualScreenPreviewProvider) || controller == null) return null;
    return QuickMenuItem(
        label: 'Game actions',
        icon: Icons.gamepad_outlined,
        children: [
          QuickMenuItem(
              label: 'Details',
              icon: Icons.info_outline,
              onSelect: () => _action('details', null)),
          if (_hardwareModels.isNotEmpty)
            QuickMenuItem(
                label: 'Inspect hardware',
                icon: Icons.zoom_in,
                children: [
                  for (var i = 0; i < _hardwareModels.length; i++)
                    QuickMenuItem(
                        label: _hardwareModels[i].label ??
                            GameWatchHardwareInfo.forHardware(
                                    _hardwareModels[i].model.hardwareId)
                                ?.series ??
                            'Hardware edition',
                        icon: Icons.view_in_ar,
                        onSelect: () => _action('hardware-inspect', i))
                ]),
          if (_inspectedHardware != null) ...[
            QuickMenuItem(
                label: _hardwareInformationVisible
                    ? 'Hide hardware information'
                    : 'Hardware information',
                icon: Icons.info_outline,
                onSelect: () => _action(
                    _hardwareInformationVisible
                        ? 'hardware-hide-info'
                        : 'hardware-info',
                    null)),
            if (_hardwareInformationVisible)
              QuickMenuItem(
                  label: 'Open reference page',
                  icon: Icons.open_in_new,
                  onSelect: () => _action('hardware-source', null)),
            QuickMenuItem(
                label: 'Back to models',
                icon: Icons.arrow_back,
                onSelect: () => _action('hardware-overview', null)),
          ],
          if (controller.canOpenSelected)
            QuickMenuItem(
                label: 'Play',
                icon: Icons.play_arrow,
                onSelect: () => _action('launch', null)),
          if (!controller.state.isVariantInstalled &&
              controller.selectedVariant.hasDownloadSource)
            QuickMenuItem(
                label: 'Download',
                icon: Icons.download,
                onSelect: () => _action('download', null)),
          if ((_selection?.variants.length ?? 0) > 1)
            QuickMenuItem(
                label: 'Version',
                icon: Icons.layers_outlined,
                children: [
                  for (var i = 0; i < _selection!.variants.length; i++)
                    QuickMenuItem(
                        label: _selection!.variants[i].filename,
                        icon: Icons.album_outlined,
                        onSelect: () => _action('variant', i)),
                ]),
          QuickMenuItem(
              label: 'Resources',
              icon: Icons.view_in_ar,
              onSelect: () => _action('gallery', null)),
          if (_video != null &&
              ref.read(previewSettingsProvider).background ==
                  PreviewBackground.video)
            QuickMenuItem(
                label: 'Play / pause preview',
                icon: Icons.play_circle_outline,
                onSelect: () => _bridge?.togglePlayback(this)),
        ]);
  }

  Future<void> downloadMedia() => _action('media', null);

  Future<void> _findClip(GameMetadataInfo? metadata) async {
    if (_sceneView) {
      if (mounted)
        setState(() {
          _video = null;
          _videoMedia = null;
          _clipLoading = false;
        });
      return;
    }
    final generation = _generation;
    final request = ++_clipRequest;
    if (mounted) setState(() => _clipLoading = true);
    try {
      final edition = metadata?.editionId;
      if (edition == null) return;
      final record = await LibraryStore(ref.read(libraryDbProvider).database)
          .metadata(edition, 'screenscraper');
      if (!mounted || generation != _generation) return;
      final normalized = ref.read(previewSettingsProvider).normalized;
      final videos = (record == null
              ? const <MetadataMedia>[]
              : MetadataArtworkCache.displayMedia(record, includeVideo: true))
          .where((m) =>
              m.providerReference != null &&
              {'video', 'video-normalized'}.contains(m.type))
          .toList();
      final media = videos
              .where(
                  (m) => m.type == (normalized ? 'video-normalized' : 'video'))
              .firstOrNull ??
          videos.firstOrNull;
      // Playing a cached trailer must not construct the scraping/settings
      // worker: its load() deliberately restores the whole metadata library.
      await ref.read(metadataCloudProvider.notifier).ready;
      final store = await ref.read(sharedMetadataStoreProvider);
      final path = media == null || store == null
          ? null
          : await PreviewVideoCache(store).find(media);
      if (!mounted ||
          generation != _generation ||
          _metadata != metadata ||
          normalized != ref.read(previewSettingsProvider).normalized) return;
      setState(() {
        _videoMedia = media;
        _video = path;
      });
    } catch (_) {
      /* Cached media unavailable: the red/screenshot fallback remains usable. */
    } finally {
      if (mounted && request == _clipRequest && generation == _generation) {
        setState(() => _clipLoading = false);
      }
    }
  }

  Future<void> _action(String action, int? variant) async {
    if (!mounted || !_visible) return;
    if (action == 'media-inspection') {
      if (_sceneView &&
          !_sceneLaunch.pending &&
          (variant == 0 || variant == 1)) {
        setState(() => _cartridgeInspected = variant == 1);
      }
      return;
    }
    if (action.startsWith('nes-reference:')) {
      if (_sceneLaunch.pending || _selection?.system.id != 'nes') return;
      final style = action.substring('nes-reference:'.length);
      if (style == 'none' || NesCartridgeModel.labels.containsKey(style)) {
        _nesReferenceStyle = style == 'none' ? null : style;
      }
      return;
    }
    if (action.startsWith('launch-')) {
      if (variant == null || variant != _sceneLaunch.token) return;
      switch (action) {
        case 'launch-ready':
          _sceneLaunch.ready(variant);
        case 'launch-unavailable':
          _sceneLaunch.unavailable(variant);
        case 'launch-finished':
          _sceneLaunch.rendered(variant);
        case 'launch-cancel':
          _sceneLaunch.cancel();
        case 'launch-skip':
          _sceneLaunch.skip();
      }
      return;
    }
    if (action == 'launch' && _sceneLaunch.canInterrupt) {
      _sceneLaunch.confirm();
      return;
    }
    if (_sceneLaunch.phase == SceneLaunchPhase.committing) return;
    if (_sceneLaunch.canInterrupt) _sceneLaunch.cancel();
    if (action == 'hardware-inspect') {
      if (variant == null || variant < 0 || variant >= _hardwareModels.length) {
        return;
      }
      setState(() {
        _inspectedHardware = variant;
        _hardwareInformationVisible = false;
        _details = false;
        _gallery = false;
      });
      return;
    }
    if (action == 'hardware-info' || action == 'hardware-hide-info') {
      if (_inspectedHardware == null) return;
      setState(() => _hardwareInformationVisible = action == 'hardware-info');
      return;
    }
    if (action == 'hardware-source') {
      final index = _inspectedHardware;
      if (index == null || index >= _hardwareModels.length) return;
      final generation = _generation;
      final info = GameWatchHardwareInfo.forHardware(
          _hardwareModels[index].model.hardwareId);
      final opened = await launchUrl(
          Uri.parse(info?.sourceUrl ??
              'https://nintendogameandwatch.com/collection/'),
          mode: LaunchMode.externalApplication);
      if (!opened &&
          mounted &&
          generation == _generation &&
          _inspectedHardware == index) {
        setState(() => _notice = 'The reference page could not be opened.');
      }
      return;
    }
    if (action == 'hardware-overview') {
      setState(() {
        _inspectedHardware = null;
        _hardwareInformationVisible = false;
      });
      return;
    }
    if (action == 'gallery' || action == 'manual' || action == 'preview') {
      final edition = _metadata?.editionId;
      if (action != 'preview' && _galleryLoading) return;
      final request = ++_galleryRequest;
      setState(() {
        _gallery = action != 'preview';
        _galleryManual = action == 'manual';
        _galleryLoading = _gallery && edition != null;
        _details = false;
        _inspectedHardware = null;
        _hardwareInformationVisible = false;
        _notice = null;
      });
      if (action != 'preview' && edition != null) {
        try {
          final resources =
              await (await ref.read(cachedMetadataArtworkProvider))
                  .galleryForEdition(edition, hydrate: true);
          if (!mounted ||
              !_visible ||
              request != _galleryRequest ||
              _metadata?.editionId != edition) return;
          setState(() => _openedGallery = resources);
        } catch (_) {
          if (mounted && request == _galleryRequest)
            setState(() {
              _gallery = false;
              _details = true;
              _notice =
                  'Resources could not load. Check your connection and try again.';
            });
        } finally {
          if (mounted && request == _galleryRequest)
            setState(() => _galleryLoading = false);
        }
      }
      return;
    }
    if (action == 'details') {
      setState(() {
        _details = true;
        if (!_sceneView) _inspectedHardware = null;
        _hardwareInformationVisible = false;
      });
      return;
    }
    if (action == 'close') {
      closeDetails();
      return;
    }
    final controller = _controller, selection = _selection;
    if (controller == null || selection == null || _working) return;
    if (action == 'variant' &&
        variant != null &&
        variant >= 0 &&
        variant < selection.variants.length) {
      controller.selectVariant(variant);
      _cartridgeInspected = false;
      _nesReferenceStyle =
          NesCartridgeModel.referencesFor(controller.selectedVariant.filename)
              .firstOrNull;
      _metadata = null;
      _video = null;
      _videoMedia = null;
      _generation++;
      setState(() {});
      return;
    }
    setState(() => _working = true);
    final generation = _generation;
    int? launchToken;
    try {
      if (action == 'launch' && controller.canOpenSelected) {
        if (_sceneView) {
          setState(() {
            _details = false;
            _hardwareInformationVisible = false;
          });
        }
        final cinematic = _sceneView && selection.system.id == 'nes';
        final token = launchToken = cinematic
            ? _sceneLaunch.begin(
                identity:
                    '${selection.identity}:${controller.selectedVariant.selectionKey}',
                consoleId: null)
            : null;
        if (token != null) {
          _launchConsoleGeneration = null;
          _launchDisplayGeneration = null;
          try {
            final target =
                await NesLaunchScene.chooseConsole(_nesReferenceStyle);
            final display = await ConsoleModel.findNesLaunchDisplay();
            if (display != null) await display.load();
            if (!mounted ||
                generation != _generation ||
                !_sceneLaunch.canInterrupt) {
              throw PlatformException(code: 'cancelled');
            }
            if (target == null || display == null) {
              _sceneLaunch.unavailable(token);
            } else {
              setState(() {
                _launchConsoleGeneration = target.generation;
                _launchDisplayGeneration = display.generation;
              });
              _sceneLaunch.selectConsole(token, 'nes-${target.launchTarget}');
            }
          } on FormatException {
            _sceneLaunch.unavailable(token);
          } on FileSystemException {
            _sceneLaunch.unavailable(token);
          }
        }
        await openManagedGame(
            ref,
            context,
            _launcher,
            controller.selectedVariant,
            selection.system,
            selection.target, beforeHandoff: () async {
          if (!mounted || generation != _generation)
            throw PlatformException(code: 'cancelled');
          if (token == null) return;
          if (!await _sceneLaunch.commitWhenPresented(token) ||
              !mounted ||
              generation != _generation) {
            throw PlatformException(code: 'cancelled');
          }
        });
        if (token != null) _sceneLaunch.handedOff(token);
      } else if (action == 'download' && !controller.state.isVariantInstalled) {
        final added =
            await controller.addVariantToQueue(controller.selectedIndex);
        if (mounted && generation == _generation)
          _notice =
              added ? 'Added to downloads.' : 'Already queued or unavailable.';
      } else if (action == 'media') {
        final prefs = ref.read(previewSettingsProvider);
        if (prefs.downloads == PreviewDownloadPolicy.wifi &&
            await SecondaryPreview.channel.invokeMethod<bool>('wifi') != true) {
          throw StateError('Wi-Fi is required by your preview settings.');
        }
        final controls = ref.read(metadataControlsProvider.notifier);
        await controls.load();
        if (_videoMedia == null && _metadata?.cacheRowId != null) {
          await controls.selectProvider('screenscraper');
          await controls.refresh(
              systemSlug: selection.system.id,
              cacheRowId: _metadata!.cacheRowId);
          if (!mounted || generation != _generation) return;
          ref.invalidate(gameMetadataProvider((
            filename: controller.selectedVariant.selectionKey,
            systemSlug: selection.system.id
          )));
          _metadata = await ref.read(gameMetadataProvider((
            filename: controller.selectedVariant.selectionKey,
            systemSlug: selection.system.id
          )).future);
          await _findClip(_metadata);
        }
        final media = _videoMedia;
        if (media == null) {
          _notice =
              'No gameplay clip was supplied. Available images have been kept.';
        } else {
          final path = await controls.downloadPreviewVideo(media,
              budgetBytes: prefs.cacheMiB * 1024 * 1024, protectedPath: _video);
          if (!mounted || generation != _generation) return;
          _video = path;
          _notice = path == null
              ? 'Media download could not finish. Check Metadata settings.'
              : 'Gameplay clip ready offline.';
        }
      }
    } catch (error) {
      if (launchToken != null) _sceneLaunch.failed(launchToken);
      debugPrint('GShopPreviewAction ${jsonEncode({
            'action': action,
            'system': selection.system.id,
            'state': 'failed',
            'errorType': error.runtimeType.toString(),
            if (error is PlatformException) 'code': error.code,
          })}');
      if (mounted && generation == _generation) {
        _notice = error is PlatformException && error.code == 'cancelled'
            ? null
            : error is StateError
                ? error.message.toString()
                : error is PlatformException && error.code == 'save_conflict'
                    ? 'Choose which save to use in Save backups.'
                    : 'Could not finish. Check game or metadata settings.';
      }
    } finally {
      if (_sceneLaunch.canInterrupt) _sceneLaunch.cancel();
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(dualScreenPreviewProvider);
    _bridge = ref.read(secondaryPreviewProvider);
    final selection = widget.itemAt(widget.selection.value);
    if (enabled && selection != null && _visible) {
      _bind(selection);
      final controller = _controller!;
      final visibleCover = ref.watch(cloudSelectionMediaProvider((
        platform: selection.system.id,
        selection: controller.selectedVariant.selectionKey,
        details: false
      )));
      final cloudMedia = ref.watch(cloudSelectionMediaProvider((
        platform: selection.system.id,
        selection: controller.selectedVariant.selectionKey,
        details: true
      )));
      final metadataState = ref.watch(gameMetadataProvider((
        filename: controller.selectedVariant.selectionKey,
        systemSlug: selection.system.id
      )));
      final metadata = metadataState.valueOrNull;
      final galleryMedia = metadata?.editionId == null
          ? <String, List<String>>{}
          : ref
                  .watch(editionGalleryMediaProvider(metadata!.editionId!))
                  .valueOrNull ??
              <String, List<String>>{};
      final prefs = ref.watch(previewSettingsProvider);
      final audio = ref.watch(soundSettingsProvider);
      final media = ref.watch(mediaPresentationProvider);
      final hardwareFilename = controller.selectedVariant.filename;
      if (selection.system.id == 'gameandwatch' &&
          media.enabled &&
          _hardwareFilename != hardwareFilename) {
        _hardwareFilename = hardwareFilename;
        _hardwareModels = const [];
        _inspectedHardware = null;
        _hardwareInformationVisible = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _hardwareFilename == hardwareFilename) {
            unawaited(_loadHardware(hardwareFilename));
          }
        });
      }
      ref.listen(romChangeSignalProvider,
          (previous, next) => controller.checkInstallationStatus());
      final clipChanged =
          _metadata != metadata || _clipPreference != prefs.normalized;
      if (clipChanged) {
        _metadata = metadata;
        _clipPreference = prefs.normalized;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_findClip(metadata));
        });
      }
      String? local(String? url) =>
          url?.startsWith('file://') == true ? url : null;
      final state = controller.state;
      final payload = <String, dynamic>{
        'identity': selection.identity,
        'actionIdentity':
            '${controller.selectedVariant.selectionKey}:${controller.selectedVariant.raMatchKey}:${_sceneLaunch.token}',
        'sceneView': _sceneView,
        'cartridgeInspected': _cartridgeInspected,
        'sceneLaunch': _sceneLaunch.pending
            ? {
                'token': _sceneLaunch.token,
                'phase': _sceneLaunch.phase.name,
                'console': _sceneLaunch.consoleId,
                'consoleGeneration': _launchConsoleGeneration,
                'displayGeneration': _launchDisplayGeneration,
                'skip': _sceneLaunch.skipRequested,
                'visualAvailable': _sceneLaunch.visualAvailable,
              }
            : null,
        'filename': controller.selectedVariant.filename,
        'title': controller.selectedVariant.displayName,
        'system': selection.system.id,
        'cover': local(metadata?.cachedCover ??
            visibleCover.valueOrNull ??
            selection.variants[controller.selectedIndex].cachedCoverUrl),
        'label': local(metadata?.cachedSupportTexture),
        'gbcDualMode': metadata?.gbcDualMode,
        'contentTags': metadata?.contentTags.toList() ?? const <String>[],
        'screenshots': metadata?.cachedScreenshots
                .where((s) => s.startsWith('file://'))
                .toList() ??
            [],
        'summary': metadata?.summary,
        'credits': metadata?.creditsLine,
        'genres': metadata?.genres,
        'rating':
            metadata?.overallRating?.rating.normalizedValue ?? metadata?.rating,
        'scoreLabel': metadata?.overallRating == null
            ? null
            : metadata!.overallRating!.rating.sourceId == 'igdb'
                ? 'IGDB ${(metadata.overallRating!.rating.normalizedValue / 10).toStringAsFixed(1)}'
                : '${metadata.overallRating!.rating.sourceLabel} ${metadata.overallRating!.rating.normalizedValue.toStringAsFixed(1)}/100',
        'installed': state.isVariantInstalled,
        'video': _video,
        'audioVolume': audio.enabled ? audio.bgmVolume.clamp(0.0, 1.0) : 0.0,
        'resourceGeneration': ref.watch(socketMediaImportProvider).generation,
        'resourceRoot': ref.read(socketMediaImportProvider).rootDirectory?.path,
        'threeD': media.enabled,
        'reducedMotion': media.reducedMotion,
        'details': _details,
        'inspectedHardware': _inspectedHardware,
        'hardwareInformationVisible': _hardwareInformationVisible,
        'gallery': _gallery,
        'galleryManual': _galleryManual,
        'galleryLoading': _galleryLoading,
        'galleryResources':
            _gallery ? (_openedGallery ?? galleryMedia) : galleryMedia,
        'variant': controller.selectedIndex,
        'variants': selection.variants.map((v) => v.filename).toList(),
        'canLaunch': !_working && controller.canOpenSelected,
        'canDownload': !_working &&
            !state.isVariantInstalled &&
            controller.selectedVariant.hasDownloadSource,
        'readiness': state.isVariantInstalled
            ? (controller.canOpenSelected ? 'Ready to play' : 'Stored locally')
            : 'Available in the cloud',
        'notice': _notice ?? state.error,
        'mediaBusy': _working,
        'settings': prefs.toJson(),
        'mediaLoading': cloudMedia.isLoading ||
            (media.enabled &&
                selection.system.id == 'gba' &&
                metadata?.editionId != null &&
                ref
                    .watch(editionGalleryMediaProvider(metadata!.editionId!))
                    .isLoading) ||
            metadataState.isLoading ||
            _clipLoading ||
            clipChanged,
      };
      final encoded = jsonEncode(payload);
      if (encoded != _sent) {
        _sent = encoded;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _visible && _sent == encoded) {
            unawaited(_bridge!.present(this, payload, _action));
          }
        });
      }
    } else {
      if (!enabled && _controller != null) {
        _generation++;
        _controller!.removeListener(_changed);
        _controller!.dispose();
        _controller = null;
        _selection = null;
        _bindingSignature = null;
      }
      _sent = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_bridge?.hide(this));
      });
    }
    return widget.child;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _sceneLaunch.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sceneLaunch.removeListener(_sceneLaunchChanged);
    _sceneLaunch.dispose();
    _generation++;
    widget.selection.removeListener(_selected);
    previewRouteObserver.unsubscribe(this);
    _controller?.removeListener(_changed);
    _controller?.dispose();
    unawaited(_bridge?.hide(this));
    super.dispose();
  }
}
