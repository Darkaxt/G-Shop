import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class DynamicBackground extends StatelessWidget {
  final Color accentColor;

  const DynamicBackground({super.key, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppTheme.backgroundGradient,
      ),
    );
  }
}
