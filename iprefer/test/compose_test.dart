import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iprefer/data/entry_store.dart';
import 'package:iprefer/data/location_service.dart';
import 'package:iprefer/screens/compose_screen.dart';
import 'package:iprefer/theme.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'support/harness.dart';

/// The first screen of the product, and until now the only one with no tests.
///
/// Everything here is pumped through [ComposeScreen.seeded]: a real pick goes
/// out to the platform picker and then to the location stack, so every state
/// that follows a pick is otherwise unreachable under `flutter test`. Nothing
/// here taps the well, which is what keeps LocationService.current out of it.
void main() {
  late TestEnv env;
  late EntryStore store;
  var seq = 0;

  setUpAll(() async {
    // flutter_test's stand-in font gives every glyph a one-em advance, so at
    // 2x type "try again" alone measures wider than a phone. Nothing is
    // provable about layout with it; load the face the app actually ships and
    // use it for everything so the numbers mean something.
    final bytes =
        File('assets/fonts/PlayfairDisplay-Variable.ttf').readAsBytesSync();
    final loader = FontLoader(AppTheme.serif)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  });

  setUp(() async {
    env = await TestEnv.create('iprefer_compose_test');
    store = await env.store(withOutbox: false);
  });

  tearDown(() => env.dispose());

  /// A path that exists but holds nothing decodable, so the well takes its
  /// error path — which is the point: without an errorBuilder that throws.
  File fakePhoto() {
    return File(p.join(env.tempDir.path, 'pick_${seq++}.jpg'))
      ..writeAsBytesSync(const <int>[0, 1, 2, 3]);
  }

  Future<void> pump(
    WidgetTester tester, {
    File? photo,
    FixState fixState = FixState.idle,
    PlaceFix? fix,
    TextScaler scaler = TextScaler.noScaling,
  }) {
    final theme = AppTheme.light();
    return tester.pumpWidget(
      ChangeNotifierProvider<EntryStore>.value(
        value: store,
        child: MaterialApp(
          // Anything the screen does not explicitly set in serif falls back to
          // the platform sans, which under test is the one-em font above.
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: AppTheme.serif),
          ),
          home: MediaQuery(
            data: MediaQueryData(textScaler: scaler),
            child: ComposeScreen.seeded(
              initialPhoto: photo,
              initialFixState: fixState,
              initialFix: fix,
            ),
          ),
        ),
      ),
    );
  }

  FilledButton makeButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  testWidgets('without a photo there is nothing to make a card from',
      (tester) async {
    await pump(tester);

    expect(makeButton(tester).onPressed, isNull);

    // Words alone are not enough either — the card is the photo.
    await tester.enterText(find.byType(TextField).first, 'ferns');
    await tester.pump();

    expect(makeButton(tester).onPressed, isNull);
  });

  testWidgets('typing arms the button without rebuilding the photo well',
      (tester) async {
    await pump(tester, photo: fakePhoto());

    final wellBefore = tester.widget(find.byKey(photoWellKey));
    expect(makeButton(tester).onPressed, isNull);

    await tester.enterText(
        find.byType(TextField).first, 'a flat white before the world wakes up');
    await tester.pump();

    expect(makeButton(tester).onPressed, isNotNull,
        reason: 'the button still has to notice the words');
    // Identity, not equality: the well is constructed afresh on every parent
    // build, so a surviving instance is proof the parent did not rebuild —
    // and that the decoded photo and the store's tag vocabulary were left
    // alone for the length of a sentence.
    expect(
      identical(tester.widget(find.byKey(photoWellKey)), wellBefore),
      isTrue,
      reason: 'a keystroke must not rebuild the photo well',
    );
  });

  testWidgets('emptying the field disarms the button again', (tester) async {
    await pump(tester, photo: fakePhoto());

    await tester.enterText(find.byType(TextField).first, 'something');
    await tester.pump();
    expect(makeButton(tester).onPressed, isNotNull);

    // Whitespace is not a preference.
    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.pump();
    expect(makeButton(tester).onPressed, isNull);
  });

  testWidgets('the well caps its decode and has somewhere to fall back to',
      (tester) async {
    await pump(tester, photo: fakePhoto());
    await tester.pump();

    expect(tester.takeException(), isNull);

    final image = tester.widget<Image>(find.descendant(
      of: find.byKey(photoWellKey),
      matching: find.byType(Image),
    ));
    // The picker allows 2000 px; the well is ~360 pt. Uncapped this is tens of
    // MB of RGBA sitting in the image cache behind the first thing anyone does.
    expect(
      image.image,
      isA<ResizeImage>().having((r) => r.width, 'decode cap', 1200),
    );

    // Build the fallback the way the framework would when a file will not
    // decode. Before this existed, that case threw straight out of build.
    final fallback = image.errorBuilder!(
        tester.element(find.byKey(photoWellKey)),
        Exception('not an image'),
        null);
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: Scaffold(body: fallback)));

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
  });

  testWidgets('an empty well announces itself as the way in', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    final label = find.bySemanticsLabel('add a photo of something you like');
    expect(label, findsOneWidget);
    // The affordance is the point: without it this is a decorated box and a
    // sentence, and the product's first action reads as prose.
    expect(
      tester.getSemantics(label),
      isSemantics(
        label: 'add a photo of something you like',
        isButton: true,
        hasTapAction: true,
      ),
    );

    handle.dispose();
  });

  testWidgets('a filled well offers to change the photo', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, photo: fakePhoto());

    expect(find.bySemanticsLabel('change the photo'), findsOneWidget);

    handle.dispose();
  });

  group('the place row survives large type on a narrow phone', () {
    // 360 dp is the ordinary Android width and 2x is an accessibility setting
    // people really use; together they are what pushed the "no place on this
    // one" label and its button past the right edge.
    const labels = <FixState, String>{
      FixState.locating: 'finding where you are',
      FixState.found: 'the wine shop on gertrude street',
      FixState.dropped: 'no place on this one',
      FixState.unavailable: "couldn't get your location",
    };

    for (final state in labels.keys) {
      testWidgets('${state.name} fits', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        await pump(
          tester,
          photo: fakePhoto(),
          fixState: state,
          fix: state == FixState.found
              ? PlaceFix(
                  latitude: -37.8, longitude: 144.98, label: labels[state])
              : null,
          scaler: const TextScaler.linear(2.0),
        );
        // Not pumpAndSettle: the locating branch spins forever.
        await tester.pump();

        expect(tester.takeException(), isNull,
            reason: 'nothing may overflow at 2x type');

        // The label yields to the action rather than shoving it off-screen:
        // this button is the recovery path after a location denial, so it has
        // to stay whole and tappable. 340 = 360 dp less the screen's padding.
        if (state != FixState.locating) {
          final button = tester.getRect(find.byType(TextButton));
          expect(button.right, lessThanOrEqualTo(340.0));
          expect(button.width, greaterThanOrEqualTo(48.0));
          expect(button.height, greaterThanOrEqualTo(40.0));
        }

        // Drop the tree so the locating spinner's ticker does not outlive the
        // test.
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });

  testWidgets('idle keeps the place row out of the way', (tester) async {
    await pump(tester, photo: fakePhoto());

    expect(find.text('finding where you are'), findsNothing);
    expect(find.text('no place on this one'), findsNothing);
    expect(find.text("couldn't get your location"), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });
}
