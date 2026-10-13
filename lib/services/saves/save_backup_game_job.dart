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
import '../../models/save_root_configuration.dart';
import '../../models/pcsx_save_layout.dart';
import '../../models/library_identity.dart';
import '../../models/save_emulator_coverage.dart';
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
  final bool ppssppCompanion;
  final String? ppssppSavedataDirectory;
  final String? melonDirectory, melonName;
  final RetroArchBatteryRoute retroArchRoute;
  final PcsxSaveLayout? pcsxLayout;
  final PcsxSaveCard? pcsxCard;
  final Future<Map<String, Object>> Function()? resolvePcsxGrant;
  final Future<Map<String, Object>> Function()? resolveRomCompanionGrant;
  final SaveRootConfiguration? saveRootConfiguration;
  final String? romCompanionDirectory,
      romCompanionName,
      romCompanionPlatform,
      romCompanionEmulator,
      romCompanionCore;
  Map<String, dynamic>? _record;
  SaveBackupBinding? _deviceBinding;
  List<SaveBackupManifest> _otherDeviceHeads = const [];
  Map<String, String> _deviceImportChoices = {};
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
      this.ppssppCompanion = false,
      this.ppssppSavedataDirectory,
      this.melonDirectory,
      this.melonName,
      this.pcsxLayout,
      this.pcsxCard,
      this.resolvePcsxGrant,
      this.resolveRomCompanionGrant,
      this.saveRootConfiguration,
      this.romCompanionName,
      this.romCompanionDirectory,
      this.romCompanionPlatform,
      this.romCompanionEmulator,
      this.romCompanionCore,
      this.retroArchRoute = RetroArchBatteryRoute.mgba})
      : admission = admission ?? SaveOperationAdmission() {
    if ([clientId, accountId, areaId, editionId].any((s) => s.trim().isEmpty) ||
        areas.accountId != accountId ||
        generations.accountId != accountId) {
      throw ArgumentError('Invalid save job binding');
    }
    if ((isPpsspp && retroArchRoute != RetroArchBatteryRoute.mgba) ||
        (ppssppDirectory == null) != (ppssppSlot == null) ||
        (ppssppCompanion && ppssppDirectory == null) ||
        (ppssppDirectory != null && isPpssppSavedata) ||
        (isPpssppSavedata &&
            !SaveCapture.validPpssppSavedataDirectory(
                ppssppSavedataDirectory!)) ||
        (ppssppDirectory != null &&
            (!SaveCapture.validPpssppDirectory(ppssppDirectory!) ||
                !(ppssppCompanion
                    ? SaveCapture.validPpssppCompanionName(ppssppSlot!)
                    : SaveCapture.validPpssppName(ppssppSlot!))))) {
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
    if ((pcsxLayout == null) != (pcsxCard == null) ||
        (pcsxLayout == null) != (resolvePcsxGrant == null) ||
        (isPcsx &&
            (isStandalone ||
                retroArchRoute != RetroArchBatteryRoute.mgba ||
                !pcsxLayout!.cards.contains(pcsxCard) ||
                pcsxCard!.name == null ||
                !{'libretro', 'shared'}.contains(pcsxCard!.mode)))) {
      throw ArgumentError('Invalid PlayStation card mapping');
    }
    final companionFields = [
      romCompanionDirectory,
      romCompanionName,
      romCompanionPlatform,
      romCompanionEmulator,
      romCompanionCore
    ];
    if (isRomCompanion !=
            companionFields
                .every((value) => value != null && value.trim().isNotEmpty) ||
        !isRomCompanion && companionFields.any((value) => value != null) ||
        isRomCompanion &&
            (isStandalone ||
                isPcsx ||
                !SaveCapture.validPpssppSavedataMember(romCompanionName!) ||
                romCompanionName!.lastIndexOf('.') <= 0)) {
      throw ArgumentError('Invalid ROM companion binding');
    }
    if (saveRootConfiguration != null &&
        (!isRomCompanion ||
            saveRootConfiguration!.directory != romCompanionDirectory ||
            saveRootConfiguration!.emulator != romCompanionEmulator ||
            saveRootConfiguration!.core != romCompanionCore)) {
      throw ArgumentError('Invalid configured save binding');
    }
  }

  bool get isRomCompanion => resolveRomCompanionGrant != null;
  bool get isPcsx => pcsxLayout != null;
  bool get isSharedPcsx => isPcsx && pcsxCard!.isShared;
  String? get _sharedCardKey =>
      isSharedPcsx ? pcsxLayout!.sharedResourceKey(pcsxCard!) : null;
  bool get isPpssppState => ppssppDirectory != null && !ppssppCompanion;
  bool get isPpssppSavedata => ppssppSavedataDirectory != null;
  bool get isPpsspp => ppssppDirectory != null || isPpssppSavedata;
  bool get isMelon => melonDirectory != null;
  bool get isStandalone => isPpsspp || isMelon;
  String get emulatorLabel => isRomCompanion
      ? SaveEmulatorCoverage.knownPackages[_emulator] ?? 'Emulator'
      : isMelon
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
  String get _platform => isRomCompanion
      ? romCompanionPlatform!
      : isPcsx
          ? 'psx'
          : isMelon
              ? 'nds'
              : isPpsspp
                  ? 'psp'
                  : retroArchRoute.platformId;
  String get _emulator => isRomCompanion
      ? romCompanionEmulator!
      : isMelon
          ? 'me.magnum.melondualds'
          : isPpsspp
              ? 'org.ppsspp.ppsspp'
              : 'com.retroarch.aarch64';
  String get _core => isRomCompanion
      ? romCompanionCore!
      : isPcsx
          ? 'pcsx_rearmed'
          : isMelon
              ? 'melonds'
              : isPpsspp
                  ? 'ppsspp'
                  : retroArchRoute.coreId;
  String get _format => isRomCompanion
      ? saveRootConfiguration?.format ?? 'rom-companion-files-v1'
      : isPcsx
          ? 'pcsx-${pcsxCard!.mode}-card${pcsxCard!.slot}-v1'
          : isMelon
              ? 'melondualds-sram-v1'
              : isPpssppSavedata
                  ? 'ppsspp-savedata-v1'
                  : isPpsspp
                      ? (ppssppCompanion
                          ? 'ppsspp-screenshot-jpeg-v1'
                          : 'ppsspp-slot-v1')
                      : retroArchRoute.formatId;
  SaveBackupKind get _kind =>
      saveRootConfiguration?.kind ??
      (isRomCompanion || ppssppCompanion
          ? SaveBackupKind.companion
          : isPpssppState
              ? SaveBackupKind.state
              : SaveBackupKind.save);
  String get _savedataName => ppssppSavedataDirectory!.split('/').last;
  bool _validName(String name) => isRomCompanion
      ? name == romCompanionName
      : isPcsx
          ? name == pcsxCard!.name
          : isMelon
              ? name == melonName && SaveCapture.validMelonName(name)
              : isPpssppSavedata
                  ? name == _savedataName
                  : isPpsspp
                      ? name == ppssppSlot &&
                          (ppssppCompanion
                              ? SaveCapture.validPpssppCompanionName(name)
                              : SaveCapture.validPpssppName(name))
                      : SaveCapture.validName(name);
  bool _bindingMatches(SaveBackupBinding binding) =>
      binding.accountId == accountId &&
      binding.platformId == _platform &&
      binding.sharedCardResourceKey == _sharedCardKey &&
      (isSharedPcsx ||
          (binding.editions.length == 1 &&
              binding.editions.single.editionId == editionId)) &&
      binding.emulatorPackage == _emulator &&
      binding.coreId == _core &&
      binding.kind == _kind &&
      binding.companionCompatibility ==
          (isRomCompanion && _kind == SaveBackupKind.companion
              ? SaveCompanionCompatibility.runtime
              : ppssppCompanion
                  ? SaveCompanionCompatibility.portable
                  : null) &&
      binding.formatId == _format &&
      (!isPpsspp || {'v1.20.4', '1.20.4'}.contains(binding.emulatorVersion)) &&
      (!isMelon || binding.emulatorVersion == '0.8.0.rc2');

  Future<CapturedSaveGroup> _capture(String id, String name,
      {bool restoreBaseline = false, Set<String>? companionMembers}) async {
    if (isRomCompanion) {
      final grant = await resolveRomCompanionGrant!();
      final snapshot = await capture.reviewRomCompanions(grant: grant);
      if (snapshot.romName != romCompanionName) {
        throw PlatformException(code: 'source_changed');
      }
      if (snapshot.directory != romCompanionDirectory) {
        throw PlatformException(code: 'source_changed');
      }
      if (snapshot.configuration?.identity != saveRootConfiguration?.identity) {
        throw PlatformException(code: 'source_changed');
      }
      final members = companionMembers ?? snapshot.files.keys.toSet();
      return capture.captureRomCompanions(
          captureId: id,
          grant: grant,
          snapshot: snapshot,
          members: members,
          emulatorPackage: romCompanionEmulator!,
          restoreBaseline: restoreBaseline || members.isEmpty);
    }
    return isPcsx
        ? capture.capturePcsx(
            captureId: id,
            grant: await resolvePcsxGrant!(),
            layout: pcsxLayout!,
            card: pcsxCard!,
            restoreBaseline: restoreBaseline)
        : isMelon
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
                    ? (ppssppCompanion
                            ? capture.capturePpssppCompanion
                            : capture.capturePpsspp)(
                        captureId: id,
                        directory: ppssppDirectory!,
                        name: name,
                        restoreBaseline: restoreBaseline)
                    : capture.captureRetroArch(
                        captureId: id,
                        name: name,
                        route: retroArchRoute,
                        restoreBaseline: restoreBaseline);
  }

  String get _key => sha256
      .convert(utf8.encode(jsonEncode([
        clientId,
        accountId,
        areaId,
        if (isSharedPcsx) _sharedCardKey else editionId,
        if (isRomCompanion) ...[
          _format,
          romCompanionName,
          romCompanionDirectory,
          romCompanionPlatform,
          romCompanionEmulator,
          romCompanionCore,
          if (saveRootConfiguration != null) saveRootConfiguration!.identity,
        ] else if (isPcsx) ...[
          _format,
          pcsxLayout!.directory,
          pcsxCard!.slot,
        ] else if (isMelon) ...[
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
  List<SaveBackupManifest> get otherDeviceBackups =>
      List.unmodifiable(_otherDeviceHeads);
  String _deviceChoiceKey(SaveBackupManifest manifest) => sha256
      .convert(utf8.encode(jsonEncode([
        _deviceBinding?.deviceId,
        sha256.convert(manifest.encode()).toString()
      ])))
      .toString();
  bool deviceBackupIgnored(SaveBackupManifest manifest) =>
      _deviceImportChoices[_deviceChoiceKey(manifest)] == 'ignore';
  String _deviceMemberChoiceKey(SaveBackupManifest manifest, String path) =>
      sha256
          .convert(utf8
              .encode(jsonEncode([_deviceChoiceKey(manifest), 'member', path])))
          .toString();
  bool deviceBackupMemberSelected(SaveBackupManifest manifest, String path) =>
      manifest.binding.kind == SaveBackupKind.companion &&
      !deviceBackupIgnored(manifest) &&
      manifest.members.any((member) => member.relativePath == path) &&
      _deviceImportChoices[_deviceMemberChoiceKey(manifest, path)] == 'import';

  bool _validDeviceImportMembers(
      SaveBackupManifest manifest, Set<String> paths) {
    if (!_bindingMatches(manifest.binding)) return false;
    // Validate the actual route as well as the chooser input. In particular,
    // today's screenshot route is exactly one JPEG; a crafted multi-file
    // manifest must not reach the scalar native restore path.
    try {
      _contents(manifest);
    } on FormatException {
      return false;
    }
    final available = manifest.members.map((m) => m.relativePath).toSet();
    return paths.isNotEmpty &&
        available.containsAll(paths) &&
        (manifest.binding.kind == SaveBackupKind.companion ||
            setEquals(available, paths));
  }

  List<SaveBackupManifest> get suggestedDeviceBackups {
    final current = lastVerified;
    return List.unmodifiable(_otherDeviceHeads.where((item) =>
        !_deviceImportChoices.containsKey(_deviceChoiceKey(item)) &&
        (!localCopyAvailable ||
            current == null ||
            current.binding.deviceId != _deviceBinding?.deviceId ||
            item.createdAt.isAfter(current.createdAt))));
  }

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
      _deviceImportChoices = Map<String, String>.from(
          (record['deviceImportChoices'] as Map?) ?? const {});
      if (_deviceImportChoices.entries.any((entry) =>
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.key) ||
          !{'ignore', 'import'}.contains(entry.value))) {
        throw const FormatException('Invalid device import choice');
      }
      _deviceBinding = record['deviceBinding'] == null
          ? null
          : SaveBackupBinding.fromJson(record['deviceBinding']);
      if (_deviceBinding != null && !_bindingMatches(_deviceBinding!)) {
        throw const FormatException('Changed current-device save binding');
      }
      _otherDeviceHeads = ((record['otherDeviceHeads'] as List?) ?? const [])
          .map((raw) => SaveBackupManifest.decode(utf8.encode(jsonEncode(raw))))
          .toList();
      for (final head in _otherDeviceHeads) {
        if (!_bindingMatches(head.binding) ||
            _deviceBinding == null ||
            head.binding.deviceId == _deviceBinding!.deviceId ||
            head.binding.restoreIssue(_deviceBinding!) != null) {
          throw const FormatException('Changed other-device save binding');
        }
        _contents(head);
      }
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
          if (restore.containsKey('memberPaths')) {
            final paths = restore['memberPaths'];
            if (!(restore['deviceImport'] == true ||
                    operationKey == 'rollback' && isRomCompanion) ||
                paths is! List ||
                paths.any((path) => path is! String) ||
                paths.toSet().length != paths.length ||
                !_validDeviceImportMembers(
                    manifest, paths.cast<String>().toSet())) {
              throw const FormatException('Changed device import files');
            }
          }
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
    } else {
      _record = null;
      _deviceBinding = null;
      _otherDeviceHeads = const [];
      _deviceImportChoices = {};
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
    record = {
      ...record,
      if (_deviceBinding != null) 'deviceBinding': _deviceBinding!.toJson(),
      'otherDeviceHeads': _otherDeviceHeads
          .map((item) => jsonDecode(utf8.decode(item.encode())))
          .toList(),
      'deviceImportChoices': _deviceImportChoices,
    };
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

  /// Remember a decision about this exact immutable publication, not a title,
  /// filename or clock. Ignored copies remain available for a revised choice.
  Future<void> setDeviceBackupIgnored(
      SaveBackupManifest candidate, bool ignored) {
    if (_disposed) return Future.value();
    final pending = _operation ?? _running[_key];
    if (pending != null) {
      return pending.then((_) => setDeviceBackupIgnored(candidate, ignored));
    }
    final cancellation = CancelToken();
    _cancellation = cancellation;
    final operation = Future<void>.microtask(() async {
      Future<void> Function()? release;
      Map<String, String>? previousChoices;
      try {
        release = await admission.acquire(cancellation);
        _check(cancellation);
        _issue = null;
        await load();
        if (_record == null ||
            !_otherDeviceHeads
                .any((head) => listEquals(head.encode(), candidate.encode()))) {
          _issue = 'device_import_changed';
          return;
        }
        final key = _deviceChoiceKey(candidate);
        previousChoices = _deviceImportChoices;
        _deviceImportChoices = Map.of(_deviceImportChoices);
        // Revising a publication-wide choice resets its per-file associations.
        // Otherwise Suggest could silently reselect a previously imported file.
        for (final member in candidate.members) {
          _deviceImportChoices
              .remove(_deviceMemberChoiceKey(candidate, member.relativePath));
        }
        if (ignored) {
          _deviceImportChoices[key] = 'ignore';
        } else {
          _deviceImportChoices.remove(key);
        }
        await _persist(_record!);
      } catch (_) {
        if (previousChoices != null) _deviceImportChoices = previousChoices;
        _issue = cancellation.isCancelled
            ? 'cancelled'
            : 'device_choice_unavailable';
      } finally {
        try {
          await release?.call();
        } finally {
          _running.remove(_key);
          _operation = null;
          _cancellation = null;
          _changed();
        }
      }
    });
    _operation = operation;
    _running[_key] = operation;
    _changed();
    return operation;
  }

  Future<void> importDeviceBackup(SaveBackupManifest candidate,
      {Set<String>? memberPaths}) async {
    if (_disposed || busy) return;
    final paths = Set<String>.unmodifiable(
        memberPaths ?? candidate.members.map((member) => member.relativePath));
    if (!_validDeviceImportMembers(candidate, paths)) {
      _issue = 'device_import_selection';
      _changed();
      return;
    }
    // Preserve the current device branch first. Foreign heads cannot interfere
    // with this reconciliation or become an implicit restore selection.
    try {
      await reconcileBeforeLaunch(await _reviewName());
    } on PlatformException catch (error) {
      _issue = error.code;
      _changed();
      return;
    }
    if (_issue != null || restorePending || pendingName != null) return;
    await _restore(deviceImport: candidate, deviceMemberPaths: paths);
  }

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
    var compatible = await generations.discoverGenerations(
        areaId: areaId, target: binding, cancellation: cancellation);
    // PPSSPP slots are independent state streams within one game/edition.
    // Transport compatibility covers emulator/format; exact member selection
    // supplies slot identity without borrowing ancestry from another slot.
    if (isPpssppSavedata) {
      compatible = compatible
          .where((item) =>
              _bindingMatches(item.binding) &&
              item.members.isNotEmpty &&
              item.members.every(
                  (member) => _savedataLeaf(member.relativePath) != null))
          .toList();
    }
    if (ppssppDirectory != null) {
      compatible = compatible
          .where((item) =>
              item.members.length == 1 &&
              item.members.single.relativePath == ppssppSlot)
          .toList();
    }
    // Compatibility permits an explicit portable import, never automatic
    // reconciliation across devices. A missing local save follows this rule too.
    _deviceBinding ??= binding;
    final device = _deviceBinding!.deviceId;
    final other = <String, List<SaveBackupManifest>>{};
    for (final item in compatible) {
      if (item.binding.deviceId != device &&
          _bindingMatches(item.binding) &&
          item.binding.restoreIssue(_deviceBinding!) == null) {
        _contents(item);
        other.putIfAbsent(item.binding.deviceId, () => []).add(item);
      }
    }
    _otherDeviceHeads = [
      for (final history in other.values) ..._heads(history)
    ];
    return compatible.where((item) => item.binding.deviceId == device).toList();
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
    if (isRomCompanion) {
      if (!_bindingMatches(manifest.binding) ||
          manifest.members.isEmpty ||
          manifest.members.length > 128 ||
          (saveRootConfiguration != null &&
              !saveRootConfiguration!.completeGroup(manifest.members
                  .map((member) => member.relativePath)
                  .toSet())) ||
          manifest.members.any((member) =>
              !(saveRootConfiguration?.acceptsFile(member.relativePath) ??
                  SaveCapture.validRomCompanionName(
                      romCompanionName!, member.relativePath,
                      directory: romCompanionDirectory))) ||
          manifest.members
                  .fold<int>(0, (total, member) => total + member.sizeBytes) >
              512 * 1024 * 1024) {
        throw const FormatException('Invalid ROM companion generation');
      }
      final ordered = manifest.members.toList()
        ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
      return jsonEncode([
        for (final member in ordered)
          [member.relativePath, member.sizeBytes, member.sha256]
      ]);
    }
    if (isPcsx) {
      if (!_bindingMatches(manifest.binding) ||
          manifest.members.length != 1 ||
          manifest.members.single.sizeBytes != 131072 ||
          (isSharedPcsx
              ? manifest.members.single.relativePath != pcsxCard!.name
              : !SaveCapture.validName(manifest.members.single.relativePath))) {
        throw const FormatException('Invalid PlayStation card generation');
      }
      final member = manifest.members.single;
      return jsonEncode([_format, member.sizeBytes, member.sha256]);
    }
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
        if (edition == null || game == null || game.platformId != _platform) {
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
                SaveBackupEdition(gameId: game.id, editionId: editionId)
              ],
              kind: _kind,
              companionCompatibility:
                  isRomCompanion && _kind == SaveBackupKind.companion
                      ? SaveCompanionCompatibility.runtime
                      : ppssppCompanion
                          ? SaveCompanionCompatibility.portable
                          : null,
              formatId: _format,
              sharedCardDirectory: isSharedPcsx ? pcsxLayout!.directory : null,
              sharedCardSlot: isSharedPcsx ? pcsxCard!.slot : null);
          final priorDevice =
              _deviceBinding?.deviceId ?? lastVerified?.binding.deviceId;
          if (priorDevice != null && priorDevice != binding.deviceId) {
            // Restored app data is not authority to inherit another device's
            // history or import preferences. Start a separate local history.
            record = {...record, 'parentGenerationIds': <String>[]};
          } else if (lastVerified != null &&
              lastVerified!.binding.deviceId != binding.deviceId) {
            // An explicitly imported copy is provenance, not our device's head.
            // Keep the preserved local branch as the new local ancestry base.
            record = {
              ...record,
              'parentGenerationIds':
                  ((record['parentGenerationIds'] as List?) ?? const [])
                      .where((id) => id != lastVerified!.generationId)
                      .toList()
            };
          }
          _deviceBinding = binding;
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
                  (!isSharedPcsx &&
                      head.binding.editions.single.gameId != game.id)) {
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
                'rollbackId': isRomCompanion
                    ? List.generate(16, (_) => Random.secure().nextInt(256))
                        .map((b) => b.toRadixString(16).padLeft(2, '0'))
                        .join()
                    : record['captureId'],
                'generationId': chosen.generationId,
                'name': name,
                'manifest': jsonDecode(utf8.decode(chosen.encode())),
                'state': isRomCompanion ? 'capture' : 'download',
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
        if (!isSharedPcsx &&
            manifest.binding.editions.single.gameId != game.id) {
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

  Future<void> _restore(
      {bool rollback = false,
      bool beforeLaunch = false,
      SaveBackupManifest? deviceImport,
      Set<String>? deviceMemberPaths}) {
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
            (lastVerified == null &&
                deviceImport == null &&
                (rollback || record['restore'] == null))) {
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
        if (edition == null || game == null || game.platformId != _platform) {
          throw const FormatException('Unresolved restore edition');
        }
        final operationKey = rollback ? 'rollback' : 'restore';
        final currentName = await _reviewName();
        _check(cancellation);
        if (deviceImport != null) {
          final target = _deviceBinding;
          if (target == null ||
              deviceMemberPaths == null ||
              !_validDeviceImportMembers(deviceImport, deviceMemberPaths) ||
              deviceImport.binding.deviceId == target.deviceId ||
              deviceImport.binding.restoreIssue(target) != null ||
              !_otherDeviceHeads.any(
                  (head) => listEquals(head.encode(), deviceImport.encode()))) {
            _issue = 'device_import_changed';
            return;
          }
          final reviewed = await generations.loadGeneration(
              areaId: areaId,
              generationId: deviceImport.generationId,
              target: target,
              cancellation: cancellation);
          _check(cancellation);
          if (!listEquals(reviewed.encode(), deviceImport.encode())) {
            _issue = 'device_import_changed';
            return;
          }
        }
        Map<String, dynamic>? restore =
            (record[operationKey] as Map?)?.cast<String, dynamic>();
        if (restore == null || restore['state'] == 'complete') {
          final manifest = deviceImport ??
              (rollback
                  ? SaveBackupManifest.decode(
                      utf8.encode(jsonEncode(record['restore']['manifest'])))
                  : lastVerified!);
          if (!isSharedPcsx &&
              manifest.binding.editions.single.gameId != game.id) {
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
            'state': 'capture',
            if (deviceImport != null) ...{
              'deviceImport': true,
              'memberPaths': deviceMemberPaths!.toList()..sort(),
              'deviceParentGenerationIds': [
                if (lastVerified?.binding.deviceId ==
                        _deviceBinding?.deviceId &&
                    lastVerified != null)
                  lastVerified!.generationId,
              ],
            },
          };
          if (rollback) {
            restore['sourceCaptureId'] = record['restore']['rollbackId'];
            if (isRomCompanion) {
              restore['memberPaths'] = record['restore']
                      ['retainedCompanionPaths'] ??
                  record['restore']['memberPaths'] ??
                  manifest.members
                      .map((member) => member.relativePath)
                      .toList();
            }
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
        if (!isSharedPcsx &&
            selected.binding.editions.single.gameId != game.id) {
          throw const FormatException('Changed restore game');
        }
        _contents(selected);
        final companionPaths = isRomCompanion
            ? ((restore['memberPaths'] as List?)?.cast<String>().toSet() ??
                selected.members.map((member) => member.relativePath).toSet())
            : null;
        final restoreId = restore['id'] as String;
        final rollbackId = restore['rollbackId'] as String;
        final name = restore['name'] as String;
        await _requireName(name, gameId: game.id);
        _check(cancellation);
        if (restore['state'] == 'capture') {
          phase = 'rollback_capture';
          _captureId = rollbackId;
          _changed();
          final local = await _capture(rollbackId, name,
              restoreBaseline: !rollback, companionMembers: companionPaths);
          _check(cancellation);
          if (!isRomCompanion &&
              !isPpssppSavedata &&
              !(local.localWasAbsent && local.files.isEmpty && !rollback) &&
              (local.files.length != selected.members.length ||
                  !local.files.any((file) => file.name == name))) {
            _issue = 'related_group_changed';
            return;
          }
          restore = {
            ...restore,
            'state': 'download',
            if (isRomCompanion)
              'retainedCompanionPaths':
                  local.files.map((file) => file.name).toList()..sort(),
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
            final group = await _capture(_captureId!, name,
                restoreBaseline: isRomCompanion,
                companionMembers: isRomCompanion
                    ? (record['restore']['memberPaths'] as List?)
                            ?.cast<String>()
                            .toSet() ??
                        selected.members
                            .map((member) => member.relativePath)
                            .toSet()
                    : null);
            _check(cancellation);
            if (!isRomCompanion &&
                !isPpssppSavedata &&
                (group.files.length != selected.members.length ||
                    !group.files.any((file) => file.name == name))) {
              throw const FormatException('Changed retained rollback group');
            }
            retained = group;
            _captureId = restoreId;
          }
          if (isRomCompanion) {
            final grant = await resolveRomCompanionGrant!();
            final snapshot = await capture.reviewRomCompanions(grant: grant);
            if (snapshot.romName != romCompanionName) {
              throw PlatformException(code: 'source_changed');
            }
            if (snapshot.directory != romCompanionDirectory) {
              throw PlatformException(code: 'source_changed');
            }
            final members = <RestoreSaveMember>[];
            for (final member in cloud.members.where(
                (member) => companionPaths!.contains(member.relativePath))) {
              final local = retained?.files
                  .where((file) => file.name == member.relativePath)
                  .firstOrNull;
              // Rollback restores only files actually retained. It never turns
              // prior absence into a deletion of a newly restored companion.
              if (rollback && local == null) continue;
              members.add(RestoreSaveMember(
                  member.relativePath,
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
                          cancellation: cancellation)));
            }
            await capture.stageRomCompanionRestore(
                restoreId: restoreId,
                grant: grant,
                snapshot: snapshot,
                emulatorPackage: romCompanionEmulator!,
                members: members);
          } else if (isPpssppSavedata) {
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
                restoreId: restoreId,
                name: name,
                members: members,
                route: retroArchRoute);
          } else {
            final member = cloud.members.single;
            final retainedFile = retained?.files.single;
            final bytes = retainedFile != null
                ? retainedFile.file.openRead().map((chunk) {
                    _check(cancellation);
                    return Uint8List.fromList(chunk);
                  })
                : generations.memberBytes(
                    areaId: areaId,
                    generation: cloud,
                    memberId: member.cloudFileId,
                    cancellation: cancellation);
            if (isPcsx) {
              final grant = await resolvePcsxGrant!();
              _check(cancellation);
              await capture.stagePcsxRestore(
                  restoreId: restoreId,
                  grant: grant,
                  layout: pcsxLayout!,
                  card: pcsxCard!,
                  size: retainedFile?.size ?? member.sizeBytes,
                  sha256: retainedFile?.sha256 ?? member.sha256,
                  bytes: bytes);
            } else {
              await capture.stageRestore(
                  ppssppCompanion: ppssppCompanion,
                  restoreId: restoreId,
                  name: name,
                  size: retainedFile?.size ?? member.sizeBytes,
                  sha256: retainedFile?.sha256 ?? member.sha256,
                  ppssppDirectory: ppssppDirectory,
                  melonDirectory: melonDirectory,
                  retroArchRoute: retroArchRoute,
                  bytes: bytes);
            }
          }
          _check(cancellation);
          restore = {...restore, 'state': 'ready'};
          record = {...record, operationKey: restore};
          await _persist(record);
        }
        _check(cancellation);
        phase = 'restore_publish';
        _changed();
        await _requireName(name, gameId: game.id);
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
        if (isPcsx) {
          final grant = await resolvePcsxGrant!();
          _check(cancellation);
          await capture.publishPcsxRestore(
              restoreId: restoreId,
              rollbackCaptureId: rollbackId,
              grant: grant,
              layout: pcsxLayout!,
              card: pcsxCard!);
        } else if (isRomCompanion ||
            isPpssppSavedata ||
            selected.members.length > 1) {
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
        if (!rollback && restore['deviceImport'] == true) {
          _deviceImportChoices[_deviceChoiceKey(selected)] = 'import';
          if (selected.binding.kind == SaveBackupKind.companion) {
            final paths = (restore['memberPaths'] as List?)?.cast<String>() ??
                selected.members.map((member) => member.relativePath).toList();
            for (final member in selected.members) {
              _deviceImportChoices[
                      _deviceMemberChoiceKey(selected, member.relativePath)] =
                  paths.contains(member.relativePath) ? 'import' : 'ignore';
            }
          }
        }
        await _persist({
          ...record,
          if (!rollback && restore['deviceImport'] == true)
            'resolvedHeadIds': restore['deviceParentGenerationIds'],
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
