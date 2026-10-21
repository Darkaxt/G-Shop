import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/config/app_config.dart';
import '../../models/library_identity.dart';
import '../../models/transfer_record.dart';
import '../config_storage_service.dart';
import '../installation_index.dart';
import '../metadata/shared_metadata_store.dart';
import '../owned_storage.dart';
import '../verified_file_publication.dart';
import '../saves/automatic_save_backups.dart';
import '../saves/save_capture.dart';
import '../transfer_journal.dart';
import 'migration_activation.dart';
import 'migration_archive.dart';
import 'migration_data.dart';
import 'migration_maintenance.dart';
import 'migration_game_data.dart';

class MigrationLocations {
  final Directory documents, support, configuration, roms;
  final File database;
  final Map<String, String> aliases;
  Directory get privateRoot => Directory(p.join(support.path, 'migrations'));
  const MigrationLocations(
      {required this.documents,
      required this.support,
      required this.configuration,
      required this.roms,
      required this.database,
      this.aliases = const {}});

  /// Resolve platform-owned aliases once at the coordinator boundary, without
  /// relaxing the archive/activation checks for links inside a selected root.
  Future<MigrationLocations> canonical() async {
    Future<String> path(String value) async {
      var ancestor = Directory(value);
      while (!await ancestor.exists()) {
        final parent = ancestor.parent;
        if (parent.path == ancestor.path) {
          throw const MigrationArchiveException('storage_permission');
        }
        ancestor = parent;
      }
      return p.normalize(p.join(await ancestor.resolveSymbolicLinks(),
          p.relative(value, from: ancestor.path)));
    }

    final rebound = <String, String>{...aliases};
    Future<Directory> directory(Directory original) async {
      final resolved = await path(original.absolute.path);
      if (resolved != p.normalize(original.absolute.path)) {
        rebound[original.absolute.path] = resolved;
      }
      return Directory(resolved);
    }

    return MigrationLocations(
        documents: await directory(documents),
        support: await directory(support),
        configuration: await directory(configuration),
        roms: await directory(roms),
        database: File(p.join(await path(database.parent.absolute.path),
            p.basename(database.path))),
        aliases: rebound);
  }
}

/// Full private migration. Existing owners supply joined maintenance and stable
/// save capture; this coordinator owns one export/import and its activation.
/// Public configuration/recipe sharing does not call this credential-bearing path.
class MigrationService extends ChangeNotifier {
  MigrationLocations locations;
  final Future<Database> database;
  final ConfigStorageService configuration;
  final MigrationSettings settings;
  final Future<SharedMetadataStore?> sharedMetadata;
  final Future<List<MigrationCapturedData>> Function() captureAssociated;
  final Future<Future<void> Function(bool resume)> Function() joinOwners;
  final Future<void> Function() closeDatabase;
  final OwnedStorage storage;
  final MigrationArchive archive;
  bool busy = false, restartRequired = false;
  String phase = 'Ready';
  String? issue;
  int completed = 0, total = 0;
  File? lastBackup;
  bool canRecoverPrevious = false, canResume = false;
  File get _pending => File(p.join(locations.privateRoot.path, 'pending.json'));
  static const _pendingSecret = 'rshop.migration.rollback.pending';
  CancelToken? _cancel;
  MigrationService(
      {required this.locations,
      required this.database,
      required this.configuration,
      required this.settings,
      required this.sharedMetadata,
      required this.captureAssociated,
      required this.joinOwners,
      required this.closeDatabase,
      this.storage = const OwnedStorage(),
      MigrationArchive? archive})
      : archive = archive ?? MigrationArchive();

  Future<void> initialize() async {
    final activation =
        await MigrationActivation.existing(locations.privateRoot, settings);
    canRecoverPrevious = await activation.hasPrevious();
    canResume = await _pending.exists();
    final directory = Directory(p.join(locations.privateRoot.path, 'exports'));
    if (await directory.exists()) {
      final files = await directory
          .list()
          .where((file) =>
              file is File &&
              (p.basename(file.path).startsWith('G-Shop-') ||
                  p.basename(file.path).startsWith('R-Shop-')) &&
              file.path.endsWith('.rshop'))
          .cast<File>()
          .toList();
      // Both product names use the same timestamped export format. Comparing
      // the full prefix would always rank an older R-Shop export after G-Shop.
      String timestamp(File file) => p.basename(file.path)
          .replaceFirst(RegExp(r'^[RG]-Shop-'), '');
      files.sort((a, b) => timestamp(a).compareTo(timestamp(b)));
      if (files.isNotEmpty) lastBackup = files.last;
    }
  }

