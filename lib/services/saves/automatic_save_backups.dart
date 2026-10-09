import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/config/source.dart';
import '../../models/library_identity.dart';
import '../drive/drive_runtime.dart';
import 'drive_save_backup_area.dart';
import 'drive_save_backup_generation.dart';
import 'save_backup_game_job.dart';
import 'save_backup_setup.dart';
import 'save_capture.dart';

/// Explicit published-slot association, not a folder watch or title match.
/// RetroArch's closed-content handshake is not yet an unattended capture route.
class AutomaticSaveMapping {
  final String clientId, accountId, areaId, editionId, directory, slot, title;
  final RemoteArtifactId artifactId;
  AutomaticSaveMapping._(Map<String, dynamic> value)
      : clientId = value['clientId'] as String,
        accountId = value['accountId'] as String,
        areaId = value['areaId'] as String,
        editionId = value['editionId'] as String,
        directory = value['directory'] as String,
        slot = value['slot'] as String,
        title = value['title'] as String,
        artifactId = RemoteArtifactId.fromJson(
            value['artifact'] as Map<String, dynamic>) {
    if (value['schema'] != 1 ||
        [clientId, accountId, areaId, editionId, title]
            .any((s) => s.trim().isEmpty || s.length > 1024) ||
        artifactId.providerId != 'drive' ||
        artifactId.accountId != accountId ||
        !SaveCapture.validPpssppDirectory(directory) ||
        !SaveCapture.validPpssppName(slot)) {
      throw const FormatException('Invalid automatic save mapping');
    }
  }

  factory AutomaticSaveMapping.fromJob(SaveBackupGameJob job,
      {required String title}) {
    if (!job.isPpsspp) {
      throw UnsupportedError(
          'Unattended capture is not reviewed for this route');
    }
    return AutomaticSaveMapping._({
      'schema': 1,
      'clientId': job.clientId,
      'accountId': job.accountId,
      'areaId': job.areaId,
      'editionId': job.editionId,
      'directory': job.ppssppDirectory,
      'slot': job.ppssppSlot,
      'artifact': job.artifactId.toJson(),
      'title': title,
    });
  }

  String get slotStorageKey =>
      ppssppMappingKey(clientId, accountId, editionId, artifactId);
  static String ppssppMappingKey(String clientId, String accountId,
          String editionId, RemoteArtifactId artifact) =>
      'save_ppsspp_mapping_v1_${sha256.convert(utf8.encode(jsonEncode([
            clientId,
            accountId,
            editionId,
            artifact.key
          ])))}';
  String get key => sha256
      .convert(utf8.encode(jsonEncode([
        clientId,
        accountId,
        areaId,
        editionId,
        artifactId.key,
        directory,
        slot
      ])))
      .toString();
  String encode() => jsonEncode({
        'schema': 1,
        'clientId': clientId,
        'accountId': accountId,
        'areaId': areaId,
        'editionId': editionId,
        'artifact': artifactId.toJson(),
        'directory': directory,
        'slot': slot,
        'title': title,
      });
}

class AutomaticSaveStatus {
  final bool enabled;
  final String? outcome, issue;
  const AutomaticSaveStatus({required this.enabled, this.outcome, this.issue});
}

/// One process-owned serial lane, with durable opt-in and event requests.
/// No timers, recursive file scans, automatic restore or conflict choices.
/// Android background dispatch is a separate required S10 integration.
class AutomaticSaveBackups extends ChangeNotifier {
  final Future<Database> database;
  final SharedPreferences preferences;
  final List<Source> Function() sources;
  final SaveBackupGameJob Function(
      AutomaticSaveMapping, Future<String> Function())? createJob;
  Future<void>? _operation;
  Future<void> _events = Future.value();
  SaveBackupGameJob? _active;
  String? _activeKey;
  bool _disposed = false;
  AutomaticSaveBackups(
      {required this.database,
      required this.preferences,
      required this.sources,
      this.createJob});
  bool get busy => _operation != null;
  String? get activeMappingKey => _activeKey;

  Future<Database> _db() async {
    final db = await database;
    await db.execute('''CREATE TABLE IF NOT EXISTS automatic_save_backups(
      mapping_key TEXT PRIMARY KEY, record_json TEXT NOT NULL,
      enabled INTEGER NOT NULL, requested INTEGER NOT NULL DEFAULT 0,
      handled INTEGER NOT NULL DEFAULT 0, outcome TEXT, issue TEXT)''');
    return db;
  }

