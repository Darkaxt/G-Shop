import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/config/app_config.dart';
import '../services/database_service.dart';
import '../services/config_storage_service.dart';
import '../services/rom_cache_runtime.dart';
import '../services/rom_cache_store.dart';
import '../services/rom_cache_dispatch.dart';
import 'app_providers.dart';

final romCacheProvider = FutureProvider<RomCacheRuntime>((ref) async {
  await ref.read(sourcesProvider.notifier).ready;
  final service = RomCacheRuntime(
      store: RomCacheStore(DatabaseService().database),
      configuration: () async {
        final loaded =
            await ConfigStorageService().loadConfigWithRecoveryInfo();
        if (loaded.wasRecovered) {
          throw StateError('Configuration requires review');
        }
        return loaded.config ?? AppConfig.empty;
      },
      acquirePass: RomCacheDispatch.acquire,
      releasePass: RomCacheDispatch.release,
      schedule: RomCacheDispatch.schedule);
  ref.onDispose(service.dispose);
  await RomCacheDispatch.bind(service);
  return service;
});
