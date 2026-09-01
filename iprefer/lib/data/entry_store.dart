import 'dart:io';

import 'package:flutter/foundation.dart';
// For the image-cache eviction in [EntryStore.writePhotoBytes] — the store
// touches no widgets, only the cache the photo tiles resolve through.
import 'package:flutter/painting.dart';
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

  /// Memoized [entries]. Invalidated in [notifyListeners], which every
  /// mutation on this class already goes through.
  ///
  /// That is only sufficient because of one invariant: `_box` is never mutated
  /// from outside this class — nothing hands the box out, and every write goes
  /// through a method here. Anyone who adds a path that puts to or deletes from
  /// Hive without notifying leaves the timeline showing yesterday's archive.
  List<Entry>? _sorted;
  Map<String, int>? _counts;
  List<String>? _byUse;

  @override
  void notifyListeners() {
    _sorted = null;
    _counts = null;
    _byUse = null;
    super.notifyListeners();
  }

  /// All entries, newest first.
  ///
  /// Cached because this copies and sorts the whole box, and a single frame
  /// asks for it several times over — the timeline, the map (kept alive
  /// offstage by the IndexedStack), and both recall banners. Searching made
  /// that a per-keystroke cost.
  ///
  /// The list is unmodifiable: callers used to receive a fresh copy they could
  /// safely sort in place, and now they share one.
  List<Entry> get entries {
    return _sorted ??= List.unmodifiable(
      _box.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
  }

  bool get isEmpty => _box.isEmpty;

  /// Every tag in use, most-used first, ties broken alphabetically.
  ///
  /// Drives the compose suggestions, so the shelves the user actually reaches
  /// for float to the front instead of us guessing for them.
  List<String> get tagsByUse {
    return _byUse ??= () {
      final counts = tagCounts;
      return List<String>.unmodifiable(counts.keys.toList()
        ..sort((a, b) {
          final byCount = counts[b]!.compareTo(counts[a]!);
          return byCount != 0 ? byCount : a.compareTo(b);
        }));
    }();
  }

  /// How many entries carry each tag.
  /// Cached alongside [entries], and for the same reason: the filter bar asks
  /// for this on both tabs, and `effective(tagsByUse)` asks again — several
  /// full scans of the box per keystroke once search existed.
  Map<String, int> get tagCounts {
    return _counts ??= () {
      final counts = <String, int>{};
      for (final e in _box.values) {
        // toSet(): one entry counts once per tag even if its list repeats one.
        for (final t in e.tags.toSet()) {
          counts[t] = (counts[t] ?? 0) + 1;
        }
      }
      return Map<String, int>.unmodifiable(counts);
    }();
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

  /// Puts a ready-made entry straight into the box, for tests that need an
  /// archive without a photo file to copy.
  ///
  /// Never call this from a screen: it skips both [_persistPhoto] and the
  /// outbox, so the entry would reference a photo nobody wrote and would never
  /// reach the server — an entry that exists on exactly one device and is lost
  /// with it. Recording goes through [create].
  @visibleForTesting
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

  /// Where a photo with this wire name *belongs*: always `photosRoot/<name>`.
  ///
  /// Deliberately without the legacy-path fallback [readPhotoBytes] has — this
  /// is also the download destination, and a download must never be talked into
  /// writing outside the photos directory by what a record happens to store.
  File _photoByName(String name) => File(p.join(photosRoot, name));

  /// Null when the file isn't there — a delete that raced the upload, or an
  /// OS reclaim. The caller drops the pending upload rather than retrying.
  Future<Uint8List?> readPhotoBytes(String name) async {
    final file = _photoByName(name);
    if (file.existsSync()) return file.readAsBytes();

    // Records written before the name-not-path change keep an absolute path,
    // so their photo is not under photosRoot under this name and the lookup
    // above misses it. Without this fallback the caller reads that miss as
    // "the file is gone", marks the upload done and the photo never leaves the
    // device — silently, and for every entry recorded before the change.
    for (final entry in _box.values) {
      if (entry.syncPhotoName != name) continue;
      final legacy = fileFor(entry);
      if (legacy.existsSync()) return legacy.readAsBytes();
    }
    return null;
  }

  /// Stores a photo that came down from the server, then makes it visible.
  ///
  /// The eviction is the point. A tile whose photo hadn't downloaded yet
  /// painted the error placeholder, and the completer that failed stays in the
  /// image cache keyed by the provider — so every later resolve of the same
  /// file is handed that same failure and the tile is a grey slab until the app
  /// restarts. On a second device that is the entire visible payoff of syncing.
  /// [notifyListeners] then rebuilds the timeline (nulling the memoized lists,
  /// which is correct — the box did not change, and rebuilding them is cheap
  /// next to a decode).
  Future<void> writePhotoBytes(String name, Uint8List bytes) async {
    final dir = Directory(photosRoot);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = _photoByName(name);
    await file.writeAsBytes(bytes, flush: true);

    // Best-effort, and deliberately swallowing: the bytes are already on disk
    // and the notify below must still happen. A store running without a Flutter
    // binding (the sync tests) has no image cache at all, and letting that
    // throw here would abort the caller's whole photo pass over a cache hint.
    try {
      final cache = PaintingBinding.instance.imageCache;
      final provider = FileImage(file);
      cache.evict(provider);
      // Grid tiles paint through a ResizeImage wrapper, which is a *separate*
      // cache key — evicting the bare FileImage would leave exactly the screen
      // this fix is for still stale. The key type has a private constructor, so
      // obtainKey is the only way to build it from out here.
      cache.evict(
        await ResizeImage(provider, width: _compactDecodeWidth)
            .obtainKey(ImageConfiguration.empty),
      );
    } catch (_) {}

    notifyListeners();
  }

  /// Decode width the compact cards ask for. Must stay in step with
  /// `PreferenceCard._paintImage`; duplicated because that number belongs to
  /// the widget and a wrong value here only means one stale tile, never a
  /// wrong pixel.
  static const int _compactDecodeWidth = 600;

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
