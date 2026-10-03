import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../models/library_identity.dart';
import '../models/scraped_metadata.dart';

/// Additive v14 schema. Legacy file-keyed cache and anonymous ratings remain
/// untouched; they are not promoted into the fresh identity/metadata namespace.
class LibrarySchema {
  LibrarySchema._();

  static Future<void> install(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS library_game_identities (
      game_id TEXT PRIMARY KEY, platform_id TEXT, title TEXT NOT NULL,
      match_status TEXT NOT NULL, record_json TEXT NOT NULL
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_library_platform
      ON library_game_identities(platform_id, game_id)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS library_editions (
      edition_id TEXT PRIMARY KEY, game_id TEXT NOT NULL, record_json TEXT NOT NULL
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_library_edition_game
      ON library_editions(game_id, edition_id)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS library_artifacts (
      artifact_id TEXT PRIMARY KEY, provider_id TEXT NOT NULL,
      source_id TEXT NOT NULL, account_id TEXT, provider_file_id TEXT NOT NULL,
      record_json TEXT NOT NULL
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_library_artifact_source
      ON library_artifacts(source_id, account_id, artifact_id)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS library_metadata (
      edition_id TEXT NOT NULL, provider_id TEXT NOT NULL,
      provider_game_id TEXT NOT NULL, generation_id INTEGER NOT NULL,
      retrieved_at TEXT NOT NULL, identity_key TEXT NOT NULL, record_json TEXT NOT NULL,
      PRIMARY KEY (edition_id, provider_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS library_canonical_groups (
      edition_id TEXT PRIMARY KEY, group_key TEXT NOT NULL,
      platform_id TEXT, identity_key TEXT NOT NULL
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_library_canonical_group
      ON library_canonical_groups(group_key, edition_id)''');
    await db
        .execute('''CREATE INDEX IF NOT EXISTS idx_library_canonical_platform
      ON library_canonical_groups(platform_id, group_key, edition_id)''');
  }
}

/// Identity persistence independent of file cache eviction and local residency.
/// The normal DatabaseService opens/migrates this database; injecting its future
/// also permits real SQLite tests without a second production database singleton.
class LibraryStore {
  final Future<Database> _database;
  LibraryStore(this._database);

  Future<void> putGame(GameIdentity game) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.insert(
          'library_game_identities',
          {
            'game_id': game.id,
            'platform_id': game.platformId,
            'title': game.title,
            'match_status': game.matchStatus.name,
            'record_json': jsonEncode(game.toJson()),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await indexCanonicalGroups(txn, gameId: game.id);
    });
  }

  Future<void> putEdition(EditionIdentity edition) async {
    final db = await _database;
    await db.transaction((txn) async {
      final game = await txn.query('library_game_identities',
          columns: ['game_id'],
          where: 'game_id = ?',
          whereArgs: [edition.gameId],
          limit: 1);
      if (game.isEmpty) {
        throw StateError('Edition requires a known game identity');
      }
      final existing = await txn.query('library_editions',
          columns: ['game_id'],
          where: 'edition_id = ?',
          whereArgs: [edition.id],
          limit: 1);
      if (existing.isNotEmpty && existing.single['game_id'] != edition.gameId) {
        throw StateError(
            'Edition reassignment requires explicit reconciliation');
      }
      await txn.insert(
          'library_editions',
          {
            'edition_id': edition.id,
            'game_id': edition.gameId,
            'record_json': jsonEncode(edition.toJson()),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await indexCanonicalGroups(txn, editionId: edition.id);
    });
  }

  /// Indexed grouping is a projection, not a destructive identity merge. Exact
  /// editions, patches, members, metadata ownership and transfer state survive.
  /// Rebuild in bounded keyset pages inside the caller's identity transaction.
  static Future<void> indexCanonicalGroups(DatabaseExecutor db,
      {String? gameId, String? editionId}) async {
    String? cursor;
    while (true) {
      final rows = await db.rawQuery('''SELECT e.edition_id,
        e.record_json AS edition_json, g.record_json AS game_json
        FROM library_editions e JOIN library_game_identities g ON g.game_id = e.game_id
        WHERE 1 = 1 ${cursor == null ? '' : 'AND e.edition_id > ?'}
        ${gameId == null ? '' : 'AND e.game_id = ?'}
        ${editionId == null ? '' : 'AND e.edition_id = ?'}
        ORDER BY e.edition_id LIMIT 128''', [
        if (cursor != null) cursor,
        if (gameId != null) gameId,
        if (editionId != null) editionId,
      ]);
      for (final row in rows) {
        final game =
            GameIdentity.fromJson(jsonDecode(row['game_json'] as String));
        final edition =
            EditionIdentity.fromJson(jsonDecode(row['edition_json'] as String));
        await db.insert(
            'library_canonical_groups',
            {
              'edition_id': edition.id,
              'group_key': _canonicalGroupKey(game, edition),
              'platform_id': game.platformId,
              'identity_key': metadataIdentity(row),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (rows.length < 128) break;
      cursor = rows.last['edition_id'] as String;
    }
  }

  static String _canonicalGroupKey(GameIdentity game, EditionIdentity edition) {
    const originalGameModifications = {'T-Eng', 'Dub', 'Undub', 'Uncensor'};
    final official = edition.tags.length == 1 &&
        edition.tags.contains('official') &&
        edition.isTranslation != true;
    final modifiedRelease = edition.tags.isNotEmpty &&
        originalGameModifications.containsAll(edition.tags) &&
        (!edition.tags.contains('T-Eng') ||
            (edition.isTranslation == true &&
                edition.translatedLanguages.contains('en')));
    final verified = game.matchStatus == IdentityMatchStatus.matched ||
        game.matchStatus == IdentityMatchStatus.manuallyMatched;
    // ScreenScraper is the currently implemented identity namespace. A base ID
    // on a hack/homebrew/demo/unknown classification cannot identify its project.
    // Explicit editions of the same project still share their stable game ID.
    final providerGameId = game.providerIds['screenscraper'];
    if (verified &&
        game.platformId != null &&
        providerGameId != null &&
        providerGameId.trim().isNotEmpty &&
        (official || modifiedRelease)) {
      return jsonEncode(
          ['provider-game', game.platformId, 'screenscraper', providerGameId]);
    }
    return jsonEncode(['game', game.id]);
  }

  /// Select exact editions of one canonical game without loading its entire
  /// metadata or artwork. A cursor covers the examined rows, including stale
  /// rows omitted from consumption, so an empty page need not end traversal.
  /// This does not transfer a rating, patch identity or installation ownership.
  Future<({List<EditionIdentity> editions, String? nextEditionId})>
      canonicalEditions(String editionId,
          {String? afterEditionId, int limit = 50}) async {
    if (limit < 1 || limit > 128) {
      throw ArgumentError.value(limit, 'limit', 'Must be within 1..128');
    }
    final db = await _database;
    return db.transaction((txn) async {
      const selection = '''SELECT c.group_key, c.identity_key, c.edition_id,
        g.record_json AS game_json, e.record_json AS edition_json
        FROM library_canonical_groups c
        JOIN library_editions e ON e.edition_id = c.edition_id
        JOIN library_game_identities g ON g.game_id = e.game_id''';
      Future<bool> current(Map<String, Object?> row) async =>
          row['identity_key'] == metadataIdentity(row) &&
          await isCurrentCatalogueIdentity(txn, row);
      final anchor = await txn
          .rawQuery('$selection WHERE c.edition_id = ? LIMIT 1', [editionId]);
      if (anchor.isEmpty || !await current(anchor.single)) {
        return (editions: <EditionIdentity>[], nextEditionId: null);
      }
      final rows = await txn.rawQuery('''$selection WHERE c.group_key = ?
        ${afterEditionId == null ? '' : 'AND c.edition_id > ?'}
        ORDER BY c.edition_id LIMIT ?''', [
        anchor.single['group_key'],
        if (afterEditionId != null) afterEditionId,
        limit,
      ]);
      final editions = <EditionIdentity>[];
      for (final row in rows) {
        if (await current(row)) {
          editions.add(EditionIdentity.fromJson(
              jsonDecode(row['edition_json'] as String)));
        }
      }
      return (
        editions: editions,
        nextEditionId:
            rows.length == limit ? rows.last['edition_id'] as String : null
      );
    });
  }

  Future<void> putArtifact(RemoteArtifact artifact) async {
    final db = await _database;
    await db.insert(
        'library_artifacts',
        {
          'artifact_id': artifact.id.key,
          'provider_id': artifact.id.providerId,
          'source_id': artifact.id.sourceId,
          'account_id': artifact.id.accountId,
          'provider_file_id': artifact.id.providerFileId,
          'record_json': jsonEncode(artifact.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> _record(
      String table, String column, String id) async {
    final db = await _database;
    final rows = await db.query(table,
        columns: ['record_json'],
        where: '$column = ?',
        whereArgs: [id],
        limit: 1);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.single['record_json'] as String)
        as Map<String, dynamic>;
  }

  Future<GameIdentity?> game(String id) async {
    final record = await _record('library_game_identities', 'game_id', id);
    return record == null ? null : GameIdentity.fromJson(record);
  }

  Future<EditionIdentity?> edition(String id) async {
    final record = await _record('library_editions', 'edition_id', id);
    return record == null ? null : EditionIdentity.fromJson(record);
  }

  Future<RemoteArtifact?> artifact(RemoteArtifactId id) async {
    final record = await _record('library_artifacts', 'artifact_id', id.key);
    return record == null ? null : RemoteArtifact.fromJson(record);
  }

  /// Capture the normal app's committed game cache, not historical metadata or
  /// installation residency. The caller holds the snapshot transaction while
  /// consuming this bounded stream and creating its durable refresh items.
  ///
  /// Each unreviewed artifact initially owns a distinct game/edition. A cleaned
  /// name is a search hint, never evidence for merging projects or rating them.
  static Stream<String> catalogueEditions(DatabaseExecutor db,
      {String? systemSlug, int? cacheRowId}) async* {
    var cursor = 0;
    while (true) {
      final rows = await db.query('games',
          columns: [
            'id',
            'systemSlug',
            'displayName',
            'artifact_key',
            'remote_artifact'
          ],
          where: 'id > ? AND is_folder = 0'
              '${systemSlug == null ? '' : ' AND systemSlug = ?'}'
              '${cacheRowId == null ? '' : ' AND id = ?'}',
          whereArgs: [
            cursor,
            if (systemSlug != null) systemSlug,
            if (cacheRowId != null) cacheRowId
          ],
          orderBy: 'id',
          limit: 128);
      for (final row in rows) {
        final artifactJson = row['remote_artifact'] as String?;
        final artifact = artifactJson == null
            ? null
            : RemoteArtifact.fromJson(
                jsonDecode(artifactJson) as Map<String, dynamic>);
        if (row['artifact_key'] != artifact?.id.key) {
          throw StateError('Cached artifact identity is inconsistent');
        }
        final suffix = sha256
            .convert(utf8.encode(jsonEncode([
              row['systemSlug'],
              artifact == null
                  ? ['legacy-cache-row', row['id']]
                  : ['artifact', artifact.id.key],
            ])))
            .toString();
        final gameId = 'catalogue-game:$suffix';
        final editionId = 'catalogue-edition:$suffix';
        final existingGame = await db.query('library_game_identities',
            where: 'game_id = ?', whereArgs: [gameId], limit: 1);
        var game = existingGame.isEmpty
            ? GameIdentity(
                id: gameId,
                platformId: row['systemSlug'] as String,
                title: row['displayName'] as String,
                evidence: [
                  IdentityEvidence(
                      source: 'catalogue',
                      kind: 'artifactIdentity',
                      value:
                          artifact?.id.key ?? 'legacy-cache-row:${row['id']}'),
                  IdentityEvidence(
                      source: 'catalogue',
                      kind: 'system',
                      value: row['systemSlug'] as String)
                ],
              )
            : GameIdentity.fromJson(
                jsonDecode(existingGame.single['record_json'] as String));
        final existingEdition = await db.query('library_editions',
            where: 'edition_id = ?', whereArgs: [editionId], limit: 1);
        var edition = existingEdition.isEmpty
            ? EditionIdentity(
                id: editionId,
                gameId: gameId,
                members: [
                  if (artifact != null) EditionMember(artifactId: artifact.id)
                ],
              )
            : EditionIdentity.fromJson(
                jsonDecode(existingEdition.single['record_json'] as String));
        if (artifact != null) {
          final marker = _artifactContentMarker(artifact);
          final previousMarkers = edition.evidence.where(
              (e) => e.source == 'catalogue' && e.kind == 'artifactContent');
          if (previousMarkers.isNotEmpty &&
              previousMarkers.single.value != marker) {
            // Retain the correction as candidate evidence, but a replaced blob
            // must not silently inherit the old blob's verified provider match.
            game = GameIdentity.fromJson(
                {...game.toJson(), 'matchStatus': 'unmatched'});
          }
          edition = EditionIdentity.fromJson({
            ...edition.toJson(),
            'evidence': [
              ...edition.evidence
                  .where((e) =>
                      !(e.source == 'catalogue' && e.kind == 'artifactContent'))
                  .map((e) => e.toJson()),
              IdentityEvidence(
                      source: 'catalogue',
                      kind: 'artifactContent',
                      value: marker)
                  .toJson(),
            ]
          });
          await db.insert(
              'library_artifacts',
              {
                'artifact_id': artifact.id.key,
                'provider_id': artifact.id.providerId,
                'source_id': artifact.id.sourceId,
                'account_id': artifact.id.accountId,
                'provider_file_id': artifact.id.providerFileId,
                'record_json': jsonEncode(artifact.toJson()),
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await db.insert(
            'library_game_identities',
            {
              'game_id': game.id,
              'platform_id': game.platformId,
              'title': game.title,
              'match_status': game.matchStatus.name,
              'record_json': jsonEncode(game.toJson()),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        await db.insert(
            'library_editions',
            {
              'edition_id': edition.id,
              'game_id': edition.gameId,
              'record_json': jsonEncode(edition.toJson()),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        await indexCanonicalGroups(db, editionId: edition.id);
        yield editionId;
      }
      if (rows.length < 128) break;
      cursor = rows.last['id'] as int;
    }
  }

  static String _artifactContentMarker(RemoteArtifact artifact) {
    final algorithms = artifact.providerChecksums.keys.toList()..sort();
    return sha256
        .convert(utf8.encode(jsonEncode([
          artifact.sizeBytes,
          // A provider metadata/version change can be a pure rename. Known hashes
          // establish equal bytes; use version/time only without that evidence.
          if (algorithms.isEmpty)
            artifact.version ?? artifact.modifiedAt?.toIso8601String(),
          {
            for (final algorithm in algorithms)
              algorithm: artifact.providerChecksums[algorithm]
          },
        ])))
        .toString();
  }

  /// Refresh only the selected retry member from its exact current cache row.
  /// Explicit identities do not depend on the file cache. Removed catalogue
  /// members remain invalid and will receive an identityChanged retry outcome.
  static Future<void> refreshCatalogueEdition(
      DatabaseExecutor db, String editionId) async {
    final identities =
        await db.rawQuery('''SELECT g.record_json FROM library_editions e
      JOIN library_game_identities g ON g.game_id = e.game_id
      WHERE e.edition_id = ? LIMIT 1''', [editionId]);
    if (identities.isEmpty) return;
    final game = GameIdentity.fromJson(
        jsonDecode(identities.single['record_json'] as String));
    final keys = game.evidence
        .where((e) => e.source == 'catalogue' && e.kind == 'artifactIdentity');
    final systems = game.evidence
        .where((e) => e.source == 'catalogue' && e.kind == 'system');
    if (keys.length != 1 || systems.length != 1) return;
    final key = keys.single.value;
    final legacyId = key.startsWith('legacy-cache-row:')
        ? int.tryParse(key.substring('legacy-cache-row:'.length))
        : null;
    final rows = await db.query('games',
        columns: ['id'],
        where:
            'systemSlug = ? AND is_folder = 0 AND ${legacyId == null ? 'artifact_key = ?' : 'id = ? AND artifact_key IS NULL'}',
        whereArgs: [systems.single.value, legacyId ?? key],
        limit: 2);
    if (rows.length != 1) return;
    await for (final captured
        in catalogueEditions(db, cacheRowId: rows.single['id'] as int)) {
      if (captured != editionId) {
        throw StateError('Catalogue retry identity is inconsistent');
      }
    }
  }

  /// A saved scrape snapshot is evidence about those bytes, not permission to
  /// attach results to a removed/replaced object. Called again inside result
  /// publication's transaction, so catalogue changes during HTTP are detected.
  static Future<bool> isCurrentCatalogueIdentity(
      DatabaseExecutor db, Map<String, Object?> row) async {
    final game = GameIdentity.fromJson(jsonDecode(row['game_json'] as String));
    final catalogueKeys = game.evidence
        .where((e) => e.source == 'catalogue' && e.kind == 'artifactIdentity');
    if (catalogueKeys.isEmpty) {
      return true; // Explicit non-catalogue identities.
    }
    if (catalogueKeys.length != 1) return false;
    final systems = game.evidence
        .where((e) => e.source == 'catalogue' && e.kind == 'system');
    if (systems.length != 1) return false;
    final key = catalogueKeys.single.value;
    if (key.startsWith('legacy-cache-row:')) {
      final id = int.tryParse(key.substring('legacy-cache-row:'.length));
      if (id == null) return false;
      return (await db.query('games',
              columns: ['id'],
              where:
                  'id = ? AND systemSlug = ? AND is_folder = 0 AND artifact_key IS NULL',
              whereArgs: [id, systems.single.value],
              limit: 1))
          .isNotEmpty;
    }
    final records = await db.query('games',
        columns: ['remote_artifact'],
        where: 'systemSlug = ? AND artifact_key = ? AND is_folder = 0',
        whereArgs: [systems.single.value, key],
        limit: 2);
    if (records.length != 1 || records.single['remote_artifact'] == null) {
      return false;
    }
    final artifact = RemoteArtifact.fromJson(
        jsonDecode(records.single['remote_artifact'] as String));
    if (artifact.id.key != key) return false;
    final edition =
        EditionIdentity.fromJson(jsonDecode(row['edition_json'] as String));
    final markers = edition.evidence
        .where((e) => e.source == 'catalogue' && e.kind == 'artifactContent');
    return markers.length == 1 &&
        markers.single.value == _artifactContentMarker(artifact);
  }

  Future<void> putMetadata(MetadataRecord record,
      {Transaction? transaction}) async {
    if (!hasConsistentProvenance(record)) {
      throw StateError('Metadata provenance is inconsistent');
    }
    Future<void> write(Transaction txn) async {
      final identities = await txn.rawQuery('''
        SELECT g.platform_id, g.record_json AS game_json, e.record_json AS edition_json
        FROM library_editions e
        JOIN library_game_identities g ON g.game_id = e.game_id
        WHERE e.edition_id = ? AND e.game_id = ?
      ''', [record.editionId, record.gameId]);
      if (identities.isEmpty ||
          identities.single['platform_id'] != record.platformId) {
        throw StateError(
            'Metadata requires matching game, edition and platform');
      }
      final game = GameIdentity.fromJson(
          jsonDecode(identities.single['game_json'] as String)
              as Map<String, dynamic>);
      final assignedProviderId = game.providerIds[record.providerId];
      if (assignedProviderId != null &&
          assignedProviderId != record.providerGameId) {
        throw StateError(
            'Metadata cannot replace an assigned provider identity');
      }
      final previous = await txn.query('library_metadata',
          columns: ['generation_id'],
          where: 'edition_id = ? AND provider_id = ?',
          whereArgs: [record.editionId, record.providerId],
          limit: 1);
      if (previous.isNotEmpty &&
          (previous.single['generation_id'] as int) >
              record.refreshGeneration) {
        throw StateError(
            'A stale metadata generation cannot replace a newer one');
      }
      await txn.insert(
          'library_metadata',
          {
            'edition_id': record.editionId,
            'provider_id': record.providerId,
            'provider_game_id': record.providerGameId,
            'generation_id': record.refreshGeneration,
            'retrieved_at': record.retrievedAt.toUtc().toIso8601String(),
            'identity_key': metadataIdentity(identities.single,
                providerId: record.providerId),
            'record_json': jsonEncode(record.toJson()),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    if (transaction != null) {
      await write(transaction);
    } else {
      final db = await _database;
      await db.transaction(write);
    }
  }

  static bool hasConsistentProvenance(MetadataRecord record) =>
      record.providerId.trim().isNotEmpty &&
      record.providerGameId.trim().isNotEmpty &&
      record.refreshGeneration >= 0 &&
      record.ratings.every((rating) =>
          rating.sourceId == record.providerId &&
          rating.providerGameId == record.providerGameId) &&
      record.fieldProvenance.entries.every((entry) =>
          entry.value.providerId == record.providerId &&
          entry.value.providerGameId == record.providerGameId &&
          entry.key == entry.value.field &&
          entry.key.trim().isNotEmpty);

  Future<MetadataRecord?> metadata(String editionId, String providerId) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT m.record_json, m.identity_key, g.record_json AS game_json,
        e.record_json AS edition_json
      FROM library_metadata m
      JOIN library_editions e ON e.edition_id = m.edition_id
      JOIN library_game_identities g ON g.game_id = e.game_id
      WHERE m.edition_id = ? AND m.provider_id = ? LIMIT 1
    ''', [editionId, providerId]);
    if (rows.isEmpty) return null;
    if (rows.single['identity_key'] !=
        metadataIdentity(rows.single, providerId: providerId)) {
      return null;
    }
    if (!await isCurrentCatalogueIdentity(db, rows.single)) return null;
    return MetadataRecord.fromJson(
        jsonDecode(rows.single['record_json'] as String)
            as Map<String, dynamic>);
  }

  /// Metadata stays stored as evidence, but cannot be consumed under a changed
  /// game/edition/patch identity. Display-name-only renames are not identity edits.
  static String metadataIdentity(Map<String, Object?> row,
      {String? providerId}) {
    final game = jsonDecode(row['game_json'] as String) as Map<String, dynamic>;
    game.remove('title');
    final edition =
        jsonDecode(row['edition_json'] as String) as Map<String, dynamic>;
    if (providerId == null) {
      // Canonical grouping and pre-v26 records retain the full identity key.
      return sha256
          .convert(utf8.encode(jsonEncode([game, edition])))
          .toString();
    }
    if (providerId.trim().isEmpty) {
      throw ArgumentError.value(providerId, 'providerId');
    }
    for (final identity in [game, edition]) {
      final ids = identity['providerIds'] as Map<String, dynamic>? ?? {};
      identity['providerIds'] = {
        if (ids.containsKey(providerId)) providerId: ids[providerId]
      };
      // Only an explicit provider-ID assertion is source-scoped. Raw-ROM,
      // release, classification, platform, artifact and other evidence remain
      // bound; unknown/malformed assertions must not be silently discarded.
      identity['evidence'] =
          (identity['evidence'] as List? ?? []).where((value) {
        final evidence = value as Map<String, dynamic>;
        if (evidence['source'] != 'manual' ||
            evidence['kind'] != 'providerId') {
          return true;
        }
        try {
          final asserted = jsonDecode(evidence['value'] as String);
          if (asserted is List &&
              asserted.length == 2 &&
              asserted[0] is String &&
              asserted[1] is String &&
              (asserted[0] as String).trim().isNotEmpty &&
              (asserted[1] as String).trim().isNotEmpty) {
            return asserted[0] == providerId;
          }
        } on FormatException {
          // Preserve uncertain evidence in the binding.
        }
        return true;
      }).toList();
    }
    return sha256
        .convert(utf8.encode(
            jsonEncode(['metadata-owner-v1', providerId, game, edition])))
        .toString();
  }

  /// v26 migrates only bindings which still prove their complete old identity.
  /// Stale records remain stored but unusable. Work items and image ownership
  /// move with their provider, preserving generation/selector/request/offset.
  /// The production upgrade transaction owns these bounded keyset pages.
  static Future<void> migrateMetadataOwnership(DatabaseExecutor db) async {
    for (final table in [
      'library_metadata',
      'metadata_refresh_items',
      'metadata_artwork_items'
    ]) {
      final metadata = table == 'library_metadata';
      var cursor = 0;
      while (true) {
        final rows = await db.rawQuery('''SELECT m.rowid AS binding_rowid,
          m.identity_key, ${metadata ? 'm' : 'j'}.provider_id,
          g.record_json AS game_json, e.record_json AS edition_json
          FROM $table m
          ${metadata ? '' : 'JOIN metadata_refresh_jobs j ON j.id = m.job_id'}
          JOIN library_editions e ON e.edition_id = m.edition_id
          JOIN library_game_identities g ON g.game_id = e.game_id
          WHERE m.rowid > ? ORDER BY m.rowid LIMIT 128''', [cursor]);
        for (final row in rows) {
          if (row['identity_key'] != metadataIdentity(row) ||
              !await isCurrentCatalogueIdentity(db, row)) {
            continue;
          }
          await db.update(
              table,
              {
                'identity_key': metadataIdentity(row,
                    providerId: row['provider_id'] as String)
              },
              where: 'rowid = ? AND identity_key = ?',
              whereArgs: [row['binding_rowid'], row['identity_key']]);
        }
        if (rows.length < 128) break;
        cursor = rows.last['binding_rowid'] as int;
      }
    }
  }
}
