import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/metadata/effective_overall_rating.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:sqflite/sqflite.dart';

// Observe the actual SQLite calls; never replace their returned rows or writes.
class _ObservedDatabase implements Database {
  final Database db;
  final List<String> rankedSql = [];
  List<Object?> rankedArgs = [];
  int maxIdentityRows = 0, maxMetadataRows = 0, projectionWrites = 0;
  _ObservedDatabase(this.db);
  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action,
          {bool? exclusive}) =>
      db.transaction((txn) => action(_ObservedTransaction(txn, this)),
          exclusive: exclusive);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
      'Unexpected database call ${invocation.memberName}');
}

class _ObservedTransaction implements Transaction {
  final Transaction db;
  final _ObservedDatabase owner;
  _ObservedTransaction(this.db, this.owner);
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) async {
    final rows = await db.rawQuery(sql, arguments);
    if (sql.contains('game_json') && rows.length > owner.maxIdentityRows) {
      owner.maxIdentityRows = rows.length;
    }
    if (sql.contains('library_metadata') &&
        rows.length > owner.maxMetadataRows) {
      owner.maxMetadataRows = rows.length;
    }
    if (sql.startsWith('WITH scoped') && sql.contains('LIMIT ? OFFSET ?')) {
      owner.rankedSql.add(sql);
      owner.rankedArgs = arguments ?? [];
    }
    return rows;
  }

  @override
  Future<List<Map<String, Object?>>> query(String table,
      {bool? distinct,
      List<String>? columns,
      String? where,
      List<Object?>? whereArgs,
      String? groupBy,
      String? having,
      String? orderBy,
      int? limit,
      int? offset}) async {
    final rows = await db.query(table,
        distinct: distinct,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy,
        having: having,
        orderBy: orderBy,
        limit: limit,
        offset: offset);
    if (table == 'library_metadata' && rows.length > owner.maxMetadataRows) {
      owner.maxMetadataRows = rows.length;
    }
    if (table == 'library_game_identities' &&
        rows.length > owner.maxIdentityRows) {
      owner.maxIdentityRows = rows.length;
    }
    return rows;
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) =>
      db.rawInsert(sql, arguments);
  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) =>
      db.rawUpdate(sql, arguments);
  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) =>
      db.rawDelete(sql, arguments);
  @override
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) {
    if (table == 'library_query_editions') owner.projectionWrites++;
    return db.insert(table, values,
        nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      db.delete(table, where: where, whereArgs: whereArgs);
  @override
  Future<int> update(String table, Map<String, Object?> values,
          {String? where,
          List<Object?>? whereArgs,
          ConflictAlgorithm? conflictAlgorithm}) =>
      db.update(table, values,
          where: where,
          whereArgs: whereArgs,
          conflictAlgorithm: conflictAlgorithm);
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      db.execute(sql, arguments);
  @override
  Batch batch() => db.batch();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
      'Unexpected transaction call ${invocation.memberName}');
}

