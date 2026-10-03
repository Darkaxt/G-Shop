import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/services/library_store.dart';

void main() {
  late Database db;
  late LibraryStore store;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await LibrarySchema.install(db);
    store = LibraryStore(Future.value(db));
  });
  tearDown(() => db.close());

  Future<void> edition(String id,
      {String platform = 'psx',
      String providerId = '42',
      Map<String, String>? providerIds,
      IdentityMatchStatus status = IdentityMatchStatus.manuallyMatched,
      Set<String> tags = const {'official'},
      String? patch,
      bool? translation,
      List<String> translatedLanguages = const []}) async {
    await store.putGame(GameIdentity(
        id: 'game:$id',
        platformId: platform,
        title: 'Same title',
        providerIds: providerIds ?? {'screenscraper': providerId},
        matchStatus: status));
    await store.putEdition(EditionIdentity(
        id: id,
        gameId: 'game:$id',
        tags: tags,
        patchId: patch,
        isTranslation: translation,
        translatedLanguages: translatedLanguages));
  }

  Future<String> group(String id) async =>
      (await db.query('library_canonical_groups',
              columns: ['group_key'], where: 'edition_id = ?', whereArgs: [id]))
          .single['group_key'] as String;

  test('verified editions share one group without merging exact editions',
      () async {
    await edition('us');
    await edition('eu');
    await edition('translated',
        tags: {'T-Eng', 'Undub', 'Uncensor'},
        translation: true,
        translatedLanguages: ['en'],
        patch: 'translation');
    expect(await group('us'), await group('eu'));
    expect(await group('us'), await group('translated'));
    expect((await store.edition('translated'))!.patchId, 'translation');
    expect(await db.query('library_editions'), hasLength(3));
  });

  test('candidate IDs titles and platforms cannot merge unverified games',
      () async {
    await edition('matched');
    await edition('candidate', status: IdentityMatchStatus.unmatched);
    await edition('wrong-platform', platform: 'snes');
    await edition('unknown', tags: {});
    await edition('another-id', providerId: '43');
    final groups = <String>{};
    for (final id in [
      'matched',
      'candidate',
      'wrong-platform',
      'unknown',
      'another-id'
    ]) {
      groups.add(await group(id));
    }
    expect(groups, hasLength(5));
  });

  test('verified IGDB-only regions and discs identify one canonical game',
      () async {
    await edition('igdb-us', providerIds: {'igdb': '42'});
    await edition('igdb-eu-disc2', providerIds: {'igdb': '42'});
    await edition('igdb-translation',
        providerIds: {'igdb': '42'},
        tags: {'T-Eng', 'Undub'},
        translation: true,
        translatedLanguages: ['en'],
        patch: 'english-audio');
    await edition('igdb-base-hack',
        providerIds: {'igdb': '42'}, tags: {'Hack'}, patch: 'project');
    expect(await group('igdb-us'), await group('igdb-eu-disc2'));
    expect(await group('igdb-us'), await group('igdb-translation'));
    expect(await group('igdb-base-hack'), isNot(await group('igdb-us')));
    expect((await store.edition('igdb-translation'))!.patchId, 'english-audio');
  });

  test('reviewed provider bridge joins variants and correction splits them',
      () async {
    await edition('ss-only', providerIds: {'screenscraper': '42'});
    await edition('igdb-only', providerIds: {'igdb': '99'});
    await edition('bridge', providerIds: {'screenscraper': '42', 'igdb': '99'});
    expect(await group('ss-only'), await group('igdb-only'));
    expect(await group('ss-only'), await group('bridge'));
    await store.putGame(GameIdentity(
        id: 'game:bridge',
        platformId: 'psx',
        title: 'Reviewed correction',
        providerIds: {'screenscraper': '42', 'igdb': '100'},
        matchStatus: IdentityMatchStatus.manuallyMatched));
    expect(await group('ss-only'), await group('bridge'));
    expect(await group('ss-only'), isNot(await group('igdb-only')));
    await edition('corrected-igdb', providerIds: {'igdb': '100'});
    expect(await group('corrected-igdb'), await group('bridge'));
    expect((await store.canonicalEditions('bridge')).editions.map((e) => e.id),
        ['bridge', 'corrected-igdb', 'ss-only']);
  });

  test('unverified wrong-platform and hack IDs cannot bridge providers',
      () async {
    await edition('ss-only', providerIds: {'screenscraper': '42'});
    await edition('igdb-only', providerIds: {'igdb': '99'});
    for (final kind in ['candidate', 'unknown', 'hack', 'wrong-platform']) {
      await edition(kind,
          providerIds: {'screenscraper': '42', 'igdb': '99'},
          status: kind == 'candidate'
              ? IdentityMatchStatus.unmatched
              : IdentityMatchStatus.manuallyMatched,
          tags: kind == 'unknown'
              ? {}
              : kind == 'hack'
                  ? {'Hack'}
                  : {'official'},
          platform: kind == 'wrong-platform' ? 'snes' : 'psx');
    }
    expect(await group('ss-only'), isNot(await group('igdb-only')));
    final distinct = <String>{};
    for (final id in [
      'ss-only',
      'igdb-only',
      'candidate',
      'unknown',
      'hack',
      'wrong-platform'
    ]) {
      distinct.add(await group(id));
    }
    expect(distinct, hasLength(6));
  });

  test('base provider ID cannot group unrelated hack projects', () async {
    await edition('base');
    await edition('hack-a', tags: {'Hack'}, patch: 'project-a');
    await edition('hack-b', tags: {'Hack'}, patch: 'project-b');
    expect({await group('base'), await group('hack-a'), await group('hack-b')},
        hasLength(3));
    await store.putEdition(EditionIdentity(
        id: 'hack-a-revision',
        gameId: 'game:hack-a',
        tags: {'Hack'},
        patchId: 'project-a-v2'));
    expect(await group('hack-a'), await group('hack-a-revision'));
  });

  test(
      'inconsistent edition translation classification cannot bridge originals',
      () async {
    await edition('ordinary');
    await edition('audio', tags: {'Undub'});
    expect(await group('audio'), await group('ordinary'));
    // A known audio modification does not explain a separately asserted
    // translation. It must not silently become an English translation alias.
    await edition('unclassified-translation',
        tags: {'Undub'}, translation: true, translatedLanguages: ['fr']);
    expect(await group('unclassified-translation'),
        isNot(await group('ordinary')));
    expect((await store.edition('unclassified-translation'))!.isTranslation,
        isTrue);
    expect(
        (await store.edition('unclassified-translation'))!.translatedLanguages,
        ['fr']);
  });

  test('inconsistent edition provider ID cannot bridge reviewed game IDs',
      () async {
    await edition('ordinary');
    await edition('conflicting');
    final exactEdition = (await store.edition('conflicting'))!;
    await store.putEdition(EditionIdentity.fromJson({
      ...exactEdition.toJson(),
      'providerIds': {'screenscraper': '43'}
    }));
    expect(await group('conflicting'), isNot(await group('ordinary')));
    // Correcting the exact edition restores the reviewed alias transactionally.
    await store.putEdition(EditionIdentity.fromJson({
      ...exactEdition.toJson(),
      'providerIds': {'screenscraper': '42'}
    }));
    expect(await group('conflicting'), await group('ordinary'));
  });

  test(
      'identity correction and classification changes update grouping atomically',
      () async {
    await edition('first');
    await edition('second', providerId: '43');
    expect(await group('first'), isNot(await group('second')));
    await store.putGame(GameIdentity(
        id: 'game:second',
        platformId: 'psx',
        title: 'Localized title',
        providerIds: {'screenscraper': '42'},
        matchStatus: IdentityMatchStatus.manuallyMatched));
    expect(await group('first'), await group('second'));
    await store.putEdition(EditionIdentity(
        id: 'second',
        gameId: 'game:second',
        tags: {'Hack'},
        patchId: 'different-project'));
    expect(await group('first'), isNot(await group('second')));
  });

  test('explicit multi-disc game groups once without collapsing its members',
      () async {
    await store
        .putGame(GameIdentity(id: 'multi', platformId: 'psx', title: 'Multi'));
    for (final disc in [1, 2]) {
      await store.putEdition(
          EditionIdentity(id: 'disc:$disc', gameId: 'multi', members: [
        EditionMember(
            discNumber: disc,
            artifactId: RemoteArtifactId(
                providerId: 'drive',
                sourceId: 's',
                accountId: 'a',
                providerFileId: '$disc'))
      ]));
    }
    expect(await group('disc:1'), await group('disc:2'));
    expect((await store.edition('disc:2'))!.members.single.discNumber, 2);
  });

  test(
      'canonical edition selection is bounded stable and detects stale bindings',
      () async {
    await edition('a');
    await edition('b');
    await edition('c');
    final first = await store.canonicalEditions('a', limit: 2);
    expect(first.editions.map((e) => e.id), ['a', 'b']);
    expect(first.nextEditionId, 'b');
    final second = await store.canonicalEditions('a',
        limit: 2, afterEditionId: first.nextEditionId);
    expect(second.editions.map((e) => e.id), ['c']);
    expect(second.nextEditionId, isNull);
    await db.update('library_canonical_groups', {'identity_key': 'stale'},
        where: 'edition_id = ?', whereArgs: ['b']);
    expect((await store.canonicalEditions('a')).editions.map((e) => e.id),
        ['a', 'c']);
    expect((await store.canonicalEditions('b')).editions, isEmpty);
    await expectLater(
        store.canonicalEditions('a', limit: 129), throwsArgumentError);
    final plan = await db.rawQuery('''EXPLAIN QUERY PLAN SELECT edition_id
      FROM library_canonical_groups WHERE group_key = ? AND edition_id > ?
      ORDER BY edition_id LIMIT 2''', [await group('a'), 'a']);
    expect(
        plan.any((row) =>
            '${row['detail']}'.contains('idx_library_canonical_group')),
        isTrue);
  });

  test('canonical backfill and selection remain paged for 30000 games',
      () async {
    final rssBefore = ProcessInfo.currentRss;
    await db.transaction((txn) async {
      for (var start = 0; start < 30000; start += 128) {
        final batch = txn.batch();
        final end = (start + 128).clamp(0, 30000);
        for (var n = start; n < end; n++) {
          final id = n.toString().padLeft(8, '0');
          final game = GameIdentity(
              id: 'g$id',
              platformId: 'psx',
              title: 'Game $n',
              providerIds: {'screenscraper': '$n'},
              matchStatus: IdentityMatchStatus.manuallyMatched);
          final edition =
              EditionIdentity(id: 'e$id', gameId: game.id, tags: {'official'});
          batch.insert('library_game_identities', {
            'game_id': game.id,
            'platform_id': game.platformId,
            'title': game.title,
            'match_status': game.matchStatus.name,
            'record_json': jsonEncode(game.toJson()),
          });
          batch.insert('library_editions', {
            'edition_id': edition.id,
            'game_id': edition.gameId,
            'record_json': jsonEncode(edition.toJson()),
          });
        }
        await batch.commit(noResult: true);
      }
      await LibraryStore.indexCanonicalGroups(txn);
    });
    expect(
        (await db.rawQuery(
                'SELECT COUNT(DISTINCT group_key) AS n FROM library_canonical_groups'))
            .single['n'],
        30000);
    expect(
        (await store.canonicalEditions('e00000042', limit: 8))
            .editions
            .single
            .id,
        'e00000042');
    // Observed resource evidence, not a timeout or lifecycle/success heuristic.
    // ignore: avoid_print
    print(
        'canonical grouping 30000 games: pid=$pid rssBefore=$rssBefore rssAfter=${ProcessInfo.currentRss}');
  }, timeout: Timeout.none);
}
