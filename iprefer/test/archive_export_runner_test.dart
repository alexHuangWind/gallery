import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:iprefer/data/archive_export_runner.dart';
import 'package:iprefer/data/entry_store.dart';
import 'package:iprefer/models/entry.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

/// What the shell used to do inline, now testable without a platform.
///
/// The assertions worth having here are the ones a widget could not make: that
/// the work directory is gone afterwards *whatever* the share sheet did, and
/// that a copy with gaps in it says so.
void main() {
  late Directory tempDir;
  late Directory photosRoot;
  late Box<Entry> box;
  late EntryStore store;
  var seq = 0;

  final now = DateTime.utc(2026, 9, 2, 11, 30);

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('iprefer_export_runner_test');
    Hive.init(p.join(tempDir.path, 'hive'));
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(EntryAdapter());
    box = await Hive.openBox<Entry>('entries_${seq++}');
    photosRoot = Directory(p.join(tempDir.path, 'photos'))
      ..createSync(recursive: true);
    store = EntryStore.forTest(box, photosRoot: photosRoot.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Where the runner is told to build, and where the zip should not survive.
  Directory workDir() =>
      Directory(p.join(tempDir.path, ArchiveExportRunner.workDirName));

  Future<Directory> temp() async => tempDir;

  Future<void> add(String id, {bool withPhoto = true}) async {
    if (withPhoto) {
      File(p.join(photosRoot.path, '$id.jpg')).writeAsBytesSync([1, 2, 3]);
    }
    await store.applyRemoteCreate(Entry(
      id: id,
      localPath: '$id.jpg',
      text: 'a flat white before the world wakes up',
      createdAt: DateTime.utc(2026, 8, 20),
    ));
  }

  test('an empty archive packs nothing and opens no sheet', () async {
    var shared = 0;
    final runner = ArchiveExportRunner(
      temporaryDirectory: temp,
      share: (file, origin) async => shared++,
    );

    final reported = <ExportOutcome>[];
    final outcome = await runner.run(
      store: store,
      now: now,
      onOutcome: reported.add,
    );

    expect(outcome.status, ExportStatus.nothingToSave);
    expect(reported.single.status, ExportStatus.nothingToSave);
    expect(shared, 0);
    // Nothing was built, so nothing was left behind either.
    expect(workDir().existsSync(), isFalse);
  });

  test(
      'a packed archive reaches the sheet, and the work directory does not '
      'outlive it', () async {
    await add('a');
    await add('b');

    XFile? offered;
    Rect? anchoredAt;
    final runner = ArchiveExportRunner(
      temporaryDirectory: temp,
      share: (file, origin) async {
        offered = file;
        anchoredAt = origin;
        // The file has to still be there while the sheet is up — cleanup that
        // ran before this point would hand the system a path to nothing.
        expect(File(file.path).existsSync(), isTrue);
      },
    );

    final outcome = await runner.run(
      store: store,
      now: now,
      origin: const Rect.fromLTWH(0, 0, 320, 640),
    );

    expect(outcome.status, ExportStatus.packed);
    expect(outcome.missingPhotos, 0);
    expect(p.basename(offered!.path), 'i-prefer-2026-09-02.zip');
    // Passed straight through: on iPad an unanchored sheet raises a native
    // exception no Dart catch can intercept.
    expect(anchoredAt, const Rect.fromLTWH(0, 0, 320, 640));
    expect(workDir().existsSync(), isFalse);
  });

  test('entries whose photo is gone are counted, not dropped', () async {
    await add('a');
    await add('b', withPhoto: false);
    await add('c', withPhoto: false);

    final runner = ArchiveExportRunner(
      temporaryDirectory: temp,
      share: (file, origin) async {},
    );

    final reported = <ExportOutcome>[];
    final outcome = await runner.run(
      store: store,
      now: now,
      onOutcome: reported.add,
    );

    expect(outcome.status, ExportStatus.packed);
    expect(outcome.missingPhotos, 2);
    // Reported before the sheet opened, which is the whole reason the callback
    // exists: on iOS the share future only completes on dismissal, so a
    // warning taken from the return value would land on someone who cancelled.
    expect(reported.single.missingPhotos, 2);
  });

  test('a share that throws still takes the work directory with it', () async {
    await add('a');

    final runner = ArchiveExportRunner(
      temporaryDirectory: temp,
      share: (file, origin) async =>
          throw const FileSystemException('no sheet'),
    );

    final reported = <ExportOutcome>[];
    final outcome = await runner.run(
      store: store,
      now: now,
      onOutcome: reported.add,
    );

    // The failure is reported, not thrown: the caller shows one sentence.
    expect(outcome.status, ExportStatus.failed);
    expect(reported.last.status, ExportStatus.failed);
    // Otherwise every refused sheet leaves a second copy of the whole archive
    // in a cache directory iOS does not reliably reclaim.
    expect(workDir().existsSync(), isFalse);
  });

  test('a temp directory that cannot be reached fails quietly', () async {
    await add('a');

    final runner = ArchiveExportRunner(
      temporaryDirectory: () async =>
          throw const FileSystemException('no temp'),
      share: (file, origin) async => fail('nothing to share'),
    );

    final outcome = await runner.run(store: store, now: now);

    expect(outcome.status, ExportStatus.failed);
    expect(outcome.missingPhotos, 0);
  });
}
