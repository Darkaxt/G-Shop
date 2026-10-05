import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/library_identity.dart';
import '../../models/scraped_metadata.dart';
import '../library_store.dart';
import 'effective_overall_rating.dart';
import 'metadata_artwork_cache.dart';
import 'metadata_provider.dart';
import 'shared_metadata_store.dart';

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
      this.providerId = ''});
}

class MetadataReviewItem {
  final int jobId;
  final String editionId;
  final String status;
  final List<MetadataLookupCandidate> candidates;
  final MetadataLookupRequest? request;
  final bool identityCurrent;
  const MetadataReviewItem(
      {required this.jobId,
      required this.editionId,
      required this.status,
      required this.candidates,
      this.request,
      this.identityCurrent = true});
}

class MetadataRefreshJobs {
  final Future<Database> _database;
  final Future<SharedMetadataStore?>? _sharedStore;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _schedule;
  Future<MetadataRefreshReport>? _active;
  CancelToken? _cancel;
  MetadataRefreshJobs(this._database,
      {DateTime Function()? now,
      Future<SharedMetadataStore?>? sharedStore,
      Timer Function(Duration, void Function())? schedule})
      : _sharedStore = sharedStore,
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
    await installMatchReviewMode(db);
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
        final request = game.platformId == null
            ? null
            : MetadataLookupRequest(
                gameId: game.id,
                editionId: edition.id,
                platformId: game.platformId!,
                title: game.title,
                verifiedProviderGameId: !matchReview &&
                        {
                          IdentityMatchStatus.matched,
                          IdentityMatchStatus.manuallyMatched
                        }.contains(game.matchStatus)
                    ? game.providerIds[providerId]
                    : null,
                baseProviderGameId: matchReview ? null : baseProviderId,
                contentTags: edition.tags,
                region:
                    edition.regions.length == 1 ? edition.regions.single : null,
                language: edition.languages.length == 1
                    ? edition.languages.single
                    : null,
                revision: edition.revision,
                romIdentifier: matchReview ? null : _rawIdentifier(edition),
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

  /// Explicit compatible ROM evidence, not a provider-file/container checksum.
  /// The edition binding preserves this assertion through lookup/publication.
  /// Conflicting or malformed assertions leave title discovery for review; the
  /// adapter still checks kind, filename, hash syntax, size and returned hash.
  static MetadataRomIdentifier? _rawIdentifier(EditionIdentity edition) {
    final evidence = edition.evidence
        .where((item) => item.kind == 'rawRomIdentifier')
        .toList(growable: false);
    if (evidence.length != 1) return null;
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
            identityCurrent: current != null &&
                row['identity_key'] ==
                    LibraryStore.metadataIdentity(current,
                        providerId: providerId)));
      }
      return List.unmodifiable(items);
    });
  }

  static MetadataReviewItem _reviewItem(Map<String, Object?> row,
          {bool identityCurrent = true}) =>
      MetadataReviewItem(
        jobId: row['job_id'] as int,
        editionId: row['edition_id'] as String,
        status: row['status'] as String,
        identityCurrent: identityCurrent,
        candidates:
            List.unmodifiable(_candidates(row['candidates_json'] as String?)),
        request: row['request_json'] == null
            ? null
            : MetadataLookupRequest.fromJson(
                jsonDecode(row['request_json'] as String)
                    as Map<String, dynamic>),
      );

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
      required Set<String> contentTags}) async {
    final classification = EditionIdentity.normalizeContentTags(contentTags);
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
                      e.kind == 'contentClassification'))
                  .map((e) => e.toJson()),
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
        final item = next.single;
        final request = MetadataLookupRequest.fromJson(
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
        if (_blocking.contains(result.status)) {
          await _block(db, id, result.status, result.retryAfter);
          return await report(id);
        }
        await _commitResult(
            db, id, item, request, result, provider.providerId, cancel, publish,
            matchReview: matchReview);
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
          final identity = await _identity(txn, editionId);
          if (identity == null ||
              LibraryStore.metadataIdentity(identity, providerId: providerId) !=
                  target['identity_key']) {
            outcome = 'identityChanged';
          } else if (outcome == 'matched') {
            final copy = MetadataRecord.fromJson(
                {...record!.toJson(), 'editionId': editionId});
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
                final shared = await _sharedStore;
                await shared?.preserve(copy, identity, txn);
                if (cancel.isCancelled) throw const _RefreshCommitCancelled();
                await store.putMetadata(copy, transaction: txn);
                rated = copy.ratings.isEmpty ? 0 : 1;
              }
            }
          }
          await txn.update(
              'metadata_refresh_items',
              {
                'status': outcome,
                'rated': rated,
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
}

class _RefreshCommitCancelled implements Exception {
  const _RefreshCommitCancelled();
}
