// Isolated, debug-only native migration acceptance. The host removes/reinstalls
// only this recorded test package between export and import. No network requests,
// production bootstrap, owner settings, save directories or SD cleanup.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:g_shop/main.dart' as application;
import 'package:g_shop/models/config/app_config.dart';
import 'package:g_shop/models/config/system_config.dart';
import 'package:g_shop/models/game_item.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/save_root_configuration.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/models/system_model.dart';
import 'package:g_shop/models/transfer_record.dart';
import 'package:g_shop/services/config_storage_service.dart';
import 'package:g_shop/services/database_service.dart';
import 'package:g_shop/services/installation_index.dart';
import 'package:g_shop/services/library_store.dart';
import 'package:g_shop/services/metadata/metadata_artwork_cache.dart';
import 'package:g_shop/services/metadata/metadata_credentials.dart';
import 'package:g_shop/services/migration/migration_activation.dart';
import 'package:g_shop/services/migration/migration_archive.dart';
import 'package:g_shop/services/migration/migration_maintenance.dart';
import 'package:g_shop/services/migration/migration_service.dart';
import 'package:g_shop/services/owned_emulator_launcher.dart';
import 'package:g_shop/services/owned_storage.dart';
import 'package:g_shop/services/rom_cache_dispatch.dart';
import 'package:g_shop/services/saves/automatic_save_backups.dart';
import 'package:g_shop/services/saves/save_operation_admission.dart';
import 'package:g_shop/services/saves/save_backup_setup.dart';
import 'package:g_shop/services/transfer_journal.dart';
import 'package:g_shop/services/verified_file_publication.dart';

const proofRoot = '/storage/emulated/0/RShopMigrationProof-20261016';
final status = ValueNotifier('Waiting for private proof input');
void require(bool value, String code) {
  if (!value) throw StateError(code);
}

final marker = File('$proofRoot/phase.json');
final archive = File('$proofRoot/portable.rshop');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  require(
      kDebugMode &&
          Platform.isAndroid &&
          (await PackageInfo.fromPlatform()).packageName ==
              'com.darkaxt.rshop.sharedproof',
      'isolated_debug_package_required');
  runApp(MaterialApp(
      home: Scaffold(
          body: Center(
              child: ValueListenableBuilder(
                  valueListenable: status,
                  builder: (_, value, __) => Text(value))))));
  unawaited(proof().catchError((Object error, StackTrace stack) {
    status.value = 'Native migration check failed';
    debugPrint(
        'MIGRATION_PROOF_FAILED ${error is MigrationArchiveException ? error.code : error is PlatformException ? error.code : error is StateError ? error.message : error.runtimeType}');
    debugPrintStack(stackTrace: stack, maxFrames: 8);
  }));
}

