import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iprefer/widgets/preference_card.dart';

/// What the card promises: one artifact. The same entry has to come off two
/// different phones as the same PNG, and the tone under the lockup has to come
/// out of the photo rather than out of a generic black bar.
///
/// The sampler seam is what makes any of this testable in reasonable time —
/// the real one decodes and quantizes the photo and waits up to 15 s on
/// PaletteGenerator. These tests hand the card the answer instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A flat 9:16 photo. Built once, in setUpAll, which runs outside the
  // fake-async zone where real image encoding actually completes.
  late Uint8List photo;

  setUpAll(() async {
    photo = await _solidPng(const Color(0xFF6E8B74));
  });

  setUp(clearScrimCache); // one test's cached tones must not decide another's

  group('scrimFrom', () {
    // The spread a real photo lands in: near-black night shots, mid tones,
    // saturated signage, blown-out sky.
    const sources = <Color>[
      Color(0xFF0A0A0A),
      Color(0xFF101010),
      Color(0xFF3355AA),
      Color(0xFF6E8B74),
      Color(0xFFB5651D),
      Color(0xFFFF0000),
      Color(0xFFFFE066),
      Color(0xFFFFFFFF),
    ];

    test('never paints the generic black bar the spec rules out', () {
      for (final source in sources) {
        final scrim = scrimFrom(source);
        expect(
          scrim.r + scrim.g + scrim.b,
          greaterThan(0),
          reason: '$source flattened to black',
        );
      }
    });

    test('a black photo keeps a black scrim', () {
      // The one place the rule above bottoms out, recorded so it stays a
      // decision. "Not pure black" is about not slamming a generic bar over
      // someone's photo; a bottom region that really is black has no other
      // tone to offer, and lifting it to a grey would put a colour on the card
      // that is not in the picture — which is the thing the spec forbids.
      final scrim = scrimFrom(const Color(0xFF000000));
      expect(scrim.r, 0);
      expect(scrim.g, 0);
      expect(scrim.b, 0);
    });

    // The ceilings are applied in HSV and then rounded to 8-bit channels, so
    // reading them back can land a single step above where they were set.
    const rounding = 1 / 255;

    test('stays dark enough for white type to sit on it', () {
      for (final source in sources) {
        final hsv = HSVColor.fromColor(scrimFrom(source));
        expect(hsv.value, lessThanOrEqualTo(0.32 + rounding),
            reason: '$source');
      }
    });

    test('stays quiet enough not to become a colour of its own', () {
      for (final source in sources) {
        final hsv = HSVColor.fromColor(scrimFrom(source));
        expect(hsv.saturation, lessThanOrEqualTo(0.6 + rounding),
            reason: '$source');
      }
    });

    test('keeps the photo visible through it', () {
      for (final source in sources) {
        expect(scrimFrom(source).a, closeTo(0.92, 0.001), reason: '$source');
      }
    });

    test('a blown-out source still darkens', () {
      // The case that matters: a card shot into the sun must not end up with a
      // near-white slab across the bottom third.
      for (final source in const [Color(0xFFFFFFFF), Color(0xFFFFE066)]) {
        final scrim = scrimFrom(source);
        expect(
          scrim.computeLuminance(),
          lessThan(source.computeLuminance() / 4),
          reason: '$source barely moved',
        );
      }
    });

    test('keeps the hue it was handed', () {
      // Otherwise the scrim would stop being "of the photo", which is the
      // whole point of sampling one.
      const source = Color(0xFF3355AA);
      expect(
        HSVColor.fromColor(scrimFrom(source)).hue,
        closeTo(HSVColor.fromColor(source).hue, 2),
      );
    });
  });

  group('the exported card ignores the phone', () {
    testWidgets('two text scales produce byte-identical PNGs', (tester) async {
      final provider = MemoryImage(photo);
      final key = GlobalKey();
      final control = GlobalKey();

      Future<(Uint8List, double)> render(double scale) async {
        await tester.pumpWidget(_Harness(
          textScale: scale,
          boundaryKey: key,
          controlKey: control,
          image: provider,
        ));
        await _settleImage(tester, provider);

        // Proves the harness really is scaling type: the same words in the
        // same size outside the card do grow. Without this the equality below
        // could pass for the wrong reason.
        final controlHeight = tester.getSize(find.byKey(control)).height;

        final capture = tester.runAsync(() => capturePng(key, pixelRatio: 1));
        // capturePng waits on endOfFrame, which only arrives when the test
        // pumps — so the pump has to happen alongside it, not before.
        await tester.pump();
        final bytes = await capture;
        return (bytes!, controlHeight);
      }

      final (plain, plainControl) = await render(1.0);
      final (doubled, doubledControl) = await render(2.0);

      expect(doubledControl, greaterThan(plainControl),
          reason: 'the harness never applied the text scale');
      expect(doubled, equals(plain),
          reason: 'the same entry exported differently on two phones');
    });
  });

  group('the scrim cache', () {
    testWidgets('a photo is only sampled once', (tester) async {
      final provider = MemoryImage(photo);
      var calls = 0;
      Future<Color?> sampler(ImageProvider image) async {
        calls++;
        return const Color(0xFF3355AA);
      }

      await tester.pumpWidget(_Harness(
        textScale: 1.0,
        image: provider,
        sampleScrim: sampler,
      ));
      await tester.pump(); // let the (synchronous) fake sampler land
      expect(calls, 1);
      final sampled = _scrimOf(tester);

      // What a grid tile does when it is scrolled off and back on: the State
      // is thrown away and a new one starts from nothing.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_Harness(
        textScale: 1.0,
        image: provider,
        sampleScrim: sampler,
      ));

      expect(calls, 1, reason: 'the photo was decoded and quantized twice');
      // And on the very first frame, not after a flash of the fallback.
      expect(_scrimOf(tester), sampled);
    });

    testWidgets('a different photo is sampled on its own', (tester) async {
      final other =
          await tester.runAsync(() => _solidPng(const Color(0xFF223344)));
      var calls = 0;
      Future<Color?> sampler(ImageProvider image) async {
        calls++;
        return const Color(0xFF3355AA);
      }

      await tester.pumpWidget(_Harness(
        textScale: 1.0,
        image: MemoryImage(photo),
        sampleScrim: sampler,
      ));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_Harness(
        textScale: 1.0,
        image: MemoryImage(other!),
        sampleScrim: sampler,
      ));
      await tester.pump();

      expect(calls, 2);
    });

    testWidgets('a sampler with nothing to say leaves the fallback alone',
        (tester) async {
      await tester.pumpWidget(_Harness(
        textScale: 1.0,
        image: MemoryImage(photo),
        sampleScrim: (_) async => null,
      ));
      await tester.pump();

      // The neutral scrim, not a transparent one: a failed sample must never
      // leave white type sitting straight on the photo.
      expect(_scrimOf(tester).a, greaterThan(0.5));
    });
  });
}

