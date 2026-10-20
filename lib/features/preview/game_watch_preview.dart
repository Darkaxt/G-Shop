import 'package:flutter/material.dart';
import '../../models/console_model.dart';
import '../../widgets/media_cover_fallback.dart';
import 'console_hardware_view.dart';

/// A ROM is the complete handheld. It never enters a cartridge/carton timeline.
class GameWatchPreview extends StatefulWidget {
  final String filename, title, identity;
  final bool reducedMotion;
  final VoidCallback? onReady;
  const GameWatchPreview(
      {super.key,
      required this.filename,
      required this.title,
      required this.identity,
      this.reducedMotion = false,
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
        return ConsoleHardwareView(
            key: ValueKey('${model.romSet}:${model.generation}'),
            model: model,
            title: widget.title,
            showTitle: false,
            reducedMotion: widget.reducedMotion,
            onReady: widget.onReady);
      });
}
