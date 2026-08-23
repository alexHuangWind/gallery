import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:iprefer/data/session.dart';
import 'package:iprefer/data/sync/auth_client.dart';

class FakeAuthClient implements AuthClient {
  FakeAuthClient({this.session, this.error});

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

void main() {
  late Directory tempDir;
  late Box box;
  var seq = 0;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('iprefer_session_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox('session_${seq++}');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Session sessionWith({
    String? appleToken = 'apple-identity-token',
    AppleSession? result =
        const AppleSession(token: 'server-token', userId: 'server-user'),
    Object? error,
  }) =>
      Session.forTest(
        box,
        appleToken: () async => appleToken,
        auth: FakeAuthClient(session: result, error: error),
      );

  group('guest', () {
    test('continuing mints a local id and leaves sync off', () async {
      final session = sessionWith();

      await session.continueAsGuest();

      expect(session.signedIn, isTrue);
      expect(session.userId, startsWith('local-'));
      // The whole point of a guest: nothing to sync with.
      expect(session.syncEnabled, isFalse);
      expect(session.syncToken, isNull);
    });

    test('continuing twice keeps the same id', () async {
      final session = sessionWith();

      await session.continueAsGuest();
      final first = session.userId;
      await session.continueAsGuest();

      expect(session.userId, first);
    });
  });

  group('sign in with apple', () {
    test('a completed sign-in stores the account and turns sync on', () async {
      final session = sessionWith();
      var notified = 0;
      session.addListener(() => notified++);

      final ok = await session.signInWithApple();

      expect(ok, isTrue);
      expect(session.signedIn, isTrue);
      expect(session.userId, 'server-user');
      expect(session.syncToken, 'server-token');
      expect(session.syncEnabled, isTrue);
      expect(notified, 1);
    });

    test('cancelling is not an error and changes nothing', () async {
      final session = sessionWith(appleToken: null);
      var notified = 0;
      session.addListener(() => notified++);

      final ok = await session.signInWithApple();

      expect(ok, isFalse);
      expect(session.signedIn, isFalse);
      expect(notified, 0);
    });

    test('a rejected token throws and signs nobody in', () async {
      final session = sessionWith(
        result: null,
        error: AuthException("apple couldn't confirm that sign-in"),
      );

      await expectLater(session.signInWithApple(), throwsA(isA<AuthException>()));
      expect(session.signedIn, isFalse);
      expect(session.syncToken, isNull);
    });

    test('a guest who signs in keeps one session, now with sync', () async {
      final session = sessionWith();
      await session.continueAsGuest();
      expect(session.userId, startsWith('local-'));

      await session.signInWithApple();

      expect(session.userId, 'server-user');
      expect(session.syncEnabled, isTrue);
    });
  });

  group('sign out', () {
    test('clears the account and the sync token', () async {
      final session = sessionWith();
      await session.signInWithApple();

      await session.signOut();

      expect(session.signedIn, isFalse);
      expect(session.userId, isNull);
      // Leaving a token behind would let the next person on this phone sync
      // into the previous account.
      expect(session.syncToken, isNull);
      expect(session.syncEnabled, isFalse);
    });
  });
}
