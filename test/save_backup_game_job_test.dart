import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/services/migration/migration_game_data.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_eshop/models/config/source.dart';
import 'package:retro_eshop/models/config/drive_source_config.dart';
import 'package:retro_eshop/services/saves/automatic_save_backups.dart';
import 'package:retro_eshop/services/saves/save_backup_setup.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/save_backup_manifest.dart';
import 'package:retro_eshop/models/retroarch_battery_route.dart';
import 'package:retro_eshop/models/pcsx_save_layout.dart';
import 'package:retro_eshop/models/save_root_configuration.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/saves/drive_save_backup_area.dart';
import 'package:retro_eshop/services/saves/drive_save_backup_generation.dart';
import 'package:retro_eshop/services/saves/save_capture.dart';
import 'package:retro_eshop/services/saves/save_backup_game_job.dart';
import 'package:retro_eshop/features/settings/save_backup_settings_screen.dart';
import 'helpers/pump_helpers.dart';

class _Driver implements DriveAuthorizationDriver {
  @override
  Future<String?> authenticate({required bool interactive}) async => 'account';
  @override
  Future<String?> authorize(String accountId, List<String> scopes,
          {required bool interactive}) async =>
      'token';
  @override
  Future<void> clearRejectedToken(String accountId, String token) async {}
  @override
  Future<void> signOut({required bool revoke}) async {}
}

class _Capture extends SaveCapture {
  String deviceId = 'device';
  int captures = 0;
  bool includeRtc = false;
  bool localAbsent = false;
  String digest = 'b' * 64;
  final staged = <String>[];
  final stagedNames = <String>[];
  final stagedDirectories = <String?>[];
  final restored = <({String id, String rollback})>[];
  String? publicationIssue, captureIssue;
  final started = Completer<void>();
  Completer<void>? held;
  Map<String, CapturedSaveGroup> sealed = {};
  final ppssppSources = <String>[];
  final melonSources = <String>[];
  final pcsxSources = <String>[];
  final pcsxRestores = <String>[];
  bool companionNested = false;
  SaveRootConfiguration? configuredRoot;
  final companionCaptureMembers = <Set<String>>[];
  String runtimeFingerprint = 'd' * 64;
  @override
  Future<RomCompanionSnapshot> reviewRomCompanions(
          {required Map<String, Object> grant,
          RomCompanionSnapshot? before}) async =>
      RomCompanionSnapshot.decode({
        'binding': 'a' * 64,
        'directory':
            configuredRoot?.directory ?? '/storage/emulated/0/Roms/gba',
        'romName': configuredRoot?.logicalRomName ?? 'Game.7z',
        'directoryIdentity': [1, 2],
        'files': {
          for (final name in configuredRoot?.files ??
              [
                'Game.png',
                'Game.cache',
                if (companionNested) 'Game/images/shot.png'
              ])
            name: [1, 3, 4, 100, 0]
        },
        'changed': <String>[],
        if (configuredRoot != null) 'saveRoot': configuredRoot!.toJson(),
      });

  @override
  Future<CapturedSaveGroup> captureRomCompanions(
      {required String captureId,
      required Map<String, Object> grant,
      required RomCompanionSnapshot snapshot,
      required Set<String> members,
      required String emulatorPackage,
      bool restoreBaseline = false}) async {
    companionCaptureMembers.add(Set.of(members));
    if (captureIssue != null) throw PlatformException(code: captureIssue!);
    if (sealed[captureId] case final previous?) return previous;
    captures++;
    final names = members.toList()..sort();
    return sealed[captureId] = CapturedSaveGroup(
        captureId,
        deviceId,
        '1.22.2_GIT',
        [
          if (!localAbsent)
            for (final name in names)
              CapturedSaveFile(
                  name,
                  _MemorySaveFile('/private/$captureId/$name', [1, 2, 3, 4]),
                  4,
                  digest),
        ],
        coreVersion: runtimeFingerprint,
        localWasAbsent: localAbsent && restoreBaseline);
  }

  @override
  Future<void> stageRomCompanionRestore(
      {required String restoreId,
      required Map<String, Object> grant,
      required RomCompanionSnapshot snapshot,
      required String emulatorPackage,
      Map<String, String>? expectedRuntime,
      required List<RestoreSaveMember> members}) async {
    for (final member in members) {
      var received = 0;
      await for (final chunk in member.bytes) {
        received += chunk.length;
      }
      expect(received, member.size);
    }
    stagedGroups.add(members.map((member) => member.name).toList());
    staged.add(restoreId);
  }

  @override
  Future<CapturedSaveGroup> capturePcsx(
      {required String captureId,
      required Map<String, Object> grant,
      required PcsxSaveLayout layout,
      required PcsxSaveCard card,
      bool restoreBaseline = false}) async {
    if (captureIssue != null) throw PlatformException(code: captureIssue!);
    if (sealed[captureId] case final previous?) return previous;
    captures++;
    pcsxSources.add('${layout.directory}/${card.name}');
    return sealed[captureId] = CapturedSaveGroup(
        captureId,
        'device',
        '1.22.2_GIT',
        [
          if (!localAbsent)
            CapturedSaveFile(
                card.name!,
                _MemorySaveFile(
                    '/private/$captureId/member-0', List.filled(131072, 7)),
                131072,
                digest)
        ],
        localWasAbsent: localAbsent && restoreBaseline);
  }

  final batteryRoutes = <RetroArchBatteryRoute>[];
  @override
  Future<void> stagePcsxRestore(
      {required String restoreId,
      required Map<String, Object> grant,
      required PcsxSaveLayout layout,
      required PcsxSaveCard card,
      required int size,
      required String sha256,
      required Stream<Uint8List> bytes}) async {
    var received = 0;
    await for (final chunk in bytes) {
      received += chunk.length;
    }
    expect(received, 131072);
    expect(size, 131072);
    pcsxRestores.add('${layout.directory}/${card.slot}/${card.name}');
    staged.add(restoreId);
  }

  @override
  Future<void> publishPcsxRestore(
      {required String restoreId,
      required String rollbackCaptureId,
      required Map<String, Object> grant,
      required PcsxSaveLayout layout,
      required PcsxSaveCard card}) async {
    if (publicationIssue != null) {
      throw PlatformException(code: publicationIssue!);
    }
    restored.add((id: restoreId, rollback: rollbackCaptureId));
  }

  int batterySize = 4;
  final restoreRoutes = <RetroArchBatteryRoute>[];
  final stagedGroups = <List<String>>[];
  int appInfoOpens = 0;
  final retired = <String>[];
  String? retirementIssue;
  Future<void> Function(String)? beforeRetirement;
  @override
  Future<void> retireCapture(String captureId) async {
    await beforeRetirement?.call(captureId);
    if (retirementIssue != null) {
      throw PlatformException(code: retirementIssue!);
    }
    retired.add(captureId);
    sealed.remove(captureId);
  }

  @override
  Future<void> openPpssppAppInfo() async {
    appInfoOpens++;
  }

  @override
  Future<CapturedSaveGroup> capturePpsspp(
      {required String captureId,
      required String directory,
      required String name,
      bool restoreBaseline = false}) async {
    if (sealed[captureId] case final previous?) return previous;
    captures++;
    ppssppSources.add('$directory/$name');
    if (!started.isCompleted) started.complete();
    await held?.future;
    return sealed[captureId] = CapturedSaveGroup(
        captureId,
        'device',
        'v1.20.4',
        [
          if (!localAbsent)
            CapturedSaveFile(
                name, File('/private/$captureId/member-0'), 4, digest)
        ],
        localWasAbsent: localAbsent && restoreBaseline);
  }

  @override
  Future<CapturedSaveGroup> capturePpssppCompanion(
          {required String captureId,
          required String directory,
          required String name,
          bool restoreBaseline = false}) =>
      capturePpsspp(
          captureId: captureId,
          directory: directory,
          name: name,
          restoreBaseline: restoreBaseline);

  @override
  Future<List<String>> retroArchNames() async => ['Game.srm'];
  @override
  Future<CapturedSaveGroup> captureMelon(
      {required String captureId,
      required String directory,
      required String name,
      bool restoreBaseline = false}) async {
    if (captureIssue != null) throw PlatformException(code: captureIssue!);
    if (sealed[captureId] case final previous?) return previous;
    captures++;
    melonSources.add('$directory/$name');
    return sealed[captureId] = CapturedSaveGroup(
        captureId, 'device', '0.8.0.rc2', [
      CapturedSaveFile(name, File('/private/$captureId/member-0'), 4, digest)
    ]);
  }

  @override
  Future<CapturedSaveGroup> captureRetroArch(
      {required String captureId,
      required String name,
      RetroArchBatteryRoute route = RetroArchBatteryRoute.mgba,
      bool restoreBaseline = false}) async {
    batteryRoutes.add(route);
    if (captureIssue != null) throw PlatformException(code: captureIssue!);
    if (sealed[captureId] case final previous?) return previous;
    captures++;
    if (!started.isCompleted) started.complete();
    await held?.future;
    return sealed[captureId] = CapturedSaveGroup(
        captureId,
        deviceId,
        '1.22.2_GIT',
        [
          if (!localAbsent)
            CapturedSaveFile(name, File('/private/$captureId/member-0'),
                batterySize, digest),
          if (includeRtc && !localAbsent)
            CapturedSaveFile(name.replaceFirst(RegExp(r'\.srm$'), '.rtc'),
                File('/private/$captureId/member-1'), 4, 'd' * 64)
        ],
        localWasAbsent: localAbsent && restoreBaseline);
  }

  @override
  Future<void> cancel(String captureId) async {
    if (held?.isCompleted == false) {
      held!.completeError(StateError('cancelled'));
    }
  }

  @override
  Future<void> stageRestore(
      {required String restoreId,
      required String name,
      required int size,
      required String sha256,
      String? ppssppDirectory,
      bool ppssppCompanion = false,
      String? melonDirectory,
      RetroArchBatteryRoute retroArchRoute = RetroArchBatteryRoute.mgba,
      required Stream<Uint8List> bytes}) async {
    await bytes.drain<void>(); // final transport verification must finish
    staged.add(restoreId);
    stagedNames.add(name);
    stagedDirectories.add(melonDirectory ?? ppssppDirectory);
    restoreRoutes.add(retroArchRoute);
  }

  @override
  Future<void> publishRestore(
      {required String restoreId, required String rollbackCaptureId}) async {
    if (publicationIssue != null) {
      throw PlatformException(code: publicationIssue!);
    }
    restored.add((id: restoreId, rollback: rollbackCaptureId));
  }

  @override
  Future<void> stageRetroArchGroupRestore(
      {required String restoreId,
      required String name,
      RetroArchBatteryRoute route = RetroArchBatteryRoute.mgba,
      required List<RestoreSaveMember> members}) async {
    for (final member in members) {
      await member.bytes.drain<void>();
    }
    stagedGroups.add(members.map((m) => m.name).toList());
    restoreRoutes.add(route);
    staged.add(restoreId);
  }

  @override
  Future<void> publishRestoreGroup(
          {required String restoreId, required String rollbackCaptureId}) =>
      publishRestore(
          restoreId: restoreId, rollbackCaptureId: rollbackCaptureId);
}

class _MemorySaveFile extends Fake implements File {
  @override
  final String path;
  final List<int> bytes;
  _MemorySaveFile(this.path, this.bytes);

  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      Stream.value(bytes.sublist(start ?? 0, end));
}

class _SavedataCapture extends _Capture {
  List<String> leaves = ['PARAM.SFO', 'CUSTOM.SAV', 'ICON0.PNG', 'EMPTY'];

  @override
  Future<CapturedSaveGroup> capturePpssppSavedata(
      {required String captureId,
      required String directory,
      bool restoreBaseline = false}) async {
    if (sealed[captureId] case final previous?) return previous;
    captures++;
    ppssppSources.add(directory);
    return sealed[captureId] =
        CapturedSaveGroup(captureId, 'device', 'v1.20.4', [
      for (var index = 0; index < leaves.length; index++)
        CapturedSaveFile(
            leaves[index],
            _MemorySaveFile('/private/$captureId/member-$index',
                leaves[index] == 'EMPTY' ? [] : [1, 2, 3, 4]),
            leaves[index] == 'EMPTY' ? 0 : 4,
            leaves[index] == 'EMPTY'
                ? 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
                : digest)
    ]);
  }

  @override
  Future<void> stagePpssppSavedataRestore(
      {required String restoreId,
      required String directory,
      required List<RestoreSaveMember> members}) async {
    for (final member in members) {
      var size = 0;
      await for (final bytes in member.bytes) {
        size += bytes.length;
      }
      expect(size, member.size);
    }
    stagedGroups.add(members.map((member) => member.name).toList());
    stagedDirectories.add(directory);
    staged.add(restoreId);
  }

  @override
  Future<void> publishRestoreGroup(
      {required String restoreId, required String rollbackCaptureId}) async {
    await super.publishRestoreGroup(
        restoreId: restoreId, rollbackCaptureId: rollbackCaptureId);
    leaves = stagedGroups.last.toList();
  }
}

class _Areas extends DriveSaveBackupAreaApi {
  int reserved = 0;
  _Areas(DriveAuthorization auth)
      : super(authorization: auth, accountId: 'account');
  @override
  Future<String> reserveAreaId({CancelToken? cancellation}) async =>
      'reserved-${++reserved}';
}

/// UI verifies the explicit choice; the separate job tests exercise real SQLite
/// ordering. Do not launch FFI work from a dialog's fake-clock continuation.
class _UiJob extends SaveBackupGameJob {
  List<SaveBackupManifest>? deviceCopiesFixture;
  final deviceImports = <({SaveBackupManifest copy, Set<String>? paths})>[];
  @override
  List<SaveBackupManifest> get otherDeviceBackups =>
      deviceCopiesFixture ?? super.otherDeviceBackups;
  @override
  List<SaveBackupManifest> get suggestedDeviceBackups =>
      deviceCopiesFixture ?? super.suggestedDeviceBackups;
  @override
  Future<void> importDeviceBackup(SaveBackupManifest candidate,
      {Set<String>? memberPaths}) async {
    deviceImports.add((copy: candidate, paths: memberPaths));
  }

  List<String>? namesFixture;
  Object? namesFailure;
  Future<List<String>>? namesPending;
  bool? busyFixture;
  @override
  bool get busy => busyFixture ?? super.busy;
  SaveBackupGameJob? refreshedFrom;
  bool refreshFixture = false;
  bool refreshed = false;
  Completer<void>? loadHold;
  @override
  Future<void> load() async {
    await loadHold?.future;
    if (!refreshFixture) return super.load();
    refreshed = refreshedFrom != null;
    notifyListeners();
  }

  @override
  String? get pendingName =>
      refreshed ? refreshedFrom!.pendingName : super.pendingName;
  @override
  SaveBackupManifest? get lastVerified =>
      refreshed ? refreshedFrom!.lastVerified : super.lastVerified;
  int restores = 0;
  int rollbacks = 0;
  int localChoices = 0;
  final cloudChoices = <String>[];
  _UiJob(SaveBackupGameJob other)
      : super(
            database: other.database,
            capture: other.capture,
            areas: other.areas,
            generations: other.generations,
            clientId: other.clientId,
            accountId: other.accountId,
            areaId: other.areaId,
            editionId: other.editionId,
            artifactId: other.artifactId,
            ppssppDirectory: other.ppssppDirectory,
            ppssppSlot: other.ppssppSlot,
            ppssppCompanion: other.ppssppCompanion,
            melonDirectory: other.melonDirectory,
            melonName: other.melonName,
            pcsxLayout: other.pcsxLayout,
            pcsxCard: other.pcsxCard,
            resolvePcsxGrant: other.resolvePcsxGrant,
            resolveSaveName: other.resolveSaveName);
  @override
  Future<List<String>> reviewedNames() async {
    if (namesPending != null) return await namesPending!;
    if (namesFailure != null) throw namesFailure!;
    return namesFixture ?? [await resolveSaveName()];
  }

  @override
  Future<void> restoreLatest() async {
    restores++;
  }

  @override
  Future<void> rollbackLast() async {
    rollbacks++;
  }

  @override
  Future<void> keepLocalConflict(Set<String> reviewedHeads) async {
    localChoices++;
  }

  @override
  Future<void> restoreConflict(
      String generationId, Set<String> reviewedHeads) async {
    cloudChoices.add(generationId);
  }
}

class _AutomaticUi extends AutomaticSaveBackups {
  bool enabled = false;
  AutomaticSaveMapping? selected;
  int changes = 0;
  void completed() => notifyListeners();
  _AutomaticUi(Database db, SharedPreferences preferences)
      : super(
            database: Future.value(db),
            preferences: preferences,
            sources: () => []);
  @override
  Future<AutomaticSaveStatus> status(AutomaticSaveMapping mapping) async =>
      AutomaticSaveStatus(enabled: enabled, outcome: 'unchanged');
  @override
  Future<void> setEnabled(AutomaticSaveMapping mapping, bool value) async {
    selected = mapping;
    enabled = value;
    changes++;
    notifyListeners();
  }
}

class _Generations extends DriveSaveBackupGenerationApi {
  final Database db;
  int uploads = 0;
  bool fail = false;
  bool failDownload = false;
  int downloads = 0;
  SaveBackupManifest? uploaded;
  final cloud = <String, SaveBackupManifest>{};
  void Function()? onPublish, onDiscover, onDownload;
  _Generations(DriveAuthorization auth, this.db)
      : super(authorization: auth, accountId: 'account');
  @override
  Future<SaveBackupManifest> loadGeneration(
          {required String areaId,
          required String generationId,
          required SaveBackupBinding target,
          CancelToken? cancellation}) async =>
      cloud[generationId] ?? uploaded!;
  @override
  Future<List<SaveBackupManifest>> discoverGenerations(
      {required String areaId,
      required SaveBackupBinding target,
      CancelToken? cancellation}) async {
    onDiscover?.call();
    return cloud.values.toList();
  }

  @override
  Stream<Uint8List> memberBytes(
      {required String areaId,
      required SaveBackupManifest generation,
      required String memberId,
      CancelToken? cancellation}) async* {
    downloads++;
    onDownload?.call();
    final record = jsonDecode((await db.query('save_backup_game_jobs'))
        .single['record_json'] as String);
    expect(record['restore']['generationId'], generation.generationId);
    expect(record['restore']['rollbackId'], matches(RegExp(r'^[a-f0-9]{32}$')));
    if (generation.members
            .singleWhere((m) => m.cloudFileId == memberId)
            .sizeBytes !=
        0) {
      yield generation.binding.platformId == 'psx'
          ? Uint8List(131072)
          : generation.binding.platformId == 'n64'
              ? Uint8List(296960)
              : Uint8List.fromList([1, 2, 3, 4]);
    }
    if (failDownload) {
      throw const SaveBackupGenerationException(
          SaveBackupGenerationIssue.digestMismatch);
    }
  }

  @override
  Future<void> publish(
      {required String areaId,
      required SaveBackupManifest generation,
      required Map<String, File> captures,
      CancelToken? cancellation}) async {
    uploads++;
    final record = jsonDecode((await db.query('save_backup_game_jobs'))
        .single['record_json'] as String);
    expect(record['generation']['generationId'], generation.generationId);
    expect(record['captures'].keys.toSet(), captures.keys.toSet());
    uploaded = generation;
    if (fail) {
      throw const SaveBackupGenerationException(
          SaveBackupGenerationIssue.unavailable);
    }
    cloud[generation.generationId] = generation;
    onPublish?.call();
  }
}

