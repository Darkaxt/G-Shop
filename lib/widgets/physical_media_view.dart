import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
export 'handwritten_media_sticker.dart';

enum PhysicalMediaFormat {
  gameBoy('Game Boy cartridge', 850),
  n64('Nintendo 64 cartridge', 700),
  disc('optical disc', 1600);

  final String description;
  final int insertionMilliseconds;
  const PhysicalMediaFormat(this.description, this.insertionMilliseconds);

  static PhysicalMediaFormat? forSystem(String systemId) => switch (systemId) {
        'gb' => gameBoy,
        'n64' => n64,
        'psx' || 'ps2' => disc,
        // UMD, mini-disc and other cartridge shells are not these formats.
        _ => null,
      };
}

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
  static final n64 = _n64();
  static final disc = _disc();
  static PhysicalMediaGeometry forFormat(PhysicalMediaFormat format) =>
      switch (format) {
        PhysicalMediaFormat.gameBoy => gameBoy,
        PhysicalMediaFormat.n64 => n64,
        PhysicalMediaFormat.disc => disc,
      };

  static void _extrude(List<MediaFace> faces, List<Offset> polygon,
      double front, double back, Color color) {
    final near = polygon.map((p) => MediaPoint3(p.dx, p.dy, front)).toList();
    final far = polygon.map((p) => MediaPoint3(p.dx, p.dy, back)).toList();
    faces.add(MediaFace(near, color));
    faces.add(MediaFace(far.reversed.toList(), color));
    for (var i = 0; i < polygon.length; i++) {
      final next = (i + 1) % polygon.length;
      faces.add(MediaFace([near[i], far[i], far[next], near[next]], color));
    }
  }

  static PhysicalMediaGeometry _n64() {
    const height = 0.03 / 0.045, depth = 0.0075 / 0.045;
    // Independently drawn curved crown, shoulders, bottom connector notches.
    final outline = <Offset>[
      for (var step = 0; step <= 24; step++)
        Offset(-0.5 + step / 24,
            -height / 2 + 0.14 * math.pow((step - 12) / 12, 2)),
      const Offset(0.5, height / 2 - 0.045),
      const Offset(0.46, height / 2),
      const Offset(0.33, height / 2),
      const Offset(0.33, height / 2 - 0.025),
      const Offset(-0.33, height / 2 - 0.025),
      const Offset(-0.33, height / 2),
      const Offset(-0.46, height / 2),
      const Offset(-0.5, height / 2 - 0.045),
    ];
    final faces = <MediaFace>[];
    _extrude(faces, outline, depth / 2 - 0.008, -depth / 2 + 0.008,
        const Color(0xff777775));
    _extrude(faces, outline.map((p) => p * 0.982).toList(), depth / 2,
        -depth / 2, const Color(0xff929290));
    final label = Rect.fromCenter(
        center: const Offset(0, -0.018),
        width: 0.0210141 / 0.045,
        height: 0.50);
    final rim = label.inflate(0.012);
    _extrude(faces, _n64LabelOutline(rim), depth / 2 + 0.002, depth / 2 - 0.002,
        const Color(0xff55575e));
    for (final x in [-0.29, 0.285]) {
      _extrude(
          faces,
          [
            Offset(x, -0.28),
            Offset(x + 0.005, -0.28),
            Offset(x + 0.005, height / 2 - 0.025),
            Offset(x, height / 2 - 0.025)
          ],
          depth / 2 + 0.001,
          depth / 2,
          const Color(0xff6d6d6b));
    }
    _extrude(
        faces,
        [
          const Offset(-0.33, height / 2 - 0.04),
          const Offset(0.33, height / 2 - 0.04),
          const Offset(0.33, height / 2 - 0.025),
          const Offset(-0.33, height / 2 - 0.025)
        ],
        depth / 2 + 0.001,
        depth / 2,
        const Color(0xff353534));
    return PhysicalMediaGeometry._(
        1, height, depth, label, Rect.zero, List.unmodifiable(faces));
  }

  static List<Offset> _n64LabelOutline(Rect rect) => [
        for (var step = 0; step <= 12; step++)
          Offset(rect.left + rect.width * step / 12,
              rect.top + rect.height * 0.12 * math.pow((step - 6) / 6, 2)),
        Offset(rect.right, rect.bottom - rect.height * 0.02),
        Offset(rect.right - rect.width * 0.02, rect.bottom),
        Offset(rect.left + rect.width * 0.02, rect.bottom),
        Offset(rect.left, rect.bottom - rect.height * 0.02),
      ];

  static PhysicalMediaGeometry _disc() {
    const depth = 0.001886 / 0.1239977, outer = 0.5, hole = 0.0625, hub = 0.15;
    final faces = <MediaFace>[];
    MediaPoint3 point(double radius, double angle, double z) =>
        MediaPoint3(math.cos(angle) * radius, math.sin(angle) * radius, z);
    for (var segment = 0; segment < 48; segment++) {
      final a = segment * math.pi / 24, b = (segment + 1) * math.pi / 24;
      final ofa = point(outer, a, depth / 2),
          ofb = point(outer, b, depth / 2),
          ifa = point(hole, a, depth / 2),
          ifb = point(hole, b, depth / 2),
          oba = point(outer, a, -depth / 2),
          obb = point(outer, b, -depth / 2),
          iba = point(hole, a, -depth / 2),
          ibb = point(hole, b, -depth / 2);
      final hfa = point(hub, a, depth / 2), hfb = point(hub, b, depth / 2);
      faces.add(MediaFace([ofa, ofb, hfb, hfa], const Color(0xffd9dce7)));
      faces.add(MediaFace([hfa, hfb, ifb, ifa], const Color(0xffc2c5ce)));
      faces.add(MediaFace(
          [obb, oba, iba, ibb],
          Color.lerp(const Color(0xff899dac), const Color(0xffdbc1dc),
              (math.sin(a * 3) + 1) / 2)!));
      faces.add(MediaFace([ofb, ofa, oba, obb], const Color(0xffaeb3c0)));
      faces.add(MediaFace([ifa, ifb, ibb, iba], const Color(0xff8b8e98)));
    }
    return PhysicalMediaGeometry._(
        1,
        1,
        depth,
        const Rect.fromLTRB(-0.49, -0.49, 0.49, 0.49),
        Rect.zero,
        List.unmodifiable(faces));
  }

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
      _extrude(faces, polygon, front, back, color);
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

