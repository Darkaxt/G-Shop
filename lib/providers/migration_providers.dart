import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';
import '../services/migration/migration_activation.dart';
import '../services/migration/migration_maintenance.dart';
import '../services/migration/migration_service.dart';
import '../services/patch_build_service.dart';
import '../services/rom_cache_dispatch.dart';
import '../services/saves/save_background_dispatch.dart';
import '../services/saves/save_operation_admission.dart';
import '../services/saves/emulator_family_settings.dart';
import 'app_providers.dart';
import 'download_providers.dart';
import 'library_providers.dart';
import 'metadata_providers.dart';
import 'metadata_cloud_providers.dart';
import 'rom_cache_providers.dart';
import 'save_backup_providers.dart';

final migrationServiceProvider = FutureProvider<MigrationService>((ref) async {
  await ref.read(sourcesProvider.notifier).ready;
  final support = await getApplicationSupportDirectory();
  final documents = await getApplicationDocumentsDirectory();
  final configuredRoms = ref.read(storageServiceProvider).getRomPath();
  final roms =
      configuredRoms != null && await Directory(configuredRoms).exists()
          ? Directory(configuredRoms)
          : Directory('/storage/emulated/0/RShop/ROMs');
  final service = MigrationService(
      locations: MigrationLocations(
          documents: documents,
          support: support,
          database: File(p.join(await getDatabasesPath(), 'rshop.db')),
          configuration: File(EmulatorFamilySettings.androidPath).parent,
          roms: roms),
      database: DatabaseService().database,
      configuration: ref.read(configStorageServiceProvider),
      settings: const DeviceMigrationSettings(),
      sharedMetadata: ref.read(sharedMetadataStoreProvider),
      captureAssociated: () async =>
          (await ref.read(automaticSaveBackupsProvider.future))
              .captureForMigration(),
      closeDatabase: DatabaseService.closeForMigration,
      joinOwners: () async {
        Future<void> Function()? saveRelease;
        var cacheHeld = false;
        final cancellation = CancelToken();
        final saves = await ref.read(automaticSaveBackupsProvider.future);
        final cache = await ref.read(romCacheProvider.future);
        try {
          // Block new foreground work first; join original owners, including
          // post-download processing and catalogue thumbnail publication.
          await ref.read(downloadQueueManagerProvider).close();
          final sync = ref.read(librarySyncServiceProvider.notifier);
          sync.cancel();
          await sync.waitForCompletion();
          await ref.read(metadataControlsProvider.notifier).joinForMigration();
          await ref.read(metadataCloudProvider.notifier).pause();
          await ref.read(sharedMetadataProjectionProvider.future);
          await PatchBuildService.joinForMigration();
          await SaveBackgroundDispatch.configureWatches([]);
          await saves.cancelAndJoin();
          await cache.cancelAndJoin();
          saveRelease = await SaveOperationAdmission()
              .acquire(cancellation, migration: true);
          await RomCacheDispatch.acquire(cancellation, migration: true);
          cacheHeld = true;
          await MigrationMaintenance.quiescent();
        } catch (_) {
          if (cacheHeld) await RomCacheDispatch.release();
          await saveRelease?.call();
          await MigrationMaintenance.end();
          ref.read(metadataCloudProvider.notifier).resume();
          ref.invalidate(downloadQueueManagerProvider);
          await saves.reconcileSchedule();
          await cache.reconcile();
          rethrow;
        }
        return (bool resume) async {
          if (cacheHeld) {
            cacheHeld = false;
            await RomCacheDispatch.release();
          }
          await saveRelease?.call();
          saveRelease = null;
          if (resume) {
            await MigrationMaintenance.end();
            ref.read(metadataCloudProvider.notifier).resume();
            ref.invalidate(downloadQueueManagerProvider);
            await saves.reconcileSchedule();
            await cache.reconcile();
          }
        };
      });
  ref.onDispose(service.dispose);
  await service.initialize();
  return service;
});
