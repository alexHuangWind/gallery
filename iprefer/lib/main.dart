import 'dart:async';

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
      darkTheme: AppTheme.dark(),
      home: Scaffold(
        // Builder, so `context.colors` resolves against the MaterialApp's own
        // theme rather than the (theme-less) context this widget was built in.
        body: Builder(
          builder: (context) => Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                "couldn't open your archive.\nrestarting may help.",
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.muted, height: 1.5),
              ),
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
  bool _initialised = false;
  String? _syncingAs;
  bool _wasSignedIn = false;

  /// Session changes, run strictly one after another.
  ///
  /// The sign-out wipe is a Hive write. Fired and forgotten it could still be
  /// running when a fast re-sign-in reconfigures sync, and land *after* the
  /// new account had queued its ops — deleting them.
  Future<void> _sessionWork = Future<void>.value();

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
    final signedOut = _wasSignedIn && !signedIn;
    _wasSignedIn = signedIn;
    _sessionWork = _sessionWork
        .then((_) => _applySessionChange(signedOut))
        .catchError((Object e, StackTrace stack) {
      // Nothing can await a listener, so without this a failed write here is
      // an unhandled async error rather than a line in the log.
      debugPrint('handling a session change failed: $e\n$stack');
    });
  }

  Future<void> _applySessionChange(bool signedOut) async {
    if (signedOut) {
      _view.reset();
      // Awaited before anything reconfigures sync: the next account must not
      // inherit this one's queue or cursor, and must not have its own queue
      // wiped by a reset that was still in flight. The entries stay on the
      // phone — see SyncOutbox.reset — and the outbox refuses to offer them
      // to whoever signs in next.
      await widget.outbox.reset();
    }
    // The state can be gone across that await.
    if (!mounted) return;
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
    // Safe even mid-pass: dispose bumps the service's generation, so an
    // in-flight pass stops writing after its next await instead of landing the
    // previous account's records in this one's archive.
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
    // Read here rather than inside the pass: by the time that runs the person
    // may already have signed out again.
    final userId = widget.session.userId;
    if (wanted != null && userId != null) unawaited(_syncAfterSignIn(userId));
    return true;
  }

  Future<void> _syncAfterSignIn(String userId) async {
    try {
      // Anything recorded as a guest predates the account and has never been
      // offered to the server. The outbox decides whether this is that case:
      // a *second* account on this phone adopts nothing, or it would upload
      // the first account's archive into the second one's.
      await widget.outbox.adoptExisting(widget.store.entries, userId: userId);
      await _sync.syncNow();
    } catch (e, stack) {
      // Nobody awaits this pass, so a failed Hive write used to escape as an
      // unhandled async error. Backing up is best-effort by construction: the
      // queue is untouched, and the next resume tries the whole thing again.
      debugPrint('sync after sign-in failed: $e\n$stack');
    }
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
        // Follows the system appearance. The palette is the same paper/ink
        // relationship inverted — see AppColors.dark.
        darkTheme: AppTheme.dark(),
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
