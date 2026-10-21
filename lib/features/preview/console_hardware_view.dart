import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/console_model.dart';
import '../../models/game_watch_unboxing_scene.dart';
import '../../models/socket_media_model.dart';
import '../../widgets/socket_media_renderer.dart';
import 'scene_preview_layout.dart';

class ConsoleHardwareView extends StatefulWidget {
  final ConsoleModel model;
  final String title;
  String get systemId => model.systemId;
  String get generation => model.generation;
  final bool reducedMotion;
  final bool showTitle;
  final bool turntable, transparentBackground;
  final bool informationRotation;
  final double stagingYaw, stagingScale, compositionFill;
  final VoidCallback? onInspect;
  final VoidCallback? onReady;
  final GameWatchUnboxingScene? unboxingScene;
  final double unboxingProgress;
  final double? sequenceOpening;
  final bool inspecting;
  final VoidCallback? onInteraction;
  const ConsoleHardwareView(
      {super.key,
      required this.model,
      required this.title,
      this.showTitle = true,
      this.turntable = true,
      this.informationRotation = false,
      this.stagingYaw = 0,
      this.stagingScale = 1,
      this.compositionFill = .75,
      this.onInspect,
      this.transparentBackground = false,
      this.reducedMotion = false,
      this.onReady,
      this.unboxingScene,
      this.unboxingProgress = 1,
      this.sequenceOpening,
      this.inspecting = false,
      this.onInteraction});
  @override
  State<ConsoleHardwareView> createState() => ConsoleHardwareViewState();
}

