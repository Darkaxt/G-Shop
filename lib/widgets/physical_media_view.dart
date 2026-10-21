import 'dart:async';
import 'dart:convert';

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
  final Object? labelIdentity;
  final VoidCallback? onReady;
  final bool reducedMotion;
  final PhysicalMediaFormat format;
  final String? cartridgeStyle;
  final bool inspectInside;
  const PhysicalMediaView(
      {super.key,
      required this.identity,
      required this.title,
      required this.label,
      this.labelIdentity,
      this.onReady,
      this.cartridgeStyle,
      this.inspectInside = false,
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
  late final _inspection = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1350));
  late final _insertion = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.format.insertionMilliseconds));
  Completer<bool>? _completion;
  bool _resumed = true;
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
      opening: _inspection.value,
      reducedMotion: _reduce);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _insertion.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish(true);
    });
    _inspection.addStatusListener((status) {
      if (widget.format == PhysicalMediaFormat.nes &&
          (status == AnimationStatus.completed ||
              status == AnimationStatus.dismissed)) {
        debugPrint('GShopNesAssemblyMotion ${jsonEncode({
              'identity': widget.identity,
              'progress': _inspection.value,
              'motionCompleted': true
            })}');
      }
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
      _inspection.value = 0;
      _insertion.duration =
          Duration(milliseconds: widget.format.insertionMilliseconds);
    }
    _configureMotion();
  }

  void _configureMotion() {
    if (!_resumed) return;
    if (_reduce) {
      _inspection.value = widget.inspectInside ? 1 : 0;
    } else if (widget.inspectInside) {
      if (!_inspection.isCompleted &&
          (!_inspection.isAnimating ||
              _inspection.status != AnimationStatus.forward))
        _inspection.forward();
    } else if (!_inspection.isDismissed &&
        (!_inspection.isAnimating ||
            _inspection.status != AnimationStatus.reverse)) {
      _inspection.reverse();
    }
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
    _inspection.value = 0;
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
    _resumed = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) {
      _finish(false);
      _insertion.stop();
      _idle.stop();
      _inspection.stop();
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
    _inspection.dispose();
    _insertion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
      label: '3D ${widget.format.description}: ${widget.title}',
      child: AnimatedBuilder(
          animation:
              Listenable.merge([_selection, _idle, _insertion, _inspection]),
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
                            cartridgeStyle: widget.cartridgeStyle,
                            pose: pose,
                            identity: widget.identity,
                            title: widget.title,
                            label: widget.label,
                            labelIdentity: widget.labelIdentity,
                            onReady: widget.onReady)),
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
