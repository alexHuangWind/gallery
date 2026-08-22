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

  static SyncOp fromJson(Map<String, Object?> json) => SyncOp(
        type: json['type'] == 'delete' ? SyncOpType.delete : SyncOpType.create,
        entryId: json['entryId']! as String,
        payload: (json['payload'] as Map?)?.cast<String, Object?>(),
      );
}

/// An op as it came back from the server, carrying its position in the log.
class RemoteOp {
  const RemoteOp({required this.seq, required this.op});

  final int seq;
  final SyncOp op;

  static RemoteOp fromJson(Map<String, Object?> json) => RemoteOp(
        seq: (json['seq'] as num).toInt(),
        op: SyncOp.fromJson(json),
      );
}
