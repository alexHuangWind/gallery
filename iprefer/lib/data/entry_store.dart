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

  /// Absolute path of the photos directory, resolved once at [open].
  ///
  /// Entries store only a file *name* (see [persistPhoto]); this is what turns
  /// one back into a file.
  static String? _photosRoot;

  /// Opens Hive and the entries box. Call once during app startup.
  static Future<EntryStore> open() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(EntryAdapter());
    }
    final docs = await getApplicationDocumentsDirectory();
    _photosRoot = p.join(docs.path, 'photos');
    final box = await Hive.openBox<Entry>(_boxName);
    return EntryStore._(box);
  }

  /// Resolves an entry's photo to a file.
  ///
  /// iOS regenerates the app container's UUID on reinstall and on some OS
  /// updates, so an absolute path stored today is dangling tomorrow and the
  /// entire archive turns to grey rectangles. New entries therefore store just
  /// the file name; the absolute branch is kept so records written before this
  /// change still resolve.
  static File fileFor(Entry entry) {
    final stored = entry.localPath;
    if (p.isAbsolute(stored) || _photosRoot == null) return File(stored);
    return File(p.join(_photosRoot!, stored));
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
      // toSet(): one entry counts once per tag even if its list repeats one.
      for (final t in e.tags.toSet()) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Entries carrying *any* of [tags] (OR, not AND), newest first.
  ///
  /// Selecting more tags widens the archive rather than narrowing it: picking
  /// "wine" and "dish" shows everything under either shelf. An empty selection
  /// means no filter at all, so everything comes back.
  List<Entry> withAnyTag(Set<String> tags) => entriesWithAnyTag(entries, tags);

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
    Set<String> tags = const {},
  }) {
    final hits = withAnyTag(tags)
        .where((e) => e.metresTo(latitude, longitude) <= radiusMetres);
    return sortedByDistanceFrom(hits, latitude, longitude);
  }

  Entry? byId(String id) => _box.get(id);

  Future<void> add(Entry entry) async {
    await _box.put(entry.id, entry);
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final entry = _box.get(id);

    // Record first, photo second. If this is interrupted between the two, an
    // orphaned file is invisible and costs only disk, whereas an orphaned
    // record is a permanently broken tile the app offers no way to repair.
    await _box.delete(id);

    if (entry != null) {
      try {
        final file = fileFor(entry);
        if (file.existsSync()) {
          await file.delete();
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Copies a picked photo into app-private storage and returns its file name.
  ///
  /// We never reference the picker's temp/cache path directly — it can be
  /// reclaimed by the OS — so the card always has a stable file to render.
  static Future<String> persistPhoto(String sourcePath, String entryId) async {
    final docs = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(docs.path, 'photos'));
    if (!photosDir.existsSync()) {
      photosDir.createSync(recursive: true);
    }
    _photosRoot = photosDir.path;
    final ext = p.extension(sourcePath).isNotEmpty ? p.extension(sourcePath) : '.jpg';
    final name = '$entryId$ext';
    await File(sourcePath).copy(p.join(photosDir.path, name));
    // Name only — see [fileFor] for why the absolute path must not be stored.
    return name;
  }

  /// Deletes a photo that no record ended up referencing.
  ///
  /// Saving copies the photo before writing the record; if the write then
  /// fails, that copy would otherwise sit in app documents forever.
  static Future<void> discardPhoto(String storedName) async {
    try {
      final root = _photosRoot;
      if (root == null) return;
      final file = File(p.join(root, storedName));
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  /// Writes exported PNG bytes (the rendered card) to a temp file for sharing.
  static Future<File> writeShareablePng(Uint8List bytes, String entryId) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'iprefer_$entryId.png'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
