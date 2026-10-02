import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/services/owned_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('owned-storage-fixture');
  const storage = OwnedStorage(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final identity = <String, Object>{
    'device': '17',
    'inode': '23',
    'size': 4,
    'modifiedSeconds': 1700000000,
    'modifiedNanos': 123456789
  };
  Future<OwnedStorageSession> open() => storage.open(
      destinationRoot: '/roms',
      relativePath: 'game.chd',
      stagePath: '/private/fixture.partial');
  Matcher fails(String code) => throwsA(
      isA<OwnedStorageException>().having((error) => error.code, 'code', code));
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'ownedOpen') {
        return {'session': 'fixture', 'identity': identity};
      }
      if (call.method == 'ownedCheckpoint' || call.method == 'ownedPublish') {
        return identity;
      }
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('native nanoseconds survive journal and channel round trips', () {
    final decoded = OwnedStorage.decodeIdentity(identity);
    expect(decoded.modifiedNanoseconds, 123456789);
    expect(
        OwnedStorage.nativeIdentity(
            NativeFileIdentity.fromJson(decoded.toJson())),
        identity);
    final legacy = Map<String, dynamic>.from(decoded.toJson())
      ..remove('modifiedNanoseconds');
    expect(NativeFileIdentity.fromJson(legacy).modifiedNanoseconds, 123456000);
  });
  test('quarantine operations retain exact paths and read-only evidence', () async {
    final expected = OwnedStorage.decodeIdentity(identity);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'ownedOpen') {
        return {'session': 'fixture', 'identity': identity};
      }
      return call.method == 'ownedQuarantine' ? identity : null;
    });
    expect((await storage.quarantine(destinationRoot: '/roms', relativePath: 'game.chd',
        stagePath: '/private/removal.partial', expectedIdentity: expected)).matches(expected), isTrue);
    expect(calls.single.arguments['expectedIdentity'], identity);
    final session = await storage.openQuarantine(destinationRoot: '/roms', relativePath: 'game.chd',
        stagePath: '/private/removal.partial', expectedIdentity: expected);
    expect(calls.last.arguments['mode'], 'quarantine');
    await expectLater(session.write(0, Uint8List(1)), fails('invalid_arguments'));
    await expectLater(session.publish(expected), fails('invalid_arguments'));
    await session.close();
    await storage.retireQuarantine(destinationRoot: '/roms', relativePath: 'game.chd',
        stagePath: '/private/removal.partial', expectedIdentity: expected);
    expect(calls.last.method, 'ownedRetireQuarantine');
    expect(calls.where((c) => c.method == 'ownedWrite'), isEmpty);
  });
  test('timestamps before epoch also retain normalized native nanoseconds', () {
    final beforeEpoch = {
      ...identity,
      'modifiedSeconds': -1,
      'modifiedNanos': 123456789
    };
    expect(
        OwnedStorage.nativeIdentity(OwnedStorage.decodeIdentity(beforeEpoch)),
        beforeEpoch);
  });
  test('create and resume carry exact immutable path and identity', () async {
    final session = await open();
    expect(calls.single.arguments['mode'], 'create');
    await session.close();
    final expected = OwnedStorage.decodeIdentity(identity);
    await storage.open(
        destinationRoot: '/roms',
        relativePath: 'game.chd',
        stagePath: '/private/fixture.partial',
        durableOffset: 4,
        expectedIdentity: expected);
    final args = calls.last.arguments;
    expect(args['mode'], 'resume');
    expect(args['expectedIdentity'], identity);
    expect(args['durableOffset'], 4);
  });
  test('resume and published recovery cannot infer ownership from a name',
      () async {
    await expectLater(
        storage.open(
            destinationRoot: '/roms',
            relativePath: 'game',
            stagePath: '/private/fixture.partial',
            durableOffset: 1),
        fails('invalid_arguments'));
    await expectLater(
        storage.open(
            destinationRoot: '/roms',
            relativePath: 'game',
            stagePath: '/private/fixture.partial',
            published: true),
        fails('invalid_arguments'));
    expect(calls, isEmpty);
  });
  test('storage errors never expose raw platform details', () async {
    for (final code in ['collision', 'unexpected-secret']) {
      messenger.setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(
              code: code,
              message: 'private-path-and-token',
              details: 'private-account'));
      try {
        await open();
        fail('must throw');
      } on OwnedStorageException catch (error) {
        expect(error.code, code == 'collision' ? code : 'io_error');
        expect(error.toString(), isNot(contains('private')));
      }
    }
  });
  test('unavailable native bridge fails closed', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(open(), fails('unsupported'));
  });
  test('one write is bounded and reports completion only after native IO',
      () async {
    final gate = Completer<void>();
    final session = await open();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      await gate.future;
      return null;
    });
    var completed = false;
    final write =
        session.write(0, Uint8List(65536)).then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    gate.complete();
    await write;
    expect(completed, isTrue);
    await expectLater(
        session.write(0, Uint8List(65537)), fails('invalid_arguments'));
    await expectLater(
        session.write(-1, Uint8List(1)), fails('invalid_arguments'));
    expect(calls.where((call) => call.method == 'ownedWrite'), hasLength(1));
  });
  test('read stream is demand driven with a 64 KiB chunk bound', () async {
    final session = await open();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return Uint8List(call.arguments['length'] as int);
    });
    final iterator = StreamIterator(session.bytes(65537));
    expect(calls.where((call) => call.method == 'ownedRead'), isEmpty);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, hasLength(65536));
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((call) => call.method == 'ownedRead'), hasLength(1));
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, hasLength(1));
    expect(calls.last.arguments['offset'], 65536);
    expect(await iterator.moveNext(), isFalse);
    await iterator.cancel();
  });
  test('unexpected EOF is not successful verification', () async {
    final session = await open();
    messenger.setMockMethodCallHandler(channel, (_) async => Uint8List(0));
    await expectLater(session.bytes(1).drain<void>(), fails('changed'));
  });
  test('published session is read-only and publish carries verified identity',
      () async {
    final session = await open();
    final verified = await session.checkpoint();
    await session.publish(verified);
    expect(calls.last.arguments['expectedIdentity'], identity);
    await expectLater(
        session.write(0, Uint8List(1)), fails('invalid_arguments'));
    await expectLater(session.publish(verified), fails('invalid_arguments'));
  });
  test('close joins one native close and rejects subsequent work', () async {
    final session = await open();
    final gate = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      await gate.future;
      return null;
    });
    final a = session.close();
    final b = session.close();
    expect(identical(a, b), isTrue);
    await expectLater(session.checkpoint(), fails('closed'));
    gate.complete();
    await a;
    expect(calls.where((call) => call.method == 'ownedClose'), hasLength(1));
  });
  test('staging IDs cannot address another file or directory', () {
    const plan = OwnedStoragePlan(
        destinationRoot: '/roms',
        stageRoot: '/owned',
        destinationVolume: '1',
        stageVolume: '2',
        destinationMount: '10',
        stageMount: '20',
        destinationFreeBytes: 100,
        stageFreeBytes: 100);
    expect(plan.sameVolumeHint, isFalse);
    expect(plan.sameMountHint, isFalse);
    expect(plan.stagePath('transfer-1'), '/owned/transfer-1.partial');
    for (final bad in ['', '..', '../rom', '/rom', 'a/b', 'x.partial']) {
      expect(() => plan.stagePath(bad), fails('invalid_arguments'));
    }
  });
  test('copy creation carries source proof and exposes no network writer',
      () async {
    final source = await open();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'ownedCopyOpen') return {...identity, 'size': 0};
      if (call.method == 'ownedCopyChunk') {
        return (call.arguments['offset'] as int) +
            (call.arguments['length'] as int);
      }
      return identity;
    });
    final copy = await source
        .beginPublicationCopy(OwnedStorage.decodeIdentity(identity));
    expect(calls.last.arguments['expectedIdentity'], identity);
    expect(calls.last.arguments['durableOffset'], 0);
    expect(copy.openedIdentity.sizeBytes, 0);
    await copy.copyNext(4);
    expect(copy.copiedBytes, 4);
    expect(
        calls.last.arguments, {'session': 'fixture', 'offset': 0, 'length': 4});
    await expectLater(copy.copyNext(65537), fails('invalid_arguments'));
    final verified = await copy.checkpoint();
    await copy.finish(verified);
    expect(calls.last.arguments['expectedIdentity'], identity);
    await expectLater(copy.copyNext(1), fails('invalid_arguments'));
    expect(calls.any((call) => call.method.contains('install')), isFalse);
  });
  test('copy resume validates the recorded prefix in bounded native steps',
      () async {
    final source = await open();
    final resumed = {...identity, 'size': 65537};
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'ownedCopyOpen') return resumed;
      if (call.method == 'ownedClose') return null;
      return (call.arguments['offset'] as int) +
          (call.arguments['length'] as int);
    });
    final saved = OwnedStorage.decodeIdentity(resumed);
    final copy = await source.beginPublicationCopy(saved,
        durableOffset: 65537, destinationIdentity: saved);
    expect(calls.last.arguments['destinationIdentity'], resumed);
    await copy.validateResumePrefix();
    final checks = calls
        .where((call) => call.method == 'ownedCopyValidatePrefix')
        .toList();
    expect(checks.map((call) => call.arguments['length']), [65536, 1]);
    expect(copy.copiedBytes, 65537);
    await source.close();
    await expectLater(copy.copyNext(1), fails('closed'));
  });
  test('copy prefix mismatch never schedules a destination write', () async {
    final source = await open();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'ownedCopyOpen') return identity;
      throw PlatformException(code: 'changed');
    });
    final saved = OwnedStorage.decodeIdentity(identity);
    final copy = await source.beginPublicationCopy(saved,
        durableOffset: 4, destinationIdentity: saved);
    await expectLater(copy.validateResumePrefix(), fails('changed'));
    expect(calls.where((call) => call.method == 'ownedCopyChunk'), isEmpty);
    expect(copy.copiedBytes, 4);
  });
}