  Future<AutomaticSaveStatus> status(AutomaticSaveMapping mapping) async {
    final db = await _db();
    final rows = await db.query('automatic_save_backups',
        where: 'mapping_key = ?', whereArgs: [mapping.key]);
    if (rows.isEmpty) return const AutomaticSaveStatus(enabled: false);
    final row = rows.single;
    return AutomaticSaveStatus(
        enabled: row['enabled'] == 1,
        outcome: row['outcome'] as String?,
        issue: row['issue'] as String?);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> setEnabled(AutomaticSaveMapping mapping, bool enabled) async {
    final db = await _db();
    if (enabled) {
      _requireConfiguration(mapping);
      await db.transaction((tx) async {
        final old = await tx.query('automatic_save_backups',
            where: 'mapping_key = ?', whereArgs: [mapping.key]);
        if (old.isEmpty) {
          final count = Sqflite.firstIntValue(await tx
              .rawQuery('SELECT COUNT(*) FROM automatic_save_backups'))!;
          if (count >= 4096) throw StateError('Save mapping limit reached');
          await tx.insert('automatic_save_backups', {
            'mapping_key': mapping.key,
            'record_json': mapping.encode(),
            'enabled': 1
          });
        } else {
          await tx.update('automatic_save_backups',
              {'record_json': mapping.encode(), 'enabled': 1},
              where: 'mapping_key = ?', whereArgs: [mapping.key]);
        }
      });
    } else {
      await db.update('automatic_save_backups', {'enabled': 0},
          where: 'mapping_key = ?', whereArgs: [mapping.key]);
      if (_activeKey == mapping.key) await _active?.cancelAndJoin();
    }
    _notify();
  }

  void _requireConfiguration(AutomaticSaveMapping mapping) {
    final configured = sources().any((s) =>
        s.enabled &&
        s.type == SourceType.drive &&
        s.id == mapping.artifactId.sourceId &&
        s.drive?.accountId == mapping.accountId &&
        s.drive?.serverClientId == mapping.clientId);
    final setup = jsonDecode(preferences.getString(
            SaveBackupSetup.storageKey(mapping.clientId, mapping.accountId)) ??
        '{}');
    final slot =
        jsonDecode(preferences.getString(mapping.slotStorageKey) ?? '{}');
    if (!configured ||
        setup is! Map ||
        setup['ready'] != true ||
        setup['areaId'] != mapping.areaId ||
        slot is! Map ||
        slot['directory'] != mapping.directory ||
        slot['slot'] != mapping.slot) {
      throw PlatformException(code: 'source_changed');
    }
  }

  Future<String> _resolve(AutomaticSaveMapping mapping) async {
    _requireConfiguration(mapping);
    final db = await _db();
    final rows = await db.query('automatic_save_backups',
        where: 'mapping_key = ? AND enabled = 1', whereArgs: [mapping.key]);
    if (_disposed ||
        rows.length != 1 ||
        rows.single['record_json'] != mapping.encode()) {
      throw PlatformException(code: 'source_changed');
    }
    return mapping.slot;
  }

  SaveBackupGameJob _open(AutomaticSaveMapping mapping) {
    Future<String> resolve() => _resolve(mapping);
    if (createJob != null) return createJob!(mapping, resolve);
    final authorization =
        DriveRuntime.instance.authorizationFor(mapping.clientId);
    return SaveBackupGameJob(
        database: database,
        capture: SaveCapture(),
        areas: DriveSaveBackupAreaApi(
            authorization: authorization, accountId: mapping.accountId),
        generations: DriveSaveBackupGenerationApi(
            authorization: authorization, accountId: mapping.accountId),
        clientId: mapping.clientId,
        accountId: mapping.accountId,
        areaId: mapping.areaId,
        editionId: mapping.editionId,
        artifactId: mapping.artifactId,
        ppssppDirectory: mapping.directory,
        ppssppSlot: mapping.slot,
        resolveSaveName: resolve);
  }

  /// Called by real app startup/resume events; repeated events join the lane.
  /// A crash leaves requested > handled, while the existing game job retains
  /// its exact sealed capture/reserved remote objects for idempotent resume.
  Future<void> checkEnabled() {
    final event = _events.then((_) async {
      if (_disposed) return;
      final db = await _db();
      await db.rawUpdate(
          'UPDATE automatic_save_backups SET requested = requested + 1 WHERE enabled = 1');
      await _drain();
    });
    _events = event.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return event;
  }

  Future<void> _drain() {
    if (_operation != null) return _operation!;
    final operation = Future<void>.microtask(() async {
      final db = await _db();
      while (!_disposed) {
        final rows = await db.query('automatic_save_backups',
            where: 'enabled = 1 AND requested > handled',
            orderBy: 'mapping_key',
            limit: 1);
        if (rows.isEmpty) break;
        final row = rows.single;
        String? outcome, issue;
        SaveBackupGameJob? job;
        try {
          final raw = row['record_json'] as String;
          if (raw.length > 16384) {
            throw const FormatException('Invalid mapping');
          }
          final mapping =
              AutomaticSaveMapping._(jsonDecode(raw) as Map<String, dynamic>);
          if (mapping.key != row['mapping_key']) {
            throw const FormatException('Changed mapping');
          }
          await _resolve(mapping);
          _activeKey = mapping.key;
          job = _active = _open(mapping);
          job.addListener(_notify);
          await job.load();
          if (job.conflicts.isNotEmpty) {
            issue = 'save_conflict';
          } else if (job.restorePending) {
            issue = 'pending_restore';
          } else {
            await job.backup(mapping.slot);
            // A concurrent manual operation may own the same durable job.
            // Refresh after joining it, never interpret another object's idle
            // fields as proof of our requested capture being verified.
            await job.load();
            outcome = job.phase;
            issue = job.issue;
            if (outcome == 'idle' && issue == null) {
              issue = 'manual_operation_joined';
            }
          }
        } on PlatformException catch (error) {
          issue = error.code == 'source_changed'
              ? error.code
              : 'backup_unavailable';
        } catch (_) {
          issue = 'backup_unavailable';
        } finally {
          if (job != null) {
            await job.cancelAndJoin();
            job.removeListener(_notify);
            job.dispose();
            job.areas.close();
            job.generations.close();
          }
          _active = null;
          _activeKey = null;
        }
        await db.update(
            'automatic_save_backups',
            {
              'handled': row['requested'],
              'outcome': outcome,
              'issue': issue,
            },
            where: 'mapping_key = ? AND record_json = ?',
            whereArgs: [row['mapping_key'], row['record_json']]);
        _notify();
      }
    });
    _operation = operation.whenComplete(() => _operation = null);
    return _operation!;
  }

  Future<void> cancelAndJoin() async {
    await _active?.cancelAndJoin();
    await _operation;
  }

  @override
  void dispose() {
    _disposed = true;
    _active?.cancelAndJoin();
    super.dispose();
  }
}
