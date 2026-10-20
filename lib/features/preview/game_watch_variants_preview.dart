import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/console_model.dart';
import 'console_hardware_view.dart';
import 'game_watch_preview.dart';

/// Bottom-screen presentation only. Cards and Resources retain exact lookup.
class GameWatchVariantsPreview extends StatefulWidget {
  final String filename, title, identity;
  final bool reducedMotion;
  final VoidCallback? onReady;
  final Directory? modelsDirectory;
  const GameWatchVariantsPreview(
      {super.key,
      required this.filename,
      required this.title,
      required this.identity,
      this.reducedMotion = false,
      this.onReady,
      this.modelsDirectory});
  @override
  State<GameWatchVariantsPreview> createState() =>
      GameWatchVariantsPreviewState();
}

class GameWatchVariantsPreviewState extends State<GameWatchVariantsPreview> {
  final _viewKey = GlobalKey<GameWatchVariantsViewState>();
  late Future<List<GameWatchModelVariant>> _models;
  bool _errorReported = false;
  Map<String, Object?>? get snapshot => _viewKey.currentState?.snapshot;
  void _load() {
    _errorReported = false;
    _models = ConsoleModel.findGameWatchVariants(widget.filename,
        modelsDirectory: widget.modelsDirectory);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GameWatchVariantsPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filename != widget.filename ||
        oldWidget.modelsDirectory?.path != widget.modelsDirectory?.path) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<GameWatchModelVariant>>(
          future: _models,
          builder: (context, result) {
            if (result.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final variants = result.data;
            if (result.hasError && !_errorReported) {
              _errorReported = true;
              debugPrint(
                  'RShopGameWatchVariants import unavailable: ${result.error}');
            }
            if (variants == null || variants.isEmpty) {
              // An optional visual catalogue cannot hide the exact primary or the
              // existing honest fallback when no primary has been imported.
              return GameWatchPreview(
                  filename: widget.filename,
                  title: widget.title,
                  identity: widget.identity,
                  reducedMotion: widget.reducedMotion,
                  onReady: widget.onReady);
            }
            return GameWatchVariantsView(
                key: _viewKey,
                variants: variants,
                reducedMotion: widget.reducedMotion,
                onReady: widget.onReady);
          });
}

class GameWatchVariantsView extends StatefulWidget {
  final List<GameWatchModelVariant> variants;
  final bool reducedMotion;
  final VoidCallback? onReady;
  const GameWatchVariantsView(
      {super.key,
      required this.variants,
      this.reducedMotion = false,
      this.onReady});
  @override
  State<GameWatchVariantsView> createState() => GameWatchVariantsViewState();
}

class GameWatchVariantsViewState extends State<GameWatchVariantsView> {
  late List<GlobalKey<ConsoleHardwareViewState>> _keys;
  final _ready = <int>{};
  int _generation = 0;
  bool _reported = false;
  String _signature(List<GameWatchModelVariant> models) => models
      .map((v) => '${v.model.directory.path}:${v.model.generation}')
      .join('|');
  void _reset() {
    _generation++;
    _keys = [
      for (final _ in widget.variants) GlobalKey<ConsoleHardwareViewState>()
    ];
    _ready.clear();
    _reported = false;
  }

  Map<String, Object?> get snapshot => {
        'frameRendered': _reported,
        'expectedModels': widget.variants.length,
        'readyModels': _ready.length,
        'layout': widget.variants.length > 1 ? 'sideBySide' : 'single',
        'error': _keys
            .map((key) => key.currentState?.snapshot['error'])
            .where((value) => value != null)
            .firstOrNull,
        'models': [for (final key in _keys) key.currentState?.snapshot],
      };
  void _rendered(int index, int generation) {
    if (!mounted || generation != _generation || _reported) return;
    _ready.add(index);
    if (_ready.length != widget.variants.length) return;
    _reported = true;
    final size = context.size;
    debugPrint('RShopGameWatchVariants ${jsonEncode({
          'frameRendered': true,
          'expected': widget.variants.length,
          'ready': _ready.length,
          'width': size?.width,
          'height': size?.height,
          'models': [
            for (var i = 0; i < _keys.length; i++)
              {
                'hardware': widget.variants[i].model.hardwareId,
                'geometrySha256':
                    _keys[i].currentState?.snapshot['geometrySha256'],
                'frameRendered':
                    _keys[i].currentState?.snapshot['frameRendered'],
                'error': _keys[i].currentState?.snapshot['error'],
              }
          ],
        })}');
    widget.onReady?.call();
  }

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(GameWatchVariantsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_signature(oldWidget.variants) != _signature(widget.variants)) _reset();
  }

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    final paired = widget.variants.length > 1;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < widget.variants.length; i++) ...[
        if (i != 0) const SizedBox(width: 12),
        Expanded(
            child: Semantics(
                label: widget.variants[i].label,
                child: ConsoleHardwareView(
                    key: _keys[i],
                    model: widget.variants[i].model,
                    title: widget.variants[i].label ?? '',
                    showTitle: paired,
                    turntable: false,
                    reducedMotion: widget.reducedMotion,
                    transparentBackground: true,
                    onReady: () => _rendered(i, generation)))),
      ],
    ]);
  }
}
