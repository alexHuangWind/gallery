import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/entry_store.dart';
import 'data/session.dart';
import 'data/archive_view.dart';
import 'data/sync/sync_api.dart';
import 'data/sync/sync_config.dart';
import 'data/sync/sync_outbox.dart';
import 'data/sync/sync_service.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local-first startup: open Hive, the stubbed-or-real session, and the sync
  // outbox. Nothing here talks to the network — syncing happens later and
  // never gates the first frame.
  //
  // Guarded because openBox is non-lazy — it deserializes the whole archive
  // here. Without this, one unreadable record throws before runApp and the app
  // launches to a permanently black window with no way back to the entries.
  try {
    final outbox = await SyncOutbox.open();
    final store = await EntryStore.open(outbox: outbox);
    final session = await Session.open();
    runApp(IPreferApp(store: store, session: session, outbox: outbox));
  } catch (e, stack) {
    debugPrint('startup failed: $e\n$stack');
    runApp(const _StartupFailed());
  }
}

/// Last resort when the archive cannot be opened. Says what happened plainly
/// and does not pretend the app is working.
class _StartupFailed extends StatelessWidget {
  const _StartupFailed();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: Text(
              "couldn't open your archive.\nrestarting may help.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted, height: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

class IPreferApp extends StatefulWidget {
  const IPreferApp({
    super.key,
    required this.store,
    required this.session,
    required this.outbox,
  });

  final EntryStore store;
  final Session session;
  final SyncOutbox outbox;

  @override
  State<IPreferApp> createState() => _IPreferAppState();
}

class _IPreferAppState extends State<IPreferApp> with WidgetsBindingObserver {
  final ArchiveView _view = ArchiveView();

  /// Always present so the UI can ask about backup state without every widget
  /// coping with a missing service; it simply reports `enabled == false` for a
  /// guest, which is a supported way to use the app rather than a degraded one.
  late SyncService _sync;
  String? _syncingAs;
  bool _wasSignedIn = false;

  @override
  void initState() {
    super.initState();
    // Drop filter selections whose tag stops existing. Driven from the store's
    // notification rather than from build, because pruning notifies and
    // mutating a ChangeNotifier mid-build throws.
    widget.store.addListener(_pruneFilter);
    widget.session.addListener(_onSessionChanged);
    WidgetsBinding.instance.addObserver(this);
    _wasSignedIn = widget.session.signedIn;
    _configureSync();
  }

  void _pruneFilter() => _view.prune(widget.store.tagsByUse);

  void _onSessionChanged() {
    final signedIn = widget.session.signedIn;
    // Edge-detected: Session notifies on the way in as well as out, and only
    // a sign-*out* should clear anything.
    if (_wasSignedIn && !signedIn) {
      _view.reset();
      // The next account must not inherit this one's queue, cursor, or the
      // "already adopted" flag.
      widget.outbox.reset();
    }
    _wasSignedIn = signedIn;
    // The provider hands out this instance, so a swap needs a rebuild.
    if (_configureSync()) setState(() {});
  }

  /// Rebuilds the sync service to match the current account.
  ///
  /// Returns true when the instance changed, so the caller can rebuild the
  /// provider around it.
  bool _configureSync() {
    final token = widget.session.syncEnabled ? widget.session.syncToken : null;
    final wanted = syncConfigured ? token : null;
    if (_syncingAs == wanted && _initialised) return false;

    _syncingAs = wanted;
    // Safe even mid-pass: SyncService guards its own notifications after
    // disposal, so an in-flight sync's `finally` can no longer throw.
    if (_initialised) _sync.dispose();
    _initialised = true;
    _sync = SyncService(
      api: wanted == null ? null : HttpSyncApi(baseUrl: kSyncBaseUrl, token: wanted),
      outbox: widget.outbox,
      store: widget.store,
      // Record the lapse on the session so the timeline can offer one
      // sign-in instead of the app retrying a dead token forever.
      onAuthExpired: widget.session.markSyncTokenExpired,
    );
    if (wanted != null) _syncAfterSignIn();
    return true;
  }

  bool _initialised = false;

  Future<void> _syncAfterSignIn() async {
    // Anything recorded as a guest predates the account and has never been
    // offered to the server. Adopt it once, then sync normally.
    await widget.outbox.adoptExisting(widget.store.entries);
    await _sync.syncNow();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back is the natural moment: anything recorded offline goes up,
    // and anything recorded on another phone comes down.
    if (state == AppLifecycleState.resumed) _sync.syncNow();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_pruneFilter);
    widget.session.removeListener(_onSessionChanged);
    _sync.dispose();
    _view.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<EntryStore>.value(value: widget.store),
        ChangeNotifierProvider<Session>.value(value: widget.session),
        // Filter + sort, shared so the timeline and the map stay in step.
        ChangeNotifierProvider<ArchiveView>.value(value: _view),
        // So the timeline can say whether the archive is actually backed up.
        ChangeNotifierProvider<SyncService>.value(value: _sync),
      ],
      child: MaterialApp(
        title: 'I prefer',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const _Root(),
      ),
    );
  }
}

/// Routes between the login screen and the timeline based on session state.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final signedIn = context.watch<Session>().signedIn;
    return signedIn ? const HomeShell() : const LoginScreen();
  }
}
