import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../models/entry.dart';

/// Packs the whole archive into one file the user can keep.
///
/// The account backs the archive up to our server; this is the other half of
/// the same promise — a copy that does not depend on us existing. It is also
/// the answer to "what happens to my entries if I stop using this", which is a
/// question worth being able to answer plainly.
///
/// The zip holds `entries.json`, a `photos/` directory, and a short
/// `README.txt`. The JSON is deliberately the *same shape* as the sync wire
/// format ([Entry.toSyncJson]), so there is one description of an entry rather
/// than two that can drift.
class ArchiveExport {
  ArchiveExport._();

  /// Bumped only when the shape changes in a way a reader would have to know
  /// about. Present so a future importer can refuse a file it doesn't
  /// understand instead of guessing.
  static const int formatVersion = 1;

  static const String manifestName = 'entries.json';
  static const String readmeName = 'README.txt';
  static const String photosDir = 'photos';

  /// What an id may contain before it is allowed to become a path inside the
  /// zip. Ids are uuids, so this rejects nothing real — it exists because ids
  /// arrive from the server, and `../../x` would otherwise become a zip entry
  /// that escapes its directory on whoever extracts the file.
  static final RegExp _safeName = RegExp(r'^[A-Za-z0-9._-]+$');

  /// Writes the zip and returns it.
  ///
  /// [photosRoot] and [entries] come from the store; [workDir] is where the
  /// file is built. Anything already in [workDir] is deleted first.
  ///
  /// Entries whose photo cannot be read are still listed in the manifest: the
  /// words and the place are the part that can't be re-photographed, and
  /// silently dropping the record would lose them too. The manifest names
  /// them, and [ExportResult.missingPhotos] counts them, so neither the UI nor
  /// a future reader has to guess whether the file is damaged.
  static Future<ExportResult> pack({
    required List<Entry> entries,
    required String photosRoot,
    required Directory workDir,
    required DateTime now,
  }) async {
    if (workDir.existsSync()) workDir.deleteSync(recursive: true);
    workDir.createSync(recursive: true);

    final root = p.normalize(photosRoot);
    final photos = <_PhotoEntry>[];
    final skipped = <String>[];
    final claimed = <String>{};

    for (final entry in entries) {
      final name = entry.syncPhotoName;
      // Two entries can only collide here through a torn record read back with
      // an empty id (see EntryAdapter.read). Archive.add replaces on a
      // duplicate name, so without this the second photo would be in the file
      // but invisible to every reader, and photoCount would lie.
      if (!_safeName.hasMatch(name) || !claimed.add(name)) {
        skipped.add(entry.id);
        continue;
      }

      final stored = entry.localPath;
      final path = p.normalize(
        p.isAbsolute(stored) ? stored : p.join(root, stored),
      );
      // Only files from the photos directory. Legacy records hold an absolute
      // path, and nothing validates where it points — this is what stops an
      // entry from copying an arbitrary readable file into something the user
      // then hands to someone else.
      if (!p.isWithin(root, path) || !File(path).existsSync()) {
        skipped.add(entry.id);
        continue;
      }

      photos.add((source: path, name: '$photosDir/$name'));
    }

    final outPath = p.join(workDir.path, fileNameFor(now));

    // Off the UI isolate: this reads every photo in the archive. Only Strings
    // and records cross the boundary, so nothing here depends on Entry being
    // sendable.
    //
    // Returns the ids it could not read: a photo can be deleted between the
    // check above and the read here — a sync pull landing on resume does
    // exactly that — and one unreadable file must not cost the whole export.
    final manifest = _manifest(entries, skipped, now);
    final readme = readmeFor(entries.length, now);
    final unreadable = await Isolate.run(
      () => _write(outPath, manifest, readme, photos),
    );

    return ExportResult(
      file: File(outPath),
      entryCount: entries.length,
      photoCount: photos.length - unreadable.length,
      missingPhotos: skipped.length + unreadable.length,
    );
  }

  static String _manifest(
    List<Entry> entries,
    List<String> withoutPhotos,
    DateTime now,
  ) {
    return const JsonEncoder.withIndent('  ').convert({
      'format': formatVersion,
      // UTC, so the stamp is unambiguous to whoever opens this. A local ISO
      // string carries no offset and means nothing a year later.
      'exportedAt': now.toUtc().toIso8601String(),
      'count': entries.length,
      // Named, not merely counted: a reader who finds a photoName with no file
      // behind it can otherwise not tell "was never on that phone" from "this
      // zip is damaged" — which is exactly the difference that decides whether
      // to go looking for the photo somewhere else.
      'entriesWithoutPhotos': withoutPhotos,
      'entries': [for (final e in entries) e.toSyncJson()],
    });
  }

  /// A plain-language note, because the promise is that this outlives us.
  static String readmeFor(int entryCount, DateTime now) => '''
I prefer — an export of your archive
made ${now.toUtc().toIso8601String()}

$entryCount ${entryCount == 1 ? 'entry' : 'entries'}.

$manifestName   every entry: the line you wrote, when, where (when known),
                and its tags. One JSON object per entry, in "entries".
$photosDir/     one photo per entry, named by the entry's "photoName".

Dates are milliseconds since 1970-01-01 UTC.
Entries listed under "entriesWithoutPhotos" had no photo on the phone that
made this file — their words are still here.

Nothing in this file needs the app to read it.
''';

  /// `i-prefer-2026-09-02.zip` — sorts chronologically in a file list, and
  /// says what it is without being opened.
  static String fileNameFor(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'i-prefer-${now.year}-${two(now.month)}-${two(now.day)}.zip';
  }

  /// Writes the archive. Returns the zip names it could not read.
  static List<String> _write(
    String outPath,
    String manifest,
    String readme,
    List<_PhotoEntry> photos,
  ) {
    final unreadable = <String>[];
    final zip = ZipFileEncoder();
    zip.create(outPath);
    try {
      zip.addArchiveFile(
        ArchiveFile.bytes(manifestName, utf8.encode(manifest)),
      );
      zip.addArchiveFile(
        ArchiveFile.bytes(readmeName, utf8.encode(readme)),
      );
      for (final photo in photos) {
        try {
          final file = File(photo.source);
          final stream = InputFileStream(photo.source);
          // Genuinely stored, not deflated at level 0: ZipFileEncoder.store is
          // a *level*, and a null compression still takes the deflate path —
          // which buffers each photo in memory and, on already-compressed
          // JPEG, produces a file slightly larger than its inputs.
          final archived = ArchiveFile.stream(photo.name, stream)
            ..compression = CompressionType.none
            ..lastModTime =
                file.lastModifiedSync().millisecondsSinceEpoch ~/ 1000;
          zip.addArchiveFile(archived);
        } catch (_) {
          // Deleted or unreadable since we looked. One photo must not cost the
          // export — the caller folds this into missingPhotos.
          unreadable.add(photo.name);
        }
      }
    } finally {
      zip.closeSync();
    }
    return unreadable;
  }
}

/// What a photo is called on disk, and what it is called in the zip.
typedef _PhotoEntry = ({String source, String name});

class ExportResult {
  const ExportResult({
    required this.file,
    required this.entryCount,
    required this.photoCount,
    required this.missingPhotos,
  });

  final File file;
  final int entryCount;
  final int photoCount;

  /// Entries whose photo could not be put in the file. Non-zero is normal on a
  /// phone that has synced an account but not yet downloaded every photo.
  final int missingPhotos;
}
