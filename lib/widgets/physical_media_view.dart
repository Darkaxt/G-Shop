import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Independently constructed exterior, not recovered Socket topology/textures.
/// Model-space proportions follow the hash-bound physical reference study.
class MediaPoint3 {
  final double x, y, z;
  const MediaPoint3(this.x, this.y, this.z);
  MediaPoint3 operator -(MediaPoint3 other) =>
      MediaPoint3(x - other.x, y - other.y, z - other.z);
  MediaPoint3 cross(MediaPoint3 b) =>
      MediaPoint3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x);
}

class MediaFace {
  final List<MediaPoint3> points;
  final Color color;
  const MediaFace(this.points, this.color);
}

class PhysicalMediaGeometry {
  final double width, height, depth;
  final Rect label, header;
  final List<MediaFace> faces;
  const PhysicalMediaGeometry._(
      this.width, this.height, this.depth, this.label, this.header, this.faces);
  static final gameBoy = _gameBoy();
  static PhysicalMediaGeometry _gameBoy() {
    const width = 1.0,
        height = 0.0648228 / 0.0564107,
        depth = 0.0074225 / 0.0564107;
    final outline = <Offset>[
      Offset(-0.5, -height / 2 + 0.012),
      Offset(-0.488, -height / 2),
      Offset(0.43, -height / 2),
      Offset(0.43, -height / 2 + 0.055),
      Offset(0.5, -height / 2 + 0.055),
      Offset(0.5, height / 2 - 0.025),
      Offset(0.475, height / 2),
      Offset(-0.475, height / 2),
      Offset(-0.5, height / 2 - 0.025),
    ];
    final faces = <MediaFace>[];
    void extrude(List<Offset> polygon, double front, double back, Color color) {
      final near = polygon.map((p) => MediaPoint3(p.dx, p.dy, front)).toList();
      final far = polygon.map((p) => MediaPoint3(p.dx, p.dy, back)).toList();
      // Each convex front/back plane is one face. Sorting separate coplanar
      // triangles by their centres can paint the shell over its moulded ribs.
      faces.add(MediaFace(near, color));
      faces.add(MediaFace(far.reversed.toList(), color));
      for (var i = 0; i < polygon.length; i++) {
        final next = (i + 1) % polygon.length;
        faces.add(MediaFace([near[i], far[i], far[next], near[next]], color));
      }
    }

    extrude(
        outline, depth / 2 - 0.01, -depth / 2 + 0.01, const Color(0xff74767e));
    final bevel = outline.map((p) => p * 0.985).toList();
    extrude(bevel, depth / 2, -depth / 2, const Color(0xff8a8c94));
    // Moulded grip and shell seam are geometry, not a tilted cartridge image.
    for (var row = 0; row < 8; row++) {
      final y = -height / 2 + 0.035 + row * 0.029;
      for (final x in [-0.485, 0.395]) {
        extrude([
          Offset(x, y),
          Offset(x + 0.09, y),
          Offset(x + 0.09, y + 0.008),
          Offset(x, y + 0.008)
        ], depth / 2 + 0.004, depth / 2, const Color(0xff6b6d75));
      }
    }
    final header = Rect.fromCenter(
        center: Offset(0, -height / 2 + 0.15), width: 0.78, height: 0.15);
    List<Offset> capsule(Rect rect) => [
          for (final side in [0, 1])
            for (var step = 0; step <= 8; step++)
              Offset(
                  (side == 0
                          ? rect.right - rect.height / 2
                          : rect.left + rect.height / 2) +
                      math.cos(-math.pi / 2 +
                              side * math.pi +
                              step * math.pi / 8) *
                          rect.height /
                          2,
                  rect.center.dy +
                      math.sin(-math.pi / 2 +
                              side * math.pi +
                              step * math.pi / 8) *
                          rect.height /
                          2),
        ];
    extrude(capsule(header.inflate(0.008)), depth / 2 + 0.005, depth / 2,
        const Color(0xff565860));
    extrude(capsule(header), depth / 2 + 0.006, depth / 2 + 0.005,
        const Color(0xff74767e));
    final label = Rect.fromCenter(
        center: const Offset(0, 0.055),
        width: 0.0439713 / 0.0564107,
        height: 0.0390049 / 0.0564107);
    final rim = label.inflate(0.014);
    extrude([rim.topLeft, rim.topRight, rim.bottomRight, rim.bottomLeft],
        depth / 2 + 0.002, depth / 2 - 0.002, const Color(0xff565860));
    return PhysicalMediaGeometry._(
        width, height, depth, label, header, List.unmodifiable(faces));
  }
}