  static Future<void> recoverBeforeBootstrap(Directory privateRoot,
      {MigrationSettings settings = const DeviceMigrationSettings()}) async {
    try {
      final activation =
          await MigrationActivation.existing(privateRoot, settings);
      final marker = File(p.join(privateRoot.path, 'pending.json'));
      if (await marker.exists() && await activation.journal.exists()) {
        final pending = jsonDecode(await marker.readAsString()) as Map;
        final record =
            jsonDecode(await activation.journal.readAsString()) as Map;
        if (record['phase'] == 'committed' &&
            pending['activationId'] == record['id']) {
          await marker.delete();
          final secrets = await settings.readSecrets();
          secrets.remove(_pendingSecret);
          await settings.writeSecrets(secrets);
        }
      }
      await activation.recover();
      await MigrationMaintenance.end();
    } catch (_) {
      throw const MigrationArchiveException('recovery_failed');
    }
  }

  Future<void> recoverPrevious() => _run(() async {
        final activation =
            await MigrationActivation.existing(locations.privateRoot, settings);
        restartRequired = true;
        await closeDatabase();
        await activation.preparePrevious();
        await activation.activate();
      });

  static String newId() =>
      List.generate(16, (_) => Random.secure().nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
  void cancel() => _cancel?.cancel();
  void _check() {
    if (_cancel?.isCancelled == true) {
      throw const MigrationArchiveException('cancelled');
    }
  }

  void _progress(int done, int all) {
    completed = done;
    total = all;
    notifyListeners();
  }

  void _phase(String value) {
    phase = value;
    completed = 0;
    total = 0;
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (busy || restartRequired) throw const MigrationArchiveException('busy');
    busy = true;
    issue = null;
    _cancel = CancelToken();
    _phase('Preparing');
    Future<void> Function(bool)? release;
    try {
      locations = await locations.canonical();
      await MigrationMaintenance.begin();
      release = await joinOwners();
      _check();
      await operation();
      _phase('Complete');
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('Migration phase $phase failed: ${error.runtimeType}'
            '${error is PlatformException ? " (${error.code})" : ""}');
        debugPrintStack(stackTrace: stack, maxFrames: 8);
      }
      issue = error is MigrationArchiveException
          ? error.code
          : error is PlatformException &&
                  {
                    'root_unavailable',
                    'source_changed',
                    'capture_busy',
                    'capture_unavailable',
                    'runtime_unreviewed',
                    'storage_permission',
                    'migration_unavailable'
                  }.contains(error.code)
              ? error.code
              : 'migration_failed';
      _phase(issue == 'cancelled' ? 'Stopped' : 'Could not finish');
      throw MigrationArchiveException(issue!);
    } finally {
      try {
        if (release != null) await release(!restartRequired);
        if (!restartRequired && MigrationMaintenance.active) {
          await MigrationMaintenance.end();
        }
      } finally {
        busy = false;
        _cancel = null;
        notifyListeners();
      }
    }
  }

