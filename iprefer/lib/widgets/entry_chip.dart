import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/entry_store.dart';
import '../models/entry.dart';
import '../screens/card_screen.dart';
import '../theme.dart';

/// One entry as a small horizontal card: photo, the line, the date.
///
/// Shared by both banners that resurface old entries — "you've been here
/// before" and "a year ago today". They were byte-identical copies, which
/// meant the next fix to the decode cap or the tap affordance would land on
/// one and quietly miss the other.
class EntryChip extends StatelessWidget {
  const EntryChip({super.key, required this.entry});

  /// The size the chip's line is set in. [EntryStrip] derives its height from
  /// this, so the two cannot drift apart.
  static const double lineFontSize = 14;

  final Entry entry;

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CardScreen(entry: entry)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A bare GestureDetector announces nothing: a screen reader met three
    // unrelated nodes here — an unlabelled photo, a line, a date — none of
    // which said it could be opened. The parts are excluded and re-announced
    // as the one button the chip actually is.
    return Semantics(
      button: true,
      label: '${entry.text}, ${quietDate(entry.createdAt)}',
      excludeSemantics: true,
      onTap: () => _open(context),
      child: GestureDetector(
        onTap: () => _open(context),
        child: SizedBox(
          width: 170,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  context.read<EntryStore>().fileFor(entry),
                  width: 64,
                  height: 114,
                  fit: BoxFit.cover,
                  // Painted at 64pt; capping the decode near 3x that keeps a
                  // full-resolution photo out of the image cache.
                  cacheWidth: 200,
                  errorBuilder: (context, _, __) => Container(
                    width: 64,
                    height: 114,
                    color: context.colors.placeholder,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.serif,
                        fontSize: lineFontSize,
                        height: 1.25,
                        color: context.colors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      quietDate(entry.createdAt),
                      style:
                          TextStyle(fontSize: 10, color: context.colors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The horizontal run of [EntryChip]s under both recall banners.
///
/// Shared for the same reason the chip itself is: the two banners had
/// identical strips, so a fix to one silently missed the other.
class EntryStrip extends StatelessWidget {
  const EntryStrip({super.key, required this.entries});

  /// What a chip measures at text scale 1.0 — the 114pt photo plus the
  /// breathing room its four-line column needs beside it.
  static const double baseHeight = 116;

  final List<Entry> entries;

  @override
  Widget build(BuildContext context) {
    // A horizontal ListView has no cross-axis extent of its own, so the height
    // has to be stated. Stating it as a constant 116 clipped the chips the
    // moment the system type grew: four scaled lines plus the date measure
    // past 160 at double size, and the strip is the whole point of the
    // feature this app is built around.
    //
    // Scaled off the chip's own type rather than by scaling 116 directly:
    // the platform's scaler is a curve, not a factor, and it barely moves
    // something the size of "116pt text" — the box would have stayed put
    // while the type inside it grew.
    final scaler = MediaQuery.textScalerOf(context);
    final growth = scaler.scale(EntryChip.lineFontSize) / EntryChip.lineFontSize;

    return SizedBox(
      height: baseHeight * growth,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        // Keyed so a strip that regains an entry — a sync pull, a tag filter
        // narrowing — reuses the right element instead of re-decoding.
        itemBuilder: (_, i) =>
            EntryChip(key: ValueKey<String>(entries[i].id), entry: entries[i]),
      ),
    );
  }
}
