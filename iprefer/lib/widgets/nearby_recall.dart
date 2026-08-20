import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../data/entry_store.dart';
import '../data/location_service.dart';
import '../models/entry.dart';
import '../screens/card_screen.dart';
import '../theme.dart';

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
    this.radiusMetres = 200,
    this.tags = const {},
  });

  final double radiusMetres;

  /// Narrows recall to the active tag filter, so "wine" + standing here asks
  /// "what wine did I like here?".
  final Set<String> tags;

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
    if (here == null || _dismissed) return const SizedBox.shrink();

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
              const Icon(Icons.place_outlined, size: 15, color: AppTheme.muted),
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
                    color: AppTheme.ink.withValues(alpha: 0.9),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: AppTheme.muted),
                visualDensity: VisualDensity.compact,
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
              itemCount: nearby.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _RecallChip(entry: nearby[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecallChip extends StatelessWidget {
  const _RecallChip({required this.entry});

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
                EntryStore.fileFor(entry),
                width: 64,
                height: 114,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 64,
                  height: 114,
                  color: const Color(0xFFEDEAE3),
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
                    DateFormat('MMM d, yyyy').format(entry.createdAt).toLowerCase(),
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