  Future<File> backup(String password) async {
    late File result;
    await _run(() async {
      final id = newId();
      final requestedWork =
          Directory(p.join(locations.privateRoot.path, 'working-$id'));
      await requestedWork.create(recursive: true);
      // Android path-provider may return /data/data, whose system-owned alias
      // resolves to /data/user/0. Hand the strict archive writer the actual
      // private working directory, just as _tree does for existing data.
      final work = Directory(await requestedWork.resolveSymbolicLinks());
      final captured = <MigrationCapturedData>[];
      try {
        final loaded = await configuration.loadConfigWithRecoveryInfo();
        if (loaded.wasRecovered || loaded.config == null) {
          throw const MigrationArchiveException('configuration_unavailable');
        }
        final config = loaded.config!;
        final db = await database;
        final files = <MigrationFile>[];
        final dbCopy = File(p.join(work.path, 'rshop.db'));
        final preferences = await settings.readPreferences();
        DeviceMigrationSettings.validatePreferences(preferences);
        final credentials = await settings.readSecrets();
        credentials.removeWhere(
            (key, _) => key.startsWith(MigrationActivation.rollbackPrefix));
        final shared = await sharedMetadata;
        if (shared != null) {
          final copy = File(p.join(work.path, 'metadata.sqlite'));
          await shared.snapshotForMigration(copy);
          files.add(MigrationFile('shared/metadata.sqlite', copy));
          await _tree(shared.root, 'shared', files, exclude: {
            'metadata.sqlite',
            'metadata.sqlite-journal',
            'metadata.sqlite-wal',
            'metadata.sqlite-shm'
          });
        }
        // Documents is also used by Flutter's debug engine. Only G-Shop's
        // persistent documents belong in migration, never kernels/snapshots or
        // resource timestamps that could replace the destination runtime.
        for (final name in ['config.json', 'config.json.bak']) {
          final file = File(p.join(locations.documents.path, name));
          if (await file.exists()) {
            files.add(MigrationFile('documents/$name', file));
          }
        }
        await _tree(
            Directory(p.join(locations.documents.path, 'RShop', 'config')),
            'documents/RShop/config',
            files);
        for (final name in [
          'metadata-artwork',
          'cover_thumbnails',
          'socket-media',
          'migration-game-data'
        ]) {
          await _tree(Directory(p.join(locations.support.path, name)),
              'support/$name', files);
        }
        // Unuploaded/conflicting sealed copies remain historical data, not
        // executable captures or restore intents on the destination device.
        for (final name in ['save-captures', 'save-restores']) {
          await _tree(Directory(p.join(locations.support.path, name)),
              'history/$name', files);
        }
        await _tree(locations.configuration, 'configuration', files);
        final journal = TransferJournal(database);
        final index = InstallationIndex(journal, storage: storage);
        final installs = <Map<String, Object?>>[];
        for (final row in await db.query('installed_artifacts')) {
          _check();
          final installed = InstalledArtifact.fromJson(
              (jsonDecode(row['record_json'] as String) as Map)
                  .cast<String, dynamic>());
          final record = await journal.transfer(installed.transferId);
          if (record == null) {
            throw const MigrationArchiveException('installation_changed');
          }
          await index.requireInstallation(record, installed,
              bundleOwner: record.bundleOwner);
          final source =
              File(p.join(installed.destinationRoot, installed.relativePath));
          // Verify original artifact digests as well as the archive's own hash.
          await fingerprintPatchBytes(source.openRead(), _cancel!,
              expectedSize: installed.sizeBytes,
              expected: installed.verifiedChecksums);
          await index.requireInstallation(record, installed,
              bundleOwner: record.bundleOwner);
          final name = 'roms/${installs.length}/content';
          files.add(
              MigrationFile(name, File(await source.resolveSymbolicLinks())));
          installs.add({
            'entry': name,
            'sourceId': installed.id,
            'sourceTransfer': record.id,
            'artifact': installed.artifact.toJson(),
            'root': installed.destinationRoot,
            'relativePath': installed.relativePath,
            'archivePlatformId': record.archivePlatformId,
            'bundleOwner': record.bundleOwner,
            'members': record.bundleMembers.map((m) => m.toJson()).toList(),
            'gameId': installed.gameId,
            'editionId': installed.editionId
          });
        }
        _phase('Reading game data');
        captured.addAll(await captureAssociated());
        await MigrationData.snapshotDatabase(db, dbCopy);
        files.add(MigrationFile('database/rshop.db', dbCopy));
        final associated = <Map<String, Object?>>[];
        for (var i = 0; i < captured.length; i++) {
          final item = captured[i];
          final members = <Map<String, Object?>>[];
          for (final member in item.group.files) {
            final name = 'associated/$i/${member.name}';
            files.add(MigrationFile(
                name, File(await member.file.resolveSymbolicLinks())));
            members.add({
              'entry': name,
              'name': member.name,
              'sha256': member.sha256,
              'size': member.size
            });
          }
          associated.add({
            'mapping': jsonDecode(item.mapping.encode()),
            'scope': item.scope,
            'sourceJobKey': item.sourceJobKey,
            'sourceDevice': item.group.deviceId,
            'emulatorVersion': item.group.emulatorVersion,
            'coreVersion': item.group.coreVersion,
            'members': members
          });
        }
        _check();
        final exports =
            Directory(p.join(locations.privateRoot.path, 'exports'));
        await exports.create(recursive: true);
        result = File(p.join(exports.path,
            'G-Shop-${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.rshop'));
        _phase('Backing up');
        await archive.write(result,
            password: password,
            files: files,
            state: {
              'schema': 1,
              'configuration': config.toJson(),
              'preferences': preferences,
              'credentials': credentials,
              'installations': installs,
              'associated': associated,
              'roots': {
                'documents': locations.documents.path,
                'support': locations.support.path,
                'configuration': locations.configuration.path,
                if (shared != null) 'shared': shared.root.path
              },
              'rootAliases': locations.aliases,
            },
            progress: _progress,
            checkCancellation: _check);
        lastBackup = result;
      } finally {
        for (final item in captured) {
          await SaveCapture().retireCapture(item.group.captureId);
        }
        await work.delete(recursive: true);
      }
    });
    return result;
  }

