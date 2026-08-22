import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/entry.dart';
import 'sync_op.dart';

/// Everything the client remembers *about* syncing, kept deliberately outside
/// [Entry] and its hand-written Hive adapter.
///
/// Sync state is not part of the domain model — an entry is the same entry
/// whether or not a server has heard of it — and keeping it in its own boxes
/// means the adapter's field ids and its legacy-layout tests stay untouched.
class SyncOutbox {
  SyncOutbox._(this._ops, this._meta, this._photos);

  @visibleForTesting
  SyncOutbox.forTest(this._ops, this._meta, this._photos);

  static const String _opsBox = 'sync_outbox';
  static const String _metaBox = 'sync_meta';
  static const String _photosBox = 'sync_photo_uploads';
  static const String _cursorKey = 'cursor';

  final Box _ops;
  final Box _meta;
  final Box _photos;

  static Future<SyncOutbox> open() async {
    await Hive.initFlutter();
    return SyncOutbox._(
      await Hive.openBox(_opsBox),
      await Hive.openBox(_metaBox),
      await Hive.openBox(_photosBox),
    );
  }

  // --- the op queue --------------------------------------------------------

  /// Pending ops in the order they were recorded. Insertion order is what Hive
  /// gives back, and it matters: a create must reach the server before the
  /// delete that follows it.
  List<SyncOp> get pending => [
        for (final v in _ops.values)
          SyncOp.fromJson((jsonDecode(v as String) as Map).cast<String, Object?>()),
      ];

  bool get isEmpty => _ops.isEmpty;

  Future<void> enqueueCreate(Entry entry) async {
    final op = SyncOp.create(entry);
    await _ops.put(op.key, jsonEncode(op.toJson()));
    await _photos.put(entry.syncPhotoName, true);
  }

  Future<void> enqueueDelete(String entryId, {String? photoName}) async {
    final delete = SyncOp.delete(entryId);
    await _ops.put(delete.key, jsonEncode(delete.toJson()));
    // Nothing will ever read this photo again, so don't spend a phone's
    // upload budget on it. (A create op still queued for the same entry still
    // goes — the server records both, and other devices replay create then
    // delete to arrive at the same place.)
    if (photoName != null) await _photos.delete(photoName);
  }

  /// Drops ops the server has accepted.
  Future<void> forget(Iterable<SyncOp> ops) async {
    await _ops.deleteAll([for (final o in ops) o.key]);
  }

  // --- the pull cursor -----------------------------------------------------

  /// How far through the server's log this device has read.
  ///
  /// Advanced ONLY by a pull. Adopting the seq that `push` returns would skip
  /// any lower-seq op another device wrote but this one hasn't seen — see
  /// `server/README.md`.
  int get cursor => (_meta.get(_cursorKey) as int?) ?? 0;

  Future<void> setCursor(int value) async {
    if (value > cursor) await _meta.put(_cursorKey, value);
  }

  // --- photos --------------------------------------------------------------

  /// Photos this device has but the server may not.
  Set<String> get pendingPhotoUploads => _photos.keys.cast<String>().toSet();

  Future<void> markPhotoUploaded(String name) => _photos.delete(name);

  /// Wipes every trace of syncing. For sign-out: the next account must not
  /// inherit this one's queue or cursor.
  Future<void> reset() async {
    await _ops.clear();
    await _meta.clear();
    await _photos.clear();
  }
}
