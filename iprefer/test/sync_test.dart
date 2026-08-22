import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:iprefer/data/entry_store.dart';
import 'package:iprefer/data/sync/sync_api.dart';
import 'package:iprefer/data/sync/sync_op.dart';
import 'package:iprefer/data/sync/sync_outbox.dart';
import 'package:iprefer/data/sync/sync_service.dart';
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

  /// Simulates an op written by another device.
  void seedRemote(SyncOp op) => log.add(RemoteOp(seq: _nextSeq++, op: op));

  @override
  Future<int> push(List<SyncOp> ops) async {
    if (offline) throw SyncApiException('offline');
    pushes.add(List.of(ops));
    for (final op in ops) {
      final already = log.any((r) => r.op.type == op.type && r.op.entryId == op.entryId);
      if (!already) log.add(RemoteOp(seq: _nextSeq++, op: op));
    }
    return log.isEmpty ? 0 : log.last.seq;
  }

  @override
  Future<PullPage> pull({required int since, int limit = 200}) async {
    if (offline) throw SyncApiException('offline');
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
    if (offline) throw SyncApiException('offline');
    photos[name] = bytes;
  }

  @override
  Future<Uint8List?> downloadPhoto(String name) async {
    if (offline) throw SyncApiException('offline');
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

    test('the cursor never moves backwards', () async {
      await outbox.setCursor(7);
      await outbox.setCursor(3);

      expect(outbox.cursor, 7);
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
