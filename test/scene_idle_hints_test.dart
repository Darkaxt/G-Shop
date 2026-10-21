import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/features/preview/scene_idle_hints.dart';

void main() {
  Widget view(
          {String identity = 'scene', bool enabled = true, int activity = 0}) =>
      MaterialApp(
          home: Scaffold(
              body: SceneIdleHints(
                  identity: identity,
                  enabled: enabled,
                  activityRevision: activity,
                  hints: const [
                    'Tap a model to inspect it.',
                    'A hardware fact.'
                  ],
                  child: const ColoredBox(
                      key: ValueKey('full-scene'), color: Colors.black))));
  final hint = find.byKey(const ValueKey('scene-idle-hint'));

  testWidgets('hints begin at 25 seconds and rotate without resizing the scene',
      (tester) async {
    tester.view.physicalSize = const Size(537.67, 468.29);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(view());
    final scene = tester.getRect(find.byKey(const ValueKey('full-scene')));
    await tester.pump(const Duration(seconds: 24));
    expect(hint, findsNothing);
    await tester.pumpWidget(view());
    await tester.pump(const Duration(seconds: 1));
    expect(
        find.text('Did you know? Tap a model to inspect it.'), findsOneWidget);
    expect(tester.getRect(hint).top, greaterThan(468.29 * .875));
    expect(tester.getRect(find.byKey(const ValueKey('full-scene'))), scene);
    await tester.pump(const Duration(seconds: 25));
    expect(find.text('Did you know? A hardware fact.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'touch, held gestures and controller activity reset idle presentation',
      (tester) async {
    await tester.pumpWidget(view());
    await tester.pump(const Duration(seconds: 25));
    final touch = await tester.startGesture(const Offset(100, 100));
    await tester.pump();
    expect(hint, findsNothing);
    await tester.pump(const Duration(seconds: 30));
    expect(hint, findsNothing);
    await touch.up();
    await tester.pump(const Duration(seconds: 24));
    expect(hint, findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(hint, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pump();
    expect(hint, findsNothing);
    await tester.pump(const Duration(seconds: 24));
    await tester.pumpWidget(view(activity: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(hint, findsNothing,
        reason: 'Input from the primary display also resets the wait');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'information, launch, backgrounding and selection hide stale hints',
      (tester) async {
    await tester.pumpWidget(view());
    await tester.pump(const Duration(seconds: 25));
    await tester.pumpWidget(view(enabled: false));
    expect(hint, findsNothing);
    await tester.pump(const Duration(seconds: 30));
    expect(hint, findsNothing);
    await tester.pumpWidget(view());
    await tester.pump(const Duration(seconds: 25));
    final observer =
        tester.state(find.byType(SceneIdleHints)) as WidgetsBindingObserver;
    observer.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(hint, findsNothing);
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 25));
    expect(hint, findsOneWidget);
    await tester.pumpWidget(view(identity: 'another-game'));
    expect(hint, findsNothing);
    await tester.pump(const Duration(seconds: 25));
    expect(
        find.text('Did you know? Tap a model to inspect it.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
