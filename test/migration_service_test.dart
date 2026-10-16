import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/models/config/app_config.dart';
import 'package:retro_eshop/services/config_storage_service.dart';
import 'package:retro_eshop/services/migration/migration_service.dart';
import 'package:retro_eshop/services/migration/migration_maintenance.dart';
import 'migration_activation_test.dart' show MemorySettings;

class _InterruptedSettings extends MemorySettings {
  bool interrupt = true;
  @override
  Future<void> writePreferences(Map<String, Object?> values) async {
    if (interrupt) {
      interrupt = false;
      throw StateError('simulated process boundary');
    }
    await super.writePreferences(values);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('migration-service-');
  });
  tearDown(() async {
    MigrationMaintenance.active = false;
    await root.delete(recursive: true);
  });

  Future<
      ({
        MigrationService service,
        MemorySettings settings,
        MigrationLocations locations
      })> setup(String name, {MemorySettings? settings}) async {
    final base = Directory(p.join(root.path, name));
    final locations = MigrationLocations(
        documents: Directory(p.join(base.path, 'documents')),
        support: Directory(p.join(base.path, 'support')),
        configuration: Directory(p.join(base.path, 'config')),
        roms: Directory(p.join(base.path, 'roms')),
        database: File(p.join(base.path, 'database', 'rshop.db')));
    for (final dir in [
      locations.documents,
      locations.support,
      locations.configuration,
      locations.roms,
      locations.database.parent
    ]) {
      await dir.create(recursive: true);
    }
    final db = await openDatabase(locations.database.path);
    await db.setVersion(41);
    for (final table in ['games', 'installed_artifacts', 'transfer_records']) {
      await db.execute(
          'CREATE TABLE IF NOT EXISTS $table(id TEXT,record_json TEXT)');
    }
    final config = ConfigStorageService(
        directoryProvider: () async => locations.documents);
    await config.saveConfig('{"version":3,"systems":[],"sources":[]}');
    final values = settings ?? MemorySettings();
    final service = MigrationService(
        locations: locations,
        database: Future.value(db),
        configuration: config,
        settings: values,
        sharedMetadata: Future.value(null),
        captureAssociated: () async => [],
        joinOwners: () async => (_) async {},
        closeDatabase: db.close);
    return (service: service, settings: values, locations: locations);
  }

  test(
      'complete setup export/import resumes its original interrupted activation',
      () async {
    final source = await setup('source');
    source.settings.preferences = {
      'favorites': ['game'],
      'rom_path': source.locations.roms.path,
      'artwork':
          p.join(source.locations.support.path, 'metadata-artwork', 'cover.png')
    };
    source.settings.secrets = {
      'screenscraper': 'private-api-value',
      'igdb': 'other-private-value'
    };
    final art = File(
        p.join(source.locations.support.path, 'metadata-artwork', 'cover.png'));
    await art.parent.create();
    await art.writeAsBytes([1, 2, 3]);
    final runtime = File(p.join(
        source.locations.documents.path, 'flutter_assets', 'kernel_blob.bin'));
    await runtime.parent.create();
    await runtime.writeAsString('source runtime must never migrate');
    await File(
            p.join(source.locations.documents.path, 'res_timestamp-15-source'))
        .writeAsString('not user data');
    final archive = await source.service.backup('portable backup password');
    expect(
        latin1
            .decode(await archive.readAsBytes())
            .contains('private-api-value'),
        false);
    final destination =
        await setup('destination', settings: _InterruptedSettings());
    await expectLater(
        destination.service.restore(archive, 'portable backup password'),
        throwsException);
    expect(destination.settings.secrets['api'], 'destination-secret');
    expect(destination.settings.preferences, {
      'favorites': ['destination-game']
    });
    expect(destination.service.canResume, true);
    // New engine/app-data startup settles the old activation before any owner
    // boots, then resumes the original authenticated private generation.
    await MigrationService.recoverBeforeBootstrap(
        destination.locations.privateRoot,
        settings: destination.settings);
    final reopened = await openDatabase(destination.locations.database.path);
    final resumed = MigrationService(
        locations: destination.locations,
        database: Future.value(reopened),
        configuration: ConfigStorageService(
            directoryProvider: () async => destination.locations.documents),
        settings: destination.settings,
        sharedMetadata: Future.value(null),
        captureAssociated: () async => [],
        joinOwners: () async => (_) async {},
        closeDatabase: reopened.close);
    await resumed.initialize();
    await resumed.resume();
    expect(resumed.canResume, false);
    expect(destination.settings.secrets['screenscraper'], 'private-api-value');
    expect(destination.settings.secrets['igdb'], 'other-private-value');
    expect(destination.settings.preferences['favorites'], ['game']);
    expect(
        destination.settings.preferences['artwork'],
        p.join(destination.locations.support.path, 'metadata-artwork',
            'cover.png'));
    expect(
        await File(destination.settings.preferences['artwork'] as String)
            .readAsBytes(),
        [1, 2, 3]);
    expect(
        await ConfigStorageService(
                directoryProvider: () async => destination.locations.documents)
            .loadConfig(),
        isA<AppConfig>());
    expect(
        await Directory(
                p.join(destination.locations.documents.path, 'flutter_assets'))
            .exists(),
        false);
    expect(
        await File(p.join(destination.locations.documents.path,
                'res_timestamp-15-source'))
            .exists(),
        false);
    await (await source.service.database).close();
  });
}
