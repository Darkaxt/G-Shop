import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One foreground presentation, with no acquisition, auth or installation owner.
class SecondaryPreview extends ChangeNotifier {
  static const channel = MethodChannel('com.darkaxt.gshop/preview');
  bool available = false;
  bool _disposed = false;
  Object? _owner;
  Future<void> Function(String, int?)? _action;
  int _revision = 0;
  int _actionEpoch = 0;
  String? _actionIdentity;
  String? _video;
  bool _playing = false;
  final void Function(bool)? onPlaybackChanged;
  SecondaryPreview({this.onPlaybackChanged}) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'availability') {
        _availability(call.arguments == true);
      } else if (call.method == 'action') {
        final args = (call.arguments as Map).cast<String, dynamic>();
        if (args['actionEpoch'] == _actionEpoch)
          await _action?.call(
              args['action'] as String, args['variant'] as int?);
      } else if (call.method == 'playing') {
        final args = (call.arguments as Map).cast<String, dynamic>();
        if (_owner != null &&
            args['actionEpoch'] == _actionEpoch &&
            args['video'] == _video) {
          _setPlaying(available && args['playing'] == true);
        }
      }
    });
    if (!Platform.isAndroid) return;
    unawaited(channel
        .invokeMethod<bool>('available')
        .then((v) => _availability(v == true))
        .catchError((Object _) => _availability(false)));
  }
  void _availability(bool value) {
    if (!value) _setPlaying(false);
    if (_disposed || available == value) return;
    available = value;
    notifyListeners();
  }

  void _setPlaying(bool value) {
    if (_playing == value) return;
    _playing = value;
    onPlaybackChanged?.call(value);
  }

  /// Prepare a hidden renderer, not a presentation or a selected game.
  Future<void> prepare(
      {required bool enabled,
      String? resourceRoot,
      String? resourceGeneration}) async {
    if (_disposed) return;
    if (!enabled) {
      _owner = null;
      _video = null;
      _action = null;
      _actionIdentity = null;
      _actionEpoch++;
      _setPlaying(false);
    }
    await channel.invokeMethod<void>('prepare', {
      'enabled': enabled,
      if (resourceRoot != null) 'resourceRoot': resourceRoot,
      if (resourceGeneration != null) 'resourceGeneration': resourceGeneration,
    });
  }

  Future<void> present(Object owner, Map<String, dynamic> payload,
      Future<void> Function(String, int?) action) async {
    if (_disposed || !available) return;
    final identity = payload['actionIdentity'] as String;
    if (!identical(_owner, owner) ||
        _actionIdentity != identity ||
        _video != payload['video']) {
      _setPlaying(false);
      _actionEpoch++;
    }
    _owner = owner;
    _video = payload['video'] as String?;
    _actionIdentity = identity;
    _action = action;
    final revision = ++_revision;
    await channel.invokeMethod<void>('present',
        {...payload, 'revision': revision, 'actionEpoch': _actionEpoch});
  }

  Future<void> hide(Object owner) async {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _video = null;
    _setPlaying(false);
    _action = null;
    _revision++;
    _actionEpoch++;
    await channel.invokeMethod<void>('hide');
  }

  /// The destination route owns the existing window while it prepares a real
  /// selected-game payload. No timer, engine restart or native dismissal.
  void retainFor(Object destination) {
    if (_disposed || !available || _owner == null) return;
    _owner = destination;
    _action = null;
    _actionIdentity = null;
    _actionEpoch++;
  }

  Future<void> togglePlayback(Object owner) async {
    if (!identical(owner, _owner) || !available) return;
    await channel.invokeMethod<void>('playback', {'actionEpoch': _actionEpoch});
  }

  @override
  void dispose() {
    _disposed = true;
    _setPlaying(false);
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}
