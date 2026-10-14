import 'dart:async';

import 'package:flutter/material.dart';
import '../models/socket_media_model.dart';
import 'socket_media_renderer.dart';
export 'handwritten_media_sticker.dart';
export '../models/socket_media_model.dart' show PhysicalMediaFormat;

/// One selected source model. The existing insertion/launch lifecycle stays
/// owned here; the renderer does not introduce another game-launch pipeline.
class PhysicalMediaView extends StatefulWidget {
  final String identity, title;
  final Widget label;
  final bool reducedMotion;
  final PhysicalMediaFormat format;
  const PhysicalMediaView(
      {super.key,
      required this.identity,
      required this.title,
      required this.label,
      this.reducedMotion = false,
      this.format = PhysicalMediaFormat.gameBoy});
  @override
  State<PhysicalMediaView> createState() => PhysicalMediaViewState();
}

class PhysicalMediaViewState extends State<PhysicalMediaView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _rendererKey = GlobalKey<SocketMediaRendererState>();
  late final _selection = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));
  late final _idle = AnimationController(
      vsync: this, duration: const Duration(microseconds: 62831853));
  late final _insertion = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.format.insertionMilliseconds));
  Completer<bool>? _completion;
  double _manualRotation = 0;
  bool get _reduce =>
      widget.reducedMotion || MediaQuery.disableAnimationsOf(context);
  Map<String, Object?> get renderSnapshot =>
      _rendererKey.currentState?.snapshot ??
      {
        'model': widget.format.assetName,
        'identity': widget.identity,
        'frameRendered': false
      };
  Future<Map<String, Object?>> get renderReady =>
      _rendererKey.currentState!.ready;
  SocketMediaPose get pose => SocketMediaPose.sample(
      kind: widget.format == PhysicalMediaFormat.disc
          ? 'disc'
          : widget.format == PhysicalMediaFormat.psp
              ? 'umd'
              : {
                  PhysicalMediaFormat.gba,
                  PhysicalMediaFormat.n64,
                  PhysicalMediaFormat.snesPal,
                  PhysicalMediaFormat.snesUs
                }.contains(widget.format)
                  ? 'drop'
                  : 'pushClick',
      selected: _selection.value,
      seconds: _idle.value * 62.831853,
      insertion: _insertion.value * widget.format.insertionMilliseconds / 1000,
      manualRotation: _manualRotation,
      reducedMotion: _reduce);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _insertion.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish(true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configureMotion();
  }

  @override
  void didUpdateWidget(PhysicalMediaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.format != widget.format) {
      _finish(false);
      _insertion.reset();
      _manualRotation = 0;
      _selection.reset();
      _insertion.duration =
          Duration(milliseconds: widget.format.insertionMilliseconds);
    }
    _configureMotion();
  }

  void _configureMotion() {
    if (_reduce) {
      _idle.stop();
      _selection.value = 1;
      if (_completion != null) skipInsertion();
    } else {
      if (!_idle.isAnimating) _idle.repeat();
      if (!_selection.isCompleted) _selection.forward();
    }
  }

  Future<bool> playInsertion() {
    if (_completion case final pending?) return pending.future;
    if (_reduce) return Future.value(true);
    final pending = Completer<bool>();
    _completion = pending;
    _insertion.forward(from: 0);
    setState(() {});
    return pending.future;
  }

  void skipInsertion() {
    if (_completion != null) _insertion.value = 1;
  }

  void resetInsertion() {
    _finish(false);
    _insertion.reset();
  }

  void _finish(bool result) {
    final pending = _completion;
    _completion = null;
    if (pending != null && !pending.isCompleted) pending.complete(result);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _finish(false);
      _insertion.stop();
      _idle.stop();
    } else {
      if (_insertion.isCompleted) resetInsertion();
      _configureMotion();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finish(false);
    _selection.dispose();
    _idle.dispose();
    _insertion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
      label: '3D ${widget.format.description}: ${widget.title}',
      child: AnimatedBuilder(
          animation: Listenable.merge([_selection, _idle, _insertion]),
          builder: (context, _) => Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    GestureDetector(
                        onHorizontalDragUpdate: (event) {
                          if (_completion == null) {
                            setState(
                                () => _manualRotation += event.delta.dx * .012);
                          }
                        },
                        child: SocketMediaRenderer(
                            key: _rendererKey,
                            format: widget.format,
                            pose: pose,
                            identity: widget.identity,
                            title: widget.title,
                            label: widget.label)),
                    if (_completion != null)
                      Positioned(
                          right: 8,
                          bottom: 8,
                          child: IconButton.filled(
                              key: const ValueKey('physical-media-skip'),
                              tooltip: 'Skip animation',
                              onPressed: skipInsertion,
                              icon: const Icon(Icons.skip_next_rounded))),
                  ])));
}
