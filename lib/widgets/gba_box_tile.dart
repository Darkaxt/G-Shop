import 'dart:io';
import 'package:flutter/material.dart';
import '../models/packaging_model.dart';
import 'library_model_presentation.dart';
import 'socket_media_renderer.dart';
import 'unboxing_preview.dart' show boxPanelPath;
import 'box_face_badges.dart';

/// Shelf object. Its badges are painted into the front-face atlas, not
/// attached to an unrelated square overlay. The selected cinematic stays below.
class GbaBoxTile extends StatelessWidget {
  final String identity, title;
  final Map<String, List<String>> resources;
  final Widget frontFallback;
  final Widget? score, availability;
  final bool selected, reducedMotion;
  const GbaBoxTile(
      {super.key,
      required this.identity,
      required this.title,
      required this.resources,
      required this.frontFallback,
      this.score,
      this.availability,
      this.selected = false,
      this.reducedMotion = false});

  Widget _face(int index) {
    final path = boxPanelPath(resources, index);
    final image = path == null ? null : Uri.tryParse(path);
    Widget surface = image?.scheme == 'file'
        ? Image.file(File.fromUri(image!),
            fit: BoxFit.fill,
            errorBuilder: (_, __, ___) =>
                index == 0 ? frontFallback : const SizedBox())
        : index == 0
            ? frontFallback
            : const ColoredBox(color: Color(0xff34333a));
    if (index == 0) {
      surface = BoxFaceBadges(
          score: score, availability: availability, child: surface);
    }
    return surface;
  }

  @override
  Widget build(BuildContext context) => Semantics(
      selected: selected,
      label: title,
      image: true,
      child: LibraryModelPresentation(
          selected: selected,
          reducedMotion: reducedMotion,
          builder: (context, pose) => SocketMediaRenderer.packaging(
                key: const ValueKey('gba-grid-box'),
                model: PackagingModel(PackagingKind.box,
                    systemId: 'gba', aspect: 1, depth: .3671875),
                pose: pose,
                identity: identity,
                title: title,
                labelIdentity:
                    '$identity:$resources:${score?.key}:${availability?.key}',
                label: Column(children: [
                  for (var row = 0; row < 2; row++)
                    Expanded(
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          for (var col = 0; col < 3; col++)
                            Expanded(child: _face(row * 3 + col))
                        ]))
                ]),
              )));
}
