import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/features/preview/scene_preview_layout.dart';

void main() {
  testWidgets(
      '3D viewport uses the full screen while text stays in its edge areas',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(537.67, 468.29), const Size(360, 640)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ScenePreviewLayout(
                  composition: true,
                  header:
                      const Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        'A long game title spanning more than one line of the screen',
                        maxLines: 2,
                        style: TextStyle(fontSize: 26)),
                    Text('Game & Watch'),
                  ]),
                  content: const ColoredBox(
                      key: ValueKey('scene'), color: Colors.black),
                  footer: const Text('Tap a model to inspect',
                      key: ValueKey('caption'))))));
      expect(tester.getRect(find.byKey(const ValueKey('scene'))),
          Offset.zero & size,
          reason:
              'Header/footer must not subtract another model viewport inset');
      final header = tester.getRect(find.byType(FittedBox));
      expect(header.top, greaterThanOrEqualTo(0));
      expect(header.bottom, lessThanOrEqualTo(size.height * .125 + .001));
      expect(tester.getRect(find.byKey(const ValueKey('caption'))).top,
          greaterThan(size.height * .875));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'ordinary resources retain their measured header/content/footer flow',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ScenePreviewLayout(
                composition: false,
                header: SizedBox(height: 50),
                content:
                    ColoredBox(key: ValueKey('content'), color: Colors.black),
                footer: SizedBox(height: 40)))));
    final rect = tester.getRect(find.byKey(const ValueKey('content')));
    expect(rect.top, 50);
    expect(rect.bottom, tester.getSize(find.byType(Scaffold)).height - 40);
  });
}
