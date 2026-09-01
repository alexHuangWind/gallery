import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:iprefer/data/entry_store.dart';
import 'package:iprefer/data/session.dart';
import 'package:iprefer/data/sync/auth_client.dart';
import 'package:iprefer/data/sync/sync_api.dart';
import 'package:iprefer/data/sync/sync_op.dart';
import 'package:iprefer/data/sync/sync_outbox.dart';
import 'package:iprefer/data/sync/sync_service.dart';
import 'package:iprefer/models/entry.dart';
import 'package:iprefer/theme.dart';
import 'package:iprefer/widgets/backup_bar.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

/// The backup line is the only place the app ever reports on the account's
/// one promise. A device can't reach most of these states — a lapsed session
/// takes 30 days, an in-flight sync is a blink — so they are pinned here.
///
/// Note the `tester.runAsync` calls: testWidgets runs inside a fake-async
/// zone, and the store and outbox do real file I/O. Awaiting those directly
/// hangs forever, because fake time never delivers a real IO completion.

class _StubApi implements SyncApi {
  _StubApi({this.expired = false, this.offline = false});
  final bool expired;
  final bool offline;

  Never _fail() {
    if (expired) throw SyncAuthExpiredException();
    throw SyncApiException('offline');
  }

  @override
  Future<int> push(List<SyncOp> ops) async {
    if (expired || offline) _fail();
    return 0;
  }

  @override
  Future<PullPage> pull({required int since, int limit = 200}) async {
    if (expired || offline) _fail();
    return const PullPage(ops: [], seq: 0, hasMore: false);
  }

  @override
  Future<void> uploadPhoto(String name, Uint8List bytes) async {
    if (expired || offline) _fail();
  }

  @override
  Future<Uint8List?> downloadPhoto(String name) async {
    if (expired || offline) _fail();
    return null;
  }
}

class _StubAuth implements AuthClient {
  @override
  Future<AppleSession> exchangeAppleToken(String identityToken) async =>
      const AppleSession(token: 'fresh-token', userId: 'user-1');
}

void main() {
  late Directory tempDir;
  late Box<Entry> entriesBox;
  late SyncOutbox outbox;
  late EntryStore store;
  late Session session;
  late String photosRoot;
  var seq = 0;

  final when = DateTime.fromMillisecondsSinceEpoch(1755000000000);

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('iprefer_backup_bar_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(EntryAdapter());

    final n = seq++;
    entriesBox = await Hive.openBox<Entry>('entries_$n');
    outbox = SyncOutbox.forTest(
      await Hive.openBox('ops_$n'),
      await Hive.openBox('meta_$n'),
      await Hive.openBox('photos_$n'),
    );
    photosRoot = p.join(tempDir.path, 'photos');
    Directory(photosRoot).createSync(recursive: true);
    store = EntryStore.forTest(entriesBox, photosRoot: photosRoot, outbox: outbox);
    session = Session.forTest(
      await Hive.openBox('session_$n'),
      appleToken: () async => 'apple-token',
      auth: _StubAuth(),
    );
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester, SyncService sync) {
    return tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EntryStore>.value(value: store),
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<SyncService>.value(value: sync),
        ],
        // The real theme, so the bar's colours resolve the way they do in
        // the app rather than through AppColors' release-only fallback.
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: BackupBar()),
        ),
      ),
    );
  }

  Future<Entry> record() async {
    final src = File(p.join(tempDir.path, 'pick_${seq++}.jpg'))
      ..writeAsBytesSync(List.filled(16, 3));
    return store.create(sourcePhotoPath: src.path, text: 'a thing', createdAt: when);
  }

  testWidgets('a guest is told nothing — no account, no promise', (tester) async {
    final sync = SyncService(api: null, outbox: outbox, store: store);
    await tester.runAsync(record);

    await pump(tester, sync);

    expect(find.byType(BackupBar), findsOneWidget);
    // Renders, but occupies nothing and says nothing.
    expect(tester.getSize(find.byType(BackupBar)).height, 0);
    expect(find.textContaining('backed up'), findsNothing);
  });

  testWidgets('an account with nothing outstanding says it is backed up',
      (tester) async {
    final sync = SyncService(api: _StubApi(), outbox: outbox, store: store);
    await tester.runAsync(sync.syncNow);

    await pump(tester, sync);

    expect(find.textContaining('backed up'), findsOneWidget);
    expect(find.textContaining('just now'), findsOneWidget);
  });

  testWidgets('unsynced entries are counted, and read as safe-but-not-yet',
      (tester) async {
    final sync = SyncService(api: _StubApi(offline: true), outbox: outbox, store: store);
    await tester.runAsync(() async {
      await record();
      await record();
    });

    await pump(tester, sync);

    expect(find.text('2 entries not backed up yet'), findsOneWidget);
  });

  testWidgets('one entry is singular', (tester) async {
    final sync = SyncService(api: _StubApi(offline: true), outbox: outbox, store: store);
    await tester.runAsync(record);

    await pump(tester, sync);

    expect(find.text('1 entry not backed up yet'), findsOneWidget);
  });

  testWidgets('an unreachable server is stated plainly, not as an error',
      (tester) async {
    final sync = SyncService(api: _StubApi(offline: true), outbox: outbox, store: store);
    await tester.runAsync(sync.syncNow); // fails, nothing pending

    await pump(tester, sync);

    expect(find.text("couldn't reach your backup"), findsOneWidget);
  });

  group('a lapsed session', () {
    testWidgets('asks for a sign-in instead of pretending to work',
        (tester) async {
      final sync = SyncService(
        api: _StubApi(expired: true),
        outbox: outbox,
        store: store,
        onAuthExpired: session.markSyncTokenExpired,
      );
      await tester.runAsync(() async {
        await record();
        await sync.syncNow();
      });

      await pump(tester, sync);

      expect(find.text('sign in again to keep backing up'), findsOneWidget);
      expect(find.text('sign in'), findsOneWidget);
    });

    testWidgets('still shows the prompt once the service is rebuilt as disabled',
        (tester) async {
      // What actually happens in the app: the session is marked expired, so
      // the next service is built with no api at all. The bar must keep
      // asking rather than falling silent and stranding the user.
      await tester.runAsync(() async {
        await session.signInWithApple();
        await session.markSyncTokenExpired();
      });
      final rebuilt = SyncService(api: null, outbox: outbox, store: store);

      await pump(tester, rebuilt);

      expect(find.text('sign in again to keep backing up'), findsOneWidget);
    });

    testWidgets('offers a working way out rather than a dead end',
        (tester) async {
      await tester.runAsync(() async {
        await session.signInWithApple();
        await session.markSyncTokenExpired();
      });
      final rebuilt = SyncService(api: null, outbox: outbox, store: store);
      await pump(tester, rebuilt);

      // The repair has to be reachable from the message itself — telling
      // someone their backup lapsed without a way to fix it is worse than
      // saying nothing. (That signing in actually clears the lapse is a
      // session concern, pinned in session_test.dart; driving the async
      // sign-in from here would straddle the fake- and real-async zones.)
      final button = find.widgetWithText(TextButton, 'sign in');
      expect(button, findsOneWidget);
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    });
  });
}
