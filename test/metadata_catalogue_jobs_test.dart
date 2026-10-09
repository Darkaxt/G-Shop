import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/drive/drive_catalogue.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';
import 'package:retro_eshop/services/drive/drive_media.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';

class _ReviewProvider implements MetadataProvider {
  int calls = 0;
  final requests = <MetadataLookupRequest>[];
  Future<MetadataLookupResult> Function(MetadataLookupRequest)? reply;
  Future<void> Function()? beforeResult;
  @override
  String get providerId => 'screenscraper';
  @override
  MetadataProviderCapabilities get capabilities =>
      const MetadataProviderCapabilities(
          fields: {},
          verifiedIdLookup: true,
          rawRomLookup: false,
          titleSearch: true,
          documentedVoteCounts: false);
  @override
  void close() {}
  @override
  Future<MetadataLookupResult> lookup(MetadataLookupRequest request,
      {CancelToken? cancelToken}) async {
    calls++;
    requests.add(request);
    await beforeResult?.call();
    if (reply != null) return reply!(request);
    return MetadataLookupResult(
        status: MetadataLookupStatus.needsReview,
        message: 'Review required',
        candidates: [
          MetadataLookupCandidate(
              providerGameId: '42',
              platformId: request.platformId,
              titles: [MetadataText(text: request.title)],
              titleMatched: true,
              evidence: 'platformAndTitle')
        ]);
  }
}

