import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/scene_launch_presentation.dart';

void main() {
  test('the save-check boundary waits for resources and the actual final frame',
      () async {
    final scene = SceneLaunchPresentation();
    final token =
        scene.begin(identity: 'nes:owned-a', consoleId: 'front-loader');
    var committed = false;
    final handoff =
        scene.commitWhenPresented(token).then((value) => committed = value);
    expect(scene.phase, SceneLaunchPhase.preparing);
    scene.ready(token);
    await Future<void>.value();
    expect(scene.phase, SceneLaunchPhase.animating);
    expect(committed, isFalse);
    scene.skip();
    expect(committed, isFalse);
    scene.rendered(token);
    await handoff;
    expect(committed, isTrue);
    expect(scene.phase, SceneLaunchPhase.committing);
    scene.dispose();
  });

  test(
      'missing visual resources permit direct handoff only at the owned boundary',
      () async {
    final scene = SceneLaunchPresentation();
    final token =
        scene.begin(identity: 'nes:owned-a', consoleId: 'front-loader');
    expect(scene.commitWithoutAnimation(token), isFalse);
    scene.unavailable(token);
    expect(scene.phase, SceneLaunchPhase.preparing);
    expect(await scene.commitWhenPresented(token), isTrue);
    expect(scene.phase, SceneLaunchPhase.committing);
    scene.dispose();
  });

  test(
      'B interrupts an integrated pending handoff and ignores a late final frame',
      () async {
    final scene = SceneLaunchPresentation();
    final token =
        scene.begin(identity: 'nes:owned-a', consoleId: 'front-loader');
    final handoff = scene.commitWhenPresented(token);
    scene.ready(token);
    await Future<void>.value();
    scene.cancel();
    expect(await handoff, isFalse);
    expect(scene.rendered(token), isFalse);
    scene.dispose();
  });
  test('two additional A presses skip visuals without admitting handoff', () {
    final scene = SceneLaunchPresentation();
    final token =
        scene.begin(identity: 'nes:owned-a', consoleId: 'front-loader');
    scene.ready(token);
    expect(scene.animate(token), isTrue);
    expect(scene.confirm(const Duration(seconds: 1)), isFalse);
    expect(scene.skipRequested, isFalse);
    expect(scene.confirm(const Duration(seconds: 1) + kDoubleTapTimeout ~/ 2),
        isTrue);
    expect(scene.skipRequested, isTrue);
    expect(scene.commit(token), isFalse);
    scene.rendered(token);
    expect(scene.commit(token), isTrue);
    expect(scene.consoleId, 'front-loader');
    scene.dispose();
  });

  test('separate A presses never become an old pending double press', () {
    final scene = SceneLaunchPresentation();
    scene.begin(identity: 'gba:owned-a', consoleId: 'agb');
    expect(scene.confirm(Duration.zero), isFalse);
    expect(scene.confirm(kDoubleTapTimeout + const Duration(milliseconds: 1)),
        isFalse);
    expect(scene.skipRequested, isFalse);
    scene.dispose();
  });

  test('B during preparation resolves waits and rejects late renderer replies',
      () async {
    final scene = SceneLaunchPresentation();
    final old = scene.begin(identity: 'nes:owned-a', consoleId: 'top-loader');
    final waiting = scene.waitForResources(old);
    expect(scene.cancel(), isTrue);
    expect(await waiting, isFalse);
    final current =
        scene.begin(identity: 'nes:owned-b', consoleId: 'front-loader');
    expect(scene.ready(old), isFalse);
    expect(scene.rendered(old), isFalse);
    expect(scene.animate(current), isFalse);
    expect(scene.identity, 'nes:owned-b');
    expect(scene.consoleId, 'front-loader');
    scene.dispose();
  });

  test('B after the final frame still cancels before commit', () async {
    final scene = SceneLaunchPresentation();
    final token =
        scene.begin(identity: 'nes:owned-a', consoleId: 'front-loader');
    scene.ready(token);
    scene.animate(token);
    final frame = scene.waitForFrame(token);
    scene.rendered(token);
    expect(await frame, isTrue);
    expect(scene.cancel(), isTrue);
    expect(scene.commit(token), isFalse);
    scene.dispose();
  });

  test('committed handoff is distinct from a cancellable animation', () {
    final scene = SceneLaunchPresentation();
    final token = scene.begin(identity: 'gba:owned-a', consoleId: 'ags');
    scene.ready(token);
    scene.animate(token);
    scene.rendered(token);
    expect(scene.commit(token), isTrue);
    expect(scene.cancel(), isFalse);
    scene.handedOff(token);
    expect(scene.phase, SceneLaunchPhase.handedOff);
    scene.reset();
    expect(scene.phase, SceneLaunchPhase.idle);
    scene.dispose();
  });

  test('disposal completes renderer waits without a watchdog', () async {
    final scene = SceneLaunchPresentation();
    final token =
        scene.begin(identity: 'gameandwatch:owned-a', consoleId: 'gnw_ball');
    final resources = scene.waitForResources(token);
    final frame = scene.waitForFrame(token);
    scene.dispose();
    expect(await resources, isFalse);
    expect(await frame, isFalse);
    expect(scene.ready(token), isFalse);
    expect(scene.rendered(token), isFalse);
  });
}
