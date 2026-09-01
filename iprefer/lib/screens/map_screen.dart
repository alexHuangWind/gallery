import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/entry_store.dart';
import '../data/location_service.dart';
import '../data/archive_view.dart';
import '../models/entry.dart';
import '../theme.dart';
import '../widgets/tag_filter_bar.dart';
import 'card_screen.dart';

/// Where you liked what. Every located entry is a dot on the map; tapping one
/// opens its card.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final _controller = MapController();
  LatLng? _me;
  int _findRequest = 0;

  /// Identifies the current pin set, so the camera is re-fitted when the tag
  /// filter changes the pins but not on every unrelated rebuild — which would
  /// yank the user's pan and zoom back on each store notification.
  String? _fittedSignature;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _findMe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // IndexedStack keeps this State for the whole session, so without this the
    // "you are here" dot stays frozen wherever the app was launched.
    if (state == AppLifecycleState.resumed) _findMe();
  }

  /// Passive: only shows the "you are here" dot if permission already exists.
  Future<void> _findMe() async {
    final request = ++_findRequest;
    final fix = await LocationService.passive();
    if (!mounted || fix == null || request != _findRequest) return;
    setState(() => _me = LatLng(fix.latitude, fix.longitude));
  }

  /// One camera-fit policy, referenced by both the initial [MapOptions] and
  /// every later re-fit — change these in one place or the first frame
  /// disagrees with every subsequent filter change.
  static const double _singlePointZoom = 15;
  static CameraFit _boundsFit(List<LatLng> points) => CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(64),
        maxZoom: 16,
      );

  /// Moves the camera when the pin set actually changes.
  ///
  /// `initialCameraFit` applies once at construction, so filtering down to a
  /// different city would otherwise leave the user staring at empty ocean.
  ///
  /// Called from build on purpose, and safe there: it is idempotent per pin
  /// signature (`_fittedSignature` is a plain field, not a notifier), and the
  /// actual camera move is deferred to after the frame. Don't "fix" the
  /// build-time call by moving it into a lifecycle hook — the pin set is
  /// derived from providers only available at build time.
  void _fitTo(List<LatLng> points) {
    final signature = points.map((p) => '${p.latitude},${p.longitude}').join(';');
    if (signature == _fittedSignature) return;
    _fittedSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || points.isEmpty) return;
      if (points.length == 1) {
        _controller.move(points.first, _singlePointZoom);
      } else {
        _controller.fitCamera(_boundsFit(points));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<EntryStore>();
    final view = context.watch<ArchiveView>();
    final active = view.effective(store.tagsByUse);
    // matching, not arrange: the map has its own geography and must not be
    // re-ordered by the timeline's nearest-first sort.
    final located = view
        .matching(store.withAnyTag(active))
        .where((e) => e.hasLocation)
        .toList();

    if (located.isEmpty) {
      // The camera has nothing to fit, and the FlutterMap widget is leaving
      // the tree — so forget what it was fitted to. Otherwise clearing the
      // search rebuilds the map, initialCameraFit re-applies, and _fitTo
      // no-ops on a signature that still matches: the user's pan and zoom
      // would be dropped with nothing here admitting it.
      _fittedSignature = null;
      return Column(
        children: [
          const TagFilterBar(),
          Expanded(
            child: _MapEmptyState(
              filtered: active.isNotEmpty,
              query: view.query.trim(),
            ),
          ),
        ],
      );
    }

    final points = [
      for (final e in located) LatLng(e.latitude!, e.longitude!),
    ];
    _fitTo(points);

    return Column(
      children: [
        const TagFilterBar(),
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _controller,
                options: MapOptions(
                  // A single point has degenerate bounds, so centre on it
                  // instead of asking the camera to fit a zero-area box.
                  initialCenter:
                      points.length == 1 ? points.first : const LatLng(0, 0),
                  initialZoom:
                      points.length == 1 ? _MapScreenState._singlePointZoom : 2,
                  initialCameraFit: points.length > 1
                      ? _MapScreenState._boundsFit(points)
                      : null,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    // OSM's tile policy requires identifying the client. Swap
                    // this layer for a paid tile source before shipping at
                    // volume.
                    userAgentPackageName: 'com.iprefer.app',
                    maxZoom: 19,
                  ),
                  if (_me != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _me!,
                          width: 18,
                          height: 18,
                          child: const _YouAreHereDot(),
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      for (final e in located)
                        Marker(
                          point: LatLng(e.latitude!, e.longitude!),
                          width: 54,
                          height: 54,
                          child: _EntryPin(entry: e),
                        ),
                    ],
                  ),
                ],
              ),
              // OSM's licence requires visible attribution.
              Positioned(
                right: 6,
                bottom: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    child: Text(
                      '© OpenStreetMap',
                      style: TextStyle(fontSize: 9, color: Colors.black87),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EntryPin extends StatelessWidget {
  const _EntryPin({required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CardScreen(entry: entry)),
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.file(
          context.read<EntryStore>().fileFor(entry),
          fit: BoxFit.cover,
          // The pin is 54 pt; decoding beyond ~3x that is pure memory waste.
          cacheWidth: 162,
          // Fixed, like the white border and the shadow above it: the pin
          // sits on OSM tiles, which are always the light raster set. Reading
          // the palette here would give two phones different pins for the
          // same missing photo.
          errorBuilder: (_, __, ___) =>
              const ColoredBox(color: Color(0xFF8A8580)),
        ),
      ),
    );
  }
}

class _YouAreHereDot extends StatelessWidget {
  const _YouAreHereDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF3B7DD8),
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4),
        ],
      ),
    );
  }
}

class _MapEmptyState extends StatelessWidget {
  const _MapEmptyState({this.filtered = false, this.query = ''});

  /// True when a tag filter is what emptied the map, rather than a genuinely
  /// empty archive — the two need different copy or the user thinks their
  /// entries vanished.
  final bool filtered;

  /// What is being searched for, if anything. Takes precedence over [filtered]
  /// in the copy: a search is the more recent, more deliberate act, so it is
  /// the explanation the user is looking for.
  final String query;

  @override
  Widget build(BuildContext context) {
    final searching = query.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              searching
                  ? 'nothing to put on the map'
                  : filtered
                      ? 'nothing under that, here'
                      : 'no places yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.serif,
                fontStyle: FontStyle.italic,
                fontSize: 26,
                color: context.colors.ink,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              searching
                  ? filtered
                      // Both filters are on, so neither alone explains it.
                      ? 'nothing matching “$query” under those tags has a place.'
                      : 'nothing matching “$query” has a place.'
                  : filtered
                      ? 'no tagged entries have a place yet.'
                      : 'record something while you are out,\nand it will land here.',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.colors.mutedText, height: 1.5),
            ),
            if (searching) ...[
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: () => context.read<ArchiveView>().clearQuery(),
                child: const Text('clear the search'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
