import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/transfer_record.dart';
import '../models/owned_removal_record.dart';
import 'installation_paths.dart';

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
    await installArtifactIndex(db);
    await installRemovalJournal(db);
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

  static Future<void> installArtifactIndex(DatabaseExecutor db) =>
      db.execute('''CREATE INDEX IF NOT EXISTS idx_transfer_artifact
      ON transfer_records(artifact_key, destination_root, relative_path)''');

  static Future<void> installRemovalJournal(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS owned_removals (
      removal_id TEXT PRIMARY KEY, transfer_id TEXT NOT NULL,
      phase TEXT NOT NULL, revision INTEGER NOT NULL, issue TEXT,
      record_json TEXT NOT NULL
    )''');
    await db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS idx_active_removal
      ON owned_removals(transfer_id) WHERE phase NOT IN ('completed', 'retained') ''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_pending_removal
      ON owned_removals(phase, issue, removal_id)''');
  }

  static Future<void> installRemovalRetention(DatabaseExecutor db) async {
    // v19 included every non-completed audit record in the active index.
    await db.execute('DROP INDEX IF EXISTS idx_active_removal');
    await db.execute('''CREATE UNIQUE INDEX idx_active_removal
      ON owned_removals(transfer_id) WHERE phase NOT IN ('completed', 'retained')''');
  }
}

/// Durable state only: this class performs no filesystem operations and never
/// infers publication or completion from a filename's existence.
class TransferJournal {
  static const _digestHexLengths = {'md5': 32, 'sha1': 40, 'sha256': 64};
  final Future<Database> _database;
  TransferJournal(this._database);

  Future<OwnedRemovalRecord> beginRemoval(TransferRecord transfer,
      InstalledArtifact installation, {required String id,
      required String quarantinePath}) async {
    final intent = OwnedRemovalRecord(id: id, installation: installation,
        quarantinePath: quarantinePath);
    final db = await _database;
    return db.transaction((txn) async {
      _requireExactRecord(await _requiredTransfer(txn, transfer.id), transfer);
      if (transfer.lifecycle != TransferLifecycle.completed ||
          (transfer.publication?.method == PublicationMethod.copy && !transfer.stageRetired) ||
          quarantinePath == transfer.stagePath || installation.verifiedChecksums['sha256'] == null) {
        throw StateError('Removal requires a completed installation and retired transfer stage');
      }
      _requireMatchingInstallation(transfer, installation);
      await _requireInstalledOwner(txn, installation);
      if (await _pendingRemoval(txn, transfer.id)) throw StateError('Removal is already pending');
      await txn.insert('owned_removals', _removalValues(intent));
      return intent;
    });
  }

  Future<OwnedRemovalRecord?> removal(String id) async => _removal(await _database, id);

  Future<bool> hasPendingRemoval(String transferId) async =>
      _pendingRemoval(await _database, transferId);

  Future<OwnedRemovalRecord> advanceRemoval(OwnedRemovalRecord record,
      OwnedRemovalPhase phase) async {
    if (record.isTerminal || phase == OwnedRemovalPhase.completed || phase == OwnedRemovalPhase.retained ||
        phase.index != record.phase.index + 1 || record.issue != null) {
      throw StateError('Invalid removal transition');
    }
    final db = await _database;
    return db.transaction((txn) async {
      await _requireRemoval(txn, record);
      await _requireInstalledOwner(txn, record.installation);
      final next = record.next(phase: phase);
      await _updateRemoval(txn, next, record.revision);
      return next;
    });
  }

  Future<OwnedRemovalRecord> removalIssue(OwnedRemovalRecord record, String issue) async {
    if (record.isTerminal) throw StateError('Removal is terminal');
    final db = await _database;
    return db.transaction((txn) async {
      await _requireRemoval(txn, record);
      final next = record.next(issue: issue);
      await _updateRemoval(txn, next, record.revision);
      return next;
    });
  }

  /// Only after EXDEV and fresh native evidence that the public object is exact
  /// and private quarantine is absent. Preserve installed ownership and the
  /// failed attempt's audit; this is NOT a successful deletion.
  Future<void> retainUnmovedRemoval(OwnedRemovalRecord record) async {
    if (record.phase != OwnedRemovalPhase.intent || record.issue != null) {
      throw StateError('Only an unmoved intent can be retained');
    }
    final db = await _database;
    await db.transaction((txn) async {
      await _requireRemoval(txn, record);
      await _requireInstalledOwner(txn, record.installation);
      await _updateRemoval(txn, record.next(
          phase: OwnedRemovalPhase.retained, issue: 'cross_volume'), record.revision);
    });
  }

