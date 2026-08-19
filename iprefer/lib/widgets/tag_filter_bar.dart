import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/entry_store.dart';
import '../data/tag_filter.dart';
import '../theme.dart';

/// Horizontal strip of tag chips that narrows both the timeline and the map.
///
/// Takes no height at all when the user has never tagged anything, so an
/// untagged archive looks exactly as it did before this feature existed.
class TagFilterBar extends StatelessWidget {
  const TagFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    final counts = context.watch<EntryStore>().tagCounts;
    final filter = context.watch<TagFilter>();

    if (counts.isEmpty) return const SizedBox.shrink();

    final tags = context.read<EntryStore>().tagsByUse;
    final active = filter.effective(tags);

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (active.isNotEmpty) ...[
            _Chip(
              label: 'all',
              selected: false,
              onTap: () => context.read<TagFilter>().clear(),
            ),
            const SizedBox(width: 8),
          ],
          for (final tag in tags) ...[
            _Chip(
              label: '$tag  ${counts[tag]}',
              selected: active.contains(tag),
              onTap: () => context.read<TagFilter>().toggle(tag),
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
