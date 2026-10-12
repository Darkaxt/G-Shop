import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/save_backup_manifest.dart';
import '../../models/retroarch_battery_route.dart';
import '../../models/library_identity.dart';
import '../drive/drive_authorization.dart';
import '../library_store.dart';
import 'drive_save_backup_area.dart';
import 'drive_save_backup_generation.dart';
import 'save_capture.dart';
import 'save_operation_admission.dart';

/// The first native save workflow. SQLite commits the exact selection/capture
/// intent before native IO and immutable reserved objects before remote writes.
/// Interrupted publication reuses the sealed capture and the same cloud IDs.
/// This is explicit user work, not yet SAVE-01's background workflow.
class SaveBackupGameJob extends ChangeNotifier {
  static final _running = <String, Future<void>>{};
  final Future<Database> database;
  final SaveCapture capture;
  final DriveSaveBackupAreaApi areas;
  final DriveSaveBackupGenerationApi generations;
  final String clientId, accountId, areaId, editionId;
  final RemoteArtifactId artifactId;
  final Future<String> Function() resolveSaveName;
  final SaveOperationAdmission admission;
  // Explicitly reviewed mapping, never inferred from a game title. One slot is
  // one state stream; another directory/slot must have a separate durable job.
  final String? ppssppDirectory, ppssppSlot;
  final String? ppssppSavedataDirectory;
  final String? melonDirectory, melonName;
  final RetroArchBatteryRoute retroArchRoute;
  Map<String, dynamic>? _record;
  Future<void>? _operation;
  CancelToken? _cancellation;
  String? _captureId, _issue;
  bool _disposed = false;
  String phase = 'idle';

  SaveBackupGameJob(
      {required this.database,
      required this.capture,
      required this.areas,
      required this.generations,
      required this.clientId,
      required this.accountId,
      required this.areaId,
      required this.editionId,
      required this.artifactId,
      required this.resolveSaveName,
      SaveOperationAdmission? admission,
      this.ppssppDirectory,
      this.ppssppSlot,
      this.ppssppSavedataDirectory,
      this.melonDirectory,
      this.melonName,
      this.retroArchRoute = RetroArchBatteryRoute.mgba})
      : admission = admission ?? SaveOperationAdmission() {
    if ([clientId, accountId, areaId, editionId].any((s) => s.trim().isEmpty) ||
        areas.accountId != accountId ||
        generations.accountId != accountId) {
      throw ArgumentError('Invalid save job binding');
    }
    if ((isPpsspp && retroArchRoute != RetroArchBatteryRoute.mgba) ||
        (ppssppDirectory == null) != (ppssppSlot == null) ||
        (isPpssppState && isPpssppSavedata) ||
        (isPpssppSavedata &&
            !SaveCapture.validPpssppSavedataDirectory(
                ppssppSavedataDirectory!)) ||
        (isPpssppState &&
            (!SaveCapture.validPpssppDirectory(ppssppDirectory!) ||
                !SaveCapture.validPpssppName(ppssppSlot!)))) {
      throw ArgumentError('Invalid PPSSPP mapping');
    }
    if ((melonDirectory == null) != (melonName == null) ||
        (isMelon &&
            (isPpsspp ||
                retroArchRoute != RetroArchBatteryRoute.mgba ||
                !SaveCapture.validMelonDirectory(melonDirectory!) ||
                !SaveCapture.validMelonName(melonName!)))) {
      throw ArgumentError('Invalid MelonDualDS mapping');
    }
  }

  bool get isPpssppState => ppssppDirectory != null;
  bool get isPpssppSavedata => ppssppSavedataDirectory != null;
  bool get isPpsspp => isPpssppState || isPpssppSavedata;
  bool get isMelon => melonDirectory != null;
  bool get isStandalone => isPpsspp || isMelon;
  String get emulatorLabel => isMelon
      ? 'MelonDualDS'
      : isPpsspp
          ? 'PPSSPP'
          : 'RetroArch';
  Future<void> openEmulator() => isMelon
      ? capture.openMelon()
      : isPpsspp
          ? capture.openPpsspp()
          : capture.openRetroArch();
  Future<void> openAppInfo() =>
      isMelon ? capture.openMelonAppInfo() : capture.openPpssppAppInfo();
  String get _platform => isMelon
      ? 'nds'
      : isPpsspp
          ? 'psp'
          : retroArchRoute.platformId;
  String get _emulator => isMelon
      ? 'me.magnum.melondualds'
      : isPpsspp
          ? 'org.ppsspp.ppsspp'
          : 'com.retroarch.aarch64';
  String get _core => isMelon
      ? 'melonds'
      : isPpsspp
          ? 'ppsspp'
          : retroArchRoute.coreId;
  String get _format => isMelon
      ? 'melondualds-sram-v1'
      : isPpssppSavedata
          ? 'ppsspp-savedata-v1'
          : isPpsspp
              ? 'ppsspp-slot-v1'
              : retroArchRoute.formatId;
  SaveBackupKind get _kind =>
      isPpssppState ? SaveBackupKind.state : SaveBackupKind.save;
  String get _savedataName => ppssppSavedataDirectory!.split('/').last;
  bool _validName(String name) => isMelon
      ? name == melonName && SaveCapture.validMelonName(name)
      : isPpssppSavedata
          ? name == _savedataName
          : isPpsspp
              ? name == ppssppSlot && SaveCapture.validPpssppName(name)
              : SaveCapture.validName(name);
  bool _bindingMatches(SaveBackupBinding binding) =>
      binding.accountId == accountId &&
      binding.platformId == _platform &&
      binding.editions.length == 1 &&
      binding.editions.single.editionId == editionId &&
      binding.emulatorPackage == _emulator &&
      binding.coreId == _core &&
      binding.kind == _kind &&
      binding.formatId == _format &&
      (!isPpsspp || {'v1.20.4', '1.20.4'}.contains(binding.emulatorVersion)) &&
      (!isMelon || binding.emulatorVersion == '0.8.0.rc2');

  Future<CapturedSaveGroup> _capture(String id, String name,
          {bool restoreBaseline = false}) =>
      isMelon
          ? capture.captureMelon(
              captureId: id,
              directory: melonDirectory!,
              name: name,
              restoreBaseline: restoreBaseline)
          : isPpssppSavedata
              ? capture.capturePpssppSavedata(
                  captureId: id,
                  directory: ppssppSavedataDirectory!,
                  restoreBaseline: restoreBaseline)
              : isPpsspp
                  ? capture.capturePpsspp(
                      captureId: id,
                      directory: ppssppDirectory!,
                      name: name,
                      restoreBaseline: restoreBaseline)
                  : capture.captureRetroArch(
                      captureId: id,
                      name: name,
                      route: retroArchRoute,
                      restoreBaseline: restoreBaseline);

