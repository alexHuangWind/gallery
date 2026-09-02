import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/entry_store.dart';
import '../data/archive_view.dart';
import '../models/entry.dart';
import '../theme.dart';
import '../widgets/backup_bar.dart';
import '../widgets/nearby_recall.dart';
import '../widgets/on_this_day.dart';
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
      // The backup line still belongs here: a lapsed session on a device with
      // nothing recorded would otherwise have nowhere to say so.
      return Column(
        children: [
          const BackupBar(),
          Expanded(
            child: _EmptyState(
              onStart: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ComposeScreen()),
              ),
            ),
          ),
        ],
      );
    }

    final view = context.watch<ArchiveView>();
    final active = view.effective(store.tagsByUse);

    // Tag filtering is OR and `active` only ever holds tags that still exist,
    // so tags alone cannot empty this list. Search can, and does — a typo is
    // enough — so that state is handled below.
    final entries = view.arrange(store.withAnyTag(active));

    // Keyed lookup for findChildIndexCallback below. Built once per build
    // rather than scanning the list per child.
    final indexOfId = {
      for (var i = 0; i < entries.length; i++) entries[i].id: i,
    };

    return CustomScrollView(
      // The only way to put an iOS keyboard away without also closing the
      // search — the search key unfocuses too, but scrolling the results is
      // the gesture people reach for.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        // Zero height until the user has tagged something.
        const SliverToBoxAdapter(child: TagFilterBar()),
        const SliverToBoxAdapter(child: SortBar()),
        // Zero height for a guest; one quiet line for an account.
        const SliverToBoxAdapter(child: BackupBar()),
        // Both banners resurface entries the user did not ask for, which is
        // the point — until they are looking for something specific, when it
        // is just something else to read past. Suppressed rather than removed:
        // dropping them from this list would tear down their State, losing a
        // dismissal and re-running a GPS read on every search that starts or
        // ends.
        //
        // Surfaces only when the user is standing somewhere they've recorded
        // before; otherwise it takes zero height.
        SliverToBoxAdapter(
          child: NearbyRecall(tags: active, suppressed: view.isSearching),
        ),
        // The same "here is what you liked" payback, on the time axis.
        // Zero height on a day the archive has nothing to say about.
        SliverToBoxAdapter(
          child: OnThisDay(tags: active, suppressed: view.isSearching),
        ),
        // A search that matched nothing replaces the grid and nothing else:
        // the filter bar, the sort and the backup line all stay put, so a
        // lapsed-token warning cannot vanish behind a typo.
        if (entries.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _NoMatches(
              query: view.query.trim(),
              filtered: active.isNotEmpty,
              onRecord: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ComposeScreen()),
              ),
            ),
          )
        else
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
                (context, i) => _ArchiveTile(
                    key: ValueKey(entries[i].id), entry: entries[i]),
                childCount: entries.length,
                // Without this, a keyed child whose index moved cannot be
                // matched to its old Element: it is rebuilt from scratch, and
                // every rebuilt card restarts its palette extraction — a
                // decode and a quantization per visible tile, on every
                // keystroke that reorders the results.
                findChildIndexCallback: (key) =>
                    indexOfId[(key as ValueKey<String>).value],
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
      // The dialog's own context, not the tile's: the tile can be unmounted
      // under an open dialog (a sync pull removing that entry), and the next
      // rebuild would then read the theme off a defunct element.
      builder: (ctx) => AlertDialog(
        title: const Text('remove this?'),
        content: const Text('this entry leaves your timeline for good.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            // The only irreversible choice in the app gets the only red.
            style: TextButton.styleFrom(foregroundColor: ctx.colors.danger),
            child: const Text('remove'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final store = context.read<EntryStore>();
      final messenger = ScaffoldMessenger.of(context);
      try {
        await store.delete(entry.id);
      } catch (_) {
        // A failed box write would otherwise vanish into an unhandled async
        // error while the tile silently stays — say so, plainly.
        messenger.showSnackBar(
          const SnackBar(content: Text("couldn't remove — try again")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final place = entry.placeLabel;

    // The tile's own parts announce as a stack of unrelated strings, and the
    // only way to remove an entry is a long press — an affordance nothing on
    // screen or in the semantics tree mentioned. One button node says what
    // the card is, and the hint says what holding it does.
    return Semantics(
      button: true,
      label: [
        entry.text,
        if (place != null && place.isNotEmpty) place,
        quietDate(entry.createdAt),
      ].join(', '),
      excludeSemantics: true,
      onTap: () => _open(context),
      onLongPress: () => _confirmDelete(context),
      onLongPressHint: 'remove',
      // InkWell rather than a bare GestureDetector so both the tap and the
      // long-press visibly register before anything happens. The splash is
      // explicit muted ink — the default ripple resolves from the seed-derived
      // primary, which is exactly the stray color the theme keeps out.
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          splashColor: context.colors.ink.withValues(alpha: 0.06),
          highlightColor: context.colors.ink.withValues(alpha: 0.04),
          onTap: () => _open(context),
          onLongPress: () => _confirmDelete(context),
          child: PreferenceCard(
            image: FileImage(context.read<EntryStore>().fileFor(entry)),
            text: entry.text,
            createdAt: entry.createdAt,
            placeLabel: entry.placeLabel,
            compact: true,
          ),
        ),
      ),
    );
  }
}

/// The archive has entries, but none of them match what was typed.
///
/// Distinct from [_EmptyState] on purpose: "nothing here yet" invites a first
/// recording, which is the wrong thing to say to someone who has fifty entries
/// and a typo. This says what was searched and offers both ways out.
class _NoMatches extends StatelessWidget {
  const _NoMatches({
    required this.query,
    required this.filtered,
    required this.onRecord,
  });

  final String query;

  /// True when a tag filter is *also* narrowing things. The copy has to say
  /// so: with "wine" lit, a search for "ferns" can match an entry that is
  /// plainly in the archive, and "isn't in your archive yet" would be a lie
  /// the user can disprove in two taps.
  final bool filtered;

  final VoidCallback onRecord;

  String get _explanation {
    if (query.isEmpty) return 'nothing is under that tag yet.';
    return filtered
        ? '“$query” isn\u2019t under the tags you have picked.'
        : '“$query” isn\u2019t in your archive yet.';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'nothing matches',
              style: TextStyle(
                fontFamily: AppTheme.serif,
                fontStyle: FontStyle.italic,
                fontSize: 24,
                color: context.colors.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              // The query is echoed so a stale search left open from an
              // earlier session explains the empty page by itself.
              _explanation,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.colors.mutedText, height: 1.5),
            ),
            const SizedBox(height: 18),
            if (query.isNotEmpty)
              OutlinedButton(
                onPressed: () => context.read<ArchiveView>().clearQuery(),
                child: const Text('clear the search'),
              ),
            const SizedBox(height: 10),
            // "I looked for it, it isn't there" is a reason to record it. The
            // tag bar and the filter stay exactly as they were.
            TextButton(
              onPressed: onRecord,
              child: const Text('record it now'),
            ),
          ],
        ),
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
                color: context.colors.ink,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'photograph one small thing you like.\nstart the record.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.mutedText, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton(
                onPressed: onStart, child: const Text('record the first one')),
          ],
        ),
      ),
    );
  }
}
