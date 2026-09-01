import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:uuid/uuid.dart';

import 'sync/auth_client.dart';
import 'sync/sync_config.dart';

/// Performs the native Sign in with Apple prompt and returns Apple's identity
/// token, or null if the person backed out. A seam, so signing in is testable
/// without a device or a developer account.
typedef AppleIdentityTokenProvider = Future<String?> Function();

/// Who is using the app, and whether their archive is backed up.
///
/// Two ways in, and both are legitimate:
///  - **guest** — a local id, no account, no server. The app is complete like
///    this; it is what every existing user already has.
///  - **Apple** — a real account, which is what makes sync possible.
///
/// Signing in is therefore an *upgrade*, never a gate. Nothing in the app
/// requires an account, in the same spirit as location being an enhancement
/// rather than a requirement.
class Session extends ChangeNotifier {
  Session._(this._box, this._appleToken, this._auth);

  @visibleForTesting
  Session.forTest(
    this._box, {
    required AppleIdentityTokenProvider appleToken,
    required AuthClient auth,
  })  : _appleToken = appleToken,
        _auth = auth;

  static const String _boxName = 'session';
  static const String _userIdKey = 'userId';
  static const String _tokenKey = 'syncToken';
  static const String _expiredKey = 'syncTokenExpired';

  final Box _box;
  final AppleIdentityTokenProvider _appleToken;
  final AuthClient _auth;

  static Future<Session> open({
    AppleIdentityTokenProvider? appleToken,
    AuthClient? auth,
  }) async {
    final box = await Hive.openBox(_boxName);
    return Session._(
      box,
      appleToken ?? _nativeAppleToken,
      auth ?? HttpAuthClient(baseUrl: kSyncBaseUrl),
    );
  }

  bool get signedIn => _box.get(_userIdKey) != null;

  String? get userId => _box.get(_userIdKey) as String?;

  /// Bearer token for the sync backend. Null for a guest, which is exactly
  /// what makes a guest local-only: no token, nothing to sync with.
  String? get syncToken => _box.get(_tokenKey) as String?;

  bool get syncEnabled => syncToken != null && !syncTokenExpired;

  /// The server has stopped accepting our token — tokens last 30 days.
  ///
  /// This deliberately does NOT sign the person out. Their archive is local
  /// and complete; only the backup half has lapsed. Throwing them back to a
  /// login screen would punish them for a clock running out, so the app keeps
  /// working and asks for one sign-in to resume backing up.
  bool get syncTokenExpired => _box.get(_expiredKey) == true;

  Future<void> markSyncTokenExpired() async {
    // A pass still in flight from a previous account can land after sign-out.
    // Recording a lapse against nobody is what left guests staring at a
    // "sign in again" prompt for an account they never had.
    if (_box.get(_tokenKey) == null) return;
    if (syncTokenExpired) return;
    await _box.put(_expiredKey, true);
    notifyListeners();
  }

  /// Local id, no account, no network. Unchanged from before there was a
  /// backend, and still the default way in.
  Future<void> continueAsGuest() async {
    if (_box.get(_userIdKey) == null) {
      await _box.put(_userIdKey, 'local-${const Uuid().v4()}');
    }
    await _box.delete(_expiredKey);
    notifyListeners();
  }

  /// Signs in with Apple and stores the resulting session.
  ///
  /// Returns false when the person simply cancelled — that is not an error
  /// and should not raise anything at the UI. Genuine failures throw
  /// [AuthException] with something plain to show.
  Future<bool> signInWithApple() async {
    final identityToken = await _appleToken();
    if (identityToken == null) return false; // cancelled

    final session = await _auth.exchangeAppleToken(identityToken);
    await _box.put(_userIdKey, session.userId);
    await _box.put(_tokenKey, session.token);
    // A fresh token clears the lapse, so signing in again is the whole repair.
    await _box.delete(_expiredKey);
    notifyListeners();
    return true;
  }

  Future<void> signOut() async {
    await _box.delete(_userIdKey);
    await _box.delete(_tokenKey);
    await _box.delete(_expiredKey);
    notifyListeners();
  }

  /// The real prompt. Kept out of [signInWithApple] so the flow around it can
  /// be tested; this part can only be exercised on a device.
  static Future<String?> _nativeAppleToken() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          // Name and email are requested but never required: the app shows
          // neither. Apple only supplies them on the very first sign-in, and
          // nothing here depends on having them.
          AppleIDAuthorizationScopes.email,
        ],
      );
      // Apple can return a credential with no identity token in some failure
      // modes; there is nothing to send the server without one.
      final token = credential.identityToken;
      if (token == null || token.isEmpty) {
        throw AuthException("apple didn't return a sign-in token");
      }
      return token;
    } on SignInWithAppleAuthorizationException catch (e) {
      // Cancelled is a choice, not a failure.
      if (e.code == AuthorizationErrorCode.canceled) return null;

      // Carry Apple's own code through. Swallowing it left "Sign-up Not
      // Completed" on the device with nothing on our side to tell apart a
      // transient Apple outage from a misconfigured entitlement — the two
      // need completely different fixes.
      debugPrint('sign in with apple failed: ${e.code} — ${e.message}');
      throw AuthException("apple couldn't complete that sign-in (${e.code.name})");
    } on SignInWithAppleNotSupportedException {
      throw AuthException('this device cannot sign in with apple');
    }
  }
}
