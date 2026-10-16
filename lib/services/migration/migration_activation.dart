import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'migration_archive.dart';

abstract class MigrationSettings {
  Future<Map<String, Object?>> readPreferences();
  Future<void> writePreferences(Map<String, Object?> values);
  Future<Map<String, String>> readSecrets();
  Future<void> writeSecrets(Map<String, String> values);
}

/// Values pass through the destination's supported stores/Keystore. Opaque
/// encrypted Android XML and Google/Android account grants are never imported.
class DeviceMigrationSettings implements MigrationSettings {
  final FlutterSecureStorage secure;
  const DeviceMigrationSettings(
      {this.secure = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true))});
  @override
  Future<Map<String, Object?>> readPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return {for (final key in preferences.getKeys()) key: preferences.get(key)};
  }

  @override
  Future<void> writePreferences(Map<String, Object?> values) async {
    validatePreferences(values);
    final preferences = await SharedPreferences.getInstance();
    for (final entry in values.entries) {
      final value = entry.value;
      final bool saved;
      if (value is String) {
        saved = await preferences.setString(entry.key, value);
      } else if (value is bool) {
        saved = await preferences.setBool(entry.key, value);
      } else if (value is int) {
        saved = await preferences.setInt(entry.key, value);
      } else if (value is double) {
        saved = await preferences.setDouble(entry.key, value);
      } else if (value is List && value.every((v) => v is String)) {
        saved =
            await preferences.setStringList(entry.key, value.cast<String>());
      } else {
        throw const MigrationArchiveException('invalid_preferences');
      }
      if (!saved) throw const MigrationArchiveException('settings_not_saved');
    }
    for (final key in preferences.getKeys().difference(values.keys.toSet())) {
      if (!await preferences.remove(key)) {
        throw const MigrationArchiveException('settings_not_saved');
      }
    }
    await preferences.reload();
    if (jsonEncode(await readPreferences()) != jsonEncode(values)) {
      // Map insertion order is not a persistence contract.
      final saved = await readPreferences();
      if (saved.length != values.length ||
          values.entries
              .any((e) => jsonEncode(saved[e.key]) != jsonEncode(e.value))) {
        throw const MigrationArchiveException('settings_not_saved');
      }
    }
  }

  static void validatePreferences(Map<String, Object?> values) {
    for (final entry in values.entries) {
      final value = entry.value;
      if (entry.key.isEmpty ||
          !(value is String ||
              value is bool ||
              value is int ||
              value is double && value.isFinite ||
              value is List && value.every((v) => v is String))) {
        throw const MigrationArchiveException('invalid_preferences');
      }
    }
  }

  @override
  Future<Map<String, String>> readSecrets() => secure.readAll();
  @override
  Future<void> writeSecrets(Map<String, String> values) async {
    // Write/verify new values before retiring old ones. The migration rollback
    // envelope stays under Keystore until the durable transaction permits removal.
    for (final entry in values.entries) {
      await secure.write(key: entry.key, value: entry.value);
      if (await secure.read(key: entry.key) != entry.value) {
        throw const MigrationArchiveException('credentials_not_saved');
      }
    }
    for (final key in (await secure.readAll())
        .keys
        .toSet()
        .difference(values.keys.toSet())) {
      await secure.delete(key: key);
    }
  }
}

/// One app-private durable restore journal. Incoming files are first verified
/// beside their destination, then old files are retained by exact sibling rename.
/// Any pre-commit restart restores the complete old setup before app bootstrap.
/// Committed old state has a defined recovery purpose and is intentionally kept.
class MigrationActivation {
  static const rollbackPrefix = 'rshop.migration.rollback.';
  final Directory privateRoot;
  final MigrationSettings settings;
  final List<Directory> allowedRoots;
  File get journal => File(p.join(privateRoot.path, 'activation.json'));
  MigrationActivation(
      {required this.privateRoot,
      required this.settings,
      required this.allowedRoots});

  static Future<MigrationActivation> existing(
      Directory root, MigrationSettings settings) async {
    final journal = File(p.join(root.path, 'activation.json'));
    final roots = <Directory>[];
    if (await journal.exists()) {
      if (await journal.length() > MigrationArchive.maxManifestBytes) {
        throw const MigrationArchiveException('invalid_recovery_record');
      }
      final record = jsonDecode(await journal.readAsString()) as Map;
      final allowed = record['allowedRoots'];
      if (allowed is! List ||
          allowed.length > 16384 ||
          allowed.any((value) =>
              value is! String ||
              value == '/' ||
              !p.isAbsolute(value) ||
              value.split(p.separator).contains('..'))) {
        throw const MigrationArchiveException('invalid_recovery_record');
      }
      roots.addAll(allowed.cast<String>().map(Directory.new));
    }
    final result = MigrationActivation(
        privateRoot: root, settings: settings, allowedRoots: roots);
    if (await journal.exists()) await result._record();
    return result;
  }