/// Same compact-query assertions on the host driver and the Android plugin.
/// Synthetic assessment never approves a real score source.
Future<Map<String, Object?>> verifyLibraryQueryResource(DatabaseFactory factory,
    {int count = 30000}) async {
  if (count < 2500) {
    throw ArgumentError.value(
        count, 'count', 'Needs 25 tied top-score members');
  }

  final root = await Directory.systemTemp.createTemp('rshop-query-resource-');
  Database? db;
  try {
    db = await factory.openDatabase(p.join(root.path, 'fixture.db'));
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db
        .execute('''CREATE TABLE games(id INTEGER PRIMARY KEY, systemSlug TEXT,
        displayName TEXT, artifact_key TEXT, remote_artifact TEXT, is_folder INTEGER DEFAULT 0)''');
    await LibraryQuery.install(db);
    final at = DateTime.utc(2026, 10, 3);
    // File-backed fixtures include real metadata bodies. No direct projection
    // seeding: normal capture, ownership and selector construct every score.
    await db.transaction((txn) async {
      for (var start = 1; start <= count; start += 128) {
        final batch = txn.batch();
        for (var n = start; n < start + 128 && n <= count; n++) {
          final suffix = sha256
              .convert(utf8.encode(jsonEncode([
                'psx',
                ['legacy-cache-row', n]
              ])))
              .toString();
          final game = GameIdentity(
              id: 'catalogue-game:$suffix',
              platformId: 'psx',
              title: 'Game $n',
              providerIds: {'igdb': '$n'},
              matchStatus: IdentityMatchStatus.manuallyMatched,
              evidence: [
                IdentityEvidence(
                    source: 'catalogue',
                    kind: 'artifactIdentity',
                    value: 'legacy-cache-row:$n'),
                IdentityEvidence(
                    source: 'catalogue', kind: 'system', value: 'psx')
              ]);
          final edition = EditionIdentity(
              id: 'catalogue-edition:$suffix',
              gameId: game.id,
              tags: {'official'});
          final record = MetadataRecord(
              gameId: game.id,
              editionId: edition.id,
              platformId: 'psx',
              providerId: 'igdb',
              providerGameId: '$n',
              retrievedAt: at,
              refreshGeneration: 1,
              matchMethod: 'verifiedProviderIdGlobalGame',
              titles: [
                MetadataText(text: 'Game $n')
              ],
              descriptions: [
                MetadataText(text: 'x' * 256)
              ],
              genres: [
                MetadataGenre(
                    providerGenreId: '1',
                    names: [MetadataText(text: n.isEven ? 'Action' : 'Puzzle')])
              ],
              media: [
                for (var m = 0; m < 4; m++)
                  MetadataMedia(
                      type: 'screenshot',
                      url: 'https://example.invalid/image-$n-$m.png')
              ],
              ratings: [
                SourcedRating.parse(
                    sourceId: 'igdb',
                    sourceLabel: 'IGDB',
                    providerGameId: '$n',
                    rawValue: n % 100,
                    scaleMinimum: 0,
                    scaleMaximum: 100,
                    voteCount: 100,
                    kind: RatingKind.overallAggregate,
                    retrievedAt: at)!
              ]);
          batch.insert('games',
              {'id': n, 'systemSlug': 'psx', 'displayName': game.title});
          batch.insert('library_game_identities', {
            'game_id': game.id,
            'platform_id': 'psx',
            'title': game.title,
            'match_status': game.matchStatus.name,
            'record_json': jsonEncode(game.toJson())
          });
          batch.insert('library_editions', {
            'edition_id': edition.id,
            'game_id': game.id,
            'record_json': jsonEncode(edition.toJson())
          });
          batch.insert('library_metadata', {
            'edition_id': edition.id,
            'provider_id': 'igdb',
            'provider_game_id': '$n',
            'generation_id': 1,
            'retrieved_at': at.toIso8601String(),
            'identity_key': LibraryStore.metadataIdentity({
              'game_json': jsonEncode(game.toJson()),
              'edition_json': jsonEncode(edition.toJson())
            }, providerId: 'igdb'),
            'record_json': jsonEncode(record.toJson())
          });
        }
        await batch.commit(noResult: true);
      }
    });
    final observed = _ObservedDatabase(db);
    final query = LibraryQuery(Future.value(observed));
    final basis = AssessedOverallScoreBasis(
        sourceId: 'igdb',
        kind: RatingKind.overallAggregate,
        scaleMinimum: 0,
        scaleMaximum: 100,
        platformIds: {'psx'},
        minimumVoteCount: 10,
        assessmentReference: 'synthetic-resource-assessment');
    final rssBefore = ProcessInfo.currentRss;
    final buildWatch = Stopwatch()..start();
    final initial = await query.page(
        filter: LibraryQueryFilter(top: 25, limit: 8), assessedBases: [basis]);
    buildWatch.stop();
    expect(initial.collectionGames, count);
    expect(initial.rankedGames, count);
    expect(initial.totalMatches, 25);
    expect(initial.items, hasLength(8));
    expect(observed.maxIdentityRows, lessThanOrEqualTo(128));
    expect(observed.maxMetadataRows, lessThanOrEqualTo(384));
    final writesBeforeFilters = observed.projectionWrites;
    final filterWatch = Stopwatch()..start();
    final filtered = await query.page(
        filter: LibraryQueryFilter(top: 25, genres: {'Action'}, limit: 8),
        assessedBases: [basis]);
    final second = await query.page(
        filter: LibraryQueryFilter(top: 25, limit: 8, offset: 8),
        assessedBases: [basis]);
    filterWatch.stop();
    expect(filtered.items, isEmpty,
        reason:
            'All 99-score members are odd; Action must not refill below Top 25.');
    expect(second.items, hasLength(8));
    expect(second.items.first.rank, 9);
    expect(observed.projectionWrites, writesBeforeFilters);
    final plan = await db.rawQuery(
        'EXPLAIN QUERY PLAN ${observed.rankedSql.last}', observed.rankedArgs);
    expect(plan.any((r) => '${r['detail']}'.contains('idx_library_query_')),
        isTrue);
    expect(
        plan.any((r) => '${r['detail']}'.contains('library_metadata')), isFalse,
        reason:
            'Rank SQL reads compact projection, not metadata/artwork bodies.');
    // Diagnostic measurements, not cancellation timeouts or pass deadlines.
    // ignore: avoid_print
    print(
        'ranked query $count: pid=$pid buildMs=${buildWatch.elapsedMilliseconds} warmTwoQueriesMs=${filterWatch.elapsedMilliseconds} rssBefore=$rssBefore rssAfter=${ProcessInfo.currentRss} maxRss=${ProcessInfo.maxRss} maxIdentityRows=${observed.maxIdentityRows} maxMetadataRows=${observed.maxMetadataRows}');
    return {
      'games': count,
      'ranked_games': initial.rankedGames,
      'top_matches': initial.totalMatches,
      'build_ms': buildWatch.elapsedMilliseconds,
      'warm_two_queries_ms': filterWatch.elapsedMilliseconds,
      'rss_before': rssBefore,
      'rss_after': ProcessInfo.currentRss,
      'max_rss': ProcessInfo.maxRss,
      'max_identity_rows': observed.maxIdentityRows,
      'max_metadata_rows': observed.maxMetadataRows,
      'filter_projection_writes':
          observed.projectionWrites - writesBeforeFilters,
      'network_requests': 0,
    };
  } finally {
    await db?.close();
    if (!p.isWithin(Directory.systemTemp.path, root.path) ||
        !p.basename(root.path).startsWith('rshop-query-resource-')) {
      throw StateError('Unexpected fixture cleanup root');
    }
    await root.delete(recursive: true);
  }
}