class ConsoleHardwareViewState extends State<ConsoleHardwareView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const rotationPeriod = Duration(seconds: 40);
  static const informationRotationPeriod = Duration(seconds: 120);
  static const defaultPitch = .18;
  final rendererKey = GlobalKey<SocketMediaRendererState>();
  late final AnimationController _rotation;
  late final AnimationController _opening;
  bool _resumed = true, _hasFrame = false;
  Timer? _idle;
  double? _inspectionYaw;
  int _pointers = 0;
  double _yaw = -.2, _pitch = defaultPitch, _zoom = .9, _startZoom = .9;
  double get _initialPitch => widget.model.isCollectionOverview
      ? .85
      : widget.systemId == 'nes' && !widget.model.isBox
          ? .60
          : defaultPitch;
  double get _motionYaw => widget.informationRotation || widget.turntable
      ? _rotation.value * math.pi * 2
      : math.sin(_rotation.value * math.pi * 2) * .14;
  Map<String, Object?> get snapshot => {
        ...?rendererKey.currentState?.snapshot,
        'system': widget.systemId,
        'consoleGeneration': widget.generation,
        'rotationPeriodMs': _rotation.duration!.inMilliseconds,
        'motion': widget.informationRotation
            ? 'informationTurntable'
            : widget.turntable
                ? 'turntable'
                : 'wobble',
        'rotationRunning': _rotation.isAnimating,
        'informationRotation': widget.informationRotation,
        'stagingYaw': widget.stagingYaw,
        'stagingScale': widget.stagingScale,
        'manualYaw': _yaw,
        'manualPitch': _pitch,
        'manualZoom': _zoom,
        'reducedMotion': widget.reducedMotion,
        'interaction': 'gestures',
        'resumeAfterIdleMs': 5000,
        'opening': widget.sequenceOpening ?? _opening.value,
        'unboxingProgress': widget.unboxingProgress,
        'sequenceControlled': widget.sequenceOpening != null,
        'canOpen': widget.model.canOpen,
        'romSet': widget.model.romSet,
        if (widget.model.visualVariantId != null)
          'visualVariantId': widget.model.visualVariantId,
      };
  Future<Map<String, Object?>> get renderReady async {
    await rendererKey.currentState?.ready;
    return snapshot;
  }

  @override
  void initState() {
    super.initState();
    _pitch = _initialPitch;
    _rotation = AnimationController(
        vsync: this,
        duration: widget.informationRotation
            ? informationRotationPeriod
            : widget.turntable
                ? rotationPeriod
                : const Duration(seconds: 8));
    if (widget.informationRotation) _inspectionYaw = _yaw;
    _opening = AnimationController(
        vsync: this,
        value: widget.model.canOpen ? 1 : 0,
        duration: Duration(milliseconds: widget.model.openingDurationMs));
    WidgetsBinding.instance.addObserver(this);
  }

  void _updateMotion() {
    if (_hasFrame &&
        _resumed &&
        !widget.reducedMotion &&
        widget.sequenceOpening == null &&
        (widget.informationRotation || (_pointers == 0 && _idle == null))) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.stop();
    }
  }

  void _touchDown(PointerDownEvent event) {
    widget.onInteraction?.call();
    _idle?.cancel();
    _idle = null;
    if (_pointers++ == 0) {
      _yaw += _motionYaw;
      _rotation.stop();
      _rotation.value = 0;
    }
  }

  void _touchUp(PointerEvent event) {
    if (_pointers > 0) _pointers--;
    if (_pointers != 0) return;
    _idle?.cancel();
    // Owner-requested presentation behavior, never operation synchronization.
    _idle = Timer(const Duration(seconds: 5), () {
      _idle = null;
      if (mounted) _updateMotion();
    });
  }

  void _ready() {
    _hasFrame = true;
    _updateMotion();
    _reportInformationMotion();
    // Keep the readiness/motion receipt within Android's log message boundary.
    // The full snapshot still travels through the structured preview bridge.
    debugPrint('GShopConsoleMotion ${jsonEncode({
          'system': widget.systemId,
          'geometrySha256': snapshot['geometrySha256'],
          'generation': widget.generation,
          'frameRendered': snapshot['frameRendered'],
          'motion': snapshot['motion'],
          'rotationRunning': _rotation.isAnimating,
          'periodMs': _rotation.duration!.inMilliseconds,
          'reducedMotion': widget.reducedMotion,
        })}');
    debugPrint('GShopConsolePreview ${jsonEncode(snapshot)}');
    widget.onReady?.call();
  }

  void _reportInformationMotion() {
    if (!widget.informationRotation) return;
    debugPrint('GShopGameWatchInformationMotion ${jsonEncode({
          'hardware': widget.model.hardwareId,
          'foreground': _resumed,
          'running': _rotation.isAnimating,
          'periodMs': _rotation.duration!.inMilliseconds,
          'reducedMotion': widget.reducedMotion,
        })}');
  }

  @override
  void didUpdateWidget(ConsoleHardwareView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.informationRotation != widget.informationRotation) {
      _idle?.cancel();
      _idle = null;
      _rotation.stop();
      if (widget.informationRotation) {
        _inspectionYaw = _yaw;
        if (!oldWidget.reducedMotion) {
          _yaw += oldWidget.turntable
              ? _rotation.value * math.pi * 2
              : math.sin(_rotation.value * math.pi * 2) * .14;
        }
      } else {
        _yaw = _inspectionYaw ?? _yaw;
        _inspectionYaw = null;
      }
      _rotation.value = 0;
      _rotation.duration = widget.informationRotation
          ? informationRotationPeriod
          : widget.turntable
              ? rotationPeriod
              : const Duration(seconds: 8);
    }
    if (oldWidget.systemId != widget.systemId ||
        oldWidget.generation != widget.generation) {
      _idle?.cancel();
      _idle = null;
      _pointers = 0;
      _rotation.stop();
      _rotation.value = 0;
      _yaw = -.2;
      _pitch = _initialPitch;
      _zoom = .9;
      _hasFrame = false;
      _opening.stop();
      _opening.value = widget.model.canOpen ? 1 : 0;
      _opening.duration =
          Duration(milliseconds: widget.model.openingDurationMs);
    }
    if (!oldWidget.reducedMotion && widget.reducedMotion) {
      _yaw += _motionYaw;
      _rotation.stop();
      _rotation.value = 0;
    }
    _updateMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (!_resumed) {
      _idle?.cancel();
      _idle = null;
      _pointers = 0;
      _opening.stop();
    }
    _updateMotion();
    _reportInformationMotion();
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: widget.transparentBackground
            ? null
            : const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
            child: ScenePreviewLayout(
          composition: true,
          header: widget.showTitle
              ? Text(widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w600))
              : null,
          content: AnimatedBuilder(
              animation: Listenable.merge([_rotation, _opening]),
              builder: (_, __) => Listener(
                  key: const ValueKey('console-model-gestures'),
                  onPointerDown: _touchDown,
                  onPointerUp: _touchUp,
                  onPointerCancel: _touchUp,
                  child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onInspect,
                      onDoubleTap: widget.model.canOpen
                          ? () {
                              if (_opening.value < .5) {
                                _opening.forward();
                              } else {
                                _opening.reverse();
                              }
                            }
                          : null,
                      onScaleStart: (_) => _startZoom = _zoom,
                      onScaleUpdate: (event) => setState(() {
                            _yaw += event.focalPointDelta.dx * .012;
                            _pitch = (_pitch + event.focalPointDelta.dy * .012)
                                .clamp(-1.5, 1.5);
                            _zoom = (_startZoom * event.scale).clamp(.35, 1.5);
                          }),
                      child: SocketMediaRenderer.console(
                        key: rendererKey,
                        model: widget.model,
                        frameComposition: true,
                        compositionFill: widget.compositionFill,
                        compositionZoom: _zoom / .9,
                        gameWatchScene: widget.unboxingScene,
                        identity:
                            'console:${widget.systemId}:${widget.model.hardwareId}:${widget.generation}',
                        title: widget.title,
                        onReady: _ready,
                        pose: SocketMediaPose(
                            unboxing: widget.unboxingProgress,
                            inspectedPart: widget.inspecting ? 'console' : null,
                            inspection: widget.inspecting ? 1 : 0,
                            opening: widget.sequenceOpening ?? _opening.value,
                            rx: _pitch,
                            ry: widget.stagingYaw +
                                _yaw +
                                (widget.reducedMotion ? 0 : _motionYaw),
                            scaleX: _zoom * widget.stagingScale,
                            scaleY: _zoom * widget.stagingScale,
                            scaleZ: _zoom * widget.stagingScale),
                      )))),
        )),
      );
  @override
  void dispose() {
    _idle?.cancel();
    _rotation.stop();
    debugPrint(
        'GShopConsolePreview hidden system=${widget.systemId} rotationRunning=${_rotation.isAnimating}');
    _rotation.dispose();
    _opening.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
