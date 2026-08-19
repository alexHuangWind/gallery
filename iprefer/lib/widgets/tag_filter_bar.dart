import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/entry_store.dart';
import '../data/archive_view.dart';
import '../theme.dart';

/// Horizontal strip of tag chips that filters both the timeline and the map.
///
/// Selecting more tags shows *more*, not less (OR), so several chips can be lit
/// at once and "all" clears them.
///
/// Takes no height at all when the user has never tagged anything, so an
/// untagged archive looks exactly as it did before this feature existed.
class TagFilterBar extends StatelessWidget {
  const TagFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    final counts = context.watch<EntryStore>().tagCounts;
    final view = context.watch<ArchiveView>();

    if (counts.isEmpty) return const SizedBox.shrink();

    final tags = context.read<EntryStore>().tagsByUse;
    final active = view.effective(tags);

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Keyed off the raw selection, not `active`: a selection whose tag
          // has since been deleted is invisible here but still live, and this
          // is the only control that can clear it.
          if (!view.isEmpty) ...[
            _Chip(
              label: 'all',
              selected: false,
              onTap: () => context.read<ArchiveView>().clear(),
            ),
            const SizedBox(width: 8),
          ],
          for (final tag in tags) ...[
            _Chip(
              label: '$tag  ${counts[tag]}',
              selected: active.contains(tag),
              onTap: () => context.read<ArchiveView>().toggle(tag),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppTheme.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppTheme.ink : AppTheme.muted.withOpacity(0.35),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected ? AppTheme.paper : AppTheme.ink,
            ),
          ),
        ),
      ),
    );
  }
}
