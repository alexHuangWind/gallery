import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../models/entry.dart';
import '../entry_store.dart';
import 'sync_api.dart';
import 'sync_limits.dart';
import 'sync_op.dart';
import 'sync_outbox.dart';

/// What one sync run did. Returned rather than thrown so callers can show a
/// quiet status line instead of handling exceptions.
@immutable
class SyncResult {
  const SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.photosUploaded = 0,
    this.photosDownloaded = 0,
    this.error,
  });

  final int pushed;
  final int pulled;
  final int photosUploaded;
  final int photosDownloaded;
  final Object? error;

  bool get ok => error == null;
  bool get changedAnything =>
      pushed > 0 || pulled > 0 || photosUploaded > 0 || photosDownloaded > 0;
}

/// Drives one sync pass: push what we owe, pull what we're missing, then move
/// photos.
///
/// The whole thing is best-effort by construction. The phone is the source of
/// truth and the archive is complete without this ever succeeding, so every
/// failure path ends in "leave the queue alone and try again later" — never in
/// a lost entry and never in a thrown exception reaching the UI.
class SyncService extends ChangeNotifier {
  SyncService({
    required SyncApi? api,
    required SyncOutbox outbox,
    required EntryStore store,
    this.onAuthExpired,
    this.pageLimit = 200,
  })  : _api = api,
        _outbox = outbox,
        _store = store {
    // The queue changes without this service doing anything — every save and
    // every delete enqueues. Forwarding keeps the backup line honest between
    // sync passes instead of reporting a count from the last one.
    _outbox.addListener(_onOutboxChanged);
  }

  void _onOutboxChanged() => _notify();

  /// Guards the window where a replaced service is still finishing a pass.
  /// Swapping accounts disposes the old instance while its `finally` may still
  /// be pending; notifying then throws.
  bool _disposed = false;

  /// Bumped by [dispose]. Not notification bookkeeping — this is what stops an
  /// abandoned pass from *writing*.
  ///
  /// Sign-out disposes this service and resets the boxes, but the pass already
  /// in flight keeps going: its awaits resume against the next account's
  /// outbox and store, and it happily lands the previous account's entries,
  /// cursor and "backed up just now" in a stranger's archive. So every await
  /// in a pass is followed by a generation check, and a pass that finds itself
  /// out of date stops without writing anything.
  int _generation = 0;