void main() {
  late Database db;
  late MetadataRefreshJobs jobs;
  late LibraryStore store;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games (
      id INTEGER PRIMARY KEY AUTOINCREMENT, systemSlug TEXT NOT NULL,
      filename TEXT NOT NULL, displayName TEXT NOT NULL,
      is_folder INTEGER NOT NULL DEFAULT 0, artifact_key TEXT,
      remote_artifact TEXT)''');
    jobs = MetadataRefreshJobs(Future.value(db));
    store = LibraryStore(Future.value(db));
  });
  tearDown(() => db.close());

  Future<int> cache(String system, String name,
          {RemoteArtifact? artifact, bool folder = false}) =>
      db.insert('games', {
        'systemSlug': system,
        'filename': name,
        'displayName': name.split(' (').first.split('.').first,
        'is_folder': folder ? 1 : 0,
        'artifact_key': artifact?.id.key,
        'remote_artifact':
            artifact == null ? null : jsonEncode(artifact.toJson()),
      });

  RemoteArtifact remote(String file,
          {String account = 'account',
          String version = '1',
          String checksum = 'a'}) =>
      RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: 'source',
            accountId: account,
            providerFileId: file),
        displayPath: 'Super Mario World (USA).zip',
        displayName: 'Super Mario World (USA).zip',
        version: version,
        sizeBytes: 100,
        providerChecksums: {'md5': checksum * 32},
      );

  Future<List<Map<String, Object?>>> items(int job) =>
      db.query('metadata_refresh_items',
          where: 'job_id = ?', whereArgs: [job], orderBy: 'edition_id');

  test('catalogue filenames supply only unambiguous lookup region hints',
      () async {
    final cases = <String, String?>{
      'Fixture (USA) (En,Ja).chd': 'us',
      'Fixture [JP].zip': 'jp',
      'Fixture (Europe).rvz': 'eu',
      'Fixture (World).7z': 'wor',
      'Fixture (USA, Europe).chd': null,
      'Fixture (USA) [Japan].chd': null,
      'Fixture (USA, Unknown).chd': null,
      'Fixture (En,Ja).chd': null,
      'USA Adventure.chd': null,
    };
    var index = 0;
    for (final entry in cases.entries) {
      final artifact = RemoteArtifact.fromJson({
        ...remote('region-${index++}').toJson(),
        'displayName': entry.key,
        'displayPath': 'Folder (Japan)/${entry.key}',
      });
      await cache('psx', entry.key, artifact: artifact);
    }
    // Legacy catalogue entries use their original filename too, not cleanTitle.
    await cache('snes', 'Legacy (USA).zip');
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final before = <String, String>{};
    for (final row in await items(job.id)) {
      final editionId = row['edition_id'] as String;
      final edition = (await store.edition(editionId))!;
      before[editionId] = jsonEncode(edition.toJson());
      final request = jsonDecode(row['request_json'] as String);
      final raw = edition.members.isEmpty
          ? <Map<String, Object?>>[]
          : await db.query('library_artifacts',
              where: 'artifact_id = ?',
              whereArgs: [edition.members.single.artifactId.key],
              limit: 1);
      final name = raw.isEmpty
          ? 'Legacy (USA).zip'
          : jsonDecode(raw.single['record_json'] as String)['displayName']
              as String;
      expect(request['region'], name.startsWith('Legacy') ? 'us' : cases[name],
          reason: name);
      expect(edition.regions, isEmpty);
      expect(edition.tags, isNot(contains('official')));
      expect(request['verifiedProviderGameId'], isNull);
      expect(request['romIdentifier'], isNull);
    }
    final provider = _ReviewProvider();
    final result = await jobs.run(job.id, provider);
    expect(result.rated, 0);
    expect(
        (await items(job.id)).where((r) => r['status'] == 'matched'), isEmpty);
    for (final entry in before.entries) {
      expect(
          jsonEncode((await store.edition(entry.key))!.toJson()), entry.value);
    }
  });

  test(
      'explicit unknown or multi-region facts are not replaced by filename hints',
      () async {
    await cache('psx', 'Fixture (USA).chd', artifact: remote('manual-region'));
    final first = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final id = (await items(first.id)).single['edition_id'] as String;
    final edition = (await store.edition(id))!;
    for (final regions in [
      <String>[],
      ['jp', 'eu'],
      ['jp']
    ]) {
      await store.putEdition(EditionIdentity.fromJson({
        ...edition.toJson(),
        'regions': regions,
        'evidence': [
          ...edition.evidence.map((e) => e.toJson()),
          IdentityEvidence(
                  source: 'manual', kind: 'releaseRegion', value: 'unknown')
              .toJson(),
        ],
      }));
      final next = await jobs.createFromCatalogue(providerId: 'screenscraper');
      final request =
          jsonDecode((await items(next.id)).single['request_json'] as String);
      expect(request['region'], regions.length == 1 ? 'jp' : null);
      expect((await store.edition(id))!.regions, regions);
    }
  });

  Future<RemoteArtifact> inFolder(String path, {List<String>? folders}) async {
    await DriveCatalogueSchema.install(db);
    const scope = '["source","account","root-folder"]';
    await db.insert(
        'drive_catalogue_state',
        {
          'scope': scope,
          'active': 1,
          'next_generation': 2,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    await db.delete('drive_catalogue_entries',
        where: 'scope = ?', whereArgs: [scope]);
    final labels = folders ?? (path.split('/')..removeLast());
    String? parent;
    for (var i = 0; i < labels.length; i++) {
      final id = i == 0 ? 'root-folder' : 'folder-$i';
      final folder = DriveFile(
          id: id,
          name: labels[i],
          mimeType: DriveFile.folderMime,
          parents: [if (parent != null) parent]);
      await db.insert('drive_catalogue_entries', {
        'scope': scope,
        'generation': 1,
        'file_id': id,
        'parent_id': parent,
        'display_path': labels.take(i + 1).join('/'),
        'is_folder': 1,
        'record_json': jsonEncode(folder.toJson()),
      });
      parent = id;
    }
    final file = DriveFile(
        id: 'classified-file',
        name: 'Game.chd',
        mimeType: 'application/octet-stream',
        parents: [parent!],
        sizeBytes: 100,
        version: '1',
        checksums: {'md5': 'a' * 32});
    await db.insert('drive_catalogue_entries', {
      'scope': scope,
      'generation': 1,
      'file_id': file.id,
      'parent_id': parent,
      'display_path': path,
      'is_folder': 0,
      'record_json': jsonEncode(file.toJson()),
    });
    return file.artifact(
        sourceId: 'source', accountId: 'account', displayPath: path);
  }

  test(
      'catalogue folder classification carries declared overlapping tags into lookup',
      () async {
    await LibraryQuery.install(db);
    await cache('psp', 'Game (Japan).chd',
        artifact: await inFolder(
            'Sony - PlayStation Portable/T-En/Undub/Uncensor/Game (Japan).chd'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final row = (await items(job.id)).single;
    final request = jsonDecode(row['request_json'] as String);
    final edition = (await store.edition(row['edition_id'] as String))!;
    expect(request['contentTags'],
        unorderedEquals(['T-Eng', 'Undub', 'Uncensor']));
    expect(request['verifiedProviderGameId'], isNull);
    expect(request['romIdentifier'], isNull);
    expect(edition.isTranslation, true);
    expect(edition.translatedLanguages, ['en']);
    expect(
        edition.evidence.any((e) =>
            e.source == 'catalogue' && e.kind == 'sourceFolderClassification'),
        true);
    expect((await store.game(edition.gameId))!.matchStatus,
        IdentityMatchStatus.unmatched);
    final query = await LibraryQuery(Future.value(db)).page(
        filter: LibraryQueryFilter(
            tags: {'T-Eng', 'Undub', 'Uncensor'}, matchAllTags: true));
    expect(query.items.single.editionId, edition.id);
    expect(query.rankedGames, 0);
  });

  test(
      'catalogue folder classification does not guess ordinary or filename tags',
      () async {
    for (final path in [
      'Sony - PlayStation Portable/Game (USA) (En).chd',
      'Sony - PlayStation Portable/Not T-En/Game.chd',
      'Sony - PlayStation Portable/Game T-En.chd',
    ]) {
      await db.delete('games');
      await cache('psp', 'Game.chd', artifact: await inFolder(path));
      final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
      final row = (await items(job.id)).single;
      final request = jsonDecode(row['request_json'] as String);
      expect(request['contentTags'], isEmpty);
      expect((await store.edition(row['edition_id'] as String))!.isTranslation,
          isNull);
    }
  });

  test(
      'catalogue folder classification does not assume translations are English',
      () async {
    await cache('psp', 'Game.chd',
        artifact: await inFolder(
            'Sony - PlayStation Portable/Translations/Game.chd'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final row = (await items(job.id)).single;
    final edition = (await store.edition(row['edition_id'] as String))!;
    expect(edition.tags, isEmpty);
    expect(edition.isTranslation, true);
    expect(edition.translatedLanguages, isEmpty);
  });

  test('declared modified folder supersedes automatic official classification',
      () async {
    final id = await cache('psp', 'Game.chd',
        artifact: await inFolder('Sony - PlayStation Portable/Game.chd'));
    final first = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await items(first.id)).single['edition_id'] as String;
    final edition = (await store.edition(editionId))!;
    await store.putEdition(EditionIdentity.fromJson({
      ...edition.toJson(),
      'tags': ['official'],
      'isTranslation': false,
      'evidence': [
        ...edition.evidence.map((e) => e.toJson()),
        IdentityEvidence(
                source: 'screenscraper',
                kind: 'exactRomOfficialRelease',
                value: '{"regions":[],"languages":[]}')
            .toJson()
      ]
    }));
    await db.update(
        'games',
        {
          'remote_artifact': jsonEncode((await inFolder(
                  'Sony - PlayStation Portable/T-En/Undub/Game.chd'))
              .toJson())
        },
        where: 'id = ?',
        whereArgs: [id]);
    final moved = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final request =
        jsonDecode((await items(moved.id)).single['request_json'] as String);
    expect(request['contentTags'], unorderedEquals(['T-Eng', 'Undub']));
    final after = (await store.edition(editionId))!;
    expect(after.isTranslation, true);
    expect(after.evidence.where((e) => e.kind == 'exactRomOfficialRelease'),
        isEmpty);
    expect(
        after.evidence
            .where((e) => e.kind == 'previousExactRomOfficialRelease'),
        hasLength(1));
  });

  test('catalogue folder classification updates owned evidence after a move',
      () async {
    final id = await cache('psp', 'Game.chd',
        artifact: await inFolder('Sony - PlayStation Portable/T-En/Game.chd'));
    final first = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await items(first.id)).single['edition_id'] as String;
    expect((await store.edition(editionId))!.tags, {'T-Eng'});
    await db.update(
        'games',
        {
          'remote_artifact': jsonEncode(
              (await inFolder('Sony - PlayStation Portable/Undub/Game.chd'))
                  .toJson())
        },
        where: 'id = ?',
        whereArgs: [id]);
    final moved = await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect((await items(moved.id)).single['edition_id'], editionId);
    final edition = (await store.edition(editionId))!;
    expect(edition.tags, {'Undub'});
    expect(edition.isTranslation, isNull);
    expect(edition.translatedLanguages, isEmpty);
  });

  test(
      'catalogue folder classification preserves reviewed corrections and raw aliases',
      () async {
    final id = await cache('psp', 'Game.chd',
        artifact: await inFolder('Sony - PlayStation Portable/T-En/Game.chd'));
    final first = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await items(first.id)).single['edition_id'] as String;
    final edition = (await store.edition(editionId))!;
    final corrected = {
      ...edition.toJson(),
      'tags': ['Dubbed'],
      'isTranslation': false,
      'translatedLanguages': <String>[],
      'evidence': [
        IdentityEvidence(
                source: 'manual',
                kind: 'contentClassification',
                value: '["Dub"]')
            .toJson()
      ]
    };
    await db.update('library_editions', {'record_json': jsonEncode(corrected)},
        where: 'edition_id = ?', whereArgs: [editionId]);
    await db.update(
        'games',
        {
          'remote_artifact': jsonEncode((await inFolder(
                  'Sony - PlayStation Portable/Hacks/Undub/Game.chd'))
              .toJson())
        },
        where: 'id = ?',
        whereArgs: [id]);
    await jobs.createFromCatalogue(providerId: 'screenscraper');
    final stored = (await db.query('library_editions',
            where: 'edition_id = ?', whereArgs: [editionId]))
        .single;
    final after = jsonDecode(stored['record_json'] as String);
    expect(after['tags'], ['Dubbed']);
    expect(after['isTranslation'], false);
    expect(after['translatedLanguages'], isEmpty);
  });

  test('catalogue folder classification does not split a Drive folder name',
      () async {
    await cache('psp', 'Game.chd',
        artifact: await inFolder(
            'Sony - PlayStation Portable/Not/T-En/Game.chd',
            folders: ['Sony - PlayStation Portable', 'Not/T-En']));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await items(job.id)).single['edition_id'] as String;
    expect((await store.edition(editionId))!.tags, isEmpty);
  });

  test(
      'catalogue folder classification clears only its own facts outside declared folders',
      () async {
    final id = await cache('psp', 'Game.chd',
        artifact: await inFolder('Sony - PlayStation Portable/T-En/Game.chd'));
    final first = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await items(first.id)).single['edition_id'] as String;
    await db.update(
        'games',
        {
          'remote_artifact': jsonEncode(
              (await inFolder('Sony - PlayStation Portable/Game.chd')).toJson())
        },
        where: 'id=?',
        whereArgs: [id]);
    await jobs.createFromCatalogue(providerId: 'screenscraper');
    final edition = (await store.edition(editionId))!;
    expect(edition.tags, isEmpty);
    expect(edition.isTranslation, isNull);
    expect(edition.translatedLanguages, isEmpty);
    expect(
        edition.evidence.where((e) => e.kind == 'sourceFolderClassification'),
        isEmpty);
  });

  test(
      'catalogue folder classification requires its own published account scope',
      () async {
    final artifact =
        await inFolder('Sony - PlayStation Portable/T-En/Game.chd');
    await cache('psp', 'Game.chd',
        artifact: RemoteArtifact.fromJson({
          ...artifact.toJson(),
          'id': {...artifact.id.toJson(), 'accountId': 'other-account'},
        }));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await items(job.id)).single['edition_id'] as String;
    expect((await store.edition(editionId))!.tags, isEmpty);
  });

  test('catalogue folder classification binds opaque encoded scope elements',
      () async {
    final original =
        await inFolder('Sony - PlayStation Portable/T-En/Game.chd');
    const source = 'source-"/😀';
    const account = 'account-"/😀';
    final scope = jsonEncode([source, account, 'root-folder']);
    await db.update('drive_catalogue_state', {'scope': scope});
    await db.update('drive_catalogue_entries', {'scope': scope});
    final artifact = RemoteArtifact.fromJson({
      ...original.toJson(),
      'id': {
        ...original.id.toJson(),
        'sourceId': source,
        'accountId': account,
      }
    });
    final id = await cache('psp', 'Game.chd', artifact: artifact);
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await items(job.id)).single['edition_id'] as String;
    expect((await store.edition(editionId))!.tags, {'T-Eng'});
    await db.update(
        'games',
        {
          'remote_artifact': jsonEncode(RemoteArtifact.fromJson({
            ...artifact.toJson(),
            'id': {
              ...artifact.id.toJson(),
              'accountId': '$account-other',
            }
          }).toJson()),
          'artifact_key': RemoteArtifactId(
                  providerId: 'drive',
                  sourceId: source,
                  accountId: '$account-other',
                  providerFileId: 'classified-file')
              .key
        },
        where: 'id=?',
        whereArgs: [id]);
    final other = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final otherEdition = (await items(other.id)).single['edition_id'] as String;
    expect((await store.edition(otherEdition))!.tags, isEmpty);
  });

  test(
      'catalogue folder classification ignores unpublished and missing ancestors',
      () async {
    final artifact =
        await inFolder('Sony - PlayStation Portable/T-En/Game.chd');
    await cache('psp', 'Game.chd', artifact: artifact);
    await db.update('drive_catalogue_state', {'active': null, 'pending': 1});
    final pending = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await items(pending.id)).single['edition_id'] as String;
    expect((await store.edition(editionId))!.tags, isEmpty);
    await db.update('drive_catalogue_state', {'active': 1, 'pending': null});
    await db.delete('drive_catalogue_entries',
        where: 'file_id=?', whereArgs: ['root-folder']);
    await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect((await store.edition(editionId))!.tags, isEmpty);
  });

  test('catalogue folder classification preserves unchanged identity bindings',
      () async {
    await cache('psp', 'Game.chd',
        artifact: await inFolder('Sony - PlayStation Portable/T-En/Game.chd'));
    await jobs.createFromCatalogue(providerId: 'screenscraper');
    final before = await db.query('library_editions');
    await db.execute('CREATE TABLE identity_mutations (name TEXT)');
    for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
      await db.execute('''CREATE TRIGGER observe_edition_$event
        AFTER $event ON library_editions BEGIN
        INSERT INTO identity_mutations VALUES ('edition'); END''');
    }
    await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect(await db.query('library_editions'), before);
    expect(await db.query('identity_mutations'), isEmpty);
  });

  test('unchanged catalogue capture preserves identities and canonical indexes',
      () async {
    await LibraryQuery.install(db);
    final cacheId = await cache('snes', 'Game.zip', artifact: remote('file'));
    final first = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await items(first.id)).single['edition_id'] as String;
    final edition = (await store.edition(editionId))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'providerIds': {'screenscraper': '42'},
      'matchStatus': 'manuallyMatched'
    }));
    await store.putEdition(EditionIdentity.fromJson({
      ...edition.toJson(),
      'tags': ['official']
    }));
    final identityBefore = await db.query('library_game_identities');
    final editionBefore = await db.query('library_editions');
    final claimsBefore = await db.query('library_canonical_claims');
    await db.execute('CREATE TABLE identity_mutations (name TEXT)');
    for (final table in [
      'library_game_identities',
      'library_editions',
      'library_artifacts',
      'library_canonical_groups',
      'library_canonical_claims'
    ]) {
      for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
        await db.execute('''CREATE TRIGGER observe_${table}_$event
          AFTER $event ON $table BEGIN
          INSERT INTO identity_mutations VALUES ('$table'); END''');
      }
    }
    // Fresh jobs must still revisit each identity, but unchanged catalogue
    // capture and the ensuing normal query must not rebuild its identity graph.
    final next = await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect(next.generation, greaterThan(first.generation));
    expect(next.counts, {'pending': 1});
    final request =
        jsonDecode((await items(next.id)).single['request_json'] as String);
    expect(request['verifiedProviderGameId'], '42');
    expect(await db.query('identity_mutations'), isEmpty);
    final page =
        await LibraryQuery(Future.value(db)).page(filter: LibraryQueryFilter());
    expect(page.collectionGames, 1);
    expect(await db.query('identity_mutations'), isEmpty);
    expect(await db.query('library_game_identities'), identityBefore);
    expect(await db.query('library_editions'), editionBefore);
    expect(await db.query('library_canonical_claims'), claimsBefore);

    // A real content change still invalidates the match and reindexes claims.
    await db.update(
        'games',
        {
          'remote_artifact':
              jsonEncode(remote('file', version: '2', checksum: 'b').toJson())
        },
        where: 'id = ?',
        whereArgs: [cacheId]);
    final changed = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final changedRequest =
        jsonDecode((await items(changed.id)).single['request_json'] as String);
    expect(changedRequest['verifiedProviderGameId'], isNull);
    expect((await store.game(game.id))!.matchStatus,
        IdentityMatchStatus.unmatched);
    expect(await db.query('identity_mutations'), isNotEmpty);
    expect(await db.query('library_canonical_claims'), isNot(claimsBefore));
  }, timeout: Timeout.none);

  test(
      'cached catalogue snapshots all games, excludes folders and scopes systems',
      () async {
    await cache('snes', 'Super Mario World (USA).zip',
        artifact: remote('file'));
    await cache('nes', 'Super Mario Bros.nes');
    await cache('nes', 'Folder', folder: true);
    final full = await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect(full.counts, {'pending': 2});
    final scoped = await jobs.createFromCatalogue(
        providerId: 'screenscraper', systemSlug: 'snes');
    final request =
        jsonDecode((await items(scoped.id)).single['request_json'] as String);
    expect(scoped.counts, {'pending': 1});
    expect(request['platformId'], 'snes');
    expect(request['romIdentifier'], isNull,
        reason: 'ZIP checksums are not raw-ROM identifiers.');
    expect(request['contentTags'], isEmpty,
        reason: 'Official release classification requires evidence.');
    expect(request['verifiedProviderGameId'], isNull);
    await cache('gba', 'Added later.gba');
    expect((await items(full.id)).length, 2,
        reason: 'Published job membership is immutable.');
  });

  test('normal catalogue snapshot uses exact uncompressed Drive identifiers',
      () async {
    final artifact = RemoteArtifact.fromJson({
      ...remote('raw').toJson(),
      'displayName': 'Game (USA).sfc',
      'displayPath': 'Game (USA).sfc',
      'providerChecksums': {'md5': 'a' * 32, 'sha1': 'b' * 40},
    });
    await cache('snes', 'Game (USA).sfc', artifact: artifact);
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final request = MetadataLookupRequest.fromJson(
        jsonDecode((await items(job.id)).single['request_json'] as String));
    expect(request.romIdentifier, isNotNull);
    expect(request.romIdentifier!.kind, RomIdentifierKind.rawRom);
    expect(request.romIdentifier!.filename, artifact.displayName);
    expect(request.romIdentifier!.sizeBytes, 100);
    expect(request.romIdentifier!.md5, 'a' * 32);
    expect(request.romIdentifier!.sha1, 'b' * 40);
    expect(request.contentTags, isEmpty);
  });

  test(
      'normal archive jobs bind raw members atomically and reuse current evidence',
      () async {
    final artifact = RemoteArtifact.fromJson({
      ...remote('archive').toJson(),
      'displayName': 'Game (USA).7z',
      'displayPath': 'Game (USA).7z',
      'canDownload': true
    });
    final cacheId =
        await cache('n64', artifact.displayName, artifact: artifact);
    var reads = 0;
    const raw = MetadataRomIdentifier(
        kind: RomIdentifierKind.rawRom,
        filename: 'Game (USA).z64',
        sizeBytes: 8192,
        md5: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        sha1: 'cccccccccccccccccccccccccccccccccccccccc');
    jobs = MetadataRefreshJobs(Future.value(db),
        readArchiveIdentifier: (source, platform, cancel) async {
      reads++;
      expect(source.toJson(), artifact.toJson());
      expect(platform, 'n64');
      return raw;
    });
    final provider = _ReviewProvider();
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, provider);
    expect(provider.requests.single.romIdentifier?.toJson(), raw.toJson());
    expect(reads, 1);
    final editionId = (await items(job.id)).single['edition_id'] as String;
    final edition = (await store.edition(editionId))!;
    expect(edition.tags, isEmpty,
        reason: 'The byte read itself does not classify a game.');
    expect(
        edition.evidence
            .singleWhere((e) => e.kind == 'rawRomIdentifier')
            .source,
        'driveLocalArchive');
    expect(
        jsonDecode(edition.evidence
            .singleWhere((e) => e.kind == 'rawRomArchiveSource')
            .value)['artifact'],
        artifact.toJson());
    final restarted = MetadataRefreshJobs(Future.value(db),
        readArchiveIdentifier: (_, __, ___) async {
      fail('Unchanged archive evidence must survive restart');
    });
    final next =
        await restarted.createFromCatalogue(providerId: 'screenscraper');
    await restarted.run(next.id, provider);
    expect(provider.requests.last.romIdentifier?.toJson(), raw.toJson());
    await db.update(
        'games',
        {
          'remote_artifact': jsonEncode(RemoteArtifact.fromJson({
            ...artifact.toJson(),
            'version': '2',
            'providerChecksums': {'md5': 'd' * 32}
          }).toJson())
        },
        where: 'id = ?',
        whereArgs: [cacheId]);
    final changed = await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect(
        jsonDecode((await items(changed.id)).single['request_json'] as String)[
            'romIdentifier'],
        isNull);
  });

  for (final platform in ['gb', 'gbc', 'gba', 'nes', 'snes']) {
    test('$platform job leaves unsupported ZIP identity unresolved', () async {
      final artifact = RemoteArtifact.fromJson({
        ...remote('archive').toJson(),
        'displayName': 'Game.zip',
        'displayPath': 'Game.zip',
        'canDownload': true
      });
      await cache(platform, artifact.displayName, artifact: artifact);
      jobs = MetadataRefreshJobs(Future.value(db),
          readArchiveIdentifier: (_, __, ___) async {
        fail('The explicitly supported handheld profile is 7z only');
      });
      final provider = _ReviewProvider();
      final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
      await jobs.run(job.id, provider);
      expect(provider.requests.single.romIdentifier, isNull);
    });
    test('$platform normal jobs persist exact local 7z member evidence once',
        () async {
      final artifact = RemoteArtifact.fromJson({
        ...remote('archive').toJson(),
        'displayName': 'Game (USA).7z',
        'displayPath': 'Game (USA).7z',
        'canDownload': true
      });
      await cache(platform, artifact.displayName, artifact: artifact);
      var reads = 0;
      final raw = MetadataRomIdentifier(
          kind: RomIdentifierKind.rawRom,
          filename: platform == 'snes' ? 'Game.sfc' : 'Game.$platform',
          sizeBytes: 8192,
          md5: 'b' * 32,
          sha1: 'c' * 40);
      jobs = MetadataRefreshJobs(Future.value(db),
          readArchiveIdentifier: (source, mapped, cancel) async {
        expect(mapped, platform);
        expect(source.toJson(), artifact.toJson());
        reads++;
        return raw;
      });
      final provider = _ReviewProvider();
      final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
      await jobs.run(job.id, provider);
      expect(provider.requests.single.romIdentifier?.toJson(), raw.toJson());
      expect(reads, 1);
      final edition = (await store
          .edition((await items(job.id)).single['edition_id'] as String))!;
      expect(edition.tags, isEmpty,
          reason: 'Reading raw bytes does not infer official status');
      expect(
          edition.evidence
              .singleWhere((e) => e.kind == 'rawRomIdentifier')
              .source,
          'driveLocalArchive');
      final restarted = MetadataRefreshJobs(Future.value(db),
          readArchiveIdentifier: (_, __, ___) async {
        fail('Unchanged local archive evidence must survive restart');
      });
      final next =
          await restarted.createFromCatalogue(providerId: 'screenscraper');
      await restarted.run(next.id, provider);
      expect(provider.requests.last.romIdentifier?.toJson(), raw.toJson());
    });
  }

  for (final (platform, extension) in [('megadrive', 'md'), ('mastersystem', 'sms'), ('sg1000', 'sg')]) {
    test('$platform normal jobs persist local Sega ZIP evidence across restart', () async {
      final artifact = RemoteArtifact.fromJson({...remote('archive').toJson(),
        'displayName': 'Game (USA).zip', 'displayPath': 'Game (USA).zip', 'canDownload': true});
      await cache(platform, artifact.displayName, artifact: artifact);
      var reads = 0;
      final raw = MetadataRomIdentifier(kind: RomIdentifierKind.rawRom,
          filename: 'Game.$extension', sizeBytes: 8192, md5: 'b' * 32, sha1: 'c' * 40);
      jobs = MetadataRefreshJobs(Future.value(db), readArchiveIdentifier: (source, mapped, cancel) async {
        expect(mapped, platform);
        expect(source.toJson(), artifact.toJson());
        reads++;
        return raw;
      });
      final provider = _ReviewProvider();
      final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
      await jobs.run(job.id, provider);
      expect(provider.requests.single.romIdentifier?.toJson(), raw.toJson());
      expect(reads, 1);
      final edition = (await store.edition((await items(job.id)).single['edition_id'] as String))!;
      expect(edition.tags, isEmpty, reason: 'Raw evidence cannot manufacture official classification');
      expect(edition.evidence.singleWhere((e) => e.kind == 'rawRomIdentifier').source, 'driveLocalArchive');
      final restarted = MetadataRefreshJobs(Future.value(db), readArchiveIdentifier: (_, __, ___) async {
        fail('Unchanged raw evidence must survive restart');
      });
      final next = await restarted.createFromCatalogue(providerId: 'screenscraper');
      await restarted.run(next.id, provider);
      expect(provider.requests.last.romIdentifier?.toJson(), raw.toJson());
    });
  }

  test('archive changed during identification cannot publish raw evidence',
      () async {
    final artifact = RemoteArtifact.fromJson({
      ...remote('archive').toJson(),
      'displayName': 'Game.7z',
      'displayPath': 'Game.7z',
      'canDownload': true
    });
    await cache('n64', artifact.displayName, artifact: artifact);
    jobs = MetadataRefreshJobs(Future.value(db),
        readArchiveIdentifier: (_, __, ___) async {
      await db.update('library_artifacts', {
        'record_json': jsonEncode(
            RemoteArtifact.fromJson({...artifact.toJson(), 'version': '2'})
                .toJson())
      });
      return const MetadataRomIdentifier(
          kind: RomIdentifierKind.rawRom,
          filename: 'Game.z64',
          sizeBytes: 8192,
          sha1: 'cccccccccccccccccccccccccccccccccccccccc');
    });
    final provider = _ReviewProvider();
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect((await jobs.run(job.id, provider)).counts, {'identityChanged': 1});
    expect(provider.calls, 0);
    final edition = (await store
        .edition((await items(job.id)).single['edition_id'] as String))!;
    expect(
        edition.evidence.where((e) => e.kind == 'rawRomIdentifier'), isEmpty);
  });

  for (final tag in ['Hack', 'unknown']) {
    test('local archive identification preserves explicit $tag classification', () async {
      final artifact = RemoteArtifact.fromJson({...remote('archive').toJson(),
        'displayName': 'Game.7z', 'displayPath': 'Game.7z', 'canDownload': true});
      await cache('n64', artifact.displayName, artifact: artifact);
      final initial = await jobs.createFromCatalogue(providerId: 'screenscraper');
      final edition = (await store.edition((await items(initial.id)).single['edition_id'] as String))!;
      await store.putEdition(EditionIdentity.fromJson({...edition.toJson(), 'tags': [tag],
        'evidence': [...edition.evidence.map((e) => e.toJson()),
          IdentityEvidence(source: 'manual', kind: 'contentClassification', value: 'reviewed').toJson()]}));
      jobs = MetadataRefreshJobs(Future.value(db), readArchiveIdentifier: (_, __, ___) async {
        fail('Explicit manual/modified classification must not be replaced by archive inference');
      });
      final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
      await jobs.run(job.id, _ReviewProvider());
      expect((await store.edition(edition.id))!.tags, {tag});
    });
  }

  test('cancelled local archive identification leaves the same job resumable', () async {
    final artifact = RemoteArtifact.fromJson({...remote('archive').toJson(),
      'displayName': 'Game.7z', 'displayPath': 'Game.7z', 'canDownload': true});
    await cache('n64', artifact.displayName, artifact: artifact);
    jobs = MetadataRefreshJobs(Future.value(db), readArchiveIdentifier: (_, __, cancel) async {
      cancel.cancel();
      return const MetadataRomIdentifier(kind: RomIdentifierKind.rawRom,
        filename: 'Game.z64', sizeBytes: 8192, sha1: 'cccccccccccccccccccccccccccccccccccccccc');
    });
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final provider = _ReviewProvider();
    final report = await jobs.run(job.id, provider);
    expect(report.state, 'paused'); expect(report.counts, {'pending': 1}); expect(provider.calls, 0);
    expect(jsonDecode((await items(job.id)).single['request_json'] as String)['romIdentifier'], isNull);
  });

  for (final archive in [true, false]) {
    test('changed Drive ${archive ? 'archive' : 'header'} source does not stall the saved collection', () async {
      String? changedFile;
      final reads = <String>[];
      Future<void> identify(RemoteArtifact artifact) async {
        reads.add(artifact.id.providerFileId);
        if (artifact.id.providerFileId == changedFile) {
          throw const DriveTransferException(DriveTransferIssue.sourceChanged);
        }
      }
      jobs = MetadataRefreshJobs(Future.value(db),
          readArchiveIdentifier: (artifact, _, __) async {
            await identify(artifact);
            return null;
          },
          readRomHeader: (artifact, _, __) async {
            await identify(artifact);
            return null;
          });
      for (final name in ['First', 'Second']) {
        final filename = '$name.${archive ? '7z' : 'chd'}';
        final artifact = RemoteArtifact.fromJson({
          ...remote(name).toJson(),
          'displayName': filename,
          'displayPath': filename,
          'sizeBytes': 1024,
          'canDownload': true,
        });
        await cache(archive ? 'n64' : 'psp', filename, artifact: artifact);
      }
      final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
      final captured = await items(job.id);
      final changedEditionId = captured.first['edition_id'] as String;
      final changedEdition = (await store.edition(changedEditionId))!;
      changedFile = changedEdition.members.single.artifactId.providerFileId;
      final provider = _ReviewProvider();

      final result = await jobs.run(job.id, provider);

      expect(result.state, 'completed');
      expect(result.counts, {'identityChanged': 1, 'needsReview': 1});
      expect(result.requested, 1);
      expect(result.rated, 0);
      expect(reads, hasLength(2));
      expect(reads.toSet(), {'First', 'Second'});
      expect(provider.requests.single.editionId, isNot(changedEditionId));
      expect(provider.requests.single.romIdentifier, isNull);
      final completed = await items(job.id);
      expect(completed.first, {...captured.first, 'status': 'identityChanged'});
      expect((await store.edition(changedEditionId))!.toJson(),
          changedEdition.toJson(),
          reason: 'Reject stale source evidence without rebinding or classifying it');
      expect((await db.query('metadata_refresh_jobs')), hasLength(1));

      final restarted = MetadataRefreshJobs(Future.value(db),
          readArchiveIdentifier: (_, __, ___) async {
            fail('Terminal captured items must not be re-read after restart');
          }, readRomHeader: (_, __, ___) async {
            fail('Terminal captured items must not be re-read after restart');
          });
      expect((await restarted.run(job.id, provider)).counts, result.counts);
      expect(provider.calls, 1);
      expect((await db.query('metadata_refresh_jobs')), hasLength(1));
    });
  }

  for (final archive in [true, false]) {
    for (final transfer in [false, true]) {
      test('pause joins ${archive ? 'archive' : 'header'} '
          '${transfer ? 'transfer' : 'API'} cancellation without failure', () async {
        final artifact = RemoteArtifact.fromJson({
          ...remote('cancel-read').toJson(),
          'displayName': archive ? 'Game.7z' : 'Game.chd',
          'displayPath': archive ? 'Game.7z' : 'Game.chd',
          'sizeBytes': 1024,
          'canDownload': true,
        });
        await cache(archive ? 'n64' : 'psp', artifact.displayName,
            artifact: artifact);
        final entered = Completer<void>(), drained = Completer<void>();
        var resumed = false;
        Future<void> read(CancelToken cancel) async {
          if (resumed) return;
          entered.complete();
          await cancel.whenCancel;
          await drained.future;
          if (transfer) {
            throw const DriveTransferException(DriveTransferIssue.cancelled);
          }
          throw const DriveApiException(DriveApiIssue.cancelled);
        }

        jobs = MetadataRefreshJobs(Future.value(db),
            readArchiveIdentifier: (_, __, cancel) async {
          await read(cancel);
          return null;
        }, readRomHeader: (_, __, cancel) async {
          await read(cancel);
          return null;
        });
        final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
        final before = jsonEncode((await items(job.id)).single);
        final provider = _ReviewProvider();
        final run = jobs.run(job.id, provider);
        final runCheck = expectLater(run,
            completion(isA<MetadataRefreshReport>().having((r) => r.state, 'state', 'paused')));
        await entered.future;
        var joined = false;
        final pause = jobs.pause().then((_) => joined = true);
        final pauseCheck = expectLater(pause, completes);
        await Future<void>.value();
        expect(joined, isFalse, reason: 'Pause must await the actual read drain');
        drained.complete();
        await runCheck;
        await pauseCheck;
        expect(joined, isTrue);
        expect((await jobs.report(job.id)).counts, {'pending': 1});
        expect(jsonEncode((await items(job.id)).single), before);
        expect(provider.calls, 0);
        final edition = (await store.edition(
            (await items(job.id)).single['edition_id'] as String))!;
        expect(edition.evidence.where((e) => e.kind == 'rawRomIdentifier'), isEmpty);
        resumed = true;
        expect((await jobs.run(job.id, provider)).state, 'completed');
        expect(provider.calls, 1);
        expect((await db.query('metadata_refresh_jobs')).length, 1);
      });
    }
  }

  for (final cancelOwner in [false, true]) {
    for (final error in <Exception>[
      const DriveApiException(DriveApiIssue.cancelled),
      const DriveTransferException(DriveTransferIssue.cancelled),
      const DriveApiException(DriveApiIssue.accessDenied),
      const DriveTransferException(DriveTransferIssue.sourceChanged),
      const DriveTransferException(DriveTransferIssue.unavailable),
      const FormatException('malformed native observation'),
    ]) {
      if (cancelOwner &&
          (error is DriveApiException && error.issue == DriveApiIssue.cancelled ||
              error is DriveTransferException && error.issue == DriveTransferIssue.cancelled)) {
        continue;
      }
      // The collection-continuation regressions above cover an uncancelled
      // source change. A different failure racing with Pause must still escape.
      if (!cancelOwner &&
          error is DriveTransferException &&
          error.issue == DriveTransferIssue.sourceChanged) {
        continue;
      }
      test('identifier read preserves ${error.runtimeType}:$error '
          'with owner cancellation=$cancelOwner', () async {
        final artifact = RemoteArtifact.fromJson({
          ...remote('read-error').toJson(),
          'displayName': 'Game.7z', 'displayPath': 'Game.7z', 'canDownload': true,
        });
        await cache('n64', artifact.displayName, artifact: artifact);
        jobs = MetadataRefreshJobs(Future.value(db),
            readArchiveIdentifier: (_, __, cancel) async {
          if (cancelOwner) cancel.cancel();
          throw error;
        });
        final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
        final provider = _ReviewProvider();
        await expectLater(jobs.run(job.id, provider), throwsA(same(error)));
        expect((await jobs.report(job.id)).state, 'paused');
        expect((await jobs.report(job.id)).counts, {'pending': 1});
        expect(provider.calls, 0);
      });
    }
  }

  test('replacement bytes cannot reuse an older explicit raw identifier',
      () async {
    final id = await cache('snes', 'Game.zip', artifact: remote('raw'));
    final first = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await items(first.id)).single['edition_id'] as String;
    final edition = (await store.edition(editionId))!;
    final raw = MetadataRomIdentifier(
        kind: RomIdentifierKind.rawRom,
        filename: 'Game.sfc',
        sizeBytes: 1024,
        sha1: 'b' * 40);
    await store.putEdition(EditionIdentity.fromJson({
      ...edition.toJson(),
      'evidence': [
        ...edition.evidence.map((e) => e.toJson()),
        IdentityEvidence(
                source: 'manual',
                kind: 'rawRomIdentifier',
                value: jsonEncode(raw.toJson()))
            .toJson()
      ]
    }));
    final unchanged =
        await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect(
        jsonDecode((await items(unchanged.id)).single['request_json']
            as String)['romIdentifier'],
        raw.toJson());
    await db.update(
        'games',
        {
          'remote_artifact':
              jsonEncode(remote('raw', version: '2', checksum: 'c').toJson())
        },
        where: 'id = ?',
        whereArgs: [id]);
    final changed = await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect(
        jsonDecode((await items(changed.id)).single['request_json'] as String)[
            'romIdentifier'],
        isNull);
    expect(
        (await store.edition(editionId))!
            .evidence
            .where((e) => e.kind == 'rawRomIdentifier'),
        hasLength(1),
        reason: 'manual evidence remains available for review');
  });

  test('exact artifact rename and cache reinsertion preserve reviewed identity',
      () async {
    final id = await cache('snes', 'Original.zip', artifact: remote('file'));
    final first = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await items(first.id)).single['edition_id'] as String;
    final edition = (await store.edition(editionId))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'title': 'Corrected title',
      'providerIds': {'screenscraper': '42'},
      'matchStatus': 'manuallyMatched'
    }));
    await store.putEdition(EditionIdentity.fromJson({
      ...edition.toJson(),
      'tags': ['official']
    }));
    await db.delete('games', where: 'id = ?', whereArgs: [id]);
    await cache('snes', 'Renamed.zip', artifact: remote('file', version: '2'));
    final refreshed =
        await jobs.createFromCatalogue(providerId: 'screenscraper');
    final next = (await items(refreshed.id)).single;
    expect(next['edition_id'], editionId);
    final request = jsonDecode(next['request_json'] as String);
    expect(request['verifiedProviderGameId'], '42');
    expect(request['title'], 'Corrected title');
    expect(request['contentTags'], ['official']);
  });

  test('same names in other accounts cannot share a game or edition', () async {
    await cache('snes', 'Same.zip', artifact: remote('file', account: 'one'));
    await cache('snes', 'Same.zip', artifact: remote('file', account: 'two'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final records = await items(job.id);
    expect(records.map((row) => row['edition_id']).toSet().length, 2);
    expect((await db.query('library_game_identities')).length, 2);
  });

  test(
      'changed remote bytes require renewed review without deleting correction evidence',
      () async {
    final id = await cache('snes', 'Game.zip', artifact: remote('file'));
    final first = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await items(first.id)).single['edition_id'] as String;
    final edition = (await store.edition(editionId))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'providerIds': {'screenscraper': '42'},
      'matchStatus': 'manuallyMatched'
    }));
    await db.update(
        'games',
        {
          'remote_artifact':
              jsonEncode(remote('file', version: '2', checksum: 'b').toJson())
        },
        where: 'id = ?',
        whereArgs: [id]);
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final request =
        jsonDecode((await items(job.id)).single['request_json'] as String);
    expect(request['verifiedProviderGameId'], isNull);
    expect((await store.game(game.id))!.providerIds, {'screenscraper': '42'});
  });

  test(
      'reviewed candidate and independent tags persist atomically with retry snapshot',
      () async {
    await cache('snes', 'Super Mario World.zip', artifact: remote('file'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, _ReviewProvider());
    final review = (await jobs.reviewItems(job.id)).single;
    expect(review.status, 'needsReview');
    expect(review.candidates.single.providerGameId, '42');
    final retry = await jobs.acceptCandidate(job.id,
        editionId: review.editionId,
        providerGameId: '42',
        contentTags: {'T-Eng', 'Undub', 'Uncensor'});
    expect(retry.generation, greaterThan(job.generation));
    expect(retry.counts, {'pending': 1});
    final request =
        jsonDecode((await items(retry.id)).single['request_json'] as String);
    expect(request['verifiedProviderGameId'], '42');
    expect(request['contentTags'], ['T-Eng', 'Uncensor', 'Undub']);
    expect((await store.edition(review.editionId))!.isTranslation, isTrue);
    expect(
        (await store.edition(review.editionId))!.translatedLanguages, ['en']);
    final refresh = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final persisted =
        jsonDecode((await items(refresh.id)).single['request_json'] as String);
    expect(persisted['verifiedProviderGameId'], '42');
    expect(persisted['contentTags'], request['contentTags']);
    expect(await store.metadata(review.editionId, 'screenscraper'), isNull);
  });

  for (final region in <String?>[null, '', 'USA']) {
    test(
        'reviewed region ${region ?? 'unchanged'} is atomic and survives capture',
        () async {
      await cache('snes', 'Game (Japan).zip', artifact: remote('region-file'));
      final first = await jobs.createFromCatalogue(providerId: 'screenscraper');
      final editionId = (await items(first.id)).single['edition_id'] as String;
      final edition = (await store.edition(editionId))!;
      await store.putEdition(EditionIdentity.fromJson({
        ...edition.toJson(),
        'regions': ['jp', 'eu']
      }));
      final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
      await jobs.run(job.id, _ReviewProvider());
      final beforeJobs = (await db.query('metadata_refresh_jobs')).length;
      await expectLater(
          jobs.acceptCandidate(job.id,
              editionId: editionId,
              providerGameId: '42',
              contentTags: {'official'},
              reviewedRegion: 'us\ninvalid'),
          throwsArgumentError);
      expect((await db.query('metadata_refresh_jobs')).length, beforeJobs);
      expect((await store.edition(editionId))!.regions, ['jp', 'eu']);
      final retry = await jobs.acceptCandidate(job.id,
          editionId: editionId,
          providerGameId: '42',
          contentTags: {'official'},
          reviewedRegion: region);
      final expected =
          region == null ? ['jp', 'eu'] : [if (region.isNotEmpty) region];
      expect((await store.edition(editionId))!.regions, expected);
      final refresh =
          await jobs.createFromCatalogue(providerId: 'screenscraper');
      expect((await store.edition(editionId))!.regions, expected);
      final request =
          jsonDecode((await items(retry.id)).single['request_json'] as String);
      final persisted = jsonDecode(
          (await items(refresh.id)).single['request_json'] as String);
      expect(request['region'], region == 'USA' ? 'USA' : null);
      expect(persisted['region'], request['region']);
    });
  }

  test(
      'review queue retains other editions across single-game retry and restart',
      () async {
    await cache('snes', 'First.zip', artifact: remote('first'));
    await cache('psx', 'Second.chd', artifact: remote('second'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, _ReviewProvider());
    final reviews = await jobs.reviewQueue('screenscraper');
    expect(reviews, hasLength(2));
    expect(reviews.every((r) => r.jobId == job.id), isTrue);
    expect(reviews.map((r) => r.request!.platformId).toSet(), {'snes', 'psx'});
    final chosen = reviews.first;
    await jobs.acceptCandidate(chosen.jobId,
        editionId: chosen.editionId,
        providerGameId: '42',
        contentTags: {'T-Eng', 'Undub'});
    final restored = MetadataRefreshJobs(Future.value(db));
    final remaining = await restored.reviewQueue('screenscraper');
    expect(remaining.map((r) => r.editionId), [reviews.last.editionId],
        reason: 'A latest one-game job must not hide the remaining full job.');
    expect(
        await restored.reviewQueue('screenscraper',
            editionId: chosen.editionId),
        isEmpty,
        reason: 'A superseded candidate cannot be accepted again.');
    await jobs.createFromCatalogue(providerId: 'igdb');
    expect(await restored.reviewQueue('screenscraper'), hasLength(1),
        reason: 'Another provider does not supersede this provider\'s review.');
  });

  test(
      'review queue pages and scopes newest outcomes without provider requests',
      () async {
    final firstCacheId =
        await cache('snes', 'First.zip', artifact: remote('first'));
    await cache('snes', 'Second.zip', artifact: remote('second'));
    await cache('psx', 'Third.chd', artifact: remote('third'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final provider = _ReviewProvider();
    await jobs.run(job.id, provider);
    final first = await jobs.reviewQueue('screenscraper', limit: 1);
    final next = await jobs.reviewQueue('screenscraper',
        afterEditionId: first.single.editionId, limit: 2);
    expect({...first, ...next}.map((r) => r.editionId).toSet(), hasLength(3));
    final scoped = await jobs.reviewQueue('screenscraper', systemSlug: 'snes');
    expect(scoped, hasLength(2));
    expect(scoped.every((r) => r.request!.platformId == 'snes'), isTrue);
    expect(
        await jobs.reviewQueue('screenscraper', editionId: next.last.editionId),
        hasLength(1));
    expect(provider.calls, 3);
    final exact =
        await jobs.reviewQueue('screenscraper', cacheRowId: firstCacheId);
    expect(exact.single.editionId,
        await LibraryStore.cachedCatalogueEditionId(db, firstCacheId));
    expect(await jobs.reviewQueue('screenscraper', cacheRowId: 999), isEmpty);
    expect(
        await jobs.reviewQueue('screenscraper',
            cacheRowId: firstCacheId,
            editionId: scoped
                .firstWhere((r) => r.editionId != exact.single.editionId)
                .editionId),
        isEmpty,
        reason:
            'A stale route binding must not select another cache artifact.');
    final uncaptured = await cache('snes', 'New.zip', artifact: remote('new'));
    expect(await jobs.reviewQueue('screenscraper', cacheRowId: uncaptured),
        isEmpty);
    expect(await db.query('library_editions'), hasLength(3),
        reason: 'Opening cached reviews must not create catalogue identities.');
    await expectLater(
        jobs.reviewQueue('screenscraper', limit: 129), throwsArgumentError);
    await jobs.createFromCatalogue(
        providerId: 'screenscraper', systemSlug: 'snes');
    expect(await jobs.reviewQueue('screenscraper'), hasLength(1),
        reason: 'Pending newer snapshots suppress obsolete review evidence.');
  });

  test(
      'superseded review cannot override a newer snapshot with unchanged bytes',
      () async {
    await cache('snes', 'First.zip', artifact: remote('first'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, _ReviewProvider());
    final old = (await jobs.reviewQueue('screenscraper')).single;
    await jobs.createFromCatalogue(providerId: 'screenscraper');
    await expectLater(
        jobs.acceptCandidate(old.jobId,
            editionId: old.editionId,
            providerGameId: '42',
            contentTags: {'official'}),
        throwsStateError);
    expect(await db.query('metadata_refresh_jobs'), hasLength(2));
    expect(
        (await store.game((await store.edition(old.editionId))!.gameId))!
            .providerIds,
        isEmpty);
  });

  test(
      'review page exposes changed or removed catalogue identity as not current',
      () async {
    final id = await cache('snes', 'First.zip', artifact: remote('first'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, _ReviewProvider());
    expect((await jobs.reviewQueue('screenscraper')).single.identityCurrent,
        isTrue);
    await db.update(
        'games',
        {
          'remote_artifact': jsonEncode(remote('first', checksum: 'b').toJson())
        },
        where: 'id = ?',
        whereArgs: [id]);
    expect((await jobs.reviewQueue('screenscraper')).single.identityCurrent,
        isFalse);
    await db.delete('games');
    expect((await jobs.reviewQueue('screenscraper')).single.identityCurrent,
        isFalse);
  });

  test(
      'reviewed tag aliases persist canonical classification and retry evidence',
      () async {
    await cache('snes', 'Fixture.zip', artifact: remote('file'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, _ReviewProvider());
    final review = (await jobs.reviewItems(job.id)).single;
    final retry = await jobs.acceptCandidate(job.id,
        editionId: review.editionId,
        providerGameId: '42',
        contentTags: {' T-En ', 'undubbed', 'UNCENSORED'});
    final request =
        jsonDecode((await items(retry.id)).single['request_json'] as String);
    expect(request['contentTags'], ['T-Eng', 'Uncensor', 'Undub']);
    final edition = (await store.edition(review.editionId))!;
    expect(edition.isTranslation, isTrue);
    expect(edition.translatedLanguages, ['en']);
    expect(
        jsonDecode(edition.evidence
            .singleWhere((e) => e.kind == 'contentClassification')
            .value),
        request['contentTags']);
    final refreshed =
        await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect(
        jsonDecode((await items(refreshed.id)).single['request_json']
            as String)['contentTags'],
        request['contentTags']);
    expect(await store.metadata(review.editionId, 'screenscraper'), isNull);
  });

  test(
      'catalogue review groups verified conversions without confusing changed bytes',
      () async {
    final firstRow = await cache('snes', 'Game.zip', artifact: remote('zip'));
    await cache('snes', 'Game.sfc', artifact: remote('raw'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, _ReviewProvider());
    final reviews = await jobs.reviewItems(job.id);
    expect(reviews, hasLength(2));
    for (final review in reviews) {
      await jobs.acceptCandidate(job.id,
          editionId: review.editionId,
          providerGameId: '42',
          contentTags: {'official'});
    }
    final anchor = reviews.first.editionId;
    expect((await store.canonicalEditions(anchor)).editions, hasLength(2));
    await jobs.createFromCatalogue(providerId: 'screenscraper');
    expect((await store.canonicalEditions(anchor)).editions, hasLength(2),
        reason: 'Re-scraping retains reviewed grouping and exact members.');

    await db.update('games',
        {'remote_artifact': jsonEncode(remote('zip', checksum: 'b').toJson())},
        where: 'id = ?', whereArgs: [firstRow]);
    final unchanged =
        reviews.singleWhere((r) => r.editionId != anchor).editionId;
    // Either selected anchor can be the changed artifact. The unchanged exact
    // member remains browsable; the changed object's prior binding is rejected.
    final ids = <String>{};
    for (final id in [anchor, unchanged]) {
      ids.addAll((await store.canonicalEditions(id)).editions.map((e) => e.id));
    }
    expect(ids, hasLength(1));
    await jobs.createFromCatalogue(providerId: 'screenscraper');
    for (final review in reviews) {
      expect((await store.canonicalEditions(review.editionId)).editions,
          hasLength(1),
          reason: 'Changed bytes return to their unmatched group.');
    }
  });

  test(
      'unoffered candidate and conflicting official tags roll back review and retry',
      () async {
    await cache('snes', 'Game.zip', artifact: remote('file'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, _ReviewProvider());
    final review = (await jobs.reviewItems(job.id)).single;
    for (final input in [
      ('999', <String>{'official'}),
      ('42', <String>{'official', 'Hack'}),
    ]) {
      await expectLater(
          jobs.acceptCandidate(job.id,
              editionId: review.editionId,
              providerGameId: input.$1,
              contentTags: input.$2),
          throwsStateError);
    }
    expect((await db.query('metadata_refresh_jobs')).length, 1);
    final edition = (await store.edition(review.editionId))!;
    expect((await store.game(edition.gameId))!.providerIds, isEmpty);
  });

  test('removed or changed catalogue objects cannot finish an old lookup',
      () async {
    for (final removed in [false, true]) {
      for (final duringLookup in [false, true]) {
        await db.delete('games');
        final id = await cache('snes', 'Game.zip', artifact: remote('file'));
        final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
        final captured = (await items(job.id)).single;
        final provider = _ReviewProvider();
        Future<void> change() async {
          if (removed) {
            await db.delete('games', where: 'id = ?', whereArgs: [id]);
            return;
          }
          await db.update(
              'games',
              {
                'remote_artifact':
                    jsonEncode(remote('file', checksum: 'b').toJson())
              },
              where: 'id = ?',
              whereArgs: [id]);
        }

        if (duringLookup) {
          provider.beforeResult = change;
        } else {
          await change();
        }
        final result = await jobs.run(job.id, provider);
        expect(result.counts, {'identityChanged': 1});
        expect(provider.calls, duringLookup ? 1 : 0);
        expect(await jobs.reviewItems(job.id), isEmpty);
        final retained = (await items(job.id)).single;
        expect(retained['edition_id'], captured['edition_id']);
        expect(retained['request_json'], captured['request_json']);
      }
    }
  });

  test('cached result stays usable after rename but cannot rate changed bytes',
      () async {
    final id = await cache('snes', 'Game.zip', artifact: remote('file'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    final editionId = (await items(job.id)).single['edition_id'] as String;
    final edition = (await store.edition(editionId))!;
    await store.putMetadata(MetadataRecord(
        gameId: edition.gameId,
        editionId: editionId,
        platformId: 'snes',
        providerId: 'screenscraper',
        providerGameId: '42',
        retrievedAt: DateTime.utc(2026),
        refreshGeneration: job.generation,
        matchMethod: 'verifiedProviderId',
        titles: const [MetadataText(text: 'Example')]));
    await db.update(
        'games',
        {
          'displayName': 'Renamed',
          'remote_artifact': jsonEncode(remote('file', version: '2').toJson())
        },
        where: 'id = ?',
        whereArgs: [id]);
    expect(await store.metadata(editionId, 'screenscraper'), isNotNull);
    await db.update('games',
        {'remote_artifact': jsonEncode(remote('file', checksum: 'b').toJson())},
        where: 'id = ?', whereArgs: [id]);
    expect(await store.metadata(editionId, 'screenscraper'), isNull);
    expect(await db.query('library_metadata'), hasLength(1),
        reason: 'Prior evidence is retained, not erased.');
  });

  test(
      'official review clears translation flags instead of labelling English as T-Eng',
      () async {
    await cache('snes', 'Game.zip', artifact: remote('file'));
    final job = await jobs.createFromCatalogue(providerId: 'screenscraper');
    await jobs.run(job.id, _ReviewProvider());
    final review = (await jobs.reviewItems(job.id)).single;
    await jobs.acceptCandidate(job.id,
        editionId: review.editionId,
        providerGameId: '42',
        contentTags: {'official'});
    final edition = (await store.edition(review.editionId))!;
    expect(edition.tags, {'official'});
    expect(edition.isTranslation, isFalse);
    expect(edition.translatedLanguages, isEmpty);
  });

  test(
      'disputed match survives retry and restart without publishing a candidate',
      () async {
    final rowId = await cache('snes', 'Game.zip', artifact: remote('file'));
    final initial = await jobs.createFromCatalogue(
        providerId: 'screenscraper', cacheRowId: rowId);
    final editionId = (await items(initial.id)).single['edition_id'] as String;
    final edition = (await store.edition(editionId))!;
    final game = (await store.game(edition.gameId))!;
    await store.putGame(GameIdentity.fromJson({
      ...game.toJson(),
      'providerIds': {'screenscraper': '99'},
      'matchStatus': 'manuallyMatched'
    }));
    final at = DateTime.utc(2026, 10, 4);
    final previous = MetadataRecord(
        gameId: game.id,
        editionId: editionId,
        platformId: 'snes',
        providerId: 'screenscraper',
        providerGameId: '99',
        retrievedAt: at,
        refreshGeneration: initial.generation,
        matchMethod: 'verifiedProviderId',
        titles: const [MetadataText(text: 'Old wrong match')]);
    await store.putMetadata(previous);
    final review = await jobs.createMatchReview(
        providerId: 'screenscraper', cacheRowId: rowId, editionId: editionId);
    final provider = _ReviewProvider();
    provider.reply = (_) async => MetadataLookupResult(
        status: MetadataLookupStatus.unmatched, message: 'Not found');
    await jobs.run(review.id, provider);
    final retry = await jobs.retryUnresolved(review.id);
    expect(
        (await db.query('metadata_refresh_jobs',
                where: 'id = ?', whereArgs: [retry.id]))
            .single['is_match_review'],
        1);
    final reopened = MetadataRefreshJobs(Future.value(db));
    provider.reply = (r) async => MetadataLookupResult(
        status: MetadataLookupStatus.matched,
        message: 'Confident result',
        record: MetadataRecord(
            gameId: r.gameId,
            editionId: r.editionId,
            platformId: r.platformId,
            providerId: 'screenscraper',
            providerGameId: r.verifiedProviderGameId ?? '42',
            retrievedAt: at,
            refreshGeneration: r.refreshGeneration,
            matchMethod: 'verifiedProviderId',
            titles: const [
              MetadataText(text: 'Correct candidate')
            ],
            ratings: [
              SourcedRating.parse(
                  sourceId: 'screenscraper',
                  sourceLabel: 'ScreenScraper',
                  providerGameId: '42',
                  rawValue: 20,
                  scaleMinimum: 0,
                  scaleMaximum: 20,
                  kind: RatingKind.overallAggregate,
                  retrievedAt: at)!
            ]));
    final result = await reopened.run(retry.id, provider);
    expect(result.counts, {'needsReview': 1});
    expect(result.rated, 0);
    expect(
        provider.requests.every((r) =>
            r.verifiedProviderGameId == null &&
            r.baseProviderGameId == null &&
            r.romIdentifier == null),
        isTrue);
    expect((await store.game(game.id))!.providerIds['screenscraper'], '99');
    expect((await store.metadata(editionId, 'screenscraper'))!.toJson(),
        previous.toJson());
    final candidates = await reopened.reviewQueue('screenscraper',
        cacheRowId: rowId, editionId: editionId);
    expect(candidates.single.candidates.single.providerGameId, '42');
    final accepted = await reopened.acceptCandidate(retry.id,
        editionId: editionId, providerGameId: '42', contentTags: {'official'});
    expect(
        (await db.query('metadata_refresh_jobs',
                where: 'id = ?', whereArgs: [accepted.id]))
            .single['is_match_review'],
        0);
    expect((await db.query('library_metadata')).single['generation_id'],
        previous.refreshGeneration,
        reason: 'Selection alone cannot publish new facts.');
    await reopened.run(accepted.id, provider);
    expect((await store.metadata(editionId, 'screenscraper'))!.providerGameId,
        '42');
    expect((await reopened.reviewQueue('screenscraper')), isEmpty);
  });

  test('match rediscovery rejects a stale exact-game binding atomically',
      () async {
    final first = await cache('snes', 'First.zip');
    final second = await cache('snes', 'Second.zip');
    final seed = await jobs.createFromCatalogue(
        providerId: 'screenscraper', cacheRowId: first);
    final editionId = (await items(seed.id)).single['edition_id'] as String;
    final before = await db.query('metadata_refresh_jobs');
    await expectLater(
        jobs.createMatchReview(
            providerId: 'screenscraper',
            cacheRowId: second,
            editionId: editionId),
        throwsStateError);
    expect(await db.query('metadata_refresh_jobs'), before);
    await db.delete('games', where: 'id = ?', whereArgs: [first]);
    await expectLater(
        jobs.createMatchReview(
            providerId: 'screenscraper',
            cacheRowId: first,
            editionId: editionId),
        throwsStateError);
    expect(await db.query('metadata_refresh_jobs'), before);
  });
}
