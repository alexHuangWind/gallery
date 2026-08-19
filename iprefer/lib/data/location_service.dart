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
class LocationService {
  const LocationService._();

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
  /// [prompt] controls whether we may show the OS permission dialog. The
  /// timeline's "you've been here before" check passes false — surfacing a
  /// system prompt on app launch, before the user has asked for anything, is
  /// the wrong trade. Compose passes true, because there the user has just
  /// chosen to record something.
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
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
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
  }) async {
    try {
      if (!await hasPermission()) return null;
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
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
      final marks = await geo.placemarkFromCoordinates(latitude, longitude);
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
