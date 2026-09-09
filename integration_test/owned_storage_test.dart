import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/services/owned_storage.dart';

/// Real native bridge, separate debug UID, synthetic bytes only. No production
/// bootstrap, provider access, user ROMs or recursive cleanup.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const storage = OwnedStorage();
  Matcher fails(String code) => throwsA(
      isA<OwnedStorageException>().having((error) => error.code, 'code', code));
  late _Fixture fixture;
  late OwnedStoragePlan plan;
  final sessions = <OwnedStorageSession>[];
  var sequence = 0;

  Future<String> stage() async {
    final path = plan.stagePath(
        'native-${DateTime.now().microsecondsSinceEpoch}-${sequence++}');
    await fixture.reserveFile(path);
    return path;
  }

  Future<OwnedStorageSession> open(String name, String stagePath,
      {int offset = 0,
      NativeFileIdentity? identity,
      bool published = false}) async {
    final value = await storage.open(
        destinationRoot: plan.destinationRoot,
        relativePath: name,
        stagePath: stagePath,
        durableOffset: offset,
        expectedIdentity: identity,
        published: published);
    sessions.add(value);
    return value;
  }

  setUpAll(() async {
    expect(Platform.isAndroid && kDebugMode, isTrue);
    final info = await PackageInfo.fromPlatform();
    expect(info.packageName, 'com.darkaxt.rshop.debug');
    binding.reportData = {
      'package': info.packageName,
      'scope': 'synthetic owned storage; no accounts or library access'
    };
  });
  setUp(() async {
    sessions.clear();
    final support = await getApplicationSupportDirectory();
    fixture = await _Fixture.create(support.path);
    plan = await storage.prepare(fixture.root.path);
    expect(plan.sameMountHint, isTrue,
        reason:
            'Prefer private staging over a same-device external bind mount');
  });
  tearDown(() async {
    for (final session in sessions.reversed) {
      await session.close();
    }
    await fixture.cleanup();
  });

  testWidgets(
      'native checkpoint, resume, Unicode publication and read-only reopen',
      (_) async {
    const name = '保存-🎮.bin';
    await fixture.reserveFile('${plan.destinationRoot}/$name');
    final partial = await stage();
    final original = await open(name, partial);
    final prefix =
        Uint8List.fromList(List<int>.generate(65536, (i) => i % 251));
    await original.write(0, prefix);
    final checkpoint = await original.checkpoint();
    expect(checkpoint.sizeBytes, prefix.length);
    expect(NativeFileIdentity.fromJson(checkpoint.toJson()).modifiedNanoseconds,
        checkpoint.modifiedNanoseconds);
    await original.write(prefix.length, Uint8List.fromList([90, 91, 92]));
    await original.close();
    final resumed =
        await open(name, partial, offset: prefix.length, identity: checkpoint);
    expect((await resumed.checkpoint()).sizeBytes, prefix.length);
    expect(await resumed.read(prefix.length, 1), isEmpty);
    await resumed.write(prefix.length, Uint8List.fromList([1, 2, 3]));
    final verified = await resumed.checkpoint();
    final bytes = <int>[];
    await for (final chunk in resumed.bytes(verified.sizeBytes)) {
      bytes.addAll(chunk);
    }
    expect(bytes, [...prefix, 1, 2, 3]);
    final published = await resumed.publish(verified);
    expect(published.toJson(), verified.toJson());
    expect(await File(partial).exists(), isFalse);
    expect(await File('${plan.destinationRoot}/$name').readAsBytes(), bytes);
    await resumed.close();
    final reopened = await open(name, partial,
        offset: verified.sizeBytes, identity: published, published: true);
    expect(await reopened.read(prefix.length, 3), [1, 2, 3]);
    await expectLater(
        reopened.write(0, Uint8List(1)), fails('invalid_arguments'));
    binding.reportData!['native_resume_unicode_publish'] = 'passed';
  });

  testWidgets('no-replace collision preserves both byte sequences', (_) async {
    final target = '${plan.destinationRoot}/collision.bin';
    await fixture.reserveFile(target);
    await File(target).writeAsBytes([9, 8, 7], flush: true);
    final partial = await stage();
    final session = await open('collision.bin', partial);
    await session.write(0, Uint8List.fromList([1, 2, 3]));
    final verified = await session.checkpoint();
    await expectLater(session.publish(verified), fails('collision'));
    expect(await File(target).readAsBytes(), [9, 8, 7]);
    expect(await File(partial).readAsBytes(), [1, 2, 3]);
    binding.reportData!['native_no_clobber'] = 'passed';
  });

  testWidgets('resume refuses a substituted stage inode without truncating it',
      (_) async {
    final partial = await stage();
    final session = await open('replaced.bin', partial);
    await session.write(0, Uint8List.fromList([1, 2, 3]));
    final saved = await session.checkpoint();
    await session.close();
    final moved = '$partial.fixture-held';
    await fixture.reserveFile(moved);
    await File(partial)
        .rename(moved); // Keep original inode alive: no reuse ambiguity.
    await File(partial).writeAsBytes([9, 9, 9, 9], flush: true);
    await expectLater(open('replaced.bin', partial, offset: 3, identity: saved),
        fails('changed'));
    expect(await File(partial).readAsBytes(), [9, 9, 9, 9]);
    expect(await File(moved).readAsBytes(), [1, 2, 3]);
  });

  testWidgets('redirected target parent cannot receive publication', (_) async {
    final parent =
        await fixture.createDirectory('${plan.destinationRoot}/parent');
    final moved = '${plan.destinationRoot}/original-parent';
    final partial = await stage();
    final session = await open('parent/redirect.bin', partial);
    await session.write(0, Uint8List.fromList([1]));
    final saved = await session.checkpoint();
    await fixture.reserveDirectory(moved);
    await parent.rename(moved);
    await Directory(parent.path).create();
    await expectLater(session.publish(saved), fails('changed'));
    expect(await File('${parent.path}/redirect.bin').exists(), isFalse);
    expect(await File('$moved/redirect.bin').exists(), isFalse);
    expect(await File(partial).readAsBytes(), [1]);
  });

  testWidgets('stage outside native-selected app directories is refused',
      (_) async {
    await expectLater(
        open('unsafe.bin', '${plan.destinationRoot}/outside.partial'),
        fails('invalid_arguments'));
    expect(await File('${plan.destinationRoot}/outside.partial').exists(),
        isFalse);
  });

  testWidgets(
      'private stage retirement verifies ownership, closes first and replays on SD',
      (_) async {
    const parent = String.fromEnvironment('RSHOP_STORAGE_TEST_ROOT');
    expect(parent, isNotEmpty);
    final sd = await _Fixture.create(parent);
    try {
      final selected = await storage.prepare(sd.root.path);
      final id = 'retire-${DateTime.now().microsecondsSinceEpoch}';
      final partial = selected.stagePath(id);
      const name = 'retirement-test.bin';
      final target = '${selected.destinationRoot}/$name';
      await sd.reserveFile(partial);
      await sd.reserveFile(target);
      final session = await storage.open(
          destinationRoot: selected.destinationRoot,
          relativePath: name,
          stagePath: partial);
      try {
        final bytes = Uint8List.fromList([1, 3, 5, 7, 9]);
        await session.write(0, bytes);
        final source = await session.checkpoint();
        final copy = await session.beginPublicationCopy(source);
        await copy.copyNext(bytes.length);
        final destination = await copy.finish(await copy.checkpoint());
        final record = TransferRecord(
            id: id,
            artifact: RemoteArtifact(
                id: RemoteArtifactId(
                    providerId: 'fixture',
                    sourceId: 'synthetic',
                    accountId: 'none',
                    providerFileId: id),
                displayPath: name,
                displayName: name,
                sizeBytes: bytes.length),
            destinationRoot: selected.destinationRoot,
            relativePath: name,
            stagePath: partial,
            durableOffset: bytes.length,
            lifecycle: TransferLifecycle.completed,
            stageIdentity: source,
            publication: TransferPublication(
                method: PublicationMethod.copy,
                sourceIdentity: source,
                destinationIdentity: destination,
                confirmed: true));
        await expectLater(storage.retireStage(record), fails('collision'));
        await session.close();
        final changed =
            NativeFileIdentity.fromJson({...source.toJson(), 'fileId': '0'});
        await expectLater(
            storage.retireStage(record.copyWith(stageIdentity: changed)),
            fails('changed'));
        expect(await File(partial).readAsBytes(), bytes);
        expect(await File(target).readAsBytes(), bytes);
        await storage.retireStage(record);
        expect(await File(partial).exists(), false);
        expect(await File(target).readAsBytes(), bytes);
        await storage.retireStage(record);
        expect(await File(target).readAsBytes(), bytes);
        binding.reportData!['native_sd_stage_retirement'] =
            'active-session/change preservation, postclose deletion and absent replay passed';
      } finally {
        await session.close();
      }
    } finally {
      await sd.cleanup();
    }
  });

  testWidgets(
      'actual SD verified copy, resume, collision and coarse-mtime edit protection',
      (_) async {
    const selectedParent = String.fromEnvironment('RSHOP_STORAGE_TEST_ROOT');
    expect(selectedParent, isNotEmpty,
        reason: 'Provide a reviewed synthetic SD parent');
    final sd = await _Fixture.create(selectedParent);
    try {
      final sdPlan = await storage.prepare(sd.root.path);
      final partial =
          sdPlan.stagePath('sd-${DateTime.now().microsecondsSinceEpoch}');
      await sd.reserveFile(partial);
      final target = '${sdPlan.destinationRoot}/synthetic-native.bin';
      await sd.reserveFile(target);
      var session = await storage.open(
          destinationRoot: sdPlan.destinationRoot,
          relativePath: 'synthetic-native.bin',
          stagePath: partial);
      try {
        final expected =
            Uint8List.fromList(List<int>.generate(131085, (i) => i % 251));
        for (var offset = 0; offset < expected.length;) {
          final end = (offset + 65536 < expected.length)
              ? offset + 65536
              : expected.length;
          await session.write(
              offset, Uint8List.sublistView(expected, offset, end));
          offset = end;
        }
        final verified = await session.checkpoint();
        // Exercise the explicit alternate backend, not a hidden rename fallback.
        // Actual engine intent/identity transactions remain a separate S3 test.
        var copy = await session.beginPublicationCopy(verified);
        expect(copy.openedIdentity.sizeBytes, 0);
        await expectLater(session.write(verified.sizeBytes, Uint8List(1)),
            fails('invalid_arguments'));
        await copy.copyNext(65536);
        final savedCopy = await copy.checkpoint();
        expect(savedCopy.sizeBytes, 65536);
        await copy.close();
        session = await storage.open(
            destinationRoot: sdPlan.destinationRoot,
            relativePath: 'synthetic-native.bin',
            stagePath: partial,
            durableOffset: verified.sizeBytes,
            expectedIdentity: verified);
        copy = await session.beginPublicationCopy(verified,
            durableOffset: savedCopy.sizeBytes,
            destinationIdentity:
                NativeFileIdentity.fromJson(savedCopy.toJson()));
        await expectLater(copy.copyNext(1), fails('invalid_arguments'));
        await copy.validateResumePrefix();
        while (copy.copiedBytes < expected.length) {
          final remaining = expected.length - copy.copiedBytes;
          await copy.copyNext(remaining < 65536 ? remaining : 65536);
        }
        final copied = await copy.checkpoint();
        expect(await sha256.bind(copy.bytes()).first, sha256.convert(expected));
        final published = await copy.finish(copied);
        expect(published.toJson(), copied.toJson());
        expect(await File(target).readAsBytes(), expected);
        expect(await File(partial).readAsBytes(), expected,
            reason: 'Retain verified source until installed-state commit');
        await copy.close();

        session = await storage.open(
            destinationRoot: sdPlan.destinationRoot,
            relativePath: 'synthetic-native.bin',
            stagePath: partial,
            durableOffset: verified.sizeBytes,
            expectedIdentity: verified);
        await expectLater(
            session.beginPublicationCopy(verified), fails('collision'));
        expect(await File(target).readAsBytes(), expected);

        // Reproduce an SD edit which preserves size and the coarse timestamp.
        final altered = Uint8List.fromList(expected)..[0] = 99;
        await File(target).writeAsBytes(altered, flush: true);
        await File(target).setLastModified(published.modifiedAt);
        final unchangedStat = await storage.inspect(
            destinationRoot: sdPlan.destinationRoot,
            relativePath: 'synthetic-native.bin',
            stagePath: partial,
            published: true);
        expect(unchangedStat!.toJson(), published.toJson(),
            reason: 'This fixture must defeat a stat-only resume check');
        copy = await session.beginPublicationCopy(verified,
            durableOffset: published.sizeBytes, destinationIdentity: published);
        await expectLater(copy.validateResumePrefix(), fails('changed'));
        expect(await File(target).readAsBytes(), altered);
        expect(await File(partial).readAsBytes(), expected);
        binding.reportData!['native_sd_publication'] =
            'verified exclusive copy; resume/collision/edit checks passed';
        binding.reportData!['sd_stage_same_mount_hint'] = sdPlan.sameMountHint;
      } finally {
        await session.close();
      }
    } finally {
      await sd.cleanup();
    }
  });
}

class _Fixture {
  final Directory root;
  final _files = <String>[];
  final _directories = <String>[];
  _Fixture(this.root);
  static Future<_Fixture> create(String parent) async =>
      _Fixture(await Directory(parent).createTemp('rshop-native-fixture-'));
  Future<void> reserveFile(String path) async {
    expect(await FileSystemEntity.type(path, followLinks: false),
        FileSystemEntityType.notFound);
    _files.add(path);
  }

  Future<void> reserveDirectory(String path) async {
    expect(await FileSystemEntity.type(path, followLinks: false),
        FileSystemEntityType.notFound);
    _directories.add(path);
  }

  Future<Directory> createDirectory(String path) async {
    await reserveDirectory(path);
    return Directory(path).create();
  }

  Future<void> cleanup() async {
    // No recursive delete and no parent scanning. These exact entries were
    // proven absent before synthetic creation, under this isolated test UID.
    for (final path in _files.reversed) {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.file) {
        await File(path).delete();
      } else {
        expect(type, FileSystemEntityType.notFound);
      }
    }
    for (final path in _directories.reversed) {
      if (await Directory(path).exists()) await Directory(path).delete();
    }
    await root.delete();
  }
}
