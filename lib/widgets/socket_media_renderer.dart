import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math_64.dart' as vm;

import '../models/socket_media_model.dart';
import '../models/packaging_model.dart';
import '../models/console_model.dart';
import '../models/gba_cartridge_model.dart';
import '../models/unboxing_scene.dart';

class SocketMediaRenderer extends StatefulWidget {
  final PhysicalMediaFormat format;
  final PackagingModel? packaging;
  final ConsoleModel? console;
  final String? cartridgeStyle;
  final UnboxingScene? unboxingScene;
  final SocketMediaPose pose;
  final String identity, title;
  final Widget label;
  final Object? labelIdentity;
  final VoidCallback? onReady;
  const SocketMediaRenderer(
      {super.key,
      required this.format,
      required this.pose,
      required this.identity,
      required this.title,
      required this.label,
      this.labelIdentity,
      this.cartridgeStyle,
      this.onReady})
      : packaging = null,
        console = null,
        unboxingScene = null;
  const SocketMediaRenderer.packaging(
      {super.key,
      required PackagingModel model,
      required this.pose,
      required this.identity,
      required this.title,
      required this.label,
      this.labelIdentity,
      this.onReady})
      : packaging = model,
        unboxingScene = null,
        console = null,
        cartridgeStyle = null,
        format = PhysicalMediaFormat.gameBoy;
  const SocketMediaRenderer.console(
      {super.key,
      required ConsoleModel model,
      required this.pose,
      required this.identity,
      required this.title,
      this.onReady})
      : console = model,
        unboxingScene = null,
        packaging = null,
        cartridgeStyle = null,
        format = PhysicalMediaFormat.gameBoy,
        label = const ColoredBox(color: Colors.white),
        labelIdentity = 'console';
  const SocketMediaRenderer.unboxing(
      {super.key,
      required UnboxingScene scene,
      required this.pose,
      required this.identity,
      required this.title,
      required this.label,
      this.labelIdentity,
      this.onReady})
      : unboxingScene = scene,
        packaging = null,
        console = null,
        cartridgeStyle = null,
        format = PhysicalMediaFormat.gba;
  @override
  State<SocketMediaRenderer> createState() => SocketMediaRendererState();
}

class SocketMediaRendererState extends State<SocketMediaRenderer> {
  // Cached viewport children can have layout before a capture layer exists.
  // debugNeedsPaint is always false in release; it is not runtime readiness.
  static bool labelCaptureReady(RenderRepaintBoundary boundary) =>
      boundary.attached && boundary.hasSize && boundary.layer != null;
  final _labelKey = GlobalKey();
  SocketMediaGpu? _renderer;
  AssetBundle? _resources;
  ui.Image? _labelImage;
  gpu.Texture? _labelTexture;
  Object? _error;
  int _generation = 0;
  int _labelRevision = 0;
  int _textureRevision = -1;
  bool _captureQueued = false, _captureDirty = false;
  bool frameRendered = false;
  Completer<Map<String, Object?>> _ready = Completer();
  Completer<Map<String, Object?>>? _poseReady;
  SocketMediaPose? _paintedPose;
  final _clock = Stopwatch();
  int? _modelUs, _labelUs, _gpuUs;
  Size _viewport = Size.zero;
  Future<Map<String, Object?>> get ready => _ready.future;
  Map<String, Rect> get inspectionBounds {
    final model = _renderer?.model;
    if (model == null ||
        model.data['unboxingGeometry'] != true ||
        _viewport.isEmpty) return const {};
    return SocketMediaGpu.inspectionBounds(model, widget.pose, _viewport);
  }

  String? partAt(Offset position) {
    final candidates = inspectionBounds.entries
        .where((entry) => entry.value.contains(position))
        .toList()
      ..sort((a, b) => (a.value.width * a.value.height)
          .compareTo(b.value.width * b.value.height));
    return candidates.firstOrNull?.key;
  }

  Future<Map<String, Object?>> get currentFrameReady {
    if (_error != null || identical(_paintedPose, widget.pose)) {
      return Future.value(snapshot);
    }
    return (_poseReady ??= Completer<Map<String, Object?>>()).future;
  }

