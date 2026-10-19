import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/packaging_model.dart';
import '../models/socket_media_model.dart';
import 'socket_media_renderer.dart';
import 'unboxing_preview.dart' show boxPanelPath;

/// Shelf object. Its badges are painted into the front-face atlas, not
/// attached to an unrelated square overlay. The selected cinematic stays below.
class GbaBoxTile extends StatefulWidget {
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

  @override
  State<GbaBoxTile> createState() => _GbaBoxTileState();
}

class _GbaBoxTileState extends State<GbaBoxTile>
    with SingleTickerProviderStateMixin {
  late final _wobble = AnimationController(
      vsync: this, duration: const Duration(seconds: 8));

  void _updateMotion() {
    if (widget.selected &&
        !widget.reducedMotion &&
        !MediaQuery.disableAnimationsOf(context)) {
      if (!_wobble.isAnimating) _wobble.repeat();
    } else {
      _wobble.stop();
      _wobble.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void didUpdateWidget(GbaBoxTile old) {
    super.didUpdateWidget(old);
    _updateMotion();
  }

  @override
  void dispose() {
    _wobble.dispose();
    super.dispose();
  }

  Widget _face(int index) {
    final path = boxPanelPath(widget.resources, index);
    final image = path == null ? null : Uri.tryParse(path);
    Widget surface = image?.scheme == 'file'
        ? Image.file(File.fromUri(image!),
            fit: BoxFit.fill,
            errorBuilder: (_, __, ___) =>
                index == 0 ? widget.frontFallback : const SizedBox())
        : index == 0
            ? widget.frontFallback
            : const ColoredBox(color: Color(0xff34333a));
    if (index == 0)
      surface = Stack(fit: StackFit.expand, children: [
        surface,
        if (widget.score != null)
          Positioned(
              top: 12,
              right: 12,
              child: Transform.scale(
                  scale: 1.5,
                  alignment: Alignment.topRight,
                  child: widget.score)),
        if (widget.availability != null)
          Positioned(
              bottom: 12,
              right: 12,
              child: Transform.scale(
                  scale: 1.5,
                  alignment: Alignment.bottomRight,
                  child: widget.availability)),
      ]);
    return surface;
  }

  @override
  Widget build(BuildContext context) => Semantics(
      selected: widget.selected,
      label: widget.title,
      image: true,
      child: AnimatedBuilder(
          animation: _wobble,
          builder: (context, _) {
            final wave = math.sin(_wobble.value * math.pi * 2);
            return Stack(fit: StackFit.expand, children: [
              if (widget.selected)
                const IgnorePointer(
                    child: DecoratedBox(
                        key: ValueKey('gba-selection-halo'),
                        decoration: BoxDecoration(
                            gradient: RadialGradient(radius: .7, colors: [
                          Color(0x99ffad76),
                          Color(0x55ff4848),
                          Color(0x00ff4848)
                        ], stops: [
                          0,
                          .4,
                          1
                        ])))),
              SocketMediaRenderer.packaging(
                key: const ValueKey('gba-grid-box'),
                model: PackagingModel(PackagingKind.box,
                    systemId: 'gba', aspect: 1, depth: .3671875),
                pose: SocketMediaPose(
                    // Selected cartons turn through the front to reveal both sides;
                    // unselected and Reduced Motion cartons retain the shelf angle.
                    rx: .14 + wave * .018,
                    ry: _wobble.isAnimating
                        ? -math.cos(_wobble.value * math.pi * 2) * math.pi / 6
                        : -.70,
                    rz: wave * .012,
                    scaleX: widget.selected ? 1.05 : 1,
                    scaleY: widget.selected ? 1.05 : 1,
                    scaleZ: widget.selected ? 1.05 : 1),
                identity: widget.identity,
                title: widget.title,
                labelIdentity:
                    '${widget.identity}:${widget.resources}:${widget.score?.key}:${widget.availability?.key}',
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
              )
            ]);
          }));
}
