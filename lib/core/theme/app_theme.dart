import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Colors
  static const Color primaryColor = Colors.redAccent;
  // Primary filled actions need a darker red for readable white labels.
  // Keep the brighter accent for glows, indicators and other existing UI.
  static final ButtonStyle primaryButtonStyle = FilledButton.styleFrom(
    backgroundColor: const Color(0xFFC62828),
    foregroundColor: Colors.white,
  );
  static const Color backgroundColor = Color(0xFF140609);
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF54131E),
      Color(0xFF2D0B13),
      Color(0xFF1C080E),
      backgroundColor,
    ],
    stops: [0.0, 0.3, 0.65, 1.0],
  );
  static const Color surfaceColor = Color(0xFF121212);
  static const Color cardColor = Color(0xFF1E1E1E);

  static const Color focusColor = Colors.white;
  static const Color focusGlowColor = primaryColor;

  static final Color focusOverlayColor = Colors.white.withValues(alpha: 0.1);
  static final Color hoverOverlayColor = Colors.white.withValues(alpha: 0.05);

  // Spacing
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;

  // Radius
  static const double radiusSm = 4.0;
  static const double radiusMd = 8.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;

  // Text Styles
  static TextStyle get headlineLarge => GoogleFonts.outfit(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        letterSpacing: 1.5,
      );

  static TextStyle get headlineMedium => GoogleFonts.outfit(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        letterSpacing: 1.2,
      );

  static TextStyle get titleLarge => GoogleFonts.outfit(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      );

  static TextStyle get titleMedium => GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        letterSpacing: 0.5,
      );

  static TextStyle get bodyLarge => GoogleFonts.inter(
        fontSize: 16,
        color: Colors.grey[200],
      );

  static TextStyle get bodyMedium => GoogleFonts.inter(
        fontSize: 14,
        color: Colors.grey[400],
      );

  static TextStyle get bodySmall => GoogleFonts.inter(
        fontSize: 12,
        color: Colors.grey[500],
      );

  static TextStyle get labelLarge => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        letterSpacing: 1.0,
      );

  // Theme Data
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        surface: surfaceColor,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      focusColor: focusOverlayColor,
      hoverColor: hoverOverlayColor,
      highlightColor: focusOverlayColor,
      splashColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      textTheme: TextTheme(
        headlineLarge: headlineLarge,
        headlineMedium: headlineMedium,
        titleLarge: titleLarge,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        labelLarge: labelLarge,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
