import 'dart:io';
import 'package:flutter/services.dart';

/// The foreground migration owns this admission until its original operation
/// settles. Native admission covers other Flutter engines and process recovery.
class MigrationMaintenance {
  static const channel = MethodChannel('com.darkaxt.gshop/migration');
  static bool active = false;
  static Future<void> begin() async {
    if (active) throw StateError('Migration already active');
    active = true;
    try {
      if (Platform.isAndroid) {
        await channel.invokeMethod<void>('maintenance', {'enabled': true});
      }
    } catch (_) {
      active = false;
      rethrow;
    }
  }

  static Future<void> quiescent() async {
    if (Platform.isAndroid) await channel.invokeMethod<void>('quiescent');
  }

  static Future<void> end() async {
    if (Platform.isAndroid) {
      await channel.invokeMethod<void>('maintenance', {'enabled': false});
    }
    active = false;
  }

  static Future<void> restart() async {
    if (Platform.isAndroid) await channel.invokeMethod<void>('restart');
  }
}
