import 'package:flutter/material.dart';

/// A 3D camera reserves its own edge areas. Keep text over those areas instead
/// of subtracting a header/footer and reserving the same space a second time.
class ScenePreviewLayout extends StatelessWidget {
  final bool composition;
  final Widget content;
  final Widget? header, footer;
  const ScenePreviewLayout(
      {super.key,
      required this.composition,
      required this.content,
      this.header,
      this.footer});

  @override
  Widget build(BuildContext context) => composition
      ? LayoutBuilder(
          builder: (context, bounds) => Stack(fit: StackFit.expand, children: [
                content,
                if (header != null)
                  Positioned(
                      left: 72,
                      right: 72,
                      top: 4,
                      height: bounds.maxHeight * .125 - 4,
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                              width: bounds.maxWidth - 144, child: header))),
                if (footer != null)
                  Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: footer)),
              ]))
      : Column(children: [
          if (header != null) header!,
          Expanded(child: content),
          if (footer != null) footer!,
        ]);
}
