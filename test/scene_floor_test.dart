import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/core/theme/app_theme.dart';
import 'package:g_shop/features/preview/scene_floor.dart';

void main() {
  testWidgets(
      'floor visibly spans model supports and dissolves before controls',
      (tester) async {
    const size = Size(1240, 1080);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    Future<ByteData> pixels(bool floor) async {
      await tester.pumpWidget(MaterialApp(
          home: RepaintBoundary(
              key: key,
              child: DecoratedBox(
                  decoration: const BoxDecoration(
                      gradient: AppTheme.backgroundGradient),
                  child:
                      floor ? const SceneFloor() : const SizedBox.expand()))));
      return (await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        } finally {
          image.dispose();
        }
      }))!;
    }

    final baseline = await pixels(false);
    final lit = await pixels(true);
    int delta(double x, double y, int channel) {
      final offset = ((size.height * y).round() * size.width.toInt() +
                  (size.width * x).round()) *
              4 +
          channel;
      return lit.getUint8(offset) - baseline.getUint8(offset);
    }

    // One broad pool under the whole composition, rather than a faint dot
    // below it. Pixel contrast is checked against the actual themed background.
    for (final x in [.30, .50, .70]) {
      expect(delta(x, .70, 0), greaterThanOrEqualTo(45));
      expect(delta(x, .70, 0), greaterThan(delta(x, .70, 1)));
    }
    expect(delta(.5, .61, 0), greaterThanOrEqualTo(30));
    // Smoothly fade out; no visible platform edge or illumination in controls.
    expect(delta(.5, .84, 0), inInclusiveRange(1, 30));
    for (final point in [const Offset(.01, .70), const Offset(.5, .92)]) {
      for (var channel = 0; channel < 3; channel++) {
        expect(delta(point.dx, point.dy, channel), 0);
      }
    }
  });
}
