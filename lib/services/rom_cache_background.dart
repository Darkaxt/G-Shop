import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'config_storage_service.dart';
import 'database_service.dart';
import 'rom_cache_runtime.dart';
import 'rom_cache_store.dart';
import 'rom_cache_dispatch.dart';
import 'drive/drive_runtime.dart';
import 'drive/drive_catalogue.dart';
import 'transfer_journal.dart';

/// Headless policy execution; no catalogue scraping, ROM upload, UI or consent.
@pragma('vm:entry-point')
void romCacheBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  RomCacheRuntime? runtime;
  try {
    final db = await DatabaseService.openBackgroundDatabase();
    runtime = RomCacheRuntime(
        store: RomCacheStore(Future.value(db)),
        drive: DriveRuntime(
            journal: TransferJournal(Future.value(db)),
            catalogue: DriveCatalogue(Future.value(db))),
        configuration: () async {
          final loaded =
              await ConfigStorageService().loadConfigWithRecoveryInfo();
          if (loaded.wasRecovered || loaded.config == null) {
            throw StateError('Configuration unavailable');
          }
          return loaded.config!;
        },
        acquirePass: RomCacheDispatch.acquire,
        releasePass: RomCacheDispatch.release,
        schedule: RomCacheDispatch.schedule);
    await RomCacheDispatch.bind(runtime);
  } catch (_) {
    RomCacheDispatch.channel.setMethodCallHandler((call) async {
      if (call.method == 'stop') {
        await runtime?.cancelAndJoin();
        return null;
      }
      throw PlatformException(code: 'background_setup_unavailable');
    });
    await RomCacheDispatch.channel.invokeMethod<void>('ready');
  }
}
