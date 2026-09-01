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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
  const _AppIcon({
    required this.side,
    this.transparent = false,
    this.scale = 1.0,
  });

  final double side;

  /// Adaptive-icon foregrounds sit over a background layer of their own.
  final bool transparent;

  /// Shrinks the mark within the tile, for the adaptive safe zone.
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: side,
      height: side,
      color: transparent ? const Color(0x00000000) : _paper,
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
              fontSize: side * _glyphScale * scale,
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

/// Android launcher densities (the legacy square icon, for API 24-25).
const _androidSizes = <String, int>{
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

/// Adaptive-icon foreground sizes: 108dp at each density.
///
/// From API 26 the launcher reads mipmap-anydpi-v26/ic_launcher.xml, which
/// outranks every density folder — so the legacy PNGs above are invisible on
/// effectively every real device, and shipping only those left the app with
/// two contradictory icons split by OS version.
const _androidForeground = <String, int>{
  'mipmap-mdpi': 108,
  'mipmap-hdpi': 162,
  'mipmap-xhdpi': 216,
  'mipmap-xxhdpi': 324,
  'mipmap-xxxhdpi': 432,
};

/// The adaptive foreground is 108dp but only the middle 72dp is guaranteed
/// visible — the launcher masks and parallaxes the rest. The glyph is scaled
/// to sit inside that safe zone rather than being cropped by a round mask.
const _safeZone = 72 / 108;

/// Encodes RGBA pixels as a colour-type-2 (RGB, no alpha) PNG.
///
/// Hand-rolled because the alternative is a new dependency for what is, at
/// this size, four chunks and a zlib stream — and because the one property
/// that matters (no alpha channel) has to be guaranteed, not hoped for.
Uint8List _opaquePng(Uint8List rgba, int width, int height) {
  // Each scanline is prefixed with filter type 0 (None).
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      raw..addByte(rgba[i])..addByte(rgba[i + 1])..addByte(rgba[i + 2]);
    }
  }

  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  void chunk(String type, List<int> body) {
    final data = Uint8List(body.length + 4)
      ..setAll(0, ascii.encode(type))
      ..setAll(4, body);
    out
      ..add((ByteData(4)..setUint32(0, body.length)).buffer.asUint8List())
      ..add(data)
      ..add((ByteData(4)..setUint32(0, _crc32(data))).buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2) // colour type 2 = truecolour, NO alpha
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', ZLibCodec(level: 9).encode(raw.takeBytes()));
  chunk('IEND', const []);
  return out.takeBytes();
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

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
        // Raw RGBA, then re-encoded as RGB. toImage always produces an alpha
        // channel, and Apple rejects a marketing icon that has one
        // (ITMS-90717) — the ground here is opaque paper, so the channel is
        // pure liability. Encoding all sizes the same way keeps them
        // consistent and the files smaller.
        final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final file = File(path)..parent.createSync(recursive: true);
        file.writeAsBytesSync(_opaquePng(raw!.buffer.asUint8List(), px, px));
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

    // The foreground layer is the same mark on a transparent ground, drawn
    // smaller so the mask cannot clip it. Rendered from its own boundary.
    final fgKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: fgKey,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: _AppIcon(side: side, transparent: true, scale: _safeZone),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fgBoundary =
        fgKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;

    await tester.runAsync(() async {
      for (final entry in _androidForeground.entries) {
        final image = await fgBoundary.toImage(pixelRatio: entry.value / side);
        try {
          // Keeps its alpha on purpose: the launcher composites this over the
          // background colour and masks it to the device's icon shape.
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final path =
              'android/app/src/main/res/${entry.key}/ic_launcher_foreground.png';
          File(path)
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
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
