import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Presentation timing requested by the owner, never a scene/launch watchdog.
class SceneIdleHints extends StatefulWidget {
  static const idleDelay = Duration(seconds: 25);
  final String identity;
  final List<String> hints;
  final Widget child;
  final bool enabled;
  final int activityRevision;
  const SceneIdleHints(
      {super.key,
      required this.identity,
      required this.hints,
      required this.child,
      this.enabled = true,
      this.activityRevision = 0});

  static List<String> forView(String system,
          {bool collector = false,
          bool inspecting = false,
          bool canLaunch = false}) =>
      [
        if (collector)
          'Drag to rotate. Pinch to zoom.'
        else if (system == 'gameandwatch')
          inspecting
              ? 'Use Info for available hardware facts.'
              : 'Tap a model itself to inspect it.'
        else if (system == 'nes')
          'Double-tap the cartridge to inspect it.'
        else if (system == 'gba')
          'Tap an item to inspect it.',
        if (canLaunch) 'Press A twice during launch to skip the animation.',
        // Existing hardware-history facts and generation-specific launch contract.
        if (system == 'gameandwatch')
          'Micro VS System handhelds have two wired controllers.'
        else if (system == 'nes')
          'The original NES has no universal boot logo.'
        // Nintendo’s original hardware pages: nintendo.co.jp/n08/hardware/gba/.
        else if (system == 'gba')
          'GBA cartridges measure 60 × 34.5 mm.',
      ];

  @override
  State<SceneIdleHints> createState() => _SceneIdleHintsState();
}

class _SceneIdleHintsState extends State<SceneIdleHints>
    with WidgetsBindingObserver {
  Timer? _timer;
  final _idleClock = Stopwatch();
  bool _visible = false, _resumed = true;
  int _index = -1, _pointers = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_key);
    _restart();
  }

  bool _key(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) _restart();
    return false;
  }

  void _restart() {
    _timer?.cancel();
    _timer = null;
    _idleClock
      ..reset()
      ..start();
    if (_visible) setState(() => _visible = false);
    _arm();
  }

  void _arm() {
    if (!widget.enabled ||
        !_resumed ||
        _pointers != 0 ||
        widget.hints.isEmpty) {
      return;
    }
    _timer = Timer(SceneIdleHints.idleDelay, () {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % widget.hints.length;
        _visible = true;
      });
      debugPrint('GShopSceneHint ${jsonEncode({
            "identity": widget.identity,
            "visible": true,
            "index": _index,
            "idleUs": _idleClock.elapsedMicroseconds
          })}');
      _arm();
    });
  }

  @override
  void didUpdateWidget(SceneIdleHints oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) _index = -1;
    if (oldWidget.identity != widget.identity ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.activityRevision != widget.activityRevision ||
        !listEquals(oldWidget.hints, widget.hints)) {
      _restart();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (!_resumed) _pointers = 0;
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _idleClock.stop();
    HardwareKeyboard.instance.removeHandler(_key);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        _pointers++;
        _restart();
      },
      onPointerUp: (_) {
        if (_pointers > 0) _pointers--;
        _restart();
      },
      onPointerCancel: (_) {
        if (_pointers > 0) _pointers--;
        _restart();
      },
      onPointerHover: (_) => _restart(),
      onPointerSignal: (_) => _restart(),
      child: Stack(fit: StackFit.expand, children: [
        widget.child,
        if (_visible && widget.hints.isNotEmpty)
          Positioned(
              left: MediaQuery.sizeOf(context).width * .23,
              right: MediaQuery.sizeOf(context).width * .23,
              bottom: 8,
              child: IgnorePointer(
                  child: SafeArea(
                      top: false,
                      child: Text('Did you know? ${widget.hints[_index]}',
                          key: const ValueKey('scene-idle-hint'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.white70))))),
      ]));
}
