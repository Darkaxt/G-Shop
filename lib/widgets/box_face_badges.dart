import 'package:flutter/material.dart';

/// Contents of a front-face texture, never an overlay on the surrounding card.
class BoxFaceBadges extends StatelessWidget {
  final Widget? child, score, availability;
  const BoxFaceBadges({super.key, this.child, this.score, this.availability});

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        if (child != null) child!,
        if (score != null)
          Positioned(
              top: 12,
              right: 12,
              child: Transform.scale(
                  scale: 1.5, alignment: Alignment.topRight, child: score)),
        if (availability != null)
          Positioned(
              bottom: 12,
              right: 12,
              child: Transform.scale(
                  scale: 1.5,
                  alignment: Alignment.bottomRight,
                  child: availability)),
      ]);
}
