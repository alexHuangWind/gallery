import 'dart:math' as math;

import 'package:hive/hive.dart';

/// One recorded preference: a photo, a line, a moment — and, when we could get
/// it, the place it happened.
///
/// The `text` holds only the user's words — the "I prefer" prefix lives in the
/// card layout, not the data, so it never gets double-rendered or edited away.
///
/// Location is *optional on purpose*: a denied permission or a cold GPS must
/// never block the recording habit. Everything downstream treats a missing fix
/// as normal, not as an error.
class Entry {
  Entry({
    required this.id,
    required this.localPath,
    required this.text,
    required this.createdAt,
    this.latitude,
    this.longitude,
    this.placeLabel,
  });

  final String id;

  /// Absolute path to the saved photo on disk (copied into app documents).
  final String localPath;

  /// The "I prefer ..." line, without the prefix.
  final String text;

  final DateTime createdAt;

  /// Where this was recorded. Null when location was unavailable or declined.
  final double? latitude;
  final double? longitude;

  /// Best-effort human name for the coordinates ("fitzroy", "dolores park").
  /// Null when reverse geocoding failed — the coordinates still stand.
  final String? placeLabel;

  bool get hasLocation => latitude != null && longitude != null;

  Entry copyWith({double? latitude, double? longitude, String? placeLabel}) {
    return Entry(
      id: id,
      localPath: localPath,
      text: text,
      createdAt: createdAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      placeLabel: placeLabel ?? this.placeLabel,
    );
  }

  /// Great-circle distance in metres from this entry to a point.
  ///
  /// Returns [double.infinity] for entries with no fix so they sort last and
  /// never satisfy a "within N metres" test.
  double metresTo(double lat, double lng) {
    if (!hasLocation) return double.infinity;
    return haversineMetres(latitude!, longitude!, lat, lng);
  }
}

/// Great-circle distance in metres between two lat/lng pairs.
///
/// Haversine is well within tolerance at the scale that matters here — we care
/// about "is this the same café", not survey accuracy.
double haversineMetres(double lat1, double lon1, double lat2, double lon2) {
  const earthRadius = 6371000.0; // metres
  double toRad(double deg) => deg * math.pi / 180.0;

  final dLat = toRad(lat2 - lat1);
  final dLon = toRad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(toRad(lat1)) * math.cos(toRad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Hand-written Hive adapter so the project builds without code generation
/// (no build_runner step needed for the MVP).
///
/// Reading is field-id based, so entries written before location existed (4
/// fields) still load — the absent ids simply come back null.
class EntryAdapter extends TypeAdapter<Entry> {
  @override
  final int typeId = 1;

  @override
  Entry read(BinaryReader reader) {
    final fields = <int, dynamic>{};
    final count = reader.readByte();
    for (var i = 0; i < count; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return Entry(
      id: fields[0] as String,
      localPath: fields[1] as String,
      text: fields[2] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(fields[3] as int),
      latitude: fields[4] as double?,
      longitude: fields[5] as double?,
      placeLabel: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Entry obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.localPath)
      ..writeByte(2)
      ..write(obj.text)
      ..writeByte(3)
      ..write(obj.createdAt.millisecondsSinceEpoch)
      ..writeByte(4)
      ..write(obj.latitude)
      ..writeByte(5)
      ..write(obj.longitude)
      ..writeByte(6)
      ..write(obj.placeLabel);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntryAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}
