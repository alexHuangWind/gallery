import 'dart:async';
import 'dart:typed_data';

import 'package:iprefer/data/sync/auth_client.dart';
import 'package:iprefer/data/sync/sync_api.dart';
import 'package:iprefer/data/sync/sync_op.dart';

/// Stands in for `server/`, including the parts that matter for correctness:
/// a monotonic op log, cursor-based paging, and idempotent creates.
///
/// The one [SyncApi] double for the whole suite — it folds in what used to be
/// three separate hand-rolled fakes (`_StubApi` in backup_bar_test,
/// `_DeleteApi` in account_deletion_test, and this class's own origin in
/// sync_test) so every test configures the same knobs instead of a slightly
/// different subset of them.
class FakeSyncApi implements SyncApi {
  final List<List<SyncOp>> pushes = [];
  final List<RemoteOp> log = [];
  final Map<String, Uint8List> photos = {};
  int _nextSeq = 1;
  bool offline = false;

  /// The server no longer accepts our token (a 30-day session ran out).
  bool expired = false;
  int pullCalls = 0;
  int pushCalls = 0;

  /// The real server rejects an oversized batch with a 400 rather than
  /// truncating it (`server/src/validate.ts`).
  int? maxOpsPerPush;

  /// Fails every push after this many have been accepted — the connection
  /// dropping partway through a long queue.
  int? rejectPushAfter;

  /// Photo name -> the status this server always answers with. A 413 is the
  /// realistic one: a file the server will never accept, however often it is
  /// offered.
  final Map<String, int> uploadRejections = {};
  final List<String> uploadAttempts = [];

  /// Answers every pull with this seq and `hasMore: true` — a server that
  /// claims there is more but never moves the cursor forward.
  int? stuckAtSeq;

  /// Holds a pull open, so a test can act (sign out, say) mid-pass.
  Completer<void>? pullGate;

  int deleteAccountCalls = 0;

  /// What `DELETE /v1/account` answers with. 204 is the deletion; 401 means
  /// the account is already gone, which the client also takes as success; a
  /// 5xx is the failure worth retrying.
  int deleteAccountStatus = 204;

  void _guard() {
    if (expired) throw SyncAuthExpiredException();
    if (offline) throw SyncApiException('offline');
  }

  /// Simulates an op written by another device.
  void seedRemote(SyncOp op) => log.add(RemoteOp(seq: _nextSeq++, op: op));

  @override
  Future<int> push(List<SyncOp> ops) async {
    // Counted BEFORE the guard: a test asserting "we stopped calling the
    // server" is worthless if the counter only increments on success.
    pushCalls++;
    _guard();
    final cap = maxOpsPerPush;
    if (cap != null && ops.length > cap) {
      throw SyncApiException('too many ops', statusCode: 400);
    }
    if (rejectPushAfter != null && pushCalls > rejectPushAfter!) {
      throw SyncApiException('connection dropped');
    }
    pushes.add(List.of(ops));
    for (final op in ops) {
      final already = log.any((r) => r.op.type == op.type && r.op.entryId == op.entryId);
      if (!already) log.add(RemoteOp(seq: _nextSeq++, op: op));
    }
    return log.isEmpty ? 0 : log.last.seq;
  }

  @override
  Future<PullPage> pull({required int since, int limit = 200}) async {
    pullCalls++;
    if (pullGate != null) await pullGate!.future;
    _guard();
    final stuck = stuckAtSeq;
    if (stuck != null) {
      return PullPage(
        ops: [RemoteOp(seq: stuck, op: const SyncOp.delete('gone'))],
        seq: stuck,
        hasMore: true,
      );
    }
    final after = log.where((o) => o.seq > since).toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    final page = after.take(limit).toList();
    return PullPage(
      ops: page,
      seq: page.isEmpty ? since : page.last.seq,
      hasMore: after.length > page.length,
    );
  }

  @override
  Future<void> deleteAccount() async {
    deleteAccountCalls++;
    // Mirrors HttpSyncApi: 204 and 401 both mean "no account left to keep";
    // anything else is the server refusing, and the client must not touch
    // its local state on that answer.
    if (deleteAccountStatus == 204 || deleteAccountStatus == 401) return;
    throw SyncApiException('account deletion failed: HTTP $deleteAccountStatus',
        statusCode: deleteAccountStatus);
  }

  @override
  Future<void> uploadPhoto(String name, Uint8List bytes) async {
    uploadAttempts.add(name);
    _guard();
    final rejected = uploadRejections[name];
    if (rejected != null) {
      throw SyncApiException('rejected $name', statusCode: rejected);
    }
    photos[name] = bytes;
  }

  @override
  Future<Uint8List?> downloadPhoto(String name) async {
    _guard();
    return photos[name];
  }
}

/// The one [AuthClient] double for the whole suite. By default it answers
/// with [session]; pass [error] to make it behave like a rejected Apple
/// token instead.
class FakeAuthClient implements AuthClient {
  FakeAuthClient({this.session, this.error});

  /// A `_StubAuth`-shaped convenience: always exchanges cleanly for a fixed
  /// token/user pair, for tests that only need *a* signed-in session to
  /// exist and never inspect what it contains.
  FakeAuthClient.fixed({String token = 'server-token', String userId = 'user-1'})
      : session = AppleSession(token: token, userId: userId),
        error = null;

  final AppleSession? session;
  final Object? error;
  final List<String> exchanged = [];

  @override
  Future<AppleSession> exchangeAppleToken(String identityToken) async {
    exchanged.add(identityToken);
    if (error != null) throw error!;
    return session!;
  }
}
