import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iprefer/theme.dart';

/// WCAG relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('palette', () {
    test('body copy clears AA on both grounds', () {
      // 4.5:1 is the AA bar for normal-size text. `mutedText` exists precisely
      // so reading copy never falls back on `muted`, which does not clear it.
      expect(_contrast(AppColors.light.mutedText, AppColors.light.paper),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.dark.mutedText, AppColors.dark.paper),
          greaterThanOrEqualTo(4.5));
    });

    test('primary text is comfortably above AA on both grounds', () {
      expect(_contrast(AppColors.light.ink, AppColors.light.paper),
          greaterThanOrEqualTo(7));
      expect(_contrast(AppColors.dark.ink, AppColors.dark.paper),
          greaterThanOrEqualTo(7));
    });

    test('short labels clear the 3:1 bar their size allows', () {
      expect(_contrast(AppColors.light.muted, AppColors.light.paper),
          greaterThanOrEqualTo(3));
      expect(_contrast(AppColors.dark.muted, AppColors.dark.paper),
          greaterThanOrEqualTo(3));
    });

    test('a filled button reads against its own fill', () {
      // The primary button paints paper on ink, so the pair has to work in
      // reverse too.
      expect(_contrast(AppColors.light.paper, AppColors.light.ink),
          greaterThanOrEqualTo(7));
      expect(_contrast(AppColors.dark.paper, AppColors.dark.ink),
          greaterThanOrEqualTo(7));
    });

    test('the placeholder stays a tone of paper, never a grey slab', () {
      // Broken photos must not look alarming: the stand-in should be within a
      // hair of the ground it sits on.
      expect(_contrast(AppColors.light.placeholder, AppColors.light.paper),
          lessThan(1.5));
      expect(_contrast(AppColors.dark.placeholder, AppColors.dark.paper),
          lessThan(1.5));
    });
  });

  group('theme wiring', () {
    testWidgets('context.colors follows the running brightness',
        (tester) async {
      late AppColors seen;

      Future<void> pump(ThemeMode mode) async {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(mode),
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            home: Builder(builder: (context) {
              seen = context.colors;
              return const SizedBox.shrink();
            }),
          ),
        );
      }

      await pump(ThemeMode.light);
      expect(seen.paper, AppColors.light.paper);
      expect(seen.ink, AppColors.light.ink);

      // The app itself never passes themeMode, so it stays on
      // ThemeMode.system — this is the branch that reaches.
      await pump(ThemeMode.dark);
      expect(seen.paper, AppColors.dark.paper);
      expect(seen.ink, AppColors.dark.ink);
    });

    testWidgets('the scaffold ground matches the palette', (tester) async {
      for (final (theme, colors) in [
        (AppTheme.light(), AppColors.light),
        (AppTheme.dark(), AppColors.dark),
      ]) {
        expect(theme.scaffoldBackgroundColor, colors.paper);
        expect(theme.appBarTheme.backgroundColor, colors.paper);
      }
    });

    test('lerp reaches the other end, and lands equal', () {
      // Equal by value, not just by paper: ThemeData compares extensions with
      // ==, so a lerped palette that isn't == its destination makes the theme
      // compare unequal to itself.
      expect(AppColors.light.lerp(AppColors.dark, 1), AppColors.dark);
      expect(AppColors.light.lerp(AppColors.dark, 0), AppColors.light);
      expect(AppColors.dark.copyWith(), AppColors.dark);
      expect(AppColors.dark.copyWith(ink: AppColors.light.ink),
          isNot(AppColors.dark));
    });

    test('a theme is equal to itself across calls', () {
      // Otherwise AnimatedTheme restarts a 200 ms crossfade on every root
      // rebuild, and context.colors hands back freshly-lerped palettes for the
      // duration — between two sets of identical values.
      expect(AppTheme.dark(), same(AppTheme.dark()));
      expect(AppTheme.light(), same(AppTheme.light()));
      expect(AppTheme.light(), isNot(AppTheme.dark()));
    });

    test('the app bar never tints itself', () {
      // elevation: 0 does not stop M3 re-elevating the bar to 3.0 when content
      // scrolls under it and washing it with colorScheme.surfaceTint — a warm
      // brown this palette never chose, on the one surface always on screen.
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        expect(theme.appBarTheme.scrolledUnderElevation, 0);
        expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
      }
    });

    test('a busy button keeps a fill its spinner can be seen on', () {
      // The buttons that show progress stay enabled while they work, because a
      // disabled M3 button drops the theme's ink fill for onSurface@0.12 —
      // which would put the paper spinner at ~1.3:1 on its own button. This is
      // the margin that choice buys, in both themes.
      for (final colors in [AppColors.light, AppColors.dark]) {
        expect(_contrast(colors.paper, colors.ink), greaterThanOrEqualTo(7));
      }

      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final disabled = Color.alphaBlend(
          theme.colorScheme.onSurface.withValues(alpha: 0.12),
          theme.colorScheme.surface,
        );
        final spinnerOnDisabled = _contrast(
          theme.extension<AppColors>()!.paper,
          disabled,
        );
        expect(spinnerOnDisabled, lessThan(2),
            reason: 'if this ever clears 3:1 the workaround can be dropped');
      }
    });

    testWidgets('reading the palette above the theme is caught in debug',
        (tester) async {
      // The exact bug dark mode can hide: a widget built above the MaterialApp
      // renders light chrome on a dark phone and nothing complains. Debug
      // asserts so it surfaces in development; release still falls back rather
      // than crashing someone's archive open.
      await tester.pumpWidget(
        Theme(
          data: ThemeData(), // no AppColors registered
          child: Builder(builder: (context) {
            context.colors;
            return const SizedBox.shrink();
          }),
        ),
      );
      expect(tester.takeException(), isAssertionError);
    });
  });
}