class HandwrittenMediaSticker extends StatelessWidget {
  final String identity, title;
  const HandwrittenMediaSticker(
      {super.key, required this.identity, required this.title});
  static const palette = <Color>[
    Color(0xfff0dd99),
    Color(0xffbdd9b5),
    Color(0xffd9c4e1),
    Color(0xffb8d5e7),
    Color(0xffedc0a4)
  ];
  static Color colorFor(String identity) {
    var hash = 0;
    for (final unit in identity.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
      color: colorFor(identity),
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Expanded(
                child: Center(
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                            width: 270,
                            child: Text(title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontFamily: 'Kalam',
                                    fontSize: 35,
                                    height: 1.15,
                                    color: Color(0xff25202a))))))),
            const Divider(color: Color(0x5525202a)),
            const Text('MY COLLECTION',
                style: TextStyle(
                    fontSize: 11, letterSpacing: 2, color: Color(0xff49404b))),
          ])));
}

/// One small exterior mesh in Flutter's existing renderer. The label remains an
/// ordinary projected widget, sharing the existing artwork/cache pipeline.
class PhysicalMediaView extends StatefulWidget {
  final String identity, title;
  final Widget label;
  final bool reducedMotion;
  const PhysicalMediaView(
      {super.key,
      required this.identity,
      required this.title,
      required this.label,
      this.reducedMotion = false});
  @override
  State<PhysicalMediaView> createState() => PhysicalMediaViewState();
}

class PhysicalMediaViewState extends State<PhysicalMediaView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _selection = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));
  late final AnimationController _idle = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 62832));
  late final AnimationController _insertion = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 850));
  Completer<bool>? _completion;
  double _manualRotation = 0;
  bool get _reduce =>
      widget.reducedMotion || MediaQuery.disableAnimationsOf(context);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _insertion.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish(true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configureMotion();
  }

  @override
  void didUpdateWidget(PhysicalMediaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _finish(false);
      _insertion.reset();
      _manualRotation = 0;
      _selection.reset();
    }
    _configureMotion();
  }

  void _configureMotion() {
    if (_reduce) {
      _idle.stop();
      _selection.value = 1;
      if (_completion != null) skipInsertion();
    } else {
      if (!_idle.isAnimating) _idle.repeat();
      if (!_selection.isCompleted) _selection.forward();
    }
  }

  Future<bool> playInsertion() {
    if (_completion case final pending?) return pending.future;
    if (_reduce) return Future.value(true);
    final pending = Completer<bool>();
    _completion = pending;
    _insertion.forward(from: 0);
    setState(() {});
    return pending.future;
  }

  void skipInsertion() {
    if (_completion != null) _insertion.value = 1;
  }

  void resetInsertion() {
    _finish(false);
    _insertion.reset();
  }

  void _finish(bool result) {
    final pending = _completion;
    _completion = null;
    if (pending != null && !pending.isCompleted) pending.complete(result);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _finish(false);
      _insertion.stop();
      _idle.stop();
    } else {
      _configureMotion();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finish(false);
    _selection.dispose();
    _idle.dispose();
    _insertion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
      label: '3D Game Boy cartridge: ${widget.title}',
      child: LayoutBuilder(
          builder: (context, box) => AnimatedBuilder(
              animation: Listenable.merge([_selection, _idle, _insertion]),
              builder: (context, _) {
                final model = PhysicalMediaGeometry.gameBoy;
                final phase = _idle.value * math.pi * 2;
                final selected = _reduce
                    ? 1.0
                    : Curves.easeOutBack.transform(_selection.value);
                var rx = -0.18 + (1 - selected) * -0.75,
                    ry = -0.25 + _manualRotation,
                    rz = -0.10;
                var y = 0.0, z = 0.0, scale = 0.85 + 0.15 * selected;
                if (!_reduce && _completion == null) {
                  y = math.sin(phase * 25) * 0.015;
                  rx += math.sin(phase * 15) * 0.05236;
                  ry += math.cos(phase * 12) * 0.02618;
                  rz += math.sin(phase * 18) * 0.04189;
                }
                final seconds = _insertion.value * 0.85;
                if (_insertion.value > 0) {
                  final lift = Curves.easeOutBack
                      .transform((seconds / 0.15).clamp(0.0, 1.0));
                  y = -0.13 * lift;
                  z = -0.05 * lift;
                  ry += math.pi * 2 * (seconds / 0.2).clamp(0.0, 1.0);
                  if (seconds > 0.2) {
                    y += 1.25 *
                        Curves.easeInExpo
                            .transform(((seconds - 0.2) / 0.2).clamp(0.0, 1.0));
                  }
                  if (seconds > 0.4) {
                    y -= 0.12 *
                        Curves.easeOutBack.transform(
                            ((seconds - 0.4) / 0.12).clamp(0.0, 1.0));
                  }
                  if (seconds > 0.4) {
                    scale *= 1 +
                        0.05 *
                            Curves.elasticOut.transform(
                                ((seconds - 0.4) / 0.25).clamp(0.0, 1.0));
                  }
                  if (seconds > 0.65) {
                    y += 0.12 *
                        Curves.easeInOutBack.transform(
                            ((seconds - 0.65) / 0.2).clamp(0.0, 1.0));
                  }
                }
                final units = math.min(
                    box.maxWidth * 0.72, box.maxHeight * 0.68 / model.height);
                final matrix = Matrix4.identity()
                  ..translateByDouble(box.maxWidth / 2, box.maxHeight / 2, 0, 1)
                  ..scaleByDouble(units, units, units, 1);
                final camera = Matrix4.identity()..setEntry(3, 2, -0.25);
                matrix.multiply(camera);
                matrix.translateByDouble(0, y, z, 1);
                matrix.rotateZ(rz);
                matrix.rotateY(ry);
                matrix.rotateX(rx);
                matrix.scaleByDouble(scale, scale, scale, 1);
                final labelMatrix = matrix.clone()
                  ..translateByDouble(model.label.left, model.label.top,
                      model.depth / 2 + 0.003, 1)
                  ..scaleByDouble(
                      model.label.width / 320, model.label.height / 284, 1, 1);
                final headerMatrix = matrix.clone()
                  ..translateByDouble(model.header.left, model.header.top,
                      model.depth / 2 + 0.007, 1)
                  ..scaleByDouble(
                      model.header.width / 320, model.header.height / 62, 1, 1);
                final front = math.cos(ry) * math.cos(rx) > 0;
                return Stack(clipBehavior: Clip.hardEdge, children: [
                  Positioned.fill(
                      child: GestureDetector(
                          onHorizontalDragUpdate: (event) {
                            if (_completion == null) {
                              setState(() =>
                                  _manualRotation += event.delta.dx * 0.012);
                            }
                          },
                          child: CustomPaint(
                              key: const ValueKey('physical-media-shell'),
                              painter: _MediaShellPainter(model, matrix)))),
                  if (front)
                    Positioned(
                        left: 0,
                        top: 0,
                        child: IgnorePointer(
                            child: Transform(
                                alignment: Alignment.topLeft,
                                transform: headerMatrix,
                                child: const SizedBox(
                                    width: 320,
                                    height: 62,
                                    child: Center(
                                        child: Text('Nintendo GAME BOY',
                                            style: TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xff45474f),
                                                shadows: [
                                                  Shadow(
                                                      color: Color(0xffa2a4ac),
                                                      offset: Offset(0.8, 1.2),
                                                      blurRadius: 0.5)
                                                ]))))))),
                  if (front)
                    Positioned(
                        left: 0,
                        top: 0,
                        child: IgnorePointer(
                            child: Transform(
                                alignment: Alignment.topLeft,
                                transform: labelMatrix,
                                child: SizedBox(
                                    width: 320,
                                    height: 284,
                                    child: widget.label)))),
                  if (_completion != null)
                    Positioned(
                        right: 8,
                        bottom: 8,
                        child: IconButton.filled(
                            key: const ValueKey('physical-media-skip'),
                            tooltip: 'Skip animation',
                            onPressed: skipInsertion,
                            icon: const Icon(Icons.skip_next_rounded))),
                ]);
              })));
}

