import 'dart:io';
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

class UnboxingPreview extends StatefulWidget {
  final String identity, title, style;
  final Map<String, List<String>> resources;
  final Widget cartridgeLabel;
  final Object labelIdentity;
  final bool resourcesReady, reducedMotion;
  final VoidCallback? onReady, onRevealed;
  const UnboxingPreview(
      {super.key,
      required this.identity,
      required this.title,
      required this.style,
      required this.resources,
      required this.cartridgeLabel,
      required this.labelIdentity,
      this.resourcesReady = true,
      this.reducedMotion = false,
      this.onReady,
      this.onRevealed});
  @override
  State<UnboxingPreview> createState() => UnboxingPreviewState();
}

class UnboxingPreviewState extends State<UnboxingPreview>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _renderer = GlobalKey<SocketMediaRendererState>();
  late final _timeline =
      AnimationController(vsync: this, duration: UnboxingScene.duration);
  String? _prepared;
  int _generation = 0;
  bool _imagesReady = false,
      _gpuReady = false,
      _started = false,
      _visible = true;
  double _yaw = -.2, _pitch = .06, _zoom = 1, _startZoom = 1;
  Object? _error;
  Map<String, Object?> get snapshot => {
        ...?_renderer.currentState?.snapshot,
        'cinematic': 'holder-extraction',
        'progress': _timeline.value,
        'imagesReady': _imagesReady,
        'started': _started,
        'completed': _timeline.isCompleted,
        'error': _error?.toString(),
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prepare();
  }

  @override
  void didUpdateWidget(UnboxingPreview old) {
    super.didUpdateWidget(old);
    if (old.identity != widget.identity) {
      _timeline.reset();
      _started = _gpuReady = false;
      _prepared = null;
    }
    _prepare();
    _start();
  }

  ImageProvider _provider(String path) {
    if (path.startsWith('file://'))
      return FileImage(File.fromUri(Uri.parse(path)));
    return NetworkImage(path);
  }

  Future<void> _prepare() async {
    final paths = [
      for (var i = 0; i < 6; i++) boxPanelPath(widget.resources, i)
    ];
    final key = '${widget.identity}:$paths';
    if (key == _prepared) return;
    _prepared = key;
    final generation = ++_generation;
    _imagesReady = false;
    _error = null;
    try {
      for (final path in paths.whereType<String>().toSet()) {
        Object? failure;
        await precacheImage(_provider(path), context,
            onError: (e, _) => failure = e);
        if (failure != null) throw failure!;
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
    if (widget.reducedMotion || MediaQuery.disableAnimationsOf(context)) {
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
    } else {
      _start();
    }
  }

  Widget _face(String? path) => path == null
      ? const ColoredBox(color: Color(0xff24262a))
      : Image(image: _provider(path), fit: BoxFit.fill);
  @override
  Widget build(BuildContext context) {
    if (_error != null)
      return const Center(child: Text('Box resources unavailable'));
    if (!_imagesReady) return const Center(child: CircularProgressIndicator());
    return GestureDetector(
        onScaleStart: (_) => _startZoom = _zoom,
        onScaleUpdate: (event) {
          if (_timeline.isCompleted)
            setState(() {
              _yaw += event.focalPointDelta.dx * .012;
              _pitch += event.focalPointDelta.dy * .012;
              _zoom = (_startZoom * event.scale).clamp(.5, 1.8);
            });
        },
        child: AnimatedBuilder(
            animation: _timeline,
            builder: (context, _) => SocketMediaRenderer.unboxing(
                  key: _renderer,
                  scene: UnboxingScene(widget.style),
                  identity: widget.identity,
                  title: widget.title,
                  pose: SocketMediaPose(
                      rx: _pitch,
                      ry: _yaw,
                      scaleX: _zoom,
                      scaleY: _zoom,
                      scaleZ: _zoom,
                      opening: UnboxingScene.opening(_timeline.value),
                      unboxing: _timeline.value),
                  labelIdentity: '${widget.labelIdentity}:${widget.resources}',
                  onReady: () {
                    _gpuReady = true;
                    _start();
                  },
                  label: Column(children: [
                    for (var row = 0; row < 3; row++)
                      Expanded(
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                            for (var col = 0; col < 3; col++)
                              Expanded(
                                  child: row < 2
                                      ? _face(boxPanelPath(
                                          widget.resources, row * 3 + col))
                                      : col == 0
                                          ? widget.cartridgeLabel
                                          : const SizedBox())
                          ]))
                  ]),
                )));
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _timeline.dispose();
    super.dispose();
  }
}
