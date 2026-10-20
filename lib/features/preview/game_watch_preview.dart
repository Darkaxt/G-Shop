import 'package:flutter/material.dart';
import '../../models/console_model.dart';
import '../../models/socket_media_model.dart';
import '../../widgets/socket_media_renderer.dart';
import '../../widgets/media_cover_fallback.dart';
import 'console_hardware_view.dart';

/// A ROM is the complete handheld. It never enters a cartridge/carton timeline.
class GameWatchPreview extends StatefulWidget {
  final String filename, title, identity;
  final bool reducedMotion, transparentBackground;
  final SocketMediaPose? libraryPose;
  final VoidCallback? onReady;
  const GameWatchPreview(
      {super.key,
      required this.filename,
      required this.title,
      required this.identity,
      this.reducedMotion = false,
      this.transparentBackground = false,
      this.libraryPose,
      this.onReady});
  @override
  State<GameWatchPreview> createState() => _GameWatchPreviewState();
}

class _GameWatchPreviewState extends State<GameWatchPreview> {
  late Future<ConsoleModel?> _model;
  bool _fallbackReady = false;
  @override
  void initState() {
    super.initState();
    _model = ConsoleModel.findGameWatch(widget.filename);
  }

  @override
  void didUpdateWidget(GameWatchPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filename != widget.filename) {
      _fallbackReady = false;
      _model = ConsoleModel.findGameWatch(widget.filename);
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
          return MediaCoverFallback(
              systemId: 'gameandwatch',
              title: widget.title,
              identity: widget.identity,
              backgroundColor: Colors.transparent);
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
                  opening: model.canOpen ? 1 : 0,
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
