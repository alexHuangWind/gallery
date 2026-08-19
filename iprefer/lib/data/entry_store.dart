import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/entry.dart';

/// Hive-backed local store for [Entry] records. CRUD only — no cloud, no auth.
///
/// Notifies listeners on every mutation so the timeline rebuilds.
class EntryStore extends ChangeNotifier {
  EntryStore._(this._box);

  static const String _boxName = 'entries';

  final Box<Entry> _box;

  /// Opens Hive and the entries box. Call once during app startup.
  static Future<EntryStore> open() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(EntryAdapter());
    }
    final box = await Hive.openBox<Entry>(_boxName);
    return EntryStore._(box);
  }

  /// All entries, newest first.
  List<Entry> get entries {
    final all = _box.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all;
  }

  bool get isEmpty => _box.isEmpty;

  /// Entries that carry a location fix, newest first.
  List<Entry> get located => entries.where((e) => e.hasLocation).toList();

  /// Every tag in use, most-used first, ties broken alphabetically.
  ///
  /// Drives the compose suggestions, so the shelves the user actually reaches
  /// for float to the front instead of us guessing for them.
  List<String> get tagsByUse {
    final counts = tagCounts;
    final names = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return names;
  }

  /// How many entries carry each tag.
  Map<String, int> get tagCounts {
    final counts = <String, int>{};
    for (final e in _box.values) {
      for (final t in e.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Entries carrying every tag in [tags] (AND, not OR), newest first.
  ///
  /// AND is the right default here: the archive is small and personal, so
  /// stacking "wine" and "dish" should narrow toward one memory rather than
  /// pile up two unrelated shelves.
  List<Entry> withTags(Set<String> tags) {
    if (tags.isEmpty) return entries;
    return entries.where((e) => tags.every(e.hasTag)).toList();
  }

  /// Entries recorded within [radiusMetres] of a point, nearest first.
  ///
  /// This is what powers "you've been here before": stand where you once stood
  /// and the thing you liked here comes back. The default radius is a block or
  /// so — tight enough to mean *this* place, loose enough to survive the drift
  /// of a consumer GPS.
  List<Entry> near(
    double latitude,
    double longitude, {
    double radiusMetres = 200,
    String? excludeId,
    Set<String> tags = const {},
  }) {
    final hits = <Entry>[];
    for (final e in withTags(tags)) {
      if (e.id == excludeId) continue;
      final d = e.metresTo(latitude, longitude);
      if (d <= radiusMetres) hits.add(e);
    }
    hits.sort((a, b) => a
        .metresTo(latitude, longitude)
        .compareTo(b.metresTo(latitude, longitude)));
    return hits;
  }

  Entry? byId(String id) => _box.get(id);

  Future<void> add(Entry entry) async {
    await _box.put(entry.id, entry);
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final entry = _box.get(id);
    if (entry != null) {
      // Best-effort cleanup of the on-disk photo; the record is the source of
      // truth, so a failed file delete must not block removing the entry.
      try {
        final file = File(entry.localPath);
        if (file.existsSync()) {
          await file.delete();
        }
      } catch (_) {}
    }
    await _box.delete(id);
    notifyListeners();
  }

  /// Copies a picked photo into app-private storage and returns the new path.
  ///
  /// We never reference the picker's temp/cache path directly — it can be
  /// reclaimed by the OS — so the card always has a stable file to render.
  static Future<String> persistPhoto(String sourcePath, String entryId) async {
    final dir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(dir.path, 'photos'));
    if (!photosDir.existsSync()) {
      photosDir.createSync(recursive: true);
    }
    final ext = p.extension(sourcePath).isNotEmpty ? p.extension(sourcePath) : '.jpg';
    final dest = p.join(photosDir.path, '$entryId$ext');
    await File(sourcePath).copy(dest);
    return dest;
  }

  /// Writes exported PNG bytes (the rendered card) to a temp file for sharing.
  static Future<File> writeShareablePng(Uint8List bytes, String entryId) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'iprefer_$entryId.png'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
