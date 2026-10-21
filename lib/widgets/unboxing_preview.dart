import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/unboxing_scene.dart';
import '../models/socket_media_model.dart';
import 'socket_media_renderer.dart';

String? boxPanelPath(Map<String, List<String>> resources, int index) =>
    resources['outer-box-${[
      'front',
      'back',
      'left',
      'right',
      'top',
      'bottom'
    ][index]}']
        ?.firstOrNull ??
    resources[index == 0
            ? 'box-2D'
            : index == 1
                ? 'box-2D-back'
                : 'box-2D-side']
        ?.firstOrNull;

String? bookletPanelPath(Map<String, List<String>> resources, int index) {
  final role = ['front', 'back', 'inside-left', 'inside-right'][index];
  final explicit = resources['booklet-$role']?.firstOrNull;
  if (explicit != null) return explicit;
  final pages = resources['manual-page'] ?? const <String>[];
  return switch (index) {
    0 => pages.firstOrNull,
    1 => pages.lastOrNull,
    2 when pages.length > 1 => pages[1],
    3 when pages.length > 2 => pages[2],
    _ => null,
  };
}

class UnboxingPreview extends StatefulWidget {
  final String identity, title, style;
  final Map<String, List<String>> resources;
  final Widget cartridgeLabel;
  final Object labelIdentity;
  final ImageProvider? waitingCover;
  final bool resourcesReady, reducedMotion;
  final VoidCallback? onReady, onRevealed;
  final VoidCallback? onReadManual;
  final ValueChanged<String?>? onInspectionChanged;
  final String? initialInspectionPart;
  final bool initiallySettled;
  const UnboxingPreview(
      {super.key,
      required this.identity,
      required this.title,
      required this.style,
      required this.resources,
      required this.cartridgeLabel,
      required this.labelIdentity,
      this.waitingCover,
      this.resourcesReady = true,
      this.reducedMotion = false,
      this.onReady,
      this.onRevealed,
      this.onReadManual,
      this.onInspectionChanged,
      this.initialInspectionPart,
      this.initiallySettled = false});
  @override
  State<UnboxingPreview> createState() => UnboxingPreviewState();
}

