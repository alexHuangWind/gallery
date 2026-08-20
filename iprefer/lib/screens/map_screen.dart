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

  /// Moves the camera when the pin set actually changes.
  ///
  /// `initialCameraFit` applies once at construction, so filtering down to a
  /// different city would otherwise leave the user staring at empty ocean.
  void _fitTo(List<LatLng> points) {
    final signature = points.map((p) => '${p.latitude},${p.longitude}').join(';');
    if (signature == _fittedSignature) return;
    _fittedSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || points.isEmpty) return;
      if (points.length == 1) {
        _controller.move(points.first, 15);
      } else {
        _controller.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(64),
            maxZoom: 16,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<EntryStore>();
    final active = context.watch<ArchiveView>().effective(store.tagsByUse);
    final located =
        store.withAnyTag(active).where((e) => e.hasLocation).toList();

    if (located.isEmpty) {
      return Column(
        children: [
          const TagFilterBar(),
          Expanded(child: _MapEmptyState(filtered: active.isNotEmpty)),
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
                  initialZoom: points.length == 1 ? 15 : 2,
                  initialCameraFit: points.length > 1
                      ? CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(points),
                          padding: const EdgeInsets.all(64),
                          maxZoom: 16,
                        )
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
          EntryStore.fileFor(entry),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: AppTheme.muted),
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
  const _MapEmptyState({this.filtered = false});

  /// True when a tag filter is what emptied the map, rather than a genuinely
  /// empty archive — the two need different copy or the user thinks their
  /// entries vanished.
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              filtered ? 'nothing under that, here' : 'no places yet',
              style: const TextStyle(
                fontFamily: AppTheme.serif,
                fontStyle: FontStyle.italic,
                fontSize: 26,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              filtered
                  ? 'no tagged entries have a place yet.'
                  : 'record something while you are out,\nand it will land here.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