  Future<void> restore(File file, String password) => _run(() async {
        if (await _pending.exists()) {
          throw const MigrationArchiveException('restore_pending');
        }
        _phase('Checking backup');
        final incoming = await archive.read(file,
            password: password,
            privateRoot:
                Directory(p.join(locations.privateRoot.path, 'incoming')),
            progress: _progress,
            checkCancellation: _check);
        try {
          _validateSetup(incoming.state);
        } catch (_) {
          await incoming.root.delete(recursive: true);
          rethrow;
        }
        final id = newId();
        // The resumable manifest contains credentials and therefore lives only
        // in the destination Keystore. The disk marker contains no secrets.
        await settings.writeSecrets({
          ...await settings.readSecrets(),
          _pendingSecret:
              jsonEncode({'state': incoming.state, 'entries': incoming.entries})
        });
        await _savePending({
          'schema': 1,
          'id': id,
          'root': incoming.root.path,
          'prepared': false
        });
        canResume = true;
        await _restoreSnapshot(incoming, id, prepared: false);
      });

  Future<void> resume() => _run(() async {
        final pending = await _readPending();
        final encoded = (await settings.readSecrets())[_pendingSecret];
        if (encoded == null ||
            encoded.length > MigrationArchive.maxManifestBytes) {
          throw const MigrationArchiveException('invalid_recovery_record');
        }
        final manifest = (jsonDecode(encoded) as Map).cast<String, dynamic>();
        final snapshot = MigrationSnapshot(
            Directory(pending['root'] as String),
            (manifest['state'] as Map).cast<String, dynamic>(),
            (manifest['entries'] as List)
                .map((v) => (v as Map).cast<String, dynamic>())
                .toList());
        // Independently recheck extracted bytes after a process death/external write.
        for (final entry in snapshot.entries) {
          final file = snapshot.file(entry['name'] as String);
          await fingerprintPatchBytes(file.openRead(), _cancel!,
              expectedSize: entry['size'] as int,
              expected: {'sha256': entry['sha256'] as String});
        }
        await _restoreSnapshot(snapshot, pending['id'] as String,
            prepared: pending['prepared'] == true);
      });

  Future<Map<String, dynamic>> _readPending() async {
    if (await _pending.length() > 4096) {
      throw const MigrationArchiveException('invalid_recovery_record');
    }
    final value = (jsonDecode(await _pending.readAsString()) as Map)
        .cast<String, dynamic>();
    final root = value['root'];
    if (value['schema'] != 1 ||
        value['id'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['id']) ||
        root is! String ||
        !p.isWithin(p.join(locations.privateRoot.path, 'incoming'), root) ||
        value['prepared'] is! bool) {
      throw const MigrationArchiveException('invalid_recovery_record');
    }
    return value;
  }

  Future<void> _savePending(Map<String, Object?> value) async {
    final next = File('${_pending.path}.new');
    await next.writeAsString(jsonEncode(value), flush: true);
    await next.rename(_pending.path);
  }

