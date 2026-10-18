import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:convert';
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
  double yaw = -.2,
      pitch = .06,
      zoom = .75,
      opening = 0,
      aspect = .72,
      depth = .14;
  double _startZoom = .75;
  int page = 0, _generation = 0;
  bool reading = false, _trailerSelected = false, _videoLoading = false;
  VideoPlayerController? _video;
  ImageStream? _coverStream;
  ImageStreamListener? _coverListener;
  ImageStream? _spineStream;
  ImageStreamListener? _spineListener;
  Color _paperColor = const Color(0xff343434);
  Object? _videoError;
  String? first(String type) => widget.resources[type]?.firstOrNull;
  List<String> get images => [
        ...?widget.resources['ss'],
        ...?widget.resources['screenshot'],
        ...?widget.resources['fanart'],
        ...?widget.resources['flyer'],
        ...?widget.resources['maps'],
      ].toSet().toList();
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
      if (physical && !{'gameandwatch', 'gba'}.contains(widget.systemId))
        ResourceView.cover,
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
        'depth': depth,
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
    } else if (old.resources.toString() != widget.resources.toString()) {
      _resolveAspect();
    }
  }

  String? _aspectUrl;
  void _resolveAspect() {
    final url = view == ResourceView.manual
        ? pages.firstOrNull
        : view == ResourceView.box
            ? first('outer-box-front') ?? first('box-2D')
            : first('box-2D');
    final spine = _face(2);
    final key = '${view.name}:$url:$spine';
    if (key == _aspectUrl) return;
    _detachCover();
    _detachSpine();
    _aspectUrl = key;
    aspect = .72;
    depth = view == ResourceView.manual
        ? .025
        : view == ResourceView.box &&
                {'gba', 'gb', 'gbc'}.contains(widget.systemId)
            ? .34
            : .14;
    if (url == null) return;
    final provider = _provider(url);
    _coverStream = provider.resolve(createLocalImageConfiguration(context));
    _coverListener = ImageStreamListener((info, sync) {
      if (mounted && _aspectUrl == key) {
        final ratio = info.image.width / info.image.height;
        void apply() {
          aspect = ratio.clamp(.25, 2.5);
        }

        unawaited(_paperMaterial(info.image.clone(), key));

        if (sync) {
          apply();
        } else {
          setState(apply);
        }
      }
      _detachCover();
    }, onError: (_, __) => _detachCover());
    _coverStream!.addListener(_coverListener!);
    if (spine != null && view != ResourceView.manual) {
      _spineStream =
          _provider(spine).resolve(createLocalImageConfiguration(context));
      _spineListener = ImageStreamListener((info, sync) {
        if (mounted && _aspectUrl == key) {
          void apply() => depth =
              (2 * info.image.width / info.image.height).clamp(.04, 1.0);
          if (sync) {
            apply();
          } else {
            setState(apply);
          }
        }
        _detachSpine();
      }, onError: (_, __) => _detachSpine());
      _spineStream!.addListener(_spineListener!);
    }
  }

  Future<void> _paperMaterial(ui.Image image, String key) async {
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null || !mounted || _aspectUrl != key) return;
      var red = 0, green = 0, blue = 0, count = 0;
      for (final x in [0, image.width ~/ 2, image.width - 1]) {
        for (final y in [0, image.height - 1]) {
          final i = (y * image.width + x) * 4;
          red += bytes.getUint8(i);
          green += bytes.getUint8(i + 1);
          blue += bytes.getUint8(i + 2);
          count++;
        }
      }
      setState(() => _paperColor =
          Color.fromARGB(255, red ~/ count, green ~/ count, blue ~/ count));
    } finally {
      image.dispose();
    }
  }

  void _detachSpine() {
    if (_spineListener != null) _spineStream?.removeListener(_spineListener!);
    _spineStream = null;
    _spineListener = null;
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
    _trailerSelected = false;
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
    _videoLoading = false;
    final old = _video;
    _video = null;
    old?.removeListener(_playing);
    widget.onPlayingChanged?.call(false);
    await old?.dispose();
  }

  Future<void> play() async {
    final path = first('video') ?? first('video-normalized');
    if (path == null || _video != null || _videoLoading) return;
    final generation = ++_generation;
    setState(() {
      _trailerSelected = true;
      _videoLoading = true;
    });
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
    } finally {
      if (mounted && generation == _generation)
        setState(() => _videoLoading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_stopVideo());
  }

  @override
  void dispose() {
    _detachSpine();
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
      unawaited(_stopVideo());
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

  String? _face(int index) {
    if (view == ResourceView.manual)
      return index == 0
          ? pages.firstOrNull
          : index == 1 && pages.length > 1
              ? pages.last
              : null;
    if (view == ResourceView.box) {
      final role = ['front', 'back', 'left', 'right', 'top', 'bottom'][index];
      final outer = first('outer-box-$role');
      if (outer != null) return outer;
      if (index >= 2) return first('box-2D-side');
    }
    return switch (index) {
      0 => first('box-2D'),
      1 => first('box-2D-back'),
      2 => first('box-2D-side'),
      _ => null
    };
  }

  Widget _atlas() => Column(children: [
        for (var row = 0; row < 2; row++)
          Expanded(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                for (var col = 0; col < 3; col++)
                  Expanded(
                      child: SizedBox.expand(
                          child: ColoredBox(
                              color: view == ResourceView.box
                                  ? _paperColor
                                  : const Color(0xff252525),
                              child: _face(row * 3 + col) != null ||
                                      row == 0 && col == 0
                                  ? RotatedBox(
                                      quarterTurns: view == ResourceView.box &&
                                              row * 3 + col >= 4 &&
                                              first('outer-box-${row * 3 + col == 4 ? 'top' : 'bottom'}') ==
                                                  null
                                          ? 1
                                          : 0,
                                      child: image(_face(row * 3 + col),
                                          fit: BoxFit.fill))
                                  : const SizedBox.expand())))
              ]))
      ]);
  void _rendered() {
    // Bounded transition evidence, not a frame-by-frame UI stream. No URLs,
    // titles, account data or tokens are logged.
    debugPrint('RShopResources ${jsonEncode({
          'identity': widget.identity,
          'system': widget.systemId,
          'view': view.name,
          'aspect': aspect,
          'depth': depth,
          'roles': {
            for (final entry in widget.resources.entries)
              entry.key: entry.value.length
          },
          'model': rendererKey.currentState?.snapshot,
        })}');
  }

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
        ? _trailerSelected
            ? player != null && player.value.isInitialized
                ? AspectRatio(
                    aspectRatio: player.value.aspectRatio,
                    child: VideoPlayer(player))
                : Center(
                    child: _videoLoading
                        ? const CircularProgressIndicator()
                        : const Text('Select Play to watch the trailer'))
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
                            onReady: _rendered,
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
                        model: PackagingModel(kind,
                            aspect: aspect,
                            depth: depth,
                            systemId: widget.systemId),
                        pose: pose,
                        identity: widget.identity,
                        title: widget.title,
                        onReady: _rendered,
                        label: _atlas(),
                        labelIdentity:
                            '${view.name}:${widget.resources}:${_paperColor.toARGB32()}');
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
              if (view == ResourceView.gallery)
                Wrap(spacing: 8, children: [
                  ChoiceChip(
                      label: Text('Images (${images.length})'),
                      avatar: const Icon(Icons.photo_library_outlined),
                      selected: !_trailerSelected,
                      onSelected: (_) {
                        unawaited(_stopVideo());
                        setState(() => _trailerSelected = false);
                      }),
                  if ((first('video') ?? first('video-normalized')) != null)
                    ChoiceChip(
                        key: const ValueKey('gallery-trailer'),
                        label: const Text('Trailer'),
                        avatar: const Icon(Icons.movie_outlined),
                        selected: _trailerSelected,
                        onSelected: (_) => unawaited(play())),
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
                    onPressed: () {
                      unawaited(_stopVideo());
                      setState(reset);
                    },
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