class UnboxingPreviewState extends State<UnboxingPreview>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _renderer = GlobalKey<SocketMediaRendererState>();
  late final _timeline =
      AnimationController(vsync: this, duration: UnboxingScene.duration);
  late final _inspection = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400));
  String? _prepared;
  int _generation = 0;
  bool _imagesReady = false,
      _gpuReady = false,
      _started = false,
      _visible = true;
  double _yaw = -.2, _pitch = .06, _zoom = 1, _startZoom = 1;
  Object? _error;
  Future<void> _preparation = Future.value();
  Future<void> get mediaPrepared => _preparation;
  String? _focusedPart;
  Offset? _doubleTapPosition;
  double _bookletAspect = 1.35;
  bool _returning = false;
  Map<String, Object?> get snapshot => {
        ...?_renderer.currentState?.snapshot,
        'cinematic': 'holder-tableau',
        'progress': _timeline.value,
        'imagesReady': _imagesReady,
        'started': _started,
        'completed': _timeline.isCompleted,
        'inspectedPart': _focusedPart,
        'inspection': _inspection.value,
        'inspectionStatus': _inspection.status.name,
        'returning': _returning,
        'zoom': _zoom,
        'error': _error?.toString(),
      };

  @override
  void initState() {
    super.initState();
    if (widget.initiallySettled) _timeline.value = 1;
    _focusedPart = widget.initialInspectionPart;
    if (_focusedPart != null) _inspection.value = 1;
    _inspection.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && _returning && mounted) {
        setState(() {
          _focusedPart = null;
          _returning = false;
          _zoom = 1;
          _yaw = -.2;
          _pitch = .06;
        });
        widget.onInspectionChanged?.call(null);
      }
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _preparation = _prepare();
  }

  @override
  void didUpdateWidget(UnboxingPreview old) {
    super.didUpdateWidget(old);
    if (old.identity != widget.identity) {
      _timeline.reset();
      _started = _gpuReady = false;
      _prepared = null;
      _focusedPart = null;
      _returning = false;
      _inspection.reset();
      _zoom = 1;
    }
    _preparation = _prepare();
    _start();
  }

  ImageProvider _provider(String path) {
    if (path.startsWith('file://'))
      return FileImage(File.fromUri(Uri.parse(path)));
    return NetworkImage(path);
  }

  Future<void> _prepare() async {
    _timeline.duration = UnboxingScene.durationFor(
        bookletPanelPath(widget.resources, 0) != null);
    final paths = [
      for (var i = 0; i < 6; i++) boxPanelPath(widget.resources, i),
      for (var i = 0; i < 4; i++) bookletPanelPath(widget.resources, i),
    ];
    final key = '${widget.identity}:$paths';
    if (key == _prepared) return;
    _prepared = key;
    final generation = ++_generation;
    _imagesReady = false;
    // A new panel set recaptures the GPU atlas (and may add the booklet mesh).
    // An earlier atlas's ready event cannot admit this scene's handoff.
    if (!_started) _gpuReady = false;
    _error = null;
    try {
      for (final path in paths.whereType<String>().toSet()) {
        final stream =
            _provider(path).resolve(createLocalImageConfiguration(context));
        final ready = Completer<Size>();
        final listener = ImageStreamListener((info, synchronous) {
          if (!ready.isCompleted)
            ready.complete(Size(
                info.image.width.toDouble(), info.image.height.toDouble()));
        }, onError: (Object error, StackTrace? stack) {
          if (!ready.isCompleted) ready.completeError(error, stack);
        });
        stream.addListener(listener);
        try {
          final size = await ready.future;
          if (path == bookletPanelPath(widget.resources, 0)) {
            _bookletAspect = size.aspectRatio.clamp(.25, 2.5);
          }
        } finally {
          stream.removeListener(listener);
        }
        if (!mounted || generation != _generation) return;
      }
      if (!mounted || generation != _generation) return;
      setState(() => _imagesReady = true);
      _start();
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    }
  }

  void _start() {
    if (!mounted ||
        _started ||
        !_visible ||
        !_imagesReady ||
        !_gpuReady ||
        !widget.resourcesReady) return;
    _started = true;
    widget.onReady?.call();
    final generation = _generation;
    if (widget.initiallySettled ||
        widget.reducedMotion ||
        MediaQuery.disableAnimationsOf(context)) {
      _timeline.value = 1;
      widget.onRevealed?.call();
    } else {
      _timeline.forward().then((_) {
        if (mounted && generation == _generation && _visible)
          widget.onRevealed?.call();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    if (!_visible) {
      _timeline.stop();
      _timeline.value = 1;
      _inspection.stop();
      if (_returning) {
        _returning = false;
        _focusedPart = null;
        _inspection.value = 0;
        widget.onInspectionChanged?.call(null);
      } else if (_focusedPart != null) {
        _inspection.value = 1;
      }
    } else {
      _start();
    }
  }

  Widget _face(String? path) => path == null
      ? const ColoredBox(color: Color(0xff24262a))
      : Image(image: _provider(path), fit: BoxFit.fill);

  void _focus(String part) {
    if (!_timeline.isCompleted || _returning) return;
    setState(() {
      _focusedPart = part;
      _zoom = 1;
      _yaw = -.2;
      _pitch = .06;
    });
    widget.onInspectionChanged?.call(part);
    if (widget.reducedMotion || MediaQuery.disableAnimationsOf(context)) {
      _inspection.value = 1;
    } else {
      _inspection.forward();
    }
  }

  void _overview() {
    if (_returning) return;
    setState(() => _returning = true);
    if (widget.reducedMotion || MediaQuery.disableAnimationsOf(context)) {
      _inspection.value = 0;
    } else {
      _inspection.reverse();
    }
  }

  Future<void> _read() async {
    if (!_timeline.isCompleted || bookletPanelPath(widget.resources, 0) == null)
      return;
    final part = _focusedPart ??
        (_doubleTapPosition == null
            ? null
            : _renderer.currentState?.partAt(_doubleTapPosition!));
    if (part == 'booklet') {
      final generation = _generation;
      _focus('booklet');
      try {
        await _inspection.forward().orCancel;
        if (mounted &&
            generation == _generation &&
            _visible &&
            _focusedPart == 'booklet' &&
            !_returning) {
          widget.onReadManual?.call();
        }
      } on TickerCanceled {
        // Selection, disposal or backgrounding owns cancellation.
      }
    }
  }

  Widget _preparationCover() {
    final path = boxPanelPath(widget.resources, 0);
    // The catalogue cover may be another English scan with different colour
    // grading. Once classified, keep the exact atlas front through the handoff.
    final image = path == null ? widget.waitingCover : _provider(path);
    return image == null
        ? const Center(child: CircularProgressIndicator())
        : LayoutBuilder(builder: (context, constraints) {
            final side = constraints.biggest.shortestSide * .75;
            return Center(
                child: SizedBox.square(
                    dimension: side,
                    child: Image(
                        key: const ValueKey('unboxing-preparation-cover'),
                        image: image,
                        gaplessPlayback: true,
                        fit: BoxFit.fill)));
          });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null)
      return const Center(child: Text('Box resources unavailable'));
    // Keep the preparation Image in the same element/layer while decoding and
    // mounting the scene. Replacing this whole tree briefly drops its frame.
    return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (event) {
          if (_focusedPart == null) {
            final part = _renderer.currentState?.partAt(event.localPosition);
            if (part != null) _focus(part);
          }
        },
        onDoubleTapDown: (event) => _doubleTapPosition = event.localPosition,
        onDoubleTap: _read,
        onScaleStart: (_) => _startZoom = _zoom,
        onScaleUpdate: (event) {
          if (_timeline.isCompleted && _focusedPart != null && !_returning) {
            if (_startZoom * event.scale < .60) {
              _overview();
              return;
            }
            setState(() {
              _yaw += event.focalPointDelta.dx * .012;
              _pitch += event.focalPointDelta.dy * .012;
              _zoom = (_startZoom * event.scale).clamp(.6, 1.8);
            });
          }
        },
        child: AnimatedBuilder(
            animation: Listenable.merge([_timeline, _inspection]),
            builder: (context, _) => Stack(fit: StackFit.expand, children: [
                  if (_imagesReady && widget.resources.isNotEmpty)
                    SocketMediaRenderer.unboxing(
                      key: _renderer,
                      compositionZoom: _returning
                          ? 1 + (_zoom - 1) * _inspection.value
                          : _zoom,
                      scene: UnboxingScene(widget.style,
                          hasBooklet:
                              bookletPanelPath(widget.resources, 0) != null,
                          bookletAspect: _bookletAspect),
                      identity: widget.identity,
                      title: widget.title,
                      pose: SocketMediaPose(
                          rx: _returning
                              ? .06 + (_pitch - .06) * _inspection.value
                              : _pitch,
                          ry: _returning
                              ? -.2 + (_yaw + .2) * _inspection.value
                              : _yaw,
                          scaleX: _returning
                              ? 1 + (_zoom - 1) * _inspection.value
                              : _zoom,
                          scaleY: _returning
                              ? 1 + (_zoom - 1) * _inspection.value
                              : _zoom,
                          scaleZ: _returning
                              ? 1 + (_zoom - 1) * _inspection.value
                              : _zoom,
                          opening: UnboxingScene.opening(_timeline.value,
                              hasBooklet:
                                  bookletPanelPath(widget.resources, 0) !=
                                      null),
                          unboxing: _timeline.value,
                          inspectedPart: _focusedPart,
                          inspection:
                              Curves.easeInOut.transform(_inspection.value)),
                      labelIdentity:
                          '${widget.labelIdentity}:${widget.resources}',
                      onReady: () {
                        _gpuReady = true;
                        _start();
                      },
                      label: Column(children: [
                        for (var row = 0; row < 4; row++)
                          Expanded(
                              child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                for (var col = 0; col < 3; col++)
                                  Expanded(
                                      child: row < 2
                                          ? _face(boxPanelPath(
                                              widget.resources, row * 3 + col))
                                          : row == 2 && col == 0
                                              ? widget.cartridgeLabel
                                              : row * 3 + col < 11
                                                  ? _face(bookletPanelPath(
                                                      widget.resources,
                                                      row * 3 + col - 7))
                                                  : const SizedBox())
                              ]))
                      ]),
                    )
                  else
                    const SizedBox.expand(),
                  KeyedSubtree(
                      key: ValueKey(widget.identity),
                      child: IgnorePointer(
                          child: Opacity(
                              opacity: _started
                                  ? 1 -
                                      UnboxingScene.phase(
                                          _timeline.value *
                                              _timeline
                                                  .duration!.inMilliseconds,
                                          0,
                                          180)
                                  : 1,
                              child: _preparationCover()))),
                ])));
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _timeline.dispose();
    _inspection.dispose();
    super.dispose();
  }
}
