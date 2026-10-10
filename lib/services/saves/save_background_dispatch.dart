import 'dart:io';
import 'package:flutter/services.dart';
import 'automatic_save_backups.dart';

/// One protocol for the UI-owned lane and the native headless entrypoint.
/// Android owns scheduling and cancellation; Dart owns the durable backup pass.
class SaveBackgroundDispatch {
  static const channel = MethodChannel('com.retro.rshop/save_background');
  static Future<void> schedule(bool enabled) async {
    if (Platform.isAndroid) {
      await channel.invokeMethod<void>('schedule', {'enabled': enabled});
    }
  }

  static Future<void> bind(AutomaticSaveBackups service) async {
    if (!Platform.isAndroid) return;
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'run':
          await service.checkEnabled();
          return service.passSummary();
        case 'stop':
          await service.cancelAndJoin();
          return null;
        default:
          throw MissingPluginException();
      }
    });
    try {
      await channel.invokeMethod<void>('ready');
    } on PlatformException {
      service.backgroundUnavailable();
      return;
    } on MissingPluginException {
      service.backgroundUnavailable();
      return;
    }
    await service.reconcileSchedule();
  }
}
