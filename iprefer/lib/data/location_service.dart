import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';

/// A resolved position, optionally with a human-readable name.
@immutable
class PlaceFix {
  const PlaceFix({required this.latitude, required this.longitude, this.label});

  final double latitude;
  final double longitude;

  /// Lowercase place name ("fitzroy"), or null if reverse geocoding failed.
  final String? label;

  @override
  String toString() => label ?? '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
}

/// Wraps the platform location stack. Every method answers with a value or
/// null — never an exception — because location is an enhancement here, not a
/// requirement. A cold GPS or a declined prompt must not break recording.
abstract final class LocationService {

  /// True when we already hold permission. Does not prompt.
  static Future<bool> hasPermission() async {
    try {
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.always || p == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// Current position, or null if unavailable.
  ///
  /// [prompt] controls whether we may show the OS permission dialog. Callers
  /// that appear on their own use [passive] instead; this is for moments the
  /// user actively asked for — choosing a photo to record, or switching the
  /// timeline to "nearest" — where a dialog has a visible reason attached.
  static Future<PlaceFix?> current({
    bool prompt = false,
    bool reverseGeocode = true,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        if (!prompt) return null;
        permission = await Geolocator.requestPermission();
      }
      // Allow-list rather than deny-list: `unableToDetermine` used to fall
      // through to getCurrentPosition, which is itself a prompting call — so a
      // caller passing prompt: false could still raise the system dialog.
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: timeout,
        ),
      );

      final label = reverseGeocode
          ? await describe(position.latitude, position.longitude)
          : null;

      return PlaceFix(
        latitude: position.latitude,
        longitude: position.longitude,
        label: label,
      );
    } catch (_) {
      // Timeouts, platform errors, a device with no GPS — all the same to us.
      return null;
    }
  }

  /// A fix obtained without ever showing a permission dialog.
  ///
  /// Used by surfaces that appear on their own (the timeline's "you've been
  /// here before", the map's you-are-here dot) — they may *use* location the
  /// user has already granted, but must never demand it.
  ///
  /// Tries the OS cache first because it is instant, then falls back to a live
  /// read. The fallback matters: `getLastKnownPosition` is Android-oriented and
  /// commonly returns null on iOS, so cache-only would leave recall dead on the
  /// platform we care about most.
  static Future<PlaceFix?> passive({
    bool reverseGeocode = false,
    Duration timeout = const Duration(seconds: 6),
    Duration maxAge = const Duration(minutes: 10),
  }) async {
    try {
      if (!await hasPermission()) return null;
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      Position? position;
      try {
        final cached = await Geolocator.getLastKnownPosition();
        // An unbounded-age fix is worse than none here: fly Melbourne to
        // Sydney with location off and yesterday's fix would announce "you've
        // been in fitzroy before" while you stand in another city.
        if (cached != null &&
            DateTime.now().difference(cached.timestamp).abs() <= maxAge) {
          position = cached;
        }
      } catch (_) {
        position = null; // unsupported on this platform — fall through
      }

      position ??= await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: timeout,
        ),
      );

      final label = reverseGeocode
          ? await describe(position.latitude, position.longitude)
          : null;
      return PlaceFix(
        latitude: position.latitude,
        longitude: position.longitude,
        label: label,
      );
    } catch (_) {
      return null;
    }
  }

  /// Best-effort reverse geocode to a short, lowercase place name.
  ///
  /// Prefers the most specific useful name — a named venue or neighbourhood
  /// beats a city, which is too coarse to mean anything on a card.
  static Future<String?> describe(double latitude, double longitude) async {
    try {
      // geocoding 5.x moved the top-level functions onto a Geocoding instance.
      //
      // Bounded because the platform geocoders (CLGeocoder, android Geocoder)
      // can block indefinitely on a flaky network, and this call sits inside
      // current()/passive() whose callers latch on the awaited future — an
      // unbounded hang here froze "nearest" until app restart. The service's
      // contract is value-or-null; the timeout lands in the catch below.
      final marks = await geo.Geocoding()
          .placemarkFromCoordinates(latitude, longitude)
          .timeout(const Duration(seconds: 5));
      if (marks.isEmpty) return null;
      final m = marks.first;
      final candidates = <String?>[
        m.name,
        m.subLocality,
        m.locality,
        m.subAdministrativeArea,
        m.administrativeArea,
      ];
      for (final c in candidates) {
        final v = c?.trim();
        // Skip street-number-ish "names" — they read as noise on a card.
        if (v == null || v.isEmpty) continue;
        if (RegExp(r'^[\d\s\-]+$').hasMatch(v)) continue;
        return v.toLowerCase();
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
