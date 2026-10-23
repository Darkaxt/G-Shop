import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// One diffuse pool beneath an entire lower-screen composition. This is screen
/// lighting, not geometry: it must not change camera fitting or physical scale.
class SceneFloor extends StatelessWidget {
  const SceneFloor({super.key});

  @override
  Widget build(BuildContext context) => const IgnorePointer(
      child: ExcludeSemantics(
          child:
              RepaintBoundary(child: CustomPaint(painter: _FloorPainter()))));
}

class _FloorPainter extends CustomPainter {
  const _FloorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    // Spread the light beneath the composition's lower third. A narrow, low-
    // opacity centre read as a detached spot on Thor rather than a floor.
    canvas.translate(size.width * .5, size.height * .70);
    canvas.scale(size.width * .49, size.height * .18);
    canvas.drawCircle(
        Offset.zero,
        1,
        Paint()
          ..shader = ui.Gradient.radial(Offset.zero, 1, const [
            Color(0xA8D93A4D),
            Color(0x8CBF2E44),
            Color(0x3A9C2238),
            Color(0x009C2238),
          ], const [
            0,
            .35,
            .70,
            1,
          ]));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FloorPainter oldDelegate) => false;
}
