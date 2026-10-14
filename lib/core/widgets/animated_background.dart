import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AnimatedBackground extends StatelessWidget {
  final Color? accentColor;

  const AnimatedBackground({
    super.key,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      decoration: const BoxDecoration(
        gradient: AppTheme.backgroundGradient,
      ),
    );
  }
}
