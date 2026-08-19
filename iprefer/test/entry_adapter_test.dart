import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:iprefer/models/entry.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('iprefer_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(EntryAdapter());
    }
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('Entry survives a Hive round-trip with a location', () async {
    final box = await Hive.openBox<Entry>('entries_test');
    final original = Entry(
      id: 'abc-123',
      localPath: '/photos/abc-123.jpg',
      text: 'ferns that uncurl like a slow question',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      latitude: -37.7983,
      longitude: 144.9784,
      placeLabel: 'fitzroy',
      tags: const ['wine', 'dish'],
    );

    await box.put(original.id, original);
    await box.close();

    final restored = (await Hive.openBox<Entry>('entries_test')).get('abc-123')!;

    expect(restored.id, original.id);
    expect(restored.localPath, original.localPath);
    expect(restored.text, original.text);
    expect(restored.createdAt, original.createdAt);
    expect(restored.latitude, closeTo(-37.7983, 1e-9));
    expect(restored.longitude, closeTo(144.9784, 1e-9));
    expect(restored.placeLabel, 'fitzroy');
    expect(restored.hasLocation, isTrue);
    expect(restored.tags, ['wine', 'dish']);
  });

  test('an entry with no location round-trips as unlocated', () async {
    final box = await Hive.openBox<Entry>('entries_test');
    await box.put(
      'no-loc',
      Entry(
        id: 'no-loc',
        localPath: '/photos/no-loc.jpg',
        text: 'a flat white before the world wakes up',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      ),
    );
    await box.close();

    final restored = (await Hive.openBox<Entry>('entries_test')).get('no-loc')!;

    expect(restored.hasLocation, isFalse);
    expect(restored.latitude, isNull);
    expect(restored.placeLabel, isNull);
    // Entries written before tags existed must read back as untagged, not fail.
    expect(restored.tags, isEmpty);
    // An unlocated entry must never satisfy a proximity test.
    expect(restored.metresTo(-37.7983, 144.9784), double.infinity);
  });
}
