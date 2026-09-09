import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/library_identity.dart';
import '../../models/scraped_metadata.dart';
import '../library_store.dart';
import 'metadata_provider.dart';

class MetadataRefreshReport {
  final int id;
  final int generation;
  final String collectionGeneration;
  final String state;
  final int requested;
  final int rated;
  final Map<String, int> counts;
  final String? blockedStatus;
  const MetadataRefreshReport(
      {required this.id,
      required this.generation,
      required this.collectionGeneration,
      required this.state,
      required this.requested,
      required this.rated,
      required this.counts,
      this.blockedStatus});
}

class MetadataRefreshJobs {
  final Future<Database> _database;
  final DateTime Function() _now;
  Future<MetadataRefreshReport>? _active;
  CancelToken? _cancel;
  MetadataRefreshJobs(this._database, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  static Future<void> install(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS metadata_refresh_jobs (
      id INTEGER PRIMARY KEY AUTOINCREMENT, generation INTEGER NOT NULL UNIQUE,
      provider_id TEXT NOT NULL, collection_generation TEXT NOT NULL,
      state TEXT NOT NULL, requested INTEGER NOT NULL DEFAULT 0,
      blocked_status TEXT, not_before INTEGER
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS metadata_refresh_items (
      job_id INTEGER NOT NULL, edition_id TEXT NOT NULL,
      lookup_key TEXT NOT NULL, identity_key TEXT NOT NULL,
      request_json TEXT, status TEXT NOT NULL, rated INTEGER NOT NULL DEFAULT 0,
      candidates_json TEXT, PRIMARY KEY(job_id, edition_id)
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_metadata_refresh_pending
      ON metadata_refresh_items(job_id, status, edition_id)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_metadata_refresh_lookup
      ON metadata_refresh_items(job_id, lookup_key, status, edition_id)''');
    // One worker across job objects sharing this database, without a timer lease.
    await db
        .execute('''CREATE UNIQUE INDEX IF NOT EXISTS idx_metadata_one_worker
      ON metadata_refresh_jobs(state) WHERE state = 'running' ''');
    await db.execute('''CREATE TABLE IF NOT EXISTS metadata_provider_backoff (
      provider_id TEXT PRIMARY KEY, not_before INTEGER NOT NULL, reason TEXT NOT NULL
    )''');
  }

  /// Called once by database startup, never by a second live job runner.
  static Future<void> recoverInterrupted(DatabaseExecutor db) async {
    await db.update('metadata_refresh_jobs', {'state': 'paused'},
        where: 'state = ?', whereArgs: ['running']);
  }

  static Future<Map<String, Object?>?> _identity(
      DatabaseExecutor db, String editionId) async {
    final rows = await db.rawQuery('''SELECT g.record_json AS game_json,
      e.record_json AS edition_json FROM library_editions e
      JOIN library_game_identities g ON g.game_id = e.game_id
      WHERE e.edition_id = ? LIMIT 1''', [editionId]);
    return rows.isEmpty ? null : rows.single;
  }

  Future<MetadataRefreshReport> create(
      {required String providerId,
      required String collectionGeneration,
      required Iterable<String> editionIds}) async {
    if (providerId.trim().isEmpty || collectionGeneration.trim().isEmpty) {
      throw ArgumentError('Provider and collection generation are required');
    }
    final db = await _database;
    final id = await db.transaction((txn) async {
      final maximum = await txn.rawQuery('''SELECT MAX(value) AS maximum FROM (
        SELECT MAX(generation) AS value FROM metadata_refresh_jobs
        UNION ALL SELECT MAX(generation_id) FROM library_metadata)''');
      final generation = ((maximum.single['maximum'] as int?) ?? 0) + 1;
      final id = await txn.insert('metadata_refresh_jobs', {
        'generation': generation,
        'provider_id': providerId,
        'collection_generation': collectionGeneration,
        'state': 'paused',
      });
      // Consume explicit membership incrementally; never discover the collection
      // by scanning historical metadata or load every record into a Dart list.
      for (final editionId in editionIds) {
        final row = await _identity(txn, editionId);
        if (row == null) {
          throw StateError('Unknown edition in refresh snapshot');
        }
        final game =
            GameIdentity.fromJson(jsonDecode(row['game_json'] as String));
        final edition =
            EditionIdentity.fromJson(jsonDecode(row['edition_json'] as String));
        String? baseProviderId;
        if (game.baseGameId != null) {
          final base = await txn.query('library_game_identities',
              columns: ['record_json'],
              where: 'game_id = ?',
              whereArgs: [game.baseGameId],
              limit: 1);
          if (base.isNotEmpty) {
            final identity = GameIdentity.fromJson(
                jsonDecode(base.single['record_json'] as String));
            if ({
              IdentityMatchStatus.matched,
              IdentityMatchStatus.manuallyMatched
            }.contains(identity.matchStatus)) {
              baseProviderId = identity.providerIds[providerId];
            }
          }
        }
        final request = game.platformId == null
            ? null
            : MetadataLookupRequest(
                gameId: game.id,
                editionId: edition.id,
                platformId: game.platformId!,
                title: game.title,
                verifiedProviderGameId: {
                  IdentityMatchStatus.matched,
                  IdentityMatchStatus.manuallyMatched
                }.contains(game.matchStatus)
                    ? game.providerIds[providerId]
                    : null,
                baseProviderGameId: baseProviderId,
                contentTags: edition.tags,
                region:
                    edition.regions.length == 1 ? edition.regions.single : null,
                language: edition.languages.length == 1
                    ? edition.languages.single
                    : null,
                revision: edition.revision,
                refreshGeneration: generation);
        final keyData = request?.toJson()
          ?..remove('editionId')
          ..remove('refreshGeneration');
        // Release/patch evidence must also match even if the provider has no
        // dedicated request field for it. Disc containers are not ROM hashes.
        final editionEvidence = edition.toJson()
          ..remove('id')
          ..remove('members');
        await txn.insert(
            'metadata_refresh_items',
            {
              'job_id': id,
              'edition_id': editionId,
              'lookup_key': sha256
                  .convert(utf8.encode(
                      jsonEncode(_canonical([keyData, editionEvidence]))))
                  .toString(),
              'identity_key': LibraryStore.metadataIdentity(row),
              'request_json':
                  request == null ? null : jsonEncode(request.toJson()),
              'status': request == null ? 'unsupportedPlatform' : 'pending',
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      return id;
    });
    return report(id);
  }

  static Object? _canonical(Object? value) {
    if (value is Map<String, dynamic>) {
      final keys = value.keys.toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  Future<MetadataRefreshReport> report(int id) async {
    final db = await _database;
    return db.transaction((txn) async {
      final row = await _job(txn, id);
      final totals = await txn.rawQuery('''SELECT status, COUNT(*) AS count,
        SUM(rated) AS rated FROM metadata_refresh_items WHERE job_id = ? GROUP BY status''',
          [id]);
      return MetadataRefreshReport(
          id: id,
          generation: row['generation'] as int,
          collectionGeneration: row['collection_generation'] as String,
          state: row['state'] as String,
          requested: row['requested'] as int,
          rated: totals.fold(0, (sum, r) => sum + (r['rated'] as int)),
          counts: Map.unmodifiable({
            for (final r in totals) r['status'] as String: r['count'] as int
          }),
          blockedStatus: row['blocked_status'] as String?);
    });
  }

  static Future<Map<String, Object?>> _job(DatabaseExecutor db, int id) async {
    final rows = await db.query('metadata_refresh_jobs',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw StateError('Unknown metadata refresh job');
    return rows.single;
  }

  Future<MetadataRefreshReport> run(int id, MetadataProvider provider) {
    if (_active != null) {
      throw StateError('A metadata refresh is already active');
    }
    final cancel = CancelToken();
    _cancel = cancel;
    return _active = _run(id, provider, cancel).whenComplete(() {
      _active = null;
      _cancel = null;
    });
  }

  Future<void> pause() async {
    _cancel?.cancel('Metadata refresh paused');
    await _active;
  }

  Future<MetadataRefreshReport> _run(
      int id, MetadataProvider provider, CancelToken cancel) async {
    final db = await _database;
    final claimed = await db.transaction((txn) async {
      final job = await _job(txn, id);
      if (job['provider_id'] != provider.providerId) {
        throw StateError('Wrong metadata provider');
      }
      final notBefore = job['not_before'] as int?;
      if (job['state'] == 'completed' ||
          (notBefore != null && _now().millisecondsSinceEpoch < notBefore)) {
        return false;
      }
      if (job['state'] == 'running') throw StateError('Job is already running');
      final cooldown = await txn.query('metadata_provider_backoff',
          where: 'provider_id = ?', whereArgs: [provider.providerId], limit: 1);
      if (cooldown.isNotEmpty &&
          _now().millisecondsSinceEpoch <
              (cooldown.single['not_before'] as int)) {
        await txn.update(
            'metadata_refresh_jobs',
            {
              'state': 'blocked',
              'blocked_status': cooldown.single['reason'],
              'not_before': cooldown.single['not_before']
            },
            where: 'id = ?',
            whereArgs: [id]);
        return false;
      }
      await txn.update('metadata_refresh_jobs',
          {'state': 'running', 'blocked_status': null, 'not_before': null},
          where: 'id = ?', whereArgs: [id]);
      return true;
    });
    if (!claimed) return report(id);
    try {
      while (!cancel.isCancelled) {
        final next = await db.query('metadata_refresh_items',
            where: 'job_id = ? AND status = ?',
            whereArgs: [id, 'pending'],
            orderBy: 'edition_id',
            limit: 1);
        if (next.isEmpty) {
          await _setState(db, id, 'completed');
          return await report(id);
        }
        final item = next.single;
        final request = MetadataLookupRequest.fromJson(
            jsonDecode(item['request_json'] as String));
        final current = await _identity(db, request.editionId);
        if (current == null ||
            LibraryStore.metadataIdentity(current) != item['identity_key']) {
          await db.update(
              'metadata_refresh_items', {'status': 'identityChanged'},
              where: 'job_id = ? AND edition_id = ?',
              whereArgs: [id, request.editionId]);
          continue;
        }
        if (cancel.isCancelled) break;
        await db.rawUpdate(
            'UPDATE metadata_refresh_jobs SET requested = requested + 1 WHERE id = ?',
            [id]);
        if (cancel.isCancelled) break;
        final result = await provider.lookup(request, cancelToken: cancel);
        if (cancel.isCancelled ||
            result.status == MetadataLookupStatus.cancelled) {
          break;
        }
        if (_blocking.contains(result.status)) {
          await _block(db, id, result.status, result.retryAfter);
          return await report(id);
        }
        await _commitResult(
            db, id, item, request, result, provider.providerId, cancel);
        if (cancel.isCancelled) break;
        final quota = result.quota;
        if ((quota?.requestsToday != null &&
                quota?.maxRequestsPerDay != null &&
                quota!.requestsToday! >= quota.maxRequestsPerDay!) ||
            (quota?.unmatchedToday != null &&
                quota?.maxUnmatchedPerDay != null &&
                quota!.unmatchedToday! >= quota.maxUnmatchedPerDay!)) {
          final pending = await db.query('metadata_refresh_items',
              columns: ['edition_id'],
              where: 'job_id = ? AND status = ?',
              whereArgs: [id, 'pending'],
              limit: 1);
          if (pending.isNotEmpty) {
            await _block(
                db, id, MetadataLookupStatus.quotaExceeded, result.retryAfter);
            return await report(id);
          }
        }
      }
      await _setState(db, id, 'paused');
    } on _RefreshCommitCancelled {
      await _setState(db, id, 'paused');
    } catch (_) {
      // Do not persist raw provider exceptions or erase already committed data.
      await _setState(db, id, 'paused');
      rethrow;
    }
    return report(id);
  }

  static const _blocking = {
    MetadataLookupStatus.setupRequired,
    MetadataLookupStatus.authenticationRequired,
    MetadataLookupStatus.developerAccessRequired,
    MetadataLookupStatus.quotaExceeded,
    MetadataLookupStatus.throttled,
    MetadataLookupStatus.unavailable
  };

  Future<void> _block(Database db, int id, MetadataLookupStatus status,
      Duration? retryAfter) async {
    await db.transaction((txn) async {
      final notBefore = retryAfter == null
          ? null
          : _now().add(retryAfter).millisecondsSinceEpoch;
      await txn.update(
          'metadata_refresh_jobs',
          {
            'state': 'blocked',
            'blocked_status': status.name,
            'not_before': notBefore
          },
          where: 'id = ?',
          whereArgs: [id]);
      if (notBefore != null) {
        final job = await _job(txn, id);
        await txn.insert(
            'metadata_provider_backoff',
            {
              'provider_id': job['provider_id'],
              'not_before': notBefore,
              'reason': status.name
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  static Future<void> _setState(Database db, int id, String state,
      {String? blockedStatus, int? notBefore}) async {
    await db.update(
        'metadata_refresh_jobs',
        {
          'state': state,
          'blocked_status': blockedStatus,
          'not_before': notBefore
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  Future<void> _commitResult(
      Database db,
      int id,
      Map<String, Object?> item,
      MetadataLookupRequest request,
      MetadataLookupResult result,
      String providerId,
      CancelToken cancel) async {
    final record = result.record;
    final valid = result.status != MetadataLookupStatus.matched ||
        (record != null &&
            record.gameId == request.gameId &&
            record.editionId == request.editionId &&
            record.platformId == request.platformId &&
            record.providerId == providerId &&
            record.refreshGeneration == request.refreshGeneration &&
            LibraryStore.hasConsistentProvenance(record) &&
            (request.verifiedProviderGameId == null ||
                record.providerGameId == request.verifiedProviderGameId) &&
            (request.baseProviderGameId == null ||
                record.providerGameId != request.baseProviderGameId));
    final status = valid ? result.status.name : 'invalidResponse';
    final store = LibraryStore(_database);
    // Each bounded page commits its metadata and item results together. A crash
    // leaves the remaining page pending, never a done item with missing metadata.
    while (!cancel.isCancelled) {
      final count = await db.transaction((txn) async {
        if (cancel.isCancelled) return 0;
        final rows = await txn.query('metadata_refresh_items',
            where: 'job_id = ? AND lookup_key = ? AND status = ?',
            whereArgs: [id, item['lookup_key'], 'pending'],
            orderBy: 'edition_id',
            limit: 128);
        for (final target in rows) {
          if (cancel.isCancelled) throw const _RefreshCommitCancelled();
          var outcome = status;
          var rated = 0;
          final editionId = target['edition_id'] as String;
          final identity = await _identity(txn, editionId);
          if (identity == null ||
              LibraryStore.metadataIdentity(identity) !=
                  target['identity_key']) {
            outcome = 'identityChanged';
          } else if (outcome == 'matched') {
            final previous = await txn.query('library_metadata',
                columns: ['generation_id'],
                where: 'edition_id = ? AND provider_id = ?',
                whereArgs: [editionId, providerId],
                limit: 1);
            if (previous.isNotEmpty &&
                (previous.single['generation_id'] as int) >
                    request.refreshGeneration) {
              outcome = 'superseded';
            } else {
              final copy = MetadataRecord.fromJson(
                  {...record!.toJson(), 'editionId': editionId});
              await store.putMetadata(copy, transaction: txn);
              rated = copy.ratings.isEmpty ? 0 : 1;
            }
          }
          await txn.update(
              'metadata_refresh_items',
              {
                'status': outcome,
                'rated': rated,
                'candidates_json': jsonEncode(result.candidates
                    .map((candidate) => {
                          'providerGameId': candidate.providerGameId,
                          'platformId': candidate.platformId,
                          'titles': candidate.titles
                              .map((title) => title.toJson())
                              .toList(),
                          'titleMatched': candidate.titleMatched,
                          'evidence': candidate.evidence,
                        })
                    .toList())
              },
              where: 'job_id = ? AND edition_id = ?',
              whereArgs: [id, editionId]);
        }
        if (cancel.isCancelled) throw const _RefreshCommitCancelled();
        return rows.length;
      });
      if (count < 128) break;
    }
  }
}

class _RefreshCommitCancelled implements Exception {
  const _RefreshCommitCancelled();
}
