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
  final store = await EntryStore.open();
  final session = await Session.open();

  runApp(IPreferApp(store: store, session: session));
}

class IPreferApp extends StatelessWidget {
  const IPreferApp({super.key, required this.store, required this.session});

  final EntryStore store;
  final Session session;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<EntryStore>.value(value: store),
        ChangeNotifierProvider<Session>.value(value: session),
        // Filter + sort, shared so the timeline and the map stay in step.
        ChangeNotifierProvider<ArchiveView>(create: (_) => ArchiveView()),
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
