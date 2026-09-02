import 'package:flutter_test/flutter_test.dart';
import 'package:iprefer/data/session.dart';
import 'package:iprefer/data/sync/sync_api.dart';
import 'package:iprefer/data/sync/sync_outbox.dart';
import 'package:iprefer/models/entry.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// Deleting an account is the one flow whose ordering is the whole substance:
/// server first, then the outbox's memory of the account, then the session.
/// Each test here pins one consequence of getting that order wrong.
///
/// Answers `DELETE /v1/account` with a fixed status through [FakeSyncApi]:
/// 204 is the deletion, 401 means the account is already gone (also
/// success), 5xx is the server refusing.
FakeSyncApi deleteApiAnswering(int status) => FakeSyncApi()..deleteAccountStatus = status;

void main() {
  late TestEnv env;
  late SyncOutbox outbox;
  late Session session;

  final entry = Entry(
    id: '11111111-1111-4111-8111-111111111111',
    localPath: '11111111-1111-4111-8111-111111111111.jpg',
    text: 'a flat white',
    createdAt: DateTime.utc(2026, 8, 20),
  );

  setUp(() async {
    env = await TestEnv.create('iprefer_delete_test');
    outbox = await env.outbox();
    session = await env.session(
      auth: FakeAuthClient.fixed(token: 'server-token', userId: 'user-a'),
      appleToken: () async => 'apple-identity-token',
    );
    // A real account that has adopted the guest archive, so the outbox
    // remembers user-a — the state deletion has to undo.
    await session.signInWithApple();
    await outbox.adoptExisting([entry], userId: 'user-a');
    await outbox.forget(outbox.pending);
  });

  tearDown(() => env.dispose());

  test('a 204 ends the session and the outbox forgets the account', () async {
    final api = deleteApiAnswering(204);
    expect(session.syncToken, isNotNull);
    expect(outbox.accountId, 'user-a');

    await session.deleteAccount(api, outbox: outbox);

    expect(api.deleteAccountCalls, 1);
    expect(session.signedIn, isFalse);
    expect(session.syncToken, isNull);
    expect(outbox.accountId, isNull);
    expect(outbox.cursor, 0);
  });

  test('after deletion, the next account adopts the archive afresh', () async {
    // The point of forgetAccount over reset: a sign-out keeps the "an account
    // has synced here" markers so a *second* account never inherits the first
    // one's archive. After the first account is erased those markers describe
    // nothing, and honouring them would leave the archive sitting on the phone
    // never offered to the account that replaces it.
    await session.deleteAccount(deleteApiAnswering(204), outbox: outbox);

    await outbox.adoptExisting([entry], userId: 'user-b');

    expect(outbox.pending.map((o) => o.entryId), [entry.id]);
    expect(outbox.accountId, 'user-b');
  });

  test('a 401 is treated as already deleted', () async {
    // The token lapsed or the row is already gone: either way there is no
    // account left on this phone's behalf, so the local half still happens.
    // Crucially this must not route through the "sign in again to resume
    // backing up" path that every other 401 takes.
    await session.deleteAccount(deleteApiAnswering(401), outbox: outbox);

    expect(session.signedIn, isFalse);
    expect(outbox.accountId, isNull);
  });

  test('a server refusal leaves everything local untouched', () async {
    // Clearing the session on a 5xx would strand an account nobody can reach
    // to delete — the person would be signed out of the very account they
    // still need a token for.
    await expectLater(
      session.deleteAccount(deleteApiAnswering(500), outbox: outbox),
      throwsA(isA<SyncApiException>()),
    );

    expect(session.signedIn, isTrue);
    expect(session.syncToken, 'server-token');
    expect(outbox.accountId, 'user-a');
  });

  test('a sign-out alone keeps the account markers', () async {
    // The contrast case, so the two behaviours can't quietly converge: this
    // is what makes forgetAccount necessary rather than reset being enough.
    await outbox.reset();
    await session.signOut();

    expect(outbox.accountId, 'user-a');
  });
}
