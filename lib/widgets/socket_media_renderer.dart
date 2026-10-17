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

class SocketMediaRenderer extends StatefulWidget {
  final PhysicalMediaFormat format;
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
      this.onReady});
  @override
  State<SocketMediaRenderer> createState() => SocketMediaRendererState();
}

class SocketMediaRendererState extends State<SocketMediaRenderer> {
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
  final _clock = Stopwatch();
  int? _modelUs, _labelUs, _gpuUs;
  Future<Map<String, Object?>> get ready => _ready.future;
  Map<String, Object?> get snapshot => {
        'model': widget.format.assetName,
        'identity': widget.identity,
        'triangles': _renderer?.model.triangles,
        'surfaces': _renderer?.model.surfaces.length,
        'materialTextures': _renderer?.textures.length,
        'environmentMipLevels': _renderer == null
            ? null
            : _renderer!.environment.mipLevelCount +
                _renderer!.environmentTail.length,
        'environmentPrefixMipLevels': _renderer?.environment.mipLevelCount,
        'environmentTailTextures': _renderer?.environmentTail.length,
        'labelReady': _labelTexture != null,
        'frameRendered': frameRendered,
        'error': _error?.toString(),
        'sourceApkSha256': SocketMediaModel.apkSha256,
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
      _labelPainted();
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
    _labelImage?.dispose();
    _labelImage = null;
    try {
      final renderer = await SocketMediaGpu.load(widget.format);
      if (!mounted || generation != _generation) return;
      _modelUs = _clock.elapsedMicroseconds;
      setState(() => _renderer = renderer);
      _labelPainted();
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _failed(error);
      debugPrint('Physical-media renderer: $error');
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
        if (boundary == null || boundary.debugNeedsPaint) return;
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

  void _rendered(SocketMediaGpu submitted, int labelRevision) {
    if (!mounted ||
        frameRendered ||
        _renderer != submitted ||
        labelRevision != _labelRevision) return;
    setState(() {
      frameRendered = true;
      _gpuUs = _clock.elapsedMicroseconds;
    });
    if (!_ready.isCompleted) _ready.complete(snapshot);
    widget.onReady?.call();
  }

  void _failed(Object error) {
    if (!mounted) return;
    setState(() => _error = error);
    if (!_ready.isCompleted) _ready.complete(snapshot);
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
                              width: 384,
                              height: 384 / renderer.model.labelAspect,
                              child: widget.label))))),
        ),
      if (renderer != null && _labelTexture != null && _error == null)
        CustomPaint(
            key: const ValueKey('physical-media-shell'),
            painter: _SocketMediaPainter(
                renderer,
                widget.pose,
                _labelTexture!,
                MediaQuery.devicePixelRatioOf(context),
                () => _rendered(renderer, labelRevision),
                (error) => _paintFailed(renderer, error)))
      else
        widget.label,
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
  /// Godot's source camera looks from -Z with a 180-degree Y basis. A selected
  /// Node3D replaces its root rotation (intrinsic YXZ), rather than adding to it.
  /// Undo the converter's Y reflection and baked rest basis exactly once.
  static vm.Matrix4 modelTransform(
      SocketMediaModel model, SocketMediaPose pose) {
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
    ]);
  }

  static Future<SocketMediaGpu> load(PhysicalMediaFormat format) async {
    final context = gpu.gpuContext;
    final model = await SocketMediaModel.load(format);
    final sky = await SocketMediaModel.loadEnvironment();
    if (!context.supportsTextureFormat(gpu.PixelFormat.astc4x4HDR)) {
      throw StateError(
          'Source HDR environment requires ASTC HDR texture support');
    }
    final environment = context.createTexture(gpu.StorageMode.hostVisible,
        sky.data['width'] as int, sky.data['height'] as int,
        format: gpu.PixelFormat.astc4x4HDR,
        enableRenderTargetUsage: false,
        mipLevelCount: environmentPrefixMipLevels);
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
        final data = await SocketMediaModel.importedBundle!
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
    }
    final frame = _surface!.acquireNextFrame();
    final commands = context.createCommandBuffer();
    try {
      final pass = commands.createRenderPass(gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(texture: frame.colorTexture),
          depthStencilAttachment: gpu.DepthStencilAttachment(
              texture: _depth!, depthClearValue: 1)));
      pass.bindPipeline(pipeline);
      pass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
      pass.setCullMode(gpu.CullMode.none);
      pass.setWindingOrder(gpu.WindingOrder.clockwise);
      pass.setColorBlendEnable(true);
      pass.setColorBlendEquation(gpu.ColorBlendEquation());
      final units =
          math.min(size.width * .72, size.height * .68 / model.height);
      final projection = cameraProjection(size.width, size.height, units);
      final base = modelTransform(model, pose);
      final uniforms = context.createHostBuffer(blockLengthInBytes: 16 * 1024);
      final direction = (environmentData['lightDirection'] as List).cast<num>();
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
          ]).buffer.asByteData()));
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
          ((a['material']['color'][3] as num) < 1 ? 1 : 0)
              .compareTo((b['material']['color'][3] as num) < 1 ? 1 : 0));
      for (final surface in ordered) {
        final isLabel = surface['role'] == 'label';
        final transform = base.clone();
        if (pose.labelSpin != 0 && (isLabel || model.motionKind == 'disc')) {
          final pivot = (surface['pivot'] as List).cast<num>();
          final axis = (surface['spinAxis'] as List).cast<num>();
          transform
            ..translateByDouble(pivot[0].toDouble(), pivot[1].toDouble(),
                pivot[2].toDouble(), 1)
            ..rotate(
                vm.Vector3(
                    axis[0].toDouble(), axis[1].toDouble(), axis[2].toDouble()),
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
          'ao'
        ]) {
          final texture = role == 'albedo' && isLabel
              ? label
              : textures[maps[role]] ?? (role == 'normal' ? flatNormal : white);
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
  final VoidCallback rendered;
  final ValueChanged<Object> failed;
  _SocketMediaPainter(this.renderer, this.pose, this.label, this.ratio,
      this.rendered, this.failed);
  @override
  void paint(Canvas canvas, Size size) =>
      renderer.paint(canvas, size, ratio, pose, label, rendered, failed);
  @override
  bool shouldRepaint(_SocketMediaPainter old) =>
      old.renderer != renderer ||
      old.pose != pose ||
      old.label != label ||
      old.ratio != ratio;
}
