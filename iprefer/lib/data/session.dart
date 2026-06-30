import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

/// Local, stubbed session — no real auth in this pass.
///
/// "Continue" mints a local user id and stores it in a tiny Hive box. This is
/// the seam where Firebase / Google sign-in plugs in for v2.
///
/// TODO(firebase): replace this with FirebaseAuth.
///   - on sign-in, swap [userId] for the Firebase uid
///   - migrate existing local entries to the authenticated user
///   - keep the same `signedIn` / `userId` surface so the UI doesn't change
class Session extends ChangeNotifier {
  Session._(this._box);

  static const String _boxName = 'session';
  static const String _userIdKey = 'userId';

  final Box _box;

  static Future<Session> open() async {
    final box = await Hive.openBox(_boxName);
    return Session._(box);
  }

  bool get signedIn => _box.get(_userIdKey) != null;

  String? get userId => _box.get(_userIdKey) as String?;

  /// Stub "login": mint a local id and remember it. No network, no password.
  Future<void> continueAsGuest() async {
    if (_box.get(_userIdKey) == null) {
      await _box.put(_userIdKey, 'local-${const Uuid().v4()}');
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    await _box.delete(_userIdKey);
    notifyListeners();
  }
}
