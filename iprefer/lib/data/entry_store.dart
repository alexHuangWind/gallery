import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/entry.dart';
import 'sync/sync_outbox.dart';

/// How close "you've been here before" considers *here*. One product decision,
/// one constant: both the store's default and the recall widget's read this,
/// so the radius cannot silently fork between the two.
const double kRecallRadiusMetres = 200;

/// Hive-backed local store for [Entry] records. CRUD only — no cloud, no auth.
///
/// Notifies listeners on every mutation so the timeline rebuilds.
class EntryStore extends ChangeNotifier {
  EntryStore._(this._box, this.photosRoot, this._outbox);

  /// Test seam: a store over an already-open box and an existing directory,
  /// skipping the platform channels [open] needs. Production code must keep
  /// going through [open].
  @visibleForTesting
  EntryStore.forTest(this._box, {required this.photosRoot, SyncOutbox? outbox})
      : _outbox = outbox;

  /// Where local changes queue up for the server. Null means sync is off, and
  /// the store behaves exactly as it did before there was a backend.
  final SyncOutbox? _outbox;

  static const String _boxName = 'entries';

  final Box<Entry> _box;

  /// Absolute path of the photos directory, resolved once at [open].
  ///
  /// Entries store only a file *name* (see [_persistPhoto]); this is what
  /// turns one back into a file.
  final String photosRoot;

  /// Opens Hive and the entries box. Call once during app startup.
  static Future<EntryStore> open({SyncOutbox? outbox}) async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(EntryAdapter());
    }
    final docs = await getApplicationDocumentsDirectory();
    final box = await Hive.openBox<Entry>(_boxName);
    return EntryStore._(box, p.join(docs.path, 'photos'), outbox);
  }

  /// Resolves an entry's photo to a file.
  ///
  /// iOS regenerates the app container's UUID on reinstall and on some OS
  /// updates, so an absolute path stored today is dangling tomorrow and the
  /// entire archive turns to grey rectangles. New entries therefore store just
  /// the file name; the absolute branch is kept so records written before this
  /// change still resolve.
  File fileFor(Entry entry) {
    final stored = entry.localPath;
    if (p.isAbsolute(stored)) return File(stored);
    return File(p.join(photosRoot, stored));
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
    double radiusMetres = kRecallRadiusMetres,
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

  /// The whole save transaction: copy the photo into app storage, then write
  /// the record. This is the only multi-step write in the app, and its
  /// invariant lives here rather than in a screen so it stays testable.
  ///
  /// Ordering contract: the photo is copied *before* the record exists, so a
  /// crash between the two leaves an invisible orphan file, never a broken
  /// record. The rollback below can only run when the record write failed —
  /// the try spans nothing after the put — so it can never delete the photo
  /// of an entry that made it into the box.
  Future<Entry> create({
    required String sourcePhotoPath,
    required String text,
    required DateTime createdAt,
    double? latitude,
    double? longitude,
    String? placeLabel,
    List<String> tags = const [],
  }) async {
    final id = const Uuid().v4();
    final storedName = await _persistPhoto(sourcePhotoPath, id);
    // Everything after the copy sits inside the rollback try — including the
    // Entry construction, so a future validation added there cannot silently
    // open an orphan-photo window.
    final Entry entry;
    try {
      entry = Entry(
        id: id,
        localPath: storedName,
        text: text,
        createdAt: createdAt,
        latitude: latitude,
        longitude: longitude,
        placeLabel: placeLabel,
        tags: tags,
      );
      await _box.put(id, entry);
    } catch (_) {
      await _discardPhoto(storedName);
      rethrow;
    }
    notifyListeners();
    // After the record is safely down: the queue is a convenience, and losing
    // an enqueue costs a delayed backup, never an entry.
    await _outbox?.enqueueCreate(entry);
    return entry;
  }

  Future<void> delete(String id) async {
    final entry = _box.get(id);
    await _deleteLocally(id, entry);
    await _outbox?.enqueueDelete(id, photoName: entry?.syncPhotoName);
  }

  Future<void> _deleteLocally(String id, Entry? entry) async {
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

  // --- writes that came FROM the server ------------------------------------
  //
  // These deliberately skip the outbox. Routing a pulled op through the
  // ordinary create/delete would queue it straight back to the server and
  // bounce it between devices forever.

  Future<void> applyRemoteCreate(Entry entry) async {
    await _box.put(entry.id, entry);
    notifyListeners();
  }

  Future<void> applyRemoteDelete(String id) async {
    final entry = _box.get(id);
    if (entry == null) return; // already gone here; nothing to undo
    await _deleteLocally(id, entry);
  }

  // --- photo bytes, for the sync service -----------------------------------

  bool hasPhoto(Entry entry) => fileFor(entry).existsSync();

  File _photoByName(String name) => File(p.join(photosRoot, name));

  /// Null when the file isn't there — a delete that raced the upload, or an
  /// OS reclaim. The caller drops the pending upload rather than retrying.
  Future<Uint8List?> readPhotoBytes(String name) async {
    final file = _photoByName(name);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  Future<void> writePhotoBytes(String name, Uint8List bytes) async {
    final dir = Directory(photosRoot);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await _photoByName(name).writeAsBytes(bytes, flush: true);
  }

  /// Copies a picked photo into app-private storage and returns its file name.
  ///
  /// We never reference the picker's temp/cache path directly — it can be
  /// reclaimed by the OS — so the card always has a stable file to render.
  Future<String> _persistPhoto(String sourcePath, String entryId) async {
    final photosDir = Directory(photosRoot);
    // Re-created on every save, not assumed from open(): the OS may clear it.
    if (!photosDir.existsSync()) {
      photosDir.createSync(recursive: true);
    }
    final ext =
        p.extension(sourcePath).isNotEmpty ? p.extension(sourcePath) : '.jpg';
    final name = '$entryId$ext';
    await File(sourcePath).copy(p.join(photosDir.path, name));
    // Name only — see [fileFor] for why the absolute path must not be stored.
    return name;
  }

  /// Deletes a photo that no record ended up referencing.
  Future<void> _discardPhoto(String storedName) async {
    try {
      final file = File(p.join(photosRoot, storedName));
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  /// Writes exported PNG bytes (the rendered card) to a temp file for sharing.
  ///
  /// Static on purpose: it touches only the temp directory, never the store's
  /// state, and the share path must keep working even for a card that is not
  /// (or not yet) a stored entry.
  static Future<File> writeShareablePng(Uint8List bytes, String entryId) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'iprefer_$entryId.png'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
