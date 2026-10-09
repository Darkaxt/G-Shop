import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  int captures = 0;
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
  final batteryRoutes = <RetroArchBatteryRoute>[];
  final restoreRoutes = <RetroArchBatteryRoute>[];
  int appInfoOpens = 0;
  @override
  Future<void> openPpssppAppInfo() async {
    appInfoOpens++;
  }

  @override
  Future<CapturedSaveGroup> capturePpsspp(
      {required String captureId,
      required String directory,
      required String name}) async {
    if (sealed[captureId] case final previous?) return previous;
    captures++;
    ppssppSources.add('$directory/$name');
    if (!started.isCompleted) started.complete();
    await held?.future;
    return sealed[captureId] = CapturedSaveGroup(
        captureId, 'device', 'v1.20.4', [
      CapturedSaveFile(name, File('/private/$captureId/member-0'), 4, digest)
    ]);
  }

  @override
  Future<List<String>> retroArchNames() async => ['Game.srm'];
  @override
  Future<CapturedSaveGroup> captureRetroArch(
      {required String captureId,
      required String name,
      RetroArchBatteryRoute route = RetroArchBatteryRoute.mgba}) async {
    batteryRoutes.add(route);
    if (captureIssue != null) throw PlatformException(code: captureIssue!);
    if (sealed[captureId] case final previous?) return previous;
    captures++;
    if (!started.isCompleted) started.complete();
    await held?.future;
    return sealed[captureId] = CapturedSaveGroup(
        captureId, 'device', '1.22.2_GIT', [
      CapturedSaveFile(name, File('/private/$captureId/member-0'), 4, digest)
    ]);
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
      RetroArchBatteryRoute retroArchRoute = RetroArchBatteryRoute.mgba,
      required Stream<Uint8List> bytes}) async {
    await bytes.drain<void>(); // final transport verification must finish
    staged.add(restoreId);
    stagedNames.add(name);
    stagedDirectories.add(ppssppDirectory);
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
            resolveSaveName: other.resolveSaveName);
  @override
  Future<List<String>> reviewedNames() async => [await resolveSaveName()];
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
  int changes = 0;
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
  void Function()? onPublish, onDiscover;
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
    final record = jsonDecode((await db.query('save_backup_game_jobs'))
        .single['record_json'] as String);
    expect(record['restore']['generationId'], generation.generationId);
    expect(record['restore']['rollbackId'], matches(RegExp(r'^[a-f0-9]{32}$')));
    yield Uint8List.fromList([1, 2, 3, 4]);
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
    expect(find.text('Automatic return checks: enabled'), findsOneWidget);
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
  Future<
      ({
        AutomaticSaveBackups service,
        AutomaticSaveMapping mapping,
        SharedPreferences preferences
      })> automaticFixture() async {
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
    final mapping = AutomaticSaveMapping.fromJob(psp, title: 'Game');
    psp.dispose();
    SharedPreferences.setMockInitialValues({
      SaveBackupSetup.storageKey('client', 'account'):
          jsonEncode({'ready': true, 'areaId': 'area'}),
      mapping.slotStorageKey:
          jsonEncode({'directory': directory, 'slot': slot}),
    });
    final preferences = await SharedPreferences.getInstance();
    final service = AutomaticSaveBackups(
        database: Future.value(db),
        preferences: preferences,
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
            ppssppDirectory: mapped.directory,
            ppssppSlot: mapped.slot,
            resolveSaveName: resolve));
    addTearDown(() async {
      service.dispose();
      await service.cancelAndJoin();
    });
    await service.setEnabled(mapping, true);
    return (service: service, mapping: mapping, preferences: preferences);
  }

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
  test(
      'Game Gear route persists distinct binding through backup restore and rollback',
      () async {
    await LibraryStore(Future.value(db)).putGame(GameIdentity(
        id: 'game',
        platformId: 'gamegear',
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
        retroArchRoute: RetroArchBatteryRoute.gameGear,
        resolveSaveName: () async => currentName);
    final gg = openGameGear();
    await gg.backup(currentName);
    expect(gg.issue, isNull);
    final first = gg.lastVerified!;
    expect(first.binding.platformId, 'gamegear');
    expect(first.binding.coreId, 'genesis_plus_gx');
    expect(first.binding.formatId, 'libretro-genesis-plus-gx-sram-v1');
    expect(first.binding.kind, SaveBackupKind.save);
    expect(capture.batteryRoutes, [RetroArchBatteryRoute.gameGear]);
    gg.dispose();
    final reopened = openGameGear();
    await reopened.load();
    expect(reopened.lastVerified!.generationId, first.generationId);
    await reopened.restoreLatest();
    expect(reopened.issue, isNull);
    expect(capture.restoreRoutes, [RetroArchBatteryRoute.gameGear]);
    final rollbackId = capture.restored.single.rollback;
    final directory =
        await Directory('D:/Temp').createTemp('rshop-gg-rollback-');
    final retained = File('${directory.path}/member');
    try {
      await retained.writeAsBytes([1, 2, 3, 4], flush: true);
      capture.sealed[rollbackId] = CapturedSaveGroup(rollbackId, 'device',
          '1.22.2_GIT', [CapturedSaveFile(currentName, retained, 4, 'b' * 64)]);
      await reopened.rollbackLast();
      expect(reopened.issue, isNull);
      expect(capture.restoreRoutes,
          [RetroArchBatteryRoute.gameGear, RetroArchBatteryRoute.gameGear]);
      expect(
          capture.batteryRoutes
              .every((r) => r == RetroArchBatteryRoute.gameGear),
          isTrue);
      await job.load();
      expect(job.lastVerified, isNull,
          reason: 'mGBA cannot adopt the Game Gear job');
    } finally {
      reopened.dispose();
      if (await retained.exists()) await retained.delete();
      await directory.delete();
    }
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
    expect(find.textContaining('Force stop'), findsWidgets);
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
  test('cloud choice survives failure to persist the first restore intent',
      () async {
    await job.backup('Game.srm');
    final remote = _branch(job.lastVerified!, 'other-device');
    generations.cloud[remote.generationId] = remote;
    await job.backup('Game.srm');
    await db.execute(
        '''CREATE TRIGGER reject_restore BEFORE INSERT ON save_backup_game_jobs
      WHEN json_extract(NEW.record_json, '\$.restore.state') = 'capture'
      BEGIN SELECT RAISE(ABORT, 'fixture storage failure'); END''');
    await job.restoreConflict(
        remote.generationId, job.conflicts.map((h) => h.generationId).toSet());
    await job.load();
    expect(job.restorePending, isTrue);
    await job.backup('Game.srm');
    expect(job.issue, 'pending_restore');
    expect(generations.uploads, 2);
    await db.execute('DROP TRIGGER reject_restore');
    await job.restoreLatest();
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
    expect(find.text('Restore the retained local save?'), findsOneWidget);
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
      'mapping requires both explicit file selection and edition confirmation',
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
    expect(tester.widget<FilledButton>(run).onPressed, isNull);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Game.srm').last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(run).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
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
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue);
    expect(find.text('Game.srm'), findsOneWidget);
    expect(tester.widget<FilledButton>(run).onPressed, isNotNull);
    expect(capture.captures, 0);
    expect(generations.uploads, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    uiJob.dispose();
  });
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
    expect(find.textContaining('Waiting for closed content'), findsOneWidget);
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