  Map<String, Object?> get snapshot => {
        'model': _renderer?.model.name ??
            widget.packaging?.id ??
            widget.console?.systemId ??
            widget.format.assetName,
        'geometrySha256': _renderer?.model.data['geometrySha256'] ??
            _renderer?.model.data['meshSha256'],
        'canOpen': _renderer?.model.data['canOpen'] == true,
        'openingDurationMs': _renderer?.model.data['openingDurationMs'],
        'opening': widget.pose.opening,
        'pageFocus': widget.pose.pageFocus,
        'unboxing': widget.pose.unboxing,
        'inspectedPart': widget.pose.inspectedPart,
        'inspection': widget.pose.inspection,
        'inspectionBounds': {
          for (final entry in inspectionBounds.entries)
            entry.key: [
              entry.value.left,
              entry.value.top,
              entry.value.right,
              entry.value.bottom
            ]
        },
        'paintedPose': _paintedPose == null
            ? null
            : {
                'rx': _paintedPose!.rx,
                'ry': _paintedPose!.ry,
                'scale': _paintedPose!.scaleX,
                'opening': _paintedPose!.opening,
                'pageFocus': _paintedPose!.pageFocus,
                'unboxing': _paintedPose!.unboxing
              },
        'identity': widget.identity,
        'triangles': _renderer?.model.triangles,
        'surfaces': _renderer?.model.surfaces.length,
        'materialTextures': _renderer?.textures.length,
        'environmentMipLevels': _renderer == null
            ? null
            : widget.packaging != null ||
                    widget.console != null ||
                    widget.unboxingScene != null
                ? 1
                : _renderer!.environment.mipLevelCount +
                    _renderer!.environmentTail.length,
        'environmentPrefixMipLevels': _renderer?.environment.mipLevelCount,
        'environmentTailTextures': _renderer?.environmentTail.length,
        'labelReady': _labelTexture != null,
        'frameRendered': frameRendered,
        'error': _error?.toString(),
        'cartridgeStyle': _renderer?.model.data['cartridgeStyle'],
        'transmission': _renderer?.hasTransmission == true
            ? 'thin-shell-opaque-scene'
            : null,
        'sourceApkSha256': widget.packaging == null &&
                widget.console == null &&
                widget.unboxingScene == null &&
                _renderer?.model.data['cartridgeGeometry'] != true
            ? SocketMediaModel.apkSha256
            : null,
        'elapsedMilestonesUs': {
          'modelLoaded': _modelUs,
          'labelCaptured': _labelUs,
          'gpuCommandsCompleted': _gpuUs,
          'physicalDisplayPresented': null,
        },
        'presentationLimit': 'GPU completion is not physical display timing',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SocketMediaRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.format != widget.format ||
        oldWidget.unboxingScene?.style != widget.unboxingScene?.style ||
        oldWidget.unboxingScene?.hasBooklet !=
            widget.unboxingScene?.hasBooklet ||
        oldWidget.unboxingScene?.bookletAspect !=
            widget.unboxingScene?.bookletAspect ||
        oldWidget.packaging?.id != widget.packaging?.id ||
        oldWidget.packaging?.aspect != widget.packaging?.aspect ||
        oldWidget.packaging?.depth != widget.packaging?.depth ||
        oldWidget.console?.generation != widget.console?.generation ||
        oldWidget.cartridgeStyle != widget.cartridgeStyle ||
        oldWidget.identity != widget.identity ||
        _resources != SocketMediaModel.importedBundle) {
      _load();
    } else if (oldWidget.labelIdentity != widget.labelIdentity ||
        (widget.labelIdentity == null && oldWidget.label != widget.label)) {
      if (!_ready.isCompleted) {
        _ready.complete(
            {...snapshot, 'error': 'Label replaced before readiness'});
      }
      _ready = Completer();
      _labelRevision++;
      _labelUs = _gpuUs = null;
      frameRendered = false;
      _error = null;
    }
  }

  Future<void> _load() async {
    _resources = SocketMediaModel.importedBundle;
    if (_generation > 0 && !_ready.isCompleted) {
      _ready.complete({...snapshot, 'error': 'View replaced before readiness'});
    }
    _ready = Completer();
    _clock
      ..reset()
      ..start();
    _modelUs = _labelUs = _gpuUs = null;
    final generation = ++_generation;
    _labelRevision++;
    _renderer = null;
    _labelTexture = null;
    _error = null;
    frameRendered = false;
    _paintedPose = null;
    _labelImage?.dispose();
    _labelImage = null;
    try {
      final renderer = await SocketMediaGpu.load(widget.format,
          owned: widget.unboxingScene != null
              ? await widget.unboxingScene!.load() ??
                  (throw StateError(
                      'Import the holder-enabled box and cartridge'))
              : widget.console != null
                  ? await widget.console!.load()
                  : widget.cartridgeStyle != null &&
                          widget.format == PhysicalMediaFormat.gba
                      ? await GbaCartridgeModel.load(widget.cartridgeStyle!)
                      : await widget.packaging?.load());
      if (!mounted || generation != _generation) return;
      _modelUs = _clock.elapsedMicroseconds;
      setState(() => _renderer = renderer);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _failed(error);
    }
  }

  void _labelPainted() {
    if (_renderer == null || !mounted) return;
    if (_captureQueued) {
      _captureDirty = true;
      return;
    }
    _captureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final generation = _generation;
      final labelRevision = _labelRevision;
      final boundary = _labelKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      try {
        if (boundary == null || !labelCaptureReady(boundary)) return;
        final image = await boundary.toImage(pixelRatio: 1.5);
        if (!mounted ||
            generation != _generation ||
            labelRevision != _labelRevision) {
          image.dispose();
          return;
        }
        final texture = gpu.Texture.fromImage(gpu.gpuContext, image);
        final old = _labelImage;
        setState(() {
          _labelImage = image;
          _labelTexture = texture;
          _textureRevision = labelRevision;
          _labelUs ??= _clock.elapsedMicroseconds;
        });
        old?.dispose();
      } catch (error) {
        if (mounted && generation == _generation) {
          _failed(error);
        }
      } finally {
        _captureQueued = false;
        if (_captureDirty) {
          _captureDirty = false;
          _labelPainted();
        }
      }
    });
  }

  void _rendered(
      SocketMediaGpu submitted, int labelRevision, SocketMediaPose pose) {
    if (!mounted || _renderer != submitted || labelRevision != _labelRevision)
      return;
    _paintedPose = pose;
    if (identical(widget.pose, pose) && _poseReady != null) {
      final pending = _poseReady!;
      _poseReady = null;
      pending.complete({...snapshot, 'frameRendered': true});
    }
    if (frameRendered) return;
    setState(() {
      frameRendered = true;
      _gpuUs = _clock.elapsedMicroseconds;
    });
    if (!_ready.isCompleted) _ready.complete(snapshot);
    widget.onReady?.call();
  }

  void _failed(Object error) {
    if (!mounted) return;
    debugPrint('Physical-media renderer '
        '${widget.packaging?.id ?? widget.cartridgeStyle ?? widget.format.assetName}: $error');
    setState(() => _error = error);
    if (!_ready.isCompleted) _ready.complete(snapshot);
    _poseReady?.complete(snapshot);
    _poseReady = null;
  }

  void _paintFailed(SocketMediaGpu submitted, Object error) {
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation && _renderer == submitted) {
        _failed(error);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _poseReady?.complete({...snapshot, 'error': 'View disposed'});
    _poseReady = null;
    if (!_ready.isCompleted) {
      _ready.complete({...snapshot, 'error': 'View disposed before readiness'});
    }
    _generation++;
    _labelImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    final labelRevision = _textureRevision;
    final pose = widget.pose;
    // Keep 384 logical pixels per face; six faces in a single-label viewport
    // clipped the fallback lettering during the native inspection.
    final labelWidth = widget.packaging == null && widget.unboxingScene == null
        ? 384.0
        : 1152.0;
    return Stack(fit: StackFit.expand, children: [
      // The zero-area ancestor clip hides the producer in the composed screen,
      // but does not suppress its paint/layer. toImage captures that boundary
      // without the ancestor clip. Changes to SmartCoverImage repaint it and
      // trigger one event-driven texture capture, never a polling timer.
      if (renderer != null)
        Positioned(
          left: 0,
          top: 0,
          child: ExcludeSemantics(
              child: IgnorePointer(
                  child: ClipRect(
                      clipper: const _LabelProducerClip(),
                      child: _LabelBoundary(
                          key: _labelKey,
                          onPaint: _labelPainted,
                          child: SizedBox(
                              width: labelWidth,
                              height: labelWidth / renderer.model.labelAspect,
                              child: widget.label))))),
        ),
      if (renderer != null && _labelTexture != null && _error == null)
        CustomPaint(
            key: const ValueKey('physical-media-shell'),
            painter: _SocketMediaPainter(renderer, widget.pose, _labelTexture!,
                MediaQuery.devicePixelRatioOf(context), (size) {
              _viewport = size;
              _rendered(renderer, labelRevision, pose);
            }, (error) => _paintFailed(renderer, error)))
      else
        widget.packaging != null ||
                widget.unboxingScene != null ||
                widget.console != null ||
                widget.cartridgeStyle != null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : const Text('Model unavailable'))
            : widget.label,
    ]);
  }
}

