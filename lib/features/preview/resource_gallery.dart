import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../core/theme/app_theme.dart';
import '../../models/packaging_model.dart';
import '../../models/socket_media_model.dart';
import '../../widgets/socket_media_renderer.dart';
import '../../widgets/handwritten_media_sticker.dart';
import '../../widgets/media_cover_fallback.dart';

enum ResourceView { box, cover, cartridge, manual, gallery }

/// Independent resource inspection. No automatic box/case reveal timeline.
/// Only selected, edition-owned local resources cross the secondary bridge.
class ResourceGallery extends StatefulWidget {
  final String identity, title, systemId;
  final String? region, dualMode;
  final Map<String, List<String>> resources;
  final bool importedModels;
  final double volume;
  final ValueChanged<bool>? onPlayingChanged;
  final VoidCallback? onClose;
  const ResourceGallery(
      {super.key,
      required this.identity,
      required this.title,
      required this.systemId,
      this.region,
      this.dualMode,
      this.resources = const {},
      this.importedModels = false,
      this.volume = .3,
      this.onPlayingChanged,
      this.onClose});
  @override
  State<ResourceGallery> createState() => ResourceGalleryState();
}

class ResourceGalleryState extends State<ResourceGallery>
    with WidgetsBindingObserver {
  final rendererKey = GlobalKey<SocketMediaRendererState>();
  final _readingTransform = TransformationController();
  ResourceView view = ResourceView.box;
  double yaw = -.2, pitch = .06, zoom = .75, opening = 0, aspect = .72;
  double _startZoom = .75;
  int page = 0, _generation = 0;
  bool reading = false;
  VideoPlayerController? _video;
  ImageStream? _coverStream;
  ImageStreamListener? _coverListener;
  Object? _videoError;
  String? first(String type) => widget.resources[type]?.firstOrNull;
  List<String> get images => [
        ...?widget.resources['cover-preview'],
        ...?widget.resources['box-3D'],
        ...?widget.resources['box-2D'],
        ...?widget.resources['box-2D-back'],
        ...?widget.resources['box-2D-side'],
        ...?widget.resources['support-texture'],
        ...?widget.resources['ss'],
        ...?widget.resources['screenshot'],
        ...?widget.resources['fanart']
      ];
  List<String> get pages => widget.resources['manual-page'] ?? const [];
  PackagingKind get kind => view == ResourceView.box
      ? PackagingKind.box
      : view == ResourceView.manual
          ? PackagingKind.booklet
          : {'psx', 'dreamcast', 'segacd', 'saturn', 'neogeocd', 'tgcd'}
                  .contains(widget.systemId)
              ? PackagingKind.jewelCase
              : PackagingKind.keepCase;
  PhysicalMediaFormat? get format =>
      PhysicalMediaFormat.forSystem(widget.systemId,
          region: widget.region, dualMode: widget.dualMode);
  bool get canOpen =>
      (view == ResourceView.cover ||
          view == ResourceView.manual && pages.isNotEmpty) &&
      kind != PackagingKind.box;
  List<ResourceView> get availableViews {
    final physical = !{'arcade', 'tic80', 'pico8'}.contains(widget.systemId);
    final caseOnly = {
      'gc',
      'wii',
      'wiiu',
      'switch',
      'nds',
      'dsi',
      'n3ds',
      'psx',
      'ps2',
      'ps3',
      'psp',
      'psvita',
      'dreamcast',
      'segacd',
      'saturn',
      'neogeocd',
      'tgcd',
      'pcfx',
      'cdi',
      '3do'
    }.contains(widget.systemId);
    return [
      if (physical && !caseOnly) ResourceView.box,
      if (physical && widget.systemId != 'gameandwatch') ResourceView.cover,
      ResourceView.cartridge,
      ResourceView.manual,
      ResourceView.gallery
    ];
  }

  Map<String, Object?> get snapshot => {
        'identity': widget.identity,
        'system': widget.systemId,
        'view': view.name,
        'cinematicEnabled': false,
        'availableViews': availableViews.map((v) => v.name).toList(),
        'aspect': aspect,
        'yaw': yaw,
        'pitch': pitch,
        'zoom': zoom,
        'opening': opening,
        'reading': reading,
        'page': page,
        'manualPages': pages.length,
        'readerScale': _readingTransform.value.getMaxScaleOnAxis(),
        'canOpen': canOpen,
        'model': rendererKey.currentState?.snapshot,
        'videoReady': _video?.value.isInitialized == true,
        'videoPlaying': _video?.value.isPlaying == true,
        'videoError': _videoError?.toString(),
      };
  @override
  void initState() {
    super.initState();
    view = availableViews.first;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveAspect();
  }

  @override
  void didUpdateWidget(ResourceGallery old) {
    super.didUpdateWidget(old);
    if (old.identity != widget.identity) {
      unawaited(_stopVideo());
      reset();
      view = availableViews.first;
      _resolveAspect();
    }
  }

  String? _aspectUrl;
  void _resolveAspect() {
    final url =
        view == ResourceView.manual ? pages.firstOrNull : first('box-2D');
    if (url == _aspectUrl) return;
    _detachCover();
    _aspectUrl = url;
    aspect = .72;
    if (url == null) return;
    final provider = _provider(url);
    _coverStream = provider.resolve(createLocalImageConfiguration(context));
    _coverListener = ImageStreamListener((info, sync) {
      if (mounted && _aspectUrl == url) {
        final ratio = info.image.width / info.image.height;
        void apply() {
          aspect = ratio.clamp(.25, 2.5);
        }

        if (sync) {
          apply();
        } else {
          setState(apply);
        }
      }
      _detachCover();
    }, onError: (_, __) => _detachCover());
    _coverStream!.addListener(_coverListener!);
  }

  void _detachCover() {
    if (_coverListener != null) _coverStream?.removeListener(_coverListener!);
    _coverStream = null;
    _coverListener = null;
  }

  static ImageProvider _provider(String path) {
    if (path.startsWith('file://'))
      return FileImage(File.fromUri(Uri.parse(path)));
    return NetworkImage(path);
  }

  Widget image(String? path,
          {BoxFit fit = BoxFit.contain, bool disc = false, bool umd = false}) =>
      path == null
          ? HandwrittenMediaSticker(
              identity: widget.identity,
              title: widget.title,
              disc: disc,
              umd: umd)
          : Image(
              image: _provider(path),
              fit: fit,
              errorBuilder: (_, __, ___) => HandwrittenMediaSticker(
                  identity: widget.identity,
                  title: widget.title,
                  disc: disc,
                  umd: umd));
  void reset() {
    yaw = -.2;
    pitch = .06;
    zoom = .75;
    opening = 0;
    page = 0;
    reading = false;
    _videoError = null;
    _readingTransform.value = Matrix4.identity();
  }

  void changeZoom(double delta) => setState(() {
        if (reading || view == ResourceView.gallery) {
          final scale = (_readingTransform.value.getMaxScaleOnAxis() + delta)
              .clamp(1.0, 5.0);
          _readingTransform.value = Matrix4.diagonal3Values(scale, scale, 1);
        } else {
          zoom = (zoom + delta).clamp(.35, 1.5);
        }
      });

  void select(ResourceView target) {
    if (target == view || !availableViews.contains(target)) return;
    unawaited(_stopVideo());
    setState(() {
      view = target;
      reset();
      _resolveAspect();
    });
  }

  void _playing() => widget.onPlayingChanged?.call(
      _video?.value.isPlaying == true && _video?.value.isBuffering != true);
  Future<void> _stopVideo() async {
    _generation++;
    final old = _video;
    _video = null;
    old?.removeListener(_playing);
    widget.onPlayingChanged?.call(false);
    await old?.dispose();
  }

  Future<void> play() async {
    final path = first('video') ?? first('video-normalized');
    if (path == null || _video != null) return;
    final generation = ++_generation;
    final video = VideoPlayerController.file(File.fromUri(Uri.parse(path)),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    try {
      await video.initialize();
      if (!mounted || generation != _generation) {
        await video.dispose();
        return;
      }
      await video.setVolume(widget.volume.clamp(0, 1));
      _video = video;
      video.addListener(_playing);
      await video.play();
      if (mounted && generation == _generation) setState(() {});
    } catch (error) {
      if (identical(_video, video)) {
        _video = null;
      }
      video.removeListener(_playing);
      await video.dispose();
      if (mounted && generation == _generation)
        setState(() => _videoError = error);
      widget.onPlayingChanged?.call(false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_stopVideo());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachCover();
    _readingTransform.dispose();
    unawaited(_stopVideo());
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent)
      return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.gameButtonLeft1 ||
        key == LogicalKeyboardKey.gameButtonRight1) {
      select(availableViews[(availableViews.indexOf(view) +
              (key == LogicalKeyboardKey.gameButtonRight1 ? 1 : -1)) %
          availableViews.length]);
    } else if (key == LogicalKeyboardKey.gameButtonA) {
      if (view == ResourceView.gallery) {
        final video = _video;
        unawaited(video == null
            ? play()
            : video.value.isPlaying
                ? video.pause()
                : video.play());
      } else if (canOpen) {
        setState(() => opening = opening == 0 ? 1 : 0);
      }
    } else if (key == LogicalKeyboardKey.gameButtonY &&
        view == ResourceView.manual) {
      setState(() => reading = !reading);
    } else if (key == LogicalKeyboardKey.gameButtonX) {
      setState(reset);
    } else if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.gameButtonB) {
      widget.onClose?.call();
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      setState(() {
        final step = key == LogicalKeyboardKey.arrowRight ? 1 : -1;
        if (reading || view == ResourceView.gallery) {
          page = math.max(0, page + step);
        } else {
          yaw += step * .12;
        }
      });
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      setState(
          () => pitch += (key == LogicalKeyboardKey.arrowDown ? 1 : -1) * .12);
    } else if (key == LogicalKeyboardKey.gameButtonLeft2 ||
        key == LogicalKeyboardKey.gameButtonRight2) {
      changeZoom(key == LogicalKeyboardKey.gameButtonRight2 ? .1 : -.1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _atlas() => Column(children: [
        for (var row = 0; row < 2; row++)
          Expanded(
              child: Row(children: [
            for (var col = 0; col < 3; col++)
              Expanded(
                  child: switch (row * 3 + col) {
                0 => image(
                    view == ResourceView.manual
                        ? pages.firstOrNull
                        : first('box-2D'),
                    fit: BoxFit.fill),
                1 => view == ResourceView.manual
                    ? pages.length < 2
                        ? const ColoredBox(color: Color(0xff252525))
                        : image(pages.last, fit: BoxFit.fill)
                    : first('box-2D-back') == null
                        ? const ColoredBox(color: Color(0xff252525))
                        : image(first('box-2D-back'), fit: BoxFit.fill),
                2 => view == ResourceView.manual || first('box-2D-side') == null
                    ? const ColoredBox(color: Color(0xff252525))
                    : image(first('box-2D-side'), fit: BoxFit.fill),
                _ => const ColoredBox(color: Color(0xff252525)),
              })
          ]))
      ]);
  @override
  Widget build(BuildContext context) {
    final pose = SocketMediaPose(
        rx: pitch,
        ry: yaw,
        scaleX: zoom,
        scaleY: zoom,
        scaleZ: zoom,
        opening: opening);
    final player = _video;
    final content = view == ResourceView.gallery
        ? player != null && player.value.isInitialized
            ? AspectRatio(
                aspectRatio: player.value.aspectRatio,
                child: VideoPlayer(player))
            : images.isEmpty
                ? const Center(child: Text('No images collected yet'))
                : InteractiveViewer(
                    transformationController: _readingTransform,
                    minScale: 1,
                    maxScale: 5,
                    child: image(images[page % images.length]))
        : view == ResourceView.manual && pages.isEmpty
            ? const Center(child: Text('No manual collected yet'))
            : view == ResourceView.manual && reading
                ? pages.isEmpty
                    ? const Center(child: Text('No manual collected yet'))
                    : InteractiveViewer(
                        transformationController: _readingTransform,
                        minScale: 1,
                        maxScale: 5,
                        child: image(pages[page % pages.length]))
                : view == ResourceView.cartridge
                    ? widget.importedModels && format != null
                        ? SocketMediaRenderer(
                            key: rendererKey,
                            format: format!,
                            pose: SocketMediaPose(
                                rx: -math.pi / 2 + pitch,
                                ry: yaw,
                                scaleX: zoom,
                                scaleY: zoom,
                                scaleZ: zoom),
                            identity: widget.identity,
                            title: widget.title,
                            label: image(first('support-texture'),
                                umd: format == PhysicalMediaFormat.psp,
                                disc: format == PhysicalMediaFormat.disc ||
                                    format == PhysicalMediaFormat.psp,
                                fit: BoxFit.fill),
                            labelIdentity:
                                first('support-texture') ?? widget.identity)
                        : Transform(
                            key: const ValueKey('flat-medium-pose'),
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, .001)
                              ..rotateY(yaw)
                              ..rotateX(pitch)
                              ..scaleByDouble(zoom, zoom, zoom, 1),
                            child: MediaCoverFallback(
                                systemId: widget.systemId,
                                title: widget.title,
                                identity: widget.identity,
                                physicalLabel: first('support-texture') == null
                                    ? null
                                    : image(first('support-texture'))))
                    : SocketMediaRenderer.packaging(
                        key: rendererKey,
                        model: PackagingModel(kind, aspect: aspect),
                        pose: pose,
                        identity: widget.identity,
                        title: widget.title,
                        label: _atlas(),
                        labelIdentity: '${view.name}:${widget.resources}');
    return Focus(
        autofocus: true,
        onKeyEvent: _key,
        child: Container(
            decoration:
                const BoxDecoration(gradient: AppTheme.backgroundGradient),
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (final mode in availableViews)
                            Padding(
                                padding: const EdgeInsets.all(4),
                                child: ChoiceChip(
                                    key: ValueKey('resource-mode-${mode.name}'),
                                    showCheckmark: false,
                                    selectedColor: AppTheme.primaryColor
                                        .withValues(alpha: .24),
                                    backgroundColor: Colors.black26,
                                    side: BorderSide(
                                        color: view == mode
                                            ? AppTheme.primaryColor
                                            : Colors.white24),
                                    labelStyle: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        letterSpacing: .3,
                                        fontWeight: FontWeight.w600),
                                    selected: view == mode,
                                    onSelected: (_) => select(mode),
                                    avatar: Icon(switch (mode) {
                                      ResourceView.box =>
                                        Icons.inventory_2_outlined,
                                      ResourceView.cover =>
                                        Icons.album_outlined,
                                      ResourceView.cartridge =>
                                        Icons.sd_card_outlined,
                                      ResourceView.manual => Icons.menu_book,
                                      ResourceView.gallery =>
                                        Icons.perm_media_outlined
                                    }),
                                    label: Text(
                                        switch (mode) {
                                          ResourceView.cover => 'Case',
                                          ResourceView.gallery => 'Gallery',
                                          _ => mode.name[0].toUpperCase() +
                                              mode.name.substring(1)
                                        },
                                        softWrap: false,
                                        overflow: TextOverflow.visible)))
                        ]))),
                if (widget.onClose != null)
                  IconButton(
                      tooltip: 'Close',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close))
              ]),
              Expanded(
                  child: GestureDetector(
                      onScaleStart: reading || view == ResourceView.gallery
                          ? null
                          : (_) => _startZoom = zoom,
                      onScaleUpdate: reading || view == ResourceView.gallery
                          ? null
                          : (event) => setState(() {
                                yaw += event.focalPointDelta.dx * .012;
                                pitch += event.focalPointDelta.dy * .012;
                                zoom =
                                    (_startZoom * event.scale).clamp(.35, 1.5);
                              }),
                      child: content)),
              Wrap(alignment: WrapAlignment.center, children: [
                IconButton(
                    tooltip: 'Zoom out',
                    onPressed: () => changeZoom(-.1),
                    icon: const Icon(Icons.zoom_out)),
                IconButton(
                    tooltip: 'Reset view',
                    onPressed: () => setState(reset),
                    icon: const Icon(Icons.restart_alt)),
                IconButton(
                    tooltip: 'Zoom in',
                    onPressed: () => changeZoom(.1),
                    icon: const Icon(Icons.zoom_in)),
                if (canOpen)
                  IconButton(
                      tooltip: opening == 0 ? 'Open' : 'Close case',
                      onPressed: () =>
                          setState(() => opening = opening == 0 ? 1 : 0),
                      icon: const Icon(Icons.open_in_full)),
                if (view == ResourceView.manual && pages.isNotEmpty)
                  IconButton(
                      tooltip: reading ? '3D booklet' : 'Read manual',
                      onPressed: () => setState(() => reading = !reading),
                      icon: Icon(reading ? Icons.view_in_ar : Icons.menu_book)),
                if (view == ResourceView.gallery || reading) ...[
                  IconButton(
                      tooltip: 'Previous',
                      onPressed: () =>
                          setState(() => page = math.max(0, page - 1)),
                      icon: const Icon(Icons.chevron_left)),
                  IconButton(
                      tooltip: 'Next',
                      onPressed: () => setState(() => page++),
                      icon: const Icon(Icons.chevron_right))
                ],
                if (view == ResourceView.gallery &&
                    (first('video') ?? first('video-normalized')) != null)
                  IconButton(
                      tooltip: player?.value.isPlaying == true
                          ? 'Pause trailer'
                          : 'Play trailer',
                      onPressed: () => player == null
                          ? unawaited(play())
                          : unawaited(player.value.isPlaying
                              ? player.pause()
                              : player.play()),
                      icon: const Icon(Icons.play_circle_outline)),
              ]),
              if (_videoError != null) const Text('Trailer unavailable'),
              const Text(
                  'L1 / R1: section   •   Arrows: rotate / page   •   L2 / R2: zoom',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ])));
  }
}