SaveBackupManifest _branch(SaveBackupManifest base, String id) =>
    SaveBackupManifest(
        generationId: id,
        binding: base.binding,
        parentGenerationIds: [base.generationId],
        // An older clock must not hide newer ancestry or divergent bytes.
        createdAt: DateTime.utc(2000),
        members: [
          SaveBackupMember(
              relativePath: base.members.single.relativePath,
              cloudFileId: '$id-member',
              sizeBytes: 4,
              sha256: 'c' * 64)
        ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late Database db;
  late _Capture capture;
  late _Areas areas;
  late _Generations generations;
  late SaveBackupGameJob job;
  late String currentName;
  final artifactId = RemoteArtifactId(
      providerId: 'drive',
      sourceId: 'source',
      accountId: 'account',
      providerFileId: 'file');
  setUp(() async {
    currentName = 'Game.srm';
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await LibrarySchema.install(db);
    final store = LibraryStore(Future.value(db));
    await store.putGame(GameIdentity(
        id: 'game',
        platformId: 'gba',
        title: 'Game',
        matchStatus: IdentityMatchStatus.manuallyMatched));
    await store.putEdition(EditionIdentity(
        id: 'edition',
        gameId: 'game',
        members: [EditionMember(artifactId: artifactId)]));
    final auth = DriveAuthorization(_Driver());
    capture = _Capture();
    areas = _Areas(auth);
    generations = _Generations(auth, db);
    job = SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        resolveSaveName: () async => currentName);
  });
  tearDown(() async {
    await job.cancelAndJoin();
    areas.close();
    generations.close();
    await db.close();
  });
  SaveBackupManifest otherDevice(SaveBackupManifest base) => SaveBackupManifest(
      generationId: 'other-device-copy',
      binding: SaveBackupBinding.fromJson(
          {...base.binding.toJson(), 'deviceId': 'second-device'}),
      parentGenerationIds: [],
      createdAt: DateTime.utc(2090),
      members: [
        SaveBackupMember(
            relativePath: base.members.single.relativePath,
            cloudFileId: 'other-device-member',
            sizeBytes: base.members.single.sizeBytes,
            sha256: 'c' * 64)
      ]);

  test('migration restores absent local data offline without a cloud request',
      () async {
    final support = await Directory.systemTemp.createTemp('migration-save-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => support.path);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await support.delete(recursive: true);
    });
    final file = File(
        p.join(support.path, 'migration-game-data', 'branch', currentName));
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3, 4]);
    await MigrationGameData.install(db);
    final data = {
      'schema': 1,
      'id': 'branch',
      'state': 'pending',
      'scope': job.migrationScope,
      'members': [
        {
          'name': currentName,
          'path': file.path,
          'size': 4,
          'sha256': sha256.convert([1, 2, 3, 4]).toString()
        }
      ]
    };
    await db.insert('migration_game_data', {
      'branch_id': 'branch',
      'scope_key': MigrationGameData.scopeKey(job.migrationScope),
      'state': 'pending',
      'created_at': 1,
      'record_json': jsonEncode(data)
    });
    capture.localAbsent = true;
    await job.restoreMigrationBeforeLaunch(currentName);
    expect(job.phase, 'restored');
    expect(capture.restored, hasLength(1));
    expect(generations.downloads, 0);
    expect(generations.uploads, 0);
    await job.restoreMigrationBeforeLaunch(currentName);
    expect(capture.restored, hasLength(1),
        reason: 'Do not replay a completed local restore');
  });

  test(
      'migration preserves differing destination bytes until explicitly selected',
      () async {
    final support =
        await Directory.systemTemp.createTemp('migration-conflict-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => support.path);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await support.delete(recursive: true);
    });
    final file = File(
        p.join(support.path, 'migration-game-data', 'branch', currentName));
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3, 4]);
    await MigrationGameData.install(db);
    final data = {
      'schema': 1,
      'id': 'branch',
      'state': 'pending',
      'scope': job.migrationScope,
      'members': [
        {
          'name': currentName,
          'path': file.path,
          'size': 4,
          'sha256': sha256.convert([1, 2, 3, 4]).toString()
        }
      ]
    };
    await db.insert('migration_game_data', {
      'branch_id': 'branch',
      'scope_key': MigrationGameData.scopeKey(job.migrationScope),
      'state': 'pending',
      'created_at': 1,
      'record_json': jsonEncode(data)
    });
    await job.restoreMigrationBeforeLaunch(currentName);
    expect(job.importedDataPending, true);
    expect(capture.restored, isEmpty);
    await job.restoreMigrationBeforeLaunch(currentName, useImported: true);
    expect(capture.restored, hasLength(1));
    expect(job.hasPreviousImportedData, true);
    expect(generations.uploads, 0);
  });

  test(
      'migration rebinds the reviewed battery name and only uploads later changes',
      () async {
    final support =
        await Directory.systemTemp.createTemp('migration-baseline-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => support.path);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await support.delete(recursive: true);
    });
    final file = File(p.join(
        support.path, 'migration-game-data', 'branch', 'old-native-uri.srm'));
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3, 4]);
    final digest = sha256.convert([1, 2, 3, 4]).toString();
    await MigrationGameData.install(db);
    final data = {
      'schema': 1,
      'id': 'branch',
      'state': 'pending',
      'scope': job.migrationScope,
      'members': [
        {
          'name': 'old-native-uri.srm',
          'path': file.path,
          'size': 4,
          'sha256': digest
        }
      ]
    };
    await db.insert('migration_game_data', {
      'branch_id': 'branch',
      'scope_key': MigrationGameData.scopeKey(job.migrationScope),
      'state': 'pending',
      'created_at': 1,
      'record_json': jsonEncode(data)
    });
    currentName = 'new-native-uri.srm';
    capture.localAbsent = true;
    await job.restoreMigrationBeforeLaunch(currentName);
    expect(capture.stagedNames.single, currentName);
    capture.localAbsent = false;
    capture.digest = digest;
    await job.backup(currentName, automatic: true);
    expect(job.phase, 'unchanged');
    expect(generations.uploads, 0,
        reason: 'Imported bytes are not a new save event');
    await job.load();
    expect(job.issue, isNull);
    capture.digest = 'c' * 64;
    await job.backup(currentName, automatic: true);
    expect(job.phase, 'verified');
    expect(generations.uploads, 1,
        reason:
            'A genuine later change follows normal cloud conflict handling');
  });

  test(
      'migration binds an absent companion baseline to the restored member set',
      () async {
    final support =
        await Directory.systemTemp.createTemp('migration-companion-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => support.path);
    final companionJob = SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        resolveSaveName: () async => 'Game.7z',
        romCompanionName: 'Game.7z',
        romCompanionDirectory: '/storage/emulated/0/Roms/gba',
        romCompanionPlatform: 'gba',
        romCompanionEmulator: 'com.retroarch.aarch64',
        romCompanionCore: 'mgba',
        resolveRomCompanionGrant: () async =>
            {'installationId': 'owned', 'filename': 'Game.7z'});
    addTearDown(() async {
      await companionJob.cancelAndJoin();
      companionJob.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await support.delete(recursive: true);
    });
    final file =
        File(p.join(support.path, 'migration-game-data', 'branch', 'Game.png'));
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3, 4]);
    await MigrationGameData.install(db);
    final data = {
      'schema': 1,
      'id': 'branch',
      'state': 'pending',
      'scope': companionJob.migrationScope,
      'members': [
        {
          'name': 'Game.png',
          'path': file.path,
          'size': 4,
          'sha256': sha256.convert([1, 2, 3, 4]).toString()
        }
      ]
    };
    await db.insert('migration_game_data', {
      'branch_id': 'branch',
      'scope_key': MigrationGameData.scopeKey(companionJob.migrationScope),
      'state': 'pending',
      'created_at': 1,
      'record_json': jsonEncode(data)
    });
    capture.localAbsent = true;
    await companionJob.restoreMigrationBeforeLaunch('Game.7z');
    expect(companionJob.phase, 'restored');
    expect(capture.companionCaptureMembers.single, {'Game.png'},
        reason:
            'The native rollback receipt must bind the same members as publication, even when absent');
    expect(capture.stagedGroups.single, ['Game.png']);
    expect(generations.uploads, 0);
  });

  test('another device never becomes an automatic restore or conflict',
      () async {
    await job.backup(currentName);
    final peer = otherDevice(job.lastVerified!);
    generations.cloud[peer.generationId] = peer;
    await job.reconcileBeforeLaunch(currentName);
    expect(job.issue, isNull);
    expect(job.conflicts, isEmpty);
    expect(capture.restored, isEmpty);
    capture.localAbsent = true;
    generations.cloud.remove(job.lastVerified!.generationId);
    await job.reconcileBeforeLaunch(currentName);
    expect(job.phase, 'no_save');
    expect(capture.restored, isEmpty);
    expect(generations.downloads, 0);
  });

  test(
      'device import suggestions are durable and ignore choices are reversible',
      () async {
    await job.backup(currentName);
    final peer = otherDevice(job.lastVerified!);
    generations.cloud[peer.generationId] = peer;
    await job.reconcileBeforeLaunch(currentName);
    expect(job.suggestedDeviceBackups.single.encode(), peer.encode());
    await job.setDeviceBackupIgnored(peer, true);
    await job.load();
    expect(job.suggestedDeviceBackups, isEmpty);
    expect(job.otherDeviceBackups.single.encode(), peer.encode());
    await job.setDeviceBackupIgnored(peer, false);
    expect(job.suggestedDeviceBackups.single.encode(), peer.encode());
    expect(capture.restored, isEmpty);
    expect(generations.downloads, 0);
  });

  test('device choices and ancestry do not leak into another device', () async {
    await job.backup(currentName);
    final original = job.lastVerified!;
    final peer = otherDevice(original);
    generations.cloud[peer.generationId] = peer;
    await job.reconcileBeforeLaunch(currentName);
    await job.setDeviceBackupIgnored(peer, true);
    capture.deviceId = 'third-device';
    await job.reconcileBeforeLaunch(currentName);
    expect(job.issue, isNull);
    expect(job.lastVerified!.binding.deviceId, 'third-device');
    expect(job.lastVerified!.parentGenerationIds, isEmpty);
    expect(job.suggestedDeviceBackups.map((m) => m.generationId),
        contains(peer.generationId));
    expect(capture.restored, isEmpty);
  });

  test('failed ignore persistence stays visible and does not hide a suggestion',
      () async {
    await job.backup(currentName);
    final peer = otherDevice(job.lastVerified!);
    generations.cloud[peer.generationId] = peer;
    await job.reconcileBeforeLaunch(currentName);
    await db.execute('''CREATE TRIGGER reject_device_choice BEFORE INSERT ON
      save_backup_game_jobs BEGIN SELECT RAISE(ABORT, 'fixture failure'); END''');
    await job.setDeviceBackupIgnored(peer, true);
    expect(job.issue, 'device_choice_unavailable');
    expect(job.deviceBackupIgnored(peer), isFalse);
    expect(job.suggestedDeviceBackups.single.encode(), peer.encode());
    expect(job.busy, isFalse);
    expect(capture.restored, isEmpty);
    await db.execute('DROP TRIGGER reject_device_choice');
    await job.setDeviceBackupIgnored(peer, true);
    expect(job.issue, isNull);
    expect(job.suggestedDeviceBackups, isEmpty);
  });

  test(
      'explicit device import restores the required group and retains rollback',
      () async {
    await job.backup(currentName);
    final local = job.lastVerified!;
    final peer = otherDevice(local);
    generations.cloud[peer.generationId] = peer;
    await job.reconcileBeforeLaunch(currentName);
    await job.importDeviceBackup(peer);
    expect(job.issue, isNull);
    expect(job.phase, 'restored');
    expect(job.lastVerified!.encode(), peer.encode());
    expect(job.rollbackAvailable, isTrue);
    expect(capture.restored, hasLength(1));
    expect(generations.cloud[local.generationId]!.encode(), local.encode());
    expect(generations.cloud[peer.generationId]!.encode(), peer.encode());
    expect(job.suggestedDeviceBackups, isEmpty);
    capture.digest = 'c' * 64;
    await job.backup(currentName);
    expect(job.issue, isNull);
    expect(job.lastVerified!.binding.deviceId, 'device');
    expect(job.lastVerified!.parentGenerationIds, contains(local.generationId));
    expect(job.lastVerified!.parentGenerationIds,
        isNot(contains(peer.generationId)));
    final retainedId = capture.restored.single.rollback;
    capture.sealed[retainedId] =
        CapturedSaveGroup(retainedId, 'device', '1.22.2_GIT', [
      CapturedSaveFile(
          currentName,
          _MemorySaveFile('/private/$retainedId/member-0', [1, 2, 3, 4]),
          4,
          'b' * 64)
    ]);
    await job.rollbackLast();
    expect(job.issue, isNull);
    expect(job.phase, 'rolled_back');
    expect(capture.restored, hasLength(2));
  });

  test('changed other-device manifest invalidates the reviewed import',
      () async {
    await job.backup(currentName);
    final peer = otherDevice(job.lastVerified!);
    generations.cloud[peer.generationId] = peer;
    await job.reconcileBeforeLaunch(currentName);
    generations.cloud[peer.generationId] = SaveBackupManifest(
        generationId: peer.generationId,
        binding: peer.binding,
        parentGenerationIds: [],
        createdAt: peer.createdAt,
        members: [
          SaveBackupMember(
              relativePath: peer.members.single.relativePath,
              cloudFileId: 'changed-member',
              sizeBytes: 4,
              sha256: 'd' * 64)
        ]);
    await job.importDeviceBackup(peer);
    expect(job.issue, 'device_import_changed');
    expect(capture.restored, isEmpty);
    expect(generations.downloads, 0);
  });

  test('device import cannot split a required save group', () async {
    capture.includeRtc = true;
    await job.backup(currentName);
    final local = job.lastVerified!;
    final peer = SaveBackupManifest(
        generationId: 'paired-peer',
        binding: SaveBackupBinding.fromJson(
            {...local.binding.toJson(), 'deviceId': 'second-device'}),
        parentGenerationIds: [],
        createdAt: DateTime.utc(2090),
        members: [
          for (final member in local.members)
            SaveBackupMember(
                relativePath: member.relativePath,
                cloudFileId: 'peer-${member.cloudFileId}',
                sizeBytes: member.sizeBytes,
                sha256: member.sha256)
        ]);
    generations.cloud[peer.generationId] = peer;
    await job.reconcileBeforeLaunch(currentName);
    final captures = capture.captures;
    await job.importDeviceBackup(peer, memberPaths: {currentName});
    expect(job.issue, 'device_import_selection');
    expect(capture.captures, captures);
    expect(capture.restored, isEmpty);
    expect(generations.downloads, 0);
    expect(job.lastVerified!.encode(), local.encode());
  });

  testWidgets(
      'other-device chooser lists a required group without auto-selecting',
      (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await job.backup(currentName);
      final peer = otherDevice(job.lastVerified!);
      generations.cloud[peer.generationId] = peer;
      await job.reconcileBeforeLaunch(currentName);
    });
    await tester.pumpWidget(createTestApp(Scaffold(
        body: SingleChildScrollView(
            child: SaveBackupGamePanel(
                job: job,
                title: 'Game',
                section: SaveBackupSection.restore)))));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('save-other-devices'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Import from another device'), findsOneWidget);
    expect(find.byIcon(Icons.devices_outlined), findsWidgets);
    expect(find.text('Source'), findsWidgets);
    expect(find.textContaining('Game.srm'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('save-device-files-section')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Game.srm'), findsOneWidget);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('save-device-group')))
            .value,
        isFalse);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('save-device-import')))
            .onPressed,
        isNull);
    expect(capture.restored, isEmpty);
    await tester.tap(find.byKey(const ValueKey('save-device-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-device-source-section')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Game.srm'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('save-device-files-section')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('save-device-group')))
            .value,
        isTrue);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('save-device-import')))
            .onPressed,
        isNotNull);
    expect(find.text('Cancel'), findsWidgets);
    expect(find.text('Ignore'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('save-device-cancel')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('PS1 shared card uses one durable history across reviewed games',
      () async {
    final store = LibraryStore(Future.value(db));
    final otherArtifact = RemoteArtifactId(
        providerId: 'drive',
        sourceId: 'source',
        accountId: 'account',
        providerFileId: 'other');
    for (final row in [
      ('game', 'edition', artifactId),
      ('other-game', 'other-edition', otherArtifact)
    ]) {
      await store.putGame(GameIdentity(
          id: row.$1,
          platformId: 'psx',
          title: row.$1,
          matchStatus: IdentityMatchStatus.manuallyMatched));
      await store.putEdition(EditionIdentity(
          id: row.$2,
          gameId: row.$1,
          members: [EditionMember(artifactId: row.$3)]));
    }
    final layout = PcsxSaveLayout.decode({
      'directory': '/storage/emulated/0/RetroArch/saves/PCSX-ReARMed',
      'cards': [
        {'slot': 1, 'mode': 'libretro', 'name': 'owned%2FGame.srm'},
        {'slot': 2, 'mode': 'shared', 'name': 'pcsx-card2.mcd'}
      ]
    });
    SaveBackupGameJob make(
            String edition, RemoteArtifactId artifact, PcsxSaveCard card) =>
        SaveBackupGameJob(
            database: Future.value(db),
            capture: capture,
            areas: areas,
            generations: generations,
            clientId: 'client',
            accountId: 'account',
            areaId: 'area',
            editionId: edition,
            artifactId: artifact,
            pcsxLayout: layout,
            pcsxCard: card,
            resolvePcsxGrant: () async =>
                {'installationId': edition, 'filename': 'Game.chd'},
            resolveSaveName: () async => card.name!);
    final first = make('edition', artifactId, layout.cards.last);
    final second = make('other-edition', otherArtifact, layout.cards.last);
    final privateCard =
        make('other-edition', otherArtifact, layout.cards.first);
    try {
      await first.backup(layout.cards.last.name!);
      expect(first.issue, isNull);
      final original = first.lastVerified!;
      expect(original.binding.sharedCardResourceKey,
          layout.sharedResourceKey(layout.cards.last));
      await second.backup(layout.cards.last.name!);
      expect(second.issue, isNull);
      expect(second.phase, 'unchanged');
      expect(second.lastVerified!.generationId, original.generationId);
      expect(generations.uploads, 1);
      capture.digest = 'd' * 64;
      await second.backup(layout.cards.last.name!);
      expect(second.issue, isNull);
      expect(second.lastVerified!.parentGenerationIds, [original.generationId]);
      expect(second.lastVerified!.binding.editions.single.editionId,
          'other-edition');
      expect(generations.cloud, contains(original.generationId));
      expect(await db.query('save_backup_game_jobs'), hasLength(1));
      await privateCard.load();
      expect(privateCard.lastVerified, isNull);
      expect(capture.batteryRoutes, isEmpty);
      // Restore the shared resource from another initiating game's publication,
      // then roll back using the retained local capture, not a second download.
      await first.restoreLatest();
      expect(first.issue, isNull);
      expect(first.phase, 'restored');
      expect(
          capture.pcsxRestores.single, '${layout.directory}/2/pcsx-card2.mcd');
      expect(first.rollbackAvailable, isTrue);
      final downloads = generations.downloads;
      await first.rollbackLast();
      expect(first.issue, isNull);
      expect(first.phase, 'rolled_back');
      expect(capture.restored, hasLength(2));
      expect(generations.downloads, downloads);
      expect(capture.restoreRoutes, isEmpty);
      // Automatic watch identity must remain a PS1 card, never mGBA.
      final watched = AutomaticSaveMapping.fromJob(second,
          title: 'PS1', romRoot: '/storage/1234-ABCD/Roms/psx');
      expect(jsonDecode(watched.encode())['route'], 'pcsx');
      expect(watched.directory, layout.directory);
      expect(watched.slot, 'pcsx-card2.mcd');
      expect(watched.retroArchRoute, isNull);
      expect(
          watched.key,
          isNot(AutomaticSaveMapping.fromJob(first,
                  title: 'Other', romRoot: '/storage/1234-ABCD/Roms/psx')
              .key));
    } finally {
      await first.cancelAndJoin();
      await second.cancelAndJoin();
      await privateCard.cancelAndJoin();
      first.dispose();
      second.dispose();
      privateCard.dispose();
    }
  });
  test('refresh joins another job instance and reloads without recapturing',
      () async {
    final ui = _UiJob(job);
    await ui.load();
    capture.held = Completer<void>();
    final backup = job.backup(currentName);
    await capture.started.future;
    var refreshed = false;
    final refresh = ui.refresh().then((_) => refreshed = true);
    expect(refreshed, isFalse);
    expect(ui.lastVerified, isNull);
    expect(identical(job.refresh(), backup), isTrue);
    capture.held!.complete();
    await backup;
    await refresh;
    expect(ui.lastVerified!.generationId, job.lastVerified!.generationId);
    expect(ui.pendingName, isNull);
    expect(capture.captures, 1);
    expect(generations.uploads, 1);
    ui.dispose();
  });
  test('a UI refresh never substitutes for another instance requested backup',
      () async {
    final ui = _UiJob(job)..loadHold = Completer<void>();
    final refresh = ui.refresh();
    final backup = job.backup(currentName);
    expect(identical(backup, refresh), isFalse);
    ui.loadHold!.complete();
    await refresh;
    await backup;
    expect(capture.captures, 1);
    expect(job.lastVerified, isNotNull);
    ui.dispose();
  });
  testWidgets('mapped standalone saves expose change-location action',
      (tester) async {
    final psp = _UiJob(SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        ppssppDirectory: '/storage/emulated/0/PSP/PPSSPP_STATE',
        ppssppSlot: 'ULUS10041_1.00_0.ppst',
        resolveSaveName: () async => 'ULUS10041_1.00_0.ppst'));
    var changes = 0;
    await tester.pumpWidget(createTestApp(Scaffold(
        body: SingleChildScrollView(
            child: SaveBackupGamePanel(
                job: psp, title: 'Game', onChangeMapping: () => changes++)))));
    await tester.pumpAndSettle();
    final change = find.byKey(const ValueKey('save-change-location'));
    expect(change, findsOneWidget);
    await tester.tap(change);
    expect(changes, 1);
    psp.busyFixture = true;
    await tester.pumpWidget(createTestApp(Scaffold(
        body: SingleChildScrollView(
            child: SaveBackupGamePanel(
                job: psp, title: 'Game', onChangeMapping: () => changes++)))));
    await tester.pump(); // A running operation intentionally animates.
    expect(tester.widget<OutlinedButton>(change).onPressed, isNull);
    expect(changes, 1);
    psp.busyFixture = false;
    await tester.pumpWidget(createTestApp(Scaffold(
        body: SingleChildScrollView(
            child: SaveBackupGamePanel(
                job: psp,
                title: 'Game',
                section: SaveBackupSection.restore,
                onChangeMapping: () => changes++)))));
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(change).onPressed, isNotNull);
    await tester.pumpWidget(createTestApp(Scaffold(
        body: SingleChildScrollView(
            child: SaveBackupGamePanel(
                job: psp,
                title: 'Game',
                section: SaveBackupSection.status,
                onChangeMapping: () => changes++)))));
    await tester.pumpAndSettle();
    expect(change, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    psp.dispose();
  });
  testWidgets(
      'RetroArch exact save association enables controls without manual confirmation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final automatic = _AutomaticUi(db, await SharedPreferences.getInstance());
    final ui = _UiJob(job)..refreshFixture = true;
    await tester.pumpWidget(createTestApp(Scaffold(
        body: SingleChildScrollView(
            child: SaveBackupGamePanel(
                job: ui, title: 'Game', automatic: automatic)))));
    await tester.pumpAndSettle();
    final control = find.byKey(const ValueKey('automatic-save-enable'));
    expect(control, findsOneWidget);
    expect(find.textContaining('Close the game in RetroArch'), findsNothing);
    expect(find.textContaining('backup waits until it is safely closed'),
        findsNothing);
    expect(find.textContaining('RetroArch can stay open'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('I confirm this save belongs to Game'), findsNothing);
    expect(find.text('Save linked automatically'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('save-backup-game-run')))
            .onPressed,
        isNotNull);
    expect(tester.widget<CheckboxListTile>(control).onChanged, isNotNull);
    tester.widget<CheckboxListTile>(control).onChanged!(true);
    await tester.pumpAndSettle();
    expect(automatic.selected!.slot, currentName);
    expect(automatic.selected!.retroArchRoute, RetroArchBatteryRoute.mgba);
    await tester.pumpWidget(createTestApp(Scaffold(
        body: SingleChildScrollView(
            child: SaveBackupGamePanel(
                job: ui,
                title: 'Game',
                automatic: automatic,
                section: SaveBackupSection.status)))));
    await tester.pumpAndSettle();
    expect(control, findsNothing);
    expect(find.text('Automatic save checks: enabled'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    ui.dispose();
    automatic.dispose();
  });
  testWidgets(
      'PS1 shared card panel names the resource and links without confirmation',
      (tester) async {
    final layout = PcsxSaveLayout.decode({
      'directory': '/storage/emulated/0/RetroArch/saves/PCSX-ReARMed',
      'cards': [
        {'slot': 2, 'mode': 'shared', 'name': 'pcsx-card2.mcd'}
      ]
    });
    SharedPreferences.setMockInitialValues({});
    final automatic = _AutomaticUi(db, await SharedPreferences.getInstance());
    final psx = _UiJob(SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        pcsxLayout: layout,
        pcsxCard: layout.cards.single,
        resolvePcsxGrant: () async =>
            {'installationId': 'installation', 'filename': 'Game.chd'},
        resolveSaveName: () async => 'pcsx-card2.mcd'))
      ..refreshFixture = true;
    await tester.pumpWidget(createTestApp(Scaffold(
        body: SingleChildScrollView(
            child: SaveBackupGamePanel(
                job: psx,
                title: 'Game',
                automatic: automatic,
                romRoot: '/storage/1234-ABCD/Roms/psx')))));
    await tester.pumpAndSettle();
    expect(find.textContaining('PlayStation · shared memory card 2'),
        findsOneWidget);
    expect(find.textContaining('may contain saves from several games'),
        findsOneWidget);
    expect(find.text('Save linked automatically'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    final toggle = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('automatic-save-enable')));
    expect(toggle.onChanged, isNotNull);
    toggle.onChanged!(true);
    await tester.pumpAndSettle();
    expect(automatic.selected!.pcsxCard!.mode, 'shared');
    expect(automatic.selected!.retroArchRoute, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    psx.dispose();
    automatic.dispose();
  });
  testWidgets('automatic completion refreshes an open restore panel',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final automatic = _AutomaticUi(db, await SharedPreferences.getInstance());
    final ui = _UiJob(job);
    await tester.runAsync(() async {
      generations.fail = true;
      await job.backup(currentName);
      await ui.load();
      expect(ui.pendingName, currentName);
      generations.fail = false;
      await job.backup(currentName);
      expect(job.pendingName, isNull);
    });
    ui.refreshFixture = true;
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: SaveBackupGamePanel(
                    job: ui,
                    automatic: automatic,
                    title: 'Game',
                    section: SaveBackupSection.restore)))));
    await tester.pumpAndSettle();
    expect(ui.pendingName, currentName);
    // The panel event path uses an immediate UI fixture, not FFI under fake time.
    ui.refreshedFrom = job;
    automatic.completed();
    await tester.pumpAndSettle();
    expect(ui.pendingName, isNull);
    expect(ui.lastVerified, isNotNull);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('save-backup-game-restore')))
            .onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    ui.dispose();
    automatic.dispose();
  });
  testWidgets(
      'automatic opt-in requires review and status has no hidden controls',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final automatic = _AutomaticUi(db, await SharedPreferences.getInstance());
    final psp = _UiJob(SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        ppssppDirectory: '/storage/emulated/0/PSP/PPSSPP_STATE',
        ppssppSlot: 'ULUS10041_1.00_0.ppst',
        resolveSaveName: () async => 'ULUS10041_1.00_0.ppst'));
    final mapping = AutomaticSaveMapping.fromJob(psp, title: 'Game');
    Future<void> show({bool allow = false, bool statusOnly = false}) async {
      await tester.pumpWidget(ProviderScope(
          child: createTestApp(Scaffold(
              body: AutomaticSaveBackupPanel(
                  service: automatic,
                  mapping: mapping,
                  allowEnable: allow,
                  statusOnly: statusOnly)))));
      await tester.pumpAndSettle();
    }

    await show();
    final checkbox = find.byKey(const ValueKey('automatic-save-enable'));
    expect(tester.widget<CheckboxListTile>(checkbox).onChanged, isNull);
    await show(allow: true);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(automatic.enabled, isTrue);
    expect(automatic.changes, 1);
    await show(statusOnly: true);
    expect(checkbox, findsNothing);
    expect(find.text('Automatic save checks: enabled'), findsOneWidget);
    expect(
        find.text('Last automatic check: unchanged; verified backup retained.'),
        findsOneWidget);
    await show();
    expect(tester.widget<CheckboxListTile>(checkbox).onChanged, isNotNull,
        reason: 'Opt-out remains available without enabling another save');
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(automatic.enabled, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    automatic.dispose();
    psp.dispose();
  });
  testWidgets(
      'status explains an unchanged check without claiming another upload',
      (tester) async {
    final ui = _UiJob(job)..phase = 'unchanged';
    await tester.pumpWidget(ProviderScope(
        child: createTestApp(Scaffold(
            body: SaveBackupGamePanel(
                job: ui, title: 'Game', section: SaveBackupSection.status)))));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Save unchanged. The existing verified cloud backup was retained.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('save-backup-game-run')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    ui.dispose();
  });
  testWidgets('changed related files show a specific preservation message',
      (tester) async {
    await tester.runAsync(() async {
      capture.includeRtc = true;
      await job.backup(currentName);
      capture.includeRtc = false;
      await job.restoreLatest();
    });
    expect(job.issue, 'related_group_changed');
    await tester.pumpWidget(ProviderScope(
        child: createTestApp(Scaffold(
            body: SaveBackupGamePanel(
                job: job, title: 'Game', section: SaveBackupSection.status)))));
    await tester.pumpAndSettle();
    expect(
        find.text('This backup and the local save contain different files. '
            'Nothing was replaced; both copies are kept.'),
        findsOneWidget);
    expect(find.textContaining('Check your connection'), findsNothing);
    expect(capture.restored, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'missing-save restore status does not invent a previous local copy',
      (tester) async {
    await tester.runAsync(() async {
      await job.backup(currentName);
      capture.localAbsent = true;
      await job.restoreLatest();
    });
    await tester.pumpWidget(ProviderScope(
        child: createTestApp(Scaffold(
            body: SaveBackupGamePanel(
                job: job, title: 'Game', section: SaveBackupSection.status)))));
    await tester.pumpAndSettle();
    expect(find.text('Cloud save restored and ready to use.'), findsOneWidget);
    expect(find.textContaining('previous local save is kept'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pending restore directs the user to resume before backing up',
      (tester) async {
    await tester.runAsync(() async {
      capture.includeRtc = true;
      await job.backup(currentName);
      capture.publicationIssue = 'source_changed';
      await job.restoreLatest();
      await job.backup(currentName);
    });
    expect(job.issue, 'pending_restore');
    await tester.pumpWidget(ProviderScope(
        child: createTestApp(Scaffold(
            body: SaveBackupGamePanel(
                job: job, title: 'Game', section: SaveBackupSection.status)))));
    await tester.pumpAndSettle();
    expect(
        find.text('Finish the pending restore in Restore & conflicts before '
            'backing up or opening this game.'),
        findsOneWidget);
    expect(find.textContaining('Check your connection'), findsNothing);
    expect(generations.uploads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'pending restore confirmation identifies the previously chosen copy',
      (tester) async {
    final ui = _UiJob(job);
    await tester.runAsync(() async {
      await job.backup(currentName);
      generations.failDownload = true;
      await job.restoreLatest();
      await ui.load();
    });
    expect(ui.restorePending, isTrue);
    await tester.pumpWidget(ProviderScope(
        child: createTestApp(Scaffold(
            body: SaveBackupGamePanel(
                job: ui, title: 'Game', section: SaveBackupSection.restore)))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-backup-game-restore')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining(
            'It may not be the newest copy; other cloud copies are kept.'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-restore-cancel')));
    await tester.pumpAndSettle();
    expect(ui.restores, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    ui.dispose();
  });
  Future<
      ({
        AutomaticSaveBackups service,
        AutomaticSaveMapping mapping,
        SharedPreferences preferences
      })> automaticFixture({
    Future<void> Function(bool)? schedule,
    Future<void> Function()? pending,
    Future<bool> Function()? network,
    Future<void> Function()? refresh,
    Future<void> Function(List<AutomaticSaveMapping>)? watch,
    Set<String> watchFailures = const {},
    bool melon = false,
    bool savedata = false,
    bool companion = false,
    bool romCompanion = false,
    SaveRootConfiguration? configuredRoot,
    String? ppssppDirectory,
    RetroArchBatteryRoute? retroArch,
    PcsxSaveLayout? pcsx,
  }) async {
    await LibraryStore(Future.value(db)).putGame(GameIdentity(
        id: 'game',
        platformId: romCompanion
            ? 'gba'
            : pcsx != null
                ? 'psx'
                : retroArch?.platformId ?? (melon ? 'nds' : 'psp'),
        title: 'Game',
        matchStatus: IdentityMatchStatus.manuallyMatched));
    final directory = romCompanion
        ? configuredRoot?.directory ?? '/storage/emulated/0/Roms/gba'
        : pcsx != null
            ? pcsx.directory
            : retroArch != null
                ? retroArch.directory
                : melon
                    ? '/storage/emulated/0/Android/data/me.magnum.melondualds/files/saves'
                    : savedata
                        ? '/storage/emulated/0/PSP/SAVEDATA/ULUS10041DATA00'
                        : ppssppDirectory ??
                            '/storage/emulated/0/PSP/PPSSPP_STATE';
    final slot = romCompanion
        ? 'Game.7z'
        : pcsx != null
            ? pcsx.cards.single.name!
            : retroArch != null
                ? 'owned%2FGame.srm'
                : melon
                    ? 'Game.sav'
                    : savedata
                        ? 'ULUS10041DATA00'
                        : companion
                            ? 'ULUS10041_1.00_0.jpg'
                            : 'ULUS10041_1.00_0.ppst';
    final psp = SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        ppssppDirectory: romCompanion ||
                melon ||
                savedata ||
                retroArch != null ||
                pcsx != null
            ? null
            : directory,
        ppssppSlot: romCompanion ||
                melon ||
                savedata ||
                retroArch != null ||
                pcsx != null
            ? null
            : slot,
        ppssppSavedataDirectory: savedata ? directory : null,
        ppssppCompanion: companion,
        melonDirectory: melon ? directory : null,
        melonName: melon ? slot : null,
        retroArchRoute: retroArch ?? RetroArchBatteryRoute.mgba,
        pcsxLayout: pcsx,
        pcsxCard: pcsx?.cards.single,
        resolvePcsxGrant: pcsx == null
            ? null
            : () async =>
                {'installationId': 'installation', 'filename': 'Game.chd'},
        resolveRomCompanionGrant: romCompanion
            ? () async => {'installationId': 'owned', 'filename': 'Game.7z'}
            : null,
        romCompanionName: romCompanion ? slot : null,
        romCompanionDirectory: romCompanion ? directory : null,
        romCompanionPlatform: romCompanion ? 'gba' : null,
        romCompanionEmulator: romCompanion ? 'com.retroarch.aarch64' : null,
        romCompanionCore: romCompanion ? 'mgba' : null,
        saveRootConfiguration: configuredRoot,
        resolveSaveName: () async => slot);
    final mapping = AutomaticSaveMapping.fromJob(psp,
        title: 'Game',
        saveName: retroArch != null ? slot : null,
        romRoot: romCompanion
            ? directory
            : pcsx == null
                ? null
                : '/storage/1234-ABCD/Roms/psx');
    psp.dispose();
    SharedPreferences.setMockInitialValues({
      if (configuredRoot != null)
        SaveRootConfiguration.storageKey(artifactId.key):
            configuredRoot.identity,
      SaveBackupSetup.storageKey('client', 'account'):
          jsonEncode({'ready': true, 'areaId': 'area'}),
      if (retroArch == null && pcsx == null)
        mapping.slotStorageKey: jsonEncode({
          'directory': directory,
          melon || savedata || retroArch != null ? 'name' : 'slot':
              companion ? 'ULUS10041_1.00_0.ppst' : slot
        }),
    });
    final preferences = await SharedPreferences.getInstance();
    final service = AutomaticSaveBackups(
        database: Future.value(db),
        preferences: preferences,
        scheduleBackground: schedule,
        schedulePending: pending,
        networkAvailable: network,
        configureWatches: watch == null
            ? null
            : (mappings) async {
                await watch(mappings);
                return mappings
                    .map((mapping) => mapping.key)
                    .toSet()
                    .difference(watchFailures);
              },
        refreshConfiguration: refresh,
        sources: () => [
              const Source(
                  id: 'source',
                  name: 'Drive',
                  type: SourceType.drive,
                  drive: DriveSourceConfig(
                      accountId: 'account',
                      rootFolderId: 'root',
                      serverClientId: 'client'))
            ],
        createJob: (mapped, resolve) => SaveBackupGameJob(
            database: Future.value(db),
            capture: capture,
            areas: areas,
            generations: generations,
            clientId: mapped.clientId,
            accountId: mapped.accountId,
            areaId: mapped.areaId,
            editionId: mapped.editionId,
            artifactId: mapped.artifactId,
            ppssppDirectory: romCompanion ||
                    melon ||
                    savedata ||
                    retroArch != null ||
                    pcsx != null
                ? null
                : mapped.directory,
            ppssppSlot: romCompanion ||
                    melon ||
                    savedata ||
                    retroArch != null ||
                    pcsx != null
                ? null
                : mapped.slot,
            ppssppSavedataDirectory: savedata ? mapped.directory : null,
            ppssppCompanion: mapped.isPpssppCompanion,
            melonDirectory: melon ? mapped.directory : null,
            melonName: melon ? mapped.slot : null,
            retroArchRoute: retroArch ?? RetroArchBatteryRoute.mgba,
            pcsxLayout: mapped.pcsxLayout,
            pcsxCard: mapped.pcsxCard,
            resolvePcsxGrant: pcsx == null
                ? null
                : () async =>
                    {'installationId': 'installation', 'filename': 'Game.chd'},
            resolveRomCompanionGrant: romCompanion
                ? () async => {'installationId': 'owned', 'filename': 'Game.7z'}
                : null,
            romCompanionName: romCompanion ? mapped.slot : null,
            romCompanionDirectory: romCompanion ? mapped.directory : null,
            romCompanionPlatform: mapped.companionPlatform,
            romCompanionEmulator: mapped.companionEmulator,
            romCompanionCore: mapped.companionCore,
            saveRootConfiguration: mapped.saveRootConfiguration,
            resolveSaveName: resolve));
    addTearDown(() async {
      service.dispose();
      await service.cancelAndJoin();
    });
    await service.setEnabled(mapping, true);
    return (service: service, mapping: mapping, preferences: preferences);
  }

  test(
      'configured automatic roots retain their selection and reject a replaced mapping',
      () async {
    final config = SaveRootConfiguration.decode({
      'schema': 1,
      'directory': '/storage/emulated/0/Emulator/saves',
      'emulator': 'com.retroarch.aarch64',
      'core': 'mgba',
      'kind': 'save',
      'format': 'configured-save-v1',
      'files': ['Game.sav'],
      'folders': <String>[],
      'required': ['Game.sav'],
    });
    capture.configuredRoot = config;
    final watched = <AutomaticSaveMapping>[];
    final fixture = await automaticFixture(
        romCompanion: true,
        configuredRoot: config,
        watch: (rows) async {
          watched.addAll(rows);
        });
    await fixture.service.checkEnabled();
    expect((await fixture.service.status(fixture.mapping)).issue, isNull);
    expect(watched.last.saveRootConfiguration!.identity, config.identity);
    final before = capture.captures;
    await fixture.preferences.setString(
        SaveRootConfiguration.storageKey(artifactId.key),
        jsonEncode({
          ...config.toJson(),
          'directory': '/storage/emulated/0/Other/saves'
        }));
    await fixture.service.requestChanged(fixture.mapping.key);
    await fixture.service.checkEnabled();
    expect((await fixture.service.status(fixture.mapping)).issue,
        'source_changed');
    expect(capture.captures, before);
  });

  test(
      'automatic screenshot companion reuses the reviewed state association independently',
      () async {
    final watched = <AutomaticSaveMapping>[];
    final fixture = await automaticFixture(
        companion: true,
        watch: (mappings) async {
          watched.addAll(mappings);
        });
    expect(fixture.mapping.isPpssppCompanion, isTrue);
    expect(jsonDecode(fixture.mapping.encode())['route'], 'ppsspp-companion');
    expect(fixture.mapping.matchesStoredSlot('ULUS10041_1.00_0.ppst'), isTrue);
    expect(fixture.mapping.matchesStoredSlot('ULUS10041_1.00_1.ppst'), isFalse);
    await fixture.service.checkEnabled();
    expect(watched, isNotEmpty);
    expect(watched.every((mapping) => mapping.slot == 'ULUS10041_1.00_0.jpg'),
        isTrue);
    expect(generations.uploaded!.binding.kind, SaveBackupKind.companion);
    expect((await fixture.service.status(fixture.mapping)).issue, isNull);
    await fixture.preferences.setString(
        fixture.mapping.slotStorageKey,
        jsonEncode({
          'directory': fixture.mapping.directory,
          'slot': 'ULUS10041_1.00_1.ppst'
        }));
    await fixture.service.checkEnabled();
    expect((await fixture.service.status(fixture.mapping)).issue,
        'source_changed');
    expect(generations.uploads, 1);
  });

  for (final shared in [false, true]) {
    test(
        'automatic PS1 ${shared ? 'shared' : 'private'} card persists, backs up and arms before launch',
        () async {
      final layout = PcsxSaveLayout.decode({
        'directory': '/storage/emulated/0/RetroArch/saves/PCSX-ReARMed',
        'cards': [
          {
            'slot': shared ? 2 : 1,
            'mode': shared ? 'shared' : 'libretro',
            'name': shared ? 'pcsx-card2.mcd' : 'owned%2FGame.srm'
          }
        ]
      });
      final watches = <AutomaticSaveMapping>[];
      final fixture = await automaticFixture(
          pcsx: layout, watch: (rows) async => watches.addAll(rows));
      await fixture.service.requestChanged(fixture.mapping.key);
      await fixture.service.backupPending();
      expect(
          (await fixture.service.status(fixture.mapping)).outcome, 'verified');
      expect(capture.pcsxSources.single,
          '${layout.directory}/${layout.cards.single.name}');
      expect(capture.batteryRoutes, isEmpty);
      var reviews = 0;
      await fixture.service.prepareLaunch(
          artifactId: artifactId,
          editionId: 'edition',
          reviewPcsxSaves: () async {
            reviews++;
            return layout;
          });
      expect(reviews, 2);
      expect(watches.last.pcsxCard!.mode, shared ? 'shared' : 'libretro');
      expect(watches.last.romRoot, '/storage/1234-ABCD/Roms/psx');
      await expectLater(
          fixture.service.prepareLaunch(
              artifactId: artifactId,
              reviewPcsxSaves: () async => PcsxSaveLayout.decode(
                  {'directory': layout.directory, 'cards': []})),
          throwsA(isA<PlatformException>()
              .having((e) => e.code, 'code', 'source_changed')));
      final selection = jsonDecode(
              fixture.preferences.getString(fixture.mapping.slotStorageKey)!)
          as Map<String, dynamic>;
      selection['mode'] = 'serial';
      await fixture.preferences
          .setString(fixture.mapping.slotStorageKey, jsonEncode(selection));
      await fixture.service.requestChanged(fixture.mapping.key);
      await fixture.service.backupPending();
      expect((await fixture.service.status(fixture.mapping)).issue,
          'source_changed');
      expect(generations.uploads, 1);
    });
  }

  for (final route in RetroArchBatteryRoute.values) {
    test(
        'automatic RetroArch ${route.platformId} preserves route and arms before launch',
        () async {
      capture.batterySize = route == RetroArchBatteryRoute.n64 ? 296960 : 4;
      final watches = <AutomaticSaveMapping>[];
      final fixture = await automaticFixture(
          retroArch: route, watch: (rows) async => watches.addAll(rows));
      expect(jsonDecode(fixture.mapping.encode())['route'], 'retroarch');
      expect(
          jsonDecode(fixture.mapping.encode())['platform'], route.platformId);
      expect(fixture.mapping.slot, 'owned%2FGame.srm');
      await fixture.service.requestChanged(fixture.mapping.key);
      await fixture.service.backupPending();
      expect(
          (await fixture.service.status(fixture.mapping)).outcome, 'verified');
      expect(generations.cloud.values.single.binding.coreId, route.coreId);
      expect(capture.ppssppSources, isEmpty);
      watches.clear();
      await fixture.service.prepareLaunch(
          artifactId: artifactId,
          editionId: 'edition',
          reviewRetroArchSave: (_) async => fixture.mapping.slot);
      expect(watches.single.key, fixture.mapping.key);
      expect(
          (await fixture.service.status(fixture.mapping)).outcome, 'unchanged');
      await fixture.preferences.remove(fixture.mapping.slotStorageKey);
      await fixture.service.reconcileWatches();
      expect(fixture.service.watchIssue, 'watch_unavailable');
    });
  }
  test('RetroArch pending save survives active content and retries on return',
      () async {
    final fixture = await automaticFixture(
        retroArch: RetroArchBatteryRoute.n64, watch: (_) async {});
    capture.batterySize = 296960;
    capture.captureIssue = 'close_content_required';
    await fixture.service.requestChanged(fixture.mapping.key);
    await fixture.service.backupPending();
    expect(generations.uploads, 0);
    expect((await fixture.service.status(fixture.mapping)).issue, isNotNull);
    capture.captureIssue = null;
    await fixture.service.checkEnabled();
    expect(generations.uploads, 1);
    expect((await fixture.service.status(fixture.mapping)).outcome, 'verified');
  });
  test('RetroArch launch rejects a changed installed save target before IO',
      () async {
    final fixture = await automaticFixture(
        retroArch: RetroArchBatteryRoute.n64, watch: (_) async {});
    capture.batterySize = 296960;
    await expectLater(
        fixture.service.prepareLaunch(
            artifactId: artifactId,
            editionId: 'edition',
            reviewRetroArchSave: (_) async => 'new-install%2FGame.srm'),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'source_changed')));
    expect(capture.captures, 0);
    expect(generations.uploads, 0);
  });

  for (final pending in [false, true]) {
    test(
        'RetroArch reviewed remap ${pending ? 'preserves pending work' : 'retires the former watch and keeps cloud history'}',
        () async {
      final watched = <List<String>>[];
      final fixture = await automaticFixture(
          retroArch: RetroArchBatteryRoute.n64,
          watch: (rows) async =>
              watched.add(rows.map((row) => row.slot).toList()));
      capture.batterySize = 296960;
      if (pending) capture.captureIssue = 'close_content_required';
      await fixture.service.requestChanged(fixture.mapping.key);
      await fixture.service.backupPending();
      final originalCloud = Map.of(generations.cloud);
      final replacementJob = SaveBackupGameJob(
          database: Future.value(db),
          capture: capture,
          areas: areas,
          generations: generations,
          clientId: 'client',
          accountId: 'account',
          areaId: 'area',
          editionId: 'edition',
          artifactId: artifactId,
          retroArchRoute: RetroArchBatteryRoute.n64,
          resolveSaveName: () async => 'new-install%2FGame.srm');
      final replacement = AutomaticSaveMapping.fromJob(replacementJob,
          title: 'Game', saveName: 'new-install%2FGame.srm');
      replacementJob.dispose();
      final enabling = fixture.service.setEnabled(replacement, true);
      if (pending) {
        await expectLater(
            enabling,
            throwsA(isA<PlatformException>().having(
                (error) => error.code, 'code', 'pending_save_operation')));
        expect((await fixture.service.status(replacement)).enabled, isFalse);
        expect(
            jsonDecode(fixture.preferences
                .getString(fixture.mapping.slotStorageKey)!)['name'],
            fixture.mapping.slot);
      } else {
        await enabling;
        expect(
            (await fixture.service.status(fixture.mapping)).enabled, isFalse);
        expect((await fixture.service.status(replacement)).enabled, isTrue);
        expect(watched.last, [replacement.slot]);
        expect(
            jsonDecode(fixture.preferences
                .getString(replacement.slotStorageKey)!)['name'],
            replacement.slot);
      }
      expect(generations.cloud, originalCloud);
    });
  }

  test(
      'automatic PSP save folders retain their route across persisted admission',
      () async {
    capture = _SavedataCapture();
    final watches = <List<AutomaticSaveMapping>>[];
    final fixture = await automaticFixture(
        savedata: true,
        watch: (mappings) async {
          watches.add(mappings);
        });
    expect(jsonDecode(fixture.mapping.encode())['route'], 'ppsspp-savedata');
    expect(fixture.mapping.slotStorageKey,
        startsWith('save_ppsspp_savedata_mapping_v1_'));
    expect(
        fixture.mapping.slotStorageKey,
        isNot(AutomaticSaveMapping.ppssppMappingKey(
            'client', 'account', 'edition', artifactId)));
    await fixture.service.reconcileWatches();
    expect(watches.last.single.encode(), fixture.mapping.encode());
    await fixture.service.requestChanged(fixture.mapping.key);
    await fixture.service.backupPending();
    expect((await fixture.service.status(fixture.mapping)).outcome, 'verified');
    expect(
        generations.cloud.values.single.binding.formatId, 'ppsspp-savedata-v1');
    expect(capture.ppssppSources.single, fixture.mapping.directory);
    await fixture.preferences.remove(fixture.mapping.slotStorageKey);
    await fixture.service.reconcileWatches();
    expect(watches.last, isEmpty);
    await fixture.service.requestChanged(fixture.mapping.key);
    await fixture.service.backupPending();
    expect(generations.uploads, 1);
    expect((await fixture.service.status(fixture.mapping)).issue, isNotNull);
  });

  test('schedule follows persisted opt-in and removes only after opt-out',
      () async {
    final scheduled = <bool>[];
    final fixture = await automaticFixture(schedule: (enabled) async {
      scheduled.add(enabled);
    });
    await fixture.service.reconcileSchedule();
    expect(scheduled, [true, true]);
    await fixture.service.setEnabled(fixture.mapping, false);
    expect(scheduled.last, isFalse);
    expect((await fixture.service.status(fixture.mapping)).enabled, isFalse);
  });

  test(
      'changing save location retires the exact RetroArch association and watch',
      () async {
    final watched = <List<String>>[];
    final fixture = await automaticFixture(
        retroArch: RetroArchBatteryRoute.mgba,
        watch: (mappings) async =>
            watched.add(mappings.map((m) => m.key).toList()));
    currentName = fixture.mapping.slot;
    final selection =
        fixture.preferences.getString(fixture.mapping.slotStorageKey);
    await fixture.service.reconcileWatches();
    expect(watched.last, [fixture.mapping.key]);
    await fixture.service.disableForJob(job, title: 'Game');
    expect((await fixture.service.status(fixture.mapping)).enabled, isFalse);
    expect(watched.last, isEmpty);
    expect(fixture.preferences.getString(fixture.mapping.slotStorageKey),
        selection);
    expect(capture.captures, 0);
    expect(generations.uploads, 0);
  });

  test('pre-launch waits for reconciliation and its enabled file watch',
      () async {
    var hold = false;
    final entered = Completer<void>();
    final armed = Completer<void>();
    final fixture = await automaticFixture(watch: (mappings) async {
      if (hold) {
        expect(mappings, hasLength(1));
        entered.complete();
        await armed.future;
      }
    });
    hold = true;
    var finished = false;
    final opening = fixture.service
        .prepareLaunch(artifactId: artifactId, editionId: 'edition')
        .then((_) => finished = true);
    await entered.future;
    expect(generations.uploads, 1);
    expect(finished, isFalse);
    armed.complete();
    await opening;
    expect(finished, isTrue);
    expect((await fixture.service.status(fixture.mapping)).outcome, 'verified');
  });
  test('pre-launch never implicitly enables an unmapped or disabled game',
      () async {
    final fixture = await automaticFixture(watch: (_) async {});
    await fixture.service.prepareLaunch(
        artifactId: RemoteArtifactId(
            providerId: 'drive',
            sourceId: 'source',
            accountId: 'account',
            providerFileId: 'other'));
    await fixture.service.setEnabled(fixture.mapping, false);
    await fixture.service
        .prepareLaunch(artifactId: artifactId, editionId: 'edition');
    expect(capture.captures, 0);
    expect(generations.uploads, 0);
  });
  test('launch offers other-device data before arming and remembers ignore',
      () async {
    final fixture = await automaticFixture(
        retroArch: RetroArchBatteryRoute.mgba, watch: (_) async {});
    await fixture.service.prepareLaunch(
        artifactId: artifactId,
        editionId: 'edition',
        reviewRetroArchSave: (_) async => fixture.mapping.slot);
    final own = generations.cloud.values.single;
    final peer = otherDevice(own);
    generations.cloud[peer.generationId] = peer;
    var offered = 0;
    Future<void> review(SaveBackupGameJob pending) async {
      offered++;
      expect(pending.suggestedDeviceBackups.single.encode(), peer.encode());
      expect(pending.busy, isFalse);
      await pending.setDeviceBackupIgnored(peer, true);
    }

    for (var i = 0; i < 2; i++) {
      await fixture.service.prepareLaunch(
          artifactId: artifactId,
          editionId: 'edition',
          reviewRetroArchSave: (_) async => fixture.mapping.slot,
          reviewDeviceBackups: review);
    }
    expect(offered, 1);
    expect(capture.restored, isEmpty);
    expect(generations.downloads, 0);
    expect((await fixture.service.status(fixture.mapping)).issue, isNull);
  });
  test(
      'ROM companion automatic work persists opt-in, admits changes and restores before watched launch',
      () async {
    capture.companionNested = true;
    final watched = <AutomaticSaveMapping>[];
    final fixture = await automaticFixture(
        romCompanion: true, watch: (rows) async => watched.addAll(rows));
    await fixture.service.checkEnabled();
    expect(generations.uploads, 1);
    expect(watched.last.isRomCompanion, isTrue);
    capture.digest = 'd' * 64;
    await fixture.service.requestChanged(fixture.mapping.key);
    await fixture.service.backupPending();
    expect(generations.uploads, 2);
    expect((await fixture.service.status(fixture.mapping)).outcome, 'verified');
    await db.delete('save_backup_game_jobs');
    capture.localAbsent = true;
    await fixture.service
        .prepareLaunch(artifactId: artifactId, editionId: 'edition');
    expect(capture.stagedGroups.last.toSet(),
        {'Game.png', 'Game.cache', 'Game/images/shot.png'});
    expect((await fixture.service.status(fixture.mapping)).outcome, 'restored');
    expect(generations.uploads, 2,
        reason: 'Absence must not publish an empty cloud generation');
  });

  test('automatic launch restores a missing PSP slot before arming its watch',
      () async {
    var preparingLaunch = false;
    var watchArmed = false;
    final fixture = await automaticFixture(watch: (mappings) async {
      if (preparingLaunch) {
        expect(capture.restored, hasLength(1));
        expect(mappings.single.slot, 'ULUS10041_1.00_0.ppst');
        watchArmed = true;
      }
    });
    await fixture.service.checkEnabled();
    final remote = generations.uploaded!;
    await db.delete('save_backup_game_jobs');
    capture.localAbsent = true;
    preparingLaunch = true;
    await fixture.service
        .prepareLaunch(artifactId: artifactId, editionId: 'edition');
    expect(watchArmed, isTrue);
    expect((await fixture.service.status(fixture.mapping)).outcome, 'restored');
    expect(generations.uploads, 1,
        reason: 'Missing local saves must not allocate empty cloud backups');
    expect(capture.stagedNames, ['ULUS10041_1.00_0.ppst']);
    expect(capture.stagedDirectories, ['/storage/emulated/0/PSP/PPSSPP_STATE']);
    final record = jsonDecode((await db.query('save_backup_game_jobs'))
        .single['record_json'] as String);
    expect(record['lastVerified']['generationId'], remote.generationId);
    expect(record['rollback'], isNull);
  });
  test('automatic first PSP launch arms its watch without fabricating a save',
      () async {
    capture.localAbsent = true;
    var watchArmed = false;
    final fixture = await automaticFixture(watch: (mappings) async {
      watchArmed = mappings.isNotEmpty;
    });
    await fixture.service
        .prepareLaunch(artifactId: artifactId, editionId: 'edition');
    expect(watchArmed, isTrue);
    expect((await fixture.service.status(fixture.mapping)).outcome, 'no_save');
    expect(generations.uploads, 0);
    expect(generations.downloads, 0);
    expect(capture.restored, isEmpty);
    expect(areas.reserved, 0);
  });
  test('an invalid unrelated mapping does not block a valid watched launch',
      () async {
    final watched = <String>[];
    final fixture = await automaticFixture(watch: (mappings) async {
      watched.addAll(mappings.map((mapping) => mapping.key));
    });
    await db.insert('automatic_save_backups', {
      'mapping_key': 'f' * 64,
      'record_json': '{}',
      'enabled': 1,
    });
    await fixture.service
        .prepareLaunch(artifactId: artifactId, editionId: 'edition');
    expect(watched, contains(fixture.mapping.key));
    expect(fixture.service.watchIssue, 'watch_unavailable',
        reason: 'The unrelated broken mapping must remain visible');
    expect((await fixture.service.status(fixture.mapping)).outcome, 'verified');
  });
  test('pre-launch surfaces divergence without arming a successful launch',
      () async {
    final fixture = await automaticFixture(watch: (_) async {});
    await fixture.service.checkEnabled();
    final base = generations.uploaded!;
    final head = _branch(base, 'peer-head');
    generations.cloud[head.generationId] = head;
    capture.digest = 'd' * 64;
    await expectLater(
        fixture.service
            .prepareLaunch(artifactId: artifactId, editionId: 'edition'),
        throwsA(isA<PlatformException>()
            .having((error) => error.code, 'code', 'save_conflict')));
    expect(capture.restored, isEmpty);
    expect(generations.uploads, 1);
    expect(
        (await fixture.service.status(fixture.mapping)).issue, 'save_conflict');
  });

  test('a missing watch receipt for this game still blocks its launch',
      () async {
    final failures = <String>{};
    final fixture =
        await automaticFixture(watch: (_) async {}, watchFailures: failures);
    failures.add(fixture.mapping.key);
    await expectLater(
        fixture.service.prepareLaunch(artifactId: artifactId),
        throwsA(isA<PlatformException>()
            .having((error) => error.code, 'code', 'watch_unavailable')));
    expect(fixture.service.watchIssue, 'watch_unavailable');
  });

  test('file watch requests only an explicitly enabled mapping', () async {
    final fixture = await automaticFixture();
    await fixture.service.requestChanged('f' * 64);
    await fixture.service.backupPending();
    expect(capture.captures, 0);
    await fixture.service.requestChanged(fixture.mapping.key);
    await fixture.service.backupPending();
    expect(generations.uploads, 1);
    expect((await fixture.service.status(fixture.mapping)).outcome, 'verified');
    await fixture.service.setEnabled(fixture.mapping, false);
    await fixture.service.requestChanged(fixture.mapping.key);
    await fixture.service.backupPending();
    expect(generations.uploads, 1);
    await expectLater(
        fixture.service.requestChanged('../other'), throwsFormatException);
  });

  test('protected PPSSPP watch retains its exact durable backup mapping',
      () async {
    const directory =
        '/storage/emulated/0/Android/data/org.ppsspp.ppsspp/files/PSP/PPSSPP_STATE';
    final watched = <AutomaticSaveMapping>[];
    final fixture = await automaticFixture(
        ppssppDirectory: directory,
        watch: (rows) async => watched.addAll(rows));
    expect(watched.single.directory, directory);
    expect(watched.single.key, fixture.mapping.key);
    watched.clear();
    await fixture.service.reconcileWatches();
    expect(watched.single.directory, directory);
    expect(watched.single.key, fixture.mapping.key);
    await fixture.service.requestChanged(fixture.mapping.key);
    await fixture.service.backupPending();
    expect(capture.ppssppSources, ['$directory/ULUS10041_1.00_0.ppst']);
    expect(capture.melonSources, isEmpty);
    expect(generations.uploads, 1);
    expect((await fixture.service.status(fixture.mapping)).outcome, 'verified');
    await fixture.preferences.remove(fixture.mapping.slotStorageKey);
    await fixture.service.reconcileWatches();
    expect(fixture.service.watchIssue, 'watch_unavailable');
  });

  test(
      'protected Melon watch enters the durable backup lane without borrowing PSP identity',
      () async {
    final watched = <AutomaticSaveMapping>[];
    final fixture = await automaticFixture(
        melon: true,
        watch: (rows) async {
          watched.addAll(rows);
        });
    expect(watched.single.key, fixture.mapping.key);
    expect(jsonDecode(fixture.mapping.encode())['route'], 'melon');
    expect(
        fixture.mapping.slotStorageKey, startsWith('save_melon_mapping_v1_'));
    await fixture.service.requestChanged(fixture.mapping.key);
    await fixture.service.backupPending();
    expect(capture.ppssppSources, isEmpty);
    expect(capture.melonSources, [
      '/storage/emulated/0/Android/data/me.magnum.melondualds/files/saves/Game.sav'
    ]);
    expect(generations.uploads, 1);
    expect((await fixture.service.status(fixture.mapping)).outcome, 'verified');
    await fixture.preferences.remove(fixture.mapping.slotStorageKey);
    await fixture.service.reconcileWatches();
    expect(fixture.service.watchIssue, 'watch_unavailable');
  });

  test('watch registration follows opt-in and rejects a changed association',
      () async {
    final watched = <List<AutomaticSaveMapping>>[];
    final fixture = await automaticFixture(watch: (mappings) async {
      watched.add(mappings);
    });
    expect(watched.single.single.key, fixture.mapping.key);
    await fixture.preferences.remove(fixture.mapping.slotStorageKey);
    await fixture.service.reconcileWatches();
    expect(watched.last, isEmpty);
    await fixture.service.setEnabled(fixture.mapping, false);
    expect(watched.last, isEmpty);
  });

  test('watch event is durable before the in-flight backup finishes', () async {
    final fixture = await automaticFixture();
    capture.held = Completer<void>();
    await fixture.service.requestChanged(fixture.mapping.key);
    final first = fixture.service.backupPending();
    await capture.started.future;
    await fixture.service.requestChanged(fixture.mapping.key);
    final second = fixture.service.backupPending();
    final row = (await db.query('automatic_save_backups',
            where: 'mapping_key = ?', whereArgs: [fixture.mapping.key]))
        .single;
    expect(row['requested'], 2);
    expect(row['handled'], 0);
    expect(capture.captures, 1);
    capture.held!.complete();
    await Future.wait([first, second]);
    expect(generations.uploads, 1,
        reason: 'The second identical capture must not duplicate publication');
    expect(
        (await fixture.service.status(fixture.mapping)).outcome, 'unchanged');
  });

  test('successful and unchanged checks retire only redundant local captures',
      () async {
    final fixture = await automaticFixture();
    await fixture.service.checkEnabled();
    await job.load();
    final verified = job.lastVerified;
    for (var i = 0; i < 3; i++) {
      await fixture.service.checkEnabled();
    }
    expect(capture.sealed, isEmpty);
    expect(capture.retired.toSet().length, 4);
    expect(generations.uploads, 1);
    await job.load();
    expect(job.lastVerified?.generationId, verified?.generationId);
    expect(
        (await fixture.service.status(fixture.mapping)).outcome, 'unchanged');
  });

  test('failed retirement is durable and retried before another capture',
      () async {
    capture.retirementIssue = 'capture_storage';
    capture.beforeRetirement = (id) async {
      final record = jsonDecode((await db.query('save_backup_game_jobs'))
          .single['record_json'] as String) as Map;
      expect(record['state'], 'complete');
      expect(record['retireCaptureId'], id);
      expect(record['captures'], isNull);
      expect(record['lastVerified'], isNotNull);
    };
    await job.backup('Game.srm');
    expect(job.issue, 'capture_cleanup_unavailable');
    expect(capture.captures, 1);
    final verifiedId = job.lastVerified!.generationId;
    final reopened = SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        resolveSaveName: () async => currentName);
    addTearDown(reopened.dispose);
    await reopened.backup('Game.srm');
    expect(reopened.issue, 'capture_cleanup_unavailable');
    expect(capture.captures, 1,
        reason: 'No more staging while cleanup is pending');
    capture.retirementIssue = null;
    await reopened.backup('Game.srm');
    expect(reopened.issue, isNull);
    expect(reopened.lastVerified!.generationId, verifiedId);
    expect(capture.sealed, isEmpty);
    expect(generations.uploads, 1);
  });

  test('interrupted upload keeps its capture until verified recovery',
      () async {
    generations.fail = true;
    await job.backup(currentName);
    final pendingId = capture.sealed.keys.single;
    expect(capture.retired, isEmpty);
    expect(job.lastVerified, isNull);
    generations.fail = false;
    await job.backup(currentName);
    expect(job.issue, isNull);
    expect(capture.captures, 1);
    expect(capture.retired, [pendingId]);
    expect(capture.sealed, isEmpty);
  });

  test('retirement rejects a completed journal without a last-good backup',
      () async {
    await job.backup(currentName);
    final row = (await db.query('save_backup_game_jobs')).single;
    final record =
        jsonDecode(row['record_json'] as String) as Map<String, dynamic>;
    final id = record['captureId'] as String;
    capture.retired.clear();
    await db.update(
        'save_backup_game_jobs',
        {
          'record_json': jsonEncode(
              {...record, 'lastVerified': null, 'retireCaptureId': id})
        },
        where: 'job_key = ?',
        whereArgs: [row['job_key']]);
    await job.backup(currentName);
    expect(capture.retired, isEmpty);
    expect(capture.captures, 1);
    expect(job.issue, isNotNull);
  });

  test('another pending job reference prevents exact capture retirement',
      () async {
    capture.retirementIssue = 'capture_storage';
    await job.backup(currentName);
    final row = (await db.query('save_backup_game_jobs')).single;
    final record =
        jsonDecode(row['record_json'] as String) as Map<String, dynamic>;
    final id = record['captureId'] as String;
    final foreign = {
      ...record,
      'key': 'other-job',
      'state': 'pending',
      'captures': {'member': '/private/$id/member-0'},
      'retireCaptureId': null
    };
    await db.insert('save_backup_game_jobs',
        {'job_key': 'other-job', 'record_json': jsonEncode(foreign)});
    capture.retirementIssue = null;
    await job.backup(currentName);
    expect(job.issue, isNull);
    expect(capture.sealed.keys, [id]);
    expect(capture.retired, isNot(contains(id)));
    expect(
        (await db.query('save_backup_game_jobs',
                where: 'job_key = ?', whereArgs: ['other-job']))
            .single['record_json'],
        jsonEncode(foreign));
  });

  test('resolved conflict retains its separately journaled local branch',
      () async {
    await job.backup(currentName);
    final original = job.lastVerified!;
    generations.cloud['branch'] = _branch(original, 'branch');
    await job.backup(currentName);
    final conflictId = capture.sealed.keys.single;
    expect(job.issue, 'save_conflict');
    final heads = job.conflicts.map((head) => head.generationId).toSet();
    await job.keepLocalConflict(heads);
    expect(job.issue, isNull);
    expect(job.phase, 'verified');
    expect(capture.sealed.containsKey(conflictId), isTrue);
    expect(capture.retired, isNot(contains(conflictId)));
    expect(await db.query('save_backup_conflict_captures'), hasLength(1));
    await job.backup(currentName);
    expect(job.phase, 'unchanged');
    expect(capture.sealed.keys, [conflictId]);
  });

  test('retirement never removes a retained restore rollback capture',
      () async {
    await job.backup(currentName);
    capture.digest = 'd' * 64;
    await job.restoreLatest();
    final rollbackId = capture.restored.single.rollback;
    expect(capture.sealed.containsKey(rollbackId), isTrue);
    capture.digest = 'b' * 64;
    await job.backup(currentName);
    expect(job.issue, isNull);
    expect(capture.sealed.keys, [rollbackId]);
    expect(capture.retired, isNot(contains(rollbackId)));
    expect(job.rollbackAvailable, isTrue);
  });

  test(
      'restore can create a missing local save without offering a fake rollback',
      () async {
    await job.backup(currentName);
    final verified = job.lastVerified!;
    capture.localAbsent = true;
    await job.restoreLatest();
    expect(job.issue, isNull);
    expect(job.phase, 'restored');
    expect(capture.restored, hasLength(1));
    expect(job.lastVerified!.encode(), verified.encode());
    expect(job.rollbackAvailable, isFalse);
    expect(generations.uploads, 1);
    final record = jsonDecode((await db.query('save_backup_game_jobs'))
        .single['record_json'] as String);
    expect(record['restore']['localWasAbsent'], isTrue);
    await job.rollbackLast();
    expect(job.issue, 'no_retained_rollback');
    expect(capture.restored, hasLength(1));
  });

  test(
      'missing local restore keeps its absence receipt across failed publication',
      () async {
    await job.backup(currentName);
    capture.localAbsent = true;
    capture.publicationIssue = 'source_changed';
    await job.restoreLatest();
    expect(job.issue, 'source_changed');
    expect(job.rollbackAvailable, isFalse);
    final before = jsonDecode((await db.query('save_backup_game_jobs'))
        .single['record_json'] as String)['restore'];
    expect(before['localWasAbsent'], isTrue);
    capture.publicationIssue = null;
    await job.restoreLatest();
    expect(job.issue, isNull);
    final after = jsonDecode((await db.query('save_backup_game_jobs'))
        .single['record_json'] as String)['restore'];
    expect(after['id'], before['id']);
    expect(after['rollbackId'], before['rollbackId']);
    expect(job.rollbackAvailable, isFalse);
  });

  test(
      'an absent related SRAM and clock group restores both roles without rollback',
      () async {
    capture.includeRtc = true;
    await job.backup(currentName);
    capture.localAbsent = true;
    await job.restoreLatest();
    expect(job.issue, isNull);
    expect(capture.stagedGroups.single, ['Game.rtc', 'Game.srm']);
    expect(job.rollbackAvailable, isFalse);
    expect(generations.uploads, 1);
  });

  test(
      'scheduler failure stays visible without blocking manual or return backup',
      () async {
    final fixture = await automaticFixture(schedule: (_) async {
      throw PlatformException(code: 'schedule_unavailable');
    });
    expect(fixture.service.backgroundIssue, 'schedule_unavailable');
    expect((await fixture.service.status(fixture.mapping)).enabled, isTrue);
    await fixture.service.checkEnabled();
    expect((await fixture.service.status(fixture.mapping)).outcome, 'verified');
    expect(generations.uploads, 1);
  });

  test('background stop joins active capture and cancels already queued events',
      () async {
    final fixture = await automaticFixture();
    capture.held = Completer<void>();
    final first = fixture.service.checkEnabled();
    await capture.started.future;
    final queued = fixture.service.checkEnabled();
    await fixture.service.cancelAndJoin();
    await Future.wait([first, queued]);
    expect(capture.captures, 1);
    expect(generations.uploads, 0);
    expect((await fixture.service.status(fixture.mapping)).enabled, isTrue);
  });

  test('background receipt distinguishes checked mappings from failed backups',
      () async {
    final fixture = await automaticFixture();
    await fixture.service.checkEnabled();
    expect(await fixture.service.passSummary(), {
      'enabled': 1,
      'pending': 0,
      'retryable': 0,
      'verified': 1,
      'unchanged': 0,
      'attention': 0
    });
    await fixture.service.checkEnabled();
    expect((await fixture.service.passSummary())['unchanged'], 1);
    capture.digest = 'd' * 64;
    generations.fail = true;
    await fixture.service.checkEnabled();
    final summary = await fixture.service.passSummary();
    expect(summary['attention'], 1);
    expect(summary['verified'], 0);
    expect(summary['unchanged'], 0);
  });

  test('automatic checks retain conflicts without making a resolution choice',
      () async {
    final fixture = await automaticFixture();
    await fixture.service.checkEnabled();
    final first = generations.cloud.values.single;
    final peer = _branch(first, 'peer');
    generations.cloud[peer.generationId] = peer;
    capture.digest = 'd' * 64;
    await fixture.service.checkEnabled();
    expect(
        (await fixture.service.status(fixture.mapping)).issue, 'save_conflict');
    final captures = capture.captures;
    await fixture.service.checkEnabled();
    expect(capture.captures, captures,
        reason: 'No repeated capture while an explicit choice is pending');
    expect(generations.uploads, 1);
    expect(generations.cloud.keys.toSet(),
        {first.generationId, peer.generationId});
  });
  test(
      'automatic offline recovery reuses reserved objects and respects pending restore',
      () async {
    final fixture = await automaticFixture();
    await fixture.service.checkEnabled();
    final first = generations.cloud.values.single;
    capture.digest = 'd' * 64;
    generations.fail = true;
    await fixture.service.checkEnabled();
    final reserved = generations.uploaded!.generationId;
    expect(
        (await fixture.service.status(fixture.mapping)).issue, 'unavailable');
    expect(generations.cloud.keys, [first.generationId]);
    generations.fail = false;
    await fixture.service.checkEnabled();
    expect(generations.uploaded!.generationId, reserved);
    expect((await fixture.service.status(fixture.mapping)).outcome, 'verified');
    final manual = fixture.service.createJob!(
        fixture.mapping, () async => fixture.mapping.slot);
    generations.failDownload = true;
    await manual.restoreLatest();
    expect(manual.restorePending, isTrue);
    final uploads = generations.uploads;
    await fixture.service.checkEnabled();
    expect((await fixture.service.status(fixture.mapping)).issue,
        'pending_restore');
    expect(generations.uploads, uploads);
    manual.dispose();
  });
  test('queued offline upload rechecks remote conflicts on late syncing',
      () async {
    final fixture = await automaticFixture();
    await fixture.service.checkEnabled();
    final base = generations.cloud.values.single;
    capture.digest = 'd' * 64;
    generations.fail = true;
    await fixture.service.requestChanged(fixture.mapping.key);
    await fixture.service.backupPending();
    final reserved = generations.uploaded!.generationId;
    expect((await fixture.service.passSummary())['pending'], 1,
        reason: 'An unsuccessful upload is still queued');
    final peer = _branch(base, 'late-peer');
    generations.cloud[peer.generationId] = peer;
    generations.fail = false;
    final attempts = generations.uploads;
    await fixture.service.cancelAndJoin();
    final resumed = AutomaticSaveBackups(
        database: Future.value(db),
        preferences: fixture.preferences,
        sources: fixture.service.sources,
        createJob: fixture.service.createJob);
    addTearDown(() async {
      await resumed.cancelAndJoin();
      resumed.dispose();
    });
    await resumed.backupPending();
    expect((await resumed.status(fixture.mapping)).issue, 'save_conflict');
    expect(generations.uploads, attempts,
        reason: 'Reconnect must review the remote folder before publication');
    expect(generations.uploaded!.generationId, reserved);
    expect(
        generations.cloud.keys.toSet(), {base.generationId, peer.generationId});
    expect(capture.sealed, isNotEmpty,
        reason: 'The unpublished local branch remains recoverable');
  });
  test('offline play arms the watch and queues without cloud IO', () async {
    var online = false;
    var scheduled = 0;
    final watched = <AutomaticSaveMapping>[];
    final fixture = await automaticFixture(
        network: () async => online,
        pending: () async {
          scheduled++;
        },
        watch: (mappings) async => watched.addAll(mappings));
    await fixture.service.prepareLaunch(artifactId: artifactId);
    expect(
        watched.map((mapping) => mapping.key), contains(fixture.mapping.key));
    expect(scheduled, greaterThan(0));
    expect((await fixture.service.status(fixture.mapping)).issue, 'offline');
    await fixture.service.backupPending();
    expect(capture.captures, 0);
    expect(areas.reserved, 0);
    expect(generations.uploads, 0);
    expect((await fixture.service.passSummary())['pending'], 1);
    online = true;
    await fixture.service.backupPending();
    expect((await fixture.service.status(fixture.mapping)).outcome, 'verified');
    expect((await fixture.service.passSummary())['pending'], 0);
    expect(generations.uploads, 1);
  });
  test(
      'disabling automatic capture joins cancellation and persists the opt-out',
      () async {
    final fixture = await automaticFixture();
    capture.held = Completer<void>();
    final operation = fixture.service.checkEnabled();
    await capture.started.future;
    await fixture.service.setEnabled(fixture.mapping, false);
    await operation;
    expect((await fixture.service.status(fixture.mapping)).enabled, isFalse);
    expect(generations.uploads, 0);
    await fixture.service.checkEnabled();
    expect(capture.captures, 1);
  });
  test('mapping changes while automatic capture runs prevent publication',
      () async {
    final fixture = await automaticFixture();
    capture.held = Completer<void>();
    final operation = fixture.service.checkEnabled();
    await capture.started.future;
    await fixture.preferences.setString(
        fixture.mapping.slotStorageKey,
        jsonEncode({
          'directory': fixture.mapping.directory,
          'slot': 'ULUS10041_1.00_1.ppst'
        }));
    capture.held!.complete();
    await operation;
    expect((await fixture.service.status(fixture.mapping)).issue,
        'source_changed');
    expect(generations.uploads, 0);
  });
  test(
      'repeated lifecycle events serialize capture and avoid duplicate publication',
      () async {
    final fixture = await automaticFixture();
    capture.held = Completer<void>();
    final first = fixture.service.checkEnabled();
    await capture.started.future;
    final second = fixture.service.checkEnabled();
    expect(capture.captures, 1);
    capture.held!.complete();
    await Future.wait([first, second]);
    expect(generations.uploads, 1);
    expect(
        (await fixture.service.status(fixture.mapping)).outcome, 'unchanged');
  });
  test(
      'unchanged capture retains the sole verified cloud generation after reopen',
      () async {
    await job.backup(currentName);
    final first = job.lastVerified!;
    await job.backup(currentName);
    expect(job.issue, isNull);
    expect(job.phase, 'unchanged');
    expect(generations.uploads, 1);
    expect(job.lastVerified!.generationId, first.generationId);
    expect(job.pendingName, isNull);
    final reopened = SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        resolveSaveName: () async => currentName);
    await reopened.load();
    expect(reopened.lastVerified!.generationId, first.generationId);
    expect(reopened.pendingName, isNull);
    reopened.dispose();
  });
  test(
      'PPSSPP screenshot publishes a portable companion and restores its exact leaf',
      () async {
    await LibraryStore(Future.value(db)).putGame(GameIdentity(
        id: 'game',
        platformId: 'psp',
        title: 'Game',
        matchStatus: IdentityMatchStatus.manuallyMatched));
    const name = 'ULUS10041_1.00_0.jpg';
    const directory = '/storage/emulated/0/PSP/PPSSPP_STATE';
    final companion = SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        ppssppDirectory: directory,
        ppssppSlot: name,
        ppssppCompanion: true,
        resolveSaveName: () async => name);
    addTearDown(companion.dispose);
    await companion.backup(name);
    expect(companion.issue, isNull);
    expect(companion.lastVerified!.binding.kind, SaveBackupKind.companion);
    expect(companion.lastVerified!.binding.companionCompatibility,
        SaveCompanionCompatibility.portable);
    expect(
        companion.lastVerified!.binding.formatId, 'ppsspp-screenshot-jpeg-v1');
    await companion.restoreLatest();
    expect(companion.issue, isNull);
    expect(capture.stagedNames, [name]);
    expect(capture.stagedDirectories, [directory]);
    expect(capture.restored, hasLength(1));
  });

  test('configured shared card has one history across initiating ROMs',
      () async {
    final otherArtifact = RemoteArtifactId(
        providerId: 'drive',
        sourceId: 'source',
        accountId: 'account',
        providerFileId: 'other-card-game');
    final store = LibraryStore(Future.value(db));
    await store.putGame(GameIdentity(
        id: 'other-game',
        platformId: 'gba',
        title: 'Other',
        matchStatus: IdentityMatchStatus.manuallyMatched));
    await store.putEdition(EditionIdentity(
        id: 'other-edition',
        gameId: 'other-game',
        members: [EditionMember(artifactId: otherArtifact)]));
    final config = SaveRootConfiguration.decode({
      'schema': 1,
      'directory': '/storage/emulated/0/Emulator/memcards',
      'emulator': 'example.emulator',
      'core': 'example',
      'kind': 'save',
      'format': 'memory-card-v1',
      'resourceId': 'card-1',
      'files': ['Mcd001.ps2'],
      'folders': <String>[],
      'required': ['Mcd001.ps2']
    });
    capture.configuredRoot = config;
    SaveBackupGameJob make(String edition, RemoteArtifactId artifact) =>
        SaveBackupGameJob(
            database: job.database,
            capture: capture,
            areas: areas,
            generations: generations,
            clientId: 'client',
            accountId: 'account',
            areaId: 'area',
            editionId: edition,
            artifactId: artifact,
            resolveSaveName: () async => 'shared-card-1.save',
            resolveRomCompanionGrant: () async => {
                  'installationId': edition,
                  'filename': '$edition.7z',
                  'saveRoot': config.toJson()
                },
            saveRootConfiguration: config,
            romCompanionDirectory: config.directory,
            romCompanionName: 'shared-card-1.save',
            romCompanionPlatform: 'gba',
            romCompanionEmulator: config.emulator,
            romCompanionCore: config.core);
    final first = make('edition', artifactId);
    final second = make('other-edition', otherArtifact);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await first.backup('shared-card-1.save');
    expect(first.issue, isNull);
    final original = first.lastVerified!;
    await second.backup('shared-card-1.save');
    expect(second.issue, isNull);
    expect(second.phase, 'unchanged');
    expect(generations.uploads, 1);
    capture.digest = 'e' * 64;
    await second.backup('shared-card-1.save');
    expect(second.issue, isNull);
    expect(second.lastVerified!.parentGenerationIds, [original.generationId]);
    expect(await db.query('save_backup_game_jobs'), hasLength(1));
    await first.restoreLatest();
    expect(first.issue, isNull);
    expect(first.phase, 'restored');
    await first.rollbackLast();
    expect(first.issue, isNull);
    expect(first.phase, 'rolled_back');
  });

  for (final kind in SaveBackupKind.values) {
    test(
        'configured ${kind.name} roots use the same durable backup and restore job',
        () async {
      final config = SaveRootConfiguration.decode({
        'schema': 1,
        'directory': '/storage/emulated/0/Emulator/${kind.name}',
        'emulator': 'com.retroarch.aarch64',
        'core': 'mgba',
        'kind': kind.name,
        'format': 'configured-${kind.name}-v1',
        if (kind != SaveBackupKind.save)
          'runtimeFiles': [
            '/data/user/0/com.retroarch.aarch64/cores/mgba_libretro_android.so'
          ],
        'files': ['Game.sav', 'Game.rtc'],
        'folders': <String>[],
        'required': ['Game.sav', 'Game.rtc'],
      });
      capture.configuredRoot = config;
      final configured = SaveBackupGameJob(
          database: job.database,
          capture: capture,
          areas: areas,
          generations: generations,
          clientId: 'client',
          accountId: 'account',
          areaId: 'area',
          editionId: 'edition',
          artifactId: artifactId,
          resolveSaveName: () async => 'Game.7z',
          resolveRomCompanionGrant: () async => {
                'installationId': 'owned',
                'filename': 'Game.7z',
                'saveRoot': config.toJson()
              },
          saveRootConfiguration: config,
          romCompanionDirectory: config.directory,
          romCompanionName: 'Game.7z',
          romCompanionPlatform: 'gba',
          romCompanionEmulator: config.emulator,
          romCompanionCore: config.core);
      addTearDown(configured.dispose);
      final mapping = AutomaticSaveMapping.fromJob(configured,
          title: 'Game', romRoot: '/storage/emulated/0/Roms/gba');
      expect(jsonDecode(mapping.encode())['saveRoot'], config.toJson());
      await configured.backup('Game.7z');
      expect(configured.issue, isNull);
      expect(configured.lastVerified!.binding.kind, kind);
      expect(configured.lastVerified!.binding.formatId, config.format);
      if (kind == SaveBackupKind.state) {
        expect(configured.lastVerified!.binding.coreVersion,
            capture.runtimeFingerprint);
      }
      expect(
          configured.lastVerified!.binding.companionCompatibility,
          kind == SaveBackupKind.companion
              ? SaveCompanionCompatibility.runtime
              : null);
      await configured.load();
      await configured.restoreLatest();
      expect(configured.issue, isNull);
      expect(capture.stagedGroups.last.toSet(), {'Game.sav', 'Game.rtc'});
      expect(configured.rollbackAvailable, isTrue);
      if (kind == SaveBackupKind.state) {
        final staged = capture.stagedGroups.length;
        capture.runtimeFingerprint = 'e' * 64;
        final uploads = generations.uploads;
        await configured.backup('Game.7z');
        expect(configured.issue, 'incompatible_state');
        expect(generations.uploads, uploads,
            reason:
                'unchanged old state must not be relabelled as a new-core state');
        expect(configured.lastVerified!.binding.coreVersion, 'd' * 64);
        await configured.restoreLatest();
        expect(configured.issue, 'incompatible_state');
        expect(capture.stagedGroups.length, staged);
      }
    });
  }

  test(
      'ROM companion job publishes runtime-bound files and imports only selected members',
      () async {
    capture.companionNested = true;
    final companion = SaveBackupGameJob(
        database: job.database,
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        resolveSaveName: () async => 'Game.7z',
        resolveRomCompanionGrant: () async =>
            {'installationId': 'owned', 'filename': 'Game.7z'},
        romCompanionName: 'Game.7z',
        romCompanionDirectory: '/storage/emulated/0/Roms/gba',
        romCompanionPlatform: 'gba',
        romCompanionEmulator: 'com.retroarch.aarch64',
        romCompanionCore: 'mgba');
    addTearDown(companion.dispose);
    final mapping = AutomaticSaveMapping.fromJob(companion,
        title: 'Game', romRoot: '/storage/emulated/0/Roms/gba');
    expect(mapping.isRomCompanion, isTrue);
    expect(mapping.directory, '/storage/emulated/0/Roms/gba');
    await companion.backup('Game.7z');
    expect(companion.issue, isNull);
    final local = companion.lastVerified!;
    expect(local.binding.kind, SaveBackupKind.companion);
    expect(local.binding.companionCompatibility,
        SaveCompanionCompatibility.runtime);
    expect(local.members.map((member) => member.relativePath).toSet(),
        {'Game.cache', 'Game.png', 'Game/images/shot.png'});
    final peer = SaveBackupManifest(
        generationId: 'other-device-copy',
        binding: SaveBackupBinding.fromJson(
            {...local.binding.toJson(), 'deviceId': 'second-device'}),
        parentGenerationIds: [],
        createdAt: DateTime.utc(2090),
        members: [
          for (var index = 0; index < local.members.length; index++)
            SaveBackupMember(
                relativePath: local.members[index].relativePath,
                cloudFileId: 'peer-member-$index',
                sizeBytes: local.members[index].sizeBytes,
                sha256: 'c' * 64),
        ]);
    generations.cloud[peer.generationId] = peer;
    await companion.reconcileBeforeLaunch('Game.7z');
    await companion.importDeviceBackup(peer,
        memberPaths: {'Game.png', 'Game/images/shot.png'});
    expect(companion.issue, isNull);
    expect(capture.stagedGroups.map((group) => group.toSet()), [
      {'Game.png', 'Game/images/shot.png'}
    ]);
    expect(capture.restored, hasLength(1));
    expect(companion.rollbackAvailable, isTrue);
    await companion.load();
    expect(companion.deviceBackupMemberSelected(peer, 'Game.png'), isTrue);
    expect(companion.deviceBackupMemberSelected(peer, 'Game.cache'), isFalse);
    await companion.rollbackLast();
    expect(companion.issue, isNull);
    expect(capture.stagedGroups.map((group) => group.toSet()), [
      {'Game.png', 'Game/images/shot.png'},
      {'Game.png', 'Game/images/shot.png'}
    ]);
  });

  test('companion file import rejects unrelated paths and remembers the choice',
      () async {
    const name = 'ULUS10041_1.00_0.jpg';
    final companion = SaveBackupGameJob(
        database: job.database,
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        ppssppDirectory: '/storage/emulated/0/PSP/PPSSPP_STATE',
        ppssppSlot: name,
        ppssppCompanion: true,
        resolveSaveName: () async => name);
    addTearDown(companion.dispose);
    await LibraryStore(Future.value(db)).putGame(GameIdentity(
        id: 'game',
        platformId: 'psp',
        title: 'Game',
        matchStatus: IdentityMatchStatus.manuallyMatched));
    await companion.backup(name);
    final peer = otherDevice(companion.lastVerified!);
    generations.cloud[peer.generationId] = peer;
    await companion.reconcileBeforeLaunch(name);
    final captures = capture.captures;
    await companion.importDeviceBackup(peer, memberPaths: {});
    expect(companion.issue, 'device_import_selection');
    await companion.importDeviceBackup(peer, memberPaths: {'unrelated.jpg'});
    expect(companion.issue, 'device_import_selection');
    expect(capture.captures, captures);
    expect(capture.restored, isEmpty);
    expect(generations.downloads, 0);
    await companion.importDeviceBackup(peer, memberPaths: {name});
    expect(companion.issue, isNull);
    expect(capture.stagedNames, [name]);
    expect(capture.restored, hasLength(1));
    expect(companion.rollbackAvailable, isTrue);
    await companion.load();
    expect(companion.deviceBackupMemberSelected(peer, name), isTrue);
    await companion.setDeviceBackupIgnored(peer, true);
    expect(companion.deviceBackupMemberSelected(peer, name), isFalse);
    await companion.setDeviceBackupIgnored(peer, false);
    expect(companion.deviceBackupMemberSelected(peer, name), isFalse);
  });

  testWidgets(
      'companion chooser keeps independent file choices across sections',
      (tester) async {
    const name = 'ULUS10041_1.00_0.jpg';
    final ui = _UiJob(SaveBackupGameJob(
        database: job.database,
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        ppssppDirectory: '/storage/emulated/0/PSP/PPSSPP_STATE',
        ppssppSlot: name,
        ppssppCompanion: true,
        resolveSaveName: () async => name))
      ..namesFixture = [name];
    addTearDown(ui.dispose);
    final peer = SaveBackupManifest(
        generationId: 'companion-peer',
        binding: SaveBackupBinding(
            accountId: 'account',
            deviceId: 'second-device',
            emulatorPackage: 'org.ppsspp.ppsspp',
            emulatorVersion: 'v1.20.4',
            coreId: 'ppsspp',
            coreVersion: 'unreported',
            platformId: 'psp',
            editions: [SaveBackupEdition(gameId: 'game', editionId: 'edition')],
            kind: SaveBackupKind.companion,
            formatId: 'ppsspp-screenshot-jpeg-v1',
            companionCompatibility: SaveCompanionCompatibility.portable),
        parentGenerationIds: [],
        createdAt: DateTime.utc(2090),
        members: [
          for (final slot in [0, 1])
            SaveBackupMember(
                relativePath: 'ULUS10041_1.00_$slot.jpg',
                cloudFileId: 'peer-member-$slot',
                sizeBytes: 4,
                sha256: 'c' * 64)
        ]);
    ui.deviceCopiesFixture = [peer];
    await tester.pumpWidget(createTestApp(Scaffold(
        body: SingleChildScrollView(
            child: SaveBackupGamePanel(
                job: ui, title: 'Game', section: SaveBackupSection.restore)))));
    await tester.pumpAndSettle();
    final open = find.byKey(const ValueKey('save-other-devices'));
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-device-files-section')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('save-device-group')), findsNothing);
    final file = find.byKey(const ValueKey('save-device-file-$name'));
    final otherFile =
        find.byKey(const ValueKey('save-device-file-ULUS10041_1.00_1.jpg'));
    expect(tester.widget<CheckboxListTile>(file).value, isFalse);
    expect(tester.widget<CheckboxListTile>(otherFile).value, isFalse);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('save-device-import')))
            .onPressed,
        isNull);
    await tester.tap(file);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-device-source-section')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-device-files-section')));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(file).value, isTrue);
    expect(tester.widget<CheckboxListTile>(otherFile).value, isFalse);
    await tester.tap(find.byKey(const ValueKey('save-device-import')));
    await tester.pumpAndSettle();
    expect(ui.deviceImports.single.copy.encode(), peer.encode());
    expect(ui.deviceImports.single.paths, {name});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
      'automatic mapped slot is opt-in, durable and skips identical publication',
      () async {
    await LibraryStore(Future.value(db)).putGame(GameIdentity(
        id: 'game',
        platformId: 'psp',
        title: 'Game',
        matchStatus: IdentityMatchStatus.manuallyMatched));
    const directory = '/storage/emulated/0/PSP/PPSSPP_STATE';
    const slot = 'ULUS10041_1.00_0.ppst';
    final psp = SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        ppssppDirectory: directory,
        ppssppSlot: slot,
        resolveSaveName: () async => slot);
    addTearDown(psp.dispose);
    final mapping = AutomaticSaveMapping.fromJob(psp, title: 'Game');
    SharedPreferences.setMockInitialValues({
      SaveBackupSetup.storageKey('client', 'account'):
          jsonEncode({'ready': true, 'areaId': 'area'}),
      mapping.slotStorageKey:
          jsonEncode({'directory': directory, 'slot': slot}),
    });
    final preferences = await SharedPreferences.getInstance();
    var sources = [
      const Source(
          id: 'source',
          name: 'Drive',
          type: SourceType.drive,
          drive: DriveSourceConfig(
              accountId: 'account',
              rootFolderId: 'root',
              serverClientId: 'client'))
    ];
    AutomaticSaveBackups open() => AutomaticSaveBackups(
        database: Future.value(db),
        preferences: preferences,
        sources: () => sources,
        createJob: (mapped, resolve) => SaveBackupGameJob(
            database: Future.value(db),
            capture: capture,
            areas: areas,
            generations: generations,
            clientId: mapped.clientId,
            accountId: mapped.accountId,
            areaId: mapped.areaId,
            editionId: mapped.editionId,
            artifactId: mapped.artifactId,
            ppssppDirectory: mapped.directory,
            ppssppSlot: mapped.slot,
            resolveSaveName: resolve));
    final automatic = open();
    await automatic.checkEnabled();
    expect(capture.captures, 0,
        reason: 'Never enable an unmapped game implicitly');
    await automatic.setEnabled(mapping, true);
    await automatic.checkEnabled();
    expect(generations.uploads, 1);
    expect((await automatic.status(mapping)).outcome, 'verified');
    final reopened = open();
    expect((await reopened.status(mapping)).enabled, isTrue);
    await reopened.checkEnabled();
    expect(generations.uploads, 1);
    expect((await reopened.status(mapping)).outcome, 'unchanged');
    capture.digest = 'd' * 64;
    await reopened.checkEnabled();
    expect(generations.uploads, 2);
    sources = [];
    await reopened.checkEnabled();
    expect(generations.uploads, 2);
    expect((await reopened.status(mapping)).issue, 'source_changed');
    await reopened.setEnabled(mapping, false);
    expect((await open().status(mapping)).enabled, isFalse);
    await reopened.checkEnabled();
    expect(generations.uploads, 2);
    automatic.dispose();
    reopened.dispose();
  });
  test(
      'identical local capture cannot skip a missing verified cloud generation',
      () async {
    await job.backup(currentName);
    final first = job.lastVerified!.generationId;
    generations.cloud.clear();
    await job.backup(currentName);
    expect(job.issue, isNull);
    expect(job.phase, 'verified');
    expect(generations.uploads, 2);
    expect(job.lastVerified!.generationId, isNot(first));
  });
  test('unchanged local bytes still surface a divergent cloud head', () async {
    await job.backup(currentName);
    final first = job.lastVerified!;
    final peer = _branch(first, 'changed-peer');
    generations.cloud[peer.generationId] = peer;
    await job.backup(currentName);
    expect(job.issue, 'save_conflict');
    expect(generations.uploads, 1);
    expect(job.lastVerified!.generationId, first.generationId);
    expect(job.conflicts.single.generationId, peer.generationId);
  });
  test('pre-launch restores a proven cloud descendant of unchanged local bytes',
      () async {
    await job.backup(currentName);
    final base = job.lastVerified!;
    final middle = _branch(base, 'peer-middle');
    final head = _branch(middle, 'peer-head');
    generations.cloud[middle.generationId] = middle;
    generations.cloud[head.generationId] = head;
    await job.reconcileBeforeLaunch(currentName);
    expect(job.issue, isNull);
    expect(job.phase, 'restored');
    expect(job.lastVerified!.generationId, head.generationId);
    expect(capture.restored, hasLength(1));
    expect(capture.stagedNames, [currentName]);
    expect(generations.uploads, 1,
        reason: 'The unchanged ancestor is already recoverable in cloud');
    expect(capture.captures, 2,
        reason: 'Restore must reuse the exact pre-review rollback capture');
    expect(job.rollbackAvailable, isTrue);
    expect(job.restorePending, isFalse);
  });
  test('pre-launch discovers a missing save after local job receipts are lost',
      () async {
    await job.backup(currentName);
    final remote = job.lastVerified!;
    final reserved = areas.reserved;
    await db
        .delete('save_backup_game_jobs'); // Model reinstall, not cloud loss.
    job.dispose();
    job = SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        resolveSaveName: () async => currentName);
    capture.localAbsent = true;
    await job.reconcileBeforeLaunch(currentName);
    expect(job.issue, isNull);
    expect(job.phase, 'restored');
    expect(job.lastVerified!.encode(), remote.encode());
    expect(job.rollbackAvailable, isFalse);
    expect(capture.restored, hasLength(1));
    expect(generations.uploads, 1);
    expect(areas.reserved, reserved, reason: 'No empty backup is reserved');
  });
  test('pre-launch missing save with no cloud history does not invent a backup',
      () async {
    capture.localAbsent = true;
    await job.reconcileBeforeLaunch(currentName);
    expect(job.issue, isNull);
    expect(job.phase, 'no_save');
    expect(job.lastVerified, isNull);
    expect(job.pendingName, isNull);
    expect(job.restorePending, isFalse);
    expect(generations.uploads, 0);
    expect(areas.reserved, 0);
    expect(capture.retired, hasLength(1));
    await job.load();
    await job.reconcileBeforeLaunch(currentName);
    expect(job.phase, 'no_save');
    expect(generations.uploads, 0);
  });
  test(
      'missing pre-launch cloud download resumes without a fake last-good receipt',
      () async {
    await job.backup(currentName);
    final remote = job.lastVerified!;
    await db.delete('save_backup_game_jobs');
    job.dispose();
    job = SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        resolveSaveName: () async => currentName);
    capture.localAbsent = true;
    generations.failDownload = true;
    await job.reconcileBeforeLaunch(currentName);
    expect(job.issue, 'digestMismatch');
    expect(job.lastVerified, isNull);
    expect(job.restorePending, isTrue);
    final intent = jsonDecode((await db.query('save_backup_game_jobs'))
        .single['record_json'] as String)['restore'];
    generations.failDownload = false;
    await job.reconcileBeforeLaunch(currentName);
    expect(job.issue, isNull);
    expect(job.lastVerified!.generationId, remote.generationId);
    expect(capture.restored.single.id, intent['id']);
    expect(capture.restored.single.rollback, intent['rollbackId']);
    expect(generations.uploads, 1);
  });
  test('missing local save preserves divergent cloud heads for explicit choice',
      () async {
    await job.backup(currentName);
    final base = job.lastVerified!;
    final left = _branch(base, 'left');
    final right = _branch(base, 'right');
    generations.cloud.addAll({'left': left, 'right': right});
    capture.localAbsent = true;
    await job.reconcileBeforeLaunch(currentName);
    expect(job.issue, 'save_conflict');
    expect(job.conflicts.map((m) => m.generationId).toSet(), {'left', 'right'});
    expect(capture.restored, isEmpty);
    await job.restoreConflict('left', {'left', 'right'});
    expect(job.issue, isNull);
    expect(job.lastVerified!.generationId, 'left');
    expect(job.rollbackAvailable, isFalse);
    expect(generations.uploads, 1,
        reason: 'There is no local branch to upload');
    expect(generations.cloud['right']!.encode(), right.encode());
  });
  test('missing pre-launch restore rechecks cloud heads before publication',
      () async {
    await job.backup(currentName);
    final selected = job.lastVerified!;
    capture.localAbsent = true;
    generations.onDownload = () {
      generations.cloud['advanced'] = _branch(selected, 'advanced');
    };
    await job.reconcileBeforeLaunch(currentName);
    expect(job.issue, 'conflict_changed');
    expect(job.restorePending, isTrue);
    expect(capture.restored, isEmpty);
    expect(job.lastVerified!.generationId, selected.generationId);
    expect(generations.uploads, 1);
  });
  testWidgets(
      'absent-save conflicts offer cloud choices, not an invented device copy',
      (tester) async {
    await tester.runAsync(() async {
      await job.backup(currentName);
      final base = job.lastVerified!;
      generations.cloud.addAll(
          {'left': _branch(base, 'left'), 'right': _branch(base, 'right')});
      capture.localAbsent = true;
      await job.reconcileBeforeLaunch(currentName);
    });
    await tester.pumpWidget(ProviderScope(
        child: createTestApp(Scaffold(
            body: SaveBackupGamePanel(
                job: job,
                title: 'Game',
                section: SaveBackupSection.restore)))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('save-conflict-local')), findsNothing);
    expect(
        find.byKey(const ValueKey('save-conflict-cloud-left')), findsOneWidget);
    expect(find.byKey(const ValueKey('save-conflict-cloud-right')),
        findsOneWidget);
    expect(find.text('Use this copy'), findsNWidgets(2),
        reason: 'Cloud metadata must not become a long button label');
    expect(
        find.byKey(const ValueKey('save-cloud-summary-left')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('save-cloud-summary-right')), findsOneWidget);
    expect(find.textContaining('More than one cloud save is available'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('pre-launch preserves divergent local and cloud saves for a choice',
      () async {
    await job.backup(currentName);
    final base = job.lastVerified!;
    final head = _branch(base, 'peer-head');
    generations.cloud[head.generationId] = head;
    capture.digest = 'd' * 64;
    await job.reconcileBeforeLaunch(currentName);
    expect(job.issue, 'save_conflict');
    expect(job.lastVerified!.generationId, base.generationId);
    expect(job.conflicts.single.generationId, head.generationId);
    expect(capture.restored, isEmpty);
    expect(generations.downloads, 0);
    expect(generations.uploads, 1);
    expect(generations.cloud[head.generationId]!.encode(), head.encode());
  });
  test('pre-launch failed cloud download retains last-good receipt and resumes',
      () async {
    await job.backup(currentName);
    final base = job.lastVerified!;
    final head = _branch(base, 'peer-head');
    generations.cloud[head.generationId] = head;
    generations.failDownload = true;
    await job.reconcileBeforeLaunch(currentName);
    expect(job.issue, 'digestMismatch');
    expect(job.lastVerified!.generationId, base.generationId);
    expect(job.restorePending, isTrue);
    expect(capture.restored, isEmpty);
    final intent = jsonDecode((await db.query('save_backup_game_jobs'))
        .single['record_json'] as String)['restore'];
    generations.failDownload = false;
    await job.reconcileBeforeLaunch(currentName);
    expect(job.issue, isNull);
    expect(job.phase, 'restored');
    expect(job.lastVerified!.generationId, head.generationId);
    expect(capture.restored.single.id, intent['id']);
    expect(capture.restored.single.rollback, intent['rollbackId']);
    expect(generations.uploads, 1);
  });
  test('pre-launch does not infer ancestry through a missing cloud generation',
      () async {
    await job.backup(currentName);
    final base = job.lastVerified!;
    final missing = _branch(base, 'missing-parent');
    final head = _branch(missing, 'peer-head');
    generations.cloud[head.generationId] = head;
    await job.reconcileBeforeLaunch(currentName);
    expect(job.issue, 'save_conflict');
    expect(capture.restored, isEmpty);
    expect(generations.downloads, 0);
    expect(generations.uploads, 1);
    expect(job.lastVerified!.generationId, base.generationId);
  });

  test('automatic restore rechecks cloud heads after downloading', () async {
    await job.backup(currentName);
    final base = job.lastVerified!;
    final selected = _branch(base, 'peer-selected');
    final advanced = _branch(selected, 'peer-advanced');
    generations.cloud[selected.generationId] = selected;
    generations.onDownload = () {
      generations.cloud[advanced.generationId] = advanced;
    };
    await job.reconcileBeforeLaunch(currentName);
    expect(capture.restored, isEmpty,
        reason: 'The automatically selected generation is no longer current');
    expect(job.issue, 'conflict_changed');
    expect(job.lastVerified!.generationId, base.generationId);
    expect(generations.uploads, 1);
    expect(job.restorePending, isTrue);
    final staged = capture.staged.single;
    await job.reconcileBeforeLaunch(currentName);
    expect(job.issue, 'conflict_changed');
    expect(capture.restored, isEmpty);
    expect(capture.staged, [staged],
        reason:
            'Automatic retry must retain, not replace, the reviewed intent');
    await job
        .restoreLatest(); // Explicitly confirmed resume of the chosen copy.
    expect(job.issue, isNull);
    expect(job.phase, 'restored');
    expect(job.lastVerified!.generationId, selected.generationId);
    expect(
        generations.cloud[advanced.generationId]!.encode(), advanced.encode());
  });
  test('unchanged completion rechecks the current launch target after cloud IO',
      () async {
    await job.backup(currentName);
    final first = job.lastVerified!.generationId;
    generations.onDiscover = () => currentName = 'Moved.srm';
    await job.backup('Game.srm');
    expect(job.issue, 'source_changed');
    expect(job.phase, isNot('unchanged'));
    expect(job.lastVerified!.generationId, first);
    expect(job.pendingName, 'Game.srm');
    expect(generations.uploads, 1);
  });
  test('unimplemented related group preserves last backup without publication',
      () async {
    await job.backup(currentName);
    final verified = job.lastVerified!.generationId;
    final uploads = generations.uploads;
    capture.captureIssue = 'related_group_unfinished';
    await job.backup(currentName);
    expect(job.issue, 'related_group_unfinished');
    expect(job.lastVerified!.generationId, verified);
    expect(generations.uploads, uploads);
  });
  for (final platform in [
    'gamegear',
    'mastersystem',
    'megadrive',
    'n64',
    'nes',
    'snes',
    'gb',
    'gbc'
  ]) {
    test(
        '$platform route persists distinct binding through backup restore and rollback',
        () async {
      final route = RetroArchBatteryRoute.values
          .singleWhere((route) => route.platformId == platform);
      capture.batterySize = platform == 'n64' ? 296960 : 4;
      await LibraryStore(Future.value(db)).putGame(GameIdentity(
          id: 'game',
          platformId: platform,
          title: 'Game',
          matchStatus: IdentityMatchStatus.manuallyMatched));
      SaveBackupGameJob openGameGear() => SaveBackupGameJob(
          database: Future.value(db),
          capture: capture,
          areas: areas,
          generations: generations,
          clientId: 'client',
          accountId: 'account',
          areaId: 'area',
          editionId: 'edition',
          artifactId: artifactId,
          retroArchRoute: route,
          resolveSaveName: () async => currentName);
      final gg = openGameGear();
      await gg.backup(currentName);
      expect(gg.issue, isNull);
      final first = gg.lastVerified!;
      expect(first.binding.platformId, platform);
      expect(first.binding.coreId, route.coreId);
      expect(first.binding.formatId, route.formatId);
      expect(first.binding.kind, SaveBackupKind.save);
      expect(capture.batteryRoutes, [route]);
      gg.dispose();
      final reopened = openGameGear();
      await reopened.load();
      expect(reopened.lastVerified!.generationId, first.generationId);
      await reopened.restoreLatest();
      expect(reopened.issue, isNull);
      expect(capture.restoreRoutes, [route]);
      final rollbackId = capture.restored.single.rollback;
      final directory =
          await Directory('D:/Temp').createTemp('rshop-gg-rollback-');
      final retained = File('${directory.path}/member');
      try {
        await retained.writeAsBytes(List.filled(capture.batterySize, 4),
            flush: true);
        capture.sealed[rollbackId] = CapturedSaveGroup(
            rollbackId, 'device', '1.22.2_GIT', [
          CapturedSaveFile(currentName, retained, capture.batterySize, 'b' * 64)
        ]);
        await reopened.rollbackLast();
        expect(reopened.issue, isNull);
        expect(capture.restoreRoutes, [route, route]);
        expect(capture.batteryRoutes.every((r) => r == route), isTrue);
        await job.load();
        expect(job.lastVerified, isNull,
            reason: 'mGBA cannot adopt a Sega cartridge job');
        for (final other
            in RetroArchBatteryRoute.values.where((r) => r != route)) {
          final isolated = SaveBackupGameJob(
              database: Future.value(db),
              capture: capture,
              areas: areas,
              generations: generations,
              clientId: 'client',
              accountId: 'account',
              areaId: 'area',
              editionId: 'edition',
              artifactId: artifactId,
              retroArchRoute: other,
              resolveSaveName: () async => currentName);
          await isolated.load();
          expect(isolated.lastVerified, isNull,
              reason:
                  '${other.platformId} must not load the $platform journal');
          isolated.dispose();
        }
      } finally {
        reopened.dispose();
        if (await retained.exists()) await retained.delete();
        await directory.delete();
      }
    });
  }

  testWidgets(
      'Melon backup exposes automatic saves without force-stop instructions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final automatic = _AutomaticUi(db, await SharedPreferences.getInstance());
    final ds = _UiJob(SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        melonDirectory: SaveCapture.melonStandardDirectory,
        melonName: 'Game.sav',
        resolveSaveName: () async => 'Game.sav'));
    ds.refreshFixture = true;
    addTearDown(ds.dispose);
    addTearDown(automatic.dispose);
    Future<void> show(SaveBackupSection section) async {
      await tester.pumpWidget(ProviderScope(
          child: createTestApp(SingleChildScrollView(
              child: SaveBackupGamePanel(
                  job: ds,
                  title: 'Game',
                  automatic: automatic,
                  section: section)))));
      await tester.pumpAndSettle();
    }

    await show(SaveBackupSection.backup);
    expect(find.byType(AutomaticSaveBackupPanel), findsOneWidget);
    expect(find.textContaining('Force stop'), findsNothing);
    expect(find.byKey(const ValueKey('save-melon-app-info')), findsNothing);
    final toggle = find.byKey(const ValueKey('automatic-save-enable'));
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('I confirm this save belongs to Game'), findsNothing);
    expect(find.text('Save linked automatically'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(toggle).onChanged, isNotNull);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(automatic.enabled, isTrue);
    await show(SaveBackupSection.status);
    expect(toggle, findsNothing);
    expect(find.text('Automatic save checks: enabled'), findsOneWidget);
    await show(SaveBackupSection.restore);
    expect(find.textContaining('Force stop'), findsNothing);
    expect(find.textContaining('checks that it has exited'), findsOneWidget);
    expect(find.byKey(const ValueKey('save-melon-app-info')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
      'Melon save binds DS edition and shared folder, preserves changed-source retry',
      () async {
    await LibraryStore(Future.value(db)).putGame(GameIdentity(
        id: 'game',
        platformId: 'nds',
        title: 'Game',
        matchStatus: IdentityMatchStatus.manuallyMatched));
    const directory = '/storage/emulated/0/Saves/MelonDualDS';
    SaveBackupGameJob dsJob(String path) => SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        melonDirectory: path,
        melonName: 'Game.sav',
        resolveSaveName: () async => 'Game.sav');
    final ds = dsJob(directory);
    addTearDown(ds.dispose);
    capture.captureIssue = 'source_changed';
    await ds.backup('Game.sav');
    expect(ds.issue, 'source_changed');
    expect(generations.cloud, isEmpty);
    capture.captureIssue = null;
    await ds.backup('Game.sav');
    expect(ds.issue, isNull);
    final binding = ds.lastVerified!.binding;
    expect(binding.platformId, 'nds');
    expect(binding.emulatorPackage, 'me.magnum.melondualds');
    expect(binding.emulatorVersion, '0.8.0.rc2');
    expect(binding.coreId, 'melonds');
    expect(binding.kind, SaveBackupKind.save);
    expect(binding.formatId, 'melondualds-sram-v1');
    final reopened = dsJob(directory);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.lastVerified!.generationId, ds.lastVerified!.generationId);
    final elsewhere = dsJob('/storage/75D7-DC5F/Saves/DS');
    addTearDown(elsewhere.dispose);
    await elsewhere.load();
    expect(elsewhere.lastVerified, isNull);
    capture.publicationIssue = 'stop_melon_required';
    await reopened.restoreLatest();
    expect(reopened.issue, 'stop_melon_required');
    expect(reopened.restorePending, isTrue);
    final pending = dsJob(directory);
    addTearDown(pending.dispose);
    await pending.load();
    expect(pending.restorePending, isTrue);
    capture.publicationIssue = null;
    await pending.restoreLatest();
    expect(pending.issue, isNull);
    expect(pending.phase, 'restored');
    expect(pending.rollbackAvailable, isTrue);
    expect(capture.stagedNames, ['Game.sav']);
    expect(capture.stagedDirectories, [directory]);
    expect(capture.melonSources, hasLength(2));
    expect(capture.batteryRoutes, isEmpty);
    expect(capture.ppssppSources, isEmpty);
  });

  test('PPSSPP save folder keeps complete membership and independent ancestry',
      () async {
    await LibraryStore(Future.value(db)).putGame(GameIdentity(
        id: 'game',
        platformId: 'psp',
        title: 'Game',
        matchStatus: IdentityMatchStatus.manuallyMatched));
    final folderCapture = _SavedataCapture();
    const directory = '/storage/emulated/0/PSP/SAVEDATA/ULUS10041DATA00';
    SaveBackupGameJob folderJob() => SaveBackupGameJob(
        database: Future.value(db),
        capture: folderCapture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        resolveSaveName: () async => 'ULUS10041DATA00',
        ppssppSavedataDirectory: directory);
    final psp = folderJob();
    addTearDown(psp.dispose);
    await psp.backup('ULUS10041DATA00');
    expect(psp.issue, isNull);
    final first = psp.lastVerified!;
    expect(first.binding.kind, SaveBackupKind.save);
    expect(first.binding.formatId, 'ppsspp-savedata-v1');
    expect(first.members.map((member) => member.relativePath).toSet(),
        {for (final leaf in folderCapture.leaves) 'ULUS10041DATA00/$leaf'});
    expect(
        first.members
            .singleWhere((m) => m.relativePath.endsWith('/EMPTY'))
            .sizeBytes,
        0);
    final foreignBinding = first.binding.toJson()
      ..['editions'] = [
        {'gameId': 'different-game', 'editionId': 'different-edition'}
      ];
    generations.cloud['foreign'] = SaveBackupManifest(
        generationId: 'foreign',
        binding: SaveBackupBinding.fromJson(foreignBinding),
        parentGenerationIds: const [],
        createdAt: DateTime.utc(2026),
        members: first.members);
    generations.cloud['mixed-folders'] = SaveBackupManifest(
        generationId: 'mixed-folders',
        binding: first.binding,
        parentGenerationIds: const [],
        createdAt: DateTime.utc(2026),
        members: [
          first.members.first,
          SaveBackupMember(
              relativePath: 'OTHER/DATA',
              cloudFileId: 'other-member',
              sizeBytes: 4,
              sha256: 'c' * 64)
        ]);
    final capturesBeforeDiscovery = folderCapture.captures;
    expect(
        await SaveBackupGameJob.discoverPpssppSavedataFolders(
            database: Future.value(db),
            generations: generations,
            areaId: 'area',
            editionId: 'edition',
            artifactId: artifactId),
        ['ULUS10041DATA00']);
    expect(folderCapture.captures, capturesBeforeDiscovery,
        reason: 'Cloud discovery cannot depend on a local save existing');
    generations.cloud.remove('foreign');
    generations.cloud.remove('mixed-folders');
    generations.cloud['another-folder'] = SaveBackupManifest(
        generationId: 'another-folder',
        binding: first.binding,
        parentGenerationIds: const [],
        createdAt: DateTime.utc(2026),
        members: [
          SaveBackupMember(
              relativePath: 'ULUS10041DATA01/PARAM.SFO',
              cloudFileId: 'another-folder-member',
              sizeBytes: 4,
              sha256: 'c' * 64)
        ]);
    folderCapture.digest = 'd' * 64;
    await psp.backup('ULUS10041DATA00');
    expect(psp.issue, isNull,
        reason: 'A sibling PSP save folder has independent ancestry');
    expect(psp.lastVerified!.parentGenerationIds, [first.generationId]);
    final reloaded = folderJob();
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.lastVerified!.generationId, psp.lastVerified!.generationId);
    // Membership is part of the generation, not a reason to refuse the whole-
    // folder replacement. Native publication compares the actual local baseline.
    folderCapture.leaves = ['LOCAL.DAT'];
    await reloaded.restoreLatest();
    expect(reloaded.issue, isNull);
    expect(reloaded.phase, 'restored');
    expect(folderCapture.stagedGroups.single.toSet(),
        {'PARAM.SFO', 'CUSTOM.SAV', 'ICON0.PNG', 'EMPTY'});
    expect(folderCapture.stagedDirectories, [directory]);
    expect(folderCapture.stagedNames, isEmpty,
        reason: 'A PSP folder must never use the scalar state restore route');
    expect(folderCapture.restored, hasLength(1));
    expect(reloaded.rollbackAvailable, isTrue);
    final downloads = generations.downloads;
    await reloaded.rollbackLast();
    expect(reloaded.issue, isNull);
    expect(reloaded.phase, 'rolled_back');
    expect(folderCapture.stagedGroups.last, ['LOCAL.DAT'],
        reason:
            'Rollback restores the retained local membership, not the cloud list');
    expect(generations.downloads, downloads);
  });

  test('PPSSPP one-member save folder still uses whole-folder publication',
      () async {
    await LibraryStore(Future.value(db)).putGame(GameIdentity(
        id: 'game',
        platformId: 'psp',
        title: 'Game',
        matchStatus: IdentityMatchStatus.manuallyMatched));
    final folderCapture = _SavedataCapture()..leaves = ['PARAM.SFO'];
    final psp = SaveBackupGameJob(
        database: Future.value(db),
        capture: folderCapture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        resolveSaveName: () async => 'ULUS10041DATA00',
        ppssppSavedataDirectory:
            '/storage/emulated/0/PSP/SAVEDATA/ULUS10041DATA00');
    addTearDown(psp.dispose);
    await psp.backup('ULUS10041DATA00');
    expect(psp.issue, isNull);
    await psp.restoreLatest();
    expect(psp.issue, isNull);
    expect(psp.phase, 'restored');
    expect(folderCapture.stagedGroups, [
      ['PARAM.SFO']
    ]);
    expect(folderCapture.stagedNames, isEmpty);
    expect(folderCapture.restored, hasLength(1));
  });

  test('PPSSPP slot uses reviewed state identity and survives reload',
      () async {
    await LibraryStore(Future.value(db)).putGame(GameIdentity(
        id: 'game',
        platformId: 'psp',
        title: 'Game',
        matchStatus: IdentityMatchStatus.manuallyMatched));
    SaveBackupGameJob pspJob(String directory) => SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        resolveSaveName: () async => 'ULUS10041_1.00_0.ppst',
        ppssppDirectory: directory,
        ppssppSlot: 'ULUS10041_1.00_0.ppst');
    final psp = pspJob('/storage/emulated/0/PSP/PPSSPP_STATE');
    await psp.backup('ULUS10041_1.00_0.ppst');
    expect(psp.issue, isNull);
    expect(capture.ppssppSources,
        ['/storage/emulated/0/PSP/PPSSPP_STATE/ULUS10041_1.00_0.ppst']);
    final binding = psp.lastVerified!.binding;
    expect(binding.platformId, 'psp');
    expect(binding.emulatorPackage, 'org.ppsspp.ppsspp');
    expect(binding.emulatorVersion, 'v1.20.4');
    expect(binding.kind, SaveBackupKind.state);
    expect(binding.formatId, 'ppsspp-slot-v1');
    final first = psp.lastVerified!;
    generations.cloud['another-slot'] = SaveBackupManifest(
        generationId: 'another-slot',
        binding: binding,
        parentGenerationIds: const [],
        createdAt: DateTime.utc(2026),
        members: [
          SaveBackupMember(
              relativePath: 'ULUS10041_1.00_1.ppst',
              cloudFileId: 'another-slot-member',
              sizeBytes: 4,
              sha256: 'c' * 64)
        ]);
    capture.digest = 'd' * 64;
    await psp.backup('ULUS10041_1.00_0.ppst');
    expect(psp.issue, isNull,
        reason: 'A different state slot is not a conflict');
    expect(psp.lastVerified!.parentGenerationIds, [first.generationId]);
    final reloaded = pspJob('/storage/emulated/0/PSP/PPSSPP_STATE');
    await reloaded.load();
    expect(reloaded.lastVerified!.generationId, psp.lastVerified!.generationId);
    final other = pspJob('/storage/75D7-DC5F/PSP/PPSSPP_STATE');
    await other.load();
    expect(other.lastVerified, isNull);
    capture.publicationIssue = 'stop_ppsspp_required';
    await reloaded.restoreLatest();
    expect(reloaded.issue, 'stop_ppsspp_required');
    expect(reloaded.restorePending, isTrue);
    expect(capture.restored, isEmpty);
    final pending = pspJob('/storage/emulated/0/PSP/PPSSPP_STATE');
    await pending.load();
    expect(pending.restorePending, isTrue);
    pending.dispose();
    capture.publicationIssue = null;
    await reloaded.restoreLatest();
    expect(reloaded.issue, isNull);
    expect(reloaded.phase, 'restored');
    expect(capture.stagedNames, ['ULUS10041_1.00_0.ppst']);
    expect(capture.stagedDirectories, ['/storage/emulated/0/PSP/PPSSPP_STATE']);
    expect(capture.restored.single.id, capture.staged.single);
    expect(capture.ppssppSources, hasLength(3),
        reason: 'Restore captures its local rollback through PPSSPP, not mGBA');
    final recovered = pspJob('/storage/emulated/0/PSP/PPSSPP_STATE');
    await recovered.load();
    expect(recovered.rollbackAvailable, isTrue);
    expect(recovered.restorePending, isFalse);
    recovered.dispose();
    psp.dispose();
    reloaded.dispose();
    other.dispose();
  });
  test('PPSSPP cloud conflict preserves local slot before restoring its peer',
      () async {
    await LibraryStore(Future.value(db)).putGame(GameIdentity(
        id: 'game',
        platformId: 'psp',
        title: 'Game',
        matchStatus: IdentityMatchStatus.manuallyMatched));
    final psp = SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        resolveSaveName: () async => 'ULUS10041_1.00_0.ppst',
        ppssppDirectory: '/storage/emulated/0/PSP/PPSSPP_STATE',
        ppssppSlot: 'ULUS10041_1.00_0.ppst');
    addTearDown(() async {
      await psp.cancelAndJoin();
      psp.dispose();
    });
    await psp.backup('ULUS10041_1.00_0.ppst');
    final remote = _branch(psp.lastVerified!, 'other-psp-device');
    generations.cloud[remote.generationId] = remote;
    capture.digest = 'd' * 64;
    await psp.backup('ULUS10041_1.00_0.ppst');
    expect(psp.issue, 'save_conflict');
    final originalRemote = remote.encode();
    generations.onPublish = () {
      expect(capture.restored, isEmpty);
      expect(generations.downloads, 0);
    };
    await psp.restoreConflict(
        remote.generationId, psp.conflicts.map((h) => h.generationId).toSet());
    expect(psp.issue, isNull);
    expect(psp.phase, 'restored');
    expect(generations.cloud[remote.generationId]!.encode(), originalRemote);
    expect(generations.uploaded!.members.single.sha256, 'd' * 64);
    expect(generations.uploaded!.binding.formatId, 'ppsspp-slot-v1');
    expect(generations.uploaded!.members.single.relativePath,
        'ULUS10041_1.00_0.ppst');
    expect(capture.stagedDirectories, ['/storage/emulated/0/PSP/PPSSPP_STATE']);
    expect(capture.stagedNames, ['ULUS10041_1.00_0.ppst']);
    expect(capture.restored, hasLength(1));
    expect(capture.ppssppSources, hasLength(capture.captures),
        reason: 'Every capture must use PPSSPP, never the mGBA fallback');
  });
  testWidgets(
      'PPSSPP restore explains the writer boundary and requires confirmation',
      (tester) async {
    // Keep FFI transaction creation and completion in the same real async
    // zone; mutating the outer fake-clock database here deadlocks its lock.
    final fixture = (await tester.runAsync(() async {
      final localDb =
          await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await LibrarySchema.install(localDb);
      final store = LibraryStore(Future.value(localDb));
      await store.putGame(GameIdentity(
          id: 'game',
          platformId: 'psp',
          title: 'Game',
          matchStatus: IdentityMatchStatus.manuallyMatched));
      await store.putEdition(EditionIdentity(
          id: 'edition',
          gameId: 'game',
          members: [EditionMember(artifactId: artifactId)]));
      final auth = DriveAuthorization(_Driver());
      final localAreas = _Areas(auth);
      final localGenerations = _Generations(auth, localDb);
      final psp = SaveBackupGameJob(
          database: Future.value(localDb),
          capture: capture,
          areas: localAreas,
          generations: localGenerations,
          clientId: 'client',
          accountId: 'account',
          areaId: 'area',
          editionId: 'edition',
          artifactId: artifactId,
          resolveSaveName: () async => 'ULUS10041_1.00_0.ppst',
          ppssppDirectory: '/storage/emulated/0/PSP/PPSSPP_STATE',
          ppssppSlot: 'ULUS10041_1.00_0.ppst');
      await psp.backup('ULUS10041_1.00_0.ppst');
      return (
        psp: psp,
        db: localDb,
        areas: localAreas,
        generations: localGenerations
      );
    }))!;
    final psp = fixture.psp;
    final uiJob = _UiJob(psp);
    await tester.runAsync(uiJob.load);
    addTearDown(() async {
      psp.dispose();
      uiJob.dispose();
      fixture.areas.close();
      fixture.generations.close();
      await tester.runAsync(fixture.db.close);
    });
    await tester.pumpWidget(ProviderScope(
        child: createTestApp(SingleChildScrollView(
            child: SaveBackupGamePanel(
                job: uiJob,
                title: 'Game',
                section: SaveBackupSection.restore)))));
    await tester.pumpAndSettle();
    final appInfo = find.byKey(const ValueKey('save-ppsspp-app-info'));
    expect(appInfo, findsOneWidget);
    await tester.ensureVisible(appInfo);
    await tester.tap(appInfo);
    expect(capture.appInfoOpens, 1);
    final restore = find.byKey(const ValueKey('save-backup-game-restore'));
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(find.textContaining('Force stop'), findsNothing);
    expect(find.textContaining('checks that it has exited'), findsWidgets);
    expect(find.textContaining('RetroArch'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('save-restore-cancel')));
    await tester.pumpAndSettle();
    expect(uiJob.restores, 0);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-restore-confirm')));
    await tester.pumpAndSettle();
    expect(uiJob.restores, 1);
    expect(capture.restored, isEmpty,
        reason: 'The UI fixture never writes an emulator save');
  });
  test('persists exact reviewed binding and reserved objects before upload',
      () async {
    await job.backup('Game.srm');
    expect(job.issue, isNull);
    expect(job.lastVerified?.binding.editions.single.editionId, 'edition');
    expect(job.lastVerified?.binding.editions.single.gameId, 'game');
    expect(job.lastVerified?.binding.kind, SaveBackupKind.save);
    expect(job.lastVerified?.members.single.relativePath, 'Game.srm');
    expect(generations.uploads, 1);
  });
  for (final platform in ['snes', 'gb', 'gbc']) {
    test(
        '$platform clock group retains its route across publication failure and rollback',
        () async {
      final route = RetroArchBatteryRoute.forPlatform(platform)!;
      await LibraryStore(Future.value(db)).putGame(GameIdentity(
          id: 'game',
          platformId: platform,
          title: 'Game',
          matchStatus: IdentityMatchStatus.manuallyMatched));
      final snes = SaveBackupGameJob(
          database: Future.value(db),
          capture: capture,
          areas: areas,
          generations: generations,
          clientId: 'client',
          accountId: 'account',
          areaId: 'area',
          editionId: 'edition',
          artifactId: artifactId,
          retroArchRoute: route,
          resolveSaveName: () async => currentName);
      addTearDown(snes.dispose);
      capture.includeRtc = true;
      await snes.backup(currentName);
      expect(snes.issue, isNull);
      expect(snes.lastVerified!.binding.formatId, route.formatId);
      expect(snes.lastVerified!.members, hasLength(2));
      capture.publicationIssue = 'close_content_required';
      await snes.restoreLatest();
      expect(snes.restorePending, isTrue);
      expect(capture.restoreRoutes.single, route);
      final staged = capture.staged.single;
      await snes.load();
      capture.publicationIssue = null;
      await snes.restoreLatest();
      expect(snes.issue, isNull);
      expect(capture.staged.single, staged);
      final rollback = capture.restored.single.rollback;
      capture.sealed[rollback] =
          CapturedSaveGroup(rollback, 'device', '1.22.2_GIT', [
        CapturedSaveFile('Game.srm',
            _MemorySaveFile('/private/sram', [1, 2, 3, 4]), 4, 'b' * 64),
        CapturedSaveFile('Game.rtc',
            _MemorySaveFile('/private/rtc', [5, 6, 7, 8]), 4, 'd' * 64),
      ]);
      final downloads = generations.downloads;
      await snes.rollbackLast();
      expect(snes.issue, isNull);
      expect(snes.phase, 'rolled_back');
      expect(capture.restoreRoutes, [route, route]);
      expect(generations.downloads, downloads);
      expect(
          capture.stagedGroups.last, unorderedEquals(['Game.rtc', 'Game.srm']));
    });
  }

  test(
      'related SRAM and RTC restore is not rejected as a single-file selection',
      () async {
    capture.includeRtc = true;
    await job.backup(currentName);
    expect(job.lastVerified!.members.map((m) => m.relativePath),
        unorderedEquals(['Game.srm', 'Game.rtc']));
    await job.restoreLatest();
    expect(job.issue, isNull);
    expect(job.phase, 'restored');
    expect(capture.restored, hasLength(1));
    expect(
        capture.stagedGroups.single, unorderedEquals(['Game.srm', 'Game.rtc']));
  });
  test(
      'related restore keeps its IDs and rollback after failed publication and reload',
      () async {
    capture.includeRtc = true;
    await job.backup(currentName);
    capture.publicationIssue = 'close_content_required';
    await job.restoreLatest();
    expect(job.issue, 'close_content_required');
    expect(job.restorePending, isTrue);
    final staged = capture.staged.single;
    await job.load();
    capture.publicationIssue = null;
    await job.restoreLatest();
    expect(job.issue, isNull);
    expect(capture.staged, [staged],
        reason: 'A sealed group is not re-downloaded');
    expect(capture.restored.single.id, staged);
  });
  test(
      'related restore rejects changed local membership before download or publication',
      () async {
    capture.includeRtc = true;
    await job.backup(currentName);
    capture.includeRtc = false;
    await job.restoreLatest();
    expect(job.issue, 'related_group_changed');
    expect(generations.downloads, 0);
    expect(capture.staged, isEmpty);
    expect(capture.restored, isEmpty);
  });
  test(
      'failed related-member transport preserves pending intent without publication',
      () async {
    capture.includeRtc = true;
    await job.backup(currentName);
    generations.failDownload = true;
    await job.restoreLatest();
    expect(job.issue, isNotNull);
    expect(job.restorePending, isTrue);
    expect(capture.restored, isEmpty);
    generations.failDownload = false;
    await job.restoreLatest();
    expect(job.issue, isNull);
    expect(capture.restored, hasLength(1));
  });
  test('another installation cloud change requires a choice before upload',
      () async {
    await job.backup('Game.srm');
    final base = job.lastVerified!;
    final remote = _branch(base, 'other-device');
    generations.cloud[remote.generationId] = remote;
    await job.backup('Game.srm');
    expect(job.issue, 'save_conflict');
    expect(generations.uploads, 1);
    expect(job.lastVerified!.generationId, base.generationId);
    expect(job.pendingName, 'Game.srm');
    expect(generations.cloud[remote.generationId]!.contentDigest,
        remote.contentDigest);
  });
  test('related restore uses current installation names for both file roles',
      () async {
    capture.includeRtc = true;
    await job.backup(currentName);
    currentName = 'Reinstalled.srm';
    await job.restoreLatest();
    expect(job.issue, isNull);
    expect(capture.stagedGroups.single,
        unorderedEquals(['Reinstalled.srm', 'Reinstalled.rtc']));
  });
  test(
      'related rollback reads both retained local members without a cloud download',
      () async {
    capture.includeRtc = true;
    await job.backup(currentName);
    await job.restoreLatest();
    final rollbackId = capture.restored.single.rollback;
    final downloads = generations.downloads;
    final directory =
        await Directory('D:/Temp').createTemp('rshop-group-rollback-');
    final sram = File('${directory.path}/sram');
    final rtc = File('${directory.path}/rtc');
    try {
      await sram.writeAsBytes([1, 2, 3, 4], flush: true);
      await rtc.writeAsBytes([5, 6, 7, 8], flush: true);
      capture.sealed[rollbackId] =
          CapturedSaveGroup(rollbackId, 'device', '1.22.2_GIT', [
        CapturedSaveFile(currentName, sram, 4, 'b' * 64),
        CapturedSaveFile('Game.rtc', rtc, 4, 'd' * 64),
      ]);
      await job.rollbackLast();
      expect(job.issue, isNull);
      expect(job.phase, 'rolled_back');
      expect(generations.downloads, downloads);
      expect(capture.restored, hasLength(2));
      expect(
          capture.stagedGroups.last, unorderedEquals(['Game.srm', 'Game.rtc']));
    } finally {
      if (await sram.exists()) await sram.delete();
      if (await rtc.exists()) await rtc.delete();
      await directory.delete();
    }
  });
  test(
      'related cloud choice preserves the local branch before restoring both files',
      () async {
    capture.includeRtc = true;
    await job.backup('Game.srm');
    final base = job.lastVerified!;
    final remote = SaveBackupManifest(
        generationId: 'other-device',
        binding: base.binding,
        parentGenerationIds: [base.generationId],
        createdAt: DateTime.utc(2000),
        members: base.members
            .map((m) => SaveBackupMember(
                relativePath: m.relativePath,
                cloudFileId: m.relativePath.endsWith('.srm')
                    ? 'other-sram'
                    : 'other-rtc',
                sizeBytes: 4,
                sha256: 'c' * 64))
            .toList());
    generations.cloud[remote.generationId] = remote;
    await job.backup('Game.srm');
    expect(job.issue, 'save_conflict');
    final original = remote.encode();
    await job.restoreConflict(
        remote.generationId, job.conflicts.map((m) => m.generationId).toSet());
    expect(job.issue, isNull);
    expect(job.phase, 'restored');
    expect(generations.cloud[remote.generationId]!.encode(), original);
    expect(generations.uploads, 2,
        reason: 'The local branch must be independently recoverable');
    expect(
        capture.stagedGroups.single, unorderedEquals(['Game.srm', 'Game.rtc']));
  });
  test('installation filenames do not turn identical SRAM into a conflict',
      () async {
    await job.backup('Game.srm');
    final base = job.lastVerified!;
    final remote = SaveBackupManifest(
        generationId: 'another-installation',
        binding: base.binding,
        parentGenerationIds: [base.generationId],
        createdAt: DateTime.utc(2000),
        members: [
          SaveBackupMember(
              relativePath: 'Previous-installation.srm',
              cloudFileId: 'another-member',
              sizeBytes: 4,
              sha256: 'b' * 64)
        ]);
    generations.cloud[remote.generationId] = remote;
    currentName = 'Reinstalled.srm';
    await job.backup(currentName);
    expect(job.issue, isNull);
    expect(generations.uploads, 2);
  });
  test('RTC differences still conflict when SRAM bytes are identical',
      () async {
    await job.backup('Game.srm');
    final base = job.lastVerified!;
    final remote = SaveBackupManifest(
        generationId: 'with-rtc',
        binding: base.binding,
        parentGenerationIds: [base.generationId],
        createdAt: DateTime.utc(2000),
        members: [
          base.members.single,
          SaveBackupMember(
              relativePath: 'Game.rtc',
              cloudFileId: 'rtc-member',
              sizeBytes: 4,
              sha256: 'd' * 64)
        ]);
    generations.cloud[remote.generationId] = remote;
    await job.backup('Game.srm');
    expect(job.issue, 'save_conflict');
    expect(generations.uploads, 1);
  });
  test('explicit local choice creates a child without replacing remote objects',
      () async {
    await job.backup('Game.srm');
    final base = job.lastVerified!;
    final remote = _branch(base, 'other-device');
    generations.cloud[remote.generationId] = remote;
    await job.backup('Game.srm');
    final before =
        generations.cloud.map((key, value) => MapEntry(key, value.encode()));
    await job
        .keepLocalConflict(job.conflicts.map((h) => h.generationId).toSet());
    expect(job.issue, isNull);
    expect(
        job.lastVerified!.parentGenerationIds, contains(remote.generationId));
    expect(job.lastVerified!.contentDigest, base.contentDigest);
    expect(job.conflicts, isEmpty);
    expect(await db.query('save_backup_conflict_captures'), hasLength(1));
    for (final entry in before.entries) {
      expect(generations.cloud[entry.key]!.encode(), entry.value);
    }
  });
  test(
      'cloud changed while choosing requires a fresh choice and writes nothing',
      () async {
    await job.backup('Game.srm');
    final remote = _branch(job.lastVerified!, 'other-device');
    generations.cloud[remote.generationId] = remote;
    await job.backup('Game.srm');
    final reviewed = job.conflicts.map((h) => h.generationId).toSet();
    final changed = _branch(remote, 'changed-again');
    generations.cloud[changed.generationId] = changed;
    await job.keepLocalConflict(reviewed);
    expect(job.issue, 'conflict_changed');
    expect(generations.uploads, 1);
    expect(job.conflicts.single.generationId, changed.generationId);
    expect(capture.restored, isEmpty);
  });
  test(
      'explicit cloud choice retains captured local and restores selected version',
      () async {
    await job.backup('Game.srm');
    final remote = _branch(job.lastVerified!, 'other-device');
    generations.cloud[remote.generationId] = remote;
    capture.digest = 'd' * 64;
    await job.backup('Game.srm');
    final originalRemote = remote.encode();
    generations.onPublish = () {
      // No local replacement may precede verified preservation publication.
      expect(capture.restored, isEmpty);
      expect(generations.downloads, 0);
    };
    await job.restoreConflict(
        remote.generationId, job.conflicts.map((h) => h.generationId).toSet());
    expect(job.issue, isNull);
    expect(job.phase, 'restored');
    expect(job.lastVerified!.generationId, remote.generationId);
    expect(generations.uploads, 2);
    expect(capture.restored, hasLength(1));
    expect(await db.query('save_backup_conflict_captures'), hasLength(1));
    final recovered = await generations.discoverGenerations(
        areaId: 'area', target: remote.binding);
    expect(recovered.where((g) => g.members.single.sha256 == 'd' * 64),
        hasLength(1));
    expect(generations.cloud[remote.generationId]!.encode(), originalRemote);
    final retainedId = generations.uploaded!.generationId;
    // The next backup must acknowledge the explicit resolution, not present
    // the retained losing branch as a new, unexplained conflict.
    capture.digest = remote.members.single.sha256;
    generations.onPublish = null;
    await job.backup('Game.srm');
    expect(job.issue, isNull);
    expect(job.lastVerified!.parentGenerationIds,
        containsAll([remote.generationId, retainedId]));
    expect(generations.cloud[retainedId]!.members.single.sha256, 'd' * 64);
    final newer = SaveBackupManifest(
        generationId: 'unreviewed-branch',
        binding: remote.binding,
        parentGenerationIds: [remote.generationId],
        createdAt: DateTime.utc(1999),
        members: [
          SaveBackupMember(
              relativePath: 'Game.srm',
              cloudFileId: 'unreviewed-member',
              sizeBytes: 4,
              sha256: 'e' * 64)
        ]);
    generations.cloud[newer.generationId] = newer;
    await job.backup('Game.srm');
    expect(job.issue, 'save_conflict');
    expect(generations.uploads, 3);
  });
  test('cloud choice cannot replace local when preservation publication fails',
      () async {
    await job.backup('Game.srm');
    final base = job.lastVerified!;
    final remote = _branch(base, 'other-device');
    generations.cloud[remote.generationId] = remote;
    capture.digest = 'd' * 64;
    await job.backup('Game.srm');
    final reviewed = job.conflicts.map((h) => h.generationId).toSet();
    generations.fail = true;
    await job.restoreConflict(remote.generationId, reviewed);
    expect(job.issue, 'unavailable');
    expect(job.lastVerified!.generationId, base.generationId);
    expect(job.pendingName, 'Game.srm');
    expect(job.restorePending, isFalse);
    expect(generations.downloads, 0);
    expect(capture.restored, isEmpty);
    final retainedId = generations.uploaded!.generationId;
    generations.fail = false;
    await job.restoreConflict(remote.generationId, reviewed);
    expect(job.issue, isNull);
    expect(generations.uploaded!.generationId, retainedId);
    expect(capture.restored, hasLength(1));
  });
  test('failed chosen-cloud download retains the last verified local receipt',
      () async {
    await job.backup('Game.srm');
    final base = job.lastVerified!;
    final remote = _branch(base, 'other-device');
    generations.cloud[remote.generationId] = remote;
    capture.digest = 'd' * 64;
    await job.backup('Game.srm');
    final reviewed = job.conflicts.map((h) => h.generationId).toSet();
    generations.failDownload = true;
    await job.restoreConflict(remote.generationId, reviewed);
    expect(job.issue, 'digestMismatch');
    expect(job.lastVerified!.generationId, base.generationId,
        reason: 'A cloud choice is not completed local publication');
    expect(job.restorePending, isTrue);
    expect(capture.restored, isEmpty);
    final selected = jsonDecode((await db.query('save_backup_game_jobs'))
        .single['record_json'] as String)['restore'];
    await job.load();
    generations.failDownload = false;
    await job.restoreLatest();
    expect(job.issue, isNull);
    expect(job.lastVerified!.generationId, remote.generationId);
    expect(capture.restored.single.id, selected['id']);
    expect(capture.restored.single.rollback, selected['rollbackId']);
    expect(generations.uploads, 2,
        reason: 'Resume must not duplicate preservation of the local branch');
  });
  test('pending captures from before resolution ancestry still resume',
      () async {
    await job.backup('Game.srm');
    final base = job.lastVerified!;
    final row = (await db.query('save_backup_game_jobs')).single;
    final record = jsonDecode(row['record_json'] as String) as Map;
    record['state'] = 'pending';
    record['captureId'] = 'a' * 32;
    record['generation'] = null;
    record['captures'] = null;
    record.remove('parentGenerationIds');
    await db.update(
        'save_backup_game_jobs', {'record_json': jsonEncode(record)},
        where: 'job_key = ?', whereArgs: [row['job_key']]);
    capture.digest = 'd' * 64;
    await job.backup('Game.srm');
    expect(job.issue, isNull);
    expect(job.lastVerified!.parentGenerationIds, [base.generationId]);
  });
  test('cloud change during preservation requires another explicit choice',
      () async {
    await job.backup('Game.srm');
    final base = job.lastVerified!;
    final remote = _branch(base, 'other-device');
    generations.cloud[remote.generationId] = remote;
    capture.digest = 'd' * 64;
    await job.backup('Game.srm');
    final changed = _branch(remote, 'changed-again');
    generations.onPublish = () {
      generations.cloud[changed.generationId] = changed;
    };
    await job.restoreConflict(
        remote.generationId, job.conflicts.map((h) => h.generationId).toSet());
    expect(job.issue, 'conflict_changed');
    expect(job.lastVerified!.generationId, base.generationId);
    expect(
        job.conflicts.map((h) => h.generationId),
        containsAll(
            [changed.generationId, generations.uploaded!.generationId]));
    expect(
        generations.cloud.values
            .where((g) => g.members.single.sha256 == 'd' * 64),
        hasLength(1));
    expect(generations.downloads, 0);
    expect(capture.restored, isEmpty);
  });
  test('publication racing another device retains and reports both branches',
      () async {
    await job.backup('Game.srm');
    final base = job.lastVerified!;
    final remote = _branch(base, 'other-device');
    generations.onPublish = () {
      generations.cloud[remote.generationId] = remote;
    };
    capture.digest = 'd' * 64;
    await job.backup('Game.srm');
    expect(job.issue, 'save_conflict');
    expect(job.lastVerified!.generationId, base.generationId);
    expect(job.conflicts.map((h) => h.generationId),
        containsAll([remote.generationId, generations.uploaded!.generationId]));
    await job.load();
    expect(job.conflicts, hasLength(2));
    expect(generations.cloud, hasLength(3));
  });
  test('rejected atomic cloud choice retains both branches for a fresh choice',
      () async {
    await job.backup('Game.srm');
    final base = job.lastVerified!;
    final remote = _branch(base, 'other-device');
    generations.cloud[remote.generationId] = remote;
    await job.backup('Game.srm');
    await db.execute(
        '''CREATE TRIGGER reject_restore BEFORE INSERT ON save_backup_game_jobs
      WHEN json_extract(NEW.record_json, '\$.restore.state') = 'capture'
      BEGIN SELECT RAISE(ABORT, 'fixture storage failure'); END''');
    await job.restoreConflict(
        remote.generationId, job.conflicts.map((h) => h.generationId).toSet());
    expect(job.issue, 'backup_unavailable');
    await job.load();
    // The choice and restore intent now commit together. A rejected write is
    // not a durable accepted choice and must not fabricate pending restore or
    // replace last-good evidence with the uninstalled cloud generation.
    expect(job.restorePending, isFalse);
    expect(job.lastVerified!.generationId, base.generationId);
    expect(job.pendingName, 'Game.srm');
    expect(job.conflicts, isNotEmpty);
    expect(capture.restored, isEmpty);
    expect(generations.downloads, 0);
    expect(generations.uploads, 2);
    expect(generations.cloud[remote.generationId]!.encode(), remote.encode());
    expect(generations.cloud[generations.uploaded!.generationId], isNotNull);
    await db.execute('DROP TRIGGER reject_restore');
    // Refresh the head set: the preserved local branch is now independently
    // recoverable even though the local choice transaction did not commit.
    await job.backup('Game.srm');
    expect(job.issue, 'save_conflict');
    await job.restoreConflict(
        remote.generationId, job.conflicts.map((h) => h.generationId).toSet());
    expect(job.issue, isNull);
    expect(job.phase, 'restored');
  });
  testWidgets(
      'conflict choices require confirmation and cancel changes nothing',
      (tester) async {
    await tester.runAsync(() async {
      await job.backup('Game.srm');
      final remote = _branch(job.lastVerified!, 'other-device');
      generations.cloud[remote.generationId] = remote;
      await job.backup('Game.srm');
    });
    final uiJob = _UiJob(job);
    await tester.runAsync(uiJob.load);
    await tester.pumpWidget(ProviderScope(
        child: createTestApp(SingleChildScrollView(
            child: SaveBackupGamePanel(
                job: uiJob,
                title: 'Game',
                section: SaveBackupSection.restore)))));
    await tester.pumpAndSettle();
    final local = find.byKey(const ValueKey('save-conflict-local'));
    expect(local, findsOneWidget);
    expect(find.byKey(const ValueKey('save-backup-game-run')), findsNothing);
    await tester.ensureVisible(local);
    await tester.tap(local);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-conflict-cancel')));
    await tester.pumpAndSettle();
    expect(uiJob.localChoices, 0);
    await tester.tap(local);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-conflict-confirm')));
    await tester.pumpAndSettle();
    expect(uiJob.localChoices, 1);
    final cloud =
        find.byKey(const ValueKey('save-conflict-cloud-other-device'));
    await tester.ensureVisible(cloud);
    await tester.tap(cloud);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-conflict-confirm')));
    await tester.pumpAndSettle();
    expect(uiJob.cloudChoices, ['other-device']);
    await tester.pumpWidget(const SizedBox.shrink());
    uiJob.dispose();
  });
  test('an unrelated save cannot be uploaded under the selected edition',
      () async {
    await job.backup('Other.srm');
    expect(job.issue, 'source_changed');
    expect(capture.captures, 0);
    expect(areas.reserved, 0);
    expect(generations.uploads, 0);
  });
  test(
      'lost upload response resumes reserved capture and generation after restart',
      () async {
    generations.fail = true;
    await job.backup('Game.srm');
    final original = generations.uploaded!;
    expect(job.issue, isNotNull);
    generations.fail = false;
    final restarted = SaveBackupGameJob(
        database: Future.value(db),
        capture: capture,
        areas: areas,
        generations: generations,
        clientId: 'client',
        accountId: 'account',
        areaId: 'area',
        editionId: 'edition',
        artifactId: artifactId,
        resolveSaveName: () async => currentName);
    await restarted.load();
    await restarted.backup('Game.srm');
    expect(restarted.lastVerified?.generationId, original.generationId);
    expect(capture.captures, 1);
    expect(areas.reserved, 2);
    expect(generations.uploads, 2);
  });
  test(
      'duplicate activation joins the same capture; selection cannot change mid-job',
      () async {
    capture.held = Completer<void>();
    final first = job.backup('Game.srm');
    final joined = job.backup('Other.srm');
    expect(identical(first, joined), isTrue);
    capture.held!.complete();
    await first;
    expect(capture.captures, 1);
    expect(job.lastVerified?.members.single.relativePath, 'Game.srm');
  });
  test('cancellation joins the native wait without allocating cloud objects',
      () async {
    capture.held = Completer<void>();
    final pending = job.backup('Game.srm');
    await capture.started.future;
    await job.cancelAndJoin();
    await pending;
    expect(job.busy, isFalse);
    expect(job.issue, 'cancelled');
    expect(areas.reserved, 0);
    expect(generations.uploads, 0);
    expect(job.pendingName, 'Game.srm');
  });
  test('rejected durable intent prevents native capture and every upload',
      () async {
    await job.load();
    await db.execute('''CREATE TRIGGER reject_save_intent BEFORE INSERT ON
      save_backup_game_jobs BEGIN SELECT RAISE(ABORT, 'Rejected intent'); END''');
    await job.backup('Game.srm');
    expect(job.issue, 'backup_unavailable');
    expect(capture.captures, 0);
    expect(areas.reserved, 0);
    expect(generations.uploads, 0);
  });
  test('failed newer publication retains the previous verified ancestry',
      () async {
    await job.backup('Game.srm');
    final good = job.lastVerified!;
    generations.fail = true;
    capture.digest = 'd' * 64;
    await job.backup('Game.srm');
    expect(job.lastVerified?.generationId, good.generationId);
    expect(generations.uploaded?.parentGenerationIds, [good.generationId]);
    expect(job.pendingName, 'Game.srm');
  });
  test(
      'restore persists rollback intent and downloads real cloud path before publication',
      () async {
    await job.backup('Game.srm');
    final cloud = job.lastVerified!;
    await job.restoreLatest();
    expect(job.issue, isNull);
    expect(generations.downloads, 1);
    expect(capture.captures, 2);
    expect(capture.restored.single.id, capture.staged.single);
    expect(capture.restored.single.rollback, isNot(capture.staged.single));
    expect(job.lastVerified!.generationId, cloud.generationId);
    expect(job.phase, 'restored');
  });
  test('cloud save restores into the current reinstalled launch target',
      () async {
    await job.backup('Game.srm');
    currentName = 'new-install%2FGame.srm';
    await job.restoreLatest();
    expect(job.issue, isNull);
    expect(capture.stagedNames, [currentName]);
    expect(job.lastVerified!.members.single.relativePath, 'Game.srm');
    expect(capture.restored, hasLength(1));
    // Reopening a durable intent must not equate its destination filename
    // with the immutable cloud member's original filename.
    await job.load();
    expect(job.phase, 'restored');
  });
  test('a pending restore cannot silently retarget after reinstallation',
      () async {
    await job.backup('Game.srm');
    generations.failDownload = true;
    await job.restoreLatest();
    currentName = 'new-install%2FGame.srm';
    generations.failDownload = false;
    await job.restoreLatest();
    expect(job.issue, 'source_changed');
    expect(capture.restored, isEmpty);
    expect(capture.captures, 2);
    expect(generations.downloads, 1);
  });
  test('reinstallation during capture prevents upload under the old target',
      () async {
    capture.held = Completer<void>();
    final pending = job.backup('Game.srm');
    await capture.started.future;
    currentName = 'new-install%2FGame.srm';
    capture.held!.complete();
    await pending;
    expect(job.issue, 'source_changed');
    expect(generations.uploads, 0);
  });
  test('an artifact removed from the edition is rejected before save IO',
      () async {
    await LibraryStore(Future.value(db)).putEdition(
        EditionIdentity(id: 'edition', gameId: 'game', members: const []));
    await job.backup('Game.srm');
    expect(job.issue, 'source_changed');
    expect(capture.captures, 0);
    expect(generations.uploads, 0);
  });
  test('edition reassignment during capture cannot publish for the former game',
      () async {
    capture.held = Completer<void>();
    final pending = job.backup('Game.srm');
    await capture.started.future;
    await LibraryStore(Future.value(db)).putGame(GameIdentity(
        id: 'other',
        platformId: 'gba',
        title: 'Other',
        matchStatus: IdentityMatchStatus.manuallyMatched));
    final changed = EditionIdentity(
        id: 'edition',
        gameId: 'other',
        members: [EditionMember(artifactId: artifactId)]);
    await db.update('library_editions',
        {'game_id': 'other', 'record_json': jsonEncode(changed.toJson())},
        where: 'edition_id = ?', whereArgs: ['edition']);
    capture.held!.complete();
    await pending;
    expect(job.issue, 'source_changed');
    expect(generations.uploads, 0);
  });
  test(
      'failed download cannot publish and resume retains restore/rollback identities',
      () async {
    await job.backup('Game.srm');
    generations.failDownload = true;
    await job.restoreLatest();
    expect(capture.restored, isEmpty);
    final failed = jsonDecode((await db.query('save_backup_game_jobs'))
        .single['record_json'] as String)['restore'];
    generations.failDownload = false;
    await job.restoreLatest();
    expect(capture.restored.single.id, failed['id']);
    expect(capture.restored.single.rollback, failed['rollbackId']);
    expect(
        capture.captures, 2); // replay does not recapture a changed local save
  });
  testWidgets(
      'cloud restore requires explicit replacement confirmation and cancel writes nothing',
      (tester) async {
    await tester.runAsync(() => job.backup('Game.srm'));
    final uiJob = _UiJob(job);
    await tester.runAsync(uiJob.load);
    await tester.pumpWidget(ProviderScope(
        child: createTestApp(SingleChildScrollView(
            child: SaveBackupGamePanel(
                job: uiJob,
                title: 'Game (Europe)',
                section: SaveBackupSection.restore)))));
    await tester.pumpAndSettle();
    final restore = find.byKey(const ValueKey('save-backup-game-restore'));
    expect(restore, findsOneWidget);
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(find.text('Replace local save with cloud backup?'), findsOneWidget);
    expect(capture.restored, isEmpty);
    await tester.tap(find.byKey(const ValueKey('save-restore-cancel')));
    await tester.pumpAndSettle();
    expect(generations.downloads, 0);
    expect(capture.captures, 1);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(uiJob.restores, 0);
    await tester.tap(find.byKey(const ValueKey('save-restore-confirm')));
    await tester.pumpAndSettle();
    expect(uiJob.restores, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    uiJob.dispose();
  });
  test('unfinished restore blocks a new backup without replacing the rollback',
      () async {
    await job.backup('Game.srm');
    generations.failDownload = true;
    await job.restoreLatest();
    await job.backup('Game.srm');
    expect(job.issue, 'pending_restore');
    expect(capture.captures, 2);
    expect(generations.uploads, 1);
  });
  testWidgets(
      'retained local rollback is an explicit separately confirmed action',
      (tester) async {
    await tester.runAsync(() async {
      await job.backup('Game.srm');
      await job.restoreLatest();
    });
    final uiJob = _UiJob(job);
    await tester.runAsync(uiJob.load);
    await tester.pumpWidget(ProviderScope(
        child: createTestApp(SingleChildScrollView(
            child: SaveBackupGamePanel(
                job: uiJob,
                title: 'Game (Europe)',
                section: SaveBackupSection.restore)))));
    await tester.pumpAndSettle();
    final rollback = find.byKey(const ValueKey('save-backup-game-rollback'));
    expect(rollback, findsOneWidget);
    await tester.ensureVisible(rollback);
    await tester.tap(rollback);
    await tester.pumpAndSettle();
    expect(find.text('Undo the last restore?'), findsOneWidget);
    expect(uiJob.rollbacks, 0);
    await tester.tap(find.byKey(const ValueKey('save-restore-confirm')));
    await tester.pumpAndSettle();
    expect(uiJob.rollbacks, 1);
    expect(uiJob.restores, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    uiJob.dispose();
  });
  test(
      'explicit rollback restores retained local bytes and preserves the replaced save',
      () async {
    await job.backup('Game.srm');
    await job.restoreLatest();
    final originalRollback = capture.restored.single.rollback;
    // The fake capture supplies a private fixture for the retained generation.
    final directory = await Directory('D:/Temp').createTemp('rshop-rollback-');
    final file = File('${directory.path}/member');
    await file.writeAsBytes([1, 2, 3, 4], flush: true);
    capture.sealed[originalRollback] = CapturedSaveGroup(
        originalRollback,
        'device',
        '1.22.2_GIT',
        [CapturedSaveFile('Game.srm', file, 4, 'b' * 64)]);
    try {
      await job.rollbackLast();
      expect(job.issue, isNull);
      expect(job.phase, 'rolled_back');
      expect(capture.captures, 3);
      expect(capture.restored, hasLength(2));
      expect(capture.restored.last.rollback, isNot(originalRollback));
      expect(generations.downloads, 1); // rollback needs no cloud mutation/read
    } finally {
      await file.delete();
      await directory.delete();
    }
  });
  test('restore rejects a retargeted edition before local capture or download',
      () async {
    await job.backup('Game.srm');
    final store = LibraryStore(Future.value(db));
    await store.putGame(GameIdentity(
        id: 'other',
        platformId: 'gba',
        title: 'Other',
        matchStatus: IdentityMatchStatus.manuallyMatched));
    // Simulate an explicit catalogue reconciliation, not the ordinary store
    // API which correctly refuses implicit reassignment itself.
    final changed = EditionIdentity(
        id: 'edition',
        gameId: 'other',
        members: [EditionMember(artifactId: artifactId)]);
    await db.update('library_editions',
        {'game_id': 'other', 'record_json': jsonEncode(changed.toJson())},
        where: 'edition_id = ?', whereArgs: ['edition']);
    await job.restoreLatest();
    expect(job.issue, 'restore_unavailable');
    expect(capture.captures, 1);
    expect(generations.downloads, 0);
    expect(capture.restored, isEmpty);
  });
  testWidgets(
      'exact save association survives section changes without manual confirmation',
      (tester) async {
    final uiJob = _UiJob(job);
    var section = SaveBackupSection.backup;
    late StateSetter selectSection;
    await tester.pumpWidget(ProviderScope(child: createTestApp(
        SingleChildScrollView(
            child: StatefulBuilder(builder: (context, update) {
      selectSection = update;
      return SaveBackupGamePanel(
          job: uiJob, title: 'Game (Europe)', section: section);
    })))));
    await tester.pumpAndSettle();
    final run = find.byKey(const ValueKey('save-backup-game-run'));
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(tester.widget<FilledButton>(run).onPressed, isNotNull);
    final panelState = tester.state(find.byType(SaveBackupGamePanel));
    for (final next in [
      SaveBackupSection.restore,
      SaveBackupSection.status,
      SaveBackupSection.area
    ]) {
      selectSection(() => section = next);
      await tester.pumpAndSettle();
      expect(run, findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(tester.state(find.byType(SaveBackupGamePanel)), same(panelState));
    }
    selectSection(() => section = SaveBackupSection.backup);
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('Save linked automatically'), findsOneWidget);
    expect(tester.widget<FilledButton>(run).onPressed, isNotNull);
    expect(capture.captures, 0);
    expect(generations.uploads, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    uiJob.dispose();
  });
  testWidgets('pending association shows lookup rather than a failed link',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final automatic = _AutomaticUi(db, await SharedPreferences.getInstance());
    final names = Completer<List<String>>();
    final ui = _UiJob(job)
      ..refreshFixture = true
      ..namesPending = names.future;
    await tester.pumpWidget(createTestApp(Scaffold(
        body: SaveBackupGamePanel(
            job: ui,
            title: 'Game',
            section: SaveBackupSection.status,
            automatic: automatic))));
    await tester.pump();
    expect(find.text('Finding this game’s save…'), findsOneWidget);
    expect(find.textContaining('could not link'), findsNothing);
    expect(find.byKey(const ValueKey('automatic-save-enable')), findsNothing);
    names.complete(['Game.srm']);
    await tester.pumpAndSettle();
    expect(find.text('Finding this game’s save…'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    ui.dispose();
    automatic.dispose();
  });
  for (final scenario in ['missing', 'ambiguous', 'changed']) {
    testWidgets('unresolved $scenario association cannot enable backup',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final automatic = _AutomaticUi(db, await SharedPreferences.getInstance());
      final ui = _UiJob(job)..refreshFixture = true;
      if (scenario == 'changed') {
        ui.namesFailure = PlatformException(code: 'source_changed');
      } else {
        ui.namesFixture =
            scenario == 'missing' ? [] : ['Game.srm', 'Other.srm'];
      }
      await tester.pumpWidget(createTestApp(Scaffold(
          body: SingleChildScrollView(
              child: SaveBackupGamePanel(
                  job: ui, title: 'Game', automatic: automatic)))));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('save-backup-game-run')))
              .onPressed,
          isNull);
      expect(find.text('Save linked automatically'), findsNothing);
      expect(find.byKey(const ValueKey('automatic-save-enable')), findsNothing);
      expect(capture.captures, 0);
      expect(generations.uploads, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      ui.dispose();
      automatic.dispose();
    });
  }
  testWidgets('section changes do not cancel or duplicate a running capture',
      (tester) async {
    final uiJob = _UiJob(job);
    capture.held = Completer<void>();
    late Future<void> backup;
    await tester.runAsync(() async {
      backup = uiJob.backup('Game.srm');
      await capture.started.future;
    });
    Future<void> showSection(SaveBackupSection section) async {
      await tester.pumpWidget(ProviderScope(
          child: createTestApp(SingleChildScrollView(
              child: SaveBackupGamePanel(
                  job: uiJob, title: 'Game', section: section)))));
      await tester.pump();
    }

    await showSection(SaveBackupSection.backup);
    final panelState = tester.state(find.byType(SaveBackupGamePanel));
    await showSection(SaveBackupSection.status);
    expect(tester.state(find.byType(SaveBackupGamePanel)), same(panelState));
    expect(
        find.textContaining('Waiting for the game to close'), findsOneWidget);
    await showSection(SaveBackupSection.area);
    expect(uiJob.busy, isTrue);
    expect(capture.held!.isCompleted, isFalse);
    expect(capture.captures, 1);
    expect(generations.uploads, 0);
    capture.held!.complete();
    await tester.runAsync(() => backup);
    await showSection(SaveBackupSection.status);
    expect(uiJob.issue, isNull);
    expect(find.textContaining('Verified backup:'), findsOneWidget);
    expect(capture.captures, 1);
    expect(generations.uploads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    uiJob.dispose();
  });
}
