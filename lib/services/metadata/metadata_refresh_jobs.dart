import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/library_identity.dart';
import '../../models/scraped_metadata.dart';
import '../drive/drive_api.dart';
import '../drive/drive_media.dart';
import '../library_store.dart';
import 'effective_overall_rating.dart';
import 'metadata_artwork_cache.dart';
import 'metadata_provider.dart';
import 'shared_metadata_store.dart';

/// Display-only provider observation, distinct from reserved local API budget.
class MetadataQuotaObservation {
  final MetadataQuota quota;
  final DateTime observedAt;
  final int? reservedRemaining;
  const MetadataQuotaObservation(this.quota, this.observedAt,
      {this.reservedRemaining});
  int? get remaining =>
      quota.maxRequestsPerDay == null || quota.requestsToday == null
          ? null
          : (quota.maxRequestsPerDay! - quota.requestsToday!)
              .clamp(0, quota.maxRequestsPerDay!);
  int? get unmatchedRemaining =>
      quota.maxUnmatchedPerDay == null || quota.unmatchedToday == null
          ? null
          : (quota.maxUnmatchedPerDay! - quota.unmatchedToday!)
              .clamp(0, quota.maxUnmatchedPerDay!);
}

/// One most-recent result only. Candidates remain unverified display context.
class MetadataProcessedGame {
  final int jobId;
  final String providerId, editionId, title, platformId;
  final MetadataLookupStatus status;
  final String? candidateTitle;
  final MetadataMedia? previewMedia;
  final Uint8List? coverBytes;
  final List<MetadataText> previewDescriptions;
  const MetadataProcessedGame(
      {required this.jobId,
      required this.providerId,
      required this.editionId,
      required this.title,
      required this.platformId,
      required this.status,
      this.candidateTitle,
      this.previewMedia,
      this.coverBytes,
      this.previewDescriptions = const []});
}

class MetadataRefreshReport {
  final int id;
  final int generation;
  final String collectionGeneration;
  final String state;
  final int requested;
  final int rated;
  final Map<String, int> counts;
  final String? blockedStatus;
  final DateTime? notBefore;
  final String kind;
  final String providerId;
  final MetadataQuotaObservation? quotaObservation;
  final MetadataProcessedGame? lastProcessed;
  const MetadataRefreshReport(
      {required this.id,
      required this.generation,
      required this.collectionGeneration,
      required this.state,
      required this.requested,
      required this.rated,
      required this.counts,
      this.blockedStatus,
      this.notBefore,
      this.kind = 'metadata',
      this.providerId = '',
      this.quotaObservation,
      this.lastProcessed});
}

class MetadataReviewItem {
  final int jobId;
  final String editionId;
  final String status;
  final List<MetadataLookupCandidate> candidates;
  final MetadataLookupRequest? request;
  final bool identityCurrent;
  final List<String> artifactLabels;
  const MetadataReviewItem(
      {required this.jobId,
      required this.editionId,
      required this.status,
      required this.candidates,
      this.request,
      this.identityCurrent = true,
      this.artifactLabels = const []});
}

class MetadataRefreshJobs {
  final Future<Database> _database;
  final Future<SharedMetadataStore?>? _sharedStore;
  final Future<Uint8List?> Function(RemoteArtifact, String, CancelToken)?
      _readRomHeader;
  final Future<MetadataRomIdentifier?> Function(
      RemoteArtifact, String, CancelToken)? _readArchiveIdentifier;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _schedule;
  Future<MetadataRefreshReport>? _active;
  CancelToken? _cancel;
  MetadataProcessedGame? _lastProcessed;
  MetadataRefreshJobs(this._database,
      {DateTime Function()? now,
      Future<SharedMetadataStore?>? sharedStore,
      Future<Uint8List?> Function(RemoteArtifact, String, CancelToken)?
          readRomHeader,
      Future<MetadataRomIdentifier?> Function(
              RemoteArtifact, String, CancelToken)?
          readArchiveIdentifier,
      Timer Function(Duration, void Function())? schedule})
      : _sharedStore = sharedStore,
        _readRomHeader = readRomHeader,
        _readArchiveIdentifier = readArchiveIdentifier,
        _now = now ?? DateTime.now,
        _schedule = schedule ?? Timer.new;

