import 'package:flutter/material.dart';

/// Quiet, paper-and-ink palette. The app chrome stays out of the way; all the
/// color lives in the photo.
class AppTheme {
  static const String serif = 'PlayfairDisplay';

  static const Color ink = Color(0xFF1A1A1A);
  static const Color paper = Color(0xFFFAF8F4);
  static const Color muted = Color(0xFF8A8580);

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6B5B4A),
        brightness: Brightness.light,
        surface: paper,
      ),
      scaffoldBackgroundColor: paper,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displaySmall: const TextStyle(
          fontFamily: serif,
          fontStyle: FontStyle.italic,
          fontSize: 30,
          color: ink,
        ),
        headlineSmall: const TextStyle(
          fontFamily: serif,
          fontSize: 22,
          color: ink,
        ),
        bodyLarge: const TextStyle(fontSize: 16, color: ink, height: 1.4),
        bodyMedium: TextStyle(fontSize: 14, color: ink.withValues(alpha: 0.8)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: paper,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
    );
  }
}
