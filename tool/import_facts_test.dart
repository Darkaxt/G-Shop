// Windows facts import (COVERAGE-FACTS-01). Writes sourced "Did you know?"
// facts as one 'facts' metadata record per edition into the master store; the
// catalogue publisher then ships them like any other record. Input JSON:
// {"editions": {"<editionId>": [{"text": "...", "source": "https://..."}]}}.
// Run through `flutter test tool/import_facts_test.dart`; see scripts/README.md.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/services/library_store.dart';
import 'package:g_shop/services/metadata/shared_metadata_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final storePath = env['GSHOP_STORE'];
  final projectionPath = env['GSHOP_PROJECTION'];
  final factsPath = env['GSHOP_FACTS'];
  test('import facts', () async {
    sqfliteFfiInit();
    final input = (jsonDecode(await File(factsPath!).readAsString())
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
        final facts = [
          for (final f in entry.value as List)
            (
              text: ((f as Map)['text'] as String).trim(),
              source: (f['source'] as String).trim()
            )
        ];
        if (facts.isEmpty ||
            facts.any((f) =>
                f.text.isEmpty ||
                f.text.length > 300 ||
                !f.source.startsWith('https://'))) {
          failed.add('$editionId: each fact needs text (<=300) and an https source');
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
        final previous = await library.metadata(editionId, 'facts');
        final texts = [for (final f in facts) f.text];
        if (previous != null &&
            jsonEncode(previous.descriptions.map((d) => d.text).toList()) ==
                jsonEncode(texts) &&
            jsonEncode(previous.matchEvidence['sources']) ==
                jsonEncode([for (final f in facts) f.source])) {
          unchanged++;
          continue;
        }
        final record = MetadataRecord(
            gameId: game['id'] as String,
            editionId: editionId,
            platformId: game['platformId'] as String,
            providerId: 'facts',
            providerGameId:
                sha256.convert(utf8.encode(editionId)).toString(),
            retrievedAt: now,
            refreshGeneration: generation,
            matchMethod: 'catalogueFacts',
            titles: [],
            descriptions: [
              for (final f in facts) MetadataText(text: f.text, language: 'en')
            ],
            matchEvidence: {
              'identityKey':
                  LibraryStore.metadataIdentity(identity, providerId: 'facts'),
              'sources': [for (final f in facts) f.source],
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
      skip: storePath == null || projectionPath == null || factsPath == null
          ? 'Set GSHOP_STORE, GSHOP_PROJECTION and GSHOP_FACTS'
          : false,
      timeout: Timeout.none);
}
