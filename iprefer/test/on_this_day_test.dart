import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iprefer/data/entry_store.dart';
import 'package:iprefer/models/entry.dart';
import 'package:iprefer/theme.dart';
import 'package:iprefer/widgets/entry_chip.dart';
import 'package:iprefer/widgets/on_this_day.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

/// The banner only appears on an anniversary, so a device can't show it on
/// demand — the date seam is what makes these states reachable at all.
///
/// The last test renders the real thing to a PNG so the layout can be looked
/// at rather than only asserted about.
void main() {
  late TestEnv env;
  late EntryStore store;
  var seq = 0;

  final today = DateTime(2026, 8, 25, 14);

  setUp(() async {
    env = await TestEnv.create('iprefer_on_this_day_test');
    store = await env.store(withOutbox: false);
  });

  tearDown(() => env.dispose());

  Future<void> seed(WidgetTester tester, DateTime when, String text) {
    return tester.runAsync(() async {
      await store.applyRemoteCreate(Entry(
        id: 'e-${seq++}',
        localPath: 'missing.jpg', // renders the placeholder, which is fine here
        text: text,
        createdAt: when,
      ));
    });
  }

  Future<void> pump(WidgetTester tester, {Key? boundary}) {
    final content = ChangeNotifierProvider<EntryStore>.value(
      value: store,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: OnThisDay(today: today),
          ),
        ),
      ),
    );
    return tester.pumpWidget(
      boundary == null ? content : RepaintBoundary(key: boundary, child: content),
    );
  }

  testWidgets('a day with nothing behind it takes no space', (tester) async {
    await seed(tester, DateTime(2026, 8, 20), 'five days ago');

    await pump(tester);

    expect(find.byType(OnThisDay), findsOneWidget);
    expect(tester.getSize(find.byType(OnThisDay)).height, 0);
  });

  testWidgets('an anniversary names itself and shows what you liked',
      (tester) async {
    await seed(tester, DateTime(2025, 8, 25, 9), 'a flat white before the world wakes up');

    await pump(tester);

    expect(find.text('a year ago today'), findsOneWidget);
    expect(find.text('a flat white before the world wakes up'), findsOneWidget);
    expect(find.text('aug 25, 2025'), findsOneWidget);
  });

  testWidgets('a month-old archive already has something to say',
      (tester) async {
    await seed(tester, DateTime(2026, 7, 25), 'last month');

    await pump(tester);

    // Without the month fallback this feature would be invisible for a year.
    expect(find.text('a month ago today'), findsOneWidget);
  });

  testWidgets('each chip is keyed to its entry', (tester) async {
    await seed(tester, DateTime(2025, 8, 25, 9), 'flowers that outshout the street');
    await seed(tester, DateTime(2025, 8, 25, 18), 'water that forgets to hurry');

    await pump(tester);

    // Unkeyed, the strip's elements are matched by position: an entry
    // arriving at the head hands every chip below it a different photo to
    // decode, on a list that exists to be scrolled.
    final ids = store.entries.map((e) => e.id).toSet();
    final keys = tester
        .widgetList<EntryChip>(find.byType(EntryChip))
        .map((chip) => (chip.key! as ValueKey<String>).value);
    expect(keys, hasLength(2));
    expect(keys, everyElement(isIn(ids)));
  });

  testWidgets('dismissing it collapses the banner for the session',
      (tester) async {
    await seed(tester, DateTime(2025, 8, 25), 'a thing');
    await pump(tester);
    expect(find.text('a year ago today'), findsOneWidget);

    await tester.tap(find.byTooltip('dismiss'));
    await tester.pump();

    expect(find.text('a year ago today'), findsNothing);
    expect(tester.getSize(find.byType(OnThisDay)).height, 0);
  });

  testWidgets('renders a preview png so the layout can be looked at',
      (tester) async {
    await seed(tester, DateTime(2025, 8, 25, 9), 'flowers that outshout the whole street');
    await seed(tester, DateTime(2025, 8, 25, 18), 'water that forgets to hurry');

    final fontBytes =
        File('assets/fonts/PlayfairDisplay-Italic-Variable.ttf').readAsBytesSync();
    final loader = FontLoader('PlayfairDisplay')
      ..addFont(Future.value(ByteData.view(fontBytes.buffer)));
    await loader.load();

    tester.view.physicalSize = const Size(1206, 640);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await pump(tester, boundary: key);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/on_this_day_preview.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });

    expect(File('build/on_this_day_preview.png').existsSync(), isTrue);
  });
}