  Future<void> prepare(
      {required Map<String, File> files,
      required Map<String, Object?> preferences,
      required Map<String, String> secrets}) async {
    await privateRoot.create(recursive: true);
    File? archivedPrevious;
    if (await journal.exists()) {
      final previous = await _record();
      if (previous['phase'] != 'committed') {
        throw const MigrationArchiveException('restore_pending');
      }
      final history =
          File(p.join(privateRoot.path, 'history', '${previous['id']}.json'));
      await history.parent.create(recursive: true);
      await journal.rename(history.path);
      archivedPrevious = history;
    }
    final id = List.generate(16, (_) => Random.secure().nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final oldPreferences = await settings.readPreferences();
    final oldSecrets = await settings.readSecrets();
    final previousEnvelopes = Map<String, String>.from(oldSecrets)
      ..removeWhere((key, _) => !key.startsWith(rollbackPrefix));
    oldSecrets.removeWhere((key, _) => key.startsWith(rollbackPrefix));
    final key = '$rollbackPrefix$id';
    final members = <Map<String, Object?>>[];
    try {
      for (final entry in files.entries) {
        final target = File(p.normalize(entry.key));
        await _requireTarget(target);
        if (await FileSystemEntity.type(entry.value.path, followLinks: false) !=
            FileSystemEntityType.file) {
          throw const MigrationArchiveException('unsafe_source');
        }
        final incoming = File('${target.path}.rshop-incoming-$id');
        final old = File('${target.path}.rshop-before-$id');
        if (await incoming.exists() || await old.exists()) {
          throw const MigrationArchiveException('destination_exists');
        }
        final sourceHash = '${await sha256.bind(entry.value.openRead()).first}';
        members.add({
          'target': target.path,
          'incoming': incoming.path,
          'old': old.path,
          'hadOld': await target.exists(),
          'sha256': sourceHash,
          if (await target.exists())
            'oldSha256': '${await sha256.bind(target.openRead()).first}'
        });
        await entry.value.copy(incoming.path);
        if ('${await sha256.bind(incoming.openRead()).first}' != sourceHash) {
          throw const MigrationArchiveException('copy_changed');
        }
        final sink = await incoming.open(mode: FileMode.append);
        try {
          await sink.flush();
        } finally {
          await sink.close();
        }
      }
      await settings.writeSecrets(
          {...oldSecrets, ...previousEnvelopes, key: jsonEncode(oldSecrets)});
      // Credentials to activate are held by Keystore as well, not this JSON.
      await settings.writeSecrets({
        ...await settings.readSecrets(),
        '$key.incoming': jsonEncode(secrets)
      });
      await _persist({
        'schema': 1,
        'id': id,
        'phase': 'prepared',
        'files': members,
        'oldPreferences': oldPreferences,
        'newPreferences': preferences,
        'rollbackKey': key,
        'allowedRoots': allowedRoots.map((d) => d.absolute.path).toList()
      });
    } catch (_) {
      if (await journal.exists()) await recover();
      for (final member in members) {
        final incoming = File(member['incoming'] as String);
        if (await incoming.exists()) await incoming.delete();
      }
      await settings.writeSecrets({...oldSecrets, ...previousEnvelopes});
      if (archivedPrevious != null && !await journal.exists()) {
        await archivedPrevious.rename(journal.path);
      }
      rethrow;
    }
  }

  Future<void> activate() async {
    final record = await _record();
    if (record['phase'] != 'prepared') {
      throw const MigrationArchiveException('restore_pending');
    }
    final key = record['rollbackKey'] as String;
    final saved = await settings.readSecrets();
    final incoming = saved['$key.incoming'];
    if (incoming == null) {
      throw const MigrationArchiveException('restore_pending');
    }
    final credentials = (jsonDecode(incoming) as Map).cast<String, String>();
    try {
      record['phase'] = 'applying';
      await _persist(record);
      for (final raw in record['files'] as List) {
        final member = (raw as Map).cast<String, dynamic>();
        final target = File(member['target'] as String);
        await _requireTarget(target);
        if (member['hadOld'] == true) {
          if (!await target.exists() ||
              '${await sha256.bind(target.openRead()).first}' !=
                  member['oldSha256']) {
            throw const MigrationArchiveException('destination_changed');
          }
          await target.rename(member['old'] as String);
        } else if (await target.exists()) {
          throw const MigrationArchiveException('destination_changed');
        }
        await File(member['incoming'] as String).rename(target.path);
      }
      await settings.writePreferences(
          (record['newPreferences'] as Map).cast<String, Object?>());
      await settings.writeSecrets({
        ...credentials,
        for (final entry in saved.entries)
          if (entry.key.startsWith(rollbackPrefix) &&
              entry.key != '$key.incoming')
            entry.key: entry.value
      });
      record['phase'] = 'committed';
      await _persist(record);
    } catch (_) {
      await recover();
      rethrow;
    }
  }

  Future<void> recover() async {
    if (!await journal.exists()) return;
    final record = await _record();
    if (record['phase'] == 'committed') return;
    final saved = await settings.readSecrets();
    final key = record['rollbackKey'] as String;
    final previous = saved[key];
    if (previous == null) {
      throw const MigrationArchiveException('recovery_credentials_missing');
    }
    final oldSecrets = (jsonDecode(previous) as Map).cast<String, String>();
    for (final raw in (record['files'] as List).reversed) {
      final member = (raw as Map).cast<String, dynamic>();
      final target = File(member['target'] as String);
      await _requireTarget(target);
      final old = File(member['old'] as String);
      final incoming = File(member['incoming'] as String);
      if (await old.exists() || member['hadOld'] != true) {
        if (await target.exists()) {
          final digest = '${await sha256.bind(target.openRead()).first}';
          if (digest != member['sha256']) {
            // A newer external write belongs to the user; preserve it explicitly.
            await target
                .rename('${target.path}.rshop-conflict-${record['id']}');
          } else {
            await target.delete();
          }
        }
        if (await old.exists()) await old.rename(target.path);
      }
      if (await incoming.exists()) await incoming.delete();
    }
    await settings.writePreferences(
        (record['oldPreferences'] as Map).cast<String, Object?>());
    final envelopes = Map<String, String>.from(saved)
      ..removeWhere((candidate, _) =>
          !candidate.startsWith(rollbackPrefix) ||
          candidate == '$key.incoming');
    await settings.writeSecrets({...oldSecrets, ...envelopes});
    await journal.delete();
    envelopes.remove(key);
    await settings.writeSecrets({...oldSecrets, ...envelopes});
  }

  Future<bool> hasPrevious() async =>
      await journal.exists() && (await _record())['phase'] == 'committed';

  /// Explicit recovery is another transaction; the current setup is retained
  /// as its own predecessor rather than discarded during the reversal.
  Future<void> preparePrevious() async {
    final record = await _record();
    if (record['phase'] != 'committed') {
      throw const MigrationArchiveException('restore_pending');
    }
    final saved = await settings.readSecrets();
    final previous = saved[record['rollbackKey']];
    if (previous == null) {
      throw const MigrationArchiveException('recovery_credentials_missing');
    }
    final files = <String, File>{};
    for (final raw in record['files'] as List) {
      final member = raw as Map;
      if (member['hadOld'] == true) {
        final old = File(member['old'] as String);
        if (!await old.exists() ||
            '${await sha256.bind(old.openRead()).first}' !=
                member['oldSha256']) {
          throw const MigrationArchiveException('previous_setup_changed');
        }
        files[member['target'] as String] = old;
      }
    }
    await prepare(
        files: files,
        preferences: (record['oldPreferences'] as Map).cast<String, Object?>(),
        secrets: (jsonDecode(previous) as Map).cast<String, String>());
  }

  Future<void> _requireTarget(File file) async {
    final path = file.absolute.path;
    if (!allowedRoots.any((root) => p.isWithin(root.absolute.path, path))) {
      throw const MigrationArchiveException('unsafe_destination');
    }
    var ancestor = file.parent;
    while (!await ancestor.exists()) {
      if (ancestor.parent.path == ancestor.path) {
        throw const MigrationArchiveException('unsafe_destination');
      }
      ancestor = ancestor.parent;
    }
    if (p.normalize(await ancestor.resolveSymbolicLinks()) !=
        p.normalize(ancestor.absolute.path)) {
      throw const MigrationArchiveException('unsafe_destination');
    }
    await file.parent.create(recursive: true);
    if (p.normalize(await file.parent.resolveSymbolicLinks()) !=
            p.normalize(file.parent.absolute.path) ||
        await FileSystemEntity.type(path, followLinks: false) ==
            FileSystemEntityType.link) {
      throw const MigrationArchiveException('unsafe_destination');
    }
  }

  Future<Map<String, dynamic>> _record() async {
    if (await journal.length() > MigrationArchive.maxManifestBytes) {
      throw const MigrationArchiveException('invalid_recovery_record');
    }
    final record = (jsonDecode(await journal.readAsString()) as Map)
        .cast<String, dynamic>();
    final id = record['id'];
    if (record['schema'] != 1 ||
        id is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        !{'prepared', 'applying', 'committed'}.contains(record['phase']) ||
        record['files'] is! List ||
        record['oldPreferences'] is! Map ||
        record['newPreferences'] is! Map ||
        record['rollbackKey'] != '$rollbackPrefix$id') {
      throw const MigrationArchiveException('invalid_recovery_record');
    }
    for (final raw in record['files'] as List) {
      if (raw is! Map ||
          raw['target'] is! String ||
          raw['incoming'] != '${raw['target']}.rshop-incoming-$id' ||
          raw['old'] != '${raw['target']}.rshop-before-$id' ||
          raw['hadOld'] is! bool ||
          raw['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['sha256'])) {
        throw const MigrationArchiveException('invalid_recovery_record');
      }
    }
    return record;
  }

  Future<void> _persist(Map<String, Object?> record) async {
    final staging = File('${journal.path}.new');
    await staging.writeAsString(jsonEncode(record), flush: true);
    await staging.rename(journal.path);
  }
}
