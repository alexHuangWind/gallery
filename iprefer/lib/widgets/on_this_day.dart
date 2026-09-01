import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/entry_store.dart';
import '../models/entry.dart';
import '../theme.dart';
import 'entry_chip.dart';

/// "A year ago today."
///
/// The return-to-place banner pays you back for having recorded, by *place*.
/// This is the same mechanic on the other axis — the app quietly reintroduces
/// you to your own taste on the date you formed it.
///
/// Like the recall banner it takes zero height when it has nothing to say,
/// asks for no permission, and can be dismissed for the session.
class OnThisDay extends StatefulWidget {
  const OnThisDay({
    super.key,
    this.tags = const {},
    this.today,
    this.suppressed = false,
  });

  /// Overrides "now", so the states this widget exists for can be rendered
  /// without waiting a year or moving the device clock.
  final DateTime? today;

  /// Narrows to the active tag filter, so a lit "wine" chip asks "what wine
  /// did I like a year ago today?".
  final Set<String> tags;

  /// Hides the banner without unmounting it.
  ///
  /// A `if (…) …` in the parent's child list would tear this widget's State
  /// down instead: the dismissal is meant to last the session, and the
  /// location lookup behind it is a GPS read plus a reverse geocode. Passing
  /// the suppression in keeps both.
  final bool suppressed;


  @override
  State<OnThisDay> createState() => _OnThisDayState();
}

class _OnThisDayState extends State<OnThisDay> with WidgetsBindingObserver {
  bool _dismissed = false;
  late DateTime _today = widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(OnThisDay old) {
    super.didUpdateWidget(old);
    // A seam that ignores being changed is the one thing a seam must not do.
    if (widget.today != null && widget.today != old.today) {
      setState(() => _today = widget.today!);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // HomeShell keeps this alive for the whole session via IndexedStack, so an
    // app left open overnight would otherwise still be answering for
    // yesterday — on a feature whose entire subject is what day it is.
    if (state == AppLifecycleState.resumed) {
      if (widget.today != null) return; // pinned for a test
      final now = DateTime.now();
      if (now.day != _today.day ||
          now.month != _today.month ||
          now.year != _today.year) {
        setState(() {
          _today = now;
          _dismissed = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || widget.suppressed) return const SizedBox.shrink();

    final store = context.watch<EntryStore>();
    final anniversary = anniversaryOn(store.withAnyTag(widget.tags), _today);
    if (anniversary == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 15, color: context.colors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  anniversary.label,
                  style: TextStyle(
                    fontFamily: AppTheme.serif,
                    fontStyle: FontStyle.italic,
                    fontSize: 16,
                    color: context.colors.ink.withValues(alpha: 0.9),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 16, color: context.colors.muted),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: EdgeInsets.zero,
                tooltip: 'dismiss',
                onPressed: () => setState(() => _dismissed = true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 116,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: anniversary.entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => EntryChip(entry: anniversary.entries[i]),
            ),
          ),
        ],
      ),
    );
  }
}
