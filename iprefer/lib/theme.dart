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

  /// [muted] measures ~3.4:1 on [paper] — fine for short labels and dates,
  /// below WCAG AA for body-length reading copy. This darker cut (~4.6:1) is
  /// for multi-line supporting text: the login subhead, empty-state bodies.
  static const Color mutedText = Color(0xFF6E6A64);

  /// For the rare line that must be noticed without being alarming — a lapsed
  /// backup is not an error, it is something to attend to. Darker and warmer
  /// than [muted], well short of [danger].
  static const Color accentInk = Color(0xFF7A5C3E);

  /// The one color allowed in from outside the palette: destructive actions.
  /// Named and chosen — never ColorScheme.error, which is derived from the
  /// seed and would be an accidental tone like the chrome leaks this theme
  /// exists to prevent.
  static const Color danger = Color(0xFFB3261E);

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
      // Everything below exists for one reason: ColorScheme.fromSeed derives
      // warm browns from the seed, and any surface left unthemed quietly picks
      // them up — an accent this palette never chose. Ink and muted only.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: ink.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: ink),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: ink.withValues(alpha: 0.08),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? ink : muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            color: states.contains(WidgetState.selected) ? ink : muted,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: muted.withValues(alpha: 0.35)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: muted.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: ink, width: 1.4),
        ),
        hintStyle: const TextStyle(color: muted),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: TextStyle(color: paper, fontSize: 14),
      ),
    );
  }
}
