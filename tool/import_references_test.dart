// Windows retail-reference import (COVERAGE-FACTS-01). A digital re-release
// that lacks a carton or cartridge label reuses the original retail edition's
// already-selected media as one 'reference' record; its facts say so. The media
// are copied unchanged, so they share the retail bodies (no downloads). Input:
// {"editions": {"<editionId>": {"referenceEdition": "<editionId>",
//   "roles": ["carton", "label"]}}}. Run through
// `flutter test tool/import_references_test.dart`; see scripts/README.md.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/services/library_store.dart';
import 'package:g_shop/services/metadata/metadata_artwork_cache.dart';
import 'package:g_shop/services/metadata/shared_metadata_store.dart';

const roleTypes = {
  'carton': {'box-2D', 'box-2D-back', 'box-2D-side'},
  'label': {'support-texture'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final storePath = env['GSHOP_STORE'];
  final projectionPath = env['GSHOP_PROJECTION'];
  final referencesPath = env['GSHOP_REFERENCES'];
  test('import retail references', () async {
    sqfliteFfiInit();
    final input = (jsonDecode(await File(referencesPath!).readAsString())
        as Map)['editions'] as Map;
    final database = databaseFactoryFfiNoIsolate.openDatabase(projectionPath!);
    final store = await SharedMetadataStore.open(Directory(storePath!),
        factory: databaseFactoryFfiNoIsolate,
        existingOnly: true,
        verifyAccess: () async {});
    var written = 0, unchanged = 0;
    final failed = <String>[];
    try {
      print('restored ${await store.restore(await database)} record(s)');
      final db = await database;
      final library = LibraryStore(database);
      var generation = await store.maximumGeneration();
      final private = await db
          .rawQuery('SELECT MAX(generation_id) AS n FROM library_metadata');
      if ((private.single['n'] as int? ?? 0) > generation) {
        generation = private.single['n'] as int;
      }
      generation++;
      final now = DateTime.now().toUtc();
      for (final entry in input.entries) {
        final editionId = entry.key as String;
        final spec = entry.value as Map;
        final referenceId = spec['referenceEdition'] as String;
        final types = {
          for (final role in spec['roles'] as List) ...?roleTypes[role]
        };
        final reference = await library.edition(referenceId);
        // One provider supplies every face so the set stays one printing.
        List<MetadataMedia> media = const [];
        String? source;
        for (final provider in ['packaging', 'launchbox', 'screenscraper']) {
          final record = await library.metadata(referenceId, provider);
          if (record == null || reference == null) continue;
          final selected = MetadataArtworkCache.displayMedia(record,
                  regions: reference.regions,
                  includePhysicalLabel: true,
                  includePackaging: true)
              .where((m) => types.contains(m.type))
              .toList();
          if (selected.map((m) => m.type).toSet().length >
              media.map((m) => m.type).toSet().length) {
            media = selected;
            source = provider;
          }
        }
        if (media.isEmpty) {
          failed.add('$editionId: reference $referenceId has no such media');
          continue;
        }
        final rows = await db.rawQuery('''SELECT g.record_json AS game_json,
          e.record_json AS edition_json FROM library_editions e JOIN
          library_game_identities g ON g.game_id=e.game_id WHERE e.edition_id=?''',
            [editionId]);
        if (rows.length != 1) {
          failed.add('$editionId: no current edition');
          continue;
        }
        final identity = rows.single;
        final game = jsonDecode(identity['game_json'] as String) as Map;
        final keys = [for (final m in media) MetadataArtworkCache.key(m)];
        final previous = await library.metadata(editionId, 'reference');
        if (previous != null &&
            jsonEncode(previous.media.map(MetadataArtworkCache.key).toList()) ==
                jsonEncode(keys)) {
          unchanged++;
          continue;
        }
        final record = MetadataRecord(
            gameId: game['id'] as String,
            editionId: editionId,
            platformId: game['platformId'] as String,
            providerId: 'reference',
            providerGameId: sha256.convert(utf8.encode(editionId)).toString(),
            retrievedAt: now,
            refreshGeneration: generation,
            matchMethod: 'retailReference',
            titles: [],
            media: media,
            matchEvidence: {
              'identityKey': LibraryStore.metadataIdentity(identity,
                  providerId: 'reference'),
              'referenceEditionId': referenceId,
              'referenceProviderId': source,
            });
        try {
          await store.preserve(record, identity, db);
          await library.putMetadata(record);
          written++;
        } on Object catch (e) {
          failed.add('$editionId: $e');
        }
      }
    } finally {
      await store.close();
      await (await database).close();
    }
    for (final f in failed.take(20)) {
      print('FAILED $f');
    }
    print('SUMMARY editions=${input.length} written=$written '
        'unchanged=$unchanged failed=${failed.length}');
    expect(failed, isEmpty);
  },
      skip: storePath == null ||
              projectionPath == null ||
              referencesPath == null
          ? 'Set GSHOP_STORE, GSHOP_PROJECTION and GSHOP_REFERENCES'
          : false,
      timeout: Timeout.none);
}
