import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/archive_view.dart';
import '../data/session.dart';
import '../theme.dart';
import 'archive_screen.dart';
import 'compose_screen.dart';
import 'map_screen.dart';

/// Two ways into the same record: the timeline (when) and the map (where).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  void _compose() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ComposeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // "I prefer" keeps its capital everywhere it appears as the phrase —
        // it is the app's name and the card's signature line, not body copy.
        // The lowercase voice applies to what the app *says*, not to what it
        // is called. ("places" is body copy, so it stays lowercase.)
        title: Text(_tab == 0 ? 'I prefer' : 'places'),
        actions: [
          IconButton(
            tooltip: 'sign out',
            icon: const Icon(Icons.logout, size: 20),
            onPressed: () {
              // Reset BEFORE signOut: the next user must not inherit this
              // one's filter, sort, or last known coordinates. This is the
              // only sign-out path today; if Firebase ever adds another
              // (expiry, revocation), move this pairing into main.dart's
              // composition root next to the store→prune listener.
              context.read<ArchiveView>().reset();
              context.read<Session>().signOut();
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [ArchiveScreen(), MapScreen()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        backgroundColor: context.colors.ink,
        foregroundColor: context.colors.paper,
        // 8dp like every real button; the default stadium pill reads as a
        // chip, and pills mean "selectable filter" everywhere else here.
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        icon: const Icon(Icons.add),
        label: const Text('record'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule),
            label: 'timeline',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'map',
          ),
        ],
      ),
    );
  }
}
