import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'rom_cache_runtime.dart';

class RomCacheDispatch {
  static const channel = MethodChannel('com.retro.rshop/rom_cache');
  static Future<void> acquire(CancelToken cancellation) async {
    if (!Platform.isAndroid) return;
    var waiting = true;
    unawaited(cancellation.whenCancel.then((_) async {
      if (waiting) {
        try {
          await channel.invokeMethod<void>('cancelAdmission');
        } catch (_) {/* Original acquire owns the result. */}
      }
    }));
    try {
      await channel.invokeMethod<void>('acquire');
    } finally {
      waiting = false;
    }
  }

  static Future<void> release() async {
    if (Platform.isAndroid) await channel.invokeMethod<void>('release');
  }

  static Future<void> schedule(bool enabled, DateTime? due) async {
    if (Platform.isAndroid) {
      await channel.invokeMethod<void>('schedule', {
        'enabled': enabled,
        'dueMillis': due?.toUtc().millisecondsSinceEpoch
      });
    }
  }

  static Future<void> bind(RomCacheRuntime runtime) async {
    if (!Platform.isAndroid) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'stop') {
        await runtime.cancelAndJoin();
        return null;
      }
      if (call.method != 'run') throw MissingPluginException();
      await runtime.reconcile();
      return {'removed': runtime.removedGames, 'issue': runtime.issue};
    });
    await channel.invokeMethod<void>('ready');
  }
}
