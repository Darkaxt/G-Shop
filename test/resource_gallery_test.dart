import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/features/preview/resource_gallery.dart';

void main() {
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
    expect(key.currentState!.images,
        ['file:///not-a-face.png', 'file:///static-box.png']);
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