/// One small exterior mesh in Flutter's existing renderer. The label remains an
/// ordinary projected widget, sharing the existing artwork/cache pipeline.
class PhysicalMediaView extends StatefulWidget {
  final String identity, title;
  final Widget label;
  final bool reducedMotion;
  final PhysicalMediaFormat format;
  const PhysicalMediaView(
      {super.key,
      required this.identity,
      required this.title,
      required this.label,
      this.reducedMotion = false,
      this.format = PhysicalMediaFormat.gameBoy});
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
      vsync: this,
      duration: Duration(milliseconds: widget.format.insertionMilliseconds));
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
    if (oldWidget.identity != widget.identity ||
        oldWidget.format != widget.format) {
      _finish(false);
      _insertion.reset();
      _manualRotation = 0;
      _selection.reset();
      _insertion.duration =
          Duration(milliseconds: widget.format.insertionMilliseconds);
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
      if (_insertion.isCompleted) resetInsertion();
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
      label: '3D ${widget.format.description}: ${widget.title}',
      child: LayoutBuilder(
          builder: (context, box) => AnimatedBuilder(
              animation: Listenable.merge([_selection, _idle, _insertion]),
              builder: (context, _) {
                final model = PhysicalMediaGeometry.forFormat(widget.format);
                final phase = _idle.value * math.pi * 2;
                final selected = _reduce
                    ? 1.0
                    : Curves.easeOutBack.transform(_selection.value);
                var rx = 0.18 + (1 - selected) * -0.75,
                    ry = 0.25 + _manualRotation,
                    rz = 0.10;
                var y = 0.0, z = 0.0, scale = 0.85 + 0.15 * selected;
                if (!_reduce && _completion == null) {
                  y = math.sin(phase * 25) * 0.015;
                  rx += math.sin(phase * 15) * 0.05236;
                  ry += math.cos(phase * 12) * 0.02618;
                  rz += math.sin(phase * 18) * 0.04189;
                }
                final seconds = _insertion.value *
                    widget.format.insertionMilliseconds /
                    1000;
                var labelRotation = 0.0, scaleY = 1.0;
                if (_insertion.value > 0) {
                  final lift = Curves.easeOutBack
                      .transform((seconds / 0.15).clamp(0.0, 1.0));
                  y = -0.13 * lift;
                  z = -0.05 * lift;
                  final turn = (seconds / 0.2).clamp(0.0, 1.0);
                  rx *= 1 - turn;
                  rz *= 1 - turn;
                  ry = ry * (1 - turn) +
                      (widget.format == PhysicalMediaFormat.disc
                              ? 0
                              : math.pi * 2) *
                          turn;
                  final spinEnd =
                      widget.format == PhysicalMediaFormat.disc ? 0.3 : 0.2;
                  final descent =
                      widget.format == PhysicalMediaFormat.gameBoy ? 0.2 : 0.3;
                  final landed = spinEnd + descent;
                  if (widget.format == PhysicalMediaFormat.disc) {
                    labelRotation =
                        math.pi * 4 * (seconds / 0.3).clamp(0.0, 1.0);
                  }
                  if (seconds > spinEnd) {
                    y += (widget.format == PhysicalMediaFormat.disc
                            ? 0.7
                            : 1.25) *
                        Curves.easeInExpo.transform(
                            ((seconds - spinEnd) / descent).clamp(0.0, 1.0));
                  }
                  if (widget.format == PhysicalMediaFormat.gameBoy &&
                      seconds > landed) {
                    y -= 0.12 *
                        Curves.easeOutBack.transform(
                            ((seconds - landed) / 0.12).clamp(0.0, 1.0));
                  }
                  if (seconds > landed) {
                    if (widget.format != PhysicalMediaFormat.gameBoy) {
                      final squash =
                          ((seconds - landed) / 0.05).clamp(0.0, 1.0);
                      final settle = Curves.elasticOut.transform(
                          ((seconds - landed) / 0.2).clamp(0.0, 1.0));
                      scaleY = 1 - 0.3 * squash * (1 - settle);
                    }
                    scale *= 1 +
                        0.05 *
                            Curves.elasticOut.transform(((seconds - landed) /
                                    (widget.format ==
                                            PhysicalMediaFormat.gameBoy
                                        ? 0.25
                                        : 0.2))
                                .clamp(0.0, 1.0));
                  }
                  if (widget.format == PhysicalMediaFormat.gameBoy &&
                      seconds > 0.65) {
                    y += 0.12 *
                        Curves.easeInOutBack.transform(
                            ((seconds - 0.65) / 0.2).clamp(0.0, 1.0));
                  }
                  if (widget.format == PhysicalMediaFormat.disc &&
                      seconds > 0.8) {
                    y += 0.55 * ((seconds - 0.8) / 0.8).clamp(0.0, 1.0);
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
                matrix.scaleByDouble(scale, scale * scaleY, scale, 1);
                final labelMatrix = matrix.clone()..rotateZ(labelRotation);
                final labelHeight =
                    widget.format == PhysicalMediaFormat.disc ? 320.0 : 284.0;
                labelMatrix
                  ..translateByDouble(model.label.left, model.label.top,
                      model.depth / 2 + 0.003, 1)
                  ..scaleByDouble(model.label.width / 320,
                      model.label.height / labelHeight, 1, 1);
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
                  if (front && !model.header.isEmpty)
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
                                    height: labelHeight,
                                    child: widget.format ==
                                            PhysicalMediaFormat.disc
                                        ? ClipPath(
                                            clipper: const _DiscLabelClipper(),
                                            child: widget.label)
                                        : widget.format ==
                                                PhysicalMediaFormat.n64
                                            ? ClipPath(
                                                clipper:
                                                    const _N64LabelClipper(),
                                                child: widget.label)
                                            : widget.label)))),
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

class _DiscLabelClipper extends CustomClipper<Path> {
  const _DiscLabelClipper();
  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addOval(Offset.zero & size)
    ..addOval(Rect.fromCircle(
        center: size.center(Offset.zero), radius: size.width * (0.15 / 0.98)));
  @override
  bool shouldReclip(_DiscLabelClipper old) => false;
}

class _N64LabelClipper extends CustomClipper<Path> {
  const _N64LabelClipper();
  @override
  Path getClip(Size size) => Path()
    ..addPolygon(
        PhysicalMediaGeometry._n64LabelOutline(Offset.zero & size), true);
  @override
  bool shouldReclip(_N64LabelClipper oldClipper) => false;
}

class _MediaShellPainter extends CustomPainter {
  // Independent, fixed moulded-plastic grain. Record once in model space;
  // it follows the physical surface rather than flickering in screen space.
  static final ui.Picture _plasticGrain = _recordPlasticGrain();
  static ui.Picture _recordPlasticGrain() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final dark = <Offset>[], light = <Offset>[];
    var seed = 0x53484c4c;
    double next() {
      seed = (seed * 1664525 + 1013904223) & 0xffffffff;
      return seed / 0x100000000;
    }

    for (var y = 0; y < 91; y++) {
      for (var x = 0; x < 81; x++) {
        final point =
            Offset(-0.5 + (x + next()) / 81, -0.6 + (y + next()) * 1.2 / 91);
        (next() < 0.5 ? dark : light).add(point);
      }
    }
    canvas.drawPoints(
        ui.PointMode.points,
        dark,
        Paint()
          ..color = const Color(0x19000000)
          ..strokeWidth = 0.0012);
    canvas.drawPoints(
        ui.PointMode.points,
        light,
        Paint()
          ..color = const Color(0x14ffffff)
          ..strokeWidth = 0.0012);
    return recorder.endRecording();
  }

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
      // The shells have concave shoulders/notches. A local first triangle can
      // face the opposite way; use the complete polygon's oriented normal.
      var nx = 0.0, ny = 0.0, nz = 0.0;
      for (var i = 0; i < points.length; i++) {
        final a = points[i], b = points[(i + 1) % points.length];
        nx += (a.y - b.y) * (a.z + b.z);
        ny += (a.z - b.z) * (a.x + b.x);
        nz += (a.x - b.x) * (a.y + b.y);
      }
      final normal = MediaPoint3(nx, ny, nz);
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
      // Independently shaded plastic/metal; no recovered reference textures.
      // Keep the light in screen space so rotating shells catch a highlight.
      if (projected.face.points.every(
          (p) => (p.z - projected.face.points.first.z).abs() < 0.000001)) {
        final center = _transform(const MediaPoint3(0, 0, 0));
        final bounds = Rect.fromCenter(
            center: Offset(center.x, center.y),
            width: size.width,
            height: size.height);
        if (identical(model, PhysicalMediaGeometry.disc)) {
          paint.shader = SweepGradient(colors: [
            paint.color,
            const Color(0xfff1edf2),
            const Color(0xffbbcbd1),
            paint.color,
            const Color(0xffe8dce9),
            const Color(0xfff0f1e7),
            paint.color,
          ]).createShader(bounds);
        } else {
          paint.shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(paint.color, Colors.black, 0.10)!,
                paint.color,
                Color.lerp(paint.color, Colors.white, 0.18)!,
                paint.color,
              ],
              stops: const [
                0,
                0.36,
                0.62,
                1
              ]).createShader(bounds);
        }
      }
      canvas.drawPath(path, paint);
      if (!identical(model, PhysicalMediaGeometry.disc) &&
          projected.face.points.length > 8 &&
          projected.face.points
              .every((p) => (p.z - model.depth / 2).abs() < 0.000001)) {
        canvas.save();
        canvas.clipPath(path);
        canvas.transform((matrix.clone()
              ..translateByDouble(0, 0, model.depth / 2, 1))
            .storage);
        canvas.drawPicture(_plasticGrain);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_MediaShellPainter old) =>
      old.matrix != matrix || old.model != model;
}