  /// Call only after native private unlink and parent fsync acknowledge the
  /// recorded deletion intent. Owner/transfer release and audit commit are atomic.
  Future<void> finishRemoval(OwnedRemovalRecord record) async {
    if (record.phase != OwnedRemovalPhase.deleting || record.issue != null) {
      throw StateError('Removal has no verified deletion intent');
    }
    final db = await _database;
    await db.transaction((txn) async {
      await _requireRemoval(txn, record);
      await _requireInstalledOwner(txn, record.installation);
      await txn.delete('installed_artifacts', where: 'installation_id = ?',
          whereArgs: [record.installation.id]);
      await txn.delete('transfer_target_owners', where: 'transfer_id = ?',
          whereArgs: [record.installation.transferId]);
      await txn.delete('transfer_records', where: 'transfer_id = ?',
          whereArgs: [record.installation.transferId]);
      await _updateRemoval(txn, record.next(phase: OwnedRemovalPhase.completed), record.revision);
    });
  }

  Stream<OwnedRemovalRecord> pendingRemovals({bool Function()? shouldContinue}) async* {
    final db = await _database;
    String after = '';
    while (shouldContinue?.call() ?? true) {
      final rows = await db.query('owned_removals', columns: ['removal_id', 'record_json'],
          where: "phase NOT IN ('completed', 'retained') AND issue IS NULL AND removal_id > ?",
          whereArgs: [after], orderBy: 'removal_id', limit: 128);
      if (rows.isEmpty) return;
      for (final row in rows) {
        if (!(shouldContinue?.call() ?? true)) return;
        yield OwnedRemovalRecord.fromJson((jsonDecode(row['record_json'] as String) as Map).cast<String, dynamic>());
      }
      after = rows.last['removal_id'] as String;
    }
  }

  static Future<OwnedRemovalRecord?> _removal(DatabaseExecutor db, String id) async {
    final rows = await db.query('owned_removals', columns: ['record_json'],
        where: 'removal_id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : OwnedRemovalRecord.fromJson(
        (jsonDecode(rows.single['record_json'] as String) as Map).cast<String, dynamic>());
  }

  static Future<bool> _pendingRemoval(DatabaseExecutor db, String transferId) async =>
      (await db.query('owned_removals', columns: ['removal_id'],
          where: "transfer_id = ? AND phase NOT IN ('completed', 'retained')", whereArgs: [transferId], limit: 1)).isNotEmpty;

  static Future<void> _requireRemoval(DatabaseExecutor db, OwnedRemovalRecord record) async {
    final current = await _removal(db, record.id);
    if (current == null || jsonEncode(current.toJson()) != jsonEncode(record.toJson())) {
      throw StateError('Removal evidence or revision changed');
    }
  }

  static Future<void> _requireInstalledOwner(DatabaseExecutor db, InstalledArtifact installation) async {
    final rows = await db.rawQuery('''SELECT i.record_json FROM installed_artifacts i
      JOIN transfer_target_owners o ON o.installation_id = i.installation_id
        AND o.transfer_id = i.transfer_id
      WHERE i.installation_id = ? AND i.transfer_id = ?
        AND o.destination_root = ? AND o.relative_path = ?''',
        [installation.id, installation.transferId, installation.destinationRoot, installation.relativePath]);
    if (rows.length != 1 || jsonEncode(InstalledArtifact.fromJson(
        (jsonDecode(rows.single['record_json'] as String) as Map).cast<String, dynamic>()).toJson()) !=
        jsonEncode(installation.toJson())) {
      throw StateError('Installed ownership changed');
    }
  }

  static Map<String, Object?> _removalValues(OwnedRemovalRecord record) => {
    'removal_id': record.id, 'transfer_id': record.installation.transferId,
    'phase': record.phase.name, 'revision': record.revision, 'issue': record.issue,
    'record_json': jsonEncode(record.toJson()),
  };

