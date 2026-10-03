import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../models/library_identity.dart';
import '../models/scraped_metadata.dart';
import 'library_store.dart';

import 'metadata/effective_overall_rating.dart';

/// Console IDs define ranking scope. All other constraints intersect it later.
class LibraryQueryFilter {
  final Set<String> platformIds, tags, genres, regions, languages, viewIds;
  final bool matchAllTags, ratingOrder;
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

class LibraryQuery {
  final Future<Database> _database;
  LibraryQuery(this._database);

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
    for (final table in [
      'library_editions',
      'library_metadata',
      'library_canonical_groups',
      'metadata_refresh_items'
    ]) {
      for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
        await db.execute(
            '''CREATE TRIGGER IF NOT EXISTS query_${table}_${event.toLowerCase()}
          AFTER $event ON $table BEGIN
          ${event == 'INSERT' ? '' : 'INSERT OR IGNORE INTO library_query_dirty VALUES (OLD.edition_id);'}
          ${event == 'DELETE' ? '' : 'INSERT OR IGNORE INTO library_query_dirty VALUES (NEW.edition_id);'}
          END''');
      }
    }
    for (final event in ['UPDATE', 'DELETE']) {
      await db.execute(
          '''CREATE TRIGGER IF NOT EXISTS query_game_${event.toLowerCase()}
        AFTER $event ON library_game_identities BEGIN
          INSERT OR IGNORE INTO library_query_dirty SELECT edition_id
          FROM library_editions WHERE game_id = OLD.game_id;
          INSERT OR IGNORE INTO library_query_dirty SELECT edition_id
          FROM library_query_editions WHERE base_game_id = OLD.game_id;
        END''');
    }
    for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
      final references = [
        if (event != 'INSERT') 'OLD',
        if (event != 'DELETE') 'NEW'
      ];
      await db.execute(
          '''CREATE TRIGGER IF NOT EXISTS query_cache_${event.toLowerCase()}
        AFTER $event ON games BEGIN
        ${references.map((ref) => '''INSERT OR IGNORE INTO library_query_cache_dirty VALUES ($ref.id);
          INSERT OR IGNORE INTO library_query_dirty
          SELECT edition_id FROM library_query_editions WHERE cache_row_id = $ref.id;
          INSERT OR IGNORE INTO library_query_dirty SELECT edition_id
          FROM library_query_editions WHERE legacy_row_id = $ref.id;
          INSERT OR IGNORE INTO library_query_dirty SELECT edition_id
          FROM library_query_editions WHERE platform_id = $ref.systemSlug
            AND catalogue_key = $ref.artifact_key;''').join('\n')}
        END''');
    }
    await db.execute('''CREATE TRIGGER IF NOT EXISTS query_refresh_owner
      AFTER UPDATE OF provider_id, generation, is_artwork ON metadata_refresh_jobs
      BEGIN INSERT OR IGNORE INTO library_query_dirty SELECT edition_id
        FROM metadata_refresh_items WHERE job_id = NEW.id; END''');
    await db.execute('''CREATE TRIGGER IF NOT EXISTS query_refresh_delete
      BEFORE DELETE ON metadata_refresh_jobs
      BEGIN INSERT OR IGNORE INTO library_query_dirty SELECT edition_id
        FROM metadata_refresh_items WHERE job_id = OLD.id; END''');
    // Upgrade retains original facts. Its first ordinary query rebuilds pages.
    await db.execute('''INSERT OR IGNORE INTO library_query_dirty
      SELECT edition_id FROM library_editions''');
    await db.execute('''INSERT OR IGNORE INTO library_query_cache_dirty
      SELECT id FROM games WHERE is_folder = 0''');
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
        final contradictoryOfficial = edition.tags.contains('official') &&
            (edition.tags.length != 1 ||
                edition.isTranslation == true ||
                edition.translatedLanguages.isNotEmpty);
        final tagFacets = {
          ...edition.tags
              .where((tag) => tag != 'official' || !contradictoryOfficial),
          if (edition.tags.isEmpty ||
              !EditionIdentity.knownContentTags.containsAll(edition.tags) ||
              contradictoryOfficial)
            'unknown'
        };
        final facets = {
          'tag': tagFacets,
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

  Future<LibraryQueryPage> page(
      {required LibraryQueryFilter filter,
      List<AssessedOverallScoreBasis> assessedBases = const []}) async {
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
    final bases = List<AssessedOverallScoreBasis>.unmodifiable(assessedBases);
    final db = await _database;
    return db.transaction((txn) async {
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
      final ratingOrder = filter.ratingOrder || filter.top != null;
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
          ? 'rank IS NULL, rank, group_key'
          : manual != null
              ? 'manual_position IS NULL, manual_position, group_key'
              : 'title COLLATE NOCASE, group_key';
      // One evaluation supplies coverage/count/page, including empty pages.
      // Re-running the same full-scope rank CTE for each count tripled work.
      final response = await txn.rawQuery('''$intersection, summary AS (SELECT
        (SELECT COUNT(DISTINCT group_key) FROM scoped) AS collection_games,
        (SELECT COUNT(*) FROM ranks) AS ranked_games,
        (SELECT COUNT(*) FROM filtered WHERE edition_order = 1) AS matches),
        page_rows AS (SELECT edition_id, game_id,
        group_key, platform_id, title, cache_row_id, rank, manual_position FROM filtered
        WHERE edition_order = 1 ORDER BY $order LIMIT ? OFFSET ?)
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
    });
  }
}
