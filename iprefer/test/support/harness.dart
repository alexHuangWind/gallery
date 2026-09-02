import 'dart:io';

import 'package:hive/hive.dart';
import 'package:iprefer/data/entry_store.dart';
import 'package:iprefer/data/session.dart';
import 'package:iprefer/data/sync/auth_client.dart';
import 'package:iprefer/data/sync/sync_outbox.dart';
import 'package:iprefer/models/entry.dart';
import 'package:path/path.dart' as p;

import 'fakes.dart';

/// The bootstrap almost every data-layer and widget test needs: a real temp
/// dir, a real Hive instance pointed at it, the [Entry] adapter registered
/// once, and a `photosRoot` directory — plus, lazily, an [EntryStore], a
/// [SyncOutbox] and a [Session] built the way `EntryStore.forTest` /
/// `SyncOutbox.forTest` / `Session.forTest` expect.
///
/// Everything past [create] is opt-in and lazy: a test that only wants a
/// [Session] never pays for an [EntryStore], and a test that only wants an
/// [EntryStore] never pays for a [SyncOutbox]. That is what lets both the
/// full-shaped tests (store + outbox + session, e.g. backup_bar_test) and the
/// partial ones (store alone, e.g. on_this_day_test; outbox + session alone,
/// e.g. account_deletion_test) share the one bootstrap.
class TestEnv {
  TestEnv._(this.tempDir, this.photosRoot, this._n);

  /// Bumped once per [create] call, not per box, so every box this env opens
  /// shares one number — mirroring the `boxSeq++` / `seq++` counters the
  /// migrated tests used to keep by hand, just centralised.
  static int _seq = 0;

  final Directory tempDir;
  final String photosRoot;
  final int _n;

  Box<Entry>? _entriesBox;
  SyncOutbox? _outbox;
  EntryStore? _store;
  Session? _session;

  static Future<TestEnv> create([String label = 'iprefer_test']) async {
    final tempDir = Directory.systemTemp.createTempSync(label);
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(EntryAdapter());
    final photosRoot = p.join(tempDir.path, 'photos');
    // Deliberately not created here: EntryStore creates it on demand (see
    // entry_store_test.dart's "creates the photos directory if it is gone"),
    // and a test env that always had one would make that untestable.
    return TestEnv._(tempDir, photosRoot, _seq++);
  }

  /// Opens a box named `<prefix>_<n>`, `n` shared across this env's boxes so
  /// they never collide with a previous test's boxes of the same prefix.
  Future<Box<T>> openBox<T>(String prefix) => Hive.openBox<T>('${prefix}_$_n');

  Future<Box<Entry>> entriesBox() async =>
      _entriesBox ??= await openBox<Entry>('entries');

  Future<SyncOutbox> outbox() async {
    final existing = _outbox;
    if (existing != null) return existing;
    final created = SyncOutbox.forTest(
      await openBox('ops'),
      await openBox('meta'),
      await openBox('photos'),
    );
    return _outbox = created;
  }

  /// Set [withOutbox] to false for a store that records purely locally, the
  /// way a guest archive does — several tests need that to keep the outbox
  /// out of assertions that are only about the store.
  Future<EntryStore> store({bool withOutbox = true}) async {
    final existing = _store;
    if (existing != null) return existing;
    final created = EntryStore.forTest(
      await entriesBox(),
      photosRoot: photosRoot,
      outbox: withOutbox ? await outbox() : null,
    );
    return _store = created;
  }

  Future<Session> session({
    AuthClient? auth,
    AppleIdentityTokenProvider? appleToken,
  }) async {
    final existing = _session;
    if (existing != null) return existing;
    final created = Session.forTest(
      await openBox('session'),
      appleToken: appleToken ?? (() async => 'apple-token'),
      auth: auth ?? FakeAuthClient.fixed(),
    );
    return _session = created;
  }

  Future<void> dispose() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }
}
