import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/game_item.dart';
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
    with RouteAware {
  GameDetailController? _controller;
  PreviewSelection? _selection;
  SecondaryPreview? _bridge;
  ModalRoute<void>? _route;
  GameMetadataInfo? _metadata;
  MetadataMedia? _videoMedia;
  String? _video, _notice, _sent;
  bool _details = false, _visible = true, _working = false;
  bool _clipLoading = false;
  int _clipRequest = 0;
  int _generation = 0;
  bool? _clipPreference;
  String? _bindingSignature;
  final _launcher = OwnedEmulatorLauncher();
  @override
  void initState() {
    super.initState();
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
    if (mounted) setState(() {});
  }

  void _changed() {
    if (mounted) setState(() {});
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
    _generation++;
    _details = false;
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
    if (_details) {
      unawaited(
          _action(_controller!.canOpenSelected ? 'launch' : 'download', null));
    } else {
      setState(() => _details = true);
    }
    return true;
  }

  bool closeDetails() {
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
              onSelect: () {
                if (mounted) setState(() => _details = true);
              }),
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
              label: 'Download media',
              icon: Icons.movie_outlined,
              onSelect: downloadMedia),
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
      final path = media == null
          ? null
          : await ref
              .read(metadataControlsProvider.notifier)
              .cachedPreviewVideo(media);
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
    if (action == 'details') {
      setState(() => _details = true);
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
      _metadata = null;
      _video = null;
      _videoMedia = null;
      _generation++;
      setState(() {});
      return;
    }
    setState(() => _working = true);
    final generation = _generation;
    try {
      if (action == 'launch' && controller.canOpenSelected) {
        await openManagedGame(
            ref,
            context,
            _launcher,
            controller.selectedVariant,
            selection.system,
            selection.target, beforeHandoff: () async {
          if (!mounted || generation != _generation)
            throw PlatformException(code: 'cancelled');
        });
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
      if (mounted && generation == _generation) {
        _notice = error is StateError
            ? error.message.toString()
            : error is PlatformException && error.code == 'save_conflict'
                ? 'Choose which save to use in Save backups.'
                : 'Could not finish. Check game or metadata settings.';
      }
    } finally {
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
      final prefs = ref.watch(previewSettingsProvider);
      final audio = ref.watch(soundSettingsProvider);
      final media = ref.watch(mediaPresentationProvider);
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
            '${controller.selectedVariant.selectionKey}:${controller.selectedVariant.raMatchKey}',
        'filename': controller.selectedVariant.filename,
        'title': controller.selectedVariant.displayName,
        'system': selection.system.id,
        'cover': local(metadata?.cachedCover ??
            selection.variants[controller.selectedIndex].cachedCoverUrl),
        'label': local(metadata?.cachedSupportTexture),
        'gbcDualMode': metadata?.gbcDualMode,
        'screenshots': metadata?.cachedScreenshots
                .where((s) => s.startsWith('file://'))
                .toList() ??
            [],
        'summary': metadata?.summary,
        'credits': metadata?.creditsLine,
        'genres': metadata?.genres,
        'rating':
            metadata?.overallRating?.rating.normalizedValue ?? metadata?.rating,
        'video': _video,
        'audioVolume': audio.enabled ? audio.bgmVolume.clamp(0.0, 1.0) : 0.0,
        'resourceGeneration': ref.watch(socketMediaImportProvider).generation,
        'resourceRoot': ref.read(socketMediaImportProvider).rootDirectory?.path,
        'threeD': media.enabled,
        'reducedMotion': media.reducedMotion,
        'details': _details,
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
  void dispose() {
    _generation++;
    widget.selection.removeListener(_selected);
    previewRouteObserver.unsubscribe(this);
    _controller?.removeListener(_changed);
    _controller?.dispose();
    unawaited(_bridge?.hide(this));
    super.dispose();
  }
}
