import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

enum SceneLaunchPhase {
  idle,
  preparing,
  animating,
  committing,
  handedOff,
  cancelled
}

/// Presentation gates for the existing owned-ROM launcher. This never opens a
/// ROM, chooses an emulator, reconciles saves or starts another launch pipeline.
/// Renderer replies belong to one immutable selection/console attempt.
class SceneLaunchPresentation extends ChangeNotifier {
  final Stopwatch _clock = Stopwatch()..start();
  int _sequence = 0;
  int? _token;
  String? _identity, _consoleId;
  SceneLaunchPhase _phase = SceneLaunchPhase.idle;
  Completer<bool>? _resources, _frame;
  Duration? _lastConfirm;
  bool _skip = false, _painted = false;
  bool _visualAvailable = true;

  int? get token => _token;
  String? get identity => _identity;
  String? get consoleId => _consoleId;
  SceneLaunchPhase get phase => _phase;
  bool get skipRequested => _skip;
  bool get visualAvailable => _visualAvailable;
  bool get canInterrupt =>
      _phase == SceneLaunchPhase.preparing ||
      _phase == SceneLaunchPhase.animating;
  bool get pending => canInterrupt || _phase == SceneLaunchPhase.committing;

  int begin({required String identity, required String? consoleId}) {
    if (pending) throw StateError('A scene launch is already pending');
    _finishUnresolved();
    _token = ++_sequence;
    _identity = identity;
    _consoleId = consoleId;
    _phase = SceneLaunchPhase.preparing;
    _resources = Completer<bool>();
    _frame = Completer<bool>();
    _lastConfirm = null;
    _skip = _painted = false;
    _visualAvailable = true;
    notifyListeners();
    return _token!;
  }

  /// Bind the validated compatible choice once during resource preparation.
  bool selectConsole(int token, String consoleId) {
    if (_token != token ||
        _phase != SceneLaunchPhase.preparing ||
        _consoleId != null ||
        consoleId.isEmpty) return false;
    _consoleId = consoleId;
    notifyListeners();
    return true;
  }

  bool ready(int token) {
    if (_token != token || _phase != SceneLaunchPhase.preparing) return false;
    if (!_resources!.isCompleted) _resources!.complete(true);
    return true;
  }

  /// Missing/failed presentation resources permit the existing direct-launch
  /// path. This does not waive any ROM, save or native permission checks.
  bool unavailable(int token) {
    if (_token != token || !canInterrupt) return false;
    _visualAvailable = false;
    if (!_resources!.isCompleted) _resources!.complete(true);
    if (!_frame!.isCompleted) _frame!.complete(false);
    notifyListeners();
    return true;
  }

  bool commitWithoutAnimation(int token) {
    if (_token != token ||
        !canInterrupt ||
        _visualAvailable ||
        !_resources!.isCompleted) return false;
    _phase = SceneLaunchPhase.committing;
    notifyListeners();
    return true;
  }

  /// Call only at the existing launcher's beforeHandoff boundary, after its
  /// permission/save checks. Cancellation resolves either wait deterministically.
  Future<bool> commitWhenPresented(int token) async {
    if (!await waitForResources(token)) return false;
    if (_visualAvailable) {
      if (!animate(token)) return false;
      final painted = await waitForFrame(token);
      if (painted && commit(token)) return true;
    }
    return commitWithoutAnimation(token);
  }

  bool skip() {
    if (!canInterrupt || _skip) return false;
    _skip = true;
    _lastConfirm = null;
    notifyListeners();
    return true;
  }

  Future<bool> waitForResources(int token) => _token == token && canInterrupt
      ? _resources!.future
      : Future.value(false);

  bool animate(int token) {
    if (_token != token ||
        _phase != SceneLaunchPhase.preparing ||
        !_resources!.isCompleted) return false;
    _phase = SceneLaunchPhase.animating;
    notifyListeners();
    return true;
  }

  Future<bool> waitForFrame(int token) =>
      _token == token && canInterrupt ? _frame!.future : Future.value(false);

  /// Two additional, non-repeat A events use Flutter's double-tap gesture window.
  /// No timer controls preparation, completion, cancellation or handoff.
  bool confirm([Duration? monotonicTime]) {
    if (!canInterrupt || _skip) return false;
    final now = monotonicTime ?? _clock.elapsed;
    final previous = _lastConfirm;
    _lastConfirm = now;
    if (previous == null ||
        now < previous ||
        now - previous > kDoubleTapTimeout) return false;
    return skip();
  }

  bool rendered(int token) {
    if (_token != token || _phase != SceneLaunchPhase.animating) return false;
    _painted = true;
    if (!_frame!.isCompleted) _frame!.complete(true);
    return true;
  }

  bool commit(int token) {
    if (_token != token || _phase != SceneLaunchPhase.animating || !_painted)
      return false;
    _phase = SceneLaunchPhase.committing;
    notifyListeners();
    return true;
  }

  void handedOff(int token) {
    if (_token != token || _phase != SceneLaunchPhase.committing) return;
    _phase = SceneLaunchPhase.handedOff;
    notifyListeners();
  }

  bool cancel() {
    if (!canInterrupt) return false;
    _phase = SceneLaunchPhase.cancelled;
    _lastConfirm = null;
    _finishUnresolved();
    notifyListeners();
    return true;
  }

  void reset({bool notify = true}) {
    _finishUnresolved();
    _token = null;
    _identity = _consoleId = null;
    _phase = SceneLaunchPhase.idle;
    _lastConfirm = null;
    _skip = _painted = false;
    _visualAvailable = true;
    if (notify) notifyListeners();
  }

  void _finishUnresolved() {
    if (_resources case final resources? when !resources.isCompleted) {
      resources.complete(false);
    }
    if (_frame case final frame? when !frame.isCompleted) frame.complete(false);
  }

  @override
  void dispose() {
    _clock.stop();
    _phase = SceneLaunchPhase.cancelled;
    _token = null;
    _finishUnresolved();
    super.dispose();
  }
}
