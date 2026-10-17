import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Test the existing native-player boundary, not a replacement preview widget.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:retro_eshop/features/preview/preview_screen.dart';
import 'package:retro_eshop/models/preview_settings.dart';

class _Player extends VideoPlayerPlatform {
  final events = StreamController<VideoEvent>();
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events.stream;
  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<void> setMixWithOthers(bool value) async {}
  @override
  Future<void> setLooping(int playerId, bool value) async {}
  @override
  Future<void> setVolume(int playerId, double value) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double value) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}

void main() {
  testWidgets('hidden warm preview ignores retired video layout safely',
      (tester) async {
    final original = VideoPlayerPlatform.instance;
    final player = _Player();
    VideoPlayerPlatform.instance = player;
    const channel = MethodChannel('com.retro.rshop/preview_view');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() async {
      VideoPlayerPlatform.instance = original;
      messenger.setMockMethodCallHandler(channel, null);
      await player.events.close();
    });
    Future<void> send(String method, [Map<String, dynamic>? args]) async {
      await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall(method, args)),
          (_) {});
    }

    await tester.pumpWidget(const MaterialApp(home: PreviewScreen()));
    await send('snapshot', {
      'revision': 1,
      'identity': 'fixture',
      'actionEpoch': 1,
      'system': 'gba',
      'filename': 'Fixture.gba',
      'title': 'Fixture',
      'video': '/fixture.mp4',
      'threeD': false,
      'settings': const PreviewSettings().toJson(),
    });
    await tester.idle();
    player.events.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 10),
        size: const Size(320, 240)));
    await tester.idle(); // Player completes; its layout callback has not run.
    await send('hide');
    await tester.idle(); // Join the serialized player-disposal microtasks.
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Fixture'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
