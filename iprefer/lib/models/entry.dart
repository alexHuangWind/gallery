import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
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
    List<String>? tags,
  }) : tags = tags == null ? const [] : normalizeTags(tags);

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

  /// What kind of thing this is: "wine", "dish", "grocery".
  ///
  /// Normalized by the constructor, not merely by convention — every path in
  /// and out of storage runs through [normalizeTags], so "Wine" and " wine "
  /// cannot split one shelf into two even if a caller forgets. Empty is normal.
  final List<String> tags;

  bool get hasLocation => latitude != null && longitude != null;

  /// Normalizes the query the same way the stored tags were normalized —
  /// anything less and `hasTag('#Wine')` misses a stored `wine`, which would
  /// let a lit filter chip match nothing.
  bool hasTag(String tag) {
    final normalized = normalizeTags([tag]);
    return normalized.isNotEmpty && tags.contains(normalized.first);
  }

  /// Great-circle distance in metres from this entry to a point.
  ///
  /// Returns [double.infinity] for entries with no fix so they sort last and
  /// never satisfy a "within N metres" test.
  double metresTo(double lat, double lng) {
    if (!hasLocation) return double.infinity;
    return haversineMetres(latitude!, longitude!, lat, lng);
  }

  /// What the photo is called on the wire, and its key in object storage:
  /// always `<id>.<ext>`.
  ///
  /// [localPath] is normally already exactly this. Records written before the
  /// name-not-path change hold an absolute path instead, so the name is
  /// derived from the id rather than read off the path — otherwise those
  /// entries could never sync, and a stored path would leak a device's
  /// directory layout to the server.
  String get syncPhotoName {
    final slash = localPath.lastIndexOf('/');
    final base = slash >= 0 ? localPath.substring(slash + 1) : localPath;
    final dot = base.lastIndexOf('.');
    final ext = dot > 0 ? base.substring(dot).toLowerCase() : '.jpg';
    return '$id$ext';
  }

  /// The wire shape. Mirrors `server/src/types.ts` — keep the two in step.
  Map<String, Object?> toSyncJson() => {
        'id': id,
        'text': text,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'latitude': latitude,
        'longitude': longitude,
        'placeLabel': placeLabel,
        'tags': tags,
        'photoName': syncPhotoName,
      };

  /// Rebuilds an entry that arrived from the server.
  ///
  /// [localPath] becomes the photo *name*: the file may not be on this device
  /// yet, and the sync service downloads it under exactly that name.
  static Entry fromSyncJson(Map<String, Object?> json) {
    final rawTags = json['tags'];
    return Entry(
      id: json['id']! as String,
      localPath: (json['photoName'] as String?) ?? '${json['id']}.jpg',
      text: (json['text'] as String?) ?? '',
      createdAt:
          DateTime.fromMillisecondsSinceEpoch((json['createdAt'] as num).toInt()),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      placeLabel: json['placeLabel'] as String?,
      tags: rawTags is List ? rawTags.map((t) => '$t').toList() : const [],
    );
  }
}

/// Entries carrying *any* of [tags] (OR), preserving the incoming order.
///
/// An empty selection means "no filter", so everything comes back. Lives here
/// as a pure function so both [EntryStore] and its tests exercise this exact
/// code rather than a copy that can drift.
List<Entry> entriesWithAnyTag(Iterable<Entry> entries, Set<String> tags) {
  if (tags.isEmpty) return entries.toList();
  return entries.where((e) => tags.any(e.hasTag)).toList();
}

/// What the archive has to say about today's date, if anything.
@immutable
class Anniversary {
  const Anniversary({required this.entries, required this.label});

  /// Newest first, all from the same anniversary.
  final List<Entry> entries;

  /// Reads as a sentence opener: "a year ago today".
  final String label;
}

/// Entries recorded on this date in an earlier year — or, failing that, on
/// this day of an earlier month.
///
/// The recall banner pays the user back for having recorded by *place*; this
/// is the same mechanic on the other axis. The month fallback exists because
/// a year is a long time to wait for a feature to exist at all: a young
/// archive would otherwise be silent until its first birthday.
///
/// The most distant match wins. "A year ago today" is a better thing to be
/// handed than "a month ago today", and once both exist the older one is the
/// one you've had time to forget.
Anniversary? anniversaryOn(Iterable<Entry> entries, DateTime today) {
  final byYears = <int, List<Entry>>{};
  final byMonths = <int, List<Entry>>{};

  for (final entry in entries) {
    final at = entry.createdAt;
    if (!at.isBefore(DateTime(today.year, today.month, today.day))) continue;

    if (at.month == today.month && at.day == today.day) {
      final years = today.year - at.year;
      if (years >= 1) (byYears[years] ??= []).add(entry);
      continue;
    }
    if (at.day == today.day) {
      final months = (today.year - at.year) * 12 + (today.month - at.month);
      if (months >= 1) (byMonths[months] ??= []).add(entry);
    }
  }

  String plural(int n, String unit) =>
      n == 1 ? 'a $unit ago today' : '$n ${unit}s ago today';

  if (byYears.isNotEmpty) {
    final oldest = byYears.keys.reduce((a, b) => a > b ? a : b);
    return Anniversary(
      entries: _newestFirst(byYears[oldest]!),
      label: plural(oldest, 'year'),
    );
  }
  if (byMonths.isNotEmpty) {
    final oldest = byMonths.keys.reduce((a, b) => a > b ? a : b);
    return Anniversary(
      entries: _newestFirst(byMonths[oldest]!),
      label: plural(oldest, 'month'),
    );
  }
  return null;
}

