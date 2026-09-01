import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:iprefer/data/entry_store.dart';
import 'package:iprefer/data/sync/sync_api.dart';
import 'package:iprefer/data/sync/sync_op.dart';
import 'package:iprefer/data/sync/sync_outbox.dart';
import 'package:iprefer/data/sync/sync_service.dart';
import 'package:iprefer/data/sync/sync_validate.dart';
import 'package:iprefer/models/entry.dart';
import 'package:path/path.dart' as p;

/// Stands in for `server/`, including the parts that matter for correctness:
/// a monotonic op log, cursor-based paging, and idempotent creates.
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
    _guard();
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
  Future<void> uploadPhoto(String name, Uint8List bytes) async {
    _guard();
    photos[name] = bytes;
  }

  @override
  Future<Uint8List?> downloadPhoto(String name) async {
    _guard();
    return photos[name];
  }
}

void main() {
  late Directory tempDir;
  late Box<Entry> entriesBox;
  late SyncOutbox outbox;
  late EntryStore store;
  late FakeSyncApi api;
  late SyncService sync;
  late String photosRoot;

  final when = DateTime.fromMillisecondsSinceEpoch(1755000000000);
  var boxSeq = 0;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('iprefer_sync_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(EntryAdapter());

    // Unique names so each test gets clean boxes.
    final n = boxSeq++;
    entriesBox = await Hive.openBox<Entry>('entries_$n');
    outbox = SyncOutbox.forTest(
      await Hive.openBox('ops_$n'),
      await Hive.openBox('meta_$n'),
      await Hive.openBox('photos_$n'),
    );
    photosRoot = p.join(tempDir.path, 'photos');
    Directory(photosRoot).createSync(recursive: true);

    store = EntryStore.forTest(entriesBox, photosRoot: photosRoot, outbox: outbox);
    api = FakeSyncApi();
    sync = SyncService(api: api, outbox: outbox, store: store);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File sourcePhoto([String name = 'picked.jpg']) {
    final f = File(p.join(tempDir.path, name));
    f.writeAsBytesSync(List.filled(64, 9));
    return f;
  }

  Future<Entry> record({String text = 'a flat white'}) => store.create(
        sourcePhotoPath: sourcePhoto().path,
        text: text,
        createdAt: when,
        tags: const ['coffee'],
      );

  Entry remoteEntry(String id, {String text = 'from another phone'}) => Entry(
        id: id,
        localPath: '$id.jpg',
        text: text,
        createdAt: when,
        tags: const ['wine'],
      );

  group('Entry wire format', () {
    test('round-trips through the sync json', () {
      final original = Entry(
        id: '11111111-1111-4111-8111-111111111111',
        localPath: '11111111-1111-4111-8111-111111111111.png',
        text: 'ferns that uncurl like a slow question',
        createdAt: when,
        latitude: -36.8485,
        longitude: 174.7633,
        placeLabel: 'fitzroy',
        tags: const ['plants'],
      );

      final back = Entry.fromSyncJson(original.toSyncJson());

      expect(back.id, original.id);
      expect(back.text, original.text);
      expect(back.createdAt, original.createdAt);
      expect(back.latitude, original.latitude);
      expect(back.placeLabel, original.placeLabel);
      expect(back.tags, original.tags);
      expect(back.localPath, original.localPath);
    });

    test('derives the photo name from the id, not a legacy absolute path', () {
      final legacy = Entry(
        id: '22222222-2222-4222-8222-222222222222',
        localPath: '/var/mobile/Containers/OLD-UUID/Documents/photos/whatever.JPG',
        text: 'x',
        createdAt: when,
      );

      // Never leaks the device path, and always matches the server's
      // "<entryId>.<ext>" rule.
      expect(legacy.syncPhotoName, '22222222-2222-4222-8222-222222222222.jpg');
    });
  });

  group('outbox', () {
    test('recording an entry queues a create and a photo upload', () async {
      final entry = await record();

      expect(outbox.pending.map((o) => o.type), [SyncOpType.create]);
      expect(outbox.pending.single.entryId, entry.id);
      expect(outbox.pendingPhotoUploads, {entry.syncPhotoName});
    });

    test('queueing the same op twice keeps one row', () async {
      final entry = await record();
      await outbox.enqueueCreate(entry);

      expect(outbox.pending.length, 1);
    });

    test('deleting drops the pending photo upload but still queues the delete',
        () async {
      final entry = await record();
      await store.delete(entry.id);

      expect(outbox.pending.map((o) => o.type),
          [SyncOpType.create, SyncOpType.delete]);
      expect(outbox.pendingPhotoUploads, isEmpty);
    });

    test('announces a save, so a status line cannot report a stale count',
        () async {
      var notified = 0;
      outbox.addListener(() => notified++);

      await record();

      // Without this the backup line reads a count captured before the save
      // it is meant to describe — claiming "backed up" at the exact moment
      // something isn't.
      expect(notified, greaterThan(0));
    });

    test('announces a delete too', () async {
      final entry = await record();
      var notified = 0;
      outbox.addListener(() => notified++);

      await store.delete(entry.id);

      expect(notified, greaterThan(0));
    });

    test('remembers when the last sync finished, across launches', () async {
      expect(outbox.lastSyncedAt, isNull);

      await sync.syncNow();

      expect(outbox.lastSyncedAt, isNotNull);
      // Reading through the outbox is what makes it survive a relaunch and a
      // service swap; an in-memory field always looked like "no idea".
      final reopened = SyncService(api: api, outbox: outbox, store: store);
      expect(reopened.lastSyncedAt, outbox.lastSyncedAt);
    });

    test('the cursor never moves backwards', () async {
      await outbox.setCursor(7);
      await outbox.setCursor(3);

      expect(outbox.cursor, 7);
    });
  });

  group('adopting a guest archive at sign-in', () {
    const String accountA = 'apple-user-a';
    const String accountB = 'apple-user-b';

    /// A store with no outbox behind it — entries recorded as a guest.
    EntryStore guestArchive() =>
        EntryStore.forTest(entriesBox, photosRoot: photosRoot);

    /// Signs A in, lets the archive reach the server, then signs out the way
    /// the app does.
    Future<void> signInAdoptAndOut(EntryStore archive) async {
      await outbox.adoptExisting(archive.entries, userId: accountA);
      await outbox.forget(outbox.pending);
      for (final name in outbox.pendingPhotoUploads.toList()) {
        await outbox.markPhotoUploaded(name);
      }
      await outbox.reset();
    }

    test('queues entries recorded before there was an account', () async {
      final guestStore = guestArchive();
      await guestStore.create(
          sourcePhotoPath: sourcePhoto('a.jpg').path, text: 'one', createdAt: when);
      await guestStore.create(
          sourcePhotoPath: sourcePhoto('b.jpg').path, text: 'two', createdAt: when);
      expect(outbox.pending, isEmpty);

      await outbox.adoptExisting(guestStore.entries, userId: accountA);

      expect(outbox.pending.length, 2);
      expect(outbox.pendingPhotoUploads.length, 2);
    });

    test('runs once, so relaunching never re-uploads the archive', () async {
      final guestStore = guestArchive();
      final entry = await guestStore.create(
          sourcePhotoPath: sourcePhoto('a.jpg').path, text: 'one', createdAt: when);

      await outbox.adoptExisting(guestStore.entries, userId: accountA);
      await outbox.forget(outbox.pending);
      await outbox.markPhotoUploaded(entry.syncPhotoName);

      // Every subsequent launch calls this again.
      await outbox.adoptExisting(guestStore.entries, userId: accountA);

      expect(outbox.pending, isEmpty,
          reason: 'a second adoption would re-push the whole archive');
      expect(outbox.pendingPhotoUploads, isEmpty,
          reason: 'and would re-upload every photo, which is the expensive half');
    });

    test('a second account on the same phone adopts nothing', () async {
      final guestStore = guestArchive();
      await guestStore.create(
          sourcePhotoPath: sourcePhoto('a.jpg').path, text: 'one', createdAt: when);
      await signInAdoptAndOut(guestStore);

      await outbox.adoptExisting(guestStore.entries, userId: accountB);

      // These entries are A's. Adopting them here is how one person's photos
      // end up in another person's account on a shared or resold phone.
      expect(outbox.pending, isEmpty);
      expect(outbox.pendingPhotoUploads, isEmpty);
      // They stay on the device, though: signing out must not cost anyone
      // photos that were never backed up.
      expect(guestStore.entries.length, 1);
    });

    test('signing back into the same account adopts nothing', () async {
      final guestStore = guestArchive();
      await guestStore.create(
          sourcePhotoPath: sourcePhoto('a.jpg').path, text: 'one', createdAt: when);
      await signInAdoptAndOut(guestStore);

      await outbox.adoptExisting(guestStore.entries, userId: accountA);

      // The server already has them; the pull that follows brings back
      // anything this device is missing.
      expect(outbox.pending, isEmpty);
      expect(outbox.pendingPhotoUploads, isEmpty);
      expect(outbox.accountId, accountA);
    });

    test('a queue left by the previous account never reaches the next one',
        () async {
      final guestStore = guestArchive();
      await guestStore.create(
          sourcePhotoPath: sourcePhoto('a.jpg').path, text: 'one', createdAt: when);
      await outbox.adoptExisting(guestStore.entries, userId: accountA);
      await outbox.setCursor(9);
      expect(outbox.pending.length, 1);

      // No reset in between — a sign-out killed mid-write, or a crash.
      await outbox.adoptExisting(guestStore.entries, userId: accountB);

      expect(outbox.pending, isEmpty, reason: "those ops are A's");
      expect(outbox.pendingPhotoUploads, isEmpty);
      // A's cursor would have made B skip its own log from the start.
      expect(outbox.cursor, 0);
      expect(outbox.accountId, accountB);
    });
  });

  group('ops the server would reject', () {
    /// An entry as a torn Hive record reads back: every cast in EntryAdapter
    /// softens to a default, so a bad row becomes id: '' / text: ''.
    Entry torn() => Entry(id: '', localPath: '', text: '', createdAt: when);

    test('an unsendable entry is dropped instead of blocking the queue',
        () async {
      await outbox.enqueueCreate(torn());
      // The server 400s a push on its first bad op, so the entry that follows
      // would never reach it either.
      final good = await record();

      expect(outbox.pending.map((o) => o.entryId), [good.id]);
      expect(outbox.pendingPhotoUploads, {good.syncPhotoName});
    });

    test('an entry with more tags than the server accepts is dropped',
        () async {
      final entry = Entry(
        id: '88888888-8888-4888-8888-888888888888',
        localPath: '88888888-8888-4888-8888-888888888888.jpg',
        text: 'a shelf for everything',
        createdAt: when,
        // normalizeTags caps each tag's length but never how many there are.
        tags: [for (var i = 0; i < 40; i++) 'tag$i'],
      );

      await outbox.enqueueCreate(entry);

      expect(outbox.pending, isEmpty);
      expect(outbox.pendingPhotoUploads, isEmpty);
    });

    test('a photo extension the server will not store is dropped', () {
      final entry = Entry(
        id: '99999999-9999-4999-8999-999999999999',
        localPath: '/old/container/Documents/photos/whatever.gif',
        text: 'a moving picture',
        createdAt: when,
      );

      expect(syncOpProblem(SyncOp.create(entry)), isNotNull);
      expect(syncOpProblem(SyncOp.create(remoteEntry(
        '99999999-9999-4999-8999-999999999999',
      ))), isNull);
    });

    test('an op queued before this check existed is skipped, then swept',
        () async {
      // Straight into the box, the way an older build would have written it.
      final legacyOps = await Hive.openBox('legacy_ops');
      await legacyOps.put(
        'create:',
        jsonEncode({
          'type': 'create',
          'entryId': '',
          'payload': {
            'id': '',
            'text': '',
            'createdAt': when.millisecondsSinceEpoch,
            'tags': <String>[],
            'photoName': '.jpg',
          },
        }),
      );
      final legacy = SyncOutbox.forTest(
        legacyOps,
        await Hive.openBox('legacy_meta'),
        await Hive.openBox('legacy_photos'),
      );

      expect(legacy.pending, isEmpty,
          reason: 'sending it would 400 the whole batch, forever');

      // Nothing will ever push it, so nothing would ever forget it — and the
      // backup line would sit at "1 waiting" for the life of the install.
      await legacy.forget(const []);
      expect(legacy.pendingCount, 0);
    });
  });

  group('push', () {
    test('sends pending ops and forgets them', () async {
      await record();

      final result = await sync.syncNow();

      expect(result.ok, isTrue);
      expect(result.pushed, 1);
      expect(api.pushes.single.single.type, SyncOpType.create);
      expect(outbox.pending, isEmpty);
    });

    test('a failure keeps the queue intact and never throws', () async {
      final entry = await record();
      api.offline = true;

      final result = await sync.syncNow();

      expect(result.ok, isFalse);
      expect(result.error, isA<SyncApiException>());
      // The entry is still safe locally and still owed to the server.
      expect(store.byId(entry.id), isNotNull);
      expect(outbox.pending.length, 1);
      expect(outbox.cursor, 0);
    });

    test('re-pushing after a failure sends the op exactly once', () async {
      await record();
      api.offline = true;
      await sync.syncNow();

      api.offline = false;
      await sync.syncNow();

      expect(api.log.where((r) => r.op.type == SyncOpType.create).length, 1);
      expect(outbox.pending, isEmpty);
    });
  });

  group('pull', () {
    test('applies another device\'s create', () async {
      api.seedRemote(SyncOp.create(remoteEntry('33333333-3333-4333-8333-333333333333')));

      final result = await sync.syncNow();

      expect(result.pulled, 1);
      final applied = store.byId('33333333-3333-4333-8333-333333333333');
      expect(applied, isNotNull);
      expect(applied!.text, 'from another phone');
      expect(applied.tags, ['wine']);
    });

    test('a pulled op does NOT bounce back into the outbox', () async {
      api.seedRemote(SyncOp.create(remoteEntry('44444444-4444-4444-8444-444444444444')));

      await sync.syncNow();

      // The whole point: applying a remote op must not queue it for the
      // server, or two devices ping-pong the same entry forever.
      expect(outbox.pending, isEmpty);
      expect(api.pushes, isEmpty);
    });

    test('applies another device\'s delete', () async {
      final entry = await record();
      await sync.syncNow(); // ship it
      api.seedRemote(SyncOp.delete(entry.id));

      await sync.syncNow();

      expect(store.byId(entry.id), isNull);
      expect(outbox.pending, isEmpty);
    });

    test('a delete for an entry we never had is harmless', () async {
      api.seedRemote(const SyncOp.delete('55555555-5555-4555-8555-555555555555'));

      final result = await sync.syncNow();

      expect(result.ok, isTrue);
      expect(store.entries, isEmpty);
    });

    test('receiving our own create back does not duplicate it', () async {
      final entry = await record();

      await sync.syncNow(); // pushes, then pulls its own op straight back

      expect(store.entries.where((e) => e.id == entry.id).length, 1);
      expect(store.entries.length, 1);
    });

    test('pages through a log longer than one request', () async {
      for (var i = 0; i < 5; i++) {
        api.seedRemote(SyncOp.create(remoteEntry('6666666$i-6666-4666-8666-666666666666')));
      }
      final paged = SyncService(api: api, outbox: outbox, store: store, pageLimit: 2);

      final result = await paged.syncNow();

      expect(result.pulled, 5);
      expect(store.entries.length, 5);
      expect(outbox.cursor, 5);
    });
  });

  group('the cursor rule', () {
    test("a push never advances the cursor past another device's earlier op",
        () async {
      // Another device wrote first (seq 1) and this device has not seen it.
      api.seedRemote(SyncOp.create(remoteEntry('77777777-7777-4777-8777-777777777777')));
      // This device records its own entry, which will land at seq 2.
      final mine = await record();

      await sync.syncNow();

      // If the cursor had jumped to the seq returned by push (2), seq 1 would
      // have been skipped forever and the other device's entry would never
      // arrive on this phone.
      expect(store.byId('77777777-7777-4777-8777-777777777777'), isNotNull,
          reason: 'the earlier op from another device must not be skipped');
      expect(store.byId(mine.id), isNotNull);
      expect(outbox.cursor, 2);
    });
  });

  group('photos', () {
    test('uploads what this device recorded, then stops tracking it', () async {
      final entry = await record();

      final result = await sync.syncNow();

      expect(result.photosUploaded, 1);
      expect(api.photos.keys, [entry.syncPhotoName]);
      expect(outbox.pendingPhotoUploads, isEmpty);
    });

    test('downloads a photo for an entry that arrived from another device',
        () async {
      const id = '88888888-8888-4888-8888-888888888888';
      api.seedRemote(SyncOp.create(remoteEntry(id)));
      api.photos['$id.jpg'] = Uint8List.fromList([1, 2, 3, 4]);

      final result = await sync.syncNow();

      expect(result.photosDownloaded, 1);
      final onDisk = File(p.join(photosRoot, '$id.jpg'));
      expect(onDisk.existsSync(), isTrue);
      expect(onDisk.readAsBytesSync(), [1, 2, 3, 4]);
    });

    test('an entry whose photo the other device has not uploaded yet is fine',
        () async {
      const id = '99999999-9999-4999-8999-999999999999';
      api.seedRemote(SyncOp.create(remoteEntry(id)));

      final result = await sync.syncNow();

      expect(result.ok, isTrue);
      expect(result.photosDownloaded, 0);
      // The record still landed — the entry is usable before its photo is.
      expect(store.byId(id), isNotNull);
    });

    test('a queued upload whose file vanished stops being retried', () async {
      final entry = await record();
      File(p.join(photosRoot, entry.syncPhotoName)).deleteSync();

      final result = await sync.syncNow();

      expect(result.ok, isTrue);
      expect(result.photosUploaded, 0);
      expect(outbox.pendingPhotoUploads, isEmpty);
    });

    test('a downloaded photo is not fetched again on the next sync', () async {
      const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      api.seedRemote(SyncOp.create(remoteEntry(id)));
      api.photos['$id.jpg'] = Uint8List.fromList([7, 7]);
      await sync.syncNow();

      final second = await sync.syncNow();

      expect(second.photosDownloaded, 0);
    });
  });

  group('an expired session', () {
    test('is reported as needing a sign-in rather than a plain failure',
        () async {
      await record();
      api.expired = true;

      final result = await sync.syncNow();

      expect(result.ok, isFalse);
      expect(result.error, isA<SyncAuthExpiredException>());
      expect(sync.needsReauth, isTrue);
    });

    test('stops retrying, instead of hammering a dead token forever', () async {
      await record();
      api.expired = true;
      await sync.syncNow();
      final callsAfterFirst = api.pushCalls;

      // Every resume, every save, every launch would otherwise try again.
      await sync.syncNow();
      await sync.syncNow();

      expect(api.pushCalls, callsAfterFirst,
          reason: 'a lapsed session must not keep generating requests');
      expect(callsAfterFirst, 1, reason: 'the first attempt did reach the server');
    });

    test('keeps the queue and the archive intact', () async {
      final entry = await record();
      api.expired = true;

      await sync.syncNow();

      expect(store.byId(entry.id), isNotNull);
      expect(outbox.pending.length, 1,
          reason: 'everything must still be owed once the session is renewed');
      expect(outbox.cursor, 0);
    });

    test('tells the session once, so the app can ask for one sign-in',
        () async {
      var told = 0;
      final watched = SyncService(
        api: api,
        outbox: outbox,
        store: store,
        onAuthExpired: () async => told++,
      );
      await record();
      api.expired = true;

      await watched.syncNow();
      await watched.syncNow();

      expect(told, 1);
    });

    test('a renewed session resumes exactly where it stopped', () async {
      final entry = await record();
      api.expired = true;
      await sync.syncNow();

      // Signing in again produces a new service with a fresh token.
      api.expired = false;
      final renewed = SyncService(api: api, outbox: outbox, store: store);
      final result = await renewed.syncNow();

      expect(result.ok, isTrue);
      expect(result.pushed, 1);
      expect(outbox.pending, isEmpty);
      expect(api.log.any((r) => r.op.entryId == entry.id), isTrue);
    });
  });

  group('no account', () {
    test('a service with no api reports itself off and does nothing', () async {
      final guest = SyncService(api: null, outbox: outbox, store: store);
      await record();

      final result = await guest.syncNow();

      expect(guest.enabled, isFalse);
      expect(result.ok, isTrue);
      expect(result.changedAnything, isFalse);
      // The queue survives, ready for the day an account appears.
      expect(outbox.pending.length, 1);
    });
  });

  group('sync with no backend configured', () {
    test('the store works exactly as before when there is no outbox', () async {
      final plain = EntryStore.forTest(entriesBox, photosRoot: photosRoot);

      final entry = await plain.create(
        sourcePhotoPath: sourcePhoto('other.jpg').path,
        text: 'local only',
        createdAt: when,
      );

      expect(plain.byId(entry.id), isNotNull);
      expect(outbox.pending, isEmpty);
    });
  });
}