/// The card at a fixed size, under a chosen text scale.
///
/// The [MediaQuery] sits inside [MaterialApp] on purpose — an app inserts its
/// own from the view, so an override above it would be thrown away.
class _Harness extends StatelessWidget {
  const _Harness({
    required this.textScale,
    required this.image,
    this.boundaryKey,
    this.controlKey,
    this.sampleScrim = samplePaletteScrim,
  });

  final double textScale;
  final ImageProvider image;
  final GlobalKey? boundaryKey;
  final GlobalKey? controlKey;
  final ScrimSampler sampleScrim;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: PreferenceCard(
                  boundaryKey: boundaryKey,
                  image: image,
                  text: 'ferns that uncurl like a slow question',
                  createdAt: DateTime.utc(2026, 8, 25, 9),
                  placeLabel: 'grey lynn',
                  sampleScrim: sampleScrim,
                ),
              ),
              if (controlKey != null)
                Text('I prefer',
                    key: controlKey, style: const TextStyle(fontSize: 19)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The colour at the bottom of the card's gradient — the scrim as painted.
Color _scrimOf(WidgetTester tester) {
  final gradients = tester
      .widgetList<DecoratedBox>(find.byType(DecoratedBox))
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .map((d) => d.gradient)
      .whereType<LinearGradient>();
  return gradients.single.colors.last;
}

/// Gets the photo decoded and painted before anything is captured, so the two
/// captures can't differ over which frame the image landed on.
Future<void> _settleImage(WidgetTester tester, ImageProvider provider) async {
  await tester.runAsync(() async {
    final completer = Completer<void>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener((_, __) {
      if (!completer.isCompleted) completer.complete();
    }, onError: (_, __) {
      if (!completer.isCompleted) completer.complete();
    });
    stream.addListener(listener);
    await completer.future;
    stream.removeListener(listener);
  });
  await tester.pumpAndSettle();
}

/// A 9:16 photo of one colour, as real PNG bytes — the card takes an
/// [ImageProvider], so a fake one would test a different code path.
Future<Uint8List> _solidPng(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 9, 16),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(9, 16);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
