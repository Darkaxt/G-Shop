import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/shared_metadata_lifecycle_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('lifecycle fixture retains durable state and rejects a false reinstall',
      () async {
    final root = await Directory.systemTemp.createTemp('rshop-lifecycle-');
    final external = Directory(p.join(root.path, 'shared'));
    final privateRoot = Directory(p.join(root.path, 'private'));
    addTearDown(() => root.delete(recursive: true));
    Future<Map<String, Object?>> run(String phase) =>
        verifySharedMetadataLifecycle(
            factory: databaseFactoryFfiNoIsolate,
            external: external,
            privateRoot: privateRoot,
            phase: phase);
    await run('seed');
    await run('restart');
    await expectLater(run('reinstalled'), throwsA(isA<TestFailure>()));
    // Host remount simulation is fixture validation, not Android permission proof.
    final away = await external.rename(p.join(root.path, 'unavailable'));
    await run('denied');
    expect(await external.exists(), false);
    await away.rename(external.path);
    await run('regrant');
    final before = jsonDecode(
        await File(p.join(external.path, 'proof.json')).readAsString());
    await privateRoot.delete(recursive: true);
    final result = await run('reinstalled');
    expect(result['restored_records'], 1);
    final after = jsonDecode(
        await File(p.join(external.path, 'proof.json')).readAsString());
    expect(after['hashes'], before['hashes']);
    expect(after['phase'], 'reinstalled');
  }, timeout: Timeout.none);
}
