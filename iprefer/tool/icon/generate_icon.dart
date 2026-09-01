/// Renders the app icon from the app's own typeface, then writes every size
/// iOS and Android need.
///
///   flutter test tool/icon/generate_icon.dart
///
/// Why a test file: rendering real type needs a Flutter engine and the actual
/// Playfair Display file, and `flutter test` is the only harness here that has
/// both. AI image generation was the alternative and is the wrong tool — the
/// mark IS a letterform, and a generator that approximates letterforms would
/// hand back something that merely resembles the typeface the rest of the app
/// is set in.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tuned against the measured ink box printed by this test, not by eye.
const _glyphScale = 0.82;
const _dx = -0.0127;
const _dy = 0.0347;

/// Paper ground rather than ink: the app is paper, and a light tile is also
/// the one that stands out on a home screen full of dark ones.
const _paper = Color(0xFFFAF8F4);
const _ink = Color(0xFF1A1A1A);

/// The mark is the first letter of the card's signature lockup, in the same
/// italic serif. Not a picture of the app — the app's own handwriting.
class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.side});

  final double side;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: side,
      height: side,
      color: _paper,
      child: Center(
        // Nudged off true centre: an italic glyph's optical centre sits left
        // and low of its bounding box, and centring the box makes it look
        // like it is sliding off the tile.
        child: Transform.translate(
          offset: Offset(side * _dx, side * _dy),
          child: Text(
            'I',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
              fontSize: side * _glyphScale,
              height: 1.0,
              color: _ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// iOS asset catalog slots, from the existing AppIcon.appiconset.
const _iosSizes = <String, int>{
  'Icon-App-20x20@1x.png': 20,
  'Icon-App-20x20@2x.png': 40,
  'Icon-App-20x20@3x.png': 60,
  'Icon-App-29x29@1x.png': 29,
  'Icon-App-29x29@2x.png': 58,
  'Icon-App-29x29@3x.png': 87,
  'Icon-App-40x40@1x.png': 40,
  'Icon-App-40x40@2x.png': 80,
  'Icon-App-40x40@3x.png': 120,
  'Icon-App-60x60@2x.png': 120,
  'Icon-App-60x60@3x.png': 180,
  'Icon-App-76x76@1x.png': 76,
  'Icon-App-76x76@2x.png': 152,
  'Icon-App-83.5x83.5@2x.png': 167,
  'Icon-App-1024x1024@1x.png': 1024,
};

/// Android launcher densities.
const _androidSizes = <String, int>{
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

void main() {
  testWidgets('generate the app icon at every required size', (tester) async {
    // The real typeface, not the test harness's placeholder font.
    //
    // Read synchronously on purpose: testWidgets runs in a fake-async zone,
    // and awaiting File.readAsBytes() there never completes. Future.value
    // resolves as a microtask, which fake time does drain.
    final fontBytes = File('assets/fonts/PlayfairDisplay-Italic-Variable.ttf')
        .readAsBytesSync();
    final loader = FontLoader('PlayfairDisplay')
      ..addFont(Future.value(ByteData.view(fontBytes.buffer)));
    await loader.load();

    const side = 1024.0;
    tester.view.physicalSize = const Size(side, side);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: _AppIcon(side: side),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

    Future<void> write(String path, int px) async {
      final image = await boundary.toImage(pixelRatio: px / side);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(path)..parent.createSync(recursive: true);
        file.writeAsBytesSync(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    }

    await tester.runAsync(() async {
      // A full-size master to look at before anything is wired up.
      await write('tool/icon/app_icon.png', 1024);

      const iosDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      for (final entry in _iosSizes.entries) {
        await write('$iosDir/${entry.key}', entry.value);
      }

      for (final entry in _androidSizes.entries) {
        await write(
          'android/app/src/main/res/${entry.key}/ic_launcher.png',
          entry.value,
        );
      }
    });

    // Measure where the ink actually landed rather than eyeballing it: an
    // italic glyph's bounding box is not its optical centre, and "looks
    // roughly centred" is how an icon ends up visibly sliding off its tile.
    final master = await tester.runAsync(() async {
      final bytes = File('tool/icon/app_icon.png').readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    });
    final px = master!.buffer.asUint8List();
    var minX = 1 << 30, maxX = -1, minY = 1 << 30, maxY = -1;
    for (var y = 0; y < 1024; y++) {
      for (var x = 0; x < 1024; x++) {
        // Any pixel meaningfully darker than paper counts as ink.
        if (px[(y * 1024 + x) * 4] < 128) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    // ignore: avoid_print
    print('ink box x[$minX..$maxX] y[$minY..$maxY] '
        'centre(${(minX + maxX) / 2}, ${(minY + maxY) / 2}) target 512');

    expect(File('tool/icon/app_icon.png').existsSync(), isTrue);
    // ignore: avoid_print
    print('wrote ${_iosSizes.length} iOS and ${_androidSizes.length} Android icons');
  });
}
