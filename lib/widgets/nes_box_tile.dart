import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/console_model.dart';
import '../models/nes_media_catalogue.dart';
import 'library_model_presentation.dart';
import 'socket_media_renderer.dart';
import 'box_face_badges.dart';

/// One closed, explicitly bound reference edition per library card.
class NesBoxTile extends StatefulWidget {
  final String filename, identity, title;
  final bool selected, reducedMotion;
  final Widget fallback;
  final Widget? score, availability;
  const NesBoxTile(
      {super.key,
      required this.filename,
      required this.identity,
      required this.title,
      required this.selected,
      required this.reducedMotion,
      this.score,
      this.availability,
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
        if (model == null) {
          return BoxFaceBadges(
              score: widget.score,
              availability: widget.availability,
              child: widget.fallback);
        }
        return LibraryModelPresentation(
            selected: widget.selected,
            reducedMotion: widget.reducedMotion,
            builder: (_, pose) => SocketMediaRenderer.console(
                key: ValueKey(model.generation),
                model: model,
                // Imported carton bounds include its open flaps. Frame the
                // actual closed pose so that envelope does not shrink the card.
                frameComposition: true,
                compositionFill: widget.selected ? .8925 : .85,
                pose: pose,
                identity: '${widget.identity}:${model.generation}',
                title: widget.title,
                boxFaceBadges: true,
                labelIdentity:
                    '${widget.identity}:${widget.score?.key}:${widget.availability?.key}',
                label: BoxFaceBadges(
                    score: widget.score, availability: widget.availability),
                onReady: () => debugPrint('GShopNesBoxReady ${jsonEncode({
                          'edition': model.retailEditionId,
                          'generation': model.generation,
                          'frameRendered': true,
                          'closed': true
                        })}')));
      });
}
