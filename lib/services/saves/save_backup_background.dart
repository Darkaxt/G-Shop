import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/config/source.dart';
import '../config_storage_service.dart';
import '../database_service.dart';
import 'automatic_save_backups.dart';
import 'save_background_dispatch.dart';

/// Headless boot: no widget tree, audio, catalogue sync or metadata recovery.
@pragma('vm:entry-point')
void saveBackupBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  AutomaticSaveBackups? service;
  Object? startupFailure;
  try {
    final preferences = await SharedPreferences.getInstance();
    var sources = <Source>[];
    Future<void> refresh() async {
      await preferences.reload();
      final loaded = await ConfigStorageService().loadConfigWithRecoveryInfo();
      if (loaded.wasRecovered || loaded.config == null) {
        throw PlatformException(code: 'source_changed');
      }
      sources = loaded.config!.sources;
    }

    await refresh();
    service = AutomaticSaveBackups(
        database: DatabaseService.openSaveBackgroundDatabase(),
        preferences: preferences,
        sources: () => sources,
        refreshConfiguration: refresh);
  } catch (error) {
    startupFailure = error;
  }
  SaveBackgroundDispatch.channel.setMethodCallHandler((call) async {
    if (call.method == 'stop') {
      await service?.cancelAndJoin();
      return null;
    }
    if (call.method != 'run') throw MissingPluginException();
    final current = service;
    if (startupFailure != null || current == null) {
      throw PlatformException(code: 'background_setup_unavailable');
    }
    await current.checkEnabled();
    return current.passSummary();
  });
  await SaveBackgroundDispatch.channel.invokeMethod<void>('ready');
}