List<Entry> _newestFirst(List<Entry> entries) =>
    entries..sort((a, b) => b.createdAt.compareTo(a.createdAt));

/// Entries ordered by distance from a point, closest first.
///
/// Entries with no fix tie at infinity and are held newest-first by an explicit
/// tiebreak — Dart's [List.sort] is not stable, so without it they would
/// reshuffle on every rebuild.
List<Entry> sortedByDistanceFrom(
  Iterable<Entry> entries,
  double latitude,
  double longitude,
) {
  // Decorate-sort-undecorate: the comparator would otherwise recompute two
  // square roots per comparison, and this runs on every archive rebuild.
  final decorated = [
    for (final e in entries) (entry: e, metres: e.metresTo(latitude, longitude)),
  ]..sort((a, b) {
      final byDistance = a.metres.compareTo(b.metres);
      if (byDistance != 0) return byDistance;
      return b.entry.createdAt.compareTo(a.entry.createdAt);
    });
  return [for (final d in decorated) d.entry];
}

/// Cleans user-entered tags into the one form we store and compare.
///
/// Lowercase (the app's voice is lowercase anyway), whitespace collapsed, a
/// leading `#` dropped, deduped, and capped at 24 *characters* so a stray paste
/// can't produce a tag that breaks every layout it lands in. Order is
/// preserved.
List<String> normalizeTags(Iterable<String> raw) {
  const maxLength = 24;
  final seen = <String>{};
  final out = <String>[];
  for (final candidate in raw) {
    var value = candidate.trim().toLowerCase();
    while (value.startsWith('#')) {
      value = value.substring(1).trimLeft();
    }
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value.isEmpty) continue;
    // Cap by runes, not by `length`/`substring`, which count UTF-16 code
    // units: an emoji costs two, so a code-unit cut can land between the
    // halves of a surrogate pair. Dropping the split pair is not enough
    // either — "…🍷" and "…🍺" then both truncate to the same prefix and
    // silently become one shelf. Counting characters keeps them distinct.
    final runes = value.runes;
    if (runes.length > maxLength) {
      value = String.fromCharCodes(runes.take(maxLength)).trim();
    }
    if (value.isEmpty) continue;
    if (seen.add(value)) out.add(value);
  }
  return out;
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

  // For near-antipodal points `a` exceeds 1 by a floating-point ulp, and
  // sqrt(1 - a) is then NaN. NaN outranks infinity in Dart's compareTo, so an
  // entry on the far side of the globe would sort *behind* entries with no
  // location at all. Clamp, and use asin so there is no 1 - a term to go
  // negative in the first place.
  final a = (math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(toRad(lat1)) *
              math.cos(toRad(lat2)) *
              math.sin(dLon / 2) *
              math.sin(dLon / 2))
      .clamp(0.0, 1.0);
  return earthRadius * 2 * math.asin(math.sqrt(a));
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
    // Every cast here is defensive on purpose. `openBox` is non-lazy: it
    // deserializes the whole archive at startup, so a single torn record with a
    // hard cast would throw before runApp and leave the user with a black
    // screen and no way back to their entries.
    return Entry(
      id: fields[0] as String? ?? '',
      localPath: fields[1] as String? ?? '',
      text: fields[2] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch((fields[3] as int?) ?? 0),
      latitude: fields[4] as double?,
      longitude: fields[5] as double?,
      placeLabel: fields[6] as String?,
      // Absent for entries written before tags existed — an empty list, not an
      // error. Hive hands back List<dynamic>, so copy into a typed list.
      tags: fields[7] is List
          ? (fields[7] as List).whereType<String>().toList()
          : const [],
    );
  }

  @override
  void write(BinaryWriter writer, Entry obj) {
    writer
      ..writeByte(8)
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
      ..write(obj.placeLabel)
      ..writeByte(7)
      ..write(obj.tags);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntryAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}
