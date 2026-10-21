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
  static const names = {
    'front-loader': 'NES · front loader',
    'top-loader': 'NES-101 · top loader',
    'famicom': 'Famicom HVC-001',
    'dendy': 'Dendy-compatible clone'
  };
  String _selected = 'collection';
  late final _variants = Future.wait([
    for (final id in names.keys) ConsoleModel.findNesConsoleVariant(id),
  ]);
  @override
  Widget build(BuildContext context) => FutureBuilder<List<ConsoleModel?>>(
      future: _variants,
      builder: (context, snapshot) {
        final variants = snapshot.data;
        final ConsoleModel? model;
        if (names.containsKey(_selected)) {
          model = variants == null
              ? null
              : variants[names.keys.toList().indexOf(_selected)];
        } else {
          model = widget.collection;
        }
        return Stack(fit: StackFit.expand, children: [
          if (model != null)
            ConsoleHardwareView(
                key: widget.hardwareKey,
                model: model,
                title: names[_selected] ?? 'Nintendo Entertainment System',
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
                        for (var i = 0; i < names.length; i++)
                          PopupMenuItem(
                              value: names.keys.elementAt(i),
                              enabled: variants != null && variants[i] != null,
                              child: Text(names.values.elementAt(i))),
                      ],
                  icon: const Icon(Icons.layers_outlined))),
        ]);
      });
}
