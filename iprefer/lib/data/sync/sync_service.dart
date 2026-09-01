import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/entry.dart';
import '../entry_store.dart';
import 'sync_api.dart';
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

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
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

    // One pass at a time. A second caller (resume, manual tap, a save landing
    // mid-run) would otherwise push the same ops twice and race the cursor.
    if (_syncing) return const SyncResult();
    _syncing = true;
    _notify();

    var pushed = 0;
    var pulled = 0;
    var uploaded = 0;
    var downloaded = 0;
    Object? failure;

    try {
      pushed = await _push();
      pulled = await _pull();
      final photos = await _syncPhotos();
      uploaded = photos.$1;
      downloaded = photos.$2;
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

  /// Sends the outbox. Ops are only forgotten after the server has them, so a
  /// dropped response costs one duplicate push, which the server ignores.
  Future<int> _push() async {
    final ops = _outbox.pending;
    if (ops.isEmpty) return 0;

    await _live.push(ops);
    await _outbox.forget(ops);
    return ops.length;
  }

  /// Reads the log forward from our cursor and applies what we haven't seen.
  Future<int> _pull() async {
    var applied = 0;
    var guard = 0;

    while (true) {
      final page = await _live.pull(since: _outbox.cursor, limit: pageLimit);
      for (final remote in page.ops) {
        await _apply(remote.op);
        applied++;
      }
      // Advance only from what the server actually returned — the cursor is
      // the one piece of state that must never run ahead of what we applied.
      await _outbox.setCursor(page.seq);

      if (!page.hasMore || page.ops.isEmpty) break;
      // A server that always claims hasMore must not spin us forever.
      if (++guard > 1000) break;
    }
    return applied;
  }

  /// Applies a remote op WITHOUT re-enqueueing it. Routing these through the
  /// ordinary create/delete would put the op straight back in the outbox and
  /// bounce it to the server forever.
  Future<void> _apply(SyncOp op) async {
    switch (op.type) {
      case SyncOpType.create:
        final payload = op.payload;
        if (payload == null) return;
        // Idempotent: replaying a create for an entry we already hold is a
        // no-op, which is what makes re-receiving our own ops harmless.
        if (_store.byId(op.entryId) != null) return;
        await _store.applyRemoteCreate(Entry.fromSyncJson(payload));
      case SyncOpType.delete:
        await _store.applyRemoteDelete(op.entryId);
    }
  }

  /// Photos move separately from records: they are ~10,000x bigger, and an
  /// entry is useful (searchable, on the map, in recall) before its photo
  /// lands.
  Future<(int, int)> _syncPhotos() async {
    var uploaded = 0;
    var downloaded = 0;

    // Up: whatever this device recorded and hasn't shipped.
    for (final name in _outbox.pendingPhotoUploads) {
      final bytes = await _store.readPhotoBytes(name);
      if (bytes == null) {
        // The file is gone (a delete raced us, or the OS reclaimed it).
        // Nothing to send, and nothing to keep waiting for.
        await _outbox.markPhotoUploaded(name);
        continue;
      }
      await _live.uploadPhoto(name, bytes);
      await _outbox.markPhotoUploaded(name);
      uploaded++;
    }

    // Down: any entry whose photo isn't on this device. Derived from the
    // filesystem rather than a queue, so it self-heals — an interrupted
    // download, or a fresh install that pulled records first, simply looks
    // like a missing file next time.
    for (final entry in _store.entries) {
      if (_store.hasPhoto(entry)) continue;
      final bytes = await _live.downloadPhoto(entry.syncPhotoName);
      if (bytes == null) continue; // not uploaded yet by the other device
      await _store.writePhotoBytes(entry.syncPhotoName, bytes);
      downloaded++;
    }

    return (uploaded, downloaded);
  }
}
