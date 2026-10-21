import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/features/game_detail/widgets/game_scene_information.dart';

void main() {
  testWidgets('information blurs only its backdrop and retains usable controls',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(537.67, 468.29), const Size(360, 640)]) {
      tester.view.physicalSize = size;
      var closed = false;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MediaQuery(
                  data: MediaQueryData(
                      size: size, textScaler: const TextScaler.linear(1.3)),
                  child: Stack(children: [
                    const Positioned.fill(
                        child: ColoredBox(
                            key: ValueKey('scene'), color: Colors.red)),
                    GameSceneInformation(
                        title: '10-Yard Fight',
                        summary: List.filled(15, 'Game information.').join(' '),
                        referenceNote: 'Physical editions can differ.',
                        onClose: () => closed = true),
                  ])))));
      final backdrop = find.byType(BackdropFilter);
      expect(backdrop, findsOneWidget);
      final clip =
          find.ancestor(of: backdrop, matching: find.byType(ClipRRect));
      expect(clip, findsOneWidget);
      final panelBounds = tester.getRect(clip);
      expect(panelBounds.width, lessThan(size.width));
      expect(panelBounds.height, lessThan(size.height));
      expect(find.descendant(of: backdrop, matching: find.byType(Text)),
          findsWidgets,
          reason: 'Text is painted after the filtered backdrop');
      expect(find.byType(ImageFiltered), findsNothing);
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Physical editions can differ.').hitTestable(),
          findsOneWidget);
      await tester.tap(find.byTooltip('Close game information'));
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
    }
  });
}
