import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Diffuse stage lighting. A model renderer supplies projected ground points so
/// the pool shares its camera and physical plane without changing camera fitting.
class SceneFloor extends StatelessWidget {
  final List<Offset>? projectedPoints;
  final List<List<Offset>> contactShadows;
  const SceneFloor(
      {super.key, this.projectedPoints, this.contactShadows = const []});

  @override
  Widget build(BuildContext context) => IgnorePointer(
      child: ExcludeSemantics(
          child: RepaintBoundary(
              child: CustomPaint(
                  painter: _FloorPainter(projectedPoints, contactShadows)))));
}

class _FloorPainter extends CustomPainter {
  final List<Offset>? projectedPoints;
  final List<List<Offset>> contactShadows;
  const _FloorPainter(this.projectedPoints, this.contactShadows);
  static const colours = [
    Color(0xA8D93A4D),
    Color(0x8CBF2E44),
    Color(0x3A9C2238),
    Color(0x009C2238)
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (projectedPoints case final points?) {
      const segments = 64;
      final indices = <int>[];
      for (var i = 0; i < segments; i++) {
        indices.addAll([0, 1 + i, 1 + (i + 1) % segments]);
        for (var ring = 0; ring < 2; ring++) {
          final a = 1 + ring * segments + i;
          final b = 1 + ring * segments + (i + 1) % segments;
          indices.addAll([a, a + segments, b, b, a + segments, b + segments]);
        }
      }
      void draw(List<Offset> positions, List<Color> palette) {
        final vertices = ui.Vertices(ui.VertexMode.triangles, positions,
            colors: [
              palette[0],
              for (var ring = 1; ring < 4; ring++)
                ...List.filled(segments, palette[ring])
            ],
            indices: indices);
        canvas.drawVertices(
            vertices, BlendMode.modulate, Paint()..color = Colors.white);
        vertices.dispose();
      }

      draw(points, colours);
      for (final shadow in contactShadows) {
        draw(shadow, const [
          Color(0x70000000),
          Color(0x60000000),
          Color(0x28000000),
          Color(0x00000000)
        ]);
      }
      return;
    }
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
  bool shouldRepaint(_FloorPainter oldDelegate) =>
      projectedPoints != oldDelegate.projectedPoints ||
      contactShadows != oldDelegate.contactShadows;
}