class _LabelProducerClip extends CustomClipper<Rect> {
  const _LabelProducerClip();
  @override
  Rect getClip(Size size) => Rect.zero;
  @override
  bool shouldReclip(_LabelProducerClip old) => false;
}

class _LabelBoundary extends SingleChildRenderObjectWidget {
  final VoidCallback onPaint;
  const _LabelBoundary(
      {super.key, required this.onPaint, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _LabelLayer(onPaint);
  @override
  void updateRenderObject(
      BuildContext context, covariant _LabelLayer renderObject) {
    renderObject.onPaint = onPaint;
  }
}

class _LabelLayer extends RenderRepaintBoundary {
  VoidCallback onPaint;
  _LabelLayer(this.onPaint);
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint();
  }
}

class SocketMediaGpu {
  static int uniformBlockLength(int surfaces, int alignment) {
    int aligned(int bytes) => (bytes + alignment - 1) ~/ alignment * alignment;
    // EnvironmentInfo: 16 floats; each surface has three matrices and 28
    // material floats. This SDK's HostBuffer rollover tests only the aligned
    // start, not the end of a write. Fit the whole pass without a rollover.
    return aligned(16 * 4) + surfaces * (aligned(48 * 4) + aligned(28 * 4));
  }

  static bool partVisible(String? part, SocketMediaPose pose) =>
      part == null || pose.inspectedPart == null || part == pose.inspectedPart;
  static double surfaceOpening(SocketMediaModel model,
      Map<String, dynamic> surface, SocketMediaPose pose) {
    if (model.data['unboxingGeometry'] == true &&
        surface['unboxingPart'] == 'booklet') {
      if (pose.inspectedPart != 'booklet') return 0;
      return (18 *
              math.pi /
              180 /
              (model.data['maxOpenRadians'] as num).toDouble()) *
          pose.inspection;
    }
    return pose.opening;
  }

  // Packaging meshes retain Blender's outward counter-clockwise triangles.
  // Socket's model transform reflects Y, reversing its imported winding.
  static gpu.WindingOrder windingOrder(SocketMediaModel model) =>
      model.data['packagingGeometry'] == true ||
              model.data['hardwareGeometry'] == true ||
              model.data['cartridgeGeometry'] == true ||
              model.data['ownedGeometry'] == true
          ? gpu.WindingOrder.counterClockwise
          : gpu.WindingOrder.clockwise;

  static vm.Matrix4 openingTransform(
      Map<String, dynamic> surface, double opening) {
    final transform = vm.Matrix4.identity();
    for (final raw in surface['openingHinges'] as List? ?? const []) {
      final hinge = raw as Map;
      final keys = (hinge['keys'] as List).cast<List>();
      final t = opening.clamp(0.0, 1.0);
      var angle = (keys.last[1] as num).toDouble();
      for (var i = 1; i < keys.length; i++) {
        final a = keys[i - 1], b = keys[i];
        if (t <= (b[0] as num)) {
          final f = ((t - (a[0] as num)) / ((b[0] as num) - (a[0] as num)))
              .clamp(0.0, 1.0);
          angle =
              (a[1] as num).toDouble() + ((b[1] as num) - (a[1] as num)) * f;
          break;
        }
      }
      final p = (hinge['pivot'] as List).cast<num>();
      final a = (hinge['axis'] as List).cast<num>();
      transform
        ..translateByDouble(
            p[0].toDouble(), p[1].toDouble(), p[2].toDouble(), 1)
        ..rotate(vm.Vector3(a[0].toDouble(), a[1].toDouble(), a[2].toDouble()),
            angle)
        ..translateByDouble(
            -p[0].toDouble(), -p[1].toDouble(), -p[2].toDouble(), 1);
    }
    return transform;
  }

