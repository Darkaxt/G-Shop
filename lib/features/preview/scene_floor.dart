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
    canvas.translate(size.width * .5, size.height * .74);
    canvas.scale(size.width * .49, size.height * .14);
    canvas.drawCircle(
        Offset.zero,
        1,
        Paint()
          ..shader = ui.Gradient.radial(Offset.zero, 1, const [
            Color(0x66B92742),
            Color(0x338E1B32),
            Color(0x008E1B32),
          ], const [
            0,
            .45,
            1,
          ]));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FloorPainter oldDelegate) => false;
}
