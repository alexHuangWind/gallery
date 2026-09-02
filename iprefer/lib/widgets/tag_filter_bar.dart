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

    // A horizontal ListView has no cross-axis extent of its own, so the strip
    // has to be told how tall it is — and 44 is only right at ordinary type
    // size. At the largest accessibility setting the chip's label alone is
    // taller than that and the top and bottom of every tag were clipped off.
    // Scaled by how much the chip's own type grew, not by scaling 44 (the
    // platform scaler is a curve; a "44 pt font" barely moves under it).
    final scaler = MediaQuery.textScalerOf(context);
    final growth = scaler.scale(_Chip.fontSize) / _Chip.fontSize;

    return SizedBox(
      height: 44 * growth,
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
              label: tag,
              count: counts[tag],
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
  /// The label size, shared with the strip's height calculation above.
  static const double fontSize = 13;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;

  /// How many entries carry the tag. Rendered smaller and quieter than the
  /// name so a long tag next to a two-digit number still reads as
  /// "name, count" rather than one run-on token.
  final int? count;

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? context.colors.paper : context.colors.ink;

    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? context.colors.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? context.colors.ink
                  : context.colors.muted.withValues(alpha: 0.35),
            ),
          ),
          child: Text.rich(
            TextSpan(
              text: label,
              style: TextStyle(fontSize: fontSize, color: fg),
              children: [
                if (count != null)
                  TextSpan(
                    text: '  $count',
                    style: TextStyle(
                      fontSize: 11,
                      color: fg.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
