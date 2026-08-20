import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

/// The one date rendering the app uses — "aug 20, 2026". Lowercase like all
/// copy. Shared so the card and the recall strip cannot drift apart.
String quietDate(DateTime date) =>
    DateFormat('MMM d, yyyy').format(date).toLowerCase();

/// Quiet, paper-and-ink palette. The app chrome stays out of the way; all the
/// color lives in the photo.
class AppTheme {
  static const String serif = 'PlayfairDisplay';

  static const Color ink = Color(0xFF1A1A1A);
  static const Color paper = Color(0xFFFAF8F4);
  static const Color muted = Color(0xFF8A8580);

  /// Stands in wherever a photo should be but isn't — empty compose slot,
  /// failed decode. A tone of [paper], not grey, so broken never looks alarming.
  static const Color placeholder = Color(0xFFEDEAE3);

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
