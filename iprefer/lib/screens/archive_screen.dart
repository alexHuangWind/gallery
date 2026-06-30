import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/entry_store.dart';
import '../data/session.dart';
import '../models/entry.dart';
import '../theme.dart';
import '../widgets/preference_card.dart';
import 'card_screen.dart';
import 'compose_screen.dart';

/// The timeline — a slow self-portrait of taste. Newest first. This is the
/// app's home.
class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  void _compose(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ComposeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<EntryStore>();
    final entries = store.entries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('i prefer'),
        actions: [
          IconButton(
            tooltip: 'sign out',
            icon: const Icon(Icons.logout, size: 20),
            onPressed: () => context.read<Session>().signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _compose(context),
        backgroundColor: AppTheme.ink,
        foregroundColor: AppTheme.paper,
        icon: const Icon(Icons.add),
        label: const Text('record'),
      ),
      body: entries.isEmpty
          ? _EmptyState(onStart: () => _compose(context))
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 9 / 16,
              ),
              itemCount: entries.length,
              itemBuilder: (context, i) => _ArchiveTile(entry: entries[i]),
            ),
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({required this.entry});

  final Entry entry;

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CardScreen(entry: entry)),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('remove this?'),
        content: const Text('this entry leaves your timeline for good.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('keep')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('remove')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<EntryStore>().delete(entry.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      onLongPress: () => _confirmDelete(context),
      child: PreferenceCard(
        image: FileImage(File(entry.localPath)),
        text: entry.text,
        createdAt: entry.createdAt,
        compact: true,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'nothing here yet',
              style: TextStyle(
                fontFamily: AppTheme.serif,
                fontStyle: FontStyle.italic,
                fontSize: 26,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'photograph one small thing you like.\nstart the record.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onStart, child: const Text('record the first one')),
          ],
        ),
      ),
    );
  }
}
