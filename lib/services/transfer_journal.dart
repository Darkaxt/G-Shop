import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/transfer_record.dart';

/// Additive transfer/install schema. Integration into the application database
/// migration remains the responsibility of DatabaseService.
class TransferJournalSchema {
  TransferJournalSchema._();

  static Future<void> install(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS transfer_records (
      transfer_id TEXT PRIMARY KEY,
      destination_root TEXT NOT NULL,
      relative_path TEXT NOT NULL,
      artifact_key TEXT NOT NULL,
      lifecycle TEXT NOT NULL,
      durable_offset INTEGER NOT NULL,
      revision INTEGER NOT NULL,
      record_json TEXT NOT NULL
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_transfer_lifecycle
      ON transfer_records(lifecycle, transfer_id)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS installed_artifacts (
      installation_id TEXT PRIMARY KEY,
      transfer_id TEXT NOT NULL UNIQUE,
      destination_root TEXT NOT NULL,
      relative_path TEXT NOT NULL,
      record_json TEXT NOT NULL,
      UNIQUE(destination_root, relative_path)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS transfer_target_owners (
      destination_root TEXT NOT NULL,
      relative_path TEXT NOT NULL,
      transfer_id TEXT NOT NULL UNIQUE,
      installation_id TEXT,
      PRIMARY KEY(destination_root, relative_path)
    )''');
  }
}

/// Durable state only: this class performs no filesystem operations and never
/// infers publication or completion from a filename's existence.
class TransferJournal {
  static const _digestHexLengths = {'md5': 32, 'sha1': 40, 'sha256': 64};
  final Future<Database> _database;
  TransferJournal(this._database);

  /// Reserves the target and creates a new queued transfer in one transaction.
  Future<TransferRecord> create(TransferRecord record) async {
    if (record.revision != 0 ||
        record.lifecycle != TransferLifecycle.queued ||
        record.durableOffset != 0 ||
        record.verifiedChecksums.isNotEmpty ||
        record.errorCode != null) {
      throw StateError('A new transfer must be a pristine queued record');
    }
    final db = await _database;
    return db.transaction((txn) async {
      if (await _transfer(txn, record.id) != null) {
        throw StateError('Transfer ID is already in use');
      }
      final owner = await _targetOwner(
        txn,
        record.destinationRoot,
        record.relativePath,
      );
      if (owner != null) {
        throw StateError('Destination target already has an owner');
      }
      await txn.insert('transfer_target_owners', {
        'destination_root': record.destinationRoot,
        'relative_path': record.relativePath,
        'transfer_id': record.id,
        'installation_id': null,
      });
      await txn.insert('transfer_records', _transferValues(record));
      return record;
    });
  }

  /// Applies one lifecycle/checkpoint update using [record.revision] as the
  /// compare-and-swap token. The returned record contains the next revision.
  Future<TransferRecord> save(TransferRecord record) async {
    final db = await _database;
    return db.transaction((txn) async {
      final previous = await _requiredTransfer(txn, record.id);
      _requireRevisionAndIdentity(previous, record);
      if (record.lifecycle == TransferLifecycle.completed) {
        throw StateError('Only atomic completion may declare completed');
      }
      if (!_validTransition(previous.lifecycle, record.lifecycle)) {
        throw StateError(
          'Invalid transfer transition: '
          '${previous.lifecycle.name} -> ${record.lifecycle.name}',
        );
      }
      if (record.durableOffset < previous.durableOffset) {
        throw StateError('Durable offset cannot decrease implicitly');
      }
      final hashesChanged = !_sameMap(
        previous.verifiedChecksums,
        record.verifiedChecksums,
      );
      if (hashesChanged && record.lifecycle != TransferLifecycle.verifying) {
        throw StateError(
            'Verified hashes may only be recorded while verifying');
      }
      if (record.verifiedChecksums.isNotEmpty) {
        final size = record.artifact.sizeBytes;
        if (size == null || record.durableOffset != size) {
          throw StateError('Partial bytes cannot be recorded as verified');
        }
      }
      final next = record.copyWith(revision: record.revision + 1);
      await _updateTransfer(txn, next, expectedRevision: record.revision);
      return next;
    });
  }

  /// Explicitly forgets durable partial progress after the transfer engine has
  /// discarded this transfer's stage bytes. No file is touched by the journal.
  Future<TransferRecord> resetPartial(TransferRecord record) async {
    final db = await _database;
    return db.transaction((txn) async {
      final previous = await _requiredTransfer(txn, record.id);
      _requireExactRecord(previous, record);
      if (record.lifecycle != TransferLifecycle.paused &&
          record.lifecycle != TransferLifecycle.failed) {
        throw StateError('Partial reset requires a paused or failed transfer');
      }
      final next = record.copyWith(
        durableOffset: 0,
        verifiedChecksums: const {},
        revision: record.revision + 1,
      );
      await _updateTransfer(txn, next, expectedRevision: record.revision);
      return next;
    });
  }

  /// Commits the exact installation manifest and `completed` lifecycle together.
  /// The caller must already have published the bytes and captured native file
  /// identity; this transaction makes only the durable ownership declaration.
  Future<TransferRecord> complete(
    TransferRecord record,
    InstalledArtifact installation,
  ) async {
    final db = await _database;
    return db.transaction((txn) async {
      final previous = await _requiredTransfer(txn, record.id);
      _requireExactRecord(previous, record);
      _requireCompleteBytes(record);
      _requireMatchingInstallation(record, installation);

      final owners = await txn.query(
        'transfer_target_owners',
        columns: ['transfer_id', 'installation_id'],
        where: 'destination_root = ? AND relative_path = ?',
        whereArgs: [record.destinationRoot, record.relativePath],
        limit: 1,
      );
      if (owners.isEmpty || owners.single['transfer_id'] != record.id) {
        throw StateError('Destination ownership changed before completion');
      }
      final existingInstallation = owners.single['installation_id'] as String?;
      if (existingInstallation != null) {
        throw StateError('Destination already has an installed owner');
      }
      final targetInstallations = await txn.query(
        'installed_artifacts',
        columns: ['installation_id'],
        where: 'destination_root = ? AND relative_path = ?',
        whereArgs: [record.destinationRoot, record.relativePath],
        limit: 1,
      );
      if (targetInstallations.isNotEmpty) {
        throw StateError('Destination already has an installation manifest');
      }

      await txn.insert('installed_artifacts', {
        'installation_id': installation.id,
        'transfer_id': installation.transferId,
        'destination_root': installation.destinationRoot,
        'relative_path': installation.relativePath,
        'record_json': jsonEncode(installation.toJson()),
      });
      final completed = record.copyWith(
        lifecycle: TransferLifecycle.completed,
        revision: record.revision + 1,
        clearErrorCode: true,
      );
      await _updateTransfer(txn, completed, expectedRevision: record.revision);
      final ownerUpdates = await txn.update(
        'transfer_target_owners',
        {'installation_id': installation.id},
        where: '''destination_root = ? AND relative_path = ?
          AND transfer_id = ? AND installation_id IS NULL''',
        whereArgs: [
          record.destinationRoot,
          record.relativePath,
          record.id,
        ],
      );
      if (ownerUpdates != 1) {
        throw StateError('Destination ownership changed during completion');
      }
      return completed;
    });
  }

  Future<TransferRecord?> transfer(String id) async {
    final db = await _database;
    return _transfer(db, id);
  }

  Future<String?> targetOwner({
    required String destinationRoot,
    required String relativePath,
  }) async {
    final db = await _database;
    return _targetOwner(db, destinationRoot, relativePath);
  }

  Future<InstalledArtifact?> installationForTarget({
    required String destinationRoot,
    required String relativePath,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'installed_artifacts',
      columns: ['record_json'],
      where: 'destination_root = ? AND relative_path = ?',
      whereArgs: [destinationRoot, relativePath],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return InstalledArtifact.fromJson(
      (jsonDecode(rows.single['record_json'] as String) as Map)
          .cast<String, dynamic>(),
    );
  }

  static Future<TransferRecord?> _transfer(
    DatabaseExecutor db,
    String id,
  ) async {
    final rows = await db.query(
      'transfer_records',
      columns: ['record_json'],
      where: 'transfer_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TransferRecord.fromJson(
      (jsonDecode(rows.single['record_json'] as String) as Map)
          .cast<String, dynamic>(),
    );
  }

  static Future<TransferRecord> _requiredTransfer(
    DatabaseExecutor db,
    String id,
  ) async {
    final result = await _transfer(db, id);
    if (result == null) throw StateError('Unknown transfer');
    return result;
  }

  static Future<String?> _targetOwner(
    DatabaseExecutor db,
    String destinationRoot,
    String relativePath,
  ) async {
    final rows = await db.query(
      'transfer_target_owners',
      columns: ['transfer_id'],
      where: 'destination_root = ? AND relative_path = ?',
      whereArgs: [destinationRoot, relativePath],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['transfer_id'] as String;
  }

  static Map<String, Object?> _transferValues(TransferRecord record) => {
        'transfer_id': record.id,
        'destination_root': record.destinationRoot,
        'relative_path': record.relativePath,
        'artifact_key': record.artifact.id.key,
        'lifecycle': record.lifecycle.name,
        'durable_offset': record.durableOffset,
        'revision': record.revision,
        'record_json': jsonEncode(record.toJson()),
      };

  static Future<void> _updateTransfer(
    DatabaseExecutor db,
    TransferRecord record, {
    required int expectedRevision,
  }) async {
    final updates = await db.update(
      'transfer_records',
      _transferValues(record),
      where: 'transfer_id = ? AND revision = ?',
      whereArgs: [record.id, expectedRevision],
    );
    if (updates != 1) {
      throw StateError('Stale transfer revision');
    }
  }

  static void _requireRevisionAndIdentity(
    TransferRecord previous,
    TransferRecord proposed,
  ) {
    if (previous.revision != proposed.revision) {
      throw StateError('Stale transfer revision');
    }
    if (previous.id != proposed.id ||
        previous.destinationRoot != proposed.destinationRoot ||
        previous.relativePath != proposed.relativePath ||
        previous.stagePath != proposed.stagePath ||
        !_sameJson(previous.artifact.toJson(), proposed.artifact.toJson())) {
      throw StateError('Transfer identity is immutable');
    }
  }

  static void _requireExactRecord(
    TransferRecord previous,
    TransferRecord proposed,
  ) {
    _requireRevisionAndIdentity(previous, proposed);
    if (!_sameJson(previous.toJson(), proposed.toJson())) {
      throw StateError('Operation requires the exact durable transfer record');
    }
  }

  static void _requireCompleteBytes(TransferRecord record) {
    if (record.lifecycle != TransferLifecycle.publishing) {
      throw StateError('Completion requires the publishing lifecycle');
    }
    final size = record.artifact.sizeBytes;
    if (size == null || record.durableOffset != size) {
      throw StateError('Completion requires all source bytes');
    }
    final expected = record.artifact.providerChecksums;
    final recognized = expected.entries.where((entry) {
      final length = _digestHexLengths[entry.key];
      if (length == null) return false;
      if (!RegExp('^[0-9a-fA-F]{$length}\$').hasMatch(entry.value)) {
        throw StateError('Malformed provider checksum');
      }
      return true;
    }).toList();
    if (recognized.isEmpty || record.verifiedChecksums['sha256'] == null) {
      throw StateError('Completion requires provider and local verification');
    }
    for (final checksum in recognized) {
      final verified = record.verifiedChecksums[checksum.key];
      if (verified == null ||
          verified.toLowerCase() != checksum.value.toLowerCase()) {
        throw StateError('Provider checksum was not verified');
      }
    }
  }

  static void _requireMatchingInstallation(
    TransferRecord record,
    InstalledArtifact installation,
  ) {
    if (installation.transferId != record.id ||
        installation.destinationRoot != record.destinationRoot ||
        installation.relativePath != record.relativePath ||
        installation.sizeBytes != record.artifact.sizeBytes ||
        !_sameJson(installation.artifact.toJson(), record.artifact.toJson()) ||
        !_sameMap(
          installation.verifiedChecksums,
          record.verifiedChecksums,
        )) {
      throw StateError('Installation does not match the verified transfer');
    }
  }

  static bool _validTransition(
    TransferLifecycle from,
    TransferLifecycle to,
  ) {
    if (from == to) return from != TransferLifecycle.completed;
    return switch (from) {
      TransferLifecycle.queued => to == TransferLifecycle.transferring ||
          to == TransferLifecycle.paused ||
          to == TransferLifecycle.awaitingAuthorization ||
          to == TransferLifecycle.failed,
      TransferLifecycle.transferring => to == TransferLifecycle.paused ||
          to == TransferLifecycle.awaitingAuthorization ||
          to == TransferLifecycle.verifying ||
          to == TransferLifecycle.failed,
      TransferLifecycle.paused => to == TransferLifecycle.queued ||
          to == TransferLifecycle.transferring ||
          to == TransferLifecycle.awaitingAuthorization ||
          to == TransferLifecycle.failed,
      TransferLifecycle.awaitingAuthorization =>
        to == TransferLifecycle.queued ||
            to == TransferLifecycle.transferring ||
            to == TransferLifecycle.paused ||
            to == TransferLifecycle.failed,
      TransferLifecycle.verifying => to == TransferLifecycle.publishing ||
          to == TransferLifecycle.paused ||
          to == TransferLifecycle.failed,
      TransferLifecycle.publishing =>
        to == TransferLifecycle.paused || to == TransferLifecycle.failed,
      TransferLifecycle.completed => false,
      TransferLifecycle.failed => to == TransferLifecycle.queued ||
          to == TransferLifecycle.transferring ||
          to == TransferLifecycle.paused ||
          to == TransferLifecycle.awaitingAuthorization,
    };
  }

  static bool _sameJson(Object? left, Object? right) =>
      jsonEncode(left) == jsonEncode(right);

  static bool _sameMap(Map<String, String> left, Map<String, String> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }
}