class _MediaShellPainter extends CustomPainter {
  final PhysicalMediaGeometry model;
  final Matrix4 matrix;
  _MediaShellPainter(this.model, this.matrix);
  MediaPoint3 _transform(MediaPoint3 v) {
    final m = matrix.storage;
    final w = m[3] * v.x + m[7] * v.y + m[11] * v.z + m[15];
    return MediaPoint3(
        (m[0] * v.x + m[4] * v.y + m[8] * v.z + m[12]) / w,
        (m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13]) / w,
        (m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14]) / w);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final faces = [
      for (final face in model.faces)
        (face: face, points: face.points.map(_transform).toList())
    ]..sort((a, b) =>
        (a.points.map((p) => p.z).reduce((a, b) => a + b) / a.points.length)
            .compareTo(b.points.map((p) => p.z).reduce((a, b) => a + b) /
                b.points.length));
    for (final projected in faces) {
      final points = projected.points;
      final normal = (points[1] - points[0]).cross(points[2] - points[0]);
      if (normal.z <= 0) continue;
      final length = math.sqrt(
          normal.x * normal.x + normal.y * normal.y + normal.z * normal.z);
      final light = (0.45 +
              0.55 *
                  ((-normal.x * 0.4 - normal.y * 0.6 + normal.z * 0.7) / length)
                      .clamp(0.0, 1.0))
          .clamp(0.0, 1.0);
      final color = projected.face.color;
      final paint = Paint()
        ..color = Color.fromARGB(255, (color.r * 255 * light).round(),
            (color.g * 255 * light).round(), (color.b * 255 * light).round());
      final path = Path()..moveTo(points.first.x, points.first.y);
      for (final p in points.skip(1)) {
        path.lineTo(p.x, p.y);
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_MediaShellPainter old) =>
      old.matrix != matrix || old.model != model;
}