  static Future<void> _updateRemoval(DatabaseExecutor db, OwnedRemovalRecord record, int previous) async {
    if (await db.update('owned_removals', _removalValues(record),
        where: 'removal_id = ? AND revision = ?', whereArgs: [record.id, previous]) != 1) {
      throw StateError('Removal revision changed');
    }
  }

  /// Reserves the target and creates a new queued transfer in one transaction.
  Future<TransferRecord> create(TransferRecord record) async {
    return InstallationMutations.run(
        p.join(record.destinationRoot, record.relativePath),
        () => _create(record));
  }

  Future<TransferRecord> _create(TransferRecord record) async {
    if (record.revision != 0 ||
        record.lifecycle != TransferLifecycle.queued ||
        record.durableOffset != 0 ||
        record.stageIdentity != null ||
        record.publication != null ||
        record.stageRetired ||
        record.stageRetirementIssue != null ||
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
      if (hashesChanged && previous.verifiedChecksums.isNotEmpty) {
        throw StateError('Verified digests cannot change or disappear');
      }
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
      _requireStageCheckpoint(previous, record, hashesChanged: hashesChanged);
      _requirePublicationCheckpoint(previous, record);
      final next = record.copyWith(revision: record.revision + 1);
      await _updateTransfer(txn, next, expectedRevision: record.revision);
      return next;
    });
  }

  /// Resets legacy identity-null progress only. Owned stage/publication records
  /// require a separate durable reset protocol; forgetting them could orphan
  /// bytes after a crash. No file is touched by this journal.
  Future<TransferRecord> resetPartial(TransferRecord record) async {
    final db = await _database;
    return db.transaction((txn) async {
      final previous = await _requiredTransfer(txn, record.id);
      _requireExactRecord(previous, record);
      if (record.lifecycle != TransferLifecycle.paused &&
          record.lifecycle != TransferLifecycle.failed) {
        throw StateError('Partial reset requires a paused or failed transfer');
      }
      if (record.stageIdentity != null || record.publication != null) {
        throw StateError(
            'Owned bytes require an explicit durable reset protocol');
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

  /// Captures a native resume receipt after the owned private stage has been
  /// opened and its uncommitted tail trimmed to the journal's durable offset.
  /// This is not a generic checkpoint or reset: the native resume must pin the
  /// recorded object and finish before the caller writes new bytes. The existing
  /// identity/offset is the durable recovery intent. Only an unverified stage's
  /// timestamp can be rebound; verified stage evidence remains exact.
  Future<TransferRecord> resumeStageCheckpoint(
    TransferRecord record,
    NativeFileIdentity openedIdentity,
  ) async {
    final db = await _database;
    return db.transaction((txn) async {
      final previous = await _requiredTransfer(txn, record.id);
      _requireExactRecord(previous, record);
      if (record.lifecycle != TransferLifecycle.transferring &&
          record.lifecycle != TransferLifecycle.verifying) {
        throw StateError(
            'Native resume requires an active transfer or verification');
      }
      final stage = record.stageIdentity;
      if (stage == null || record.publication != null) {
        throw StateError('Native resume requires an owned unpublished stage');
      }
      if (stage.sizeBytes != record.durableOffset ||
          openedIdentity.sizeBytes != record.durableOffset ||
          !stage.sameObject(openedIdentity)) {
        throw StateError(
            'Native resume cannot change the stage object or durable offset');
      }
      if (record.verifiedChecksums.isNotEmpty &&
          !stage.matches(openedIdentity)) {
        throw StateError('Native resume cannot change verified stage evidence');
      }
      final next = record.copyWith(
        stageIdentity: openedIdentity,
        revision: record.revision + 1,
      );
      await _updateTransfer(txn, next, expectedRevision: record.revision);
      return next;
    });
  }

  /// Commits the exact installation manifest and `completed` lifecycle together.
  /// The caller must already have published the bytes and captured native file
  /// identity; this transaction makes only the durable ownership declaration.
  /// [checkCancellation] runs before writes and after all writes. A thrown
  /// cancellation rolls back the whole transaction. The final synchronous check
  /// is the commit linearization point: cancellation after it may truthfully
  /// return completed if the database commit succeeds.
  Future<TransferRecord> complete(
    TransferRecord record,
    InstalledArtifact installation, {
    void Function()? checkCancellation,
  }) async {
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

      checkCancellation?.call();
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
      checkCancellation?.call();
      return completed;
    });
  }

  Future<TransferRecord?> transfer(String id) async {
    final db = await _database;
    return _transfer(db, id);
  }

  /// One bounded offline pass over completed copy intents, independent of the
  /// visible queue (which deliberately omits completed downloads on restart).
  /// Filter optional JSON fields in Dart for older Android SQLite compatibility.
  Stream<TransferRecord> pendingStageRetirements(
      {int batchSize = 128, bool Function()? shouldContinue}) async* {
    if (batchSize < 1 || batchSize > 128) {
      throw ArgumentError.value(batchSize, 'batchSize', 'Expected 1..128');
    }
    if (!(shouldContinue?.call() ?? true)) return;
    final db = await _database;
    final last = await db.query('transfer_records',
        columns: ['transfer_id'],
        where: 'lifecycle = ?',
        whereArgs: ['completed'],
        orderBy: 'transfer_id DESC',
        limit: 1);
    if (last.isEmpty) return;
    final upper = last.single['transfer_id'] as String;
    String? after;
    while (true) {
      if (!(shouldContinue?.call() ?? true)) return;
      final rows = await db.query('transfer_records',
          columns: ['transfer_id', 'record_json'],
          where: 'lifecycle = ? AND transfer_id <= ?'
              '${after == null ? '' : ' AND transfer_id > ?'}',
          whereArgs: ['completed', upper, if (after != null) after],
          orderBy: 'transfer_id',
          limit: batchSize);
      if (rows.isEmpty) return;
      for (final row in rows) {
        if (!(shouldContinue?.call() ?? true)) return;
        final record = TransferRecord.fromJson(
            (jsonDecode(row['record_json'] as String) as Map)
                .cast<String, dynamic>());
        if (record.lifecycle == TransferLifecycle.completed &&
            record.publication?.method == PublicationMethod.copy &&
            !record.stageRetired) {
          yield record;
        }
      }
      after = rows.last['transfer_id'] as String;
      if (after == upper) return;
    }
  }

  /// Records post-commit cleanup without rewriting installed/download truth.
  /// A completed copy is the durable intent; native replay verifies or observes
  /// absence of that exact PRIVATE stage before this acknowledgement.
  Future<TransferRecord> stageRetirementResult(TransferRecord record,
      {String? issue}) async {
    final db = await _database;
    return db.transaction((txn) async {
      final previous = await _requiredTransfer(txn, record.id);
      _requireExactRecord(previous, record);
      if (record.lifecycle != TransferLifecycle.completed ||
          record.publication?.method != PublicationMethod.copy ||
          record.publication?.confirmed != true ||
          record.stageIdentity == null ||
          record.stageRetired) {
        throw StateError(
            'Stage retirement requires an unretired completed copy');
      }
      final rows = await txn.query('installed_artifacts',
          columns: ['record_json'],
          where: 'transfer_id = ?',
          whereArgs: [record.id],
          limit: 1);
      if (rows.isEmpty) {
        throw StateError('Stage retirement requires its installed owner');
      }
      _requireMatchingInstallation(
          record,
          InstalledArtifact.fromJson(
              (jsonDecode(rows.single['record_json'] as String) as Map)
                  .cast<String, dynamic>()));
      final next = record.copyWith(
          stageRetired: issue == null,
          stageRetirementIssue: issue,
          clearStageRetirementIssue: issue == null,
          revision: record.revision + 1);
      await _updateTransfer(txn, next, expectedRevision: record.revision);
      return next;
    });
  }

  Future<List<String>> destinationRoots() async {
    final db = await _database;
    final rows = await db.rawQuery(
        'SELECT DISTINCT destination_root FROM transfer_target_owners');
    return rows.map((r) => r['destination_root'] as String).toList();
  }

  /// Keyset-paged ownership and installation evidence from the same SQL read.
  /// No transfer history, payload bytes or all-library metadata is materialized.
  Stream<({TransferRecord transfer, InstalledArtifact? installation})>
      targetsInRoot(String root, {String? artifactKey}) async* {
    final db = await _database;
    String? after;
    while (true) {
      final rows = await db.rawQuery('''
        SELECT t.record_json AS transfer_json, i.record_json AS installation_json,
          o.relative_path AS cursor
        FROM transfer_target_owners o
        JOIN transfer_records t ${artifactKey == null ? '' : 'INDEXED BY idx_transfer_artifact'}
          ON t.transfer_id = o.transfer_id
        LEFT JOIN installed_artifacts i ON i.installation_id = o.installation_id
          AND i.transfer_id = o.transfer_id
        WHERE o.destination_root = ? ${after == null ? '' : 'AND o.relative_path > ?'}
          ${artifactKey == null ? '' : 'AND t.artifact_key = ? AND t.destination_root = ?'}
        ORDER BY o.relative_path LIMIT 128
      ''', [
        root,
        if (after != null) after,
        if (artifactKey != null) ...[artifactKey, root]
      ]);
      if (rows.isEmpty) return;
      for (final row in rows) {
        yield (
          transfer: TransferRecord.fromJson(
              (jsonDecode(row['transfer_json'] as String) as Map)
                  .cast<String, dynamic>()),
          installation: row['installation_json'] == null
              ? null
              : InstalledArtifact.fromJson(
                  (jsonDecode(row['installation_json'] as String) as Map)
                      .cast<String, dynamic>()),
        );
      }
      after = rows.last['cursor'] as String;
    }
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
        previous.stageRetired != proposed.stageRetired ||
        previous.stageRetirementIssue != proposed.stageRetirementIssue ||
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
    _requireVerifiedBytes(record);
    final publication = record.publication;
    if (publication == null ||
        !publication.confirmed ||
        publication.destinationIdentity == null ||
        !publication.sourceIdentity.matches(record.stageIdentity!) ||
        publication.destinationIdentity!.sizeBytes != record.durableOffset ||
        (publication.method == PublicationMethod.rename &&
            !publication.sourceIdentity
                .matches(publication.destinationIdentity!))) {
      throw StateError('Completion requires confirmed native publication');
    }
  }

  static void _requireVerifiedBytes(TransferRecord record) {
    final size = record.artifact.sizeBytes;
    if (size == null || record.durableOffset != size) {
      throw StateError('Verification requires all source bytes');
    }
    if (record.stageIdentity == null ||
        record.stageIdentity!.sizeBytes != size) {
      throw StateError('Verification requires exact owned stage evidence');
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
      throw StateError('Publication requires provider and local verification');
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
        record.publication?.destinationIdentity == null ||
        !installation.fileIdentity
            .matches(record.publication!.destinationIdentity!) ||
        !_sameJson(installation.artifact.toJson(), record.artifact.toJson()) ||
        !_sameMap(
          installation.verifiedChecksums,
          record.verifiedChecksums,
        )) {
      throw StateError('Installation does not match the verified transfer');
    }
  }

  static void _requireStageCheckpoint(
    TransferRecord previous,
    TransferRecord record, {
    required bool hashesChanged,
  }) {
    final before = previous.stageIdentity;
    final after = record.stageIdentity;
    if (before != null && after == null) {
      throw StateError('Stage ownership cannot disappear');
    }
    if (after != null) {
      if (after.sizeBytes != record.durableOffset) {
        throw StateError('Stage size must equal the durable offset');
      }
      if (before == null) {
        if (previous.durableOffset != 0 ||
            previous.verifiedChecksums.isNotEmpty ||
            previous.publication != null) {
          throw StateError('Legacy unowned progress cannot acquire ownership');
        }
      } else {
        if (!before.sameObject(after)) {
          throw StateError('Stage native object cannot change');
        }
        if ((previous.verifiedChecksums.isNotEmpty ||
                before.sizeBytes == after.sizeBytes) &&
            !before.matches(after)) {
          throw StateError(
              'Unwritten or verified stage evidence cannot change');
        }
      }
    }
    if ((record.durableOffset != previous.durableOffset || hashesChanged) &&
        after == null) {
      throw StateError('New progress requires native stage ownership');
    }
    if (record.lifecycle == TransferLifecycle.verifying &&
        (after == null ||
            record.artifact.sizeBytes == null ||
            record.durableOffset != record.artifact.sizeBytes)) {
      throw StateError('Verification requires a complete owned stage');
    }
    if (record.lifecycle == TransferLifecycle.transferring &&
        ((record.durableOffset > 0 && after == null) ||
            record.verifiedChecksums.isNotEmpty)) {
      throw StateError('Network writes require owned unverified progress');
    }
  }

  static void _requirePublicationCheckpoint(
    TransferRecord previous,
    TransferRecord record,
  ) {
    final before = previous.publication;
    final after = record.publication;
    if (before != null && after == null) {
      throw StateError('Publication intent cannot disappear');
    }
    if (record.lifecycle == TransferLifecycle.publishing && after == null) {
      throw StateError('Publishing requires a durable intent');
    }
    if (after == null) return;
    if (record.lifecycle != TransferLifecycle.publishing &&
        !_sameJson(before?.toJson(), after.toJson())) {
      throw StateError(
          'Publication progress requires the publishing lifecycle');
    }
    if (record.lifecycle == TransferLifecycle.queued ||
        record.lifecycle == TransferLifecycle.transferring ||
        record.lifecycle == TransferLifecycle.verifying) {
      throw StateError('Publication cannot return to network or stage writes');
    }
    _requireVerifiedBytes(record);
    if (!after.sourceIdentity.matches(record.stageIdentity!)) {
      throw StateError('Publication source must match the verified stage');
    }
    if (before == null) {
      _requireVerifiedBytes(previous);
      if (record.lifecycle != TransferLifecycle.publishing ||
          after.confirmed ||
          after.destinationIdentity != null) {
        throw StateError('Publication intent must precede destination changes');
      }
      return;
    }
    if (!before.sourceIdentity.matches(after.sourceIdentity)) {
      throw StateError('Publication source identity is immutable');
    }
    if (before.method != after.method &&
        !(before.method == PublicationMethod.rename &&
            after.method == PublicationMethod.copy &&
            !before.confirmed &&
            before.destinationIdentity == null &&
            !after.confirmed &&
            after.destinationIdentity == null)) {
      throw StateError('Only an untouched rename intent may fall back to copy');
    }
    if (before.confirmed &&
        (!after.confirmed ||
            after.destinationIdentity == null ||
            !before.destinationIdentity!.matches(after.destinationIdentity!))) {
      throw StateError('Confirmed publication evidence is immutable');
    }
    final destination = after.destinationIdentity;
    final previousDestination = before.destinationIdentity;
    if (previousDestination != null &&
        (destination == null ||
            !previousDestination.sameObject(destination) ||
            destination.sizeBytes < previousDestination.sizeBytes)) {
      throw StateError(
          'Publication destination cannot disappear, change or shrink');
    }
    if (previousDestination != null &&
        destination != null &&
        previousDestination.sizeBytes == destination.sizeBytes &&
        !previousDestination.matches(destination)) {
      throw StateError('Unwritten destination evidence cannot change');
    }
    if (destination != null) {
      if (destination.sizeBytes > after.sourceIdentity.sizeBytes) {
        throw StateError('Publication destination cannot exceed the source');
      }
      if (after.method == PublicationMethod.rename &&
          !after.sourceIdentity.matches(destination)) {
        throw StateError('Renamed destination must be the exact source object');
      }
      if (after.method == PublicationMethod.copy &&
          after.sourceIdentity.sameObject(destination)) {
        throw StateError('Copy destination must be distinct from its source');
      }
    }
    if (after.confirmed &&
        (destination == null ||
            destination.sizeBytes != after.sourceIdentity.sizeBytes)) {
      throw StateError('Confirmation requires the whole destination');
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
          to == TransferLifecycle.verifying ||
          to == TransferLifecycle.publishing ||
          to == TransferLifecycle.awaitingAuthorization ||
          to == TransferLifecycle.failed,
      TransferLifecycle.awaitingAuthorization =>
        to == TransferLifecycle.queued ||
            to == TransferLifecycle.transferring ||
            to == TransferLifecycle.verifying ||
            to == TransferLifecycle.publishing ||
            to == TransferLifecycle.paused ||
            to == TransferLifecycle.failed,
      TransferLifecycle.verifying => to == TransferLifecycle.publishing ||
          to == TransferLifecycle.awaitingAuthorization ||
          to == TransferLifecycle.paused ||
          to == TransferLifecycle.failed,
      TransferLifecycle.publishing => to == TransferLifecycle.paused ||
          to == TransferLifecycle.awaitingAuthorization ||
          to == TransferLifecycle.failed,
      TransferLifecycle.completed => false,
      TransferLifecycle.failed => to == TransferLifecycle.queued ||
          to == TransferLifecycle.transferring ||
          to == TransferLifecycle.verifying ||
          to == TransferLifecycle.publishing ||
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
