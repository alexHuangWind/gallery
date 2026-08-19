import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/entry_store.dart';
import 'data/session.dart';
import 'data/archive_view.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local-only startup: open Hive store + the stubbed session. No Firebase.
  //
  // Guarded because openBox is non-lazy — it deserializes the whole archive
  // here. Without this, one unreadable record throws before runApp and the app
  // launches to a permanently black window with no way back to the entries.
  try {
    final store = await EntryStore.open();
    final session = await Session.open();
    runApp(IPreferApp(store: store, session: session));
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
  const IPreferApp({super.key, required this.store, required this.session});

  final EntryStore store;
  final Session session;

  @override
  State<IPreferApp> createState() => _IPreferAppState();
}

class _IPreferAppState extends State<IPreferApp> {
  final ArchiveView _view = ArchiveView();

  @override
  void initState() {
    super.initState();
    // Drop filter selections whose tag stops existing. Driven from the store's
    // notification rather than from build, because pruning notifies and
    // mutating a ChangeNotifier mid-build throws.
    widget.store.addListener(_pruneFilter);
  }

  void _pruneFilter() => _view.prune(widget.store.tagsByUse);

  @override
  void dispose() {
    widget.store.removeListener(_pruneFilter);
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

/// Routes between the stubbed login and the timeline based on session state.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final signedIn = context.watch<Session>().signedIn;
    return signedIn ? const HomeShell() : const LoginScreen();
  }
}