  /// Godot's source camera looks from -Z with a 180-degree Y basis. A selected
  /// Node3D replaces its root rotation (intrinsic YXZ), rather than adding to it.
  /// Undo the converter's Y reflection and baked rest basis exactly once.
  static vm.Matrix4 modelTransform(
      SocketMediaModel model, SocketMediaPose pose) {
    // Turn around the console's original upright axis; pitch is the fixed
    // inspection-camera angle, not an axis tilted by every yaw increment.
    if (model.data['hardwareGeometry'] == true) {
      return vm.Matrix4.identity()
        ..rotateX(pose.rx)
        ..rotateY(pose.ry)
        ..scaleByDouble(pose.scaleX, pose.scaleY, pose.scaleZ, 1);
    }
    if (model.data['ownedGeometry'] == true ||
        model.data['cartridgeGeometry'] == true ||
        model.data['packagingGeometry'] == true) {
      // Reveal the horizontal resting faces by looking down on the whole
      // arrangement. Inspection returns to the ordinary front-facing camera.
      final overviewPitch = model.data['unboxingGeometry'] == true
          ? UnboxingScene.overviewElevation(model, pose.unboxing) *
              (1 - pose.inspection)
          : 0.0;
      final framing = model.data['unboxingGeometry'] == true
          ? UnboxingScene.framing(model, pose.unboxing)
          : 1.0;
      return vm.Matrix4.identity()
        ..translateByDouble(0, pose.y, pose.z, 1)
        ..rotateY(pose.ry * framing)
        ..rotateX(pose.rx * framing +
            overviewPitch +
            (model.data['cartridgeGeometry'] == true ? math.pi / 2 : 0))
        ..rotateZ(pose.rz)
        ..scaleByDouble(pose.scaleX, pose.scaleY, pose.scaleZ, 1);
    }
    final values = (model.data['sourceRootTransform'] as List).cast<num>();
    final rest = vm.Matrix4.identity();
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        rest.setEntry(r, c, values[r * 3 + c].toDouble());
      }
    }
    rest.invert();
    return vm.Matrix4.identity()
      ..translateByDouble(0, pose.y, pose.z, 1)
      ..rotateY(math.pi)
      ..rotateY(pose.ry)
      ..rotateX(pose.rx)
      ..rotateZ(pose.rz)
      ..scaleByDouble(pose.scaleX, pose.scaleY, pose.scaleZ, 1)
      ..multiply(rest)
      ..scaleByDouble(1, -1, 1, 1);
  }

  /// Frame the actual inside-left printed mesh, not an assumed half of the
  /// screen. Its UV corners retain page orientation for imported booklet shapes.
  static vm.Matrix4 bookletPageTransform(SocketMediaModel model, Size size,
      {double pageAspect = 0}) {
    final surface = model.surfaces
        .firstWhere((s) => s['role'] == 'label' && s['atlasCell'] == 2);
    final hinge = surface['openingHinges'] is List
        ? openingTransform(surface, 1)
        : vm.Matrix4.identity();
    if (surface['openingHinges'] is! List && surface['hinged'] == true) {
      final pivot = (surface['pivot'] as List).cast<num>();
      hinge
        ..translateByDouble(pivot[0].toDouble(), 0, 0, 1)
        ..rotateY(-(model.data['maxOpenRadians'] as num).toDouble())
        ..translateByDouble(-pivot[0].toDouble(), 0, 0, 1);
    }
    vm.Vector3 corner(double u, double v) {
      var nearest = double.infinity;
      var point = vm.Vector3.zero();
      for (var i = 0; i < surface['vertexCount']; i++) {
        final offset = (surface['vertexOffset'] as int) + i * 32;
        final du = model.mesh.getFloat32(offset + 24, Endian.little) - u;
        final dv = model.mesh.getFloat32(offset + 28, Endian.little) - v;
        final distance = du * du + dv * dv;
        if (distance < nearest) {
          nearest = distance;
          point = hinge.transform3(vm.Vector3(
              model.mesh.getFloat32(offset, Endian.little),
              model.mesh.getFloat32(offset + 4, Endian.little),
              model.mesh.getFloat32(offset + 8, Endian.little)));
        }
      }
      return point;
    }

    // Atlas cell 2 occupies the top-right third in the two-row atlas.
    final tl = corner(2 / 3, 0), tr = corner(1, 0), bl = corner(2 / 3, .5);
    final right = tr - tl, up = tl - bl;
    final width = right.length, height = up.length;
    right.normalize();
    up.normalize();
    final normal = right.cross(up)..normalize();
    final basis = vm.Matrix4.columns(
        vm.Vector4(right.x, right.y, right.z, 0),
        vm.Vector4(up.x, up.y, up.z, 0),
        vm.Vector4(normal.x, normal.y, normal.z, 0),
        vm.Vector4(0, 0, 0, 1))
      ..invert();
    final centre = (tr + bl) * .5;
    final ratio = pageAspect > 0 ? pageAspect : width / height;
    final displayWidth = math.min(size.width, size.height * ratio);
    final units = fittedUnits(model, size);
    final sx = displayWidth / width / units;
    final sy = displayWidth / ratio / height / units;
    return vm.Matrix4.diagonal3Values(sx, sy, math.min(sx, sy))
      ..multiply(basis)
      ..translateByDouble(-centre.x, -centre.y, -centre.z, 1);
  }

  static vm.Matrix4 cameraProjection(
          double width, double height, double units) =>
      vm.Matrix4.identity()
        ..setEntry(0, 0, units * 2 / width)
        // GpuImageSurface presents +clip-Y at the image top, like Godot's
        // camera. Canvas's downward Y must not be applied a second time here.
        ..setEntry(1, 1, units * 2 / height)
        // After perspective division, depth must decrease toward the +Z
        // camera. -.1 made (.5-.1*z)/(1-.25*z) increase, drawing backs first.
        ..setEntry(2, 2, -.25)
        ..setEntry(2, 3, .5)
        ..setEntry(3, 2, -.25);

  static double fittedUnits(SocketMediaModel model, Size size,
      {SocketMediaPose? pose}) {
    if (model.data['unboxingGeometry'] == true) {
      final overview =
          math.min(size.width / 6.4, size.height * .68 / model.height);
      final frontZ = (model.data['bounds'][2] as num).toDouble() / 2;
      final front =
          math.min(size.width / model.sourceWidth, size.height / model.height) *
              .9 *
              (1 - .25 * frontZ);
      final framing = UnboxingScene.framing(model, pose?.unboxing ?? 1);
      return front + (overview - front) * framing;
    }
    return model.data['hardwareGeometry'] == true
        ? math.min(size.width * .72 / model.sourceWidth,
            size.height * .68 / model.height)
        : math.min(size.width * .72, size.height * .68 / model.height);
  }

  static Map<String, Rect> inspectionBounds(
      SocketMediaModel model, SocketMediaPose pose, Size size) {
    final units = fittedUnits(model, size, pose: pose);
    final projection = cameraProjection(size.width, size.height, units);
    final base = modelTransform(model, pose);
    final result = <String, Rect>{};
    for (final entry in (model.data['partBounds'] as Map).entries) {
      if (!partVisible(entry.key as String, pose)) continue;
      final bounds = (entry.value as List).cast<List>();
      final transform = projection.clone()
        ..multiply(base)
        ..multiply(UnboxingScene.partTransform(
            model, entry.key as String, pose.unboxing, size.width / units,
            inspectedPart: pose.inspectedPart, inspection: pose.inspection));
      var left = double.infinity,
          top = double.infinity,
          right = double.negativeInfinity,
          bottom = double.negativeInfinity;
      for (var x = 0; x < 2; x++) {
        for (var y = 0; y < 2; y++) {
          for (var z = 0; z < 2; z++) {
            final v = transform.transform(vm.Vector4(
                (bounds[x][0] as num).toDouble(),
                (bounds[y][1] as num).toDouble(),
                (bounds[z][2] as num).toDouble(),
                1));
            final px = (v.x / v.w + 1) * size.width / 2;
            final py = (1 - v.y / v.w) * size.height / 2;
            left = math.min(left, px);
            top = math.min(top, py);
            right = math.max(right, px);
            bottom = math.max(bottom, py);
          }
        }
      }
      result[entry.key as String] = Rect.fromLTRB(left, top, right, bottom);
    }
    return result;
  }

  final SocketMediaModel model;
  final gpu.RenderPipeline pipeline;
  final gpu.DeviceBuffer mesh;
  final Map<String, gpu.Texture> textures;
  final gpu.Texture white, flatNormal;
  final gpu.Texture environment;
  final List<gpu.Texture> environmentTail;
  final Map<String, dynamic> environmentData;
  // Flutter GPU currently limits 1024x512 to nine mips, unlike Godot/Vulkan's
  // eleven. Keep the final 2x1 and 1x1 source blocks in separate 4x4 ASTC textures;
  // the shader samples only their logical texels and interpolates the LOD seam.
  static const environmentPrefixMipLevels = 9;
  gpu.GpuImageSurface? _surface;
  gpu.Texture? _depth;
  gpu.Texture? _opaqueScene, _opaqueDepth;
  bool get hasTransmission =>
      model.surfaces.any((s) => transmitting(s['material']));
  static bool transmitting(Map material) =>
      ((material['sourceProperties']?['transmission'] as num?) ?? 0) > 0;
  SocketMediaGpu._(
      this.model,
      this.pipeline,
      this.mesh,
      this.textures,
      this.white,
      this.flatNormal,
      this.environment,
      this.environmentTail,
      this.environmentData);

  static bool plasticHousing(String model, Map<String, dynamic> surface) {
    if ({'glass', 'source'}.contains(surface['physicalMaterial'])) return false;
    if (model == 'disc' || surface['role'] == 'label') return false;
    final node = surface['node'] as String;
    final name = (surface['name'] as String).toLowerCase();
    if (model == 'psp' && node.contains('/Disc -')) return false;
    return !{'gold contacts', 'cartridge nuts', 'cartridge board'}
            .contains(name) &&
        !{'circuitboard', 'circuit_board', 'screw'}
            .contains(node.split('/').last.toLowerCase());
  }

  static Float32List materialUniforms(Map<String, dynamic> material,
      {bool isLabel = false,
      bool isDisc = false,
      bool plasticHousing = false}) {
    final props = (material['sourceProperties'] as Map?) ?? const {};
    double number(String key, double fallback) =>
        ((props['shader_parameter/$key'] ?? props[key]) as num?)?.toDouble() ??
        fallback;
    final casing =
        (material['shaderSource'] as String?)?.contains('casing') ?? false;
    final color = (material['color'] as List).cast<num>();
    // Imported metallic wear is not the physical material of a plastic housing.
    final plastic = plasticHousing && !isLabel;
    final offset =
        ((props['shader_parameter/uv_offset'] as Map?)?['values'] as List?) ??
            [0, 0];
    return Float32List.fromList([
      ...(isLabel ? [1.0, 1.0, 1.0, 1.0] : color.map((v) => v.toDouble())),
      number(casing ? 'roughness_scale' : 'roughness', isLabel ? .85 : 1),
      (plastic ? 0 : number(casing ? 'metallic_scale' : 'metallic', 0)) *
          (casing ? number('metallic_impact', 1) : 1),
      number(casing ? 'normal_depth' : 'normal_scale', 1),
      number('tint_strength', 1),
      number('uv_scale', 1),
      (offset[0] as num).toDouble(),
      (offset[1] as num).toDouble(),
      number('albedo_impact', 1),
      casing ? 1 : 0,
      isLabel ? 1 : 0,
      isDisc && !isLabel ? 1 : 0,
      number('ao_strength', 1),
      number('roughness_texture_channel', 0),
      number('metallic_texture_channel', 0),
      number('ao_texture_channel', 0),
      // A .75 floor still produces bright grazing HDR reflection from the
      // imported studio sky. Matte molded housings use the fully rough lobe;
      // labels, optical media and exposed hardware retain their source finish.
      plastic ? 1 : 0,
      ...((props['emission'] as List?) ?? const [0, 0, 0])
          .cast<num>()
          .map((v) => v.toDouble()),
      (material['textures'] as Map?)?['emission'] != null ? 1 : 0,
      number('transmission', 0),
      number('ior', 1.5),
      number('thickness', 0),
      0,
    ]);
  }

  static Future<SocketMediaGpu> load(PhysicalMediaFormat format,
      {SocketMediaModel? owned}) async {
    final context = gpu.gpuContext;
    final model = owned ?? await SocketMediaModel.load(format);
    final sky = owned == null
        ? await SocketMediaModel.loadEnvironment()
        : (
            data: <String, dynamic>{
              'width': 1,
              'height': 1,
              'mips': [
                {'offset': 0, 'length': 4}
              ],
              'lightDirection': [.35, .65, .7],
              'lightEnergy': 2.0,
              'ambientEnergy': .8,
              'reflectionEnergy': 0.0,
              'exposure': 1.0
            },
            pixels:
                ByteData.sublistView(Uint8List.fromList([180, 180, 180, 255]))
          );
    if (owned == null &&
        !context.supportsTextureFormat(gpu.PixelFormat.astc4x4HDR)) {
      throw StateError(
          'Source HDR environment requires ASTC HDR texture support');
    }
    final environment = context.createTexture(gpu.StorageMode.hostVisible,
        sky.data['width'] as int, sky.data['height'] as int,
        format: owned == null
            ? gpu.PixelFormat.astc4x4HDR
            : gpu.PixelFormat.r8g8b8a8UNormInt,
        enableRenderTargetUsage: false,
        mipLevelCount: owned == null ? environmentPrefixMipLevels : 1);
    for (var level = 0; level < environment.mipLevelCount; level++) {
      final range = sky.data['mips'][level] as Map;
      environment.overwrite(
          sky.pixels.buffer.asByteData(
              sky.pixels.offsetInBytes + (range['offset'] as int),
              range['length'] as int),
          mipLevel: level);
    }
    final environmentTail = <gpu.Texture>[];
    for (final range
        in (sky.data['mips'] as List).skip(environmentPrefixMipLevels)) {
      final texture = context.createTexture(gpu.StorageMode.hostVisible, 4, 4,
          format: gpu.PixelFormat.astc4x4HDR, enableRenderTargetUsage: false);
      texture.overwrite(sky.pixels.buffer.asByteData(
          sky.pixels.offsetInBytes + (range['offset'] as int),
          range['length'] as int));
      environmentTail.add(texture);
    }
    if (owned != null) {
      environmentTail.addAll([environment, environment]);
    }
    final library = await gpu.ShaderLibrary.fromAsset(
        'assets/shaders/socket_media.shaderbundle');
    if (library == null) {
      throw StateError('Physical-media shader bundle unavailable');
    }
    final pipeline = context.createRenderPipeline(
        library['SocketMediaVertex']!, library['SocketMediaFragment']!,
        vertexLayout: const gpu.VertexLayout(buffers: [
          gpu.VertexBuffer(strideInBytes: 32, attributes: [
            gpu.VertexAttribute(
                name: 'position', format: gpu.VertexFormat.float32x3),
            gpu.VertexAttribute(
                name: 'normal',
                format: gpu.VertexFormat.float32x3,
                offsetInBytes: 12),
            gpu.VertexAttribute(
                name: 'texture_coords',
                format: gpu.VertexFormat.float32x2,
                offsetInBytes: 24),
          ])
        ]));
    gpu.Texture pixel(List<int> rgba) {
      final t = context.createTexture(gpu.StorageMode.hostVisible, 1, 1,
          enableRenderTargetUsage: false);
      t.overwrite(Uint8List.fromList(rgba).buffer.asByteData());
      return t;
    }

    final textures = <String, gpu.Texture>{};
    for (final surface in model.surfaces) {
      final maps = (surface['material']['textures'] as Map?) ?? const {};
      for (final file in maps.values.cast<String>()) {
        if (textures.containsKey(file)) continue;
        final data =
            await (model.textureBundle ?? SocketMediaModel.importedBundle)!
                .load('${SocketMediaModel.assetRoot}$file');
        final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        final image = (await codec.getNextFrame()).image;
        try {
          final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawStraightRgba))!;
          final texture = context.createTexture(
              gpu.StorageMode.hostVisible, image.width, image.height,
              enableRenderTargetUsage: false);
          texture.overwrite(rgba);
          textures[file] = texture;
        } finally {
          image.dispose();
          codec.dispose();
        }
      }
    }
    return SocketMediaGpu._(
        model,
        pipeline,
        context.createDeviceBufferWithCopy(model.mesh),
        textures,
        pixel([255, 255, 255, 255]),
        pixel([128, 128, 255, 255]),
        environment,
        environmentTail,
        sky.data);
  }

  void paint(Canvas canvas, Size size, double ratio, SocketMediaPose pose,
      gpu.Texture label, VoidCallback completed, ValueChanged<Object> failed) {
    if (size.isEmpty) return;
    final context = gpu.gpuContext;
    final width = (size.width * ratio).ceil(),
        height = (size.height * ratio).ceil();
    if (_surface == null ||
        _surface!.width != width ||
        _surface!.height != height) {
      // Vulkan caches the framebuffer on each surface color attachment. Keep
      // that attachment paired with its original depth texture for its entire
      // lifetime: resizing a pooled surface can reuse an earlier color texture
      // after its depth attachment has been replaced.
      _surface = context.createImageSurface(width, height);
      _depth = context.createTexture(
          gpu.StorageMode.devicePrivate, width, height,
          format: context.defaultDepthStencilFormat,
          enableShaderReadUsage: false);
      if (hasTransmission) {
        _opaqueScene =
            context.createTexture(gpu.StorageMode.devicePrivate, width, height);
        _opaqueDepth = context.createTexture(
            gpu.StorageMode.devicePrivate, width, height,
            format: context.defaultDepthStencilFormat,
            enableShaderReadUsage: false);
      }
    }
    final frame = _surface!.acquireNextFrame();
    final commands = context.createCommandBuffer();
    try {
      void draw(gpu.CommandBuffer commandBuffer, gpu.Texture target,
          gpu.Texture depthTarget,
          {bool opaqueOnly = false}) {
        final pass = commandBuffer.createRenderPass(
            gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target),
                depthStencilAttachment: gpu.DepthStencilAttachment(
                    texture: depthTarget, depthClearValue: 1)));
        pass.bindPipeline(pipeline);
        pass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
        pass.setCullMode(gpu.CullMode.none);
        pass.setWindingOrder(windingOrder(model));
        pass.setColorBlendEnable(true);
        pass.setColorBlendEquation(gpu.ColorBlendEquation());
        final units = fittedUnits(model, size, pose: pose);
        final projection = cameraProjection(size.width, size.height, units);
        final base = pose.pageFocus == 0
            ? modelTransform(model, pose)
            : Matrix4Tween(
                    begin: modelTransform(model, pose),
                    end: bookletPageTransform(model, size,
                        pageAspect: pose.pageAspect))
                .transform(pose.pageFocus);
        final uniforms = context.createHostBuffer(
            blockLengthInBytes: uniformBlockLength(
                model.surfaces.length, context.minimumUniformByteAlignment));
        final direction =
            (environmentData['lightDirection'] as List).cast<num>();
        pass.bindUniform(
            pipeline.fragmentShader.getUniformSlot('EnvironmentInfo'),
            uniforms.emplace(Float32List.fromList([
              ...direction.map((v) => v.toDouble()),
              (environmentData['lightEnergy'] as num).toDouble(),
              ((environmentData['mips'] as List).length - 1).toDouble(),
              (environmentData['ambientEnergy'] as num).toDouble(),
              (environmentData['reflectionEnergy'] as num).toDouble(),
              (environmentData['exposure'] as num).toDouble(),
              (environment.mipLevelCount - 1).toDouble(),
              0,
              0,
              0,
              width.toDouble(),
              height.toDouble(),
              projection.entry(0, 0),
              projection.entry(1, 1),
            ]).buffer.asByteData()));
        pass.bindTexture(pipeline.fragmentShader.getUniformSlot('opaque_scene'),
            opaqueOnly ? white : _opaqueScene ?? white,
            sampler: gpu.SamplerOptions(
                minFilter: gpu.MinMagFilter.linear,
                magFilter: gpu.MinMagFilter.linear,
                widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
                heightAddressMode: gpu.SamplerAddressMode.clampToEdge));
        pass.bindTexture(
            pipeline.fragmentShader.getUniformSlot('environment_map'),
            environment,
            sampler: gpu.SamplerOptions(
                minFilter: gpu.MinMagFilter.linear,
                magFilter: gpu.MinMagFilter.linear,
                mipFilter: gpu.MipFilter.linear,
                widthAddressMode: gpu.SamplerAddressMode.repeat,
                heightAddressMode: gpu.SamplerAddressMode.clampToEdge));
        for (var i = 0; i < environmentTail.length; i++) {
          pass.bindTexture(
              pipeline.fragmentShader.getUniformSlot('environment_tail_$i'),
              environmentTail[i],
              sampler: gpu.SamplerOptions(
                  minFilter: gpu.MinMagFilter.nearest,
                  magFilter: gpu.MinMagFilter.nearest));
        }
        final ordered = [...model.surfaces]..sort((a, b) =>
            (transmitting(a['material']) ||
                        (a['material']['color'][3] as num) < 1
                    ? 1
                    : 0)
                .compareTo(transmitting(b['material']) ||
                        (b['material']['color'][3] as num) < 1
                    ? 1
                    : 0));
        for (final surface in ordered) {
          if (!partVisible(surface['unboxingPart'] as String?, pose)) continue;
          final opening = surfaceOpening(model, surface, pose);
          if (opaqueOnly && transmitting(surface['material'])) continue;
          pass.setCullMode(surface['singleSided'] == true
              ? gpu.CullMode.backFace
              : gpu.CullMode.none);
          final isLabel = surface['role'] == 'label';
          final transform = base.clone();
          if (model.data['unboxingGeometry'] == true) {
            transform.multiply(UnboxingScene.partTransform(
                model,
                surface['unboxingPart'] as String,
                pose.unboxing,
                size.width / units,
                inspectedPart: pose.inspectedPart,
                inspection: pose.inspection));
          }
          if (surface['openingHinges'] is List) {
            transform.multiply(openingTransform(surface, opening));
          } else if (surface['hinged'] == true && opening != 0) {
            final pivot = (surface['pivot'] as List).cast<num>();
            transform
              ..translateByDouble(pivot[0].toDouble(), 0, 0, 1)
              ..rotateY(-opening.clamp(0, 1) *
                  (model.data['maxOpenRadians'] as num).toDouble())
              ..translateByDouble(-pivot[0].toDouble(), 0, 0, 1);
          }
          if (pose.labelSpin != 0 && (isLabel || model.motionKind == 'disc')) {
            final pivot = (surface['pivot'] as List).cast<num>();
            final axis = (surface['spinAxis'] as List).cast<num>();
            transform
              ..translateByDouble(pivot[0].toDouble(), pivot[1].toDouble(),
                  pivot[2].toDouble(), 1)
              ..rotate(
                  vm.Vector3(axis[0].toDouble(), axis[1].toDouble(),
                      axis[2].toDouble()),
                  pose.labelSpin)
              ..translateByDouble(-pivot[0].toDouble(), -pivot[1].toDouble(),
                  -pivot[2].toDouble(), 1);
          }
          final normal = vm.Matrix4.copy(transform)
            ..invert()
            ..transpose();
          final mvp = projection * transform;
          pass.bindUniform(
              pipeline.vertexShader.getUniformSlot('VertInfo'),
              uniforms.emplace(Float32List.fromList(
                      [...mvp.storage, ...transform.storage, ...normal.storage])
                  .buffer
                  .asByteData()));
          final material = surface['material'] as Map<String, dynamic>;
          // Transmission already includes the opaque background sample. Replace
          // its pixel rather than compositing that background for a second time.
          pass.setColorBlendEnable(!transmitting(material));
          pass.setDepthWriteEnable((material['color'][3] as num) >= 1);
          pass.bindUniform(
              pipeline.fragmentShader.getUniformSlot('FragInfo'),
              uniforms.emplace(materialUniforms(material,
                      isLabel: isLabel,
                      isDisc: model.motionKind == 'disc',
                      plasticHousing:
                          SocketMediaGpu.plasticHousing(model.name, surface))
                  .buffer
                  .asByteData()));
          final maps = (material['textures'] as Map?) ?? const {};
          for (final role in [
            'albedo',
            'roughness',
            'metallic',
            'normal',
            'ao',
            'emission'
          ]) {
            final texture = role == 'albedo' && isLabel
                ? label
                : textures[maps[role]] ??
                    (role == 'normal' ? flatNormal : white);
            pass.bindTexture(
                pipeline.fragmentShader.getUniformSlot('${role}_map'), texture,
                sampler: gpu.SamplerOptions(
                    minFilter: gpu.MinMagFilter.linear,
                    magFilter: gpu.MinMagFilter.linear,
                    widthAddressMode: isLabel
                        ? gpu.SamplerAddressMode.clampToEdge
                        : gpu.SamplerAddressMode.repeat,
                    heightAddressMode: isLabel
                        ? gpu.SamplerAddressMode.clampToEdge
                        : gpu.SamplerAddressMode.repeat));
          }
          pass.bindVertexBuffer(gpu.BufferView(mesh,
              offsetInBytes: surface['vertexOffset'] as int,
              lengthInBytes: (surface['vertexCount'] as int) * 32));
          pass.bindIndexBuffer(
              gpu.BufferView(mesh,
                  offsetInBytes: surface['indexOffset'] as int,
                  lengthInBytes: (surface['indexCount'] as int) * 4),
              gpu.IndexType.int32);
          pass.drawIndexed(surface['indexCount'] as int);
        }
      }

      if (hasTransmission) {
        // RenderPassVK begins in its constructor and ends when submit encodes
        // it. Two Dart passes on one live buffer would nest native passes.
        // Submit the opaque producer before opening the composite consumer;
        // the graphics queue orders GPU work without a timer or CPU wait.
        final opaqueCommands = context.createCommandBuffer();
        draw(opaqueCommands, _opaqueScene!, _opaqueDepth!, opaqueOnly: true);
        opaqueCommands.submit();
      }
      draw(commands, frame.colorTexture, _depth!);
      frame.present(commands);
      commands.submit(completionCallback: (success) {
        if (success) {
          completed();
        } else {
          failed(StateError('Physical-media GPU submission failed'));
        }
      });
      final image = _surface!.currentImage!;
      try {
        canvas.drawImageRect(
            image,
            Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
            Offset.zero & size,
            Paint());
      } finally {
        image.dispose();
      }
    } catch (error) {
      frame.discard();
      failed(error);
    }
  }
}

class _SocketMediaPainter extends CustomPainter {
  final SocketMediaGpu renderer;
  final SocketMediaPose pose;
  final gpu.Texture label;
  final double ratio;
  final ValueChanged<Size> rendered;
  final ValueChanged<Object> failed;
  _SocketMediaPainter(this.renderer, this.pose, this.label, this.ratio,
      this.rendered, this.failed);
  @override
  void paint(Canvas canvas, Size size) => renderer.paint(
      canvas, size, ratio, pose, label, () => rendered(size), failed);
  @override
  bool shouldRepaint(_SocketMediaPainter old) =>
      old.renderer != renderer ||
      old.pose != pose ||
      old.label != label ||
      old.ratio != ratio;
}
