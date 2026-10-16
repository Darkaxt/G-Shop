import 'package:flutter/material.dart';

/// Reveals the existing background where a scrollable has more content.
/// The mask remains mounted so edge changes never replace the scroll position.
class ScrollEdgeFade extends StatefulWidget {
  final Widget child;
  final Axis axis;
  final double extent;
  const ScrollEdgeFade(
      {super.key,
      required this.child,
      this.axis = Axis.vertical,
      this.extent = 48});

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  bool _before = false, _after = false;
  void _update(ScrollMetrics metrics) {
    if (metrics.axis != widget.axis) return;
    final before = metrics.extentBefore > 0;
    final after = metrics.extentAfter > 0;
    if (before == _before && after == _after) return;
    setState(() {
      _before = before;
      _after = after;
    });
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) _update(notification.metrics);
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) _update(notification.metrics);
            return false;
          },
          child: ShaderMask(
            key: const ValueKey('scroll-edge-fade'),
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) {
              final horizontal = widget.axis == Axis.horizontal;
              final size = horizontal ? bounds.width : bounds.height;
              final edge =
                  size > 0 ? (widget.extent / size).clamp(0.0, .5) : 0.0;
              return LinearGradient(
                begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
                end:
                    horizontal ? Alignment.centerRight : Alignment.bottomCenter,
                colors: [
                  _before ? Colors.transparent : Colors.white,
                  Colors.white,
                  Colors.white,
                  _after ? Colors.transparent : Colors.white
                ],
                stops: [0, edge, 1 - edge, 1],
              ).createShader(bounds);
            },
            child: widget.child,
          ),
        ),
      );
}
