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

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CardScreen(entry: entry)),
      ),
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
                errorBuilder: (_, __, ___) => Container(
                  width: 64,
                  height: 114,
                  color: AppTheme.placeholder,
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
                    style: const TextStyle(
                      fontFamily: AppTheme.serif,
                      fontSize: 14,
                      height: 1.25,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    quietDate(entry.createdAt),
                    style: const TextStyle(fontSize: 10, color: AppTheme.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
