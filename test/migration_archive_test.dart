import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/services/migration/migration_archive.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('rshop-migration-');
  });
  tearDown(() async => root.delete(recursive: true));

  test('encrypted portable archive restores actual streamed bytes and secrets',
      () async {
    final rom = File(p.join(root.path, 'game.gba'));
    final bytes = List<int>.generate(2 * 1024 * 1024 + 17, (i) => i % 251);
    await rom.writeAsBytes(bytes);
    final save = await File(p.join(root.path, 'game.sav'))
        .writeAsString('associated-save-data');
    final archive = File(p.join(root.path, 'backup.rshop'));
    final codec = MigrationArchive();
    final state = <String, Object?>{
      'credentials': {'screenscraper': 'private-test-api-password'},
      'sourceDevice': 'source-fixture',
    };
    await codec.write(archive,
        password: 'portable backup password',
        state: state,
        files: [
          MigrationFile('roms/game.gba', rom),
          MigrationFile('associated/game.sav', save)
        ]);
    final encrypted = await archive.readAsBytes();
    expect(
        latin1.decode(encrypted).contains('private-test-api-password'), false);
    expect(latin1.decode(encrypted).contains('associated-save-data'), false);
    final restored = await codec.read(archive,
        password: 'portable backup password',
        privateRoot: Directory(p.join(root.path, 'independent-private-data')));
    expect(restored.state, state);
    expect(await restored.file('roms/game.gba').readAsBytes(), bytes);
    expect(await restored.file('associated/game.sav').readAsString(),
        'associated-save-data');
    final second = File(p.join(root.path, 'second.rshop'));
    await codec.write(second,
        password: 'portable backup password',
        state: state,
        files: [MigrationFile('roms/game.gba', rom)]);
    expect((await second.readAsBytes()).take(40).toList(),
        isNot(encrypted.take(40).toList()));
  });

  test('password, tampering and truncation never return an activation snapshot',
      () async {
    final codec = MigrationArchive();
    final archive = File(p.join(root.path, 'backup.rshop'));
    final file =
        await File(p.join(root.path, 'rom')).writeAsString('rom bytes');
    await codec.write(archive,
        password: 'a long backup password',
        state: {'secret': 'test-key'},
        files: [MigrationFile('roms/a', file)]);
    final private = Directory(p.join(root.path, 'restore'));
    await expectLater(
        codec.read(archive, password: 'wrong password', privateRoot: private),
        throwsA(isA<MigrationArchiveException>()));
    final original = await archive.readAsBytes();
    for (final index in [40, original.length ~/ 2, original.length - 1]) {
      final damaged = List<int>.from(original)..[index] ^= 1;
      await archive.writeAsBytes(damaged);
      await expectLater(
          codec.read(archive,
              password: 'a long backup password', privateRoot: private),
          throwsA(isA<MigrationArchiveException>()));
    }
    await archive.writeAsBytes(original.sublist(0, original.length - 10));
    await expectLater(
        codec.read(archive,
            password: 'a long backup password', privateRoot: private),
        throwsA(isA<MigrationArchiveException>()));
    expect(await private.list().toList(), isEmpty);
  });

  test('rejects unsafe names, duplicates and source links before output',
      () async {
    final codec = MigrationArchive();
    final archive = File(p.join(root.path, 'invalid.rshop'));
    final source =
        await File(p.join(root.path, 'source')).writeAsString('data');
    for (final name in [
      '../outside',
      '/absolute',
      'a/../b',
      r'a\b',
      'C:/outside',
      'a//b',
      'a/./b',
      'a\u0000b'
    ]) {
      await expectLater(
          codec.write(archive,
              password: 'a long backup password',
              state: {},
              files: [MigrationFile(name, source)]),
          throwsA(isA<MigrationArchiveException>()));
      expect(await archive.exists(), false);
    }
    await expectLater(
        codec.write(archive,
            password: 'a long backup password',
            state: {},
            files: [MigrationFile('a', source), MigrationFile('a', source)]),
        throwsA(isA<MigrationArchiveException>()));
  });

  test('unsupported version and trailing payload are not accepted', () async {
    final codec = MigrationArchive();
    final archive = File(p.join(root.path, 'backup.rshop'));
    await codec.write(archive,
        password: 'a long backup password', state: {}, files: []);
    final original = await archive.readAsBytes();
    await archive.writeAsBytes([...original, 1]);
    await expectLater(
        codec.read(archive,
            password: 'a long backup password',
            privateRoot: Directory(p.join(root.path, 'restore'))),
        throwsA(isA<MigrationArchiveException>()));
    final unknown = List<int>.from(original)..[11] = 2;
    await archive.writeAsBytes(unknown);
    await expectLater(
        codec.read(archive,
            password: 'a long backup password',
            privateRoot: Directory(p.join(root.path, 'restore'))),
        throwsA(isA<MigrationArchiveException>()));
  });
}
