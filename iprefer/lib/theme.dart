import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

/// The one date rendering the app uses — "aug 20, 2026". Lowercase like all
/// copy. Shared so the card and the recall strip cannot drift apart.
String quietDate(DateTime date) =>
    DateFormat('MMM d, yyyy').format(date).toLowerCase();

/// The app's semantic colours, resolved per theme.
///
/// A [ThemeExtension] rather than static constants because the same names have
/// to mean different values in the dark. Widgets read them through
/// `context.colors`, so nothing has to know which theme is running.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.ink,
    required this.paper,
    required this.muted,
    required this.mutedText,
    required this.placeholder,
    required this.accentInk,
    required this.danger,
  });

  /// Primary text, and the fill of a primary button.
  final Color ink;

  /// The ground everything sits on.
  final Color paper;

  /// Short labels, dates, chip borders. Deliberately low-contrast.
  final Color muted;

  /// Body-length supporting copy, where [muted] would fail WCAG AA.
  final Color mutedText;

  /// Stands in wherever a photo should be but isn't. A tone of [paper], not
  /// grey, so broken never looks alarming.
  final Color placeholder;

  /// For the rare line that must be noticed without being alarming — a lapsed
  /// backup is something to attend to, not an error.
  final Color accentInk;

  /// The one colour allowed in from outside the palette: destructive actions.
  final Color danger;

  /// Paper and ink. `muted` measures ~3.4:1 on paper — fine for short labels,
  /// below AA for reading copy, which is what `mutedText` (~4.6:1) is for.
  static const light = AppColors(
    ink: Color(0xFF1A1A1A),
    paper: Color(0xFFFAF8F4),
    muted: Color(0xFF8A8580),
    mutedText: Color(0xFF6E6A64),
    placeholder: Color(0xFFEDEAE3),
    accentInk: Color(0xFF7A5C3E),
    danger: Color(0xFFB3261E),
  );

  /// Not an inversion — each value was re-picked against the dark ground.
  ///
  /// The ground is a warm near-black rather than pure black, so it reads as
  /// unlit paper rather than a void, and so the photos (which are the only
  /// real colour in the app) sit on something that doesn't fight them.
  /// Contrast on that ground: `mutedText` ~9:1, `muted` ~6:1 — both clear the
  /// bar their light counterparts only just meet.
  static const dark = AppColors(
    ink: Color(0xFFF2EFE8),
    paper: Color(0xFF141311),
    muted: Color(0xFF9A9389),
    mutedText: Color(0xFFBDB6AA),
    placeholder: Color(0xFF211F1B),
    accentInk: Color(0xFFC9A377),
    danger: Color(0xFFE8877E),
  );

  @override
  AppColors copyWith({
    Color? ink,
    Color? paper,
    Color? muted,
    Color? mutedText,
    Color? placeholder,
    Color? accentInk,
    Color? danger,
  }) =>
      AppColors(
        ink: ink ?? this.ink,
        paper: paper ?? this.paper,
        muted: muted ?? this.muted,
        mutedText: mutedText ?? this.mutedText,
        placeholder: placeholder ?? this.placeholder,
        accentInk: accentInk ?? this.accentInk,
        danger: danger ?? this.danger,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      ink: Color.lerp(ink, other.ink, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      placeholder: Color.lerp(placeholder, other.placeholder, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }

  // ThemeData compares its extensions with mapEquals, i.e. by ==. Without
  // these, two equal palettes are equal only when they happen to be the same
  // canonicalised const — which stops being true the moment one is built by
  // copyWith or lerp.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppColors &&
          other.ink == ink &&
          other.paper == paper &&
          other.muted == muted &&
          other.mutedText == mutedText &&
          other.placeholder == placeholder &&
          other.accentInk == accentInk &&
          other.danger == danger;

  @override
  int get hashCode =>
      Object.hash(ink, paper, muted, mutedText, placeholder, accentInk, danger);
}

extension AppColorsOf on BuildContext {
  /// The palette for whichever theme is running.
  ///
  /// A context above the app's own [MaterialApp] has no palette to read. That
  /// would render light chrome on a dark phone, so it asserts in debug rather
  /// than degrading quietly; release keeps the fallback, because a wrong
  /// colour is still better than a crash.
  AppColors get colors {
    final found = Theme.of(this).extension<AppColors>();
    assert(
      found != null,
      'no AppColors in scope — this context is above the MaterialApp that '
      'supplies the theme. Read the palette below it (a Builder is enough).',
    );
    return found ?? AppColors.light;
  }
}

/// Quiet, paper-and-ink chrome. All the colour lives in the photo.
class AppTheme {
  static const String serif = 'PlayfairDisplay';

  // Built once. ThemeData is immutable, and the navigation-bar theme below
  // creates fresh resolver closures on every call — which never compare equal,
  // so a rebuilt theme made MaterialApp's AnimatedTheme restart a 200 ms
  // crossfade on every root rebuild, between two identical palettes.
  static final ThemeData _light = _build(AppColors.light, Brightness.light);
  static final ThemeData _dark = _build(AppColors.dark, Brightness.dark);

  static ThemeData light() => _light;
  static ThemeData dark() => _dark;

  static ThemeData _build(AppColors c, Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6B5B4A),
        brightness: brightness,
        surface: c.paper,
      ),
      scaffoldBackgroundColor: c.paper,
    );

    return base.copyWith(
      extensions: [c],
      textTheme: base.textTheme.copyWith(
        displaySmall: TextStyle(
          fontFamily: serif,
          fontStyle: FontStyle.italic,
          fontSize: 30,
          color: c.ink,
        ),
        headlineSmall: TextStyle(
          fontFamily: serif,
          fontSize: 22,
          color: c.ink,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: c.ink, height: 1.4),
        bodyMedium:
            TextStyle(fontSize: 14, color: c.ink.withValues(alpha: 0.8)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.paper,
        foregroundColor: c.ink,
        elevation: 0,
        // elevation: 0 is not enough. M3 re-elevates the bar to 3.0 the moment
        // content scrolls under it and tints it with colorScheme.surfaceTint —
        // a warm brown this palette never chose. The timeline and compose both
        // scroll, so without these two the bar becomes a coloured band over a
        // neutral page on every scroll.
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Inverted in the dark, as it should be: a light button on a dark
          // ground is the same gesture as a dark one on paper.
          backgroundColor: c.ink,
          foregroundColor: c.paper,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      // The FAB is the filled button in its other posture — same gesture, so
      // the same fill and the same corner, described here rather than at the
      // one call site that raises one. Unthemed it takes
      // colorScheme.primaryContainer, which is the seed's warm brown: the FAB
      // sits over the timeline, so that lands next to every photo in the app.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.ink,
        foregroundColor: c.paper,
        // 8dp like every real button; the default stadium pill reads as a
        // chip, and pills mean "selectable filter" everywhere else here.
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      // Everything below exists for one reason: ColorScheme.fromSeed derives
      // warm browns from the seed, and any surface left unthemed quietly picks
      // them up — an accent this palette never chose. Ink and muted only.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          side: BorderSide(color: c.ink.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.ink),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: c.ink.withValues(alpha: 0.08),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? c.ink : c.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            color: states.contains(WidgetState.selected) ? c.ink : c.muted,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.muted.withValues(alpha: 0.35)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.muted.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.ink, width: 1.4),
        ),
        hintStyle: TextStyle(color: c.muted),
      ),
      // The caret and the selection are surfaces too, and unthemed they come
      // out of the seed as a warm brown — the one accent this palette does not
      // have. Visible in any text field: compose, and the search bar.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.ink,
        selectionColor: c.ink.withValues(alpha: 0.18),
        selectionHandleColor: c.ink,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        textStyle: TextStyle(fontSize: 15, color: c.ink),
        // The border is what separates the menu from the page in the dark:
        // its fill is `paper`, the page is `paper`, and a black elevation
        // shadow on a near-black ground is invisible. Killing the seed's tint
        // removed the only edge M3 was giving it.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.muted.withValues(alpha: 0.3)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.paper,
        surfaceTintColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.ink,
        textColor: c.ink,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.ink,
        contentTextStyle: TextStyle(color: c.paper, fontSize: 14),
      ),
    );
  }
}
