import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iprefer/data/archive_view.dart';
import 'package:iprefer/data/entry_store.dart';
import 'package:iprefer/data/session.dart';
import 'package:iprefer/data/sync/sync_service.dart';
import 'package:iprefer/models/entry.dart';
import 'package:iprefer/screens/home_shell.dart';
import 'package:iprefer/theme.dart';
import 'package:iprefer/widgets/backup_bar.dart';
import 'package:iprefer/widgets/sort_bar.dart';
import 'package:iprefer/widgets/on_this_day.dart';
import 'package:iprefer/widgets/tag_filter_bar.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

/// The search flow end to end, through the real shell: open the field, narrow
/// the archive, hit a query that matches nothing, and get back out.
///
/// Note the `tester.runAsync` in [seed]: testWidgets runs in a fake-async
/// zone and the store does real file I/O, which fake time never completes.
void main() {
  late TestEnv env;
  late EntryStore store;
  late ArchiveView view;
  late Session session;
  late SyncService sync;
  var seq = 0;

  setUp(() async {
    env = await TestEnv.create('iprefer_search_ui_test');
    store = await env.store();
    session = await env.session();
    // api: null — a guest. The backup line then takes no height, which keeps
    // these assertions about search and nothing else.
    sync = SyncService(api: null, outbox: await env.outbox(), store: store);
    // No getFix: "nearest" is not what these exercise, and the default would
    // reach for the platform.
    view = ArchiveView(getFix: ({bool prompt = false}) async => null);
  });

  tearDown(() async {
    view.dispose();
    sync.dispose();
    await env.dispose();
  });

  /// localPath points nowhere on purpose — the card falls back to its
  /// placeholder, which is all these assertions need.
  Future<void> seed(
    WidgetTester tester,
    String id,
    String text, {
    String? place,
    List<String> tags = const [],
    bool located = false,
  }) {
    return tester.runAsync(() async {
      await store.applyRemoteCreate(Entry(
        id: id,
        localPath: 'missing.jpg',
        text: text,
        createdAt: DateTime(2026, 8, 20 + seq++),
        // Off by default: a located entry makes MapScreen build a real
        // FlutterMap, and its tile loading never settles under a widget test.
        latitude: located ? -41.29 : null,
        longitude: located ? 174.78 : null,
        placeLabel: place,
        tags: tags,
      ));
    });
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EntryStore>.value(value: store),
          ChangeNotifierProvider<ArchiveView>.value(value: view),
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<SyncService>.value(value: sync),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openSearch(WidgetTester tester) async {
    await tester.tap(find.byTooltip('search'));
    // The Scaffold animates the FAB out over ~200 ms; a single pump would
    // still find it on screen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// The cards carry their own "I prefer" lockup, so the title has to be
  /// looked for in the app bar specifically.
  Finder title(String text) => find.descendant(
        of: find.byType(AppBar),
        matching: find.text(text),
      );

  /// Every card starts a PaletteGenerator to sample its scrim, and that call
  /// guards itself with a 15 s timeout. In testWidgets' fake-async zone the
  /// Timer never fires on its own and the binding fails the test for leaving
  /// one pending, so every test ends by letting it expire. (The photos here
  /// don't exist, so the extraction can only ever end in that timeout.)
  Future<void> drain(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 20));

  Future<void> type(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pump();
  }

  Future<void> seedThree(WidgetTester tester) async {
    await seed(tester, 'a', 'a flat white before the world wakes up',
        place: 'Cuba Street', tags: const ['coffee']);
    await seed(tester, 'b', 'ferns that uncurl like a slow question',
        place: 'Zealandia');
    await seed(tester, 'c', 'the smell of rain on hot concrete');
  }

  testWidgets('the field is not there until asked for', (tester) async {
    await seedThree(tester);
    await pump(tester);

    expect(find.byType(TextField), findsNothing);
    expect(title('I prefer'), findsOneWidget);
    expect(find.byTooltip('search'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('opening it replaces the title but keeps the way to record',
      (tester) async {
    await seedThree(tester);
    await pump(tester);
    await openSearch(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(title('I prefer'), findsNothing);
    expect(find.text('search what you liked'), findsOneWidget);
    // "I looked for it, it isn't there, let me record it" is exactly when
    // compose is wanted; hiding the button made reaching it cost the query.
    expect(find.text('record'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('typing narrows the timeline', (tester) async {
    await seedThree(tester);
    await pump(tester);
    await openSearch(tester);

    await type(tester, 'ferns');

    expect(view.query, 'ferns');
    expect(find.text('ferns that uncurl like a slow question'), findsOneWidget);
    expect(find.text('the smell of rain on hot concrete'), findsNothing);

    await drain(tester);
  });

  testWidgets('the place and the tags are searchable too', (tester) async {
    await seedThree(tester);
    await pump(tester);
    await openSearch(tester);

    await type(tester, 'cuba');
    expect(find.text('a flat white before the world wakes up'), findsOneWidget);
    expect(find.text('ferns that uncurl like a slow question'), findsNothing);

    await type(tester, 'coffee');
    expect(find.text('a flat white before the world wakes up'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('a query that matches nothing says so and offers the way back',
      (tester) async {
    await seedThree(tester);
    await pump(tester);
    await openSearch(tester);

    await type(tester, 'kangaroo');

    expect(find.text('nothing matches'), findsOneWidget);
    // The archive is not empty, so it must not say "nothing here yet" — that
    // invites a first recording to someone who already has three.
    expect(find.text('nothing here yet'), findsNothing);
    // The exact sentence, not merely "the word appears somewhere" — the field
    // itself holds the query, so findTextContaining would pass with the echo
    // deleted entirely.
    expect(
      find.text('\u201Ckangaroo\u201D isn\u2019t in your archive yet.'),
      findsOneWidget,
    );
    // The filter bar and the backup line stay put; only the grid is replaced.
    expect(find.byType(TagFilterBar), findsOneWidget);
    // skipOffstage: false — a guest's backup line paints nothing, and the
    // default finders skip a zero-extent sliver. The claim here is that it is
    // still mounted, so a lapsed-token warning cannot vanish behind a typo.
    expect(find.byType(SortBar, skipOffstage: false), findsOneWidget);
    expect(find.byType(BackupBar, skipOffstage: false), findsOneWidget);

    await tester.tap(find.text('clear the search'));
    await tester.pump();

    expect(view.query, '');
    expect(find.text('the smell of rain on hot concrete'), findsOneWidget);
    // The regression that motivated _syncField: this button lives deep in the
    // body and cannot reach the controller, so without the sync the field
    // still read "kangaroo" over an unfiltered archive — and the next
    // backspace silently re-narrowed it to "kangaro".
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );

    await drain(tester);
  });

  testWidgets('the clear icon empties the query but keeps searching',
      (tester) async {
    await seedThree(tester);
    await pump(tester);
    await openSearch(tester);
    await type(tester, 'ferns');

    await tester.tap(find.byTooltip('clear'));
    await tester.pump();

    expect(view.query, '');
    expect(find.byType(TextField), findsOneWidget); // still open
    expect(find.text('the smell of rain on hot concrete'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('closing search drops the query', (tester) async {
    // Otherwise the archive stays narrowed with nothing on screen saying why.
    await seedThree(tester);
    await pump(tester);
    await openSearch(tester);
    await type(tester, 'ferns');

    await tester.tap(find.byTooltip('close search'));
    await tester.pump();

    expect(view.query, '');
    expect(find.byType(TextField), findsNothing);
    expect(title('I prefer'), findsOneWidget);
    expect(find.text('the smell of rain on hot concrete'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('the system back button closes search, not the app',
      (tester) async {
    // The shell is the root route: with the field open and nothing above it to
    // pop, Android's back gesture used to leave the app — losing the timeline
    // to close a search box.
    await seedThree(tester);
    await pump(tester);
    await openSearch(tester);
    await type(tester, 'ferns');

    // By predicate rather than byType: PopScope is generic and the shell lets
    // its type argument be inferred, so naming a Type here would be asserting
    // about inference rather than about back.
    bool canPop() => tester
        .widgetList(find.descendant(
          of: find.byType(HomeShell),
          matching: find.byWidgetPredicate((w) => w is PopScope),
        ))
        .whereType<PopScope>()
        .single
        .canPop;

    // The claim the gesture rests on: while searching, back is ours to answer.
    expect(canPop(), isFalse);

    await tester.binding.handlePopRoute();
    await tester.pump();

    // Exactly what the back arrow does — and the shell is still standing.
    expect(view.query, '');
    expect(find.byType(TextField), findsNothing);
    expect(title('I prefer'), findsOneWidget);
    expect(find.text('the smell of rain on hot concrete'), findsOneWidget);
    // With search closed the route is poppable again, so back means "leave"
    // and the system handles it — this shell must not swallow it.
    expect(canPop(), isTrue);

    await drain(tester);
  });

  testWidgets('the query survives a tab switch', (tester) async {
    // This is what makes the query shared state rather than the timeline's:
    // the map has to stay narrowed to the same thing.
    await seedThree(tester);
    await pump(tester);
    await openSearch(tester);
    await type(tester, 'ferns');

    await tester.tap(find.text('map'));
    await tester.pump();
    expect(view.query, 'ferns');

    await tester.tap(find.text('timeline'));
    await tester.pump();

    expect(view.query, 'ferns');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'ferns',
    );
    expect(find.text('the smell of rain on hot concrete'), findsNothing);

    await drain(tester);
  });

  testWidgets('the search narrows the map as well', (tester) async {
    // Every entry here HAS a place, so the map would have three pins to draw.
    // The query is set before the first pump because a MapScreen with pins
    // builds a real FlutterMap, whose tile loading never settles in a widget
    // test — which is also what makes this a genuine assertion: drop the
    // search from MapScreen's filter and the empty state never appears.
    await seed(tester, 'a', 'a flat white before the world wakes up',
        place: 'Cuba Street', tags: const ['coffee'], located: true);
    await seed(tester, 'b', 'ferns that uncurl like a slow question',
        place: 'Zealandia', located: true);
    await seed(tester, 'c', 'the smell of rain on hot concrete', located: true);

    view.setQuery('kangaroo');
    await pump(tester);

    await tester.tap(find.text('map'));
    await tester.pump();

    expect(find.text('nothing to put on the map'), findsOneWidget);
    expect(
      find.text('nothing matching \u201Ckangaroo\u201D has a place.'),
      findsOneWidget,
    );

    await drain(tester);
  });

  testWidgets('a dismissed banner survives a search', (tester) async {
    // The banners are suppressed while searching, not removed: dropping them
    // from the sliver list would tear down their State, so a dismissal would
    // come back and the location lookup behind one would re-run on every
    // search that starts or ends.
    await seedThree(tester);
    await pump(tester);

    final banner = find.byType(OnThisDay, skipOffstage: false);
    final before = tester.state(banner);

    await openSearch(tester);
    await type(tester, 'ferns');
    // Still mounted, just silent.
    expect(banner, findsOneWidget);
    expect(tester.getSize(banner).height, 0);

    await type(tester, '');
    // The same State object, so a dismissal — and the GPS read behind the
    // sibling banner — survived the round trip.
    expect(tester.state(banner), same(before));

    await drain(tester);
  });

  testWidgets('an empty archive still says "nothing here yet"', (tester) async {
    await pump(tester);
    expect(find.text('nothing here yet'), findsOneWidget);
    expect(find.text('nothing matches'), findsNothing);

    await drain(tester);
  });
}
