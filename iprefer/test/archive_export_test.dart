import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iprefer/data/archive_export.dart';
import 'package:iprefer/models/entry.dart';
import 'package:path/path.dart' as p;

/// The export is a promise that the record outlives us, so the assertions are
/// about the file a stranger would open in a year — not about our own types.
/// Everything here reads the zip back with a decoder that knows nothing about
/// the encoder that wrote it.
void main() {
  late Directory tempDir;
  late String photosRoot;
  late Directory workDir;

  final now = DateTime.utc(2026, 9, 2, 11, 30);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('iprefer_export_test');
    photosRoot = p.join(tempDir.path, 'photos');
    Directory(photosRoot).createSync(recursive: true);
    workDir = Directory(p.join(tempDir.path, 'work'));
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Entry write(
    String id,
    String text, {
    List<String> tags = const [],
    String? place,
    bool onDisk = true,
    String? fileName,
  }) {
    final name = fileName ?? '$id.jpg';
    if (onDisk) {
      File(p.join(photosRoot, name))
          .writeAsBytesSync([1, 2, 3, 4, id.codeUnitAt(0)]);
    }
    return Entry(
      id: id,
      localPath: name,
      text: text,
      createdAt: DateTime.utc(2026, 8, 20),
      placeLabel: place,
      tags: tags,
    );
  }

  Future<Archive> packAndRead(List<Entry> entries) async {
    final result = await ArchiveExport.pack(
      entries: entries,
      photosRoot: photosRoot,
      workDir: workDir,
      now: now,
    );
    expect(result.file.existsSync(), isTrue);
    return ZipDecoder().decodeBytes(result.file.readAsBytesSync());
  }

  test('the zip holds the manifest and every photo', () async {
    final entries = [
      write('a', 'a flat white', place: 'Cuba Street', tags: ['coffee']),
      write('b', 'ferns'),
    ];

    final zip = await packAndRead(entries);
    final names = zip.files.map((f) => f.name).toSet();

    expect(
        names, containsAll(['entries.json', 'photos/a.jpg', 'photos/b.jpg']));
  });

  test('the photos come back byte for byte', () async {
    final entries = [write('a', 'a flat white')];

    final zip = await packAndRead(entries);
    final photo = zip.files.firstWhere((f) => f.name == 'photos/a.jpg');

    expect(photo.content, File(p.join(photosRoot, 'a.jpg')).readAsBytesSync());
  });

  test('the manifest describes an entry the way the wire does', () async {
    // One shape for an entry, not two that can drift.
    final entry =
        write('a', 'a flat white', place: 'Cuba Street', tags: ['coffee']);

    final zip = await packAndRead([entry]);
    final manifest = jsonDecode(
      utf8.decode(
          zip.files.firstWhere((f) => f.name == 'entries.json').content),
    ) as Map<String, Object?>;

    expect(manifest['format'], ArchiveExport.formatVersion);
    expect(manifest['count'], 1);
    // Stamped from a LOCAL time on purpose: production passes DateTime.now(),
    // and a naive toIso8601String() would write an offset-less local string
    // that means nothing to a reader in another zone.
    final local = DateTime(2026, 9, 2, 11, 30);
    final localZip = await ArchiveExport.pack(
      entries: [entry],
      photosRoot: photosRoot,
      workDir: workDir,
      now: local,
    );
    final localManifest = jsonDecode(utf8.decode(ZipDecoder()
        .decodeBytes(localZip.file.readAsBytesSync())
        .files
        .firstWhere((f) => f.name == 'entries.json')
        .content)) as Map<String, Object?>;
    final stamped = localManifest['exportedAt']! as String;
    expect(stamped, endsWith('Z'));
    expect(DateTime.parse(stamped).isUtc, isTrue);
    expect(
      DateTime.parse(stamped).millisecondsSinceEpoch,
      local.millisecondsSinceEpoch,
    );

    final entries = manifest['entries']! as List;
    expect(entries.single, entry.toSyncJson());
  });

  test('a round trip rebuilds the entry', () async {
    // What an importer would actually do. If this passes, the export is a
    // real backup rather than a pile of files.
    final entry =
        write('a', 'a flat white', place: 'Cuba Street', tags: ['coffee']);

    final zip = await packAndRead([entry]);
    final manifest = jsonDecode(
      utf8.decode(
          zip.files.firstWhere((f) => f.name == 'entries.json').content),
    ) as Map<String, Object?>;

    final restored = Entry.fromSyncJson(
      (manifest['entries']! as List).single as Map<String, Object?>,
    );

    expect(restored.id, entry.id);
    expect(restored.text, entry.text);
    // The instant, not the object: the wire format is an epoch millisecond,
    // so a UTC DateTime comes back as the same moment in local time. That is
    // the sync format's behaviour, shared here on purpose.
    expect(
      restored.createdAt.millisecondsSinceEpoch,
      entry.createdAt.millisecondsSinceEpoch,
    );
    expect(restored.placeLabel, entry.placeLabel);
    expect(restored.tags, entry.tags);
    expect(restored.localPath, 'a.jpg'); // matches its name in photos/
  });

  test('a missing photo is counted, and its words are still saved', () async {
    // Normal on a phone that has synced an account but not yet pulled every
    // photo. The line and the place are the part that cannot be re-taken.
    final entries = [
      write('a', 'a flat white'),
      write('b', 'ferns', onDisk: false),
    ];

    final result = await ArchiveExport.pack(
      entries: entries,
      photosRoot: photosRoot,
      workDir: workDir,
      now: now,
    );

    expect(result.entryCount, 2);
    expect(result.photoCount, 1);
    expect(result.missingPhotos, 1);

    final zip = ZipDecoder().decodeBytes(result.file.readAsBytesSync());
    final manifest = jsonDecode(
      utf8.decode(
          zip.files.firstWhere((f) => f.name == 'entries.json').content),
    ) as Map<String, Object?>;

    expect((manifest['entries']! as List).length, 2);
    expect(zip.files.map((f) => f.name), isNot(contains('photos/b.jpg')));
  });

  test('an entry recorded before the name-not-path change still exports',
      () async {
    // Those hold an absolute path in localPath; the photo must still be found
    // and must still land under its id-derived name.
    final absolute = p.join(photosRoot, 'legacy.jpg');
    File(absolute).writeAsBytesSync([9, 9, 9]);
    final entry = Entry(
      id: 'legacy',
      localPath: absolute,
      text: 'from before',
      createdAt: DateTime.utc(2026, 1, 1),
    );

    final zip = await packAndRead([entry]);

    expect(zip.files.map((f) => f.name), contains('photos/legacy.jpg'));
  });

  test('a second export replaces the first rather than piling up', () async {
    // Different days, so the two would have different names and simply
    // overwriting is not what keeps this to one file. A phone must not
    // accumulate a full archive per tap.
    await ArchiveExport.pack(
      entries: [write('a', 'first')],
      photosRoot: photosRoot,
      workDir: workDir,
      now: DateTime.utc(2026, 9, 2),
    );
    await ArchiveExport.pack(
      entries: [write('b', 'second')],
      photosRoot: photosRoot,
      workDir: workDir,
      now: DateTime.utc(2026, 9, 3),
    );

    expect(workDir.listSync().map((f) => p.basename(f.path)),
        ['i-prefer-2026-09-03.zip']);
  });

  test('a photo is named by its entry id, not by its file on disk', () async {
    // syncPhotoName exists precisely for this: legacy records and records
    // whose file was renamed must still land under the id an importer will
    // look them up by.
    final entry = write('a', 'a flat white', fileName: 'IMG_4471.jpg');

    final zip = await packAndRead([entry]);

    expect(zip.files.map((f) => f.name), contains('photos/a.jpg'));
    expect(
        zip.files.map((f) => f.name), isNot(contains('photos/IMG_4471.jpg')));
  });

  test('the photos are stored, not deflated', () async {
    // JPEG does not deflate. Running it through zlib anyway costs a full pass
    // and a full in-memory buffer per photo, and makes the archive *bigger*
    // than its inputs — which is what a null compression silently did.
    File(p.join(photosRoot, 'a.jpg')).writeAsBytesSync(
      List<int>.generate(200000, (i) => (i * 2654435761) & 0xFF),
    );
    final entry = Entry(
      id: 'a',
      localPath: 'a.jpg',
      text: 'incompressible',
      createdAt: DateTime.utc(2026, 8, 20),
    );

    final zip = await packAndRead([entry]);
    final photo = zip.files.firstWhere((f) => f.name == 'photos/a.jpg');

    expect(photo.compression, CompressionType.none);
    expect(photo.size, 200000);
  });

  test('the manifest names the entries whose photo is absent', () async {
    // A reader finding a photoName with no file behind it must be able to
    // tell "was never on that phone" from "this zip is damaged".
    final entries = [
      write('a', 'a flat white'),
      write('b', 'ferns', onDisk: false),
    ];

    final zip = await packAndRead(entries);
    final manifest = jsonDecode(
      utf8.decode(
          zip.files.firstWhere((f) => f.name == 'entries.json').content),
    ) as Map<String, Object?>;

    expect(manifest['entriesWithoutPhotos'], ['b']);
  });

  test('count is the number of entries, not the number of photos', () async {
    // An importer using count to detect truncation must not be misled by an
    // archive that happens to be short some photos.
    final zip = await packAndRead([
      write('a', 'a flat white'),
      write('b', 'ferns', onDisk: false),
    ]);
    final manifest = jsonDecode(
      utf8.decode(
          zip.files.firstWhere((f) => f.name == 'entries.json').content),
    ) as Map<String, Object?>;

    expect(manifest['count'], 2);
    expect((manifest['entries']! as List).length, 2);
  });

  test('an id that would escape the photos directory is refused', () async {
    // Ids come from the server. Left unchecked, `../../x` becomes a zip entry
    // that unpacks outside the folder on whoever the user sends the file to.
    final hostile = Entry.fromSyncJson({
      'id': '../../../evil',
      'text': 'from a bad server',
      'createdAt': 0,
      'photoName': '../../../evil.jpg',
    });
    File(p.join(photosRoot, 'evil.jpg')).writeAsBytesSync([1]);

    final result = await ArchiveExport.pack(
      entries: [hostile],
      photosRoot: photosRoot,
      workDir: workDir,
      now: now,
    );
    final zip = ZipDecoder().decodeBytes(result.file.readAsBytesSync());

    expect(zip.files.map((f) => f.name), ['entries.json', 'README.txt']);
    expect(result.missingPhotos, 1);
    // The words still survive — only the file name was refused.
    expect(result.entryCount, 1);
  });

  test('a photo outside the photos directory is refused', () async {
    // Legacy records hold an absolute path and nothing validates where it
    // points; an entry must not be able to copy an arbitrary readable file
    // into something the user then hands to someone else.
    final outside = p.join(tempDir.path, 'secrets.txt');
    File(outside).writeAsStringSync('not yours');
    final entry = Entry(
      id: 'a',
      localPath: outside,
      text: 'sneaky',
      createdAt: DateTime.utc(2026, 8, 20),
    );

    final result = await ArchiveExport.pack(
      entries: [entry],
      photosRoot: photosRoot,
      workDir: workDir,
      now: now,
    );
    final zip = ZipDecoder().decodeBytes(result.file.readAsBytesSync());

    expect(zip.files.map((f) => f.name), ['entries.json', 'README.txt']);
    expect(result.missingPhotos, 1);
  });

  test('two entries cannot claim the same photo name', () async {
    // Only reachable through a torn record read back with an empty id, but
    // Archive.add replaces on a duplicate name — so without the guard the
    // second photo is in the file and invisible, and photoCount lies.
    Entry torn(String text) => Entry(
          id: '',
          localPath: 'x.jpg',
          text: text,
          createdAt: DateTime.utc(2026, 8, 20),
        );
    File(p.join(photosRoot, 'x.jpg')).writeAsBytesSync([1, 2, 3]);

    final result = await ArchiveExport.pack(
      entries: [torn('one'), torn('two')],
      photosRoot: photosRoot,
      workDir: workDir,
      now: now,
    );
    final zip = ZipDecoder().decodeBytes(result.file.readAsBytesSync());

    expect(zip.files.where((f) => f.name.startsWith('photos/')).length, 1);
    expect(result.photoCount, 1);
    expect(result.missingPhotos, 1);
  });

  test('the readme says what the file is without needing the app', () async {
    final zip = await packAndRead([write('a', 'a flat white')]);
    final readme = utf8.decode(
      zip.files.firstWhere((f) => f.name == 'README.txt').content,
    );

    expect(readme, contains('entries.json'));
    expect(readme, contains('photos/'));
    expect(readme, contains('1 entry'));
    expect(readme, contains('milliseconds'));
  });

  test('the file names itself by the day it was made', () {
    expect(ArchiveExport.fileNameFor(DateTime(2026, 9, 2)),
        'i-prefer-2026-09-02.zip');
    expect(ArchiveExport.fileNameFor(DateTime(2026, 12, 25)),
        'i-prefer-2026-12-25.zip');
  });

  test('an empty archive still produces a readable file', () async {
    // The UI refuses this case, but the packer should not be the thing that
    // enforces it — a zero-entry export is a valid, if dull, backup.
    final zip = await packAndRead([]);
    final manifest = jsonDecode(
      utf8.decode(
          zip.files.firstWhere((f) => f.name == 'entries.json').content),
    ) as Map<String, Object?>;

    expect(manifest['count'], 0);
    expect(manifest['entries'], isEmpty);
  });
}
