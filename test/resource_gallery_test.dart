import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/features/preview/resource_gallery.dart';
import 'package:retro_eshop/widgets/socket_media_renderer.dart';
// Exercise the real controller's native boundary without decoding media on host.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _GalleryPlayer extends VideoPlayerPlatform {
  final events = StreamController<VideoEvent>.broadcast();
  final volumes = <double>[];
  final disposed = <int>[];
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events.stream;
  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
  }

  @override
  Future<void> setMixWithOthers(bool value) async {}
  @override
  Future<void> setLooping(int playerId, bool value) async {}
  @override
  Future<void> setVolume(int playerId, double value) async =>
      volumes.add(value);
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
  testWidgets('box inspector stays closed while manual remains openable',
      (tester) async {
    final key = GlobalKey<ResourceGalleryState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ResourceGallery(
      key: key,
      identity: 'closed-box',
      title: 'Review',
      systemId: 'gba',
      resources: const {
        'box-2D': ['file:///front.png'],
        'manual-page': ['file:///page.png', 'file:///last.png']
      },
    ))));
    expect(key.currentState!.canOpen, false);
    expect(find.byTooltip('Open'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pump();
    expect(key.currentState!.opening, 0);
    await tester.tap(find.byKey(const ValueKey('resource-mode-manual')));
    await tester.pump();
    expect(key.currentState!.canOpen, true);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'unified media navigation releases playback and music suppression',
      (tester) async {
    final previous = VideoPlayerPlatform.instance;
    final player = _GalleryPlayer();
    VideoPlayerPlatform.instance = player;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    addTearDown(player.events.close);
    final key = GlobalKey<ResourceGalleryState>();
    final playing = <bool>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ResourceGallery(
      key: key,
      identity: 'audio',
      title: 'Review',
      systemId: 'arcade',
      volume: .17,
      onPlayingChanged: playing.add,
      resources: const {
        'video': ['file:///trailer.mp4'],
        'ss': ['file:///screen.png']
      },
    ))));
    await tester.tap(find.byKey(const ValueKey('resource-mode-gallery')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pump();
    player.events.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 30),
        size: const Size(320, 240)));
    await tester.pumpAndSettle();
    expect(key.currentState!.snapshot['videoReady'], true);
    expect(player.volumes.last, .17);
    expect(playing.last, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(key.currentState!.snapshot['videoReady'], false);
    expect(playing.last, false);
    expect(key.currentState!.snapshot['galleryIndex'], 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('gallery lists trailers without packaging or labels',
      (tester) async {
    final key = GlobalKey<ResourceGalleryState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ResourceGallery(
                key: key,
                identity: 'gallery-review',
                title: 'Review',
                systemId: 'arcade',
                resources: const {
          'box-2D': ['file:///front.png'],
          'support-texture': ['file:///label.png'],
          'video': ['file:///trailer.mp4'],
        }))));
    await tester.tap(find.byKey(const ValueKey('resource-mode-gallery')));
    await tester.pump();
    expect(key.currentState!.images, isEmpty);
    expect(find.byKey(const ValueKey('gallery-item-0')), findsOneWidget);
    expect(find.text('Images (0)'), findsNothing);
    expect(key.currentState!.snapshot['galleryItems'], [
      {'kind': 'trailer'},
    ]);
    await tester.pumpWidget(const SizedBox());
  });
  for (final system in ['gba', 'psx']) {
    testWidgets('$system gallery is one trailer-first sequence',
        (tester) async {
      final key = GlobalKey<ResourceGalleryState>();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ResourceGallery(
        key: key,
        identity: 'mixed-$system',
        title: 'Review',
        systemId: system,
        resources: const {
          'video': ['file:///first.mp4', 'file:///second.mp4'],
          'video-normalized': ['file:///first.mp4'],
          'ss': ['file:///screen.png'],
          'fanart': ['file:///art.png'],
          'box-2D': ['file:///not-gallery.png'],
        },
      ))));
      await tester.tap(find.byKey(const ValueKey('resource-mode-gallery')));
      await tester.pump();
      expect(key.currentState!.snapshot['galleryItems'], [
        {'kind': 'trailer'},
        {'kind': 'trailer'},
        {'kind': 'image'},
        {'kind': 'image'},
      ]);
      expect(key.currentState!.snapshot['galleryIndex'], 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(key.currentState!.snapshot['galleryIndex'], 2);
      expect(find.byTooltip('Play trailer'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('gallery-item-3')));
      await tester.pump();
      expect(key.currentState!.snapshot['galleryIndex'], 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(key.currentState!.snapshot['galleryIndex'], 0);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('GBA box fills six atlas cells and has no invented Case',
      (tester) async {
    final key = GlobalKey<ResourceGalleryState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ResourceGallery(
                key: key,
                identity: 'gba-review',
                title: 'Review',
                systemId: 'gba',
                resources: const {
          'box-2D': ['file:///front.png'],
          'box-2D-back': ['file:///back.png'],
          'box-2D-side': ['file:///spine.png'],
        }))));
    await tester.pump();
    expect(
        key.currentState!.availableViews, isNot(contains(ResourceView.cover)));
    final atlas = tester
        .widget<SocketMediaRenderer>(find.byType(SocketMediaRenderer))
        .label;
    final column = atlas as Column;
    final cells = column.children
        .cast<Expanded>()
        .expand((row) => ((row.child as Row).children).cast<Expanded>())
        .toList();
    expect(cells, hasLength(6));
    for (final cell in cells) {
      expect(cell.child, isA<SizedBox>(),
          reason: 'Face must fill the whole atlas cell');
      final bounds = cell.child as SizedBox;
      expect(bounds.width, double.infinity);
      expect(bounds.height, double.infinity);
    }
    final paths = cells
        .map((cell) => (((((cell.child as SizedBox).child as ColoredBox).child
                        as RotatedBox)
                    .child as Image)
                .image as FileImage)
            .file
            .path)
        .toList();
    expect(paths.where((path) => path.endsWith('spine.png')), hasLength(4));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('all six classified panels override repeated-spine fallback',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ResourceGallery(
      identity: 'six-faces',
      title: 'Review',
      systemId: 'gb',
      resources: {
        'box-2D-side': ['file:///fallback.png'],
        'outer-box-front': ['file:///front.png'],
        'outer-box-back': ['file:///back.png'],
        'outer-box-left': ['file:///left.png'],
        'outer-box-right': ['file:///right.png'],
        'outer-box-top': ['file:///top.png'],
        'outer-box-bottom': ['file:///bottom.png'],
      },
    ))));
    await tester.pump();
    final atlas = tester
        .widget<SocketMediaRenderer>(find.byType(SocketMediaRenderer))
        .label as Column;
    final cells = atlas.children
        .cast<Expanded>()
        .expand((row) => (row.child as Row).children.cast<Expanded>());
    final rotations = cells
        .map((cell) => (((cell.child as SizedBox).child as ColoredBox).child
            as RotatedBox))
        .toList();
    expect(rotations.map((r) => r.quarterTurns), everyElement(0));
    expect(
        rotations.map((r) =>
            ((r.child as Image).image as FileImage).file.uri.pathSegments.last),
        [
          'front.png',
          'back.png',
          'left.png',
          'right.png',
          'top.png',
          'bottom.png'
        ]);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('sections and controller preserve honest missing-media states',
      (tester) async {
    final key = GlobalKey<ResourceGalleryState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ResourceGallery(
      key: key,
      identity: 'inspection',
      title: 'Inspection',
      systemId: 'arcade',
      resources: const {
        'cover-preview': ['file:///not-a-face.png'],
        'box-3D': ['file:///static-box.png']
      },
    ))));
    await tester.pump();
    expect(key.currentState!.availableViews,
        [ResourceView.cartridge, ResourceView.manual, ResourceView.gallery]);
    expect(key.currentState!.images, isEmpty,
        reason: 'Packaging belongs in Box, not the art gallery');
    expect(key.currentState!.first('box-2D'), isNull);
    final flat = find.byKey(const ValueKey('flat-medium-pose'));
    final original = tester.widget<Transform>(flat).transform.clone();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(tester.widget<Transform>(flat).transform.storage,
        isNot(orderedEquals(original.storage)),
        reason: 'Flat previews must apply the controls too');
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await tester.pump();
    expect(find.text('No manual collected yet'), findsOneWidget);
    expect(key.currentState!.snapshot['canOpen'], false);
    expect(find.byTooltip('Open'), findsNothing);
    expect(find.byTooltip('Read manual'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pump();
    expect(key.currentState!.snapshot['opening'], 0);
    await tester.tap(find.byKey(const ValueKey('resource-mode-gallery')));
    await tester.pump();
    expect(key.currentState!.snapshot['view'], 'gallery');
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonLeft1);
    await tester.pump();
    expect(key.currentState!.snapshot['view'], 'manual');
    await tester.pumpWidget(const SizedBox());
  });
}
