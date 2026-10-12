import 'dart:io';
import 'dart:async';
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

  static Future<Set<String>> configureWatches(
      List<AutomaticSaveMapping> mappings) async {
    if (!Platform.isAndroid) return {};
    final registered = await channel.invokeListMethod<String>('watch', {
      'mappings': mappings
          .map((mapping) => {
                'key': mapping.key,
                'directory': mapping.directory,
                'name': mapping.slot,
                if (mapping.isMelon) 'route': 'melon',
              })
          .toList(),
    });
    if (registered == null || registered.toSet().length != registered.length) {
      throw PlatformException(code: 'invalid_watch_receipt');
    }
    return registered.toSet();
  }

  static Future<void> bind(AutomaticSaveBackups service) async {
    if (!Platform.isAndroid) return;
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'watchUnavailable':
          service.watchUnavailable();
          return null;
        case 'changed':
          final key = call.arguments;
          if (key is! String) throw PlatformException(code: 'invalid_watch');
          // Acknowledge durable admission, not completion of cloud IO. The
          // existing serial lane remains live while the emulator is in front.
          try {
            await service.requestChanged(key);
          } catch (_) {
            service.watchUnavailable();
            rethrow;
          }
          unawaited(service.backupPending().catchError((Object _) {
            service.watchUnavailable();
          }));
          return null;
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
