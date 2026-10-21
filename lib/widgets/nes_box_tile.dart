import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/console_model.dart';
import '../models/nes_media_catalogue.dart';
import 'library_model_presentation.dart';
import 'socket_media_renderer.dart';

/// One closed, explicitly bound reference edition per library card.
class NesBoxTile extends StatefulWidget {
  final String filename, identity, title;
  final bool selected, reducedMotion;
  final Widget fallback;
  const NesBoxTile(
      {super.key,
      required this.filename,
      required this.identity,
      required this.title,
      required this.selected,
      required this.reducedMotion,
      required this.fallback});
  @override
  State<NesBoxTile> createState() => _NesBoxTileState();
}

class _NesBoxTileState extends State<NesBoxTile> {
  Future<ConsoleModel?> _find() async {
    final catalogue = await NesMediaCatalogue.load();
    final editions = catalogue?.forArchive(widget.filename);
    return editions == null || editions.isEmpty ? null : editions.first.load();
  }

  late Future<ConsoleModel?> _model = _find();
  @override
  void didUpdateWidget(NesBoxTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filename != widget.filename ||
        oldWidget.identity != widget.identity) {
      _model = _find();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ConsoleModel?>(
      future: _model,
      builder: (context, snapshot) {
        final model = snapshot.data;
        if (model == null) return widget.fallback;
        return LibraryModelPresentation(
            selected: widget.selected,
            reducedMotion: widget.reducedMotion,
            builder: (_, pose) => SocketMediaRenderer.console(
                key: ValueKey(model.generation),
                model: model,
                pose: pose,
                identity: '${widget.identity}:${model.generation}',
                title: widget.title,
                onReady: () => debugPrint('GShopNesBoxReady ${jsonEncode({
                          'edition': model.retailEditionId,
                          'generation': model.generation,
                          'frameRendered': true,
                          'closed': true
                        })}')));
      });
}