  String get _key => sha256
      .convert(utf8.encode(jsonEncode([
        clientId,
        accountId,
        areaId,
        editionId,
        if (isMelon) ...[
          _format,
          melonDirectory,
          melonName
        ] else if (isPpssppSavedata) ...[
          _format,
          ppssppSavedataDirectory,
          _savedataName
        ] else if (isPpsspp) ...[
          _format,
          ppssppDirectory,
          ppssppSlot
        ] else
          retroArchRoute.journalId
      ])))
      .toString();
  bool get busy => _operation != null;

  Future<String> _reviewName({String? gameId}) async {
    final store = LibraryStore(database);
    final edition = await store.edition(editionId);
    final game = edition == null ? null : await store.game(edition.gameId);
    if (game?.platformId != _platform ||
        (gameId != null && edition?.gameId != gameId) ||
        !edition!.members.any((member) => member.artifactId == artifactId)) {
      throw PlatformException(code: 'source_changed');
    }
    final name = await resolveSaveName();
    if (!_validName(name)) {
      throw PlatformException(code: 'source_changed');
    }
    return name;
  }

  Future<List<String>> reviewedNames() async => [await _reviewName()];

  /// Recover the save-folder identity from verified cloud publications, even
  /// when the emulator has not recreated a local save after reinstall.
  static Future<List<String>> discoverPpssppSavedataFolders({
    required Future<Database> database,
    required DriveSaveBackupGenerationApi generations,
    required String areaId,
    required String editionId,
    required RemoteArtifactId artifactId,
    CancelToken? cancellation,
  }) async {
    final store = LibraryStore(database);
    Future<String> reviewedGame() async {
      if (cancellation?.isCancelled == true) throw cancellation!.cancelError!;
      final edition = await store.edition(editionId);
      final game = edition == null ? null : await store.game(edition.gameId);
      if (artifactId.providerId != 'drive' ||
          artifactId.accountId != generations.accountId ||
          game?.platformId != 'psp' ||
          !edition!.members.any((member) => member.artifactId == artifactId)) {
        throw PlatformException(code: 'source_changed');
      }
      return game!.id;
    }

    final gameId = await reviewedGame();
    final target = SaveBackupBinding(
        accountId: generations.accountId,
        deviceId: 'restore-discovery',
        emulatorPackage: 'org.ppsspp.ppsspp',
        emulatorVersion: 'v1.20.4',
        coreId: 'ppsspp',
        coreVersion: 'v1.20.4',
        platformId: 'psp',
        editions: [SaveBackupEdition(gameId: gameId, editionId: editionId)],
        kind: SaveBackupKind.save,
        formatId: 'ppsspp-savedata-v1');
    final publications = await generations.discoverGenerations(
        areaId: areaId, target: target, cancellation: cancellation);
    if (await reviewedGame() != gameId) {
      throw PlatformException(code: 'source_changed');
    }
    final names = <String>{};
    for (final publication in publications) {
      final binding = publication.binding;
      if (binding.restoreIssue(target) != null ||
          binding.emulatorPackage != target.emulatorPackage ||
          binding.coreId != target.coreId ||
          !{'v1.20.4', '1.20.4'}.contains(binding.emulatorVersion)) {
        continue;
      }
      final folder = _savedataFolder(publication);
      if (folder != null) names.add(folder);
    }
    if (cancellation?.isCancelled == true) throw cancellation!.cancelError!;
    return List.unmodifiable(names.toList()..sort());
  }

  static String? _savedataFolder(SaveBackupManifest manifest) {
    if (manifest.members.isEmpty ||
        manifest.members.length > 128 ||
        manifest.members.fold<int>(0, (sum, member) => sum + member.sizeBytes) >
            512 * 1024 * 1024) {
      return null;
    }
    String? folder;
    for (final member in manifest.members) {
      final parts = member.relativePath.split('/');
      if (parts.length != 2 ||
          !parts.every(SaveCapture.validPpssppSavedataMember) ||
          member.sizeBytes > 512 * 1024 * 1024 ||
          folder != null && folder != parts.first) {
        return null;
      }
      folder = parts.first;
    }
    return folder;
  }

  Future<void> _requireName(String name, {String? gameId}) async {
    if (await _reviewName(gameId: gameId) != name) {
      throw PlatformException(code: 'source_changed');
    }
  }

  String? get issue => _issue;
  String? get pendingName =>
      _record?['state'] == 'pending' ? (_record?['name'] as String?) : null;
  List<SaveBackupManifest> get conflicts =>
      List.unmodifiable(((_record?['conflictHeads'] as List?) ?? const []).map(
          (raw) => SaveBackupManifest.decode(utf8.encode(jsonEncode(raw)))));
  bool get restorePending =>
      _record?['selectedCloudRestore'] != null ||
      ['restore', 'rollback'].any((key) =>
          _record?[key] != null &&
          (_record![key] as Map)['state'] != 'complete');
  bool get rollbackAvailable =>
      _record?['selectedCloudRestore'] == null &&
      _record?['restore'] != null &&
      (_record!['restore'] as Map)['state'] == 'complete' &&
      (_record!['restore'] as Map)['localWasAbsent'] != true &&
      (_record?['rollback'] as Map?)?['state'] != 'complete';
  bool get localCopyAvailable => _record?['localWasAbsent'] != true;
  SaveBackupManifest? get lastVerified {
    final raw = _record?['lastVerified'];
    return raw == null
        ? null
        : SaveBackupManifest.decode(utf8.encode(jsonEncode(raw)));
  }

  bool get rollbackPending =>
      _record?['rollback'] != null &&
      (_record!['rollback'] as Map)['state'] != 'complete';

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _check(CancelToken cancellation) {
    if (_disposed || cancellation.isCancelled) {
      throw const SaveBackupGenerationException(
          SaveBackupGenerationIssue.cancelled);
    }
  }

