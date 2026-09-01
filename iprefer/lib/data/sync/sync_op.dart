import '../../models/entry.dart';

/// An entry is created and deleted, never edited — so those two are the whole
/// vocabulary the client and server need. See `server/README.md`.
enum SyncOpType { create, delete }

/// One pending change, waiting to reach the server.
class SyncOp {
  const SyncOp({required this.type, required this.entryId, this.payload});

  SyncOp.create(Entry entry)
      : type = SyncOpType.create,
        entryId = entry.id,
        payload = entry.toSyncJson();

  const SyncOp.delete(this.entryId)
      : type = SyncOpType.delete,
        payload = null;

  final SyncOpType type;
  final String entryId;

  /// The entry JSON on a create; null on a delete.
  final Map<String, Object?>? payload;

  /// Outbox key. Keying by (type, entry) rather than appending makes
  /// enqueueing idempotent: recording the same change twice is one row, so a
  /// retry that races a save can't push a duplicate.
  String get key => '${type.name}:$entryId';

  Map<String, Object?> toJson() => {
        'type': type.name,
        'entryId': entryId,
        if (payload != null) 'payload': payload,
      };

  /// Parses one op from the wire (or from the outbox, which stores this same
  /// shape).
  ///
  /// Soft casts throughout: a hard one throws inside the pull loop before the
  /// cursor advances, so a single malformed op from the server would make the
  /// client replay that page forever and no later change would ever land.
  /// [MalformedSyncOp] is reserved for the entry id — an op that doesn't say
  /// what it is about cannot be applied to anything — and lets the caller skip
  /// that one op and carry on.
  static SyncOp fromJson(Map<String, Object?> json) {
    final entryId = json['entryId'];
    if (entryId is! String || entryId.isEmpty) throw MalformedSyncOp('entryId');
    final payload = json['payload'];
    return SyncOp(
      // Anything that isn't the literal 'delete' is a create — the same
      // reading as before, and it cannot throw on a garbage value.
      type: json['type'] == 'delete' ? SyncOpType.delete : SyncOpType.create,
      entryId: entryId,
      // A payload of the wrong shape is treated as absent; the create is then
      // skipped by the applier rather than crashing the pass.
      payload: payload is Map ? payload.cast<String, Object?>() : null,
    );
  }
}

/// An op as it came back from the server, carrying its position in the log.
class RemoteOp {
  const RemoteOp({required this.seq, required this.op});

  final int seq;
  final SyncOp op;

  /// [MalformedSyncOp] on a missing or unreadable seq: the sequence number is
  /// the cursor. Defaulting it to 0 would rewind the client to the start of the
  /// log, and defaulting it to the current cursor would let an op we never
  /// applied be marked as applied — so this is the one place where refusing the
  /// op is the only safe reading.
  static RemoteOp fromJson(Map<String, Object?> json) {
    final seq = json['seq'];
    if (seq is! num) throw MalformedSyncOp('seq');
    return RemoteOp(seq: seq.toInt(), op: SyncOp.fromJson(json));
  }
}
