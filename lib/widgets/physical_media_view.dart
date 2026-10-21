import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/socket_media_model.dart';
import '../models/nes_unboxing_scene.dart';
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
  final NesUnboxingScene? nesScene;
  final bool resourcesReady;
  final bool informationVisible;
  final bool? cartridgeInspected;
  final ValueChanged<String?>? onInspectionChanged;
  const PhysicalMediaView(
      {super.key,
      required this.identity,
      required this.title,
      required this.label,
      this.labelIdentity,
      this.onReady,
      this.cartridgeStyle,
      this.inspectInside = false,
      this.nesScene,
      this.resourcesReady = true,
      this.informationVisible = false,
      this.cartridgeInspected,
      this.onInspectionChanged,
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
  late final _unboxing = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.nesScene?.durationMs ?? 1));
  late final _insertion = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.format.insertionMilliseconds));
  Completer<bool>? _completion;
  bool _resumed = true;
  bool _gpuReady = false;
  bool _launchHeld = false;
  bool _zoomCartridge = false;
  double _informationStart = 0, _informationBase = 0;
  double get _informationAngle =>
      _informationBase + (_idle.value - _informationStart) * math.pi * 2;
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
  SocketMediaPose get pose {
    final sample = SocketMediaPose.sample(
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
        insertion:
            _insertion.value * widget.format.insertionMilliseconds / 1000,
        manualRotation: _manualRotation,
        opening: _inspection.value,
        reducedMotion: _reduce);
    if (widget.nesScene == null) return sample;
    if (_completion != null)
      return SocketMediaPose(
          rx: sample.rx + math.pi / 2,
          ry: sample.ry,
          rz: sample.rz,
          y: sample.y,
          z: sample.z,
          scaleX: sample.scaleX,
          scaleY: sample.scaleY,
          scaleZ: sample.scaleZ,
          unboxing: 1,
          inspectedPart: 'cartridge');
    final idle = _unboxing.isCompleted && !_reduce;
    if (_zoomCartridge) {
      return SocketMediaPose(
          rx: .12,
          ry: _manualRotation +
              (idle && widget.informationVisible ? _informationAngle : 0),
          opening: _inspection.value,
          unboxing: 1,
          inspectedPart: 'cartridge');
    }
    return SocketMediaPose(
        rx: .12 + (idle ? math.sin(_idle.value * math.pi * 2) * .015 : 0),
        ry: -.12 +
            _manualRotation +
            (idle
                ? widget.informationVisible
                    ? _informationAngle
                    : math.sin(_idle.value * math.pi * 2) * .025
                : 0),
        opening: _inspection.value,
        unboxing: _unboxing.value);
  }

  @override
  void initState() {
    super.initState();
    _zoomCartridge = widget.cartridgeInspected == true;
    WidgetsBinding.instance.addObserver(this);
    _unboxing.addStatusListener((s) {
      if (s == AnimationStatus.completed) _configureMotion();
    });
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
    if (oldWidget.informationVisible != widget.informationVisible) {
      final idleYaw =
          _zoomCartridge ? 0.0 : math.sin(_idle.value * math.pi * 2) * .025;
      if (widget.informationVisible) {
        _informationStart = _idle.value;
        _informationBase = idleYaw;
      } else {
        _manualRotation += _informationAngle - idleYaw;
      }
      _idle.stop();
    }
    if (oldWidget.identity != widget.identity ||
        oldWidget.format != widget.format ||
        oldWidget.nesScene?.identity != widget.nesScene?.identity) {
      _finish(false);
      _insertion.reset();
      _manualRotation = 0;
      _zoomCartridge = false;
      _selection.reset();
      _inspection.value = 0;
      _gpuReady = false;
      _unboxing.duration =
          Duration(milliseconds: widget.nesScene?.durationMs ?? 1);
      _unboxing.reset();
      _insertion.duration =
          Duration(milliseconds: widget.format.insertionMilliseconds);
    }
    if (oldWidget.labelIdentity != widget.labelIdentity) {
      _gpuReady = false;
      _unboxing.stop();
    }
    if (widget.cartridgeInspected != null &&
        oldWidget.cartridgeInspected != widget.cartridgeInspected) {
      _zoomCartridge = widget.cartridgeInspected!;
    }
    _configureMotion();
  }

  bool closeInspection() {
    if (!_zoomCartridge || _launchHeld) return false;
    setState(() => _zoomCartridge = false);
    _configureMotion();
    widget.onInspectionChanged?.call(null);
    return true;
  }

  void _configureMotion() {
    if (!_resumed || _launchHeld) return;
    _idle.duration = widget.informationVisible
        ? const Duration(seconds: 120)
        : const Duration(microseconds: 62831853);
    if (widget.nesScene != null && !_unboxing.isCompleted) _idle.stop();
    if (widget.nesScene != null && _gpuReady && widget.resourcesReady) {
      if (_reduce || widget.inspectInside) {
        if (!_unboxing.isCompleted) _unboxing.value = 1;
      } else if (!_unboxing.isCompleted && !_unboxing.isAnimating) {
        _unboxing.forward();
      }
    } else if (widget.nesScene != null) {
      _unboxing.stop();
    }
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
      if (!_idle.isAnimating &&
          (widget.nesScene == null || _unboxing.isCompleted)) _idle.repeat();
      if (!_selection.isCompleted) _selection.forward();
    }
  }

  Future<bool> playInsertion() {
    if (_completion case final pending?) return pending.future;
    if (_reduce) return Future.value(true);
    _inspection.value = 0;
    if (widget.nesScene != null) _unboxing.value = 1;
    final pending = Completer<bool>();
    _completion = pending;
    _insertion.forward(from: 0);
    setState(() {});
    return pending.future;
  }

  /// Keep the selected source pose stable while the launch composite loads.
  /// Releasing it resumes these same controllers, without resetting selection.
  void holdForLaunch() {
    _launchHeld = true;
    _unboxing.stop();
    _idle.stop();
    _inspection.stop();
  }

  void inspectCartridge({bool toggle = false}) {
    if (widget.nesScene == null || _launchHeld) return;
    setState(() {
      _zoomCartridge = toggle ? !_zoomCartridge : true;
      _unboxing.value = 1;
    });
    _configureMotion();
    widget.onInspectionChanged?.call(_zoomCartridge ? 'cartridge' : null);
  }

  void releaseLaunchHold() {
    _launchHeld = false;
    _configureMotion();
  }

  void skipInsertion() {
    if (_completion != null) _insertion.value = 1;
  }

  void resetInsertion() {
    _finish(false);
    _insertion.reset();
  }

  void replayUnboxing() {
    if (widget.nesScene == null || _completion != null) return;
    closeInspection();
    _inspection.value = 0;
    _unboxing.reset();
    _configureMotion();
  }

  void _rendered() {
    _gpuReady = true;
    _configureMotion();
    widget.onReady?.call();
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
      _unboxing.stop();
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
    _unboxing.dispose();
    _insertion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
      label: '3D ${widget.format.description}: ${widget.title}',
      child: AnimatedBuilder(
          animation: Listenable.merge(
              [_selection, _idle, _insertion, _inspection, _unboxing]),
          builder: (context, _) => Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    GestureDetector(
                        onDoubleTap: widget.nesScene == null
                            ? null
                            : () => inspectCartridge(toggle: true),
                        onHorizontalDragUpdate: (event) {
                          if (_completion == null) {
                            setState(
                                () => _manualRotation += event.delta.dx * .012);
                          }
                        },
                        child: SocketMediaRenderer(
                            key: _rendererKey,
                            frameComposition: true,
                            format: widget.format,
                            cartridgeStyle: widget.cartridgeStyle,
                            nesScene: widget.nesScene,
                            pose: pose,
                            identity: widget.identity,
                            title: widget.title,
                            label: widget.label,
                            labelIdentity: widget.labelIdentity,
                            onReady: _rendered)),
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
