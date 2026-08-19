import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
        title: Text(_tab == 0 ? 'i prefer' : 'places'),
        actions: [
          IconButton(
            tooltip: 'sign out',
            icon: const Icon(Icons.logout, size: 20),
            onPressed: () => context.read<Session>().signOut(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [ArchiveScreen(), MapScreen()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        backgroundColor: AppTheme.ink,
        foregroundColor: AppTheme.paper,
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
