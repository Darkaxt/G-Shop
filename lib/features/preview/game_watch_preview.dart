import 'package:flutter/material.dart';
import '../../models/console_model.dart';
import '../../models/socket_media_model.dart';
import '../../widgets/socket_media_renderer.dart';
import '../../widgets/media_cover_fallback.dart';
import 'console_hardware_view.dart';

/// Exact single handheld/box resource view. The lower variant preview owns
/// its separate handheld unboxing sequence; this is never a cartridge.
class GameWatchPreview extends StatefulWidget {
  final String filename, title, identity;
  final bool reducedMotion, transparentBackground;
  final SocketMediaPose? libraryPose;
  final bool isBox;
  final SocketMediaPose? inspectionPose;
  final GlobalKey<SocketMediaRendererState>? rendererKey;
  final VoidCallback? onReady;
  const GameWatchPreview(
      {super.key,
      required this.filename,
      required this.title,
      required this.identity,
      this.reducedMotion = false,
      this.transparentBackground = false,
      this.libraryPose,
      this.onReady})
      : isBox = false,
        inspectionPose = null,
        rendererKey = null;
  const GameWatchPreview.box(
      {super.key,
      required this.filename,
      required this.title,
      required this.identity,
      required SocketMediaPose pose,
      this.rendererKey,
      this.reducedMotion = false,
      this.onReady})
      : isBox = true,
        inspectionPose = pose,
        libraryPose = null,
        transparentBackground = true;
  @override
  State<GameWatchPreview> createState() => _GameWatchPreviewState();
}

class _GameWatchPreviewState extends State<GameWatchPreview> {
  late Future<ConsoleModel?> _model;
  bool _fallbackReady = false;
  Future<ConsoleModel?> _findModel() => widget.libraryPose != null
      ? ConsoleModel.findGameWatchLibrary(widget.filename)
      : ConsoleModel.findGameWatch(widget.filename, box: widget.isBox);
  @override
  void initState() {
    super.initState();
    _model = _findModel();
  }

  @override
  void didUpdateWidget(GameWatchPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filename != widget.filename ||
        oldWidget.isBox != widget.isBox ||
        (oldWidget.libraryPose == null) != (widget.libraryPose == null)) {
      _fallbackReady = false;
      _model = _findModel();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ConsoleModel?>(
      future: _model,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final model = snapshot.data;
        if (model == null) {
          if (!_fallbackReady) {
            _fallbackReady = true;
            final filename = widget.filename;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _fallbackReady && widget.filename == filename) {
                widget.onReady?.call();
              }
            });
          }
          if (widget.isBox) {
            return const Center(child: Text('Box model not imported'));
          }
          return MediaCoverFallback(
              systemId: 'gameandwatch',
              title: widget.title,
              identity: widget.identity,
              backgroundColor: Colors.transparent);
        }
        final inspection = widget.inspectionPose;
        if (inspection != null) {
          // ResourceGallery owns the inspection controls. Animate only the
          // supplied opening clip, preserving the same loaded mesh and pose.
          return TweenAnimationBuilder<double>(
              tween: Tween(begin: inspection.opening, end: inspection.opening),
              duration: widget.reducedMotion
                  ? Duration.zero
                  : Duration(milliseconds: model.openingDurationMs),
              builder: (_, opening, __) => SocketMediaRenderer.console(
                  key: widget.rendererKey,
                  model: model,
                  identity:
                      'console:gameandwatch:${model.romSet}:box:${model.generation}',
                  title: widget.title,
                  onReady: widget.onReady,
                  pose: SocketMediaPose(
                      rx: inspection.rx,
                      ry: inspection.ry,
                      rz: inspection.rz,
                      y: inspection.y,
                      z: inspection.z,
                      scaleX: inspection.scaleX,
                      scaleY: inspection.scaleY,
                      scaleZ: inspection.scaleZ,
                      opening: opening)));
        }
        final pose = widget.libraryPose;
        if (pose != null) {
          // The library owns selection motion. Do not run a second viewer
          // controller or attach gestures inside the card's touch target.
          return SocketMediaRenderer.console(
              key: ValueKey('${model.romSet}:${model.generation}'),
              model: model,
              identity:
                  'console:${model.systemId}:${model.romSet}:${model.generation}',
              title: widget.title,
              onReady: widget.onReady,
              pose: SocketMediaPose(
                  opening: !model.isBox && model.canOpen ? 1 : 0,
                  ry: pose.ry,
                  scaleX: .9 * pose.scaleX,
                  scaleY: .9 * pose.scaleY,
                  scaleZ: .9 * pose.scaleZ));
        }
        return ConsoleHardwareView(
            key: ValueKey('${model.romSet}:${model.generation}'),
            model: model,
            title: widget.title,
            showTitle: false,
            turntable: false,
            transparentBackground: widget.transparentBackground,
            reducedMotion: widget.reducedMotion,
            onReady: widget.onReady);
      });
}
