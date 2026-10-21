import 'package:flutter/material.dart';
import '../../models/console_model.dart';
import 'console_hardware_view.dart';

class NesConsoleSelector extends StatefulWidget {
  final ConsoleModel collection;
  final GlobalKey<ConsoleHardwareViewState> hardwareKey;
  final bool reducedMotion;
  final VoidCallback onReady;
  const NesConsoleSelector(
      {super.key,
      required this.collection,
      required this.hardwareKey,
      required this.reducedMotion,
      required this.onReady});
  @override
  State<NesConsoleSelector> createState() => _NesConsoleSelectorState();
}

class _NesConsoleSelectorState extends State<NesConsoleSelector> {
  String _selected = 'collection';
  late final _variants = Future.wait([
    ConsoleModel.findNesConsoleVariant('front-loader'),
    ConsoleModel.findNesConsoleVariant('top-loader'),
  ]);
  @override
  Widget build(BuildContext context) => FutureBuilder<List<ConsoleModel?>>(
      future: _variants,
      builder: (context, snapshot) {
        final variants = snapshot.data;
        final ConsoleModel? model;
        if (_selected == 'front-loader') {
          model = variants == null ? null : variants[0];
        } else if (_selected == 'top-loader') {
          model = variants == null ? null : variants[1];
        } else {
          model = widget.collection;
        }
        return Stack(fit: StackFit.expand, children: [
          if (model != null)
            ConsoleHardwareView(
                key: widget.hardwareKey,
                model: model,
                title: _selected == 'collection'
                    ? 'Nintendo Entertainment System'
                    : _selected == 'front-loader'
                        ? 'NES · front loader'
                        : 'NES-101 · top loader',
                reducedMotion: widget.reducedMotion,
                onReady: widget.onReady),
          Positioned(
              top: 12,
              right: 12,
              child: PopupMenuButton<String>(
                  tooltip: 'Console hardware',
                  initialValue: _selected,
                  onSelected: (value) => setState(() => _selected = value),
                  itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'collection',
                            child: Text('Collector scene')),
                        PopupMenuItem(
                            value: 'front-loader',
                            enabled: variants?[0] != null,
                            child: const Text('NES · front loader')),
                        PopupMenuItem(
                            value: 'top-loader',
                            enabled: variants?[1] != null,
                            child: const Text('NES-101 · top loader')),
                      ],
                  icon: const Icon(Icons.layers_outlined))),
        ]);
      });
}
