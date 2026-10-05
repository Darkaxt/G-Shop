import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/services/metadata/es_de_metadata_projection.dart';
import 'package:retro_eshop/services/metadata/es_de_metadata_publication.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database db;
  late File target;
  late EsDeMetadataPublication publication;
  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('rshop-esde-publication-');
    db = await databaseFactoryFfiNoIsolate
        .openDatabase(p.join(root.path, 'journal.sqlite'));
    await EsDeMetadataPublication.install(db);
    publication = EsDeMetadataPublication(db);
    target = File(p.join(root.path, 'gamelist.xml'));
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  Future<void> queue(String text, {String edition = 'edition-1'}) =>
      publication.queue(
          target: target,
          identityKey: 'binding-$edition',
          generation: 1,
          update: EsDeMetadataUpdate(
              editionId: edition,
              relativeRomPath: './Game.chd',
              fields: {'desc': text}));
  Future<bool> current(String edition, String binding) async =>
      binding == 'binding-$edition';

  test('artwork keeps manual alternatives and recovers rename-before-ack',
      () async {
    final media = await Directory(p.join(root.path, 'media')).create();
    final image = File(p.join(root.path, 'immutable.png'));
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==');
    await image.writeAsBytes(bytes);
    final hash = sha256.convert(bytes).toString();
    final cover = File(p.join(media.path, 'covers', 'Game.png'));
    Future<EsDePublicationResult> publish({String edition = 'edition-1'}) =>
        publication.publishArtwork(
            target: cover,
            mediaRoot: media,
            source: image,
            contentHash: hash,
            editionId: edition,
            identityKey: 'binding-$edition',
            relativeRomPath: './Game.chd',
            esDeClosed: true,
            isCurrent: current);
    await cover.parent.create();
    final jpg = File('${p.withoutExtension(cover.path)}.jpg');
    await jpg.writeAsString('existing launcher cover');
    expect((await publish()).status, 'conflict');
    expect(await cover.exists(), false);
    await jpg.delete();
    // Persist precisely the interruption after the atomic rename but before the
    // shared ownership transaction. The next publisher must acknowledge it.
    final stage = '${cover.path}.rshop-$hash.pending';
    await db.insert('es_de_media_publications', {
      'target_path': cover.path,
      'edition_id': 'edition-1',
      'identity_key': 'binding-edition-1',
      'source_path': image.path,
      'before_hash': null,
      'after_hash': hash,
      'stage_path': stage,
    });
    await File(stage).writeAsBytes(bytes);
    await File(stage).rename(cover.path);
    await db.close();
    db = await databaseFactoryFfiNoIsolate
        .openDatabase(p.join(root.path, 'journal.sqlite'));
    publication = EsDeMetadataPublication(db);
    expect((await publish()).status, 'upToDate');
    expect(await db.query('es_de_media_publications'), isEmpty);
    expect(
        (await db.query('es_de_media_ownership')).single['content_hash'], hash);
    expect((await publish(edition: 'edition-2')).status, 'conflict');
    expect(await cover.readAsBytes(), bytes);
    await cover.writeAsString('manual replacement');
    expect((await publish()).status, 'conflict');
    expect(await cover.readAsString(), 'manual replacement');
  });

  test('artwork interruption repairs only an exact owned stage prefix',
      () async {
    final media = await Directory(p.join(root.path, 'media')).create();
    final image = File(p.join(root.path, 'immutable.png'));
    final bytes = utf8.encode('bounded fixture payload');
    await image.writeAsBytes(bytes);
    final hash = sha256.convert(bytes).toString();
    final cover = File(p.join(media.path, 'covers', 'Game.png'));
    await cover.parent.create();
    final stage = '${cover.path}.rshop-$hash.pending';
    await db.insert('es_de_media_publications', {
      'target_path': cover.path,
      'edition_id': 'edition-1',
      'identity_key': 'binding-edition-1',
      'source_path': image.path,
      'before_hash': null,
      'after_hash': hash,
      'stage_path': stage,
    });
    await File(stage).writeAsBytes(bytes.take(3).toList());
    final written = await publication.publishArtwork(
        target: cover,
        mediaRoot: media,
        source: image,
        contentHash: hash,
        editionId: 'edition-1',
        identityKey: 'binding-edition-1',
        relativeRomPath: './Game.chd',
        esDeClosed: true,
        isCurrent: current);
    expect(written.status, 'upToDate');
    expect(await cover.readAsBytes(), bytes);
    expect(await File(stage).exists(), false);
  });

  test(
      'closed-writer publication preserves manual fields and pending conflicts',
      () async {
    const before =
        '<gameList><game><path>./Game.chd</path><favorite>true</favorite>'
        '<playcount>7</playcount><unknown>keep</unknown></game></gameList>';
    await target.writeAsString(before);
    await queue('Fresh description');
    final refused = await publication.publish(target,
        esDeClosed: false, isCurrent: current);
    expect(refused.status, 'esDeMustBeClosed');
    expect(await target.readAsString(), before);
    expect(await publication.pendingCount(target), 1);
    final written =
        await publication.publish(target, esDeClosed: true, isCurrent: current);
    expect(written.status, 'published');
    expect(await target.readAsString(),
        contains('<desc>Fresh description</desc>'));
    expect(await target.readAsString(), contains('<favorite>true</favorite>'));
    expect(await target.readAsString(), contains('<playcount>7</playcount>'));
    expect(await target.readAsString(), contains('<unknown>keep</unknown>'));
    expect(await File(p.join(root.path, 'Game.chd')).exists(), false);
    expect(await publication.pendingCount(target), 0);
    await target.writeAsString((await target.readAsString())
        .replaceFirst('Fresh description', 'Manual edit'));
    await queue('Next description');
    final conflict =
        await publication.publish(target, esDeClosed: true, isCurrent: current);
    expect(conflict.status, 'conflict');
    expect(conflict.conflicts.single.reason, 'manualField');
    expect(await target.readAsString(), contains('Manual edit'));
    expect(await publication.pendingCount(target), 1);
    final retried = await publication.publish(target,
        esDeClosed: true, rebasePrepared: true, isCurrent: current);
    expect(retried.status, 'conflict');
    expect(await target.readAsString(), contains('Manual edit'));
    expect(await publication.pendingCount(target), 1);
  });

  test('file changes after prepare are preserved with recoverable pending work',
      () async {
    await target.writeAsString('<gameList/>');
    await queue('Fresh');
    // The prepared journal survives the exact process interruption boundary.
    await publication.prepare(target, isCurrent: current);
    const edited = '<gameList><!-- another writer --></gameList>';
    await target.writeAsString(edited);
    final result =
        await publication.publish(target, esDeClosed: true, isCurrent: current);
    expect(result.status, 'fileChanged');
    expect(await target.readAsString(), edited);
    expect(await publication.pendingCount(target), 1);
    final retried = await publication.publish(target,
        esDeClosed: true, rebasePrepared: true, isCurrent: current);
    expect(retried.status, 'published');
    expect(await target.readAsString(), contains('another writer'));
    expect(await target.readAsString(), contains('<desc>Fresh</desc>'));
    expect(await publication.pendingCount(target), 0);
  });

  test(
      'reopen reconciles rename-before-ack without repeating or losing ownership',
      () async {
    await target.writeAsString('<gameList/>');
    await queue('First');
    await publication.prepare(target, isCurrent: current);
    final journal = (await db.query('es_de_publications')).single;
    final stage = File(journal['stage_path'] as String);
    expect(sha256.convert(await stage.readAsBytes()).toString(),
        journal['after_hash']);
    await stage
        .rename(target.path); // Simulate death before SQLite acknowledgement.
    await db.close();
    db = await databaseFactoryFfiNoIsolate
        .openDatabase(p.join(root.path, 'journal.sqlite'));
    publication = EsDeMetadataPublication(db);
    expect(
        (await publication.publish(target,
                esDeClosed: true, isCurrent: current))
            .status,
        'published');
    expect(await publication.pendingCount(target), 0);
    await queue('Second');
    expect(
        (await publication.publish(target,
                esDeClosed: true, isCurrent: current))
            .status,
        'published');
    expect(await target.readAsString(), contains('<desc>Second</desc>'));
  });

  test('changed identity and ambiguous paths cannot publish another edition',
      () async {
    await target.writeAsString('<gameList/>');
    await queue('One');
    final stale = await publication.publish(target,
        esDeClosed: true, isCurrent: (_, __) async => false);
    expect(stale.status, 'identityChanged');
    expect(await target.readAsString(), '<gameList/>');
    await queue('Two', edition: 'edition-2');
    final ambiguous =
        await publication.publish(target, esDeClosed: true, isCurrent: current);
    expect(ambiguous.status, 'conflict');
    expect(ambiguous.conflicts.single.reason, 'ambiguousPath');
    expect(await target.readAsString(), '<gameList/>');
    expect(await publication.pendingCount(target), 2);
    expect(
        jsonDecode(
            (await db.query('es_de_pending')).first['fields_json'] as String),
        {'desc': 'One'});
  });

  test('a partial owned stage is reconstructed from the durable journal',
      () async {
    await target.writeAsString('<gameList/>');
    await queue('Recover a interrupted stage flush');
    await publication.prepare(target, isCurrent: current);
    final journal = (await db.query('es_de_publications')).single;
    final stage = File(journal['stage_path'] as String);
    final bytes = await stage.readAsBytes();
    await stage.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2), flush: true);
    final result =
        await publication.publish(target, esDeClosed: true, isCurrent: current);
    expect(result.status, 'published');
    expect(await target.readAsString(),
        contains('Recover a interrupted stage flush'));
    expect(await publication.pendingCount(target), 0);
  });
}
