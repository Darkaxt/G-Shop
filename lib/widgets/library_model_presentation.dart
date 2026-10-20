import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/socket_media_model.dart';

/// Selection presentation shared by every 3D library object, not its viewer.
class LibraryModelPresentation extends StatefulWidget {
  final bool selected, reducedMotion;
  final double restYaw;
  final Widget Function(BuildContext, SocketMediaPose) builder;
  const LibraryModelPresentation(
      {super.key,
      required this.selected,
      required this.reducedMotion,
      required this.builder,
      this.restYaw = -.70});

  @override
  State<LibraryModelPresentation> createState() =>
      _LibraryModelPresentationState();
}

class _LibraryModelPresentationState extends State<LibraryModelPresentation>
    with SingleTickerProviderStateMixin {
  late final _motion =
      AnimationController(vsync: this, duration: const Duration(seconds: 8));

  void _updateMotion() {
    if (widget.selected &&
        !widget.reducedMotion &&
        !MediaQuery.disableAnimationsOf(context)) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
      _motion.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void didUpdateWidget(LibraryModelPresentation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateMotion();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _motion,
      builder: (context, _) => Stack(fit: StackFit.expand, children: [
            if (widget.selected)
              const IgnorePointer(
                  child: DecoratedBox(
                      key: ValueKey('library-model-selection-halo'),
                      decoration: BoxDecoration(
                          // Finish the fade inside the shorter tile dimension.
                          gradient: RadialGradient(radius: .48, colors: [
                        Color(0x99ffad76),
                        Color(0x55ff4848),
                        Color(0x00ff4848)
                      ], stops: [
                        0,
                        .4,
                        1
                      ])))),
            widget.builder(
                context,
                SocketMediaPose(
                    ry: _motion.isAnimating
                        ? -math.cos(_motion.value * math.pi * 2) * math.pi / 6
                        : widget.restYaw,
                    scaleX: widget.selected ? 1.05 : 1,
                    scaleY: widget.selected ? 1.05 : 1,
                    scaleZ: widget.selected ? 1.05 : 1))
          ]));

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }
}
