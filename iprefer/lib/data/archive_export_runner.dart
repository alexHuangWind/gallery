import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'archive_export.dart';
import 'entry_store.dart';

/// How an export attempt ended.
enum ExportStatus {
  /// There was nothing to pack, so no file was written and no sheet opened.
  nothingToSave,

  /// A zip was written and handed to the share sheet.
  packed,

  /// Something went wrong; the cause was logged, not shown.
  failed,
}

/// The result of an export attempt, in terms the UI can act on.
///
/// Deliberately free of copy: the sentences belong to whatever is on screen,
/// this only says what happened.
class ExportOutcome {
  const ExportOutcome._(this.status, this.missingPhotos);

  const ExportOutcome.nothingToSave() : this._(ExportStatus.nothingToSave, 0);

  const ExportOutcome.packed({int missingPhotos = 0})
      : this._(ExportStatus.packed, missingPhotos);

  const ExportOutcome.failed() : this._(ExportStatus.failed, 0);

  final ExportStatus status;

  /// Entries whose photo could not go in the file. Non-zero is normal on a
  /// phone that has synced an account but not yet downloaded every photo — it
  /// is worth saying out loud, but it is not a failure.
  final int missingPhotos;
}

/// Runs "save a copy of everything" end to end: build the zip, hand it to the
/// share sheet, throw the work directory away again.
///
/// Split out of the shell because all of that is file work, and a widget that
/// owns a temp directory is a widget that cannot be tested without a platform.
/// Its two platform touch points — the temp directory and the share sheet —
/// are injectable, which is what lets the cleanup guarantee be tested.
///
/// It never looks a widget up. In particular the iPad share anchor arrives as
/// [Rect] from the caller: it has to be read from the render tree *before* the
/// first await, and only the caller knows where that is.
class ArchiveExportRunner {
  ArchiveExportRunner({
    Future<Directory> Function()? temporaryDirectory,
    Future<void> Function(XFile file, Rect? origin)? share,
  })  : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _share = share ?? _shareSheet;

  final Future<Directory> Function() _temporaryDirectory;
  final Future<void> Function(XFile file, Rect? origin) _share;

  static Future<void> _shareSheet(XFile file, Rect? origin) =>
      Share.shareXFiles([file], sharePositionOrigin: origin);

  /// Packs [store] and offers the file to the system share sheet.
  ///
  /// [origin] anchors the sheet on iPad and must already have been resolved by
  /// the caller — see the class comment. [now] stamps the manifest and names
  /// the file.
  ///
  /// [onOutcome] is called exactly once, as early as the outcome can honestly
  /// be reported: for a packed archive that is *before* the share sheet opens,
  /// which is the point of it existing. On iOS the share future does not
  /// complete until the sheet is dismissed, so a caller that waited for the
  /// return value would tell someone who just cancelled about gaps in a copy
  /// they decided not to make. The same outcome is returned when everything,
  /// including cleanup, is done.
  Future<ExportOutcome> run({
    required EntryStore store,
    required DateTime now,
    Rect? origin,
    void Function(ExportOutcome outcome)? onOutcome,
  }) async {
    if (store.isEmpty) {
      const outcome = ExportOutcome.nothingToSave();
      onOutcome?.call(outcome);
      return outcome;
    }

    Directory? workDir;
    try {
      final temp = await _temporaryDirectory();
      workDir = Directory(p.join(temp.path, workDirName));
      final result = await ArchiveExport.pack(
        entries: store.entries,
        photosRoot: store.photosRoot,
        workDir: workDir,
        now: now,
      );

      final outcome = ExportOutcome.packed(
        missingPhotos: result.missingPhotos,
      );
      onOutcome?.call(outcome);

      await _share(XFile(result.file.path), origin);
      return outcome;
    } catch (e) {
      // Recorded, because disk-full, an unreadable photo and a share sheet
      // that refused to open all reach the user as one sentence.
      debugPrint('export failed: $e');
      const outcome = ExportOutcome.failed();
      onOutcome?.call(outcome);
      return outcome;
    } finally {
      // A whole second copy of the archive, otherwise: this lives in
      // Library/Caches, which iOS does not reliably reclaim, and share_plus on
      // Android has already copied what it needs into its own cache. Both
      // platforms are done with our file by the time this future completes.
      try {
        if (workDir != null && workDir.existsSync()) {
          workDir.deleteSync(recursive: true);
        }
      } catch (_) {
        // Cleanup is best-effort; the next export clears the directory anyway.
      }
    }
  }

  /// Where the zip is built, inside the temp directory. Named so a test can
  /// assert it is gone afterwards without knowing how the path is assembled.
  @visibleForTesting
  static const String workDirName = 'export';
}
