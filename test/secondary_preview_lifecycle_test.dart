import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Test the existing native-player boundary, not a replacement preview widget.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:g_shop/features/preview/preview_screen.dart';
import 'package:g_shop/models/preview_settings.dart';
import 'package:g_shop/features/game_detail/widgets/cover_section.dart';
import 'package:g_shop/features/preview/resource_gallery.dart';
import 'package:g_shop/models/game_item.dart';
import 'package:g_shop/models/system_model.dart';
import 'package:g_shop/utils/game_metadata.dart';
import 'package:g_shop/widgets/socket_media_renderer.dart';

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
  testWidgets(
      'details rounds displayed ratings to one decimal without changing scale',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('com.darkaxt.gshop/preview_view');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: PreviewScreen()));
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('snapshot', {
          'revision': 1,
          'identity': 'rating-fixture',
          'actionEpoch': 1,
          'system': 'gba',
          'filename': 'Fixture.gba',
          'title': 'Fixture',
          'details': true,
          'rating': 83.78967206580847,
          'threeD': false,
          'settings': const PreviewSettings().toJson(),
        })),
        (_) {});
    await tester.pump();
    expect(find.text('★ 83.8'), findsOneWidget);
    expect(find.textContaining('83.789'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('single-display Resources also has no title app bar',
      (tester) async {
    final key = GlobalKey<CoverSectionState>();
    const game =
        GameItem(filename: 'Fixture.gba', displayName: 'Fixture', url: '');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CoverSection(
                key: key,
                game: game,
                system: SystemModel.supportedSystems
                    .singleWhere((s) => s.id == 'gba'),
                coverUrls: const [],
                metadata: GameMetadata.parse(game.filename),
                galleryResources: () async => {
                      'manual-page': [
                        'file:///first.png',
                        'file:///second.png'
                      ],
                    }))));
    unawaited(key.currentState!.openGallery());
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    final viewport = tester.getRect(find.byType(Scaffold).last);
    expect(tester.getRect(find.byType(ResourceGallery)), viewport);
    await tester.tap(find.byKey(const ValueKey('resource-mode-manual')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonY);
    await tester.pump();
    expect(
        tester
            .getRect(find.byKey(const ValueKey('resource-inspection-surface'))),
        viewport);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(ResourceGallery), findsNothing);
    expect(find.byType(CoverSection), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Resources fills the display and restores preview chrome on exit',
      (tester) async {
    final page = File.fromUri(File('assets/icon.png').absolute.uri);
    tester.view.physicalSize = const Size(1240, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('com.darkaxt.gshop/preview_view');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: PreviewScreen()));
    await tester.runAsync(() => precacheImage(
        FileImage(page), tester.element(find.byType(PreviewScreen))));
    Future<void> show(bool gallery) async {
      await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall('snapshot', {
            'revision': gallery ? 1 : 2,
            'identity': 'viewer-fixture',
            'actionEpoch': 1,
            'system': 'gba',
            'filename': 'Fixture.gba',
            'title': 'Fixture title',
            'scoreLabel': 'IGDB 8.4',
            'installed': true,
            'gallery': gallery,
            'galleryResources': {
              'manual-page': [page.uri.toString(), page.uri.toString()],
              'ss': ['file:///screen.png'],
            },
            'threeD': false,
            'reducedMotion': true,
            'settings': const PreviewSettings().toJson(),
          })),
          (_) {});
      await tester.pump();
    }

    await show(true);
    expect(find.byKey(const ValueKey('preview-score')), findsNothing);
    expect(find.byKey(const ValueKey('preview-availability')), findsNothing);
    final display = tester.getRect(find.byType(Scaffold));
    expect(tester.getRect(find.byType(ResourceGallery)), display);
    expect(find.text('Fixture title'), findsNothing);
    expect(find.text('Select for details'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('resource-mode-manual')));
    await tester.pump();
    await tester
        .longPress(find.byKey(const ValueKey('resource-inspection-surface')));
    await tester.pump();
    await tester.runAsync(() => precacheImage(
        FileImage(page), tester.element(find.byType(ResourceGallery))));
    await tester.pump();
    // Host tests cannot paint Impeller. Acknowledge that boundary explicitly;
    // real device rendering is verified separately, not bypassed in production.
    tester
        .widget<SocketMediaRenderer>(find.byType(SocketMediaRenderer))
        .onReady!();
    await tester.pump();
    expect(
        tester
            .getRect(find.byKey(const ValueKey('resource-inspection-surface'))),
        display);
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('resource-mode-gallery')));
    await tester.pump();
    expect(
        tester
            .getRect(find.byKey(const ValueKey('resource-inspection-surface'))),
        display);
    await show(false);
    final score = tester.getRect(find.byKey(const ValueKey('preview-score')));
    final available =
        tester.getRect(find.byKey(const ValueKey('preview-availability')));
    expect(score.left, lessThan(display.width / 2));
    expect(available.right, greaterThan(display.width / 2));
    expect(score.bottom, greaterThan(display.height * .85));
    expect(available.bottom, greaterThan(display.height * .85));
    expect(find.byKey(const ValueKey('preview-game-title')), findsOneWidget);
    expect(find.text('Select for details'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('preview media canvas reaches both display edges',
      (tester) async {
    const channel = MethodChannel('com.darkaxt.gshop/preview_view');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: PreviewScreen()));
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('snapshot', {
          'revision': 1,
          'identity': 'edge-fixture',
          'actionEpoch': 1,
          'system': 'gba',
          'filename': 'Fixture.gba',
          'title': 'Fixture',
          'mediaLoading': false,
          'threeD': false,
          'settings': const PreviewSettings().toJson(),
        })),
        (_) {});
    await tester.pump();
    final media = tester.getRect(find.byType(CoverSection));
    final display = tester.getRect(find.byType(Scaffold));
    expect(media.left, display.left);
    expect(media.right, display.right);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('pending cover never exposes an unfinished cartridge',
      (tester) async {
    const channel = MethodChannel('com.darkaxt.gshop/preview_view');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: PreviewScreen()));
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('snapshot', {
          'revision': 1,
          'identity': 'fixture',
          'actionEpoch': 1,
          'system': 'gba',
          'filename': 'Fixture.gba',
          'title': 'Fixture',
          'mediaLoading': true,
          'threeD': false,
          'settings': const PreviewSettings().toJson(),
        })),
        (_) {});
    await tester.pump();
    expect(find.byType(CoverSection), findsNothing);
    expect(find.byKey(const ValueKey('preview-loading-cover')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('hidden warm preview ignores retired video layout safely',
      (tester) async {
    final original = VideoPlayerPlatform.instance;
    final player = _Player();
    VideoPlayerPlatform.instance = player;
    const channel = MethodChannel('com.darkaxt.gshop/preview_view');
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
