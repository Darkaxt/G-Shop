import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_artwork_cache.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/services/metadata/shared_metadata_store.dart';
import 'package:sqflite/sqflite.dart';

final _retrieved = DateTime.utc(2026, 10, 5);

RemoteArtifact _artifact(int n, String source) => RemoteArtifact(
    id: RemoteArtifactId(
        providerId: 'drive',
        sourceId: source,
        accountId: 'synthetic-account',
        providerFileId: 'file-$n'),
    parentId: 'synthetic-root',
    displayName: 'Game $n.chd',
    displayPath: 'Game $n.chd',
    sizeBytes: 1024,
    version: '1',
    providerChecksums: {'md5': n.toRadixString(16).padLeft(32, '0')},
    canDownload: true);

Map<String, Object?> _record(int n) {
  final artifact = _artifact(n, 'old-source');
  final suffix = sha256
      .convert(utf8.encode(jsonEncode([
        'psx',
        ['artifact', artifact.id.key]
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
            value: artifact.id.key),
        IdentityEvidence(source: 'catalogue', kind: 'system', value: 'psx')
      ]);
  final marker = sha256
      .convert(utf8
          .encode(jsonEncode([artifact.sizeBytes, artifact.providerChecksums])))
      .toString();
  final edition = EditionIdentity(
      id: 'catalogue-edition:$suffix',
      gameId: game.id,
      tags: {
        'official'
      },
      members: [
        EditionMember(artifactId: artifact.id)
      ],
      evidence: [
        IdentityEvidence(
            source: 'catalogue', kind: 'artifactContent', value: marker)
      ]);
  final metadata = MetadataRecord(
      gameId: game.id,
      editionId: edition.id,
      platformId: 'psx',
      providerId: 'igdb',
      providerGameId: '$n',
      retrievedAt: _retrieved,
      refreshGeneration: 1,
      matchMethod: 'verifiedProviderIdGlobalGame',
      titles: [
        MetadataText(text: game.title)
      ],
      descriptions: [
        MetadataText(text: 'Synthetic description $n ${'x' * 512}')
      ],
      genres: [
        MetadataGenre(
            providerGenreId: '1', names: [MetadataText(text: 'Action')])
      ],
      ratings: [
        SourcedRating.parse(
            sourceId: 'igdb',
            sourceLabel: 'IGDB users',
            providerGameId: '$n',
            rawValue: 80 + n % 20,
            scaleMinimum: 0,
            scaleMaximum: 100,
            voteCount: 100,
            kind: RatingKind.communityAggregate,
            retrievedAt: _retrieved)!
      ]);
  final identity = {
    'game_json': jsonEncode(game.toJson()),
    'edition_json': jsonEncode(edition.toJson())
  };
  return {
    'platform_id': game.platformId,
    'edition_id': edition.id,
    'provider_id': 'igdb',
    'generation': 1,
    'identity_key': LibraryStore.metadataIdentity(identity, providerId: 'igdb'),
    ...identity,
    'artifacts_json': jsonEncode([artifact.toJson()]),
    'record_json': jsonEncode(metadata.toJson())
  };
}

Future<Database> _private(DatabaseFactory factory, String path) async {
  final db = await factory.openDatabase(path);
  await LibrarySchema.install(db);
  await MetadataRefreshJobs.install(db);
  await MetadataArtworkCache.install(db);
  await db
      .execute('''CREATE TABLE games(id INTEGER PRIMARY KEY, systemSlug TEXT,
    displayName TEXT, filename TEXT, artifact_key TEXT, remote_artifact TEXT,
    is_folder INTEGER DEFAULT 0)''');
  // Match DatabaseService's current catalogue constraints/access paths. Without
  // these production indexes this fixture benchmarks repeated table scans,
  // rather than the application restore/query boundary.
  await db.execute('''CREATE UNIQUE INDEX idx_games_system_filename
    ON games(systemSlug, filename) WHERE artifact_key IS NULL''');
  await db.execute('''CREATE UNIQUE INDEX idx_games_system_artifact
    ON games(systemSlug, artifact_key) WHERE artifact_key IS NOT NULL''');
  final plan = await db.rawQuery('''EXPLAIN QUERY PLAN SELECT id FROM games
    WHERE systemSlug = ? AND artifact_key = ? AND is_folder = 0''',
      ['psx', _artifact(1, 'old-source').id.key]);
  expect(plan.map((row) => row['detail']).join(' '),
      contains('idx_games_system_artifact'));
  await LibraryQuery.install(db);
  return db;
}

Map<String, Object?> _file(int n, String source) {
  final artifact = _artifact(n, source);
  return {
    'id': n,
    'systemSlug': 'psx',
    'displayName': 'Game $n',
    'filename': artifact.displayName,
    'artifact_key': artifact.id.key,
    'remote_artifact': jsonEncode(artifact.toJson())
  };
}

/// Resource verification of the actual restore/query paths, not provider load.
/// Bulk synthetic records are checked against one real preserve() publication;
/// refresh/artwork producer integration has its own normal-workflow fixtures.
/// Nothing here mirrors ROMs, imports legacy scores or restores operational state.
Future<Map<String, Object?>> verifySharedMetadataRebuildResource(
    DatabaseFactory factory,
    {int count = 30000}) async {
  final root = await Directory.systemTemp.createTemp('rshop-shared-resource-');
  final durable = Directory(p.join(root.path, 'RShopMetadata'));
  SharedMetadataStore? shared;
  Database? old, seed, fresh;
  final rssBefore = ProcessInfo.currentRss;
  final watch = Stopwatch()..start();
  try {
    shared = await SharedMetadataStore.open(durable, factory: factory);
    old = await _private(factory, p.join(root.path, 'old.sqlite'));
    await old.insert('games', _file(1, 'old-source'));
    await old.transaction((txn) async {
      await for (final _
          in LibraryStore.catalogueEditions(txn, cacheRowId: 1)) {}
    });
    final template = _record(1);
    final game =
        GameIdentity.fromJson(jsonDecode(template['game_json'] as String));
    final edition = EditionIdentity.fromJson(
        jsonDecode(template['edition_json'] as String));
    final record =
        MetadataRecord.fromJson(jsonDecode(template['record_json'] as String));
    final store = LibraryStore(Future.value(old));
    await store.putGame(game);
    await store.putEdition(edition);
    await store.putMetadata(record);
    await shared.preserve(record, template, old);
    await shared.close();
    shared = null;
    await old.close();
    old = null;

    seed = await factory.openDatabase(p.join(durable.path, 'metadata.sqlite'));
    expect((await seed.query('records')).single, template,
        reason: 'Bulk fixture must equal the actual durable producer format');
    await seed.transaction((txn) async {
      for (var start = 1; start <= count; start += 128) {
        final batch = txn.batch();
        for (var n = start; n < start + 128 && n <= count; n++) {
          final row = _record(n);
          expect(
              LibraryStore.hasConsistentProvenance(MetadataRecord.fromJson(
                  jsonDecode(row['record_json'] as String))),
              true);
          batch.insert('records', row,
              conflictAlgorithm: ConflictAlgorithm.replace);
          batch.insert(
              'identity_bindings',
              {
                'edition_id': row['edition_id'],
                'game_id':
                    (jsonDecode(row['game_json'] as String) as Map)['id'],
                'generation': 1,
                'game_json': row['game_json'],
                'edition_json': row['edition_json'],
                'artifacts_json': row['artifacts_json'],
                'identity_key': LibraryStore.metadataIdentity(row)
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      }
    });
    await seed.close();
    seed = null;
    shared = await SharedMetadataStore.open(durable,
        factory: factory, existingOnly: true);

    // A genuinely new private DB contains only a republished remote catalogue,
    // with a different local source ID. No old private identities are supplied.
    fresh = await _private(factory, p.join(root.path, 'fresh.sqlite'));
    await fresh.transaction((txn) async {
      for (var start = 1; start <= count; start += 128) {
        final batch = txn.batch();
        for (var n = start; n < start + 128 && n <= count; n++) {
          batch.insert('games', _file(n, 'reselected-source'));
        }
        await batch.commit(noResult: true);
      }
    });
    expect(await fresh.query('library_metadata'), isEmpty);
    final restoreWatch = Stopwatch()..start();
    expect(await shared.restore(fresh), count);
    restoreWatch.stop();
    final rebuilt = LibraryStore(Future.value(fresh));
    for (final n in [1, 128, count]) {
      final id = (await LibraryStore.cachedCatalogueEditionId(fresh, n))!;
      final record = (await rebuilt.metadata(id, 'igdb'))!;
      expect(record.providerGameId, '$n');
      expect(record.refreshGeneration, 1);
      expect((await rebuilt.edition(id))!.members.single.artifactId.sourceId,
          'reselected-source');
      expect(record.descriptions.single.text,
          contains('Synthetic description $n'));
    }
    final queryWatch = Stopwatch()..start();
    final page = await LibraryQuery(Future.value(fresh))
        .page(filter: LibraryQueryFilter(top: 25, limit: 8));
    queryWatch.stop();
    expect(page.collectionGames, count);
    expect(page.rankedGames, count);
    expect(page.totalMatches, 25);
    expect(page.items, hasLength(8));
    expect(page.provisional, false);
    final replayWatch = Stopwatch()..start();
    expect(await shared.restore(fresh), 0);
    replayWatch.stop();
    expect(
        (await fresh.rawQuery('SELECT COUNT(*) AS n FROM library_metadata'))
            .single['n'],
        count);
    expect(await fresh.query('metadata_refresh_jobs'), isEmpty);
    expect(
        await fresh.rawQuery("SELECT name FROM sqlite_master WHERE "
            "name LIKE '%installation%' OR name LIKE '%transfer%'"),
        isEmpty);
    final result = <String, Object?>{
      'editions': count,
      'restored': count,
      'ranked': page.rankedGames,
      'top_matches': page.totalMatches,
      'restore_ms': restoreWatch.elapsedMilliseconds,
      'query_ms': queryWatch.elapsedMilliseconds,
      'replay_ms': replayWatch.elapsedMilliseconds,
      'total_ms': watch.elapsedMilliseconds,
      'rss_before': rssBefore,
      'rss_after': ProcessInfo.currentRss,
      'max_rss': ProcessInfo.maxRss
    };
    // Diagnostic output only: neither elapsed time nor RSS decides completion.
    // ignore: avoid_print
    print('shared metadata rebuild ${jsonEncode(result)}');
    return result;
  } finally {
    await old?.close();
    await seed?.close();
    await fresh?.close();
    await shared?.close();
    if (!p.isWithin(Directory.systemTemp.path, root.path) ||
        !p.basename(root.path).startsWith('rshop-shared-resource-')) {
      throw StateError('Unexpected resource fixture cleanup root');
    }
    await root.delete(recursive: true);
  }
}
