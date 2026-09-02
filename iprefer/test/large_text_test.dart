import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:iprefer/data/archive_view.dart';
import 'package:iprefer/data/entry_store.dart';
import 'package:iprefer/models/entry.dart';
import 'package:iprefer/theme.dart';
import 'package:iprefer/widgets/entry_chip.dart';
import 'package:iprefer/widgets/on_this_day.dart';
import 'package:iprefer/widgets/sort_bar.dart';
import 'package:iprefer/widgets/tag_filter_bar.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

/// Everything here is the same layout at twice the system type size, on a
/// 360 dp phone — the combination that turned the timeline's header and both
/// recall banners into RenderFlex overflows.
///
/// [NearbyRecall] is not pumped: it reads a location itself and can't be
/// handed a fix from a test. It doesn't need to be — its strip *is*
/// [EntryStrip], the same widget [OnThisDay] builds and the one exercised
/// directly below, so covering that covers both banners.
void main() {
  late Directory tempDir;
  late Box<Entry> box;
  late EntryStore store;
  var seq = 0;

  final today = DateTime(2026, 8, 25, 14);

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('iprefer_large_text_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(EntryAdapter());
    box = await Hive.openBox<Entry>('entries_${seq++}');
    final photosRoot = p.join(tempDir.path, 'photos');
    Directory(photosRoot).createSync(recursive: true);
    store = EntryStore.forTest(box, photosRoot: photosRoot);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// A long line on purpose: the chip caps at four lines, and four scaled
  /// lines are what outgrew the old fixed-height strip.
  Entry entryOf(String id) => Entry(
        id: id,
        localPath: 'missing.jpg', // the placeholder is all these need
        text: 'a flat white before the world wakes up, in a cup that is far '
            'too warm to hold',
        createdAt: DateTime(2025, 8, 25, 9),
      );

  Future<void> seed(
    WidgetTester tester,
    String id, {
    List<String> tags = const [],
  }) =>
      tester.runAsync(
        () => store.applyRemoteCreate(
          tags.isEmpty
              ? entryOf(id)
              : Entry(
                  id: id,
                  localPath: '$id.jpg',
                  text: 'thing $id',
                  createdAt: DateTime(2026, 8, 20),
                  tags: tags,
                ),
        ),
      );

  /// A 360 dp phone — the narrowest width worth supporting, and the one the
  /// sort bar's fixed content outgrew first.
  void useNarrowPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double scale = 2.0,
    ArchiveView? view,
  }) {
    return tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EntryStore>.value(value: store),
          if (view != null) ChangeNotifierProvider<ArchiveView>.value(value: view),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            // Inside the app, so this overrides the MediaQuery MaterialApp
            // builds from the test view rather than being replaced by it.
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Align(alignment: Alignment.topLeft, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the recall strip is exactly 116 tall at ordinary type size',
      (tester) async {
    useNarrowPhone(tester);

    await pump(tester, EntryStrip(entries: [entryOf('a')]), scale: 1.0);

    // The pin that keeps the fix from moving anything for the people who
    // never touched the type size.
    expect(tester.getSize(find.byType(EntryStrip)).height, 116);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the recall strip grows with the type instead of clipping it',
      (tester) async {
    useNarrowPhone(tester);

    await pump(tester, EntryStrip(entries: [entryOf('a'), entryOf('b')]));

    expect(tester.takeException(), isNull);
    final strip = tester.getSize(find.byType(EntryStrip)).height;
    expect(strip, greaterThan(116));
    // Every chip has to fit the box it was given — an overflow here is the
    // bug this test exists for, and it is silent in a release build.
    for (final chip in tester.widgetList(find.byType(EntryChip))) {
      expect(tester.getSize(find.byWidget(chip)).height, lessThanOrEqualTo(strip));
    }
  });

  testWidgets('the anniversary banner survives double-size type',
      (tester) async {
    useNarrowPhone(tester);
    await seed(tester, 'a');
    await seed(tester, 'b');

    await pump(tester, OnThisDay(today: today));

    expect(find.byType(EntryStrip), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tag strip is exactly 44 tall at ordinary type size',
      (tester) async {
    await seed(tester, 'a', tags: const ['flowers']);
    final view = ArchiveView(getFix: ({bool prompt = false}) async => null);
    addTearDown(view.dispose);

    await pump(tester, const TagFilterBar(), scale: 1.0, view: view);

    expect(tester.getSize(find.byType(TagFilterBar)).height, 44.0);
  });

  testWidgets('the tag strip grows with the type instead of clipping it',
      (tester) async {
    // Seen on a simulator at the largest accessibility size: the strip stayed
    // 44 tall while its labels did not, and the top and bottom of every tag
    // were cut off.
    await seed(tester, 'a', tags: const ['flowers']);
    final view = ArchiveView(getFix: ({bool prompt = false}) async => null);
    addTearDown(view.dispose);

    await pump(tester, const TagFilterBar(), scale: 3.0, view: view);

    expect(tester.takeException(), isNull);
    final strip = tester.getRect(find.byType(TagFilterBar));
    // Text.rich — the count rides along in the same run, so match a substring.
    final label = tester.getRect(find.textContaining('flowers'));
    expect(label.top, greaterThanOrEqualTo(strip.top));
    expect(label.bottom, lessThanOrEqualTo(strip.bottom));
  });

  testWidgets('the sort bar scrolls rather than overflowing', (tester) async {
    useNarrowPhone(tester);
    final view = ArchiveView(getFix: ({bool prompt = false}) async => null);
    addTearDown(view.dispose);

    await pump(tester, const SortBar(), view: view);

    expect(tester.takeException(), isNull);
    // The labels stay ordinary Text, so the rest of the suite can still find
    // them by what they say.
    expect(find.text('sorted by'), findsOneWidget);
    expect(find.text('newest'), findsOneWidget);
    expect(find.text('nearest'), findsOneWidget);
  });

  testWidgets('the sort bar survives its widest state — nearest, no fix',
      (tester) async {
    useNarrowPhone(tester);
    final view = ArchiveView(getFix: ({bool prompt = false}) async => null);
    addTearDown(view.dispose);
    // No fix and no history: the bar grows a "needs your location" line and a
    // recovery button on top of everything else it already carries.
    await view.setSort(ArchiveSort.nearest);

    await pump(tester, const SortBar(), view: view);

    expect(view.originUnavailable, isTrue);
    expect(find.text('needs your location'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sort bar still fills its width when the controls fit',
      (tester) async {
    // Wider than the phone above on purpose: the test font is a fixed square
    // per glyph and far wider than the app's, so "does it fit" has to be
    // asked at a width where, in this font, it does.
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final view = ArchiveView(getFix: ({bool prompt = false}) async => null);
    addTearDown(view.dispose);

    await pump(tester, const SortBar(), view: view, scale: 1.0);

    // Laid out at the viewport width, exactly as the plain Row was: the
    // scroll view is there for the large sizes and costs nothing here.
    final scroller = tester.state<ScrollableState>(
      find.descendant(
          of: find.byType(SortBar), matching: find.byType(Scrollable)),
    );
    expect(scroller.position.maxScrollExtent, 0);
    final row = find
        .descendant(of: find.byType(SortBar), matching: find.byType(Row))
        .first;
    expect(tester.getSize(row).width, 600 - 32); // the padding, not the type
    expect(tester.takeException(), isNull);
  });
}
