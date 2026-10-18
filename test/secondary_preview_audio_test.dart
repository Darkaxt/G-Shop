import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/services/secondary_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('explicit route handoff retains window and rejects outgoing hide',
      () async {
    final bridge = SecondaryPreview()..available = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(SecondaryPreview.channel, (call) async {
      calls.add(call.method);
      return null;
    });
    final home = Object(), loadingRoute = Object(), game = Object();
    try {
      await bridge.present(
          home, {'actionIdentity': 'console:gba'}, (_, __) async {});
      bridge.retainFor(loadingRoute);
      await bridge.hide(home);
      expect(calls, ['present']);
      await bridge.present(
          game, {'actionIdentity': 'gba:game'}, (_, __) async {});
      await bridge.hide(loadingRoute);
      expect(calls, ['present', 'present']);
      await bridge.hide(game);
      expect(calls.last, 'hide');
    } finally {
      bridge.dispose();
      messenger.setMockMethodCallHandler(SecondaryPreview.channel, null);
    }
  });
  test('startup preparation does not present a window or select a game',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(SecondaryPreview.channel, (call) async {
      calls.add(call);
      return null;
    });
    final bridge = SecondaryPreview();
    addTearDown(() {
      bridge.dispose();
      messenger.setMockMethodCallHandler(SecondaryPreview.channel, null);
    });
    await bridge.prepare(
        enabled: true,
        resourceRoot: '/private/socket-media',
        resourceGeneration: 'generation');
    expect(calls.map((call) => call.method), ['prepare']);
    expect(calls.single.arguments, {
      'enabled': true,
      'resourceRoot': '/private/socket-media',
      'resourceGeneration': 'generation'
    });
    await bridge.prepare(enabled: false);
    expect(calls.last.method, 'prepare');
    expect(calls.last.arguments, {'enabled': false});
  });

  test('only current player controls music, and hide releases suppression',
      () async {
    final changes = <bool>[];
    final bridge = SecondaryPreview(onPlaybackChanged: changes.add)
      ..available = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final snapshots = <Map>[];
    messenger.setMockMethodCallHandler(SecondaryPreview.channel, (call) async {
      if (call.method == 'present') snapshots.add(call.arguments as Map);
      return null;
    });
    addTearDown(() {
      bridge.dispose();
      messenger.setMockMethodCallHandler(SecondaryPreview.channel, null);
    });
    Future<void> report(Map snapshot, bool playing) async {
      await messenger.handlePlatformMessage(
          SecondaryPreview.channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall('playing', {
            'actionEpoch': snapshot['actionEpoch'],
            'video': snapshot['video'],
            'playing': playing,
          })),
          (_) {});
    }

    final owner = Object();
    await bridge.present(owner,
        {'actionIdentity': 'first', 'video': '/first.mp4'}, (_, __) async {});
    await report(snapshots.first, true);
    expect(changes.last, isTrue);
    await bridge.present(owner,
        {'actionIdentity': 'second', 'video': '/second.mp4'}, (_, __) async {});
    expect(changes.last, isFalse);
    await report(snapshots.first, true);
    expect(changes.last, isFalse,
        reason: 'Retired player cannot mute new selection');
    await report(snapshots.last, true);
    expect(changes.last, isTrue);
    await messenger.handlePlatformMessage(
        SecondaryPreview.channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('availability', false)),
        (_) {});
    expect(changes.last, isFalse);
    await report(snapshots.last, true);
    expect(changes.last, isFalse,
        reason: 'Disconnected display cannot regain music ownership');
    await bridge.hide(owner);
    expect(changes.last, isFalse);
    await report(snapshots.last, true);
    expect(changes.last, isFalse);
  });
}