  Future<void> _restoreSnapshot(MigrationSnapshot incoming, String id,
      {required bool prepared}) async {
    final state = incoming.state;
    _validateSetup(state);
    final config = AppConfig.fromJson(
        (state['configuration'] as Map).cast<String, dynamic>());
    final gameRoot =
        Directory(p.join(locations.roms.path, 'RShopMigration-$id'));
    final sharedRoot = Directory(p.join(
        locations.configuration.parent.path, 'migrations', id, 'metadata'));
    final roots = (state['roots'] as Map).cast<String, String>();
    final rebind = <String, String>{
      roots['documents']!: locations.documents.path,
      roots['support']!: locations.support.path,
      '${roots['support']!}/save-captures': p.join(
          locations.support.path, 'migration-history', id, 'save-captures'),
      '${roots['support']!}/save-restores': p.join(
          locations.support.path, 'migration-history', id, 'save-restores'),
      roots['configuration']!: locations.configuration.path,
      if (roots['shared'] != null) roots['shared']!: sharedRoot.path,
    };
    final aliases = (state['rootAliases'] as Map?)?.cast<String, String>() ??
        const <String, String>{};
    for (final entry in aliases.entries) {
      final rootPaths = MigrationPaths(rebind);
      final target = rootPaths.value(entry.value) as String;
      if (target != entry.value) rebind[entry.key] = target;
    }
    final destinationVolume =
        RegExp(r'^/storage/(?:emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})')
            .firstMatch(locations.roms.path)
            ?.group(0);
    if (destinationVolume != null) {
      for (final group in state['associated'] as List) {
        final directory = (group as Map)['mapping']['directory'];
        if (directory is String) {
          final oldVolume = RegExp(r'^/storage/[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}')
              .firstMatch(directory)
              ?.group(0);
          if (oldVolume != null) {
            rebind.putIfAbsent(oldVolume, () => destinationVolume);
          }
        }
      }
    }
    final oldRomRoot = (state['preferences'] as Map)['rom_path'];
    if (oldRomRoot is String && oldRomRoot.isNotEmpty) {
      rebind[oldRomRoot] = gameRoot.path;
    }
    for (final system in config.systems) {
      rebind.putIfAbsent(
          system.targetFolder, () => p.join(gameRoot.path, system.id));
    }
    final installs = (state['installations'] as List)
        .map((v) => (v as Map).cast<String, dynamic>())
        .toList();
    for (final install in installs) {
      final source = install['root'] as String;
      if (!rebind.keys
          .any((root) => source == root || source.startsWith('$root/'))) {
        rebind[source] = p.join(gameRoot.path, 'other-${rebind.length}');
      }
      MigrationArchive.checkName(install['relativePath'] as String);
      incoming.file(install['entry'] as String);
      RemoteArtifact.fromJson(
          (install['artifact'] as Map).cast<String, dynamic>());
    }
    final paths = MigrationPaths(rebind);
    for (final install in installs) {
      final target = p.join(paths.value(install['root']) as String,
          install['relativePath'] as String);
      if (!p.isWithin(gameRoot.path, target)) {
        throw const MigrationArchiveException('unsafe_game_path');
      }
    }
    for (final entry in incoming.entries) {
      final name = entry['name'] as String;
      if (!(name == 'database/rshop.db' ||
          name == 'documents/config.json' ||
          name == 'documents/config.json.bak' ||
          name.startsWith('documents/RShop/config/') ||
          name.startsWith('support/metadata-artwork/') ||
          name.startsWith('support/cover_thumbnails/') ||
          name.startsWith('support/socket-media/') ||
          name.startsWith('support/migration-game-data/') ||
          name.startsWith('configuration/') ||
          name.startsWith('shared/') ||
          name.startsWith('roms/') ||
          name.startsWith('associated/') ||
          name.startsWith('history/save-captures/') ||
          name.startsWith('history/save-restores/'))) {
        throw const MigrationArchiveException('unsupported_entry');
      }
    }
    // Validate every associated destination before any game publication.
    for (final raw in state['associated'] as List) {
      final group = raw as Map;
      final mapping = AutomaticSaveMapping.decode(
          jsonEncode(paths.value(group['mapping'])));
      final directory = mapping.directory;
      if (group['scope'] is! Map) {
        throw const MigrationArchiveException('invalid_game_data');
      }
      if (!directory.startsWith('/storage/') &&
          !directory.startsWith('/data/user/0/')) {
        throw const MigrationArchiveException('unsafe_game_data_path');
      }
      if (directory.split('/').contains('..') || directory.contains('\u0000')) {
        throw const MigrationArchiveException('unsafe_game_data_path');
      }
      for (final raw in group['members'] as List) {
        final member = raw as Map;
        MigrationArchive.checkName(member['name'] as String);
        incoming.file(member['entry'] as String);
      }
    }
    // Companion/save folders inside the new managed ROM generation have no
    // emulator-created directory yet. Create only these validated owned roots;
    // other emulator locations keep their normal native access/consent path.
    for (final raw in state['associated'] as List) {
      final mapping = AutomaticSaveMapping.decode(
          jsonEncode(paths.value((raw as Map)['mapping'])));
      if (p.isWithin(gameRoot.path, mapping.directory)) {
        await _createDestinationDirectory(mapping.directory);
      }
    }
    File? sharedFile;
    if (roots['shared'] != null) {
      sharedFile = File(p.join(incoming.root.path, 'prepared-metadata.sqlite'));
      await incoming.file('shared/metadata.sqlite').copy(sharedFile.path);
      final shared = await openDatabase(sharedFile.path, singleInstance: false);
      try {
        if (await shared.getVersion() != 7) {
          throw const MigrationArchiveException('unsupported_metadata');
        }
        await MigrationData.rebindDatabase(shared, paths: paths);
      } finally {
        await shared.close();
      }
    }
    final stagedDbFile = File(p.join(incoming.root.path, 'prepared-rshop.db'));
    if (!prepared) {
      await incoming.file('database/rshop.db').copy(stagedDbFile.path);
    }
    final associatedFiles = <String, File>{};
    final stagedDb =
        await openDatabase(stagedDbFile.path, singleInstance: false);
    try {
      if (!prepared) {
        await MigrationData.prepareDatabase(stagedDb, paths: paths);
        await _savePending({
          'schema': 1,
          'id': id,
          'root': incoming.root.path,
          'prepared': true
        });
      }
      _check();
      _phase('Restoring games');
      await _restoreInstallations(incoming, installs, paths, stagedDb, id);
      await _restoreMappings(stagedDb);
      await MigrationGameData.install(stagedDb);
      for (var i = 0; i < (state['associated'] as List).length; i++) {
        final group = (state['associated'] as List)[i] as Map;
        final branchId = '$id-$i';
        final members = <Map<String, Object?>>[];
        for (final raw in group['members'] as List) {
          final member = raw as Map;
          final name = member['name'] as String;
          MigrationArchive.checkName(name);
          final sourceName = member['entry'] as String;
          final actual =
              incoming.entries.singleWhere((e) => e['name'] == sourceName);
          if (member['size'] != actual['size'] ||
              member['sha256'] != actual['sha256']) {
            throw const MigrationArchiveException('invalid_game_data');
          }
          final target = p.join(
              locations.support.path, 'migration-game-data', branchId, name);
          associatedFiles[target] = incoming.file(sourceName);
          members.add({
            'name': name,
            'path': target,
            'size': member['size'],
            'sha256': member['sha256']
          });
        }
        if (members.isEmpty) continue;
        final scope =
            (paths.value(group['scope']) as Map).cast<String, Object?>();
        final mapping = AutomaticSaveMapping.decode(
            jsonEncode(paths.value(group['mapping'])));
        if (scope.containsKey('resource')) {
          scope['resource'] =
              mapping.saveRootConfiguration?.sharedResourceKey ??
                  (mapping.pcsxCard?.isShared == true
                      ? mapping.pcsxLayout!.sharedResourceKey(mapping.pcsxCard!)
                      : scope['resource']);
        }
        final data = {
          'schema': 1,
          'id': branchId,
          'state': 'pending',
          'scope': scope,
          'mapping': paths.value(group['mapping']),
          'sourceDevice': group['sourceDevice'],
          'sourceJobKey': group['sourceJobKey'],
          'emulatorVersion': group['emulatorVersion'],
          'coreVersion': group['coreVersion'],
          'members': members
        };
        await stagedDb.insert(
            'migration_game_data',
            {
              'branch_id': branchId,
              'scope_key': MigrationGameData.scopeKey(scope),
              'state': 'pending',
              'created_at': DateTime.now().millisecondsSinceEpoch,
              'record_json': jsonEncode(data)
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    } finally {
      await stagedDb.close();
    }
    final activations = <String, File>{
      locations.database.path: stagedDbFile,
      ...associatedFiles
    };
    final allowed = <Directory>[
      locations.documents,
      locations.support,
      locations.database.parent,
      locations.configuration,
      sharedRoot
    ];
    for (final entry in incoming.entries) {
      final name = entry['name'] as String;
      String? target;
      if (name.startsWith('documents/')) {
        target = p.join(locations.documents.path, name.substring(10));
      } else if (name.startsWith('support/')) {
        target = p.join(locations.support.path, name.substring(8));
      } else if (name.startsWith('configuration/')) {
        target = p.join(locations.configuration.path, name.substring(14));
      } else if (name.startsWith('shared/')) {
        target = p.join(sharedRoot.path, name.substring(7));
      } else if (name.startsWith('history/')) {
        final root =
            Directory(p.join(locations.support.path, 'migration-history', id));
        target = p.join(root.path, name.substring(8));
      }
      if (target != null) {
        activations[target] = name == 'shared/metadata.sqlite'
            ? sharedFile!
            : incoming.file(name);
      }
    }
    // Configuration is regenerated from the parsed model, not an arbitrary file
    // from the archive. Cloud identities/credentials are retained verbatim.
    final configFile =
        File(p.join(incoming.root.path, 'activated-config.json'));
    final reboundConfig = config.copyWith(
        systems: config.systems
            .map((system) => system.copyWith(
                targetFolder: paths.value(system.targetFolder) as String))
            .toList());
    await configFile.writeAsString(jsonEncode(reboundConfig.toJson()),
        flush: true);
    activations[p.join(locations.documents.path, 'config.json')] = configFile;
    final preferences =
        (paths.value(state['preferences']) as Map).cast<String, Object?>();
    preferences['rom_path'] = gameRoot.path;
    preferences.remove('download_queue');
    for (final key
        in preferences.keys.where((k) => k.startsWith('last_sync_')).toList()) {
      preferences.remove(key);
    }
    final activation = MigrationActivation(
        privateRoot: locations.privateRoot,
        settings: settings,
        allowedRoots: allowed);
    _check();
    _phase('Restoring setup');
    // Closing SQLite may checkpoint its WAL and change the old main file.
    // Capture activation's old-file hashes only after that actual close.
    restartRequired = true;
    await closeDatabase();
    await activation.prepare(
        files: activations,
        preferences: preferences,
        secrets: (state['credentials'] as Map).cast<String, String>());
    final activationRecord =
        jsonDecode(await activation.journal.readAsString()) as Map;
    await _savePending({
      'schema': 1,
      'id': id,
      'root': incoming.root.path,
      'prepared': true,
      'activationId': activationRecord['id']
    });
    await activation.activate();
    await _pending.delete();
    final savedSecrets = await settings.readSecrets();
    savedSecrets.remove(_pendingSecret);
    await settings.writeSecrets(savedSecrets);
    canResume = false;
    // The native maintenance flag remains set until recovery/new bootstrap. No
    // old engine may upload saves or evict games against freshly activated data.
  }

  static void _validateSetup(Map<String, dynamic> state) {
    if (state['schema'] != 1 ||
        state['configuration'] is! Map ||
        state['roots'] is! Map ||
        state['preferences'] is! Map ||
        state['credentials'] is! Map ||
        state['installations'] is! List ||
        state['associated'] is! List) {
      throw const MigrationArchiveException('unsupported_setup');
    }
    final config = AppConfig.fromJson(
        (state['configuration'] as Map).cast<String, dynamic>());
    if (config.version != AppConfig.currentVersion) {
      throw const MigrationArchiveException('unsupported_setup');
    }
    final roots = (state['roots'] as Map).cast<String, String>();
    if (!roots.keys
        .toSet()
        .containsAll({'documents', 'support', 'configuration'})) {
      throw const MigrationArchiveException('invalid_root_mapping');
    }
    DeviceMigrationSettings.validatePreferences(
        (state['preferences'] as Map).cast<String, Object?>());
    (state['credentials'] as Map).cast<String, String>().forEach((key, value) {
      if (key.startsWith(MigrationActivation.rollbackPrefix)) {
        throw const MigrationArchiveException('invalid_credentials');
      }
    });
  }

  Future<void> _restoreInstallations(
      MigrationSnapshot snapshot,
      List<Map<String, dynamic>> source,
      MigrationPaths paths,
      Database db,
      String id) async {
    final journal = TransferJournal(Future.value(db));
    final publisher = VerifiedFilePublication(journal, storage: storage);
    final ids = {
      for (var i = 0; i < source.length; i++)
        source[i]['sourceTransfer'] as String: 'migration-$id-$i'
    };
    if (ids.length != source.length) {
      throw const MigrationArchiveException('duplicate_installation');
    }
    final reservationOrder = [
      ...source.where((e) => e['bundleOwner'] == null),
      ...source.where((e) => e['bundleOwner'] != null)
    ];
    for (final entry in reservationOrder) {
      _check();
      final root = paths.value(entry['root']) as String;
      final relative = entry['relativePath'] as String;
      final artifact = RemoteArtifact.fromJson(
          (entry['artifact'] as Map).cast<String, dynamic>());
      final transferId = ids[entry['sourceTransfer']]!;
      // Native publication opens an existing root; migration owns creation of
      // these already-validated, generation-specific destination directories.
      await _createDestinationDirectory(root);
      final plan = await storage.prepare(root);
      final members = ((entry['members'] as List?) ?? const []).map((raw) {
        final member =
            TransferBundleMember.fromJson((raw as Map).cast<String, dynamic>());
        if (!ids.containsKey(member.transferId)) {
          throw const MigrationArchiveException('incomplete_bundle');
        }
        return TransferBundleMember(
            transferId: ids[member.transferId]!,
            artifact: member.artifact,
            relativePath: member.relativePath);
      }).toList();
      if (entry['bundleOwner'] != null &&
          !ids.containsKey(entry['bundleOwner'])) {
        throw const MigrationArchiveException('incomplete_bundle');
      }
      if (await journal.transfer(transferId) == null) {
        await journal.create(TransferRecord(
            id: transferId,
            artifact: artifact,
            destinationRoot: root,
            relativePath: relative,
            stagePath: plan.stagePath(transferId),
            archivePlatformId: entry['archivePlatformId'] as String?,
            bundleOwner:
                entry['bundleOwner'] == null ? null : ids[entry['bundleOwner']],
            bundleMembers: members));
      }
    }
    final publicationOrder = [
      ...source.where((e) => e['bundleOwner'] != null),
      ...source.where((e) => e['bundleOwner'] == null)
    ];
    final identities = <String, String>{};
    var done = 0;
    for (final entry in publicationOrder) {
      _check();
      final record = await publisher.publish(
          transferId: ids[entry['sourceTransfer']]!,
          artifact: RemoteArtifact.fromJson(
              (entry['artifact'] as Map).cast<String, dynamic>()),
          output: snapshot.file(entry['entry'] as String),
          targetRoot: paths.value(entry['root']) as String,
          filename: entry['relativePath'] as String,
          cancellation: _cancel!,
          gameId: entry['gameId'] as String?,
          editionId: entry['editionId'] as String?);
      identities[entry['sourceTransfer'] as String] = record.id;
      identities[entry['sourceId'] as String] = record.id;
      _progress(++done, source.length);
    }
    await MigrationData.rebindDatabase(db,
        paths: MigrationPaths(paths.roots, identities: identities));
    // Source usage stays in migration_cache_usage as history. Native publication
    // records this destination's real installation lifetime; copying old expiry
    // stamps would immediately evict freshly restored games on first startup.
  }

  Future<void> _restoreMappings(Database db) async {
    final tables =
        (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
            .map((v) => v['name'])
            .toSet();
    if (!tables.contains('migration_save_mappings')) return;
    for (final row in await db.query('migration_save_mappings')) {
      final mapping = AutomaticSaveMapping.decode(row['record_json'] as String);
      await db.insert(
          'automatic_save_backups',
          {
            'mapping_key': mapping.key,
            'record_json': mapping.encode(),
            'enabled': row['enabled'],
            'requested': 0,
            'handled': 0,
            'outcome': 'migrated',
            'issue': null
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _createDestinationDirectory(String root) async {
    final destination = Directory(root);
    var ancestor = destination;
    while (!await ancestor.exists()) {
      if (ancestor.parent.path == ancestor.path) {
        throw const MigrationArchiveException('storage_permission');
      }
      ancestor = ancestor.parent;
    }
    if (p.normalize(await ancestor.resolveSymbolicLinks()) !=
        p.normalize(ancestor.absolute.path)) {
      throw const MigrationArchiveException('unsafe_game_path');
    }
    await destination.create(recursive: true);
  }

  Future<void> _tree(
      Directory directory, String prefix, List<MigrationFile> files,
      {Set<String> exclude = const {}}) async {
    if (!await directory.exists()) return;
    final canonical = Directory(await directory.resolveSymbolicLinks());
    await for (final file
        in canonical.list(recursive: true, followLinks: false)) {
      _check();
      if (file is Link) throw const MigrationArchiveException('unsafe_source');
      if (file is! File) continue;
      final relative =
          p.relative(file.path, from: canonical.path).replaceAll('\\', '/');
      if (exclude.contains(relative)) continue;
      files.add(MigrationFile('$prefix/$relative', file));
    }
  }
}
