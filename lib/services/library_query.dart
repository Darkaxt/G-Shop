import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../models/library_identity.dart';
import '../models/game_metadata_info.dart';
import '../models/scraped_metadata.dart';
import 'library_store.dart';

import 'metadata/effective_overall_rating.dart';
import 'metadata/metadata_artwork_cache.dart';

/// File identity shared by cached covers and discovery, never a cleaned title.
String coverRatingKey(String systemSlug, String selectionKey) =>
    jsonEncode([systemSlug, selectionKey]);

/// Console IDs define ranking scope. All other constraints intersect it later.
class LibraryQueryFilter {
  final Set<String> platformIds, tags, genres, regions, languages, viewIds;
  final bool matchAllTags, ratingOrder, includeVariants;
  final int? top;
  final String? search, manualViewId;
  final int limit, offset;
  LibraryQueryFilter(
      {Set<String> platformIds = const {},
      Set<String> tags = const {},
      Set<String> genres = const {},
      Set<String> regions = const {},
      Set<String> languages = const {},
      Set<String> viewIds = const {},
      this.matchAllTags = false,
      this.ratingOrder = false,
      this.includeVariants = false,
      this.top,
      this.search,
      this.manualViewId,
      this.limit = 50,
      this.offset = 0})
      : platformIds = Set.unmodifiable(platformIds),
        tags = EditionIdentity.normalizeContentTags(tags),
        genres = Set.unmodifiable(genres),
        regions = Set.unmodifiable(regions),
        languages = Set.unmodifiable(languages),
        viewIds = Set.unmodifiable(viewIds);
}

class LibraryQueryItem {
  final String editionId, gameId, groupKey, platformId, title;
  final int cacheRowId;
  final int? rank;
  final EffectiveOverallRating? score;
  const LibraryQueryItem(
      {required this.editionId,
      required this.gameId,
      required this.groupKey,
      required this.platformId,
      required this.title,
      required this.cacheRowId,
      required this.rank,
      required this.score});
}

class LibraryQueryPage {
  final List<LibraryQueryItem> items;
  final int collectionGames, rankedGames, totalMatches;
  bool get provisional => rankedGames < collectionGames;
  LibraryQueryPage(
      {required List<LibraryQueryItem> items,
      required this.collectionGames,
      required this.rankedGames,
      required this.totalMatches})
      : items = List.unmodifiable(items);
}

/// Lightweight UI identities only; metadata/artwork stay in the paged cache.
class LibraryDiscoveryResult {
  final Map<String, List<String>> groups;
  final List<String> genres;
  final int collectionGames, rankedGames, totalMatches;
  bool get provisional => rankedGames < collectionGames;
  LibraryDiscoveryResult(
      {required Map<String, List<String>> groups,
      required List<String> genres,
      required this.collectionGames,
      required this.rankedGames,
      required this.totalMatches})
      : groups = Map.unmodifiable(
            groups.map((k, v) => MapEntry(k, List<String>.unmodifiable(v)))),
        genres = List.unmodifiable(genres);
}

class LibraryQuery {
  final Future<Database> _database;
  LibraryQuery(this._database);
  static int _viewSequence = 0;

