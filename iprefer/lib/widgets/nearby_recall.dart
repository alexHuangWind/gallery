import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/entry_store.dart';
import '../data/location_service.dart';
import '../theme.dart';
import 'entry_chip.dart';

/// "You've been here before."
///
/// On opening the timeline, if we already have location permission and the
/// user is standing near something they once recorded, that thing comes back.
/// This is the retention mechanic: the app quietly reintroduces you to your
/// own taste when you return to a place.
///
/// Deliberately passive about permission — it never prompts on launch. If we
/// don't already have the right, we simply show nothing.
class NearbyRecall extends StatefulWidget {
  const NearbyRecall({
    super.key,
    this.radiusMetres = kRecallRadiusMetres,
    this.tags = const {},
    this.suppressed = false,
  });

  final double radiusMetres;

  /// Narrows recall to the active tag filter, so "wine" + standing here asks
  /// "what wine did I like here?".
  final Set<String> tags;

  /// Hides the banner without unmounting it.
  ///
  /// A `if (…) …` in the parent's child list would tear this widget's State
  /// down instead: the dismissal is meant to last the session, and the
  /// location lookup behind it is a GPS read plus a reverse geocode. Passing
  /// the suppression in keeps both.
  final bool suppressed;

  @override
  State<NearbyRecall> createState() => _NearbyRecallState();
}

class _NearbyRecallState extends State<NearbyRecall>
    with WidgetsBindingObserver {
  PlaceFix? _here;
  bool _dismissed = false;
  int _lookRequest = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _look();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // HomeShell keeps this State alive for the whole session via IndexedStack,
    // so without re-reading on resume the recall would answer for wherever the
    // user launched the app this morning — which is exactly the case this
    // feature exists to catch.
    if (state == AppLifecycleState.resumed) {
      _dismissed = false;
      _look();
    }
  }

  Future<void> _look() async {
    final request = ++_lookRequest;
    // passive() returns null unless permission was already granted, so this
    // never shows a system dialog on launch.
    final fix = await LocationService.passive(reverseGeocode: true);
    if (!mounted || request != _lookRequest) return;
    setState(() => _here = fix);
  }

  @override
  Widget build(BuildContext context) {
    final here = _here;
    if (here == null || _dismissed || widget.suppressed) {
      return const SizedBox.shrink();
    }

    final nearby = context
        .watch<EntryStore>()
        .near(here.latitude, here.longitude,
            radiusMetres: widget.radiusMetres, tags: widget.tags);
    if (nearby.isEmpty) return const SizedBox.shrink();

    final place = here.label;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.place_outlined, size: 15, color: context.colors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  place == null
                      ? "you've been here before"
                      : "you've been in $place before",
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
                // 44pt minimum (iOS HIG) — compact density shrank the hit box
                // of the one control that makes this banner ignorable.
                constraints:
                    const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: EdgeInsets.zero,
                tooltip: 'dismiss',
                onPressed: () => setState(() => _dismissed = true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          EntryStrip(entries: nearby),
        ],
      ),
    );
  }
}
