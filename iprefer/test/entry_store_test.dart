import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:iprefer/data/entry_store.dart';
import 'package:iprefer/models/entry.dart';
import 'package:path/path.dart' as p;

/// These tests exercise the store's real contracts through EntryStore.forTest —
/// a real Hive box in a temp dir, a real photos directory. Per the project
/// rule, they call production methods; nothing here re-implements store logic.
void main() {
  // writePhotoBytes talks to PaintingBinding.instance.imageCache, which needs a
  // binding; these are plain `test`s, so nothing else would have set one up.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<Entry> box;
  late String photosRoot;
  late EntryStore store;

  final when = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  Entry entryAt(
    String id, {
    double? lat,
    double? lng,
    List<String> tags = const [],
    String? localPath,
    DateTime? createdAt,
  }) =>
      Entry(
        id: id,
        localPath: localPath ?? '$id.jpg',
        text: 'thing $id',
        createdAt: createdAt ?? when,
        latitude: lat,
        longitude: lng,
        tags: tags,
      );

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('iprefer_store_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(EntryAdapter());
    }
    box = await Hive.openBox<Entry>('store_test');
    photosRoot = p.join(tempDir.path, 'photos');
    store = EntryStore.forTest(box, photosRoot: photosRoot);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// A fake "picked photo" on disk for create() to copy.
  File writeSourcePhoto([String name = 'picked.jpg']) {
    final f = File(p.join(tempDir.path, name));
    f.writeAsBytesSync(List.filled(32, 7));
    return f;
  }

  group('create', () {
    test('copies the photo under photosRoot and writes the record', () async {
      final source = writeSourcePhoto();
      var notified = 0;
      store.addListener(() => notified++);

      final entry = await store.create(
        sourcePhotoPath: source.path,
        text: 'a flat white before the world wakes up',
        createdAt: when,
        tags: const ['coffee'],
      );

      // Stored by NAME, never absolute path.
      expect(p.isAbsolute(entry.localPath), isFalse);
      expect(entry.localPath, '${entry.id}.jpg');
      expect(File(p.join(photosRoot, entry.localPath)).existsSync(), isTrue);
      expect(box.get(entry.id), isNotNull);
      expect(box.get(entry.id)!.text, entry.text);
      expect(notified, 1);
    });

    test('keeps the source extension, falls back to .jpg without one',
        () async {
      final png = writeSourcePhoto('picked.png');
      final bare = writeSourcePhoto('picked');

      final fromPng =
          await store.create(sourcePhotoPath: png.path, text: 'x', createdAt: when);
      final fromBare =
          await store.create(sourcePhotoPath: bare.path, text: 'y', createdAt: when);

      expect(p.extension(fromPng.localPath), '.png');
      expect(p.extension(fromBare.localPath), '.jpg');
    });

    test('rolls back the photo copy when the record write fails', () async {
      final source = writeSourcePhoto();
      await box.close(); // makes _box.put throw

      await expectLater(
        store.create(sourcePhotoPath: source.path, text: 'x', createdAt: when),
        throwsA(isA<HiveError>()),
      );

      // The copied photo must not be left orphaned.
      final photosDir = Directory(photosRoot);
      final leftovers =
          photosDir.existsSync() ? photosDir.listSync() : const <FileSystemEntity>[];
      expect(leftovers, isEmpty);
    });
  });

  group('delete', () {
    test('removes the record and then the photo', () async {
      final source = writeSourcePhoto();
      final entry = await store.create(
          sourcePhotoPath: source.path, text: 'x', createdAt: when);
      final photo = File(p.join(photosRoot, entry.localPath));
      expect(photo.existsSync(), isTrue);

      await store.delete(entry.id);

      expect(box.get(entry.id), isNull);
      expect(photo.existsSync(), isFalse);
    });

    test('still removes the record when the photo is already gone', () async {
      await store.add(entryAt('ghost', localPath: 'nowhere.jpg'));

      await store.delete('ghost');

      expect(box.get('ghost'), isNull);
    });
  });

  group('fileFor', () {
    test('resolves a stored name against photosRoot', () {
      final f = store.fileFor(entryAt('e1', localPath: 'e1.jpg'));
      expect(f.path, p.join(photosRoot, 'e1.jpg'));
    });

    test('passes a legacy absolute path through untouched', () {
      final abs = p.join(tempDir.path, 'legacy', 'old.jpg');
      final f = store.fileFor(entryAt('e2', localPath: abs));
      expect(f.path, abs);
    });
  });

  group('tags', () {
    test('a cached read is invalidated by every mutation', () async {
      // entries/tagCounts/tagsByUse are memoized behind notifyListeners,
      // because a single frame asks for them several times over. A stale
      // cache would mean recording something and watching the timeline not
      // change, so pin the invalidation rather than trusting the plumbing.
      expect(store.entries, isEmpty);
      expect(store.tagCounts, isEmpty);

      final first = await store.create(
        sourcePhotoPath: writeSourcePhoto().path,
        text: 'a flat white',
        createdAt: when,
        tags: const ['coffee'],
      );
      expect(store.entries.map((e) => e.id), [first.id]);
      expect(store.tagCounts, {'coffee': 1});
      expect(store.tagsByUse, ['coffee']);

      await store.delete(first.id);
      expect(store.entries, isEmpty);
      expect(store.tagCounts, isEmpty);
      expect(store.tagsByUse, isEmpty);
    });

    test('the cached lists are not the caller\'s to mutate', () async {
      // Callers used to get a fresh copy they could safely sort in place, and
      // now they share one. Unmodifiable so that stops being silent.
      await store.create(
        sourcePhotoPath: writeSourcePhoto().path,
        text: 'one',
        createdAt: when,
      );

      expect(() => store.entries.removeAt(0), throwsUnsupportedError);
      expect(() => store.tagsByUse.add('x'), throwsUnsupportedError);
      expect(() => store.tagCounts['x'] = 1, throwsUnsupportedError);
    });

    test('tagCounts counts entries per tag', () async {
      await store.add(entryAt('a', tags: const ['wine']));
      await store.add(entryAt('b', tags: const ['wine', 'dish']));
      await store.add(entryAt('c', tags: const ['apple']));

      expect(store.tagCounts, {'wine': 2, 'dish': 1, 'apple': 1});
    });

    test('tagsByUse orders by count, ties broken alphabetically', () async {
      await store.add(entryAt('a', tags: const ['wine']));
      await store.add(entryAt('b', tags: const ['wine', 'dish']));
      await store.add(entryAt('c', tags: const ['apple']));

      expect(store.tagsByUse, ['wine', 'apple', 'dish']);
    });
  });

  group('photo bytes', () {
    test('writePhotoBytes tells the UI the photo landed', () async {
      // A downloaded photo that nothing announces is a tile that stays a grey
      // placeholder until the app restarts — on a second device, that is the
      // whole visible result of syncing.
      var notified = 0;
      store.addListener(() => notified++);

      await store.writePhotoBytes('e1.jpg', Uint8List.fromList([1, 2, 3]));

      expect(File(p.join(photosRoot, 'e1.jpg')).readAsBytesSync(), [1, 2, 3]);
      expect(notified, 1);
    });

    test('writePhotoBytes drops the stale image-cache entries', () async {
      // The failed resolve from when the file was missing lingers in the cache
      // and is handed to every later resolve of the same key, so the tile keeps
      // painting the placeholder even once the bytes are here. Both keys have
      // to go: full-size cards resolve the FileImage, grid tiles the
      // ResizeImage wrapper around it.
      final cache = PaintingBinding.instance.imageCache;
      final provider = FileImage(File(p.join(photosRoot, 'e1.jpg')));
      final compactKey = await ResizeImage(provider, width: 600)
          .obtainKey(ImageConfiguration.empty);
      cache.putIfAbsent(provider, _StuckCompleter.new);
      cache.putIfAbsent(compactKey, _StuckCompleter.new);
      expect(cache.containsKey(provider), isTrue);
      expect(cache.containsKey(compactKey), isTrue);

      await store.writePhotoBytes('e1.jpg', Uint8List.fromList([1]));

      expect(cache.containsKey(provider), isFalse);
      expect(cache.containsKey(compactKey), isFalse);
    });

    test('writePhotoBytes creates the photos directory if it is gone',
        () async {
      expect(Directory(photosRoot).existsSync(), isFalse);

      await store.writePhotoBytes('e1.jpg', Uint8List.fromList([9]));

      expect(File(p.join(photosRoot, 'e1.jpg')).existsSync(), isTrue);
    });

    test('readPhotoBytes finds a legacy entry\'s photo by its sync name',
        () async {
      // Records written before the name-not-path change hold an absolute path,
      // so photosRoot/<syncPhotoName> does not exist for them. Returning null
      // here makes the sync service mark the upload done and drop the photo
      // for good — silently, for every entry recorded before that change.
      final legacyDir = Directory(p.join(tempDir.path, 'legacy'))
        ..createSync(recursive: true);
      final legacyPhoto = File(p.join(legacyDir.path, 'IMG_0042.JPG'))
        ..writeAsBytesSync([4, 2]);
      final entry = entryAt('old-1', localPath: legacyPhoto.path);
      await store.add(entry);

      expect(await store.readPhotoBytes(entry.syncPhotoName), [4, 2]);
    });

    test('readPhotoBytes is still null when the file is really gone', () async {
      await store.add(entryAt('ghost', localPath: 'ghost.jpg'));

      expect(await store.readPhotoBytes('ghost.jpg'), isNull);
    });
  });

  group('near', () {
    // 0.001° of latitude ≈ 111 m.
    test('filters by radius and returns nearest first', () async {
      await store.add(entryAt('near', lat: 0.0005, lng: 0)); // ~55 m
      await store.add(entryAt('mid', lat: 0.001, lng: 0)); // ~111 m
      await store.add(entryAt('far', lat: 0.003, lng: 0)); // ~333 m

      final hits = store.near(0, 0);

      expect(hits.map((e) => e.id), ['near', 'mid']);
    });

    test('composes with the tag filter', () async {
      await store.add(entryAt('wine', lat: 0.0005, lng: 0, tags: const ['wine']));
      await store.add(entryAt('dish', lat: 0.001, lng: 0, tags: const ['dish']));

      final hits = store.near(0, 0, tags: const {'wine'});

      expect(hits.map((e) => e.id), ['wine']);
    });
  });
}

/// An image that never resolves, standing in for the resolve that *failed*
/// while the photo was still downloading — both sit in the cache under the same
/// key, and both make a tile paint the placeholder forever if they survive.
class _StuckCompleter extends ImageStreamCompleter {}
