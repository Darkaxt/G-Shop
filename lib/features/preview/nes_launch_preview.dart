import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/nes_launch_scene.dart';
import '../../models/scene_launch_presentation.dart';
import '../../models/socket_media_model.dart';
import '../../widgets/socket_media_renderer.dart';
import '../../core/theme/app_theme.dart';

/// Rendering only. The main engine still owns ROM checks, saves and handoff.
class NesLaunchPreview extends StatefulWidget {
  final int token;
  final NesLaunchScene scene;
  final SocketMediaPose initialPose;
  final SceneLaunchPhase phase;
  final Widget label;
  final Object? labelIdentity;
  final String title;
  final bool skip, reducedMotion;
  final ValueChanged<bool> onPrepared;
  final VoidCallback onFinished, onCancel, onSkip;
  const NesLaunchPreview(
      {super.key,
      required this.token,
      required this.scene,
      required this.initialPose,
      required this.phase,
      required this.label,
      required this.title,
      required this.onPrepared,
      required this.onFinished,
      required this.onCancel,
      required this.onSkip,
      this.labelIdentity,
      this.skip = false,
      this.reducedMotion = false});
  @override
  State<NesLaunchPreview> createState() => _NesLaunchPreviewState();
}

class _NesLaunchPreviewState extends State<NesLaunchPreview>
    with SingleTickerProviderStateMixin {
  final _renderer = GlobalKey<SocketMediaRendererState>();
  late final double _remaining = widget.scene.media.durationMs *
      (1 - widget.initialPose.unboxing).clamp(0.0, 1.0);
  late final _timeline = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_remaining + 5500).round()));
  bool _ready = false, _completing = false;

  @override
  void initState() {
    super.initState();
    _timeline.addStatusListener((state) {
      if (state == AnimationStatus.completed) unawaited(_finish());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_prepare()));
  }

  Future<void> _prepare() async {
    final renderer = _renderer.currentState;
    if (!mounted || renderer == null) return;
    final snapshot = await renderer.ready;
    if (!mounted) return;
    setState(() => _ready =
        snapshot['error'] == null && snapshot['frameRendered'] == true);
    widget.onPrepared(_ready);
    if (_ready) _start();
  }

  @override
  void didUpdateWidget(NesLaunchPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token ||
        oldWidget.scene.identity != widget.scene.identity) {
      throw StateError('Replace the keyed launch view for another attempt');
    }
    _start();
  }

  void _start() {
    if (!_ready || widget.phase != SceneLaunchPhase.animating) return;
    if (widget.skip ||
        widget.reducedMotion ||
        MediaQuery.disableAnimationsOf(context)) {
      _timeline.value = 1;
    } else if (!_timeline.isAnimating && !_timeline.isCompleted) {
      _timeline.forward();
    }
  }

  Future<void> _finish() async {
    if (_completing) return;
    _completing = true;
    // Controller completion schedules a new pose. Await its actual GPU image,
    // rather than authorizing native launch from an elapsed animation duration.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final renderer = _renderer.currentState;
    if (renderer == null) return;
    final snapshot = await renderer.currentFrameReady;
    if (!mounted || widget.phase != SceneLaunchPhase.animating) return;
    if (snapshot['error'] != null ||
        snapshot['frameRendered'] != true ||
        snapshot['launch'] != 1) {
      widget.onPrepared(false);
      return;
    }
    widget.onFinished();
  }

  SocketMediaPose get _pose {
    final elapsed = _timeline.value * (_remaining + 5500);
    final unboxing = _remaining == 0
        ? 1.0
        : widget.initialPose.unboxing +
            (1 - widget.initialPose.unboxing) *
                (elapsed / _remaining).clamp(0.0, 1.0);
    final launch = ((elapsed - _remaining) / 5500).clamp(0.0, 1.0);
    return SocketMediaPose(
        rx: widget.initialPose.rx,
        ry: widget.initialPose.ry,
        rz: widget.initialPose.rz,
        y: widget.initialPose.y,
        z: widget.initialPose.z,
        opening: widget.initialPose.opening,
        unboxing: unboxing,
        launch: launch,
        inspectedPart: widget.initialPose.inspectedPart);
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        if (_ready)
          const DecoratedBox(
              decoration: BoxDecoration(gradient: AppTheme.backgroundGradient)),
        AnimatedBuilder(
            animation: _timeline,
            builder: (context, _) => SocketMediaRenderer(
                key: _renderer,
                frameComposition: true,
                format: PhysicalMediaFormat.nes,
                nesLaunchScene: widget.scene,
                identity: 'launch:${widget.token}',
                title: widget.title,
                pose: _pose,
                label: widget.label,
                labelIdentity: widget.labelIdentity)),
        Positioned(
            right: 16,
            bottom: 16,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton.filledTonal(
                  tooltip: 'Cancel launch',
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.close)),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                  tooltip: 'Skip launch animation',
                  onPressed: widget.onSkip,
                  icon: const Icon(Icons.skip_next)),
            ])),
      ]);

  @override
  void dispose() {
    _timeline.dispose();
    super.dispose();
  }
}
