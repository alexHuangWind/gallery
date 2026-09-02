import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/entry.dart';
import 'sync_op.dart';
import 'sync_validate.dart';

/// Everything the client remembers *about* syncing, kept deliberately outside
/// [Entry] and its hand-written Hive adapter.
///
/// Sync state is not part of the domain model — an entry is the same entry
/// whether or not a server has heard of it — and keeping it in its own boxes
/// means the adapter's field ids and its legacy-layout tests stay untouched.
/// A [ChangeNotifier] because the UI reports on it. Without notification the
/// backup line reads a count captured before the save it is meant to describe,
/// and tells the user everything is backed up at the exact moment it isn't.
class SyncOutbox extends ChangeNotifier {
  SyncOutbox._(this._ops, this._meta, this._photos);

  @visibleForTesting
  SyncOutbox.forTest(this._ops, this._meta, this._photos);

  static const String _opsBox = 'sync_outbox';
  static const String _metaBox = 'sync_meta';
  static const String _photosBox = 'sync_photo_uploads';
  static const String _cursorKey = 'cursor';
  static const String _adoptedKey = 'adoptedExisting';
  static const String _lastSyncedKey = 'lastSyncedAt';
  static const String _accountKey = 'account';

  final Box _ops;
  final Box _meta;
  final Box _photos;

  static Future<SyncOutbox> open() async {
    await Hive.initFlutter();
    final outbox = SyncOutbox._(
      await Hive.openBox(_opsBox),
      await Hive.openBox(_metaBox),
      await Hive.openBox(_photosBox),
    );
    // One sweep at launch for ops queued before [enqueueCreate] started
    // checking them. Left in the box they would be re-examined (and skipped)
    // on every pass forever, and keep [pendingCount] permanently above zero —
    // a "not backed up yet" that nothing can clear.
    await outbox._dropUnsendable();
    return outbox;
  }

  // --- the op queue --------------------------------------------------------

  /// Pending ops in the order they were recorded. Insertion order is what Hive
  /// gives back, and it matters: a create must reach the server before the
  /// delete that follows it.
  ///
  /// Ops the server would reject are skipped rather than sent — see [_sendable].
  List<SyncOp> get pending {
    final List<SyncOp> ops = [];
    for (final Object? key in _ops.keys) {
      final SyncOp? op = _sendable(key);
      if (op != null) ops.add(op);
    }
    return ops;
  }

  /// How many ops are queued, without decoding any of them.
  ///
  /// The UI asks on every outbox notification — i.e. on every save — and
  /// [pending] JSON-decodes the whole box to answer. Rows and sendable ops
  /// only diverge for an unsendable leftover, which [open] and [forget] drop.
  int get pendingCount => _ops.length;

  Future<void> enqueueCreate(Entry entry) async {
    final op = SyncOp.create(entry);
    final String? problem = syncOpProblem(op);
    if (problem != null) {
      // Not queued at all. The server 400s a push on its first bad op, so
      // keeping this one would cost the whole archive its backup rather than
      // just this entry — see sync_validate.dart.
      debugPrint('not queueing entry ${entry.id} for sync: $problem');
      return;
    }
    await _ops.put(op.key, jsonEncode(op.toJson()));
    await _photos.put(entry.syncPhotoName, true);
    notifyListeners();
  }

  Future<void> enqueueDelete(String entryId, {String? photoName}) async {
    final delete = SyncOp.delete(entryId);
    final String? problem = syncOpProblem(delete);
    if (problem == null) {
      await _ops.put(delete.key, jsonEncode(delete.toJson()));
    } else {
      // The matching create was refused for the same reason, so the server has
      // never heard of this entry and has nothing to delete.
      debugPrint('not queueing the deletion of $entryId: $problem');
    }
    // Nothing will ever read this photo again, so don't spend a phone's
    // upload budget on it. (A create op still queued for the same entry still
    // goes — the server records both, and other devices replay create then
    // delete to arrive at the same place.)
    if (photoName != null) await _photos.delete(photoName);
    notifyListeners();
  }

  /// Drops ops the server has accepted, and anything [pending] refuses to
  /// send — an op nothing will ever push would otherwise sit in the box for
  /// the life of the install.
  Future<void> forget(Iterable<SyncOp> ops) async {
    await _ops.deleteAll([
      for (final o in ops) o.key,
      ..._unsendableKeys,
    ]);
    notifyListeners();
  }

  /// The op stored under [key], or null when it can never be sent.
  ///
  /// Two ways to be unsendable: a row that won't decode, and an op the server
  /// would reject. Either one poisons the batch it travels in — the server
  /// validates the whole push and throws on the first bad op — so skipping it
  /// is what lets every other entry keep backing up.
  SyncOp? _sendable(Object? key) {
    final SyncOp op;
    try {
      final raw = _ops.get(key);
      op = SyncOp.fromJson(
          (jsonDecode(raw as String) as Map).cast<String, Object?>());
    } catch (e) {
      debugPrint('skipping an unreadable outbox row ($key): $e');
      return null;
    }
    final String? problem = syncOpProblem(op);
    if (problem != null) {
      debugPrint('skipping outbox row $key: $problem');
      return null;
    }
    return op;
  }

