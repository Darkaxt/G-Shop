import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

/// Native admission spans UI/headless Dart engines in the default app process.
/// Cancellation removes a waiter; it never expires or steals an active owner.
class SaveOperationAdmission {
  static const _channel = MethodChannel('com.darkaxt.gshop/save_operation');
  final bool android;
  SaveOperationAdmission({bool? android})
      : android = android ?? Platform.isAndroid;
  Future<Future<void> Function()> acquire(CancelToken cancellation,
      {bool migration = false}) async {
    if (cancellation.isCancelled) throw PlatformException(code: 'cancelled');
    if (!android) return () async {};
    final id = List.generate(16, (_) => Random.secure().nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    var waiting = true;
    cancellation.whenCancel.then((_) async {
      if (waiting) await _channel.invokeMethod<void>('cancel', {'id': id});
    });
    try {
      await _channel.invokeMethod<void>(
          'acquire', {'id': id, if (migration) 'migration': true});
    } finally {
      waiting = false;
    }
    var held = true;
    return () async {
      if (!held) return;
      held = false;
      await _channel.invokeMethod<void>('release', {'id': id});
    };
  }
}