  Future<void> _schema(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS
      save_backup_game_jobs(job_key TEXT PRIMARY KEY, record_json TEXT NOT NULL)''');
    await db
        .execute('''CREATE TABLE IF NOT EXISTS save_backup_conflict_captures(
      job_key TEXT NOT NULL, generation_id TEXT NOT NULL, record_json TEXT NOT NULL,
      PRIMARY KEY(job_key, generation_id))''');
  }

  Future<void> load() async {
    final db = await database;
    await _schema(db);
    final rows = await db.query('save_backup_game_jobs',
        where: 'job_key = ?', whereArgs: [_key], limit: 1);
    if (rows.isNotEmpty) {
      final raw = rows.single['record_json'] as String;
      if (raw.length > 3 * SaveBackupManifest.maxEncodedBytes) {
        throw const FormatException('Invalid save job');
      }
      final record = jsonDecode(raw) as Map<String, dynamic>;
      if (record['key'] != _key ||
          record['schema'] != 1 ||
          !{'pending', 'complete'}.contains(record['state']) ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(record['captureId'] as String) ||
          !_validName(record['name'] as String)) {
        throw const FormatException('Invalid save job');
      }
      if (record['retireCaptureId'] != null &&
          (record['state'] != 'complete' ||
              (record['lastVerified'] == null &&
                  record['localWasAbsent'] != true) ||
              record['captures'] != null ||
              record['retireCaptureId'] != record['captureId'])) {
        throw const FormatException('Invalid capture retirement intent');
      }
      for (final rawManifest in [
        record['generation'],
        record['lastVerified'],
        ...((record['conflictHeads'] as List?) ?? const [])
      ]) {
        if (rawManifest == null) continue;
        final manifest =
            SaveBackupManifest.decode(utf8.encode(jsonEncode(rawManifest)));
        if (!_bindingMatches(manifest.binding)) {
          throw const FormatException('Changed save job binding');
        }
        _contents(manifest);
      }
      for (final operationKey in ['restore', 'rollback']) {
        final restore = record[operationKey];
        if (restore != null) {
          if (restore is! Map<String, dynamic> ||
              !RegExp(r'^[a-f0-9]{32}$').hasMatch(restore['id'] as String) ||
              !RegExp(r'^[a-f0-9]{32}$')
                  .hasMatch(restore['rollbackId'] as String) ||
              restore['id'] == restore['rollbackId'] ||
              !{'capture', 'download', 'ready', 'complete'}
                  .contains(restore['state']) ||
              !_validName(restore['name'] as String)) {
            throw const FormatException('Invalid restore intent');
          }
          final manifest = SaveBackupManifest.decode(
              utf8.encode(jsonEncode(restore['manifest'])));
          if (manifest.generationId != restore['generationId'] ||
              !_bindingMatches(manifest.binding)) {
            throw const FormatException('Changed restore binding');
          }
          _contents(manifest);
          if (operationKey == 'rollback' &&
              (record['restore'] is! Map ||
                  restore['sourceCaptureId'] !=
                      record['restore']['rollbackId'] ||
                  record['restore']['state'] != 'complete')) {
            throw const FormatException('Changed rollback association');
          }
        }
      }
      if (record['selectedCloudRestore'] != null &&
          (record['state'] != 'complete' ||
              record['selectedCloudRestore'] !=
                  record['lastVerified']?['generationId'])) {
        throw const FormatException('Changed cloud restore choice');
      }
      _record = record;
    }
    _changed();
  }

  /// Reconcile an open screen after the automatic lane updates this durable job.
  /// Admission and local ownership keep the read from racing a manual operation.
  Future<void> refresh() {
    if (_disposed) return Future.value();
    if (_operation case final pending?) return pending;
    if (_running[_key] case final pending?) {
      return pending.then((_) => refresh());
    }
    final cancellation = CancelToken();
    _cancellation = cancellation;
    final operation = Future<void>.microtask(() async {
      Future<void> Function()? release;
      try {
        release = await admission.acquire(cancellation);
        _check(cancellation);
        await load();
      } catch (_) {
        if (!cancellation.isCancelled) _issue = 'status_unavailable';
      } finally {
        try {
          await release?.call();
        } finally {
          _operation = null;
          _cancellation = null;
          _changed();
        }
      }
    });
    // A read must not occupy the backup de-duplication map: another instance's
    // requested capture still needs to run after native admission is released.
    _operation = operation;
    _changed();
    return operation;
  }

  Future<void> _persist(Map<String, dynamic> record) async {
    final db = await database;
    final encoded = jsonEncode(record);
    if (encoded.length > 3 * SaveBackupManifest.maxEncodedBytes) {
      throw const FormatException('Save job exceeds durable record limit');
    }
    await db.insert(
        'save_backup_game_jobs', {'job_key': _key, 'record_json': encoded},
        conflictAlgorithm: ConflictAlgorithm.replace);
    _record = record;
  }

  bool _referencesCapture(Map<String, dynamic> record, String id,
      {bool retainedConflict = false}) {
    if (record['captureId'] == id &&
        (retainedConflict ||
            record['state'] != 'complete' ||
            record['captures'] != null)) {
      return true;
    }
    for (final key in ['restore', 'rollback']) {
      final operation = record[key];
      if (operation is Map &&
          (operation['rollbackId'] == id ||
              operation['sourceCaptureId'] == id)) {
        return true;
      }
    }
    return false;
  }

  /// Runs under native admission. An intent and its completed backup are one
  /// journal commit; a crash during unlink replays exactly this ID, not a scan.
  Future<void> _retireCompletedCapture() async {
    final id = _record?['retireCaptureId'] as String?;
    if (id == null) return;
    try {
      final db = await database;
      var referenced = false;
      for (final table in [
        'save_backup_game_jobs',
        'save_backup_conflict_captures'
      ]) {
        for (var offset = 0;; offset += 100) {
          final rows = await db.query(table,
              columns: ['record_json'],
              orderBy: table == 'save_backup_game_jobs'
                  ? 'job_key'
                  : 'job_key, generation_id',
              limit: 100,
              offset: offset);
          for (final row in rows) {
            final raw = row['record_json'] as String;
            if (raw.length > 3 * SaveBackupManifest.maxEncodedBytes) {
              throw const FormatException('Invalid save job');
            }
            if (_referencesCapture(jsonDecode(raw) as Map<String, dynamic>, id,
                retainedConflict: table == 'save_backup_conflict_captures')) {
              referenced = true;
            }
          }
          if (rows.length < 100) break;
        }
      }
      // A retained conflict/rollback owns its copy. Drop only this redundant
      // retirement intent, never the other owner's files or journal.
      if (!referenced) await capture.retireCapture(id);
      await _persist({..._record!, 'retireCaptureId': null});
    } catch (_) {
      throw PlatformException(code: 'capture_cleanup_unavailable');
    }
  }

  Future<void> backup(String name) => _backup(name);

  /// Reconcile before an owned launch, without treating a newer clock as a
  /// replacement decision. Existing restore intents resume through the same
  /// publication/rollback path; no emulator is opened or stopped here.
  Future<void> reconcileBeforeLaunch(String name) async {
    await _backup(name, beforeLaunch: true);
    if (!_disposed &&
        ((issue == null && phase == 'cloud_selected') ||
            issue == 'pending_restore')) {
      await _restore(beforeLaunch: true);
    }
  }

  Future<void> keepLocalConflict(Set<String> reviewedHeads) {
    final name = pendingName;
    if (name == null || conflicts.isEmpty || busy) return Future.value();
    return _backup(name, reviewedHeads: Set.unmodifiable(reviewedHeads));
  }

  Future<void> restoreConflict(
      String generationId, Set<String> reviewedHeads) async {
    final name = pendingName;
    if (name == null || conflicts.isEmpty || busy) return;
    await _backup(name,
        reviewedHeads: Set.unmodifiable(reviewedHeads), useCloud: generationId);
    if (_issue == null &&
        phase == 'cloud_selected' &&
        (lastVerified?.generationId == generationId ||
            (_record?['restore'] as Map?)?['generationId'] == generationId)) {
      await _restore();
    }
  }

  /// Heads are determined by ancestry, never creation dates. Unknown parents do
  /// not authorize discarding a branch. Reject cycles rather than hiding them.
  List<SaveBackupManifest> _heads(List<SaveBackupManifest> all) {
    final byId = {for (final item in all) item.generationId: item};
    if (byId.length != all.length) {
      throw const FormatException('Duplicate generation');
    }
    final visiting = <String>{}, visited = <String>{};
    void visit(String id) {
      if (visited.contains(id) || !byId.containsKey(id)) return;
      if (!visiting.add(id)) {
        throw const FormatException('Cyclic save ancestry');
      }
      for (final parent in byId[id]!.parentGenerationIds) {
        visit(parent);
      }
      visiting.remove(id);
      visited.add(id);
    }

    for (final id in byId.keys) {
      visit(id);
    }
    final parents = all.expand((item) => item.parentGenerationIds).toSet();
    return all.where((item) => !parents.contains(item.generationId)).toList()
      ..sort((a, b) => a.generationId.compareTo(b.generationId));
  }

  Future<void> _retainConflict(Map<String, dynamic> record) async {
    final db = await database;
    await db.insert(
        'save_backup_conflict_captures',
        {
          'job_key': _key,
          'generation_id': record['generation']['generationId'],
          'record_json': jsonEncode(record),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<SaveBackupManifest>> _cloudHistory(
          SaveBackupManifest manifest, CancelToken cancellation) =>
      _cloudHistoryForBinding(manifest.binding, cancellation);

  Future<List<SaveBackupManifest>> _cloudHistoryForBinding(
      SaveBackupBinding binding, CancelToken cancellation) async {
    final compatible = await generations.discoverGenerations(
        areaId: areaId, target: binding, cancellation: cancellation);
    // PPSSPP slots are independent state streams within one game/edition.
    // Transport compatibility covers emulator/format; exact member selection
    // supplies slot identity without borrowing ancestry from another slot.
    if (isPpssppSavedata) {
      return compatible
          .where((item) =>
              _bindingMatches(item.binding) &&
              item.members.isNotEmpty &&
              item.members.every(
                  (member) => _savedataLeaf(member.relativePath) != null))
          .toList();
    }
    return isPpssppState
        ? compatible
            .where((item) =>
                item.members.length == 1 &&
                item.members.single.relativePath == ppssppSlot)
            .toList()
        : compatible;
  }

  Future<List<SaveBackupManifest>> _cloudHeads(
          SaveBackupManifest manifest, CancelToken cancellation) async =>
      _heads(await _cloudHistory(manifest, cancellation));

  /// Every ancestry link must be present in this current cloud review. A
  /// remembered base or an unknown parent ID alone cannot authorize restore.
  bool _verifiedAncestor(SaveBackupManifest head, SaveBackupManifest base,
      List<SaveBackupManifest> history) {
    final byId = {for (final item in history) item.generationId: item};
    final cloudBase = byId[base.generationId];
    if (cloudBase == null || !listEquals(cloudBase.encode(), base.encode())) {
      return false;
    }
    final pending = <String>[head.generationId];
    final visited = <String>{};
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!visited.add(id)) continue;
      if (id == base.generationId) return true;
      pending.addAll(byId[id]?.parentGenerationIds ?? const []);
    }
    return false;
  }

  /// This reviewed format is one SRAM and an optional same-stem RTC. Transport
  /// manifests retain exact source filenames; reinstall-specific names must not
  /// make identical logical save bytes diverge. Do not generalize this to other
  /// formats, whose directory/member names may carry actual game-save meaning.
  String _contents(SaveBackupManifest manifest) {
    if (isPpssppSavedata) {
      if (!_bindingMatches(manifest.binding) ||
          _savedataFolder(manifest) != _savedataName) {
        throw const FormatException('Invalid PPSSPP save folder');
      }
      final ordered = manifest.members.toList()
        ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
      return jsonEncode([
        for (final member in ordered)
          [member.relativePath, member.sizeBytes, member.sha256]
      ]);
    }
    if (isMelon) {
      if (!_bindingMatches(manifest.binding) ||
          manifest.members.length != 1 ||
          !SaveCapture.validMelonName(manifest.members.single.relativePath) ||
          manifest.members.single.sizeBytes > 64 * 1024 * 1024) {
        throw const FormatException('Invalid MelonDualDS save');
      }
      // One reviewed SRAM role. A reinstall may change the ROM-derived stem;
      // retain the remote name as provenance, publish to the current mapping.
      final member = manifest.members.single;
      return jsonEncode(['sram', member.sizeBytes, member.sha256]);
    }
    if (isPpsspp) {
      if (!_bindingMatches(manifest.binding) ||
          manifest.members.length != 1 ||
          !_validName(manifest.members.single.relativePath)) {
        throw const FormatException('Invalid PPSSPP slot group');
      }
      final member = manifest.members.single;
      return jsonEncode([member.relativePath, member.sizeBytes, member.sha256]);
    }
    final sram =
        manifest.members.where((m) => m.relativePath.endsWith('.srm')).toList();
    if (manifest.binding.formatId != _format ||
        sram.length != 1 ||
        !SaveCapture.validName(sram.single.relativePath) ||
        manifest.members.length > (retroArchRoute.includesRtc ? 2 : 1) ||
        manifest.members.any((m) => !retroArchRoute.acceptsSize(m.sizeBytes))) {
      throw const FormatException('Invalid cartridge save group');
    }
    final name = sram.single.relativePath;
    final rtcName = '${name.substring(0, name.length - 4)}.rtc';
    final roles = <List<Object>>[
      ['sram', sram.single.sizeBytes, sram.single.sha256],
    ];
    for (final member in manifest.members) {
      if (member == sram.single) continue;
      if (!retroArchRoute.includesRtc || member.relativePath != rtcName) {
        throw const FormatException('Unrelated cartridge save member');
      }
      roles.add(['rtc', member.sizeBytes, member.sha256]);
    }
    return jsonEncode(roles);
  }

  String? _savedataLeaf(String path) {
    final prefix = '$_savedataName/';
    if (!path.startsWith(prefix)) return null;
    final leaf = path.substring(prefix.length);
    return SaveCapture.validPpssppSavedataMember(leaf) ? leaf : null;
  }

  Future<void> _backup(String name,
      {Set<String>? reviewedHeads,
      String? useCloud,
      bool beforeLaunch = false}) {
    if (_disposed) return Future.value();
    final pending = _operation ?? _running[_key];
    if (pending != null) {
      // Joining a backup is not a pre-launch reconciliation result. Wait for
      // its actual completion, then perform this distinct required operation.
      return beforeLaunch
          ? pending.then((_) => _backup(name, beforeLaunch: true))
          : pending;
    }
    final cancellation = CancelToken();
    _cancellation = cancellation;
    final operation = Future<void>.microtask(() async {
      Future<void> Function()? release;
      try {
        release = await admission.acquire(cancellation);
        _check(cancellation);
        _issue = null;
        await load();
        _check(cancellation);
        await _retireCompletedCapture();
        _check(cancellation);
        if (restorePending) {
          _issue = 'pending_restore';
          return;
        }
        if (!_validName(name)) {
          throw const FormatException('Invalid save selection');
        }
        await _requireName(name);
        _check(cancellation);
        final store = LibraryStore(database);
        final edition = await store.edition(editionId);
        final game = edition == null ? null : await store.game(edition.gameId);
        if (edition == null || game?.platformId != _platform) {
          throw const FormatException('Unresolved save edition');
        }
        var record = _record;
        if (record?['state'] == 'pending' && record?['name'] != name) {
          _issue = 'pending_selection_changed';
          return;
        }
        if (record == null || record['state'] == 'complete') {
          final id = List.generate(16, (_) => Random.secure().nextInt(256))
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          record = {
            'schema': 1,
            'key': _key,
            'state': 'pending',
            'name': name,
            'captureId': id,
            'lastVerified': record?['lastVerified'],
            // Only explicitly resolved heads may join the next generation's
            // ancestry. A later, unreviewed cloud branch still needs a choice.
            'parentGenerationIds': {
              if (lastVerified != null) lastVerified!.generationId,
              ...((record?['resolvedHeadIds'] as List?) ?? const [])
                  .cast<String>()
            }.toList(),
            'generation': null,
            'captures': null,
            'restore': record?['restore'],
            'rollback': record?['rollback']
          };
          await _persist(record);
        }
        _captureId = record['captureId'] as String;
        _check(cancellation);
        if (record['generation'] == null) {
          phase = 'capture';
          _changed();
          final group = await _capture(_captureId!, name,
              restoreBaseline:
                  beforeLaunch || record['localWasAbsent'] == true);
          _check(cancellation);
          final binding = SaveBackupBinding(
              accountId: accountId,
              deviceId: group.deviceId,
              emulatorPackage: _emulator,
              emulatorVersion: group.emulatorVersion,
              coreId: _core,
              coreVersion: 'unreported',
              platformId: _platform,
              editions: [
                SaveBackupEdition(gameId: game!.id, editionId: editionId)
              ],
              kind: _kind,
              formatId: _format);
          if (group.localWasAbsent) {
            // Absence is a restore baseline, never a zero-member backup or
            // a fabricated last-good receipt. Discover using runtime/edition
            // evidence even after local job receipts have been lost.
            if (group.files.isNotEmpty) {
              throw const FormatException('Invalid absence');
            }
            record = {...record, 'localWasAbsent': true};
            await _persist(record);
            phase = 'cloud_review';
            _changed();
            final heads =
                _heads(await _cloudHistoryForBinding(binding, cancellation));
            for (final head in heads) {
              if (!_bindingMatches(head.binding) ||
                  head.binding.editions.single.gameId != game.id) {
                throw const FormatException('Changed restore binding');
              }
              _contents(head);
            }
            _check(cancellation);
            await _requireName(name, gameId: game.id);
            _check(cancellation);
            final headIds = heads.map((h) => h.generationId).toSet();
            if ((reviewedHeads != null &&
                    (!setEquals(headIds, reviewedHeads) ||
                        conflicts.isEmpty)) ||
                (useCloud != null && !headIds.contains(useCloud))) {
              await _persist({
                ...record,
                'conflictHeads': heads
                    .map((h) => jsonDecode(utf8.decode(h.encode())))
                    .toList()
              });
              _issue = 'conflict_changed';
              return;
            }
            if (heads.isEmpty) {
              await _persist({
                ...record,
                'state': 'complete',
                'captures': null,
                'retireCaptureId': record['captureId'],
                'conflictHeads': null
              });
              phase = 'no_save';
              await _retireCompletedCapture();
              return;
            }
            if ((heads.length > 1 && useCloud == null) ||
                (reviewedHeads != null && useCloud == null)) {
              await _persist({
                ...record,
                'conflictHeads': heads
                    .map((h) => jsonDecode(utf8.decode(h.encode())))
                    .toList()
              });
              _issue = 'save_conflict';
              return;
            }
            final chosen = useCloud == null
                ? heads.single
                : heads.singleWhere((h) => h.generationId == useCloud);
            final restoreId =
                List.generate(16, (_) => Random.secure().nextInt(256))
                    .map((b) => b.toRadixString(16).padLeft(2, '0'))
                    .join();
            await _persist({
              ...record,
              'state': 'complete',
              'captures': null,
              'selectedCloudRestore': null,
              'conflictHeads': null,
              'rollback': null,
              'restore': {
                'id': restoreId,
                'rollbackId': record['captureId'],
                'generationId': chosen.generationId,
                'name': name,
                'manifest': jsonDecode(utf8.decode(chosen.encode())),
                'state': 'download',
                'localWasAbsent': true
              }
            });
            phase = 'cloud_selected';
            return;
          }
          phase = 'reserve';
          _changed();
          final generationId =
              await areas.reserveAreaId(cancellation: cancellation);
          final members = <SaveBackupMember>[];
          final files = <String, String>{};
          for (final file in group.files) {
            _check(cancellation);
            final id = await areas.reserveAreaId(cancellation: cancellation);
            members.add(SaveBackupMember(
                relativePath: isPpssppSavedata
                    ? '$_savedataName/${file.name}'
                    : file.name,
                cloudFileId: id,
                sizeBytes: file.size,
                sha256: file.sha256));
            files[id] = file.file.path;
          }
          final manifest = SaveBackupManifest(
              generationId: generationId,
              binding: binding,
              parentGenerationIds:
                  (record['parentGenerationIds'] as List?)?.cast<String>() ??
                      [if (lastVerified != null) lastVerified!.generationId],
              createdAt: DateTime.now().toUtc(),
              members: members);
          record = {
            ...record,
            'localWasAbsent': false,
            'generation': jsonDecode(utf8.decode(manifest.encode())),
            'captures': files
          };
          await _persist(record);
        }
        _check(cancellation);
        var manifest = SaveBackupManifest.decode(
            utf8.encode(jsonEncode(record['generation'])));
        if (manifest.binding.editions.single.gameId != game!.id) {
          throw const FormatException('Changed game binding');
        }
        var paths = (record['captures'] as Map).cast<String, String>();
        if (paths.keys
                .toSet()
                .difference(manifest.members.map((m) => m.cloudFileId).toSet())
                .isNotEmpty ||
            paths.length != manifest.members.length) {
          throw const FormatException('Invalid captured group');
        }
        phase = 'cloud_review';
        _changed();
        final history = await _cloudHistory(manifest, cancellation);
        final heads = _heads(history);
        _check(cancellation);
        final headIds = heads.map((item) => item.generationId).toSet();
        final localContents = _contents(manifest);
        final verified = lastVerified;
        if (beforeLaunch &&
            verified != null &&
            heads.length == 1 &&
            localContents == _contents(verified) &&
            _verifiedAncestor(heads.single, verified, history)) {
          final chosen = heads.single;
          final encoded = jsonDecode(utf8.decode(chosen.encode()));
          await _requireName(name, gameId: game.id);
          _check(cancellation);
          if (_contents(chosen) == localContents) {
            await _persist({
              ...record,
              'state': 'complete',
              'generation': encoded,
              'lastVerified': encoded,
              'captures': null,
              'retireCaptureId': record['captureId'],
              'conflictHeads': null
            });
            phase = 'unchanged';
            await _retireCompletedCapture();
          } else {
            final restoreId =
                List.generate(16, (_) => Random.secure().nextInt(256))
                    .map((b) => b.toRadixString(16).padLeft(2, '0'))
                    .join();
            await _persist({
              ...record,
              'state': 'complete',
              // The chosen manifest is a restore intent, not a verified
              // replacement receipt until download and native publication pass.
              'generation': record['lastVerified'],
              'captures': null,
              'selectedCloudRestore': null,
              'conflictHeads': null,
              'rollback': null,
              'restore': {
                'id': restoreId,
                // Native publication must still match the exact bytes captured
                // before cloud review, not recapture a later changed local save.
                'rollbackId': record['captureId'],
                'generationId': chosen.generationId,
                'name': name,
                'manifest': encoded,
                'state': 'download'
              }
            });
            phase = 'cloud_selected';
          }
          return;
        }
        final needsChoice = heads.any((item) =>
            item.generationId != manifest.generationId &&
            !manifest.parentGenerationIds.contains(item.generationId) &&
            _contents(item) != localContents);
        if (reviewedHeads != null &&
            (!setEquals(headIds, reviewedHeads) || conflicts.isEmpty)) {
          await _persist({
            ...record,
            'conflictHeads':
                heads.map((h) => jsonDecode(utf8.decode(h.encode()))).toList()
          });
          _issue = 'conflict_changed';
          return;
        }
        if (needsChoice && reviewedHeads == null) {
          await _persist({
            ...record,
            'conflictHeads':
                heads.map((h) => jsonDecode(utf8.decode(h.encode()))).toList()
          });
          _issue = 'save_conflict';
          return;
        }
        if (reviewedHeads == null &&
            verified != null &&
            heads.length == 1 &&
            heads.single.generationId == verified.generationId &&
            listEquals(heads.single.encode(), verified.encode()) &&
            _contents(verified) == localContents) {
          // A lifecycle check must not manufacture another remote generation.
          // Current cloud discovery is essential: an absent or divergent head
          // cannot be replaced by our remembered last-good receipt.
          await _requireName(name, gameId: game.id);
          _check(cancellation);
          await _persist({
            ...record,
            'state': 'complete',
            'generation': record['lastVerified'],
            'captures': null,
            'retireCaptureId': record['captureId'],
            'conflictHeads': null
          });
          phase = 'unchanged';
          await _retireCompletedCapture();
          return;
        }
        if (reviewedHeads != null) {
          await _retainConflict(record);
          if (useCloud != null) {
            final chosen =
                heads.where((h) => h.generationId == useCloud).single;
            _contents(chosen);
            // A private rollback is not independently recoverable after
            // reinstall. Publish the sealed local branch, with its durable
            // reserved IDs and verified readback, before selecting a cloud
            // version that can replace it. Never rewrite the remote branch.
            phase = 'upload';
            _changed();
            await _requireName(name, gameId: game.id);
            _check(cancellation);
            await generations.publish(
                areaId: areaId,
                generation: manifest,
                captures: paths.map((key, value) => MapEntry(key, File(value))),
                cancellation: cancellation);
            _check(cancellation);
            final preservedHeads = await _cloudHeads(manifest, cancellation);
            _check(cancellation);
            // Our newly preserved branch is expected. Any other head change
            // invalidates the reviewed choice; keep both versions and ask again.
            final preservedIds =
                preservedHeads.map((h) => h.generationId).toSet();
            if (!setEquals(preservedIds.difference({manifest.generationId}),
                headIds.difference({manifest.generationId}))) {
              await _persist({
                ...record,
                'conflictHeads': preservedHeads
                    .map((h) => jsonDecode(utf8.decode(h.encode())))
                    .toList()
              });
              _issue = 'conflict_changed';
              return;
            }
            final restoreId =
                List.generate(16, (_) => Random.secure().nextInt(256))
                    .map((b) => b.toRadixString(16).padLeft(2, '0'))
                    .join();
            await _persist({
              ...record,
              'state': 'complete',
              // Selection is an intent, not a completed local restore. Keep
              // the previous receipt until verified native publication.
              'captures': null,
              'selectedCloudRestore': null,
              'rollback': null,
              'restore': {
                'id': restoreId,
                'rollbackId': record['captureId'],
                'generationId': chosen.generationId,
                'name': name,
                'manifest': jsonDecode(utf8.decode(chosen.encode())),
                // Replay the exact preserved local capture, including the
                // existing related-member validation before downloading.
                'state': 'capture'
              },
              'resolvedHeadIds': preservedIds.toList(),
              'conflictHeads': null
            });
            phase = 'cloud_selected';
            return;
          }
          // Never alter a possibly published manifest after a lost response.
          // Explicit resolution creates a new child of every reviewed branch.
          final generationId =
              await areas.reserveAreaId(cancellation: cancellation);
          final members = <SaveBackupMember>[];
          final newPaths = <String, String>{};
          for (final member in manifest.members) {
            final id = await areas.reserveAreaId(cancellation: cancellation);
            members.add(SaveBackupMember(
                relativePath: member.relativePath,
                cloudFileId: id,
                sizeBytes: member.sizeBytes,
                sha256: member.sha256));
            newPaths[id] = paths[member.cloudFileId]!;
          }
          manifest = SaveBackupManifest(
              generationId: generationId,
              binding: manifest.binding,
              parentGenerationIds:
                  {...manifest.parentGenerationIds, ...headIds}.toList(),
              createdAt: DateTime.now().toUtc(),
              members: members);
          paths = newPaths;
          record = {
            ...record,
            'generation': jsonDecode(utf8.decode(manifest.encode())),
            'captures': paths,
            'conflictHeads': null
          };
          await _persist(record);
        }
        phase = 'upload';
        _changed();
        await _requireName(name, gameId: game.id);
        _check(cancellation);
        await generations.publish(
            areaId: areaId,
            generation: manifest,
            captures: paths.map((key, value) => MapEntry(key, File(value))),
            cancellation: cancellation);
        _check(cancellation);
        // Another installation can publish between review and commit. Immutable
        // writes preserve both sides; report that branch instead of a false win.
        final after = await _cloudHeads(manifest, cancellation);
        if (after.any((h) =>
            h.generationId != manifest.generationId &&
            !manifest.parentGenerationIds.contains(h.generationId) &&
            _contents(h) != localContents)) {
          await _persist({
            ...record,
            'conflictHeads':
                after.map((h) => jsonDecode(utf8.decode(h.encode()))).toList()
          });
          _issue = 'save_conflict';
          return;
        }
        await _persist({
          ...record,
          'state': 'complete',
          'lastVerified': record['generation'],
          'captures': null,
          'retireCaptureId': record['captureId'],
          'conflictHeads': null
        });
        phase = 'verified';
        await _retireCompletedCapture();
      } on PlatformException catch (error) {
        _issue = const {
          'close_content_required',
          'stop_melon_required',
          'storage_permission',
          'runtime_unreviewed',
          'source_changed',
          'cancelled',
          'capture_cleanup_unavailable',
          'capture_busy',
          'invalid_save_size',
          'related_group_unfinished',
          'emulator_missing',
          'changed_capture',
          'root_unavailable'
        }.contains(error.code)
            ? error.code
            : 'capture_unavailable';
      } on DriveAuthorizationException catch (error) {
        _issue = 'authorization_${error.issue.name}';
      } on SaveBackupGenerationException catch (error) {
        _issue = error.issue.name;
      } on SaveBackupAreaException catch (error) {
        _issue = error.issue.name;
      } catch (_) {
        _issue = cancellation.isCancelled ? 'cancelled' : 'backup_unavailable';
      } finally {
        try {
          await release?.call();
        } finally {
          _running.remove(_key);
          _operation = null;
          _cancellation = null;
          _captureId = null;
          _changed();
        }
      }
    });
    _running[_key] = operation;
    _operation = operation;
    _changed();
    return operation;
  }

  /// Explicit replacement choice is collected by the UI, never by timestamps.
  /// A rollback capture and stable IDs are durably retained before downloading.
  Future<void> restoreLatest() {
    return _restore();
  }

  Future<void> rollbackLast() => _restore(rollback: true);

  Future<void> _restore({bool rollback = false, bool beforeLaunch = false}) {
    if (_disposed) return Future.value();
    if (_operation case final pending?) return pending;
    if (_running[_key] case final pending?) return pending;
    final cancellation = CancelToken();
    _cancellation = cancellation;
    final operation = Future<void>.microtask(() async {
      Future<void> Function()? release;
      try {
        release = await admission.acquire(cancellation);
        _check(cancellation);
        _issue = null;
        await load();
        _check(cancellation);
        await _retireCompletedCapture();
        _check(cancellation);
        var record = _record;
        if (record == null ||
            (lastVerified == null && (rollback || record['restore'] == null))) {
          _issue = 'no_verified_backup';
          return;
        }
        if (record['state'] == 'pending') {
          _issue = 'pending_backup';
          return;
        }
        if ((!rollback &&
                (record['rollback'] as Map?)?['state'] != null &&
                record['rollback']['state'] != 'complete') ||
            (rollback && !rollbackAvailable)) {
          _issue = rollback ? 'no_retained_rollback' : 'pending_rollback';
          return;
        }
        final store = LibraryStore(database);
        final edition = await store.edition(editionId);
        final game = edition == null ? null : await store.game(edition.gameId);
        if (edition == null || game?.platformId != _platform) {
          throw const FormatException('Unresolved restore edition');
        }
        final operationKey = rollback ? 'rollback' : 'restore';
        final currentName = await _reviewName();
        _check(cancellation);
        Map<String, dynamic>? restore =
            (record[operationKey] as Map?)?.cast<String, dynamic>();
        if (restore == null || restore['state'] == 'complete') {
          final manifest = rollback
              ? SaveBackupManifest.decode(
                  utf8.encode(jsonEncode(record['restore']['manifest'])))
              : lastVerified!;
          if (manifest.binding.editions.single.gameId != game!.id) {
            throw const FormatException('Changed restore game');
          }
          _contents(manifest);
          String newId() =>
              List.generate(16, (_) => Random.secure().nextInt(256))
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join();
          restore = {
            'id': newId(),
            'rollbackId': newId(),
            'generationId': manifest.generationId,
            'name': rollback ? record['restore']['name'] : currentName,
            'manifest': jsonDecode(utf8.decode(manifest.encode())),
            'state': 'capture'
          };
          if (rollback) {
            restore['sourceCaptureId'] = record['restore']['rollbackId'];
          }
          record = {
            ...record,
            operationKey: restore,
            if (!rollback) 'selectedCloudRestore': null,
            if (!rollback) 'rollback': null
          };
          await _persist(record);
        }
        final selected = SaveBackupManifest.decode(
            utf8.encode(jsonEncode(restore['manifest'])));
        if (selected.binding.editions.single.gameId != game!.id) {
          throw const FormatException('Changed restore game');
        }
        final restoreId = restore['id'] as String;
        final rollbackId = restore['rollbackId'] as String;
        final name = restore['name'] as String;
        await _requireName(name,
            gameId: selected.binding.editions.single.gameId);
        _check(cancellation);
        if (restore['state'] == 'capture') {
          phase = 'rollback_capture';
          _captureId = rollbackId;
          _changed();
          final local =
              await _capture(rollbackId, name, restoreBaseline: !rollback);
          _check(cancellation);
          if (!isPpssppSavedata &&
              !(local.localWasAbsent && local.files.isEmpty && !rollback) &&
              (local.files.length != selected.members.length ||
                  !local.files.any((file) => file.name == name))) {
            _issue = 'related_group_changed';
            return;
          }
          restore = {
            ...restore,
            'state': 'download',
            'localWasAbsent': local.localWasAbsent
          };
          record = {...record, operationKey: restore};
          await _persist(record);
        }
        _check(cancellation);
        phase = rollback ? 'rollback_verify' : 'restore_download';
        _captureId = restoreId;
        _changed();
        final cloud = rollback
            ? selected
            : await generations.loadGeneration(
                areaId: areaId,
                generationId: selected.generationId,
                target: selected.binding,
                cancellation: cancellation);
        if (utf8.decode(cloud.encode()) != utf8.decode(selected.encode())) {
          throw const SaveBackupGenerationException(
              SaveBackupGenerationIssue.invalidBinding);
        }
        _check(cancellation);
        if (restore['state'] == 'download') {
          CapturedSaveGroup? retained;
          if (rollback) {
            _captureId = restore['sourceCaptureId'] as String;
            final group = await _capture(_captureId!, name);
            _check(cancellation);
            if (!isPpssppSavedata &&
                (group.files.length != selected.members.length ||
                    !group.files.any((file) => file.name == name))) {
              throw const FormatException('Changed retained rollback group');
            }
            retained = group;
            _captureId = restoreId;
          }
          if (isPpssppSavedata) {
            final members = retained != null
                ? retained.files
                    .map((file) => RestoreSaveMember(
                        file.name,
                        file.size,
                        file.sha256,
                        file.file.openRead().map((chunk) {
                          _check(cancellation);
                          return Uint8List.fromList(chunk);
                        })))
                    .toList()
                : cloud.members
                    .map((member) => RestoreSaveMember(
                        _savedataLeaf(member.relativePath)!,
                        member.sizeBytes,
                        member.sha256,
                        generations.memberBytes(
                            areaId: areaId,
                            generation: cloud,
                            memberId: member.cloudFileId,
                            cancellation: cancellation)))
                    .toList();
            await capture.stagePpssppSavedataRestore(
                restoreId: restoreId,
                directory: ppssppSavedataDirectory!,
                members: members);
          } else if (cloud.members.length > 1) {
            final members = cloud.members.map((member) {
              final target = member.relativePath.endsWith('.srm')
                  ? name
                  : '${name.substring(0, name.length - 4)}.rtc';
              final local =
                  retained?.files.singleWhere((file) => file.name == target);
              return RestoreSaveMember(
                  target,
                  local?.size ?? member.sizeBytes,
                  local?.sha256 ?? member.sha256,
                  local != null
                      ? local.file.openRead().map((chunk) {
                          _check(cancellation);
                          return Uint8List.fromList(chunk);
                        })
                      : generations.memberBytes(
                          areaId: areaId,
                          generation: cloud,
                          memberId: member.cloudFileId,
                          cancellation: cancellation));
            }).toList();
            await capture.stageRetroArchGroupRestore(
                restoreId: restoreId, name: name, members: members);
          } else {
            final member = cloud.members.single;
            final retainedFile = retained?.files.single;
            await capture.stageRestore(
                restoreId: restoreId,
                name: name,
                size: retainedFile?.size ?? member.sizeBytes,
                sha256: retainedFile?.sha256 ?? member.sha256,
                ppssppDirectory: ppssppDirectory,
                melonDirectory: melonDirectory,
                retroArchRoute: retroArchRoute,
                bytes: retainedFile != null
                    ? retainedFile.file.openRead().map((chunk) {
                        _check(cancellation);
                        return Uint8List.fromList(chunk);
                      })
                    : generations.memberBytes(
                        areaId: areaId,
                        generation: cloud,
                        memberId: member.cloudFileId,
                        cancellation: cancellation));
          }
          _check(cancellation);
          restore = {...restore, 'state': 'ready'};
          record = {...record, operationKey: restore};
          await _persist(record);
        }
        _check(cancellation);
        phase = 'restore_publish';
        _changed();
        await _requireName(name,
            gameId: selected.binding.editions.single.gameId);
        _check(cancellation);
        if (beforeLaunch && !rollback) {
          final currentHeads = await _cloudHeads(selected, cancellation);
          _check(cancellation);
          if (currentHeads.length != 1 ||
              !listEquals(currentHeads.single.encode(), selected.encode())) {
            // Keep the sealed restore and exact rollback for explicit review.
            // Never silently publish an automatically selected stale copy. A
            // confirmed manual resume still means that particular cloud copy,
            // not an implicit choice of whichever generation arrived later.
            _issue = 'conflict_changed';
            return;
          }
        }
        if (isPpssppSavedata || selected.members.length > 1) {
          await capture.publishRestoreGroup(
              restoreId: restoreId, rollbackCaptureId: rollbackId);
        } else {
          await capture.publishRestore(
              restoreId: restoreId, rollbackCaptureId: rollbackId);
        }
        // Native acknowledges only after completed publication and a durable
        // receipt. PSP folders use one namespace exchange; legacy related
        // cartridge files retain their existing recoverable group journal.
        // Cancellation after that receipt must not discard the completed result.
        await _persist({
          ...record,
          if (!rollback) ...{
            'lastVerified': jsonDecode(utf8.decode(selected.encode())),
            'generation': jsonDecode(utf8.decode(selected.encode()))
          },
          operationKey: {...restore, 'state': 'complete'}
        });
        phase = rollback ? 'rolled_back' : 'restored';
      } on PlatformException catch (error) {
        _issue = const {
          'close_content_required',
          'stop_ppsspp_required',
          'stop_melon_required',
          'capture_cleanup_unavailable',
          'storage_permission',
          'runtime_unreviewed',
          'source_changed',
          'cancelled',
          'capture_busy',
          'invalid_save_size',
          'emulator_missing',
          'changed_capture',
          'related_group_unfinished',
          'related_group_changed',
          'restore_stage_conflict',
          'root_unavailable'
        }.contains(error.code)
            ? error.code
            : 'restore_unavailable';
      } on DriveAuthorizationException catch (error) {
        _issue = 'authorization_${error.issue.name}';
      } on SaveBackupGenerationException catch (error) {
        _issue = error.issue.name;
      } on SaveBackupAreaException catch (error) {
        _issue = error.issue.name;
      } catch (_) {
        _issue = cancellation.isCancelled ? 'cancelled' : 'restore_unavailable';
      } finally {
        try {
          await release?.call();
        } finally {
          _running.remove(_key);
          _operation = null;
          _cancellation = null;
          _captureId = null;
          _changed();
        }
      }
    });
    _running[_key] = operation;
    _operation = operation;
    _changed();
    return operation;
  }

  Future<void> cancelAndJoin() async {
    _cancellation?.cancel();
    final id = _captureId;
    try {
      if (id != null) await capture.cancel(id);
    } finally {
      await _operation;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // The screen joins before closing its owned API adapters.
    super.dispose();
  }
}