  List<Object?> get _unsendableKeys => [
        for (final Object? key in _ops.keys)
          if (_sendable(key) == null) key
      ];

  Future<void> _dropUnsendable() async {
    final List<Object?> keys = _unsendableKeys;
    if (keys.isEmpty) return;
    await _ops.deleteAll(keys);
  }

  // --- account boundaries --------------------------------------------------

  /// The account this queue, cursor and adoption state belong to.
  ///
  /// Survives [reset] on purpose: it is the only record that *some* account
  /// has already synced on this phone, which is what [adoptExisting] needs
  /// after a sign-out has wiped everything else. Only [forgetAccount] — i.e.
  /// the account being deleted outright — clears it.
  String? get accountId => _meta.get(_accountKey) as String?;

  /// Binds the outbox to [userId] and, on a genuine guest → account upgrade,
  /// queues the archive recorded before the account existed.
  ///
  /// Adoption happens **once per device**, not once per account. The local
  /// entries are only unambiguously "this person's" the first time an account
  /// appears here; after that they may be the *previous* account's, and
  /// queueing them for whoever signs in next files one person's photos under
  /// another person's archive. So:
  ///  - guest → A: adopt, this is the upgrade the feature exists for.
  ///  - A → sign out → B: adopt nothing. B's archive arrives by pull; A's
  ///    entries stay on the phone (see [reset]) but are never uploaded again.
  ///  - A → sign out → A: adopt nothing either. Those entries came from the
  ///    server; the pull that follows brings back anything missing.
  ///
  /// The old guard was a bare "have we adopted yet" flag that [reset] cleared,
  /// which made the second case above upload A's entire archive into B's
  /// account.
  Future<void> adoptExisting(
    Iterable<Entry> entries, {
    required String userId,
  }) async {
    final String? previous = accountId;
    if (previous != null && previous != userId) {
      // Belt for a sign-out that never finished its reset (a crash, a kill
      // mid-write): whatever is queued was recorded for `previous`, and one
      // push would file it under this account instead.
      await _clearAccountState();
    }
    if (previous != userId) await _meta.put(_accountKey, userId);

    // `_adoptedKey` also stands in for `accountId` on installs that adopted
    // before the account was recorded — without it their next sign-in would
    // re-queue and re-upload the whole archive.
    if (previous != null || _meta.get(_adoptedKey) == true) return;

    for (final entry in entries) {
      await enqueueCreate(entry);
    }
    await _meta.put(_adoptedKey, true);
    notifyListeners();
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

  Future<void> markPhotoUploaded(String name) async {
    await _photos.delete(name);
    notifyListeners();
  }

  /// When this device last completed a sync, kept across launches.
  ///
  /// In memory only, the bar could never say "backed up 6 days ago" — the one
  /// reading that actually reveals a problem — because a cold start always
  /// looked like "no idea".
  DateTime? get lastSyncedAt {
    final ms = _meta.get(_lastSyncedKey) as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> recordSyncedNow() async {
    await _meta.put(_lastSyncedKey, DateTime.now().millisecondsSinceEpoch);
    notifyListeners();
  }

  /// Wipes what this account queued. For sign-out: the next account must not
  /// inherit this one's queue, cursor or pending uploads.
  ///
  /// The entries themselves are deliberately left alone — someone who signs
  /// out of a shared phone would otherwise lose photos that were never backed
  /// up, which is a far worse failure than seeing them until they sign in
  /// again. [adoptExisting] is what stops those entries reaching another
  /// account.
  Future<void> reset() => _clearAccountState();

  /// [reset], plus the two markers it deliberately keeps.
  ///
  /// For account *deletion*, where those markers would be a lie: they say "an
  /// account has synced here", and the account they refer to no longer exists
  /// anywhere. Left in place, the next sign-in on this phone would skip
  /// adoption and start pulling from a cursor into a log the server has
  /// erased — an archive sitting right here, never offered to the new account.
  /// Cleared, that sign-in looks like the first one, which is what it is.
  ///
  /// The entries and photos stay on the phone, exactly as in [reset]: the
  /// person deleted their account, not their archive.
  Future<void> forgetAccount() async {
    await _meta.delete(_accountKey);
    await _meta.delete(_adoptedKey);
    await _clearAccountState();
  }

  /// Everything an account accumulated, minus the two markers that say an
  /// account has been here at all — those must outlive a sign-out or the next
  /// person on this phone adopts the last person's archive.
  Future<void> _clearAccountState() async {
    await _ops.clear();
    await _photos.clear();
    await _meta.delete(_cursorKey);
    await _meta.delete(_lastSyncedKey);
    notifyListeners();
  }
}