  static Future<void> install(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS metadata_refresh_jobs (
      id INTEGER PRIMARY KEY AUTOINCREMENT, generation INTEGER NOT NULL UNIQUE,
      provider_id TEXT NOT NULL, collection_generation TEXT NOT NULL,
      state TEXT NOT NULL, requested INTEGER NOT NULL DEFAULT 0,
      blocked_status TEXT, not_before INTEGER, is_artwork INTEGER NOT NULL DEFAULT 0
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
    await installRatingFreshnessIndex(db);
    // One worker across job objects sharing this database, without a timer lease.
    await db
        .execute('''CREATE UNIQUE INDEX IF NOT EXISTS idx_metadata_one_worker
      ON metadata_refresh_jobs(state) WHERE state = 'running' ''');
    await db.execute('''CREATE TABLE IF NOT EXISTS metadata_provider_backoff (
      provider_id TEXT PRIMARY KEY, not_before INTEGER NOT NULL, reason TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS metadata_provider_limits (
      provider_id TEXT PRIMARY KEY, requests_per_minute INTEGER,
      next_allowed_at INTEGER NOT NULL,
      max_threads INTEGER,
      quota_exhausted INTEGER NOT NULL DEFAULT 0, remaining_requests INTEGER
    )''');
    final jobColumns =
        await db.rawQuery('PRAGMA table_info(metadata_refresh_jobs)');
    if (!jobColumns.any((r) => r['name'] == 'is_artwork')) {
      await db.execute(
          'ALTER TABLE metadata_refresh_jobs ADD COLUMN is_artwork INTEGER NOT NULL DEFAULT 0');
    }
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_metadata_saved_jobs
      ON metadata_refresh_jobs(provider_id, is_artwork, id DESC)''');
    await installMatchReviewMode(db);
    await installProgressFeedback(db);
    final limitColumns =
        await db.rawQuery('PRAGMA table_info(metadata_provider_limits)');
    if (!limitColumns.any((r) => r['name'] == 'remaining_requests')) {
      await db.execute(
          'ALTER TABLE metadata_provider_limits ADD COLUMN remaining_requests INTEGER');
    }
    await db.execute('''CREATE TABLE IF NOT EXISTS metadata_artwork_items (
      job_id INTEGER NOT NULL, edition_id TEXT NOT NULL, media_key TEXT NOT NULL,
      identity_key TEXT NOT NULL, metadata_generation INTEGER NOT NULL,
      media_json TEXT NOT NULL, status TEXT NOT NULL,
      PRIMARY KEY(job_id, edition_id, media_key)
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_artwork_pending
      ON metadata_artwork_items(job_id, status, edition_id, media_key)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_artwork_coalescing
      ON metadata_artwork_items(job_id, media_key, status, edition_id)''');
    await MetadataArtworkCache.install(db);
    await installArtworkLinks(db);
  }

  /// Additive v35 display evidence; existing budget and saved jobs are untouched.
  static Future<void> installProgressFeedback(DatabaseExecutor db) async {
    final columns =
        await db.rawQuery('PRAGMA table_info(metadata_provider_limits)');
    for (final column in const {
      'quota_json': 'TEXT',
      'quota_observed_at': 'INTEGER'
    }.entries) {
      if (!columns.any((r) => r['name'] == column.key)) {
        await db.execute(
            'ALTER TABLE metadata_provider_limits ADD COLUMN ${column.key} ${column.value}');
      }
    }
  }

  static Future<MetadataQuotaObservation?> _quotaObservation(
      DatabaseExecutor db, String providerId) async {
    final rows = await db.query('metadata_provider_limits',
        where: 'provider_id = ?', whereArgs: [providerId], limit: 1);
    if (rows.isEmpty ||
        rows.single['quota_json'] == null ||
        rows.single['quota_observed_at'] == null) {
      return null;
    }
    try {
      final value = jsonDecode(rows.single['quota_json'] as String)
          as Map<String, dynamic>;
      int? counter(String key) {
        final v = value[key];
        if (v != null && (v is! int || v < 0)) {
          throw const FormatException('Invalid display quota');
        }
        return v as int?;
      }

      return MetadataQuotaObservation(
          MetadataQuota(
              requestsToday: counter('requestsToday'),
              maxRequestsPerDay: counter('maxRequestsPerDay'),
              unmatchedToday: counter('unmatchedToday'),
              maxUnmatchedPerDay: counter('maxUnmatchedPerDay')),
          DateTime.fromMillisecondsSinceEpoch(
              rows.single['quota_observed_at'] as int,
              isUtc: true),
          reservedRemaining: rows.single['remaining_requests'] as int?);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> clearQuotaObservation(String providerId) async {
    final db = await _database;
    await db.update('metadata_provider_limits',
        {'quota_json': null, 'quota_observed_at': null},
        where: 'provider_id = ?', whereArgs: [providerId]);
  }

  /// Additive v34 relationship: restore image work without re-scraping games.
  static Future<void> installArtworkLinks(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS metadata_artwork_jobs (
      metadata_job_id INTEGER PRIMARY KEY, artwork_job_id INTEGER NOT NULL UNIQUE
    )''');

  /// Exact edition lookup for current score-generation checks, not a scan of
  /// historical jobs for every card. Installed additively by the v27 upgrade.
  static Future<void> installRatingFreshnessIndex(DatabaseExecutor db) =>
      db.execute('''CREATE INDEX IF NOT EXISTS idx_metadata_refresh_edition
        ON metadata_refresh_items(edition_id, job_id)''');

  /// Additive v32 migration: retain all jobs, facts and existing refresh modes.
  static Future<void> installMatchReviewMode(DatabaseExecutor db) async {
    final columns =
        await db.rawQuery('PRAGMA table_info(metadata_refresh_jobs)');
    if (!columns.any((r) => r['name'] == 'is_match_review')) {
      await db.execute('ALTER TABLE metadata_refresh_jobs '
          'ADD COLUMN is_match_review INTEGER NOT NULL DEFAULT 0');
    }
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
    return rows.isEmpty ||
            !await LibraryStore.isCurrentCatalogueIdentity(db, rows.single)
        ? null
        : rows.single;
  }

  Future<MetadataRefreshReport> create(
          {required String providerId,
          required String collectionGeneration,
          required Iterable<String> editionIds}) =>
      _create(
          providerId: providerId,
          collectionGeneration: collectionGeneration,
          editions: (_) => Stream.fromIterable(editionIds));

  /// Full, system and individual refreshes all snapshot the committed normal
  /// catalogue. Capture and job publication share one database transaction;
  /// concurrent source changes cannot produce half-old, half-new membership.
  Future<MetadataRefreshReport> createFromCatalogue(
      {required String providerId, String? systemSlug, int? cacheRowId}) {
    if (systemSlug?.trim().isEmpty == true ||
        (cacheRowId != null && cacheRowId < 1)) {
      throw ArgumentError('Catalogue scope is invalid');
    }
    return _create(
        providerId: providerId,
        editions: (txn) => LibraryStore.catalogueEditions(txn,
            systemSlug: systemSlug, cacheRowId: cacheRowId));
  }

  /// Reconsider only the exact edition shown in details. Keep its saved identity
  /// and facts until explicit review; do not reuse the disputed lookup evidence.
  Future<MetadataRefreshReport> createMatchReview(
      {required String providerId,
      required int cacheRowId,
      required String editionId}) {
    if (cacheRowId < 1 || editionId.trim().isEmpty) {
      throw ArgumentError('An exact current game is required');
    }
    return _create(
        providerId: providerId,
        matchReview: true,
        editions: (txn) async* {
          final current =
              await LibraryStore.cachedCatalogueEditionId(txn, cacheRowId);
          if (current != editionId) {
            throw StateError('The selected catalogue edition changed');
          }
          yield editionId;
        });
  }

  static const _retryable = {
    'unmatched',
    'invalidRequest',
    'invalidResponse',
    'unsupportedPlatform',
    'identityChanged'
  };

  /// Explicit fresh artwork snapshot from current owned metadata. This never
  /// scrapes titles, imports legacy covers or enumerates installation residency.
  Future<MetadataRefreshReport> createArtwork(
          {required String providerId,
          required String collectionGeneration,
          required Iterable<String> editionIds,
          Set<String>? mediaKeys}) =>
      _createArtwork(
          providerId: providerId,
          collectionGeneration: collectionGeneration,
          editions: (_) => Stream.fromIterable(editionIds),
          mediaKeys: mediaKeys);

  Future<MetadataRefreshReport?> artworkForMetadata(int id) async {
    final db = await _database;
    final links = await db.query('metadata_artwork_jobs',
        where: 'metadata_job_id = ?', whereArgs: [id], limit: 1);
    return links.isEmpty ? null : report(links.single['artwork_job_id'] as int);
  }

  /// Capture only successfully published members of this exact refresh. Both
  /// the child job and its link commit together; repeat/resume reuses that job.
  Future<MetadataRefreshReport> ensureArtworkForMetadata(int id) async {
    final db = await _database;
    final parent = await _job(db, id);
    if (parent['is_artwork'] == 1 || parent['state'] != 'completed') {
      throw StateError('Artwork follows a completed metadata snapshot');
    }
    return _createArtwork(
        providerId: parent['provider_id'] as String,
        collectionGeneration: parent['collection_generation'] as String,
        metadataJobId: id,
        metadataGeneration: parent['generation'] as int,
        editions: (txn) async* {
          var cursor = '';
          while (true) {
            final rows = await txn.query('metadata_refresh_items',
                columns: ['edition_id'],
                where: 'job_id = ? AND status = ? AND edition_id > ?',
                whereArgs: [id, 'matched', cursor],
                orderBy: 'edition_id',
                limit: 128);
            if (rows.isEmpty) break;
            for (final row in rows) {
              yield row['edition_id'] as String;
            }
            cursor = rows.last['edition_id'] as String;
          }
        });
  }

  /// Explicit image retry snapshots only failed selectors; successful image
  /// publications and the completed metadata request remain untouched.
  Future<MetadataRefreshReport> retryArtworkForMetadata(int id) async {
    final parent = await report(id);
    final images = await artworkForMetadata(id);
    if (parent.kind != 'metadata' ||
        parent.state != 'completed' ||
        images == null) {
      throw StateError('Artwork retry requires completed linked metadata');
    }
    return _createArtwork(
        providerId: parent.providerId,
        collectionGeneration: parent.collectionGeneration,
        metadataJobId: id,
        metadataGeneration: parent.generation,
        retryArtworkJobId: images.id,
        editions: (txn) async* {
          var cursor = '';
          while (true) {
            final rows = await txn.rawQuery('''SELECT DISTINCT edition_id
              FROM metadata_artwork_items WHERE job_id = ? AND edition_id > ?
              AND status IN (${List.filled(_retryable.length, '?').join(',')})
              ORDER BY edition_id LIMIT 128''',
                [images.id, cursor, ..._retryable]);
            if (rows.isEmpty) break;
            for (final row in rows) {
              yield row['edition_id'] as String;
            }
            cursor = rows.last['edition_id'] as String;
          }
        });
  }

  Future<MetadataRefreshReport> _createArtwork(
      {required String providerId,
      required String collectionGeneration,
      required Stream<String> Function(DatabaseExecutor) editions,
      Set<String>? mediaKeys,
      int? metadataJobId,
      int? metadataGeneration,
      int? retryArtworkJobId}) async {
    if (providerId.trim().isEmpty || collectionGeneration.trim().isEmpty) {
      throw ArgumentError('Artwork scope is required');
    }
    final db = await _database;
    final sharedMaximum = await (await _sharedStore)?.maximumGeneration() ?? 0;
    final id = await db.transaction((txn) async {
      if (metadataJobId != null) {
        final links = await txn.query('metadata_artwork_jobs',
            where: 'metadata_job_id = ?', whereArgs: [metadataJobId], limit: 1);
        if (retryArtworkJobId == null && links.isNotEmpty) {
          return links.single['artwork_job_id'] as int;
        }
        if (retryArtworkJobId != null &&
            (links.isEmpty ||
                links.single['artwork_job_id'] != retryArtworkJobId ||
                (await _job(txn, retryArtworkJobId))['state'] == 'running')) {
          throw StateError('Finish the current artwork job before retrying');
        }
      }
      final maximum = await txn.rawQuery('''SELECT MAX(value) AS maximum FROM (
        SELECT MAX(generation) AS value FROM metadata_refresh_jobs
        UNION ALL SELECT MAX(generation_id) FROM library_metadata)''');
      final privateMaximum = (maximum.single['maximum'] as int?) ?? 0;
      final id = await txn.insert('metadata_refresh_jobs', {
        'generation':
            (privateMaximum > sharedMaximum ? privateMaximum : sharedMaximum) +
                1,
        'provider_id': providerId,
        'collection_generation': collectionGeneration,
        'state': 'paused',
        'is_artwork': 1,
      });
      await for (final editionId in editions(txn)) {
        final identity = await _identity(txn, editionId);
        final rows = await txn.query('library_metadata',
            where: 'edition_id = ? AND provider_id = ?',
            whereArgs: [editionId, providerId],
            limit: 1);
        if (identity == null ||
            rows.isEmpty ||
            rows.single['identity_key'] !=
                LibraryStore.metadataIdentity(identity,
                    providerId: providerId)) {
          if (metadataJobId != null) continue;
          throw StateError('Artwork requires current matched metadata');
        }
        final record = MetadataRecord.fromJson(
            jsonDecode(rows.single['record_json'] as String));
        if (metadataGeneration != null &&
            record.refreshGeneration != metadataGeneration) {
          continue;
        }
        for (final media in metadataJobId == null
            ? record.media
            : MetadataArtworkCache.displayMedia(record)) {
          final mediaKey = MetadataArtworkCache.key(media);
          if (mediaKeys != null && !mediaKeys.contains(mediaKey)) continue;
          if (retryArtworkJobId != null) {
            final failed = await txn.query('metadata_artwork_items',
                columns: ['status'],
                where: 'job_id = ? AND edition_id = ? AND media_key = ?',
                whereArgs: [retryArtworkJobId, editionId, mediaKey],
                limit: 1);
            if (failed.isEmpty ||
                !_retryable.contains(failed.single['status'])) {
              continue;
            }
          }
          await txn.insert(
              'metadata_artwork_items',
              {
                'job_id': id,
                'edition_id': editionId,
                'media_key': mediaKey,
                'identity_key': rows.single['identity_key'],
                'metadata_generation': record.refreshGeneration,
                'media_json': jsonEncode(media.toJson()),
                'status': 'pending',
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
      if (metadataJobId != null) {
        if (retryArtworkJobId == null) {
          await txn.insert('metadata_artwork_jobs',
              {'metadata_job_id': metadataJobId, 'artwork_job_id': id});
        } else {
          await txn.update('metadata_artwork_jobs', {'artwork_job_id': id},
              where: 'metadata_job_id = ?', whereArgs: [metadataJobId]);
        }
      }
      return id;
    });
    return report(id);
  }

  static Future<bool> _currentArtwork(
      DatabaseExecutor db, Map<String, Object?> item, String providerId) async {
    final identity = await _identity(db, item['edition_id'] as String);
    if (identity == null ||
        LibraryStore.metadataIdentity(identity, providerId: providerId) !=
            item['identity_key']) {
      return false;
    }
    final records = await db.query('library_metadata',
        columns: ['generation_id', 'identity_key', 'record_json'],
        where: 'edition_id = ? AND provider_id = ?',
        whereArgs: [item['edition_id'], providerId],
        limit: 1);
    if (records.isEmpty ||
        records.single['generation_id'] != item['metadata_generation'] ||
        records.single['identity_key'] != item['identity_key']) {
      return false;
    }
    final record = MetadataRecord.fromJson(
        jsonDecode(records.single['record_json'] as String));
    return record.media
        .any((m) => MetadataArtworkCache.key(m) == item['media_key']);
  }

  /// User-requested retry is a new snapshot, never an automatic busy loop or a
  /// mutation of the old report. Successful entries and review decisions are not
  /// repeated. Blocked pending work continues through run() on its original job.
  Future<MetadataRefreshReport> retryUnresolved(int id,
      {Set<String> statuses = _retryable}) async {
    if (statuses.isEmpty || !_retryable.containsAll(statuses)) {
      throw ArgumentError('Only unresolved outcomes can be retried');
    }
    final selected = List<String>.unmodifiable(statuses.toList()..sort());
    final db = await _database;
    final job = await _job(db, id);
    return _create(
        providerId: job['provider_id'] as String,
        collectionGeneration: job['collection_generation'] as String,
        matchReview: job['is_match_review'] == 1,
        recordMissingIdentities: true,
        editions: (txn) async* {
          if ((await _job(txn, id))['state'] == 'running') {
            throw StateError(
                'Pause or finish the original job before retrying');
          }
          var cursor = '';
          while (true) {
            final items = await txn.query('metadata_refresh_items',
                columns: ['edition_id'],
                where:
                    'job_id = ? AND edition_id > ? AND status IN (${List.filled(selected.length, '?').join(',')})',
                whereArgs: [id, cursor, ...selected],
                orderBy: 'edition_id',
                limit: 128);
            for (final item in items) {
              final editionId = item['edition_id'] as String;
              await LibraryStore.refreshCatalogueEdition(txn, editionId);
              yield editionId;
            }
            if (items.length < 128) break;
            cursor = items.last['edition_id'] as String;
          }
        });
  }

  Future<MetadataRefreshReport> _create(
      {required String providerId,
      String? collectionGeneration,
      bool recordMissingIdentities = false,
      bool matchReview = false,
      required Stream<String> Function(Transaction) editions}) async {
    if (providerId.trim().isEmpty ||
        collectionGeneration?.trim().isEmpty == true) {
      throw ArgumentError('Provider and collection generation are required');
    }
    final db = await _database;
    final shared = await _sharedStore;
    await shared?.restore(db);
    final sharedMaximum = await shared?.maximumGeneration() ?? 0;
    final id = await db.transaction((txn) async {
      final maximum = await txn.rawQuery('''SELECT MAX(value) AS maximum FROM (
        SELECT MAX(generation) AS value FROM metadata_refresh_jobs
        UNION ALL SELECT MAX(generation_id) FROM library_metadata)''');
      final privateMaximum = (maximum.single['maximum'] as int?) ?? 0;
      final generation =
          (privateMaximum > sharedMaximum ? privateMaximum : sharedMaximum) + 1;
      final id = await txn.insert('metadata_refresh_jobs', {
        'generation': generation,
        'provider_id': providerId,
        'collection_generation':
            collectionGeneration ?? 'cached-catalogue:$generation',
        'state': 'paused',
        'is_match_review': matchReview ? 1 : 0,
      });
      // Consume explicit membership incrementally; never discover the collection
      // by scanning historical metadata or load every record into a Dart list.
      await for (final editionId in editions(txn)) {
        final row = await _identity(txn, editionId);
        if (row == null) {
          if (recordMissingIdentities) {
            await txn.insert('metadata_refresh_items', {
              'job_id': id,
              'edition_id': editionId,
              'lookup_key': editionId,
              'identity_key': 'unavailable',
              'status': 'identityChanged'
            });
            continue;
          }
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
        final corroboration = !matchReview && providerId == 'igdb'
            ? await _currentCorroboration(txn, row)
            : null;
        final request = game.platformId == null
            ? null
            : MetadataLookupRequest(
                gameId: game.id,
                editionId: edition.id,
                platformId: game.platformId!,
                title: corroboration?.titles.first ?? game.title,
                corroboration: corroboration,
                verifiedProviderGameId: !matchReview &&
                        {
                          IdentityMatchStatus.matched,
                          IdentityMatchStatus.manuallyMatched
                        }.contains(game.matchStatus)
                    ? game.providerIds[providerId]
                    : null,
                baseProviderGameId: matchReview ? null : baseProviderId,
                contentTags: edition.tags,
                region: await _lookupRegion(txn, game, edition),
                language: edition.languages.length == 1
                    ? edition.languages.single
                    : null,
                revision: edition.revision,
                romIdentifier: matchReview
                    ? null
                    : await _rawIdentifier(txn, edition, game.platformId!),
                refreshGeneration: generation);
        await txn.insert(
            'metadata_refresh_items',
            {
              'job_id': id,
              'edition_id': editionId,
              'lookup_key': _lookupKey(request, edition),
              'identity_key':
                  LibraryStore.metadataIdentity(row, providerId: providerId),
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

  /// A filename tag narrows discovery only; it does not assign release facts,
  /// classify content, establish an identity or make a score eligible. Explicit
  /// facts (including a manually cleared region) always take precedence.
  static Future<String?> _lookupRegion(
      DatabaseExecutor db, GameIdentity game, EditionIdentity edition) async {
    if (edition.regions.isNotEmpty) {
      return edition.regions.length == 1 ? edition.regions.single : null;
    }
    if (edition.evidence
        .any((e) => e.source == 'manual' && e.kind == 'releaseRegion')) {
      return null;
    }
    String? filename;
    if (edition.members.length == 1) {
      final rows = await db.query('library_artifacts',
          columns: ['record_json'],
          where: 'artifact_id = ?',
          whereArgs: [edition.members.single.artifactId.key],
          limit: 1);
      if (rows.isNotEmpty) {
        filename = RemoteArtifact.fromJson(
                jsonDecode(rows.single['record_json'] as String))
            .displayName;
      }
    } else if (edition.members.isEmpty) {
      final legacy = game.evidence
          .where((e) =>
              e.source == 'catalogue' &&
              e.kind == 'artifactIdentity' &&
              e.value.startsWith('legacy-cache-row:'))
          .toList();
      if (legacy.length == 1) {
        final id = int.tryParse(
            legacy.single.value.substring('legacy-cache-row:'.length));
        if (id != null) {
          final rows = await db.query('games',
              columns: ['filename'],
              where: 'id = ? AND artifact_key IS NULL AND is_folder = 0',
              whereArgs: [id],
              limit: 1);
          if (rows.isNotEmpty) filename = rows.single['filename'] as String;
        }
      }
    }
    if (filename == null || filename.contains(RegExp(r'[/\\]'))) return null;
    const codes = {
      'usa': 'us',
      'us': 'us',
      'u': 'us',
      'japan': 'jp',
      'jp': 'jp',
      'j': 'jp',
      'europe': 'eu',
      'eur': 'eu',
      'eu': 'eu',
      'e': 'eu',
      'world': 'wor',
      'australia': 'au',
      'au': 'au',
      'canada': 'ca',
      'ca': 'ca',
      'germany': 'de',
      'de': 'de',
      'france': 'fr',
      'fr': 'fr',
      'spain': 'es',
      'es': 'es',
      'italy': 'it',
      'it': 'it',
      'uk': 'uk',
      'united kingdom': 'uk',
      'brazil': 'br',
      'br': 'br',
      'korea': 'kr',
      'kr': 'kr',
      'china': 'cn',
      'cn': 'cn',
      'taiwan': 'tw',
      'tw': 'tw',
      'hong kong': 'hk',
      'hk': 'hk',
      'norway': 'no',
      'nor': 'no',
      'sweden': 'se',
      'swe': 'se',
      'denmark': 'dk',
      'dk': 'dk',
      'finland': 'fi',
      'fi': 'fi',
      'netherlands': 'nl',
      'nl': 'nl',
    };
    final regions = <String>{};
    for (final tag
        in RegExp(r'\(([^()]*)\)|\[([^\[\]]*)\]').allMatches(filename)) {
      final parts = (tag.group(1) ?? tag.group(2)!)
          .toLowerCase()
          .split(',')
          .map((p) => p.trim())
          .toList();
      if (!parts.any(codes.containsKey)) continue;
      if (!parts.every(codes.containsKey)) return null;
      regions.addAll(parts.map((p) => codes[p]!));
    }
    return regions.length == 1 ? regions.single : null;
  }

  static String _lookupKey(
      MetadataLookupRequest? request, EditionIdentity edition) {
    final keyData = request?.toJson()
      ?..remove('editionId')
      ..remove('refreshGeneration');
    final evidence = edition.toJson()
      ..remove('id')
      ..remove('members');
    return sha256
        .convert(utf8.encode(jsonEncode(_canonical([keyData, evidence]))))
        .toString();
  }

  static Future<MetadataCorroboration?> _currentCorroboration(
      DatabaseExecutor db, Map<String, Object?> identity,
      {String matchingPolicy = 'regionalReleaseV1'}) async {
    final game =
        GameIdentity.fromJson(jsonDecode(identity['game_json'] as String));
    final edition = EditionIdentity.fromJson(
        jsonDecode(identity['edition_json'] as String));
    if (game.platformId == null ||
        game.baseGameId != null ||
        game.matchStatus == IdentityMatchStatus.ambiguous ||
        game.providerIds.containsKey('igdb') ||
        edition.providerIds.containsKey('igdb') ||
        edition.tags.length != 1 ||
        !edition.tags.contains('official') ||
        edition.isTranslation == true ||
        edition.translatedLanguages.isNotEmpty ||
        edition.patchId != null ||
        edition.revision?.isNotEmpty == true ||
        edition.regions.length > 1) {
      return null;
    }
    final rows = await db.query('library_metadata',
        where: 'edition_id = ? AND provider_id = ?',
        whereArgs: [edition.id, 'screenscraper'],
        limit: 1);
    if (rows.isEmpty ||
        rows.single['identity_key'] !=
            LibraryStore.metadataIdentity(identity,
                providerId: 'screenscraper')) {
      return null;
    }
    final record = MetadataRecord.fromJson(
        jsonDecode(rows.single['record_json'] as String));
    if (record.refreshGeneration <= 0 ||
        record.gameId != game.id ||
        record.platformId != game.platformId ||
        record.editionId != edition.id ||
        !LibraryStore.hasConsistentProvenance(record) ||
        !{
          'rawRomHashAndSize',
          'rawRomSha1AndCappedSize',
          if (matchingPolicy != 'exactReleaseV1') 'exactRegionalOfficialTitle',
          if (matchingPolicy != 'exactReleaseV1') 'verifiedProviderId'
        }.contains(record.matchMethod)) {
      return null;
    }
    final newer = await db.rawQuery('''SELECT 1 FROM metadata_refresh_items i
      JOIN metadata_refresh_jobs j ON j.id=i.job_id WHERE i.edition_id=?
      AND j.provider_id='screenscraper' AND j.is_artwork=0 AND j.generation>?
      LIMIT 1''', [edition.id, record.refreshGeneration]);
    if (newer.isNotEmpty) return null;
    const regions = {
      'usa': 'us',
      'us': 'us',
      'europe': 'eu',
      'eu': 'eu',
      'japan': 'jp',
      'jp': 'jp',
      'world': 'wor',
      'wor': 'wor'
    };
    final selectedRegion = edition.regions.length == 1
        ? edition.regions.single
        : record.matchMethod == 'exactRegionalOfficialTitle'
            ? await _lookupRegion(db, game, edition)
            : null;
    final region = regions[selectedRegion?.trim().toLowerCase()];
    if (region == null) return null;
    if (record.matchMethod == 'exactRegionalOfficialTitle' &&
        (record.matchEvidence['matchingPolicy'] != 'regionalReleaseV1' ||
            record.matchEvidence['region'] != region ||
            record.matchEvidence['title'] is! String ||
            !record.titles.any((t) =>
                normalizeMetadataTitle(t.text) ==
                normalizeMetadataTitle(metadataSearchTitle(record.platformId,
                    record.matchEvidence['title'] as String))))) {
      return null;
    }
    final dates = record.releaseDates
        .where((d) =>
            d.region != null &&
            regions[d.region!.trim().toLowerCase()] == region)
        .toList();
    final date = selectEditionReleaseDate(dates, regions: [region]);
    final titles = record.titles.toList()
      ..sort((a, b) {
        int priority(MetadataText t) => switch (t.region?.toLowerCase()) {
              'us' => 0,
              'eu' => 1,
              'wor' || null => 2,
              _ => 3
            };
        return priority(a).compareTo(priority(b));
      });
    try {
      return MetadataCorroboration(
          providerGameId: record.providerGameId,
          recordHash: sha256
              .convert(utf8.encode(jsonEncode(_canonical(record.toJson()))))
              .toString(),
          titles: titles.map((t) => t.text).toSet().toList(),
          releaseDate: date ?? '',
          region: region,
          developer: record.developer ?? '',
          publisher: record.publisher ?? '',
          matchingPolicy: matchingPolicy);
    } on FormatException {
      return null;
    }
  }

  /// Extract once per current artifact, not once per title or per refresh. A
  /// declared original hash is lookup evidence only, never ROM integrity proof.
  Future<Map<String, Object?>?> _bindRomIdentifier(
      Database db,
      int jobId,
      Map<String, Object?> item,
      MetadataLookupRequest request,
      Map<String, Object?> identity,
      CancelToken cancel) async {
    final archive = {'n64', 'gamegear', 'gb', 'gbc', 'gba', 'nes', 'snes'}
        .contains(request.platformId);
    if ((archive ? _readArchiveIdentifier == null : _readRomHeader == null) ||
        request.romIdentifier != null ||
        request.verifiedProviderGameId != null ||
        !{'psp', 'ps2', 'n64', 'gamegear', 'gb', 'gbc', 'gba', 'nes', 'snes'}
            .contains(request.platformId)) {
      return null;
    }
    final game =
        GameIdentity.fromJson(jsonDecode(identity['game_json'] as String));
    final edition = EditionIdentity.fromJson(
        jsonDecode(identity['edition_json'] as String));
    if (game.baseGameId != null ||
        edition.members.length != 1 ||
        edition.patchId != null ||
        edition.isTranslation == true ||
        edition.translatedLanguages.isNotEmpty ||
        edition.tags.any((tag) => !{'unknown', 'official'}.contains(tag)) ||
        edition.evidence.any((e) =>
            (e.kind == 'rawRomIdentifier' &&
                !{'driveHeader', 'driveLocalArchive'}.contains(e.source)) ||
            (e.source == 'manual' &&
                e.kind == 'contentClassification' &&
                edition.tags.contains('unknown')))) {
      return null;
    }
    final rows = await db.query('library_artifacts',
        columns: ['record_json'],
        where: 'artifact_id = ?',
        whereArgs: [edition.members.single.artifactId.key],
        limit: 1);
    if (rows.isEmpty) return null;
    final artifact = RemoteArtifact.fromJson(
        jsonDecode(rows.single['record_json'] as String));
    if (artifact.id.providerId != 'drive' ||
        artifact.version?.isNotEmpty != true ||
        artifact.canDownload != true ||
        (artifact.sizeBytes ?? 0) < (archive ? 1 : 140) ||
        !(archive
            ? {'n64', 'gamegear'}.contains(request.platformId) &&
                    artifact.displayName.toLowerCase().endsWith('.zip') ||
                {'n64', 'gb', 'gbc', 'gba', 'nes', 'snes'}
                        .contains(request.platformId) &&
                    artifact.displayName.toLowerCase().endsWith('.7z')
            : artifact.displayName.toLowerCase().endsWith('.chd'))) {
      return null;
    }
    final source = archive ? 'driveLocalArchive' : 'driveHeader';
    final MetadataRomIdentifier? raw;
    try {
      if (archive) {
        raw =
            await _readArchiveIdentifier!(artifact, request.platformId, cancel);
      } else {
        final bytes =
            await _readRomHeader!(artifact, request.platformId, cancel);
        raw = bytes == null
            ? null
            : MetadataRomIdentifier.fromChdDvdHeader(
                bytes, artifact.displayName);
      }
    } catch (error) {
      // Drive reads drain before reporting cancellation. Translate only that
      // typed outcome for this job's signal, not errors racing with Pause.
      if (cancel.isCancelled &&
          (error is DriveApiException &&
                  error.issue == DriveApiIssue.cancelled ||
              error is DriveTransferException &&
                  error.issue == DriveTransferIssue.cancelled)) {
        throw const _RefreshCommitCancelled();
      }
      rethrow;
    }
    if (cancel.isCancelled) throw const _RefreshCommitCancelled();
    if (raw == null) return null;
    final rawJson = raw.toJson();
    return db.transaction((txn) async {
      if (cancel.isCancelled) throw const _RefreshCommitCancelled();
      final current = await _identity(txn, edition.id);
      final currentArtifacts = await txn.query('library_artifacts',
          columns: ['record_json'],
          where: 'artifact_id = ?',
          whereArgs: [artifact.id.key],
          limit: 1);
      if (current == null ||
          LibraryStore.metadataIdentity(current, providerId: 'screenscraper') !=
              item['identity_key'] ||
          currentArtifacts.isEmpty ||
          jsonEncode(RemoteArtifact.fromJson(jsonDecode(
                      currentArtifacts.single['record_json'] as String))
                  .toJson()) !=
              jsonEncode(artifact.toJson())) {
        await txn.update(
            'metadata_refresh_items', {'status': 'identityChanged'},
            where: 'job_id = ? AND edition_id = ?',
            whereArgs: [jobId, edition.id]);
      } else {
        final updated = EditionIdentity.fromJson({
          ...edition.toJson(),
          'evidence': [
            for (final e in edition.evidence)
              if ({'driveHeader', 'driveLocalArchive'}.contains(e.source) &&
                  {
                    'rawRomIdentifier',
                    'rawRomHeaderSource',
                    'rawRomArchiveSource'
                  }.contains(e.kind))
                IdentityEvidence(
                        source: e.source,
                        kind:
                            'previous${e.kind[0].toUpperCase()}${e.kind.substring(1)}',
                        value: e.value)
                    .toJson()
              else
                e.toJson(),
            IdentityEvidence(
                    source: source,
                    kind: 'rawRomIdentifier',
                    value: jsonEncode(rawJson))
                .toJson(),
            IdentityEvidence(
                source: source,
                kind: archive ? 'rawRomArchiveSource' : 'rawRomHeaderSource',
                value: jsonEncode({
                  'artifact': artifact.toJson(),
                  'version': artifact.version,
                  if (!archive) 'bytesRead': 140,
                  'integrityVerified': false,
                  if (archive) 'localContainerMatchesDriveChecksums': true,
                  if (archive) 'rawContentValidated': true,
                })).toJson()
          ]
        });
        final updatedRequest = MetadataLookupRequest.fromJson(
            {...request.toJson(), 'romIdentifier': rawJson});
        await txn.update(
            'library_editions', {'record_json': jsonEncode(updated.toJson())},
            where: 'edition_id = ?', whereArgs: [edition.id]);
        final binding = (await _identity(txn, edition.id))!;
        await txn.update(
            'metadata_refresh_items',
            {
              'request_json': jsonEncode(updatedRequest.toJson()),
              'identity_key': LibraryStore.metadataIdentity(binding,
                  providerId: 'screenscraper'),
              'lookup_key': _lookupKey(updatedRequest, updated)
            },
            where: 'job_id = ? AND edition_id = ?',
            whereArgs: [jobId, edition.id]);
        await LibraryStore.indexCanonicalGroups(txn, editionId: edition.id);
      }
      if (cancel.isCancelled) throw const _RefreshCommitCancelled();
      return (await txn.query('metadata_refresh_items',
              where: 'job_id = ? AND edition_id = ?',
              whereArgs: [jobId, edition.id],
              limit: 1))
          .single;
    });
  }

  /// Explicit compatible ROM evidence, not a provider-file/container checksum.
  /// The edition binding preserves this assertion through lookup/publication.
  /// Conflicting or malformed assertions leave title discovery for review; the
  /// adapter still checks kind, filename, hash syntax, size and returned hash.
  static Future<MetadataRomIdentifier?> _rawIdentifier(
      DatabaseExecutor db, EditionIdentity edition, String platformId) async {
    final evidence = edition.evidence
        .where((item) => item.kind == 'rawRomIdentifier')
        .toList(growable: false);
    if (evidence.isEmpty) {
      if (edition.members.length != 1) return null;
      final rows = await db.query('library_artifacts',
          columns: ['record_json'],
          where: 'artifact_id = ?',
          whereArgs: [edition.members.single.artifactId.key],
          limit: 1);
      if (rows.isEmpty) return null;
      return MetadataRomIdentifier.fromUncompressedDriveArtifact(
          RemoteArtifact.fromJson(
              jsonDecode(rows.single['record_json'] as String)),
          platformId);
    }
    if (evidence.length != 1) return null;
    // A preserved manual assertion made before the current content marker is
    // review evidence, not proof about a replacement blob.
    final rawIndex = edition.evidence.indexOf(evidence.single);
    final markerIndex = edition.evidence.lastIndexWhere(
        (e) => e.source == 'catalogue' && e.kind == 'artifactContent');
    if (markerIndex > rawIndex) return null;
    try {
      final value = jsonDecode(evidence.single.value);
      if (value is! Map<String, dynamic>) return null;
      return MetadataRomIdentifier.fromJson(value);
    } on FormatException {
      return null;
    }
  }

  /// Local paged review only: displaying outcomes never starts provider requests.
  Future<List<MetadataReviewItem>> reviewItems(int id,
      {String afterEditionId = '', int limit = 50}) async {
    if (limit < 1 || limit > 128) throw ArgumentError.value(limit, 'limit');
    final db = await _database;
    final rows = await db.query('metadata_refresh_items',
        where: 'job_id = ? AND edition_id > ? AND status IN (?, ?, ?)',
        whereArgs: [
          id,
          afterEditionId,
          'needsReview',
          'ambiguous',
          'unmatched'
        ],
        orderBy: 'edition_id',
        limit: limit);
    return List.unmodifiable(rows.map(_reviewItem));
  }

  /// Latest outcome per provider/edition, not only the latest job. A one-game
  /// correction must not hide the remaining reviews from a full-library job.
  /// A newer pending/resolved outcome supersedes its old candidates. Pages are
  /// cache-only and bounded even when all preceding jobs remain in the audit.
  Future<List<MetadataReviewItem>> reviewQueue(String providerId,
      {String afterEditionId = '',
      int limit = 50,
      String? systemSlug,
      String? editionId,
      int? cacheRowId}) async {
    if (providerId.trim().isEmpty || limit < 1 || limit > 128) {
      throw ArgumentError('Provider and bounded review page are required');
    }
    final db = await _database;
    return db.transaction((txn) async {
      var selectedEditionId = editionId;
      if (cacheRowId != null) {
        final currentEditionId =
            await LibraryStore.cachedCatalogueEditionId(txn, cacheRowId);
        if (currentEditionId == null ||
            (editionId != null && currentEditionId != editionId)) {
          return <MetadataReviewItem>[];
        }
        selectedEditionId = currentEditionId;
      }
      final rows =
          await txn.rawQuery('''SELECT i.* FROM metadata_refresh_items i
      JOIN metadata_refresh_jobs j ON j.id = i.job_id
      JOIN library_editions e ON e.edition_id = i.edition_id
      JOIN library_game_identities g ON g.game_id = e.game_id
      WHERE j.provider_id = ? AND j.is_artwork = 0 AND i.edition_id > ?
        AND i.status IN ('needsReview', 'ambiguous', 'unmatched')
        ${systemSlug == null ? '' : 'AND g.platform_id = ?'}
        ${selectedEditionId == null ? '' : 'AND i.edition_id = ?'}
        AND NOT EXISTS (SELECT 1 FROM metadata_refresh_items n
          JOIN metadata_refresh_jobs nj ON nj.id = n.job_id
          WHERE n.edition_id = i.edition_id AND nj.provider_id = j.provider_id
            AND nj.is_artwork = 0 AND nj.generation > j.generation)
      ORDER BY i.edition_id LIMIT ?''', [
        providerId,
        afterEditionId,
        if (systemSlug != null) systemSlug,
        if (selectedEditionId != null) selectedEditionId,
        limit
      ]);
      final items = <MetadataReviewItem>[];
      for (final row in rows) {
        final current = await _identity(txn, row['edition_id'] as String);
        items.add(_reviewItem(row,
            artifactLabels: current == null
                ? const []
                : await _reviewArtifactLabels(txn, current),
            identityCurrent: current != null &&
                row['identity_key'] ==
                    LibraryStore.metadataIdentity(current,
                        providerId: providerId)));
      }
      return List.unmodifiable(items);
    });
  }

  static MetadataReviewItem _reviewItem(Map<String, Object?> row,
          {bool identityCurrent = true,
          List<String> artifactLabels = const []}) =>
      MetadataReviewItem(
        jobId: row['job_id'] as int,
        editionId: row['edition_id'] as String,
        status: row['status'] as String,
        identityCurrent: identityCurrent,
        artifactLabels: artifactLabels,
        candidates:
            List.unmodifiable(_candidates(row['candidates_json'] as String?)),
        request: row['request_json'] == null
            ? null
            : MetadataLookupRequest.fromJson(
                jsonDecode(row['request_json'] as String)
                    as Map<String, dynamic>),
      );

  /// Current cached names are review context, never match/classification proof.
  /// Read only this edition's members; no provider requests or library-wide scan.
  static Future<List<String>> _reviewArtifactLabels(
      DatabaseExecutor db, Map<String, Object?> identity) async {
    final edition = EditionIdentity.fromJson(
        jsonDecode(identity['edition_json'] as String));
    final labels = <String>{};
    for (final member in edition.members) {
      final rows = await db.query('library_artifacts',
          columns: ['record_json'],
          where: 'artifact_id = ?',
          whereArgs: [member.artifactId.key],
          limit: 1);
      if (rows.isEmpty) continue;
      final artifact = RemoteArtifact.fromJson(
          jsonDecode(rows.single['record_json'] as String));
      labels.add(artifact.displayPath.isEmpty
          ? artifact.displayName
          : artifact.displayPath);
    }
    final game =
        GameIdentity.fromJson(jsonDecode(identity['game_json'] as String));
    for (final evidence in game.evidence.where((e) =>
        e.source == 'catalogue' &&
        e.kind == 'artifactIdentity' &&
        e.value.startsWith('legacy-cache-row:'))) {
      final id =
          int.tryParse(evidence.value.substring('legacy-cache-row:'.length));
      if (id == null) continue;
      final rows = await db.query('games',
          columns: ['filename'],
          where: 'id = ? AND artifact_key IS NULL AND is_folder = 0',
          whereArgs: [id],
          limit: 1);
      if (rows.isNotEmpty) labels.add(rows.single['filename'] as String);
    }
    return List.unmodifiable(labels);
  }

  static List<MetadataLookupCandidate> _candidates(String? json) =>
      (json == null ? <dynamic>[] : jsonDecode(json) as List).map((value) {
        final candidate = value as Map<String, dynamic>;
        return MetadataLookupCandidate(
            providerGameId: candidate['providerGameId'] as String,
            platformId: candidate['platformId'] as String,
            titles: (candidate['titles'] as List)
                .map((title) =>
                    MetadataText.fromJson(title as Map<String, dynamic>))
                .toList(),
            titleMatched: candidate['titleMatched'] as bool,
            evidence: candidate['evidence'] as String);
      }).toList();

  /// Explicit review is one atomic correction + new-generation retry snapshot.
  /// A failed validation creates neither a correction nor an orphan retry job.
  /// Tags describe this edition; selecting an ID never makes a patch official or
  /// transfers an original game's score to it. The provider still verifies that.
  Future<MetadataRefreshReport> acceptCandidate(int id,
      {required String editionId,
      required String providerGameId,
      required Set<String> contentTags,
      String? reviewedRegion}) async {
    final classification = EditionIdentity.normalizeContentTags(contentTags);
    final region = reviewedRegion?.trim();
    if (region != null &&
        (region.length > 32 ||
            (region.isNotEmpty &&
                !RegExp(r'^[A-Za-z]{2,}(?:[ -][A-Za-z]{2,})*$')
                    .hasMatch(region)))) {
      throw ArgumentError('Invalid reviewed region');
    }
    final db = await _database;
    final job = await _job(db, id);
    final providerId = job['provider_id'] as String;
    return _create(
        providerId: providerId,
        collectionGeneration: job['collection_generation'] as String,
        editions: (txn) async* {
          final items = await txn.query('metadata_refresh_items',
              where: 'job_id = ? AND edition_id = ?',
              whereArgs: [id, editionId],
              limit: 1);
          final current = await _identity(txn, editionId);
          final newer = await txn.rawQuery(
              '''SELECT 1 FROM metadata_refresh_items i
            JOIN metadata_refresh_jobs j ON j.id = i.job_id
            WHERE i.edition_id = ? AND j.provider_id = ? AND j.is_artwork = 0
              AND j.generation > ? LIMIT 1''',
              [editionId, providerId, job['generation']]);
          if (items.isEmpty ||
              newer.isNotEmpty ||
              current == null ||
              !{'needsReview', 'ambiguous'}.contains(items.single['status']) ||
              items.single['identity_key'] !=
                  LibraryStore.metadataIdentity(current,
                      providerId: providerId)) {
            throw StateError(
                'The current identity no longer matches this review');
          }
          final game =
              GameIdentity.fromJson(jsonDecode(current['game_json'] as String));
          final edition = EditionIdentity.fromJson(
              jsonDecode(current['edition_json'] as String));
          final offered =
              _candidates(items.single['candidates_json'] as String?).where(
                  (c) =>
                      c.providerGameId == providerGameId &&
                      c.platformId == game.platformId);
          if (offered.length != 1 ||
              classification.isEmpty ||
              !EditionIdentity.knownContentTags.containsAll(classification) ||
              (classification.contains('official') &&
                  classification.length != 1)) {
            throw StateError(
                'Review requires an offered identity and consistent classification');
          }
          final tags = classification.toList()..sort();
          final correctedGame = GameIdentity.fromJson({
            ...game.toJson(),
            'providerIds': {...game.providerIds, providerId: providerGameId},
            'matchStatus': 'manuallyMatched',
            'evidence': [
              ...game.evidence.map((e) => e.toJson()),
              IdentityEvidence(
                  source: 'manual',
                  kind: 'providerId',
                  value: jsonEncode([providerId, providerGameId])).toJson()
            ],
          });
          final correctedEdition = EditionIdentity.fromJson({
            ...edition.toJson(),
            'tags': tags,
            if (region != null) 'regions': [if (region.isNotEmpty) region],
            if (classification.contains('T-Eng')) ...{
              'isTranslation': true,
              'translatedLanguages': [
                ...edition.translatedLanguages.where((l) => l != 'en'),
                'en'
              ],
            },
            if (classification.contains('official')) ...{
              'isTranslation': false,
              'translatedLanguages': <String>[],
            },
            'evidence': [
              ...edition.evidence
                  .where((e) => !(e.source == 'manual' &&
                      (e.kind == 'contentClassification' ||
                          (region != null && e.kind == 'releaseRegion'))))
                  .map((e) => e.toJson()),
              if (region != null)
                IdentityEvidence(
                        source: 'manual',
                        kind: 'releaseRegion',
                        value: region.isEmpty ? 'unknown' : region)
                    .toJson(),
              IdentityEvidence(
                      source: 'manual',
                      kind: 'contentClassification',
                      value: jsonEncode(tags))
                  .toJson()
            ],
          });
          await txn.update(
              'library_game_identities',
              {
                'title': correctedGame.title,
                'match_status': correctedGame.matchStatus.name,
                'record_json': jsonEncode(correctedGame.toJson()),
              },
              where: 'game_id = ?',
              whereArgs: [game.id]);
          await txn.update('library_editions',
              {'record_json': jsonEncode(correctedEdition.toJson())},
              where: 'edition_id = ?', whereArgs: [editionId]);
          await LibraryStore.indexCanonicalGroups(txn, gameId: game.id);
          yield editionId;
        });
  }

  Future<MetadataRefreshReport> report(int id) async {
    final db = await _database;
    return db.transaction((txn) async {
      final row = await _job(txn, id);
      final artwork = row['is_artwork'] == 1;
      final totals = await txn.rawQuery('''SELECT status, COUNT(*) AS count,
        ${artwork ? '0' : 'SUM(rated)'} AS rated FROM ${artwork ? 'metadata_artwork_items' : 'metadata_refresh_items'} WHERE job_id = ? GROUP BY status''',
          [id]);
      return MetadataRefreshReport(
          id: id,
          generation: row['generation'] as int,
          collectionGeneration: row['collection_generation'] as String,
          state: row['state'] as String,
          requested: row['requested'] as int,
          rated: totals.fold(0, (sum, r) => sum + (r['rated'] as int)),
          kind: artwork ? 'artwork' : 'metadata',
          providerId: row['provider_id'] as String,
          quotaObservation:
              await _quotaObservation(txn, row['provider_id'] as String),
          lastProcessed: _lastProcessed?.jobId == id ? _lastProcessed : null,
          counts: Map.unmodifiable({
            for (final r in totals) r['status'] as String: r['count'] as int
          }),
          blockedStatus: row['blocked_status'] as String?,
          notBefore: row['not_before'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(row['not_before'] as int,
                  isUtc: true));
    });
  }

  /// Restore one durable job, not an unbounded history or catalogue load.
  Future<MetadataRefreshReport?> latest({required String providerId}) async {
    final db = await _database;
    final rows = await db.query('metadata_refresh_jobs',
        columns: ['id'],
        where: 'provider_id = ? AND is_artwork = 0',
        whereArgs: [providerId],
        orderBy: 'id DESC',
        limit: 1);
    return rows.isEmpty ? null : report(rows.single['id'] as int);
  }

  /// Keyset-paged saved metadata jobs; never snapshot editions or fetch media.
  Future<List<MetadataRefreshReport>> savedJobs(
      {required String providerId, int? beforeId, int limit = 10}) async {
    if (limit < 1 || limit > 20 || (beforeId != null && beforeId < 1)) {
      throw ArgumentError('Invalid saved-job page');
    }
    final db = await _database;
    final rows = await db.query('metadata_refresh_jobs',
        columns: ['id'],
        where: 'provider_id = ? AND is_artwork = 0'
            '${beforeId == null ? '' : ' AND id < ?'}',
        whereArgs: [providerId, if (beforeId != null) beforeId],
        orderBy: 'id DESC',
        limit: limit);
    return List.unmodifiable(
        [for (final row in rows) await report(row['id'] as int)]);
  }

  static Future<Map<String, Object?>> _job(DatabaseExecutor db, int id) async {
    final rows = await db.query('metadata_refresh_jobs',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw StateError('Unknown metadata refresh job');
    return rows.single;
  }

  Future<MetadataRefreshReport> run(int id, MetadataProvider provider,
      {bool recheckAccess = false,
      MetadataArtworkCache? artworkCache,
      void Function(MetadataRefreshReport)? onProgress}) {
    if (recheckAccess && provider is! MetadataAccessProvider) {
      throw ArgumentError('This provider has no explicit access check');
    }
    if (_active != null) {
      throw StateError('A metadata refresh is already active');
    }
    final cancel = CancelToken();
    _cancel = cancel;
    return _active =
        _run(id, provider, cancel, recheckAccess, artworkCache, onProgress)
            .then((result) {
      onProgress?.call(result);
      return result;
    }).whenComplete(() {
      _active = null;
      _cancel = null;
    });
  }

  Future<void> pause() async {
    _cancel?.cancel('Metadata refresh paused');
    await _active;
  }

  Future<MetadataRefreshReport> _run(
      int id,
      MetadataProvider provider,
      CancelToken cancel,
      bool recheckAccess,
      MetadataArtworkCache? artworkCache,
      void Function(MetadataRefreshReport)? onProgress) async {
    final db = await _database;
    final claimed = await db.transaction((txn) async {
      final job = await _job(txn, id);
      if (job['provider_id'] != provider.providerId) {
        throw StateError('Wrong metadata provider');
      }
      if (job['is_artwork'] == 1 &&
          (artworkCache == null || provider is! MetadataArtworkProvider)) {
        throw ArgumentError(
            'Artwork job requires an image provider and private cache');
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
    final matchReview = (await _job(db, id))['is_match_review'] == 1;
    Timer? budgetTimer;
    Completer<void>? budgetWait;
    // One cancellation listener per run, not one retained listener per item.
    cancel.whenCancel.then((_) {
      budgetTimer?.cancel();
      if (budgetWait?.isCompleted == false) budgetWait!.complete();
    });
    Future<void> waitForBudget(int target) async {
      if (cancel.isCancelled) return;
      final remaining = target - _now().millisecondsSinceEpoch;
      if (remaining <= 0) return;
      final completion = Completer<void>();
      budgetWait = completion;
      // This is the provider's declared API cadence, not a lifecycle deadline.
      budgetTimer = _schedule(Duration(milliseconds: remaining), () {
        if (!completion.isCompleted) completion.complete();
      });
      await completion.future;
      budgetTimer?.cancel();
      budgetTimer = null;
      budgetWait = null;
    }

    try {
      // One SQL aggregate at entry, then bounded committed-page deltas.
      // Observer/storage failures also release the durable worker claim.
      final initial = await report(id);
      final counts = Map<String, int>.from(initial.counts);
      var requested = initial.requested;
      var rated = initial.rated;
      var quotaObservation = initial.quotaObservation;
      void publish([Map<String, int> changes = const {}, int ratedChange = 0]) {
        for (final entry in changes.entries) {
          counts['pending'] = (counts['pending'] ?? 0) - entry.value;
          counts[entry.key] = (counts[entry.key] ?? 0) + entry.value;
        }
        if (counts['pending'] == 0) counts.remove('pending');
        rated += ratedChange;
        onProgress?.call(MetadataRefreshReport(
            id: id,
            generation: initial.generation,
            collectionGeneration: initial.collectionGeneration,
            state: 'running',
            requested: requested,
            rated: rated,
            counts: Map.unmodifiable(counts),
            providerId: provider.providerId,
            quotaObservation: quotaObservation,
            lastProcessed: _lastProcessed?.jobId == id ? _lastProcessed : null,
            kind: initial.kind));
      }

      publish();
      if (recheckAccess) {
        if (!await _requestSlot(
            db, id, provider.providerId, cancel, waitForBudget,
            accessCheck: true)) {
          if (!cancel.isCancelled) return await report(id);
        } else if (!cancel.isCancelled) {
          final started = _now().millisecondsSinceEpoch;
          final checked = await (provider as MetadataAccessProvider)
              .checkAccess(cancelToken: cancel);
          if (!cancel.isCancelled &&
              checked.status != MetadataLookupStatus.cancelled) {
            await _observeQuota(db, provider.providerId, checked.quota, started,
                accessConfirmed:
                    checked.status == MetadataLookupStatus.matched);
            quotaObservation = await _quotaObservation(db, provider.providerId);
            publish();
            if (checked.status != MetadataLookupStatus.matched) {
              await _block(db, id, checked.status, checked.retryAfter);
              return await report(id);
            }
          }
        }
      }
      if ((await _job(db, id))['is_artwork'] == 1) {
        return await _runArtwork(db, id, provider as MetadataArtworkProvider,
            artworkCache!, cancel, waitForBudget, initial, onProgress);
      }
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
        var item = next.single;
        var request = MetadataLookupRequest.fromJson(
            jsonDecode(item['request_json'] as String));
        final current = await _identity(db, request.editionId);
        if (current == null ||
            LibraryStore.metadataIdentity(current,
                    providerId: provider.providerId) !=
                item['identity_key']) {
          await db.update(
              'metadata_refresh_items', {'status': 'identityChanged'},
              where: 'job_id = ? AND edition_id = ?',
              whereArgs: [id, request.editionId]);
          publish({'identityChanged': 1});
          continue;
        }
        if (cancel.isCancelled) break;
        final shared = await _sharedStore;
        final recovered = matchReview
            ? null
            : await shared?.committedResponse(
                request.editionId,
                provider.providerId,
                item['identity_key'] as String,
                request.refreshGeneration);
        if (cancel.isCancelled) break;
        if (recovered != null) {
          await _commitResult(
              db,
              id,
              item,
              request,
              MetadataLookupResult(
                  status: MetadataLookupStatus.matched,
                  record: recovered,
                  message: 'Durably committed response recovered.'),
              provider.providerId,
              cancel,
              publish);
          continue;
        }
        if (!matchReview && provider.providerId == 'screenscraper') {
          final bound =
              await _bindRomIdentifier(db, id, item, request, current, cancel);
          if (bound != null) {
            item = bound;
            if (item['status'] != 'pending') {
              publish({'identityChanged': 1});
              continue;
            }
            request = MetadataLookupRequest.fromJson(
                jsonDecode(item['request_json'] as String));
          }
        }
        if (!await _requestSlot(
            db, id, provider.providerId, cancel, waitForBudget)) {
          if (cancel.isCancelled) break;
          return await report(id);
        }
        if (cancel.isCancelled) break;
        // A protocol wait is not permission to use a now-removed or changed item.
        final afterWait = await _identity(db, request.editionId);
        if (afterWait == null ||
            LibraryStore.metadataIdentity(afterWait,
                    providerId: provider.providerId) !=
                item['identity_key']) {
          await db.update(
              'metadata_refresh_items', {'status': 'identityChanged'},
              where: 'job_id = ? AND edition_id = ?',
              whereArgs: [id, request.editionId]);
          publish({'identityChanged': 1});
          continue;
        }
        final requestStarted = _now().millisecondsSinceEpoch;
        await db.rawUpdate(
            'UPDATE metadata_refresh_jobs SET requested = requested + 1 WHERE id = ?',
            [id]);
        requested++;
        if (cancel.isCancelled) break;
        final result = await provider.lookup(request, cancelToken: cancel);
        if (cancel.isCancelled ||
            result.status == MetadataLookupStatus.cancelled) {
          break;
        }
        await _observeQuota(
            db, provider.providerId, result.quota, requestStarted);
        quotaObservation = await _quotaObservation(db, provider.providerId);
        if (_blocking.contains(result.status)) {
          await _block(db, id, result.status, result.retryAfter);
          return await report(id);
        }
        await _commitResult(
            db, id, item, request, result, provider.providerId, cancel, publish,
            matchReview: matchReview);
        final candidate =
            result.candidates.length == 1 ? result.candidates.single : null;
        final committedItem = (await db.query('metadata_refresh_items',
                columns: ['status'],
                where: 'job_id = ? AND edition_id = ?',
                whereArgs: [id, request.editionId],
                limit: 1))
            .single;
        final outcome = MetadataLookupStatus.values
                .where((s) => s.name == committedItem['status'])
                .firstOrNull ??
            MetadataLookupStatus.invalidRequest;
        final previewMedia = outcome == MetadataLookupStatus.needsReview
            ? candidate?.previewMedia
            : result.record == null
                ? null
                : MetadataArtworkCache.displayMedia(result.record!)
                    .where(
                        (m) => {'box-2D', 'box-3D', 'cover'}.contains(m.type))
                    .firstOrNull;
        final cachedCover = outcome == MetadataLookupStatus.matched
            ? await artworkCache?.previewForEdition(request.editionId)
            : null;
        final descriptions = boundedMetadataPreviewDescriptions(
            outcome == MetadataLookupStatus.matched
                ? result.record?.descriptions ?? const []
                : outcome == MetadataLookupStatus.needsReview
                    ? candidate?.previewDescriptions ?? const []
                    : const []);
        _lastProcessed = MetadataProcessedGame(
            jobId: id,
            providerId: provider.providerId,
            editionId: request.editionId,
            title: request.title,
            platformId: request.platformId,
            status: outcome,
            candidateTitle: candidate?.titles.firstOrNull?.text,
            previewMedia: previewMedia,
            previewDescriptions: descriptions,
            coverBytes: cachedCover);
        publish();
        if (cancel.isCancelled) break;
        // Candidate previews are serial budgeted image requests, independent of
        // the display cadence. Accepted covers use the existing artwork job.
        if (outcome == MetadataLookupStatus.needsReview &&
            previewMedia != null &&
            provider is MetadataArtworkProvider) {
          if (!await _requestSlot(
              db, id, provider.providerId, cancel, waitForBudget)) {
            if (cancel.isCancelled) break;
            return await report(id);
          }
          if (cancel.isCancelled) break;
          final imageStarted = _now().millisecondsSinceEpoch;
          final preview = await MetadataArtworkCache.fetchPreview(
              previewMedia, provider, cancel);
          if (cancel.isCancelled) break;
          await _observeQuota(
              db, provider.providerId, preview.result.quota, imageStarted);
          quotaObservation = await _quotaObservation(db, provider.providerId);
          _lastProcessed = MetadataProcessedGame(
              jobId: id,
              providerId: provider.providerId,
              editionId: request.editionId,
              title: request.title,
              platformId: request.platformId,
              status: outcome,
              candidateTitle: candidate?.titles.firstOrNull?.text,
              previewMedia: previewMedia,
              previewDescriptions: descriptions,
              coverBytes: preview.bytes);
          publish();
          if ({
            MetadataLookupStatus.quotaExceeded,
            MetadataLookupStatus.throttled,
            MetadataLookupStatus.authenticationRequired,
            MetadataLookupStatus.setupRequired,
            MetadataLookupStatus.developerAccessRequired
          }.contains(preview.result.status)) {
            await _block(
                db, id, preview.result.status, preview.result.retryAfter);
            return await report(id);
          }
        }
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
    } finally {
      budgetTimer?.cancel();
    }
    return report(id);
  }

  Future<MetadataRefreshReport> _runArtwork(
      Database db,
      int id,
      MetadataArtworkProvider provider,
      MetadataArtworkCache cache,
      CancelToken cancel,
      Future<void> Function(int) waitForBudget,
      MetadataRefreshReport initial,
      void Function(MetadataRefreshReport)? onProgress) async {
    final counts = Map<String, int>.from(initial.counts);
    var requested = initial.requested;
    void publish(Map<String, int> changes) {
      for (final entry in changes.entries) {
        counts['pending'] = (counts['pending'] ?? 0) - entry.value;
        counts[entry.key] = (counts[entry.key] ?? 0) + entry.value;
      }
      if (counts['pending'] == 0) counts.remove('pending');
      onProgress?.call(MetadataRefreshReport(
          id: id,
          generation: initial.generation,
          collectionGeneration: initial.collectionGeneration,
          state: 'running',
          requested: requested,
          rated: 0,
          counts: Map.unmodifiable(counts),
          kind: 'artwork',
          providerId: provider.providerId));
    }

    while (!cancel.isCancelled) {
      final next = await db.query('metadata_artwork_items',
          where: 'job_id = ? AND status = ?',
          whereArgs: [id, 'pending'],
          orderBy: 'edition_id, media_key',
          limit: 1);
      if (next.isEmpty) {
        await _setState(db, id, 'completed');
        return report(id);
      }
      final item = next.single;
      Future<bool> current() => _currentArtwork(db, item, provider.providerId);
      Future<void> invalidated() async {
        await db.update('metadata_artwork_items', {'status': 'identityChanged'},
            where: 'job_id = ? AND edition_id = ? AND media_key = ?',
            whereArgs: [id, item['edition_id'], item['media_key']]);
        publish({'identityChanged': 1});
      }

      if (!await current()) {
        await invalidated();
        continue;
      }
      final media =
          MetadataMedia.fromJson(jsonDecode(item['media_json'] as String));
      MetadataArtworkBlob? blob;
      DateTime? retrievedAt;
      var reviewedReuse = false;
      final durable = await cache.sharedStore?.committedArtwork(
          provider.providerId, initial.generation, item['media_key'] as String);
      if (durable != null) {
        blob = durable.blob;
        retrievedAt = durable.retrievedAt;
      }
      if (blob == null) {
        final reviewed = await cache.sharedStore?.reviewedArtwork(
            item['edition_id'] as String,
            provider.providerId,
            item['identity_key'] as String,
            item['media_key'] as String);
        if (reviewed != null) {
          blob = reviewed.blob;
          retrievedAt = reviewed.retrievedAt;
          reviewedReuse = true;
        }
      }
      final completed = await db.query('metadata_artwork_items',
          columns: ['edition_id'],
          where: 'job_id = ? AND media_key = ? AND status = ?',
          whereArgs: [id, item['media_key'], 'matched'],
          limit: 1);
      // Only a verified provider response can coalesce different editions.
      // Explicitly reviewed ES-DE reuse above is edition-scoped, not a fresh
      // body receipt. Shared stores use their generation-specific receipts.
      if (blob == null &&
          cache.sharedStore == null &&
          completed.isNotEmpty &&
          await cache.fileFor(
                  item['edition_id'] as String, provider.providerId, media) !=
              null) {
        final stored = (await db.query('metadata_artwork_cache',
                where: 'media_key = ?',
                whereArgs: [item['media_key']],
                limit: 1))
            .single;
        blob = MetadataArtworkBlob(item['media_key'] as String,
            stored['filename'] as String, stored['byte_length'] as int);
        retrievedAt = DateTime.parse(stored['retrieved_at'] as String);
      }
      var result = MetadataLookupResult(
          status: MetadataLookupStatus.matched,
          message: 'Completed image reused within this job.');
      if (blob == null) {
        if (!await _requestSlot(
            db, id, provider.providerId, cancel, waitForBudget)) {
          if (cancel.isCancelled) break;
          return report(id);
        }
        if (cancel.isCancelled) break;
        if (!await current()) {
          await invalidated();
          continue;
        }
        final started = _now().millisecondsSinceEpoch;
        await db.rawUpdate(
            'UPDATE metadata_refresh_jobs SET requested = requested + 1 WHERE id = ?',
            [id]);
        requested++;
        publish(const {});
        final downloaded = await cache.download(media, provider, id, cancel);
        result = downloaded.result;
        blob = downloaded.blob;
        if (blob != null) retrievedAt = _now();
        if (cancel.isCancelled ||
            result.status == MetadataLookupStatus.cancelled) {
          break;
        }
        await _observeQuota(db, provider.providerId, result.quota, started);
        if (_blocking.contains(result.status)) {
          await _block(db, id, result.status, result.retryAfter);
          return report(id);
        }
      }
      while (!cancel.isCancelled) {
        final changes = await db.transaction((txn) async {
          final targets = await txn.query('metadata_artwork_items',
              where: 'job_id = ? AND media_key = ? AND status = ?'
                  '${reviewedReuse ? ' AND edition_id = ?' : ''}',
              whereArgs: [
                id,
                item['media_key'],
                'pending',
                if (reviewedReuse) item['edition_id']
              ],
              orderBy: 'edition_id',
              limit: 128);
          var published = false;
          final changes = <String, int>{};
          for (final target in targets) {
            if (cancel.isCancelled) throw const _RefreshCommitCancelled();
            final valid =
                await _currentArtwork(txn, target, provider.providerId);
            if (valid && blob != null && !published) {
              final completedBlob = blob;
              await cache.sharedStore?.preserveBlob(completedBlob, retrievedAt!,
                  providerId: reviewedReuse ? null : provider.providerId,
                  generation: reviewedReuse ? null : initial.generation);
              if (cancel.isCancelled) throw const _RefreshCommitCancelled();
              await MetadataArtworkCache.publish(
                  txn, completedBlob, retrievedAt!);
              published = true;
            }
            await txn.update('metadata_artwork_items',
                {'status': valid ? result.status.name : 'identityChanged'},
                where: 'job_id = ? AND edition_id = ? AND media_key = ?',
                whereArgs: [id, target['edition_id'], target['media_key']]);
            final status = valid ? result.status.name : 'identityChanged';
            changes[status] = (changes[status] ?? 0) + 1;
          }
          return changes;
        });
        publish(changes);
        final count = changes.values.fold(0, (a, b) => a + b);
        if (count < 128) break;
      }
      final latest = _lastProcessed;
      if (latest != null &&
          latest.editionId == item['edition_id'] &&
          latest.providerId == provider.providerId &&
          result.status == MetadataLookupStatus.matched &&
          {'box-2D', 'box-3D', 'cover'}.contains(media.type)) {
        final bytes = await cache.previewForEdition(latest.editionId);
        if (!cancel.isCancelled) {
          _lastProcessed = MetadataProcessedGame(
              jobId: latest.jobId,
              providerId: latest.providerId,
              editionId: latest.editionId,
              title: latest.title,
              platformId: latest.platformId,
              status: latest.status,
              candidateTitle: latest.candidateTitle,
              previewMedia: latest.previewMedia,
              previewDescriptions: latest.previewDescriptions,
              coverBytes: bytes);
        }
      }
    }
    await _setState(db, id, 'paused');
    return report(id);
  }

  Future<bool> _requestSlot(Database db, int id, String providerId,
      CancelToken cancel, Future<void> Function(int) wait,
      {bool accessCheck = false}) async {
    while (!cancel.isCancelled) {
      final slot = await db.transaction((txn) async {
        final rows = await txn.query('metadata_provider_limits',
            where: 'provider_id = ?', whereArgs: [providerId], limit: 1);
        if (rows.isEmpty) return 0;
        if (!accessCheck &&
            (rows.single['quota_exhausted'] == 1 ||
                rows.single['max_threads'] == 0 ||
                rows.single['remaining_requests'] == 0)) {
          return -1;
        }
        final rate = rows.single['requests_per_minute'] as int?;
        if (rate == 0) return -1;
        final now = _now().millisecondsSinceEpoch;
        final next = rows.single['next_allowed_at'] as int;
        if (next > now) {
          await txn.update('metadata_refresh_jobs',
              {'blocked_status': 'throttled', 'not_before': next},
              where: 'id = ?', whereArgs: [id]);
          return next;
        }
        // Reserve before the request. Process death/cancellation cannot grant a
        // second runner the same protocol slot, even if no response is received.
        final remaining = rows.single['remaining_requests'] as int?;
        await txn.update(
            'metadata_provider_limits',
            {
              'next_allowed_at':
                  now + (rate == null ? 0 : (60000 / rate).ceil()),
              if (!accessCheck && remaining != null)
                'remaining_requests': remaining - 1
            },
            where: 'provider_id = ?',
            whereArgs: [providerId]);
        await txn.update('metadata_refresh_jobs',
            {'blocked_status': null, 'not_before': null},
            where: 'id = ?', whereArgs: [id]);
        return 0;
      });
      if (slot == -1) {
        await _block(db, id, MetadataLookupStatus.quotaExceeded, null);
        return false;
      }
      if (slot == 0) return !cancel.isCancelled;
      await wait(slot);
    }
    return false;
  }

  Future<void> _observeQuota(
      Database db, String providerId, MetadataQuota? quota, int requestStarted,
      {bool accessConfirmed = false}) async {
    final rate = quota?.maxRequestsPerMinute;
    if (quota == null) return;
    final dailyExhausted = (quota.requestsToday != null &&
            quota.maxRequestsPerDay != null &&
            quota.requestsToday! >= quota.maxRequestsPerDay!) ||
        (quota.unmatchedToday != null &&
            quota.maxUnmatchedPerDay != null &&
            quota.unmatchedToday! >= quota.maxUnmatchedPerDay!);
    // Reset requires a fresh explicit account-status response with complete
    // daily counters. Never guess a local midnight or clear on missing data.
    final resetConfirmed = accessConfirmed &&
        !dailyExhausted &&
        quota.requestsToday != null &&
        quota.maxRequestsPerDay != null &&
        quota.unmatchedToday != null &&
        quota.maxUnmatchedPerDay != null;
    await db.transaction((txn) async {
      final prior = await txn.query('metadata_provider_limits',
          where: 'provider_id = ?', whereArgs: [providerId], limit: 1);
      final declaredNext = requestStarted +
          (rate == null || rate <= 0 ? 0 : (60000 / rate).ceil());
      final previousNext =
          prior.isEmpty ? 0 : prior.single['next_allowed_at'] as int;
      await txn.insert(
          'metadata_provider_limits',
          {
            'provider_id': providerId,
            'requests_per_minute': rate != null && rate >= 0
                ? rate
                : prior.isEmpty
                    ? null
                    : prior.single['requests_per_minute'],
            'max_threads': quota.maxThreads ??
                (prior.isEmpty ? null : prior.single['max_threads']),
            'next_allowed_at':
                declaredNext > previousNext ? declaredNext : previousNext,
            'remaining_requests':
                quota.maxRequestsPerDay != null && quota.requestsToday != null
                    ? (quota.maxRequestsPerDay! - quota.requestsToday!)
                        .clamp(0, quota.maxRequestsPerDay!)
                    : prior.isEmpty
                        ? null
                        : prior.single['remaining_requests'],
            'quota_exhausted': dailyExhausted
                ? 1
                : resetConfirmed
                    ? 0
                    : prior.isEmpty
                        ? 0
                        : prior.single['quota_exhausted'],
            'quota_json': quota.requestsToday != null ||
                    quota.maxRequestsPerDay != null ||
                    quota.unmatchedToday != null ||
                    quota.maxUnmatchedPerDay != null
                ? jsonEncode({
                    'requestsToday': quota.requestsToday,
                    'maxRequestsPerDay': quota.maxRequestsPerDay,
                    'unmatchedToday': quota.unmatchedToday,
                    'maxUnmatchedPerDay': quota.maxUnmatchedPerDay
                  })
                : prior.isEmpty
                    ? null
                    : prior.single['quota_json'],
            'quota_observed_at': quota.requestsToday != null ||
                    quota.maxRequestsPerDay != null ||
                    quota.unmatchedToday != null ||
                    quota.maxUnmatchedPerDay != null
                ? _now().millisecondsSinceEpoch
                : prior.isEmpty
                    ? null
                    : prior.single['quota_observed_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
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
      if (status == MetadataLookupStatus.quotaExceeded) {
        final job = await _job(txn, id);
        await txn.rawInsert('''INSERT INTO metadata_provider_limits
          (provider_id, next_allowed_at, quota_exhausted) VALUES (?, 0, 1)
          ON CONFLICT(provider_id) DO UPDATE SET quota_exhausted = 1''',
            [job['provider_id']]);
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
      CancelToken cancel,
      void Function(Map<String, int>, int) committed,
      {bool matchReview = false}) async {
    final record = result.record;
    final originalBaseScore = record != null &&
        request.baseProviderGameId != null &&
        record.providerGameId == request.baseProviderGameId;
    final valid = result.status != MetadataLookupStatus.matched ||
        (record != null &&
            record.gameId == request.gameId &&
            record.editionId == request.editionId &&
            record.platformId == request.platformId &&
            record.providerId == providerId &&
            record.refreshGeneration == request.refreshGeneration &&
            LibraryStore.hasConsistentProvenance(record) &&
            (record.matchMethod != 'exactRegionalOfficialTitle' ||
                (providerId == 'screenscraper' &&
                    request.region != null &&
                    request.contentTags.length == 1 &&
                    request.contentTags.contains('official') &&
                    request.baseProviderGameId == null &&
                    request.revision?.isNotEmpty != true &&
                    record.matchEvidence['matchingPolicy'] ==
                        'regionalReleaseV1' &&
                    record.matchEvidence['title'] == request.title &&
                    record.matchEvidence['region'] ==
                        (const {
                              'usa': 'us',
                              'japan': 'jp',
                              'japon': 'jp',
                              'europe': 'eu',
                              'world': 'wor'
                            }[request.region?.toLowerCase()] ??
                            request.region?.toLowerCase()))) &&
            (record.matchMethod != 'corroboratedOfficialRelease' ||
                (providerId == 'igdb' &&
                    request.corroboration != null &&
                    jsonEncode(_canonical(record.matchEvidence)) ==
                        jsonEncode(
                            _canonical(request.corroboration!.toJson())))) &&
            (request.verifiedProviderGameId == null ||
                record.providerGameId == request.verifiedProviderGameId) &&
            (request.baseProviderGameId == null ||
                record.providerGameId != request.baseProviderGameId ||
                (providerId == 'igdb' &&
                    record.matchMethod == 'verifiedProviderIdGlobalGame' &&
                    record.providerGameId == request.verifiedProviderGameId)));
    final reviewMatched =
        matchReview && valid && result.status == MetadataLookupStatus.matched;
    final status = !valid
        ? 'invalidResponse'
        : reviewMatched
            ? 'needsReview'
            : result.status.name;
    // A provider's confident lookup is still only an offered identity during
    // explicit correction. It cannot replace cached facts before user selection.
    final candidates = reviewMatched && result.candidates.isEmpty
        ? [
            MetadataLookupCandidate(
                providerGameId: record!.providerGameId,
                platformId: record.platformId,
                titles: record.titles,
                titleMatched: false,
                evidence: record.matchMethod)
          ]
        : result.candidates;
    final store = LibraryStore(_database);
    // Each bounded page commits its metadata and item results together. A crash
    // leaves the remaining page pending, never a done item with missing metadata.
    while (!cancel.isCancelled) {
      final count = await db.transaction((txn) async {
        if (cancel.isCancelled) {
          return (length: 0, counts: <String, int>{}, rated: 0);
        }
        final outcomes = <String, int>{};
        var ratedTotal = 0;
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
          var identity = await _identity(txn, editionId);
          String? committedIdentityKey;
          if (identity == null ||
              LibraryStore.metadataIdentity(identity, providerId: providerId) !=
                  target['identity_key']) {
            outcome = 'identityChanged';
          } else if (outcome == 'matched') {
            final copy = MetadataRecord.fromJson(
                {...record!.toJson(), 'editionId': editionId});
            if (copy.matchMethod == 'corroboratedOfficialRelease') {
              final facts = await _currentCorroboration(txn, identity,
                  matchingPolicy: request.corroboration!.matchingPolicy);
              if (facts == null ||
                  jsonEncode(_canonical(facts.toJson())) !=
                      jsonEncode(_canonical(request.corroboration!.toJson()))) {
                outcome = 'identityChanged';
              }
            }
            if (originalBaseScore) {
              // Revalidate the linked original inside the publication
              // transaction. A shared provider ID alone cannot exempt a hack,
              // contradictory classification or changed base from rejection.
              final game = GameIdentity.fromJson(
                  jsonDecode(identity['game_json'] as String));
              final edition = EditionIdentity.fromJson(
                  jsonDecode(identity['edition_json'] as String));
              final bases = await txn.query('library_game_identities',
                  columns: ['record_json'],
                  where: 'game_id = ?',
                  whereArgs: [game.baseGameId],
                  limit: 1);
              final base = bases.isEmpty
                  ? null
                  : GameIdentity.fromJson(
                      jsonDecode(bases.single['record_json'] as String));
              if (metadataOverallOwnership(game, edition, copy, base) !=
                  OverallRatingOwnership.originalGame) {
                outcome = 'invalidResponse';
              }
            }
            if (outcome == 'matched') {
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
                if (result.officialRomEvidence != null) {
                  final game = GameIdentity.fromJson(
                      jsonDecode(identity['game_json'] as String));
                  final edition = EditionIdentity.fromJson(
                      jsonDecode(identity['edition_json'] as String));
                  final currentRaw =
                      await _rawIdentifier(txn, edition, game.platformId!);
                  final classified = _officialRelease(edition, game, request,
                      copy, result.officialRomEvidence!, currentRaw);
                  if (classified == null) {
                    outcome = 'needsReview';
                  } else {
                    await txn.update('library_editions',
                        {'record_json': jsonEncode(classified.toJson())},
                        where: 'edition_id = ?', whereArgs: [editionId]);
                    identity = (await _identity(txn, editionId))!;
                    committedIdentityKey = LibraryStore.metadataIdentity(
                        identity,
                        providerId: providerId);
                  }
                }
                if (outcome == 'matched') {
                  final shared = await _sharedStore;
                  await shared?.preserve(copy, identity, txn);
                  if (cancel.isCancelled) throw const _RefreshCommitCancelled();
                  await store.putMetadata(copy, transaction: txn);
                  rated = copy.ratings.isEmpty ? 0 : 1;
                }
              }
            }
          }
          await txn.update(
              'metadata_refresh_items',
              {
                'status': outcome,
                'rated': rated,
                if (committedIdentityKey != null)
                  'identity_key': committedIdentityKey,
                'candidates_json': jsonEncode(candidates
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
          outcomes[outcome] = (outcomes[outcome] ?? 0) + 1;
          ratedTotal += rated;
        }
        if (cancel.isCancelled) throw const _RefreshCommitCancelled();
        return (length: rows.length, counts: outcomes, rated: ratedTotal);
      });
      if (count.length != 0) committed(count.counts, count.rated);
      if (count.length < 128) break;
    }
  }

  /// Only this exact provider-ROM response can establish an unclassified
  /// release. Manual classifications, patch/base relationships and changed
  /// catalogue bytes are never overwritten by a provider's ordinary-game facts.
  static EditionIdentity? _officialRelease(
      EditionIdentity edition,
      GameIdentity game,
      MetadataLookupRequest request,
      MetadataRecord record,
      IdentityEvidence evidence,
      MetadataRomIdentifier? currentRaw) {
    final raw = request.romIdentifier;
    if (record.providerId != 'screenscraper' ||
        evidence.source != 'screenscraper' ||
        evidence.kind != 'exactRomOfficialRelease' ||
        !{'rawRomHashAndSize', 'rawRomSha1AndCappedSize'}
            .contains(record.matchMethod) ||
        raw == null ||
        raw.kind == RomIdentifierKind.container ||
        ![raw.md5, raw.sha1]
            .any((hash) => hash != null && !RegExp(r'^0+$').hasMatch(hash)) ||
        currentRaw == null ||
        jsonEncode(currentRaw.toJson()) != jsonEncode(raw.toJson()) ||
        game.baseGameId != null ||
        edition.patchId != null ||
        edition.isTranslation == true ||
        edition.translatedLanguages.isNotEmpty ||
        (edition.tags.isNotEmpty &&
            !(edition.tags.length == 1 && edition.tags.contains('unknown'))) ||
        edition.evidence.any(
            (e) => e.source == 'manual' && e.kind == 'contentClassification')) {
      return null;
    }
    try {
      final facts = jsonDecode(evidence.value);
      const flags = ['hack', 'trad', 'demo', 'unl', 'beta'];
      if (facts is! Map<String, dynamic> ||
          facts['providerGameId'] != record.providerGameId ||
          facts['notgame'] != false ||
          facts['flags'] is! Map ||
          !flags.every((key) => facts['flags'][key] == '0') ||
          facts['retrievedAt'] !=
              record.retrievedAt.toUtc().toIso8601String() ||
          jsonEncode(facts['identifier']) != jsonEncode(raw.toJson())) {
        return null;
      }
      List<String>? codes(String key) {
        final value = facts[key];
        if (value is! List ||
            value.length > 16 ||
            value.any(
                (v) => v is! String || !RegExp(r'^[a-z]{2,3}$').hasMatch(v))) {
          return null;
        }
        return value.cast<String>();
      }

      final regions = codes('regions');
      final languages = codes('languages');
      if (regions == null || languages == null) return null;
      return EditionIdentity.fromJson({
        ...edition.toJson(),
        'tags': ['official'],
        'isTranslation': false,
        'regions': edition.regions.isEmpty ? regions : edition.regions,
        'languages': edition.languages.isEmpty ? languages : edition.languages,
        'evidence': [
          ...edition.evidence.map((e) => e.toJson()),
          IdentityEvidence(
              source: evidence.source,
              kind: evidence.kind,
              value: jsonEncode({
                ...facts,
                'assignedRegions': edition.regions.isEmpty,
                'assignedLanguages': edition.languages.isEmpty
              })).toJson()
        ]
      });
    } on FormatException {
      return null;
    }
  }
}

class _RefreshCommitCancelled implements Exception {
  const _RefreshCommitCancelled();
}
