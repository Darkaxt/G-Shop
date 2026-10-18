import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/features/preview/resource_gallery.dart';
import 'package:retro_eshop/widgets/socket_media_renderer.dart';

void main() {
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
    expect(find.byKey(const ValueKey('gallery-trailer')), findsOneWidget);
    expect(find.text('Images (0)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
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
