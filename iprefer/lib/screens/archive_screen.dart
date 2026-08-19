import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/entry_store.dart';
import '../data/archive_view.dart';
import '../models/entry.dart';
import '../theme.dart';
import '../widgets/nearby_recall.dart';
import '../widgets/preference_card.dart';
import '../widgets/sort_bar.dart';
import '../widgets/tag_filter_bar.dart';
import 'card_screen.dart';
import 'compose_screen.dart';

/// The timeline — a slow self-portrait of taste. Newest first.
///
/// Rendered as the first tab of [HomeShell], which owns the app bar and FAB,
/// so this is a bare body.
class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<EntryStore>();

    if (store.isEmpty) {
      return _EmptyState(
        onStart: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ComposeScreen()),
        ),
      );
    }

    final view = context.watch<ArchiveView>();
    final active = view.effective(store.tagsByUse);

    // Filtering is OR, and `active` only ever holds tags that still exist, so
    // this list cannot come back empty while the store has entries — there is
    // no "your filter matched nothing" state to handle here.
    final entries = view.order(store.withAnyTag(active));

    return CustomScrollView(
      slivers: [
        // Zero height until the user has tagged something.
        const SliverToBoxAdapter(child: TagFilterBar()),
        const SliverToBoxAdapter(child: SortBar()),
        // Surfaces only when the user is standing somewhere they've recorded
        // before; otherwise it takes zero height.
        SliverToBoxAdapter(child: NearbyRecall(tags: active)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 9 / 16,
            ),
            delegate: SliverChildBuilderDelegate(
              // Keyed so recycling doesn't carry one card's extracted scrim
              // over to another photo when the list re-sorts.
              (context, i) =>
                  _ArchiveTile(key: ValueKey(entries[i].id), entry: entries[i]),
              childCount: entries.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({super.key, required this.entry});

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
        image: FileImage(EntryStore.fileFor(entry)),
        text: entry.text,
        createdAt: entry.createdAt,
        placeLabel: entry.placeLabel,
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
            const Text(
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
