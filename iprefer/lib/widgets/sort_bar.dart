import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/archive_view.dart';
import '../theme.dart';

/// Chooses between newest-first and nearest-first.
///
/// Distance sorting needs a fix, and asking for one here is fair game: the user
/// just tapped "nearest", so the permission prompt has an obvious reason. When
/// no fix can be had, the mode stays selected and says why rather than snapping
/// back to newest, which would read as a broken control.
class SortBar extends StatelessWidget {
  const SortBar({super.key});

  @override
  Widget build(BuildContext context) {
    final view = context.watch<ArchiveView>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          const Text(
            'sorted by',
            style: TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          const SizedBox(width: 10),
          _Option(
            label: 'newest',
            selected: view.sort == ArchiveSort.newest,
            onTap: () => context.read<ArchiveView>().setSort(ArchiveSort.newest),
          ),
          const SizedBox(width: 6),
          _Option(
            label: 'nearest',
            selected: view.sort == ArchiveSort.nearest,
            onTap: () =>
                context.read<ArchiveView>().setSort(ArchiveSort.nearest),
          ),
          const SizedBox(width: 10),
          if (view.sort == ArchiveSort.nearest)
            Expanded(child: _NearestStatus(view: view)),
        ],
      ),
    );
  }
}

/// Says where "nearest" is being measured from, or why it can't be.
class _NearestStatus extends StatelessWidget {
  const _NearestStatus({required this.view});

  final ArchiveView view;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: AppTheme.muted, fontSize: 11);

    if (view.locating) {
      return const Row(
        children: [
          SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(strokeWidth: 1.4),
          ),
          SizedBox(width: 8),
          Flexible(child: Text('finding you', style: style)),
        ],
      );
    }

    if (view.originUnavailable) {
      return Row(
        children: [
          const Flexible(
            child: Text('needs your location',
                style: style, overflow: TextOverflow.ellipsis),
          ),
          TextButton(
            onPressed: () => context.read<ArchiveView>().refreshOrigin(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              // Small label, honest hit area — this is the recovery control
              // after a denied location; shrinkWrap made it a precision tap.
              minimumSize: const Size(48, 40),
            ),
            child: const Text('try again', style: TextStyle(fontSize: 11)),
          ),
        ],
      );
    }

    final label = view.origin?.label;
    if (label == null) return const SizedBox.shrink();
    return Text(
      'from $label',
      style: style,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppTheme.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.ink : AppTheme.muted.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppTheme.paper : AppTheme.ink,
          ),
        ),
      ),
    );
  }
}
