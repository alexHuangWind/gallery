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

  test('Entry survives a Hive write/read round-trip', () async {
    final box = await Hive.openBox<Entry>('entries_test');
    final original = Entry(
      id: 'abc-123',
      localPath: '/photos/abc-123.jpg',
      text: 'ferns that uncurl like a slow question',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

    await box.put(original.id, original);
    await box.close();

    final reopened = await Hive.openBox<Entry>('entries_test');
    final restored = reopened.get('abc-123')!;

    expect(restored.id, original.id);
    expect(restored.localPath, original.localPath);
    expect(restored.text, original.text);
    expect(restored.createdAt, original.createdAt);
  });
}
