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

    final row = Row(
      children: [
        Text(
          'sorted by',
          style: TextStyle(color: context.colors.muted, fontSize: 12),
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
          onTap: () => context.read<ArchiveView>().setSort(ArchiveSort.nearest),
        ),
        const SizedBox(width: 10),
        if (view.sort == ArchiveSort.nearest)
          Expanded(child: _NearestStatus(view: view)),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      // The label and the two pills are as wide as their type: at the larger
      // system text sizes they outgrow a phone, and on `newest` there isn't
      // even a flexible child left to absorb the excess — the row simply
      // overflowed. It scrolls instead.
      //
      // The pair below is what keeps that from costing anything at ordinary
      // type sizes: inside a scroll view the row would be handed unbounded
      // width, which both breaks [Expanded] and would let a long place label
      // run on instead of ellipsing. IntrinsicWidth asks the row how wide it
      // wants to be and the minWidth floors that at the viewport, so as long
      // as the controls fit, the row is laid out at exactly the width it had
      // before and nothing scrolls.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: IntrinsicWidth(child: row),
          ),
        ),
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
    final style = TextStyle(color: context.colors.muted, fontSize: 11);

    if (view.locating) {
      return Row(
        children: [
          const SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(strokeWidth: 1.4),
          ),
          const SizedBox(width: 8),
          Flexible(child: Text('finding you', style: style)),
        ],
      );
    }

    if (view.originUnavailable) {
      return Row(
        children: [
          Flexible(
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
          color: selected ? context.colors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? context.colors.ink
                : context.colors.muted.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? context.colors.paper : context.colors.ink,
          ),
        ),
      ),
    );
  }
}