Future<void> proof() async {
  final support = await getApplicationSupportDirectory();
  final documents = await getApplicationDocumentsDirectory();
  final privateRoot = Directory(p.join(support.path, 'migrations'));
  final settings = const DeviceMigrationSettings();
  await MigrationService.recoverBeforeBootstrap(privateRoot);
  final phase = await marker.exists()
      ? (jsonDecode(await marker.readAsString()) as Map).cast<String, dynamic>()
      : <String, dynamic>{};
  if (phase['phase'] == 'verified') {
    application.main();
    return;
  }
  final password =
      await File(p.join(support.path, 'proof-password')).readAsString();
  final db = await DatabaseService().database;
  // A repeated fresh-install check reuses the same real exported archive, not
  // the prior destination's credentials, receipts or database.
  if (phase['phase'] == 'imported' &&
      (await settings.readSecrets()).isEmpty &&
      (await db.query('installed_artifacts')).isEmpty) {
    phase['phase'] = 'exported';
  }
  final configStore = ConfigStorageService();
  final prefs = await SharedPreferences.getInstance();
  late AppConfig config;
  late RemoteArtifact artifact;
  late GameItem item;
  if (phase.isEmpty) {
    final inputFile = File(p.join(support.path, 'proof-input.json'));
    require(await inputFile.exists(), 'private_input_required');
    final input = (jsonDecode(await inputFile.readAsString()) as Map)
        .cast<String, dynamic>();
    artifact = RemoteArtifact.fromJson(
        (input['installed']['artifact'] as Map).cast<String, dynamic>());
    final original = AppConfig.fromJson(
        (input['configuration'] as Map).cast<String, dynamic>());
    final source =
        original.sources.singleWhere((s) => s.id == artifact.id.sourceId);
    final root = '$proofRoot/source-roms';
    await Directory(root).create(recursive: true);
    config = AppConfig(sources: [
      source
    ], systems: [
      SystemConfig(
          id: 'gba',
          name: 'Game Boy Advance',
          targetFolder: root,
          providers: [],
          autoSync: false)
    ]);
    await configStore.saveConfig(jsonEncode(config.toJson()));
    await settings
        .writeSecrets((input['credentials'] as Map).cast<String, String>());
    await prefs.setString('rom_path', root);
    await prefs.setStringList('favorites', ['migration-proof-favorite']);
    await prefs.setBool('onboarding_completed', true);
    final store = LibraryStore(Future.value(db));
    final game =
        GameIdentity.fromJson((input['game'] as Map).cast<String, dynamic>());
    final edition = EditionIdentity.fromJson(
        (input['edition'] as Map).cast<String, dynamic>());
    await store.putGame(game);
    await store.putArtifact(artifact);
    await store.putEdition(edition);
    await store.putMetadata(MetadataRecord.fromJson(
        (input['metadata'] as Map).cast<String, dynamic>()));
    item = GameItem(
        filename: artifact.displayName,
        displayName: artifact.displayName,
        url: '',
        remoteArtifact: artifact);
    await DatabaseService().saveGames('gba', [item]);
    final journal = TransferJournal(Future.value(db));
    final plan = await const OwnedStorage().prepare(root);
    if (await journal.transfer('migration-proof-source') == null) {
      await journal.create(TransferRecord(
          id: 'migration-proof-source',
          artifact: artifact,
          destinationRoot: root,
          relativePath: artifact.displayName,
          stagePath: plan.stagePath('migration-proof-source'),
          archivePlatformId: 'gba'));
    }
    await VerifiedFilePublication(journal).publish(
        transferId: 'migration-proof-source',
        artifact: artifact,
        output: File(p.join(support.path, 'proof-rom')),
        targetRoot: root,
        filename: artifact.displayName,
        cancellation: CancelToken(),
        gameId: game.id,
        editionId: edition.id);
    await MetadataArtworkCache.install(db);
    final artRoot = Directory(p.join(support.path, 'metadata-artwork'));
    await artRoot.create(recursive: true);
    for (final raw in input['selectedArtwork'] as List) {
      final row = (raw as Map).cast<String, Object?>();
      final image =
          File(p.join(support.path, 'proof-art', row['filename'] as String));
      require(await image.exists(), 'artwork_input_required');
      await image.copy(p.join(artRoot.path, row['filename'] as String));
      await db.insert('metadata_artwork_cache', row,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    final saveRoot = SaveRootConfiguration.decode({
      'schema': 1,
      'directory': '$root/data',
      'emulator': 'com.retroarch.aarch64',
      'core': 'mgba',
      'kind': 'save',
      'format': 'migration-proof-save-v1',
      'files': ['proof.sav'],
      'folders': [],
      'required': ['proof.sav']
    });
    await Directory(saveRoot.directory).create();
    await File('${saveRoot.directory}/proof.sav')
        .writeAsBytes([7, 11, 13, 17, 19, 23, 29, 31], flush: true);
    final mapping = AutomaticSaveMapping.decode(jsonEncode({
      'schema': 6,
      'route': 'rom-companion',
      'romRoot': root,
      'platform': 'gba',
      'emulator': 'com.retroarch.aarch64',
      'core': 'mgba',
      'clientId': source.drive!.serverClientId,
      'accountId': source.drive!.accountId,
      'areaId': 'isolated-migration-area',
      'editionId': edition.id,
      'artifact': artifact.id.toJson(),
      'title': game.title,
      'directory': saveRoot.directory,
      'slot': artifact.displayName,
      'saveRoot': saveRoot.toJson()
    }));
    await prefs.setString(
        SaveRootConfiguration.storageKey(artifact.id.key), saveRoot.identity);
    await prefs.setString(
        SaveBackupSetup.storageKey(mapping.clientId, mapping.accountId),
        jsonEncode({'ready': true, 'areaId': mapping.areaId}));
    await db.execute('CREATE TABLE IF NOT EXISTS automatic_save_backups('
        'mapping_key TEXT PRIMARY KEY,record_json TEXT NOT NULL,enabled INTEGER NOT NULL,'
        'requested INTEGER NOT NULL DEFAULT 0,handled INTEGER NOT NULL DEFAULT 0,outcome TEXT,issue TEXT)');
    await db.insert(
        'automatic_save_backups',
        {
          'mapping_key': mapping.key,
          'record_json': mapping.encode(),
          'enabled': 0
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    final secrets = await settings.readSecrets();
    phase.addAll({
      'phase': 'seeded',
      'artifact': artifact.toJson(),
      'edition': edition.id,
      'credentialHashes': {
        for (final entry in secrets.entries)
          entry.key: sha256.convert(utf8.encode(entry.value)).toString()
      },
      'sourceInstallation': 'migration-proof-source',
      'artworkCount': (input['selectedArtwork'] as List).length
    });
    // Private seed credentials are now in supported Keystore storage, not the
    // fixture input. The recorded temporary app uninstall retires its private data.
  } else {
    artifact = RemoteArtifact.fromJson(
        (phase['artifact'] as Map).cast<String, dynamic>());
    item = GameItem(
        filename: artifact.displayName,
        displayName: artifact.displayName,
        url: '',
        remoteArtifact: artifact);
    config = await configStore.loadConfig() ?? AppConfig.empty;
  }
  final automatic = AutomaticSaveBackups(
      database: Future.value(db),
      preferences: prefs,
      sources: () => config.sources,
      networkAvailable: () async => false,
      configureWatches: (_) async => {});
  final service = MigrationService(
      locations: MigrationLocations(
          documents: documents,
          support: support,
          configuration: Directory('$proofRoot/config'),
          roms: Directory(phase['phase'] == 'seeded'
              ? '$proofRoot/source-roms'
              : '$proofRoot/destination-roms'),
          database: File(p.join(await getDatabasesPath(), 'rshop.db'))),
      database: Future.value(db),
      configuration: configStore,
      settings: settings,
      sharedMetadata: Future.value(null),
      captureAssociated: automatic.captureForMigration,
      closeDatabase: DatabaseService.closeForMigration,
      joinOwners: () async {
        final token = CancelToken();
        final release =
            await SaveOperationAdmission().acquire(token, migration: true);
        await RomCacheDispatch.acquire(token, migration: true);
        await MigrationMaintenance.quiescent();
        return (resume) async {
          await RomCacheDispatch.release();
          await release();
          if (resume) await MigrationMaintenance.end();
        };
      });
  if (phase['phase'] == 'seeded') {
    status.value = 'Exporting complete native setup';
    final exported = await service.backup(password);
    await exported.copy(archive.path);
    phase['phase'] = 'exported';
    await marker.writeAsString(jsonEncode(phase), flush: true);
    debugPrint('MIGRATION_PROOF_EXPORTED');
    status.value = 'Ready for isolated reinstall';
  } else if (phase['phase'] == 'exported') {
    await service.initialize();
    if (!service.canResume) {
      require((await settings.readSecrets()).isEmpty,
          'destination_must_have_fresh_secure_store');
    }
    status.value = 'Importing into fresh native app data';
    if (service.canResume) {
      await service.resume();
    } else {
      await service.restore(archive, password);
    }
    phase['phase'] = 'imported';
    await marker.writeAsString(jsonEncode(phase), flush: true);
    await MigrationMaintenance.restart();
  } else if (phase['phase'] == 'imported') {
    status.value = 'Checking restored setup and local launch';
    final secrets = await settings.readSecrets();
    for (final entry in (phase['credentialHashes'] as Map).entries) {
      require(
          secrets[entry.key] != null &&
              sha256.convert(utf8.encode(secrets[entry.key]!)).toString() ==
                  entry.value,
          'credential_roundtrip_failed');
    }
    require(
        (await ScreenScraperCredentialStore().readUser())?.isConfigured == true,
        'screenscraper_store_failed');
    require((await IgdbCredentialStore().read())?.isConfigured == true,
        'igdb_store_failed');
    require(
        prefs.getStringList('favorites')!.single == 'migration-proof-favorite',
        'preferences_failed');
    final installation = (await db.query('installed_artifacts')).single;
    final installed = InstalledArtifact.fromJson(
        (jsonDecode(installation['record_json'] as String) as Map)
            .cast<String, dynamic>());
    require(
        installed.id != 'migration-proof-source', 'source_ownership_reused');
    final journal = TransferJournal(Future.value(db));
    await InstallationIndex(journal).requireInstallation(
        (await journal.transfer(installed.transferId))!, installed);
    final restoredConfig = await configStore.loadConfig();
    require(restoredConfig != null, 'configuration_failed');
    config = restoredConfig!;
    await automatic.prepareLaunch(
        artifactId: artifact.id, editionId: phase['edition'] as String);
    final rows = await db.query('automatic_save_backups');
    final mapping =
        AutomaticSaveMapping.decode(rows.single['record_json'] as String);
    require(rows.single['enabled'] == 0, 'monitoring_was_enabled');
    require(
        await File('${mapping.directory}/proof.sav').readAsBytes().then(
            (bytes) => listEquals(bytes, [7, 11, 13, 17, 19, 23, 29, 31])),
        'expected_save_location_failed');
    require(
        (await db.query('metadata_artwork_cache')).length ==
            phase['artworkCount'],
        'artwork_restore_failed');
    require((await db.query('library_metadata')).isNotEmpty,
        'metadata_restore_failed');
    phase['phase'] = 'verified';
    phase['nativeOwnership'] = true;
    phase['expectedSaveBytes'] = true;
    phase['credentialRoundtrip'] = true;
    phase['monitoringStillDisabled'] = true;
    await marker.writeAsString(jsonEncode(phase), flush: true);
    debugPrint('MIGRATION_PROOF_VERIFIED');
    await OwnedEmulatorLauncher().open(
        item,
        SystemModel.supportedSystems.singleWhere((s) => s.id == 'gba'),
        installed.destinationRoot);
    status.value = 'Native migration and normal owned launch verified';
  } else {
    throw StateError('unexpected_proof_phase');
  }
}