  /// Rebuildable facts only. No ratings approval, Top membership, artwork or
  /// authoritative favorite/shelf/install state is persisted here.
  static Future<void> install(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS library_query_editions (
      edition_id TEXT PRIMARY KEY, game_id TEXT NOT NULL, base_game_id TEXT,
      group_key TEXT NOT NULL, platform_id TEXT NOT NULL, title TEXT NOT NULL,
      cache_row_id INTEGER, catalogue_key TEXT, legacy_row_id INTEGER,
      member INTEGER NOT NULL, score REAL, source_order INTEGER,
      rating_eligible INTEGER NOT NULL)''');
    for (final entry in {
      'scope': 'member, platform_id, group_key, edition_id',
      'rank': 'member, rating_eligible, score DESC, group_key, edition_id',
      'game': 'game_id, edition_id',
      'base': 'base_game_id, edition_id',
      'cache': 'cache_row_id, edition_id',
      'catalogue': 'platform_id, catalogue_key, edition_id',
      'legacy': 'legacy_row_id, edition_id'
    }.entries) {
      await db
          .execute('CREATE INDEX IF NOT EXISTS idx_library_query_${entry.key} '
              'ON library_query_editions(${entry.value})');
    }
    await db.execute('''CREATE TABLE IF NOT EXISTS library_query_facets (
      edition_id TEXT NOT NULL, dimension TEXT NOT NULL, value TEXT NOT NULL,
      PRIMARY KEY (edition_id, dimension, value))''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_library_query_facet
      ON library_query_facets(dimension, value, edition_id)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS library_query_dirty (
      edition_id TEXT PRIMARY KEY)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS library_query_cache_dirty (
      cache_row_id INTEGER PRIMARY KEY)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS library_query_policy (
      id INTEGER PRIMARY KEY CHECK(id = 1), fingerprint TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS library_query_views (
      view_id TEXT NOT NULL, edition_id TEXT NOT NULL, position INTEGER NOT NULL,
      PRIMARY KEY (view_id, edition_id))''');
    await db
        .execute('''CREATE INDEX IF NOT EXISTS idx_library_query_view_edition
      ON library_query_views(edition_id, view_id, position)''');
    await installInvalidationTriggers(db);
    // Upgrade retains original facts. Its first ordinary query rebuilds pages.
    await db.execute('''INSERT OR IGNORE INTO library_query_dirty
      SELECT edition_id FROM library_editions''');
    await db.execute('''INSERT OR IGNORE INTO library_query_cache_dirty
      SELECT id FROM games WHERE is_folder = 0''');
  }

  /// Replace only our invalidation triggers, preserving facts and pending work.
  /// An outer UPSERT/OR ABORT overrides a trigger's OR IGNORE policy. Avoid the
  /// duplicate insert itself instead; SQL executes these indexed guards within
  /// the owning write transaction, including OLD/NEW and overlapping bindings.
  static Future<void> installInvalidationTriggers(DatabaseExecutor db) async {
    String markEditions(String selection) => '''INSERT INTO library_query_dirty
      SELECT edition_id FROM ($selection) AS affected WHERE NOT EXISTS
      (SELECT 1 FROM library_query_dirty AS dirty
       WHERE dirty.edition_id = affected.edition_id);''';
    for (final table in [
      'library_editions',
      'library_metadata',
      'library_canonical_groups',
      'metadata_refresh_items'
    ]) {
      for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
        final name = 'query_${table}_${event.toLowerCase()}';
        await db.execute('DROP TRIGGER IF EXISTS $name');
        await db.execute('''CREATE TRIGGER $name
          AFTER $event ON $table BEGIN
          ${event == 'INSERT' ? '' : markEditions('SELECT OLD.edition_id AS edition_id')}
          ${event == 'DELETE' ? '' : markEditions('SELECT NEW.edition_id AS edition_id')}
          END''');
      }
    }
    for (final event in ['UPDATE', 'DELETE']) {
      final name = 'query_game_${event.toLowerCase()}';
      await db.execute('DROP TRIGGER IF EXISTS $name');
      await db.execute('''CREATE TRIGGER $name
        AFTER $event ON library_game_identities BEGIN
          ${markEditions('SELECT edition_id FROM library_editions WHERE game_id = OLD.game_id')}
          ${markEditions('SELECT edition_id FROM library_query_editions WHERE base_game_id = OLD.game_id')}
        END''');
    }
    for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
      final references = [
        if (event != 'INSERT') 'OLD',
        if (event != 'DELETE') 'NEW'
      ];
      final name = 'query_cache_${event.toLowerCase()}';
      await db.execute('DROP TRIGGER IF EXISTS $name');
      await db.execute('''CREATE TRIGGER $name
        AFTER $event ON games BEGIN
        ${references.map((ref) => '''INSERT INTO library_query_cache_dirty
          SELECT $ref.id WHERE NOT EXISTS (SELECT 1 FROM library_query_cache_dirty
            WHERE cache_row_id = $ref.id);
          ${markEditions('SELECT edition_id FROM library_query_editions WHERE cache_row_id = $ref.id')}
          ${markEditions('SELECT edition_id FROM library_query_editions WHERE legacy_row_id = $ref.id')}
          ${markEditions('SELECT edition_id FROM library_query_editions WHERE platform_id = $ref.systemSlug AND catalogue_key = $ref.artifact_key')}
          ''').join('\n')}
        END''');
    }
    await db.execute('DROP TRIGGER IF EXISTS query_refresh_owner');
    await db.execute('''CREATE TRIGGER query_refresh_owner
      AFTER UPDATE OF provider_id, generation, is_artwork ON metadata_refresh_jobs
      BEGIN ${markEditions('SELECT edition_id FROM metadata_refresh_items WHERE job_id = NEW.id')} END''');
    await db.execute('DROP TRIGGER IF EXISTS query_refresh_delete');
    await db.execute('''CREATE TRIGGER query_refresh_delete
      BEFORE DELETE ON metadata_refresh_jobs
      BEGIN ${markEditions('SELECT edition_id FROM metadata_refresh_items WHERE job_id = OLD.id')} END''');
  }

  /// S5 supplies exact edition membership from existing favorite/install/shelf
  /// owners. This bridge does not mutate those owners or establish collection
  /// membership. Manual order is preserved unless rating order is requested.
  Future<void> replaceViewMembers(
      String viewId, Iterable<String> editionIds) async {
    if (viewId.trim().isEmpty) throw ArgumentError('Empty view identity');
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('library_query_views',
          where: 'view_id = ?', whereArgs: [viewId]);
      var position = 0;
      var batch = txn.batch();
      for (final id in editionIds) {
        if (id.trim().isEmpty) throw ArgumentError('Empty edition identity');
        batch.insert('library_query_views',
            {'view_id': viewId, 'edition_id': id, 'position': position++},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        if (position % 128 == 0) {
          await batch.commit(noResult: true);
          batch = txn.batch();
        }
      }
      await batch.commit(noResult: true);
    });
  }

  /// Bind the existing UI's favorite/install/search/shelf intersection after
  /// ranking. Cache and edition ambiguity is rejected, not resolved by title.
  /// Positions are presentation order, not ownership or persisted Top lists.
  Future<Map<int, String>> replaceViewCacheMembers(
      String viewId, List<String> orderedKeys,
      {Set<String> platformIds = const {},
      List<AssessedOverallScoreBasis>? assessedBases}) async {
    if (viewId.trim().isEmpty || platformIds.length > 64) {
      throw ArgumentError('Invalid view/scope');
    }
    final db = await _database;
    return db.transaction((txn) => _bindCacheView(txn, viewId, orderedKeys,
        platformIds, assessedBases ?? productionOverallScoreBases));
  }

  static Future<Map<int, String>> _bindCacheView(
      DatabaseExecutor txn,
      String viewId,
      List<String> orderedKeys,
      Set<String> platformIds,
      List<AssessedOverallScoreBasis> bases) async {
    final positions = <String, int>{};
    for (var i = 0; i < orderedKeys.length; i++) {
      positions.putIfAbsent(orderedKeys[i], () => i);
    }
    await _refresh(txn, bases);
    await txn.delete('library_query_views',
        where: 'view_id = ?', whereArgs: [viewId]);
    final bindings = <int, String>{};
    final seen = <String, int>{};
    var cursor = 0;
    while (true) {
      final rows = await txn.rawQuery('''SELECT g.id, g.systemSlug,
          g.filename, g.artifact_key, MIN(e.edition_id) AS edition_id,
          COUNT(e.edition_id) AS editions
          FROM games g LEFT JOIN library_query_editions e
            ON e.cache_row_id = g.id AND e.member = 1
          WHERE g.id > ? AND g.is_folder = 0
          ${platformIds.isEmpty ? '' : 'AND g.systemSlug IN (${List.filled(platformIds.length, '?').join(',')})'}
          GROUP BY g.id ORDER BY g.id LIMIT 128''', [cursor, ...platformIds]);
      if (rows.isEmpty) break;
      final batch = txn.batch();
      for (final row in rows) {
        final artifact = row['artifact_key'] as String?;
        final key = coverRatingKey(
            row['systemSlug'] as String,
            artifact == null
                ? row['filename'] as String
                : 'artifact:$artifact');
        final position = positions[key];
        if (position == null) continue;
        if (seen.containsKey(key)) {
          bindings.remove(seen[key]);
          batch.delete('library_query_views',
              where: 'view_id = ? AND position = ?',
              whereArgs: [viewId, position]);
          continue;
        }
        seen[key] = row['id'] as int;
        if (row['editions'] != 1) continue;
        bindings[row['id'] as int] = key;
        batch.insert('library_query_views', {
          'view_id': viewId,
          'edition_id': row['edition_id'],
          'position': position
        });
      }
      await batch.commit(noResult: true);
      cursor = rows.last['id'] as int;
      if (rows.length < 128) break;
    }
    return Map<int, String>.unmodifiable(bindings);
  }

  /// One SQLite snapshot bridges both console and library UI intersections.
  /// The temporary membership never changes favorites, installs or shelves.
  Future<LibraryDiscoveryResult?> discover(
      {required LibraryQueryFilter filter,
      required List<String> orderedKeys,
      required bool Function() isCurrent,
      bool preserveOrder = false,
      List<AssessedOverallScoreBasis>? assessedBases}) async {
    _validate(filter);
    final db = await _database;
    final bases = assessedBases ?? productionOverallScoreBases;
    final view = 'ui-discovery:${++_viewSequence}';
    return db.transaction((txn) async {
      if (!isCurrent()) return null;
      final bindings = await _bindCacheView(
          txn, view, orderedKeys, filter.platformIds, bases);
      try {
        final groups = <String, List<String>>{};
        LibraryQueryPage? coverage;
        var offset = 0;
        while (isCurrent()) {
          final page = await _page(
              txn,
              LibraryQueryFilter(
                  platformIds: filter.platformIds,
                  tags: filter.tags,
                  genres: filter.genres,
                  regions: filter.regions,
                  languages: filter.languages,
                  matchAllTags: filter.matchAllTags,
                  ratingOrder: filter.ratingOrder,
                  top: filter.top,
                  search: filter.search,
                  viewIds: {...filter.viewIds, view},
                  manualViewId: preserveOrder ? view : null,
                  includeVariants: true,
                  limit: 128,
                  offset: offset),
              bases);
          coverage = page;
          for (final item in page.items) {
            final key = bindings[item.cacheRowId];
            if (key != null) {
              groups.putIfAbsent(item.groupKey, () => []).add(key);
            }
          }
          if (page.items.length < 128) break;
          offset += page.items.length;
        }
        if (!isCurrent() || coverage == null) return null;
        final genres = await _genres(txn, filter.platformIds);
        return LibraryDiscoveryResult(
            groups: groups,
            genres: genres,
            collectionGames: coverage.collectionGames,
            rankedGames: coverage.rankedGames,
            totalMatches: coverage.totalMatches);
      } finally {
        await txn.delete('library_query_views',
            where: 'view_id = ?', whereArgs: [view]);
      }
    });
  }

  Future<List<String>> genres({Set<String> platformIds = const {}}) async {
    final db = await _database;
    return db.transaction((txn) async {
      await _refresh(txn, productionOverallScoreBases);
      return _genres(txn, platformIds);
    });
  }

  static Future<List<String>> _genres(
      DatabaseExecutor txn, Set<String> platformIds) async {
    final rows = await txn.rawQuery('''SELECT DISTINCT f.value
          FROM library_query_facets f JOIN library_query_editions e
            ON e.edition_id = f.edition_id
          WHERE f.dimension = 'genre' AND e.member = 1
          ${platformIds.isEmpty ? '' : 'AND e.platform_id IN (${List.filled(platformIds.length, '?').join(',')})'}
          ORDER BY f.value LIMIT 128''', platformIds.toList());
    return List.unmodifiable(rows.map((r) => r['value'] as String));
  }

  static String _policy(List<AssessedOverallScoreBasis> bases) => sha256
      .convert(utf8.encode(jsonEncode(bases
          .map((b) => [
                b.sourceId,
                b.kind.name,
                b.scaleMinimum,
                b.scaleMaximum,
                b.platformIds.toList()..sort(),
                b.minimumVoteCount,
                b.assessmentReference,
                b.unknownCountAssessment
              ])
          .toList())))
      .toString();

  static Future<void> _refresh(
      DatabaseExecutor db, List<AssessedOverallScoreBasis> bases) async {
    // A newly indexed file is collection membership even before it is scraped.
    // Capture only committed cache changes, not the whole catalogue per filter.
    while (true) {
      final changed = await db.query('library_query_cache_dirty',
          orderBy: 'cache_row_id', limit: 128);
      if (changed.isEmpty) break;
      for (final row in changed) {
        final id = row['cache_row_id'] as int;
        await for (final _
            in LibraryStore.catalogueEditions(db, cacheRowId: id)) {}
        await db.delete('library_query_cache_dirty',
            where: 'cache_row_id = ?', whereArgs: [id]);
      }
    }
    final fingerprint = _policy(bases);
    final policies = await db.query('library_query_policy', where: 'id = 1');
    if (policies.isEmpty || policies.single['fingerprint'] != fingerprint) {
      await db.insert(
          'library_query_policy', {'id': 1, 'fingerprint': fingerprint},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await db.execute('''INSERT OR IGNORE INTO library_query_dirty
        SELECT edition_id FROM library_editions''');
    }
    while (true) {
      final rows = await db.rawQuery('''SELECT d.edition_id,
        e.record_json AS edition_json, g.record_json AS game_json,
        c.group_key, c.identity_key AS group_identity
        FROM library_query_dirty d
        LEFT JOIN library_editions e ON e.edition_id = d.edition_id
        LEFT JOIN library_game_identities g ON g.game_id = e.game_id
        LEFT JOIN library_canonical_groups c ON c.edition_id = d.edition_id
        ORDER BY d.edition_id LIMIT 128''');
      if (rows.isEmpty) return;
      final ids = rows.map((r) => r['edition_id'] as String).toList();
      final games = <String, GameIdentity>{};
      final baseIds = <String>{};
      for (final row in rows) {
        if (row['game_json'] == null) continue;
        final game =
            GameIdentity.fromJson(jsonDecode(row['game_json'] as String));
        games[row['edition_id'] as String] = game;
        if (game.baseGameId != null) baseIds.add(game.baseGameId!);
      }
      final baseGames = <String, GameIdentity>{};
      if (baseIds.isNotEmpty) {
        final baseRows = await db.query('library_game_identities',
            columns: ['record_json'],
            where: 'game_id IN (${List.filled(baseIds.length, '?').join(',')})',
            whereArgs: baseIds.toList());
        for (final row in baseRows) {
          final game =
              GameIdentity.fromJson(jsonDecode(row['record_json'] as String));
          baseGames[game.id] = game;
        }
      }
      final ratings = await LibraryStore.readEffectiveRatings(db, ids,
          assessedBases: bases);
      final records = await db.rawQuery('''SELECT * FROM library_metadata
        WHERE edition_id IN (${List.filled(ids.length, '?').join(',')})
        AND provider_id IN ('screenscraper', 'igdb', 'romm')''', ids);
      for (final row in rows) {
        final id = row['edition_id'] as String;
        await db.delete('library_query_facets',
            where: 'edition_id = ?', whereArgs: [id]);
        if (row['edition_json'] == null ||
            row['game_json'] == null ||
            row['group_key'] == null ||
            row['group_identity'] != LibraryStore.metadataIdentity(row)) {
          await db.delete('library_query_editions',
              where: 'edition_id = ?', whereArgs: [id]);
          await db.delete('library_query_dirty',
              where: 'edition_id = ?', whereArgs: [id]);
          continue;
        }
        final edition =
            EditionIdentity.fromJson(jsonDecode(row['edition_json'] as String));
        final game = games[id]!;
        final base = baseGames[game.baseGameId];
        final keys = game.evidence
            .where(
                (e) => e.source == 'catalogue' && e.kind == 'artifactIdentity')
            .toList();
        final systems = game.evidence
            .where((e) => e.source == 'catalogue' && e.kind == 'system')
            .toList();
        final key = keys.length == 1 ? keys.single.value : null;
        final legacy = key != null && key.startsWith('legacy-cache-row:')
            ? int.tryParse(key.substring('legacy-cache-row:'.length))
            : null;
        final cache = key == null || systems.length != 1
            ? <Map<String, Object?>>[]
            : await db.query('games',
                columns: ['id', 'displayName'],
                where:
                    'systemSlug = ? AND is_folder = 0 AND ${legacy == null ? 'artifact_key = ?' : 'id = ? AND artifact_key IS NULL'}',
                whereArgs: [systems.single.value, legacy ?? key],
                limit: 2);
        final member = cache.length == 1 &&
            game.platformId == systems.single.value &&
            await LibraryStore.isCurrentCatalogueIdentity(db, row);
        final score = ratings[id];
        final sourceOrder = score != null && score.rankingEligible
            ? bases.indexWhere((b) =>
                b.sourceId == score.rating.sourceId &&
                b.assessmentReference == score.assessmentReference)
            : null;
        await db.insert(
            'library_query_editions',
            {
              'edition_id': id,
              'game_id': game.id,
              'base_game_id': game.baseGameId,
              'group_key': row['group_key'],
              'platform_id': game.platformId ?? '',
              'title':
                  cache.length == 1 ? cache.single['displayName'] : game.title,
              'cache_row_id': cache.length == 1 ? cache.single['id'] : null,
              'catalogue_key': legacy == null ? key : null,
              'legacy_row_id': legacy,
              'member': member ? 1 : 0,
              'score': score?.rating.normalizedValue,
              'source_order': sourceOrder,
              'rating_eligible': score?.rankingEligible == true ? 1 : 0
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        final genres = <String>{};
        for (final recordRow in records.where((r) => r['edition_id'] == id)) {
          final record = MetadataRecord.fromJson(
              jsonDecode(recordRow['record_json'] as String));
          if (recordRow['identity_key'] !=
                  LibraryStore.metadataIdentity(row,
                      providerId: record.providerId) ||
              !LibraryStore.hasConsistentProvenance(record) ||
              record.gameId != game.id ||
              record.editionId != id ||
              record.platformId != game.platformId ||
              metadataOverallOwnership(game, edition, record, base) == null) {
            continue;
          }
          for (final genre in record.genres) {
            for (final name in genre.names) {
              genres.add(name.text);
            }
          }
        }
        final facets = {
          'tag': _contentTags(edition),
          'genre': genres,
          'region': edition.regions.toSet(),
          'language': edition.languages.toSet()
        };
        final batch = db.batch();
        for (final facet in facets.entries) {
          for (final value in facet.value) {
            batch.insert(
                'library_query_facets',
                {
                  'edition_id': id,
                  'dimension': facet.key,
                  'value': value.toLowerCase()
                },
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        batch.delete('library_query_dirty',
            where: 'edition_id = ?', whereArgs: [id]);
        await batch.commit(noResult: true);
      }
    }
  }

  static Set<String> _contentTags(EditionIdentity edition) {
    final contradictoryOfficial = edition.tags.contains('official') &&
        (edition.tags.length != 1 ||
            edition.isTranslation == true ||
            edition.translatedLanguages.isNotEmpty);
    return Set.unmodifiable({
      ...edition.tags
          .where((tag) => tag != 'official' || !contradictoryOfficial),
      if (edition.tags.isEmpty ||
          !EditionIdentity.knownContentTags.containsAll(edition.tags) ||
          contradictoryOfficial)
        'unknown',
    });
  }

  /// One exact selected ROM's current, identity-bound metadata. This does not
  /// look through siblings, read payloads or start a provider refresh.
  Future<GameMetadataInfo?> cachedMetadata(
      String selectionKey, String systemSlug,
      {String language = 'en'}) async {
    final db = await _database;
    return db.transaction((txn) async {
      final artifact = selectionKey.startsWith('artifact:');
      final files = await txn.query('games',
          columns: ['id', 'filename'],
          where: 'systemSlug = ? AND is_folder = 0 AND '
              '${artifact ? 'artifact_key = ?' : 'filename = ? AND artifact_key IS NULL'}',
          whereArgs: [
            systemSlug,
            artifact ? selectionKey.substring(9) : selectionKey
          ],
          limit: 2);
      if (files.isEmpty) return null;
      // Duplicate bindings cannot inherit whichever score happens to be first.
      if (files.length != 1) {
        return GameMetadataInfo(
            filename: selectionKey,
            systemSlug: systemSlug,
            lastUpdated: 0,
            cacheRowId: files.first['id'] as int);
      }
      await _refresh(txn, productionOverallScoreBases);
      final cacheId = files.single['id'] as int;
      final rows = await txn.rawQuery('''SELECT e.edition_id,
        e.record_json AS edition_json, g.record_json AS game_json
        FROM library_query_editions q JOIN library_editions e
          ON e.edition_id = q.edition_id
        JOIN library_game_identities g ON g.game_id = e.game_id
        WHERE q.cache_row_id = ? AND q.member = 1 LIMIT 2''', [cacheId]);
      if (rows.length != 1) {
        return GameMetadataInfo(
            filename: selectionKey,
            systemSlug: systemSlug,
            lastUpdated: 0,
            cacheRowId: cacheId);
      }
      final row = rows.single;
      final game =
          GameIdentity.fromJson(jsonDecode(row['game_json'] as String));
      final edition =
          EditionIdentity.fromJson(jsonDecode(row['edition_json'] as String));
      GameIdentity? base;
      if (game.baseGameId != null) {
        final bases = await txn.query('library_game_identities',
            where: 'game_id = ?', whereArgs: [game.baseGameId], limit: 1);
        if (bases.isNotEmpty) {
          base = GameIdentity.fromJson(
              jsonDecode(bases.single['record_json'] as String));
        }
      }
      final scores = await LibraryStore.readEffectiveRatings(txn, [edition.id]);
      final overall = scores[edition.id];
      final records = <MetadataRecord>[];
      final stored = await txn.query('library_metadata',
          where:
              "edition_id = ? AND provider_id IN ('screenscraper','igdb','romm')",
          whereArgs: [edition.id],
          limit: 3);
      for (final provider in ['screenscraper', 'igdb', 'romm']) {
        for (final item in stored.where((v) => v['provider_id'] == provider)) {
          if (item['identity_key'] !=
              LibraryStore.metadataIdentity(row, providerId: provider)) {
            continue;
          }
          final record = MetadataRecord.fromJson(
              jsonDecode(item['record_json'] as String));
          if (LibraryStore.hasConsistentProvenance(record) &&
              metadataOverallOwnership(game, edition, record, base) != null) {
            records.add(record);
          }
        }
      }
      String? localized(List<MetadataText> texts) {
        final values = texts.where((v) => v.text.trim().isNotEmpty).toList();
        return values.where((v) => v.language == language).firstOrNull?.text ??
            values.where((v) => v.language == 'en').firstOrNull?.text ??
            values.firstOrNull?.text;
      }

      final provenance = <String, MetadataFieldProvenance>{};
      String? field(String name, String? Function(MetadataRecord) select) {
        for (final record in records) {
          final value = select(record);
          if (value == null || value.trim().isEmpty) continue;
          final evidence = record.fieldProvenance[name];
          if (evidence != null) provenance[name] = evidence;
          return value;
        }
        return null;
      }

      final summary = field('description', (r) => localized(r.descriptions));
      final genres = field(
          'genres',
          (r) => r.genres
              .map((g) => localized(g.names))
              .whereType<String>()
              .join(', '));
      final developer = field('developer', (r) => r.developer);
      final publisher = field('publisher', (r) => r.publisher);
      final release = field(
          'releaseDate',
          (r) => selectEditionReleaseDate(r.releaseDates,
              regions: edition.regions));
      return GameMetadataInfo(
          filename: files.single['filename'] as String,
          systemSlug: systemSlug,
          cacheRowId: cacheId,
          editionId: edition.id,
          overallRating: overall,
          rating: overall?.rating.normalizedValue,
          summary: summary,
          genres: genres,
          developer: developer,
          publisher: publisher,
          releaseDate: release,
          releaseYear:
              release == null ? null : int.tryParse(release.split('-').first),
          contentTags: _contentTags(edition),
          provenance: Map.unmodifiable(provenance),
          providerMatches: Map.unmodifiable(
              {for (final r in records) r.providerId: r.matchMethod}),
          lastUpdated: records.isEmpty
              ? 0
              : records.first.retrievedAt.millisecondsSinceEpoch);
    });
  }

  /// Cover badges need every exact cached edition, including non-representative
  /// regions/discs. Unlike [page], this does not collapse canonical groups or
  /// rank/filter them. The same identity-bound score selector supplies both.
  Future<Map<int, EffectiveOverallRating?>> cachedRatings(List<int> cacheRowIds,
      {List<AssessedOverallScoreBasis>? assessedBases}) async {
    if (cacheRowIds.length > 128 || cacheRowIds.any((id) => id < 1)) {
      throw ArgumentError('Cover score pages require at most 128 positive IDs');
    }
    final ids = cacheRowIds.toSet().toList();
    final result = {for (final id in ids) id: null as EffectiveOverallRating?};
    if (ids.isEmpty) return Map.unmodifiable(result);
    final bases = assessedBases ?? productionOverallScoreBases;
    final db = await _database;
    return db.transaction((txn) async {
      await _refresh(txn, bases);
      final rows = await txn.rawQuery('''SELECT cache_row_id,
        MIN(edition_id) AS edition_id FROM library_query_editions
        WHERE member = 1 AND cache_row_id IN
          (${List.filled(ids.length, '?').join(',')})
        GROUP BY cache_row_id HAVING COUNT(*) = 1''', ids);
      final scores = await LibraryStore.readEffectiveRatings(
          txn, rows.map((row) => row['edition_id'] as String).toList(),
          assessedBases: bases);
      for (final row in rows) {
        result[row['cache_row_id'] as int] = scores[row['edition_id']];
      }
      return Map<int, EffectiveOverallRating?>.unmodifiable(result);
    });
  }

  /// Exact cache-only cover bindings in bounded pages, never per-frame requests.
  Future<Map<int, String?>> cachedCovers(
      List<int> cacheRowIds, MetadataArtworkCache cache) async {
    if (cacheRowIds.length > 128 || cacheRowIds.any((id) => id < 1)) {
      throw ArgumentError('Cover pages require at most 128 positive IDs');
    }
    final ids = cacheRowIds.toSet().toList();
    final result = {for (final id in ids) id: null as String?};
    if (ids.isEmpty) return Map.unmodifiable(result);
    final db = await _database;
    final rows = await db.transaction((txn) async {
      await _refresh(txn, productionOverallScoreBases);
      return txn.rawQuery('''SELECT cache_row_id,
        MIN(edition_id) AS edition_id FROM library_query_editions
        WHERE member = 1 AND cache_row_id IN
          (${List.filled(ids.length, '?').join(',')})
        GROUP BY cache_row_id HAVING COUNT(*) = 1''', ids);
    });
    for (final row in rows) {
      final artwork =
          await cache.artworkForEdition(row['edition_id'] as String);
      result[row['cache_row_id'] as int] = artwork.cover;
    }
    return Map.unmodifiable(result);
  }

  Future<LibraryQueryPage> page(
      {required LibraryQueryFilter filter,
      List<AssessedOverallScoreBasis>? assessedBases}) async {
    _validate(filter);
    final bases = List<AssessedOverallScoreBasis>.unmodifiable(
        assessedBases ?? productionOverallScoreBases);
    final db = await _database;
    return db.transaction((txn) => _page(txn, filter, bases));
  }

  static void _validate(LibraryQueryFilter filter) {
    if (filter.limit < 1 ||
        filter.limit > 128 ||
        filter.offset < 0 ||
        (filter.top != null && filter.top! < 1)) {
      throw ArgumentError('Invalid query page/Top');
    }
    final dimensions = [
      filter.platformIds,
      filter.tags,
      filter.genres,
      filter.regions,
      filter.languages,
      filter.viewIds
    ];
    if (dimensions.any((values) =>
        values.length > 64 || values.any((v) => v.trim().isEmpty))) {
      throw ArgumentError('Invalid filter dimensions');
    }
  }

  static Future<LibraryQueryPage> _page(DatabaseExecutor txn,
      LibraryQueryFilter filter, List<AssessedOverallScoreBasis> bases) async {
    await _refresh(txn, bases);
    final args = <Object?>[];
    final scope = filter.platformIds.isEmpty
        ? ''
        : 'AND platform_id IN (${List.filled(filter.platformIds.length, '?').join(',')})';
    args.addAll(filter.platformIds);
    // Canonical ranks precede every presentation filter. A group selects its
    // first accepted source, not its highest-scoring edition. Conflicting
    // values under that source are unresolved, not a tie-break opportunity.
    final cte = '''WITH scoped AS (
        SELECT * FROM library_query_editions WHERE member = 1 $scope),
        priorities AS (SELECT group_key, MIN(source_order) AS source_order
          FROM scoped WHERE rating_eligible = 1 GROUP BY group_key),
        scores AS (SELECT s.group_key, p.source_order, MIN(s.score) AS score
          FROM scoped s JOIN priorities p ON p.group_key = s.group_key
          AND p.source_order = s.source_order
          WHERE s.rating_eligible = 1 GROUP BY s.group_key, p.source_order
          HAVING MIN(s.score) = MAX(s.score)),
        ranks AS (SELECT group_key, source_order, score,
          ROW_NUMBER() OVER (ORDER BY score DESC, group_key) AS rank FROM scores)''';
    final predicates = <String>[];
    if (filter.top != null) {
      predicates.add(
          'r.rank <= ? AND s.rating_eligible = 1 AND s.source_order = r.source_order AND s.score = r.score');
      args.add(filter.top);
    }
    for (final facet in {
      'tag': filter.tags,
      'genre': filter.genres,
      'region': filter.regions,
      'language': filter.languages
    }.entries) {
      if (facet.value.isEmpty) continue;
      final all = facet.key == 'tag' && filter.matchAllTags;
      predicates
          .add('''(SELECT COUNT(DISTINCT f.value) FROM library_query_facets f
          WHERE f.edition_id = s.edition_id AND f.dimension = ?
          AND f.value IN (${List.filled(facet.value.length, '?').join(',')})) ${all ? '= ?' : '> 0'}''');
      args.add(facet.key);
      args.addAll(facet.value.map((v) => v.toLowerCase()));
      if (all) {
        args.add(facet.value.map((v) => v.toLowerCase()).toSet().length);
      }
    }
    final search = filter.search?.trim();
    if (search != null && search.isNotEmpty) {
      predicates.add("s.title LIKE ? ESCAPE '\\'");
      args.add(
          '%${search.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%');
    }
    for (final view in filter.viewIds) {
      predicates.add(
          'EXISTS(SELECT 1 FROM library_query_views v WHERE v.edition_id = s.edition_id AND v.view_id = ?)');
      args.add(view);
    }
    final manual = filter.manualViewId;
    final ratingOrder =
        filter.ratingOrder || (filter.top != null && manual == null);
    final intersection = '''$cte, candidates AS (SELECT s.*,
        CASE WHEN s.rating_eligible = 1 AND s.source_order = r.source_order
          AND s.score = r.score THEN r.rank ELSE NULL END AS rank,
        ${manual == null ? 'NULL' : '(SELECT position FROM library_query_views v WHERE v.edition_id = s.edition_id AND v.view_id = ?)'} AS manual_position
        FROM scoped s LEFT JOIN ranks r ON r.group_key = s.group_key
        ${predicates.isEmpty ? '' : 'WHERE ${predicates.join(' AND ')}'}),
        filtered AS (SELECT candidates.*, ROW_NUMBER() OVER (PARTITION BY group_key ORDER BY
          ${manual != null && !ratingOrder ? 'manual_position IS NULL, manual_position,' : ''}
          rating_eligible DESC, source_order, edition_id) AS edition_order FROM candidates)''';
    // manual position placeholder comes before filter predicates, after scope.
    if (manual != null) args.insert(filter.platformIds.length, manual);
    final order = ratingOrder
        ? 'rank IS NULL, rank, group_key, edition_order'
        : manual != null
            ? 'manual_position IS NULL, manual_position, group_key, edition_order'
            : 'title COLLATE NOCASE, group_key, edition_order';
    // One evaluation supplies coverage/count/page, including empty pages.
    // Re-running the same full-scope rank CTE for each count tripled work.
    final response = await txn.rawQuery('''$intersection, summary AS (SELECT
        (SELECT COUNT(DISTINCT group_key) FROM scoped) AS collection_games,
        (SELECT COUNT(*) FROM ranks) AS ranked_games,
        (SELECT COUNT(*) FROM filtered WHERE edition_order = 1) AS matches),
        page_rows AS (SELECT edition_id, game_id,
        group_key, platform_id, title, cache_row_id, rank, manual_position, edition_order FROM filtered
        ${filter.includeVariants ? '' : 'WHERE edition_order = 1'} ORDER BY $order LIMIT ? OFFSET ?)
        SELECT page_rows.*, summary.* FROM summary LEFT JOIN page_rows ON 1 = 1 ORDER BY $order''',
        [...args, filter.limit, filter.offset]);
    final coverage = response.first;
    final rows = response.where((r) => r['edition_id'] != null).toList();
    final ratings = await LibraryStore.readEffectiveRatings(
        txn, rows.map((r) => r['edition_id'] as String).toList(),
        assessedBases: bases);
    return LibraryQueryPage(
        items: rows
            .map((r) => LibraryQueryItem(
                editionId: r['edition_id'] as String,
                gameId: r['game_id'] as String,
                groupKey: r['group_key'] as String,
                platformId: r['platform_id'] as String,
                title: r['title'] as String,
                cacheRowId: r['cache_row_id'] as int,
                rank: r['rank'] as int?,
                score: ratings[r['edition_id']]))
            .toList(),
        collectionGames: coverage['collection_games'] as int,
        rankedGames: coverage['ranked_games'] as int,
        totalMatches: coverage['matches'] as int);
  }
}
