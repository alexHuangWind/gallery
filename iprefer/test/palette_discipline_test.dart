import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Colours live in `theme.dart` and are read through `context.colors`. A raw
/// colour anywhere else is a colour that cannot follow the appearance — which
/// is exactly how a screen ends up unreadable in the dark.
///
/// Two files are allowed to hold raw colours, both for the same reason: what
/// they paint on is not the app's ground.
const _overImagery = {
  // Every colour here sits on the photo itself. The card is also the export
  // artifact — a shared PNG must look the same whatever the sender's phone
  // was set to. The same argument covers the card's type: it renders under
  // MediaQuery.withNoTextScaling, so the sender's accessibility setting can't
  // reach the lockup either. See test/preference_card_test.dart.
  'lib/widgets/preference_card.dart',
  // Pin borders, the location dot, and the OSM attribution sit on map tiles,
  // which are always the light raster set.
  'lib/screens/map_screen.dart',
};

/// Where the palette is defined.
const _paletteHome = 'lib/theme.dart';

/// A literal ARGB, or any named Material colour. `Colors.transparent` is the
/// one exemption — it is theme-neutral by definition.
final _rawColour = RegExp(r'Color\(0x|Colors\.(?!transparent\b)[a-z]');

void main() {
  test('raw colours only appear over imagery', () {
    final offenders = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final path = file.path;
      if (path == _paletteHome || _overImagery.contains(path)) continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // Comments explain the rule; they don't break it.
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (_rawColour.hasMatch(lines[i])) {
          offenders.add('$path:${i + 1}  ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these colours cannot follow the appearance — move them into '
          'AppColors and read them via context.colors:\n${offenders.join('\n')}',
    );
  });

  test('the allowlist still names real files', () {
    // So a rename turns into a failing test rather than a silently dead
    // exemption that lets raw colours back in.
    for (final path in {..._overImagery, _paletteHome}) {
      expect(File(path).existsSync(), isTrue, reason: '$path is gone');
    }
  });
}