  bool _abandoned(int generation) => generation != _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _outbox.removeListener(_onOutboxChanged);
    super.dispose();
  }

  /// Null when there is no account. The service still exists so the UI can
  /// always ask it what's going on, rather than every widget having to cope
  /// with a missing service.
  final SyncApi? _api;
  final SyncOutbox _outbox;
  final EntryStore _store;
  final int pageLimit;

  /// Called once when the server stops accepting our token, so the session can
  /// remember that and the app can ask for one sign-in instead of retrying
  /// forever. Awaited: it persists a flag, and dropping the future would turn
  /// a failed write into an unhandled error with nothing retrying it.
  final Future<void> Function()? onAuthExpired;

  bool _syncing = false;
  bool _needsReauth = false;
  Object? _lastError;

  bool get enabled => _api != null;
  bool get syncing => _syncing;
  /// Read from storage, so it survives a relaunch and a service swap.
  DateTime? get lastSyncedAt => _outbox.lastSyncedAt;
  Object? get lastError => _lastError;

  /// The session has lapsed and syncing cannot resume without signing in.
  bool get needsReauth => _needsReauth;

  /// Pending local changes, for a "not backed up yet" hint in the UI.
  int get pendingCount => _outbox.pending.length;

  /// Only ever read from inside a pass that [syncNow] has already gated on
  /// `_api != null`. A final field can't be promoted across method calls, so
  /// the assertion lives here once instead of a bare `!` at four call sites.
  SyncApi get _live => _api!;

  Future<SyncResult> syncNow() async {
    // No account, or a session the server has already rejected: doing nothing
    // is the honest answer. Retrying a dead token just burns battery and
    // keeps the UI claiming it is trying.
    if (_api == null || _needsReauth) return const SyncResult();

    // A service that has been replaced must not start a pass at all: whatever
    // it wrote would land in the account that replaced it.
    if (_disposed) return const SyncResult();

    // One pass at a time. A second caller (resume, manual tap, a save landing
    // mid-run) would otherwise push the same ops twice and race the cursor.
    if (_syncing) return const SyncResult();
    _syncing = true;
    _notify();

    final generation = _generation;
    var pushed = 0;
    var pulled = 0;
    var uploaded = 0;
    var downloaded = 0;
    Object? failure;

    try {
      // A failed push must not also cost us the pull. One op the server keeps
      // refusing would otherwise block every change from every other device
      // forever, because push and pull shared a single try.
      Object? pushFailure;
      try {
        pushed = await _push(generation);
      } on SyncAuthExpiredException {
        rethrow; // nothing else in this pass can work either
      } catch (e) {
        pushFailure = e;
      }
      if (_abandoned(generation)) return const SyncResult();

      pulled = await _pull(generation);
      if (_abandoned(generation)) return const SyncResult();

      final photos = await _syncPhotos(generation);
      if (_abandoned(generation)) return const SyncResult();
      uploaded = photos.uploaded;
      downloaded = photos.downloaded;

      // Reported only now, after the pull it must not have blocked.
      if (pushFailure != null) throw pushFailure;

      // Photos that failed do not hold this back. The records are the archive;
      // a photo still in the queue is a smaller, self-healing problem, and
      // calling the whole pass a failure tells the user their backup is broken
      // when the part that matters went through.
      if (photos.failed > 0) {
        debugPrint('sync: records synced, ${photos.failed} photo(s) will retry');
      }
      await _outbox.recordSyncedNow();
      _lastError = null;
    } on SyncAuthExpiredException catch (e) {
      // The one failure retrying cannot fix. Stop trying and let the app ask
      // for a sign-in — the queue and cursor are untouched, so everything
      // resumes the moment there is a working session again.
      failure = e;
      _lastError = e;
      _needsReauth = true;
      await onAuthExpired?.call();
    } catch (e) {
      // Offline, a 500, a timeout — all the same answer: keep the queue and
      // the cursor exactly where they are, and try again next time.
      failure = e;
      _lastError = e;
    } finally {
      _syncing = false;
      _notify();
    }

    return SyncResult(
      pushed: pushed,
      pulled: pulled,
      photosUploaded: uploaded,
      photosDownloaded: downloaded,
      error: failure,
    );
  }

  /// Sends the outbox, a chunk at a time. Ops are only forgotten after the
  /// server has them, so a dropped response costs one duplicate push, which
  /// the server ignores.
  ///
  /// Chunked because the server refuses more than [kMaxOpsPerPush]'s worth in
  /// one body: sending the whole queue meant a guest with a few hundred
  /// entries got a 400 on every pass and could never sync anything, ever.
  Future<int> _push(int generation) async {
    final ops = _outbox.pending;
    if (ops.isEmpty) return 0;

    var pushed = 0;
    for (var start = 0; start < ops.length; start += kMaxOpsPerPush) {
      final chunk =
          ops.sublist(start, math.min(start + kMaxOpsPerPush, ops.length));
      await _live.push(chunk);
      if (_abandoned(generation)) return pushed;
      // Per chunk, and only after its own ack: forgetting the whole queue on
      // the first response would drop ops the server never saw when a later
      // chunk fails.
      await _outbox.forget(chunk);
      if (_abandoned(generation)) return pushed;
      pushed += chunk.length;
    }
    return pushed;
  }

  /// Reads the log forward from our cursor and applies what we haven't seen.
  Future<int> _pull(int generation) async {
    var applied = 0;
    var guard = 0;

    while (true) {
      final since = _outbox.cursor;
      final page = await _live.pull(since: since, limit: pageLimit);
      if (_abandoned(generation)) return applied;

      for (final remote in page.ops) {
        if (await _apply(remote.op, generation)) applied++;
        if (_abandoned(generation)) return applied;
      }
      // Advance only from what the server actually returned — the cursor is
      // the one piece of state that must never run ahead of what we applied.
      await _outbox.setCursor(page.seq);
      if (_abandoned(generation)) return applied;

      if (!page.hasMore || page.ops.isEmpty) break;
      // A page whose seq didn't pass the cursor leaves `since` unchanged, so
      // the next request asks the identical question and gets the identical
      // answer. hasMore alone would spin that all the way to the guard.
      if (page.seq <= since) break;
      // A server that always claims hasMore must not spin us forever.
      if (++guard > 1000) break;
    }
    return applied;
  }

  /// Applies a remote op WITHOUT re-enqueueing it. Routing these through the
  /// ordinary create/delete would put the op straight back in the outbox and
  /// bounce it to the server forever.
  ///
  /// False only when the op could not be read at all.
  Future<bool> _apply(SyncOp op, int generation) async {
    try {
      switch (op.type) {
        case SyncOpType.create:
          final payload = op.payload;
          if (payload == null) break;
          // Idempotent: replaying a create for an entry we already hold is a
          // no-op, which is what makes re-receiving our own ops harmless.
          if (_store.byId(op.entryId) != null) break;
          final entry = Entry.fromSyncJson(payload);
          if (_abandoned(generation)) break;
          await _store.applyRemoteCreate(entry);
        case SyncOpType.delete:
          if (_abandoned(generation)) break;
          await _store.applyRemoteDelete(op.entryId);
      }
      return true;
    } catch (e) {
      // One op this build can't read must not strand the cursor behind it.
      // Letting it throw meant the same page was re-fetched and re-failed on
      // every pass, so every *later* op — including the readable ones — never
      // arrived. Skipping costs one entry; stopping costs all of them.
      debugPrint(
          'sync: skipping unreadable op ${op.type.name}:${op.entryId} ($e)');
      return false;
    }
  }

  /// Photos move separately from records: they are ~10,000x bigger, and an
  /// entry is useful (searchable, on the map, in recall) before its photo
  /// lands.
  ///
  /// Every photo is attempted on its own. One bad file used to abort the pass
  /// after the records had already synced, which meant the sync was never
  /// recorded as done and the UI told the user their backup was unreachable
  /// while their archive was, in fact, safe on the server.
  Future<({int uploaded, int downloaded, int failed})> _syncPhotos(
      int generation) async {
    var uploaded = 0;
    var downloaded = 0;
    var failed = 0;

    ({int uploaded, int downloaded, int failed}) tally() =>
        (uploaded: uploaded, downloaded: downloaded, failed: failed);

    // Up: whatever this device recorded and hasn't shipped.
    for (final name in _outbox.pendingPhotoUploads) {
      if (_abandoned(generation)) return tally();
      final bytes = await _store.readPhotoBytes(name);
      if (_abandoned(generation)) return tally();
      if (bytes == null) {
        // The file is gone (a delete raced us, or the OS reclaimed it).
        // Nothing to send, and nothing to keep waiting for.
        await _outbox.markPhotoUploaded(name);
        continue;
      }
      try {
        await _live.uploadPhoto(name, bytes);
      } on SyncAuthExpiredException {
        rethrow; // the session, not the photo — the pass has to stop
      } catch (e) {
        if (_abandoned(generation)) return tally();
        if (e is SyncApiException && e.isPermanent) {
          // The server will never take this one (too big, wrong name). It is
          // retried first on every pass, so leaving it queued means every
          // photo behind it waits on a failure that cannot resolve. Drop it:
          // the entry and its local photo are untouched.
          debugPrint('sync: giving up on photo $name, the server refused it ($e)');
          await _outbox.markPhotoUploaded(name);
        } else {
          failed++;
        }
        continue;
      }
      if (_abandoned(generation)) return tally();
      await _outbox.markPhotoUploaded(name);
      uploaded++;
    }

    // Down: any entry whose photo isn't on this device. Derived from the
    // filesystem rather than a queue, so it self-heals — an interrupted
    // download, or a fresh install that pulled records first, simply looks
    // like a missing file next time.
    var attempts = 0;
    for (final entry in _store.entries) {
      if (_abandoned(generation)) return tally();
      // Self-healing is what makes a bound safe: the rest are still missing
      // next pass, and stopping keeps one pass from running for hours.
      if (attempts >= kMaxPhotoDownloadsPerPass) break;
      if (_store.hasPhoto(entry)) continue;

      final Uint8List? bytes;
      attempts++;
      try {
        bytes = await _live.downloadPhoto(entry.syncPhotoName);
      } on SyncAuthExpiredException {
        rethrow;
      } catch (e) {
        // The file still looks missing next pass, so counting it is all this
        // has to do — and the entries after it still get their turn.
        debugPrint('sync: photo ${entry.syncPhotoName} did not arrive ($e)');
        failed++;
        continue;
      }
      if (_abandoned(generation)) return tally();
      if (bytes == null) continue; // not uploaded yet by the other device
      await _store.writePhotoBytes(entry.syncPhotoName, bytes);
      downloaded++;
    }

    return tally();
  }
}
