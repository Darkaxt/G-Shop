import 'package:flutter/widgets.dart';

/// Hosts app-wide controls above the Navigator, including their tooltips.
class AppOverlayHost extends StatelessWidget {
  final Widget child;

  const AppOverlayHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Overlay.wrap(child: child);
}
