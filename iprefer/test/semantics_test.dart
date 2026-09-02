import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iprefer/data/archive_view.dart';
import 'package:iprefer/data/entry_store.dart';
import 'package:iprefer/data/session.dart';
import 'package:iprefer/data/sync/sync_service.dart';
import 'package:iprefer/models/entry.dart';
import 'package:iprefer/screens/archive_screen.dart';
import 'package:iprefer/screens/map_screen.dart';
import 'package:iprefer/theme.dart';
import 'package:iprefer/widgets/entry_chip.dart';
import 'package:iprefer/widgets/preference_card.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

/// What a screen reader is told about the three things in this app you can
/// tap: a recall chip, a map pin, a timeline tile.
///
/// All three were gesture-only and unlabelled. The pin is the worst of them —
/// it announced as an unlabelled image, and the pins *are* the map — and the
/// tile's only way to delete is a long press, which nothing said out loud.
void main() {
  late TestEnv env;
  late EntryStore store;
  late ArchiveView view;
  late Session session;
  late SyncService sync;

  const line = 'a flat white before the world wakes up';

  final entry = Entry(
    id: 'e1',
    localPath: 'missing.jpg', // the placeholder; labels don't need a photo
    text: line,
    createdAt: DateTime(2025, 8, 25, 9),
    placeLabel: 'fitzroy',
  );

  // Every box is opened here rather than in a test body: testWidgets runs in a
  // fake-async zone, and Hive's real file I/O never completes inside one.
  setUp(() async {
    env = await TestEnv.create('iprefer_semantics_test');
    store = await env.store();
    session = await env.session();
    // api: null — a guest, so the backup line takes no height and stays out
    // of this.
    sync = SyncService(api: null, outbox: await env.outbox(), store: store);
    // No getFix: nothing here sorts by distance, and the default would reach
    // for the platform.
    view = ArchiveView(getFix: ({bool prompt = false}) async => null);
  });

  tearDown(() async {
    view.dispose();
    sync.dispose();
    await env.dispose();
  });

  Future<void> pumpAlone(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      ChangeNotifierProvider<EntryStore>.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    );
  }

  testWidgets('a recall chip announces as a button that names the entry',
      (tester) async {
    // Disposed in the body, not a tearDown: the binding checks for live
    // handles before tearDowns run.
    final handle = tester.ensureSemantics();

    await pumpAlone(tester, EntryChip(entry: entry));

    final node = tester.getSemantics(find.byType(EntryChip));
    expect(node, isSemantics(isButton: true, hasTapAction: true));
    expect(node.label, contains(line));
    // The date is part of the chip, so it is part of what the chip says.
    expect(node.label, contains('aug 25, 2025'));

    handle.dispose();
  });

  testWidgets('a map pin announces the entry, its place and its date',
      (tester) async {
    final handle = tester.ensureSemantics();

    // Pumped alone: FlutterMap's tiles never settle under a widget test, so
    // the map the pin normally sits on cannot be pumped at all.
    await pumpAlone(
      tester,
      SizedBox(width: 54, height: 54, child: EntryPin(entry: entry)),
    );

    final node = tester.getSemantics(find.byType(EntryPin));
    expect(node, isSemantics(isButton: true, hasTapAction: true));
    expect(node.label, contains(line));
    expect(node.label, contains('fitzroy'));
    expect(node.label, contains('aug 25, 2025'));

    handle.dispose();
  });

  testWidgets('a timeline tile announces that holding it removes the entry',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.runAsync(() => store.applyRemoteCreate(entry));

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
          home: const Scaffold(body: ArchiveScreen()),
        ),
      ),
    );
    await tester.pump();

    final node = tester.getSemantics(find.byType(PreferenceCard));
    expect(
      node,
      isSemantics(
        isButton: true,
        hasTapAction: true,
        hasLongPressAction: true,
        // The delete path has no visible affordance at all, so the hint is
        // the only place it is announced.
        onLongPressHint: 'remove',
      ),
    );
    expect(node.label, contains(line));

    handle.dispose();
    // Every card starts a palette extraction guarded by a 15 s timeout, and
    // the fake-async binding fails a test that ends with a Timer pending.
    await tester.pump(const Duration(seconds: 20));
  });
}
