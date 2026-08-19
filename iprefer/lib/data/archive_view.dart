import 'package:flutter/foundation.dart';

import '../models/entry.dart';
import 'location_service.dart';

/// How the archive is ordered.
enum ArchiveSort {
  /// Most recent first — the default reading of a timeline.
  newest,

  /// Closest to where you are standing first.
  nearest,
}

/// How the archive is currently being looked at: which tags it is narrowed to,
/// and in what order.
///
/// Shared by the timeline and the map on purpose: picking "wine" and switching
/// to the map should answer "where do I like wine?" rather than silently
/// resetting. One view state, two presentations of the same set.
class ArchiveView extends ChangeNotifier {
  final Set<String> _selected = <String>{};
  ArchiveSort _sort = ArchiveSort.newest;

  PlaceFix? _origin;
  bool _locating = false;
  bool _originUnavailable = false;

  // --- tags -------------------------------------------------------------

  Set<String> get selected => Set.unmodifiable(_selected);

  bool get isEmpty => _selected.isEmpty;

  bool isSelected(String tag) => _selected.contains(tag);

  void toggle(String tag) {
    if (!_selected.remove(tag)) _selected.add(tag);
    notifyListeners();
  }

  void clear() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  /// The selection restricted to tags that still exist.
  ///
  /// Deliberately pure rather than self-pruning: this is read during build, and
  /// mutating a [ChangeNotifier] mid-build would throw. Without it, deleting
  /// the last "wine" entry would strand the archive on a filter referring to a
  /// tag whose chip is no longer on screen to unset.
  Set<String> effective(Iterable<String> available) {
    if (_selected.isEmpty) return const {};
    final keep = available.toSet();
    return _selected.where(keep.contains).toSet();
  }

  // --- sort -------------------------------------------------------------

  ArchiveSort get sort => _sort;

  /// Where "nearest" is measured from. Null until we have a fix.
  PlaceFix? get origin => _origin;

  bool get locating => _locating;

  /// True when sorting by distance was asked for but we could not get a fix.
  bool get originUnavailable => _originUnavailable;

  Future<void> setSort(ArchiveSort sort) async {
    if (_sort == sort && !(sort == ArchiveSort.nearest && _origin == null)) {
      return;
    }
    _sort = sort;
    notifyListeners();
    if (sort == ArchiveSort.nearest) await _resolveOrigin();
  }

  /// Re-reads the current position. Exposed so the "try again" affordance can
  /// retry after the user grants permission in system settings.
  Future<void> refreshOrigin() => _resolveOrigin();

  Future<void> _resolveOrigin() async {
    if (_locating) return;
    _locating = true;
    _originUnavailable = false;
    notifyListeners();

    // prompt: true is right here and nowhere else on this screen — the user
    // just asked to sort by distance, so the permission dialog has an obvious
    // reason attached.
    final fix = await LocationService.current(prompt: true);

    _origin = fix ?? _origin;
    _originUnavailable = fix == null && _origin == null;
    _locating = false;
    notifyListeners();
  }

  /// Applies [sort] to an already-filtered list.
  ///
  /// Falls back to the incoming order (newest first, as the store returns it)
  /// when distance sorting was asked for but no fix is available — a missing
  /// location degrades the ordering, it never empties the archive.
  List<Entry> order(List<Entry> entries) {
    final from = _origin;
    if (_sort != ArchiveSort.nearest || from == null) return entries;

    return [...entries]..sort((a, b) {
        final byDistance = a
            .metresTo(from.latitude, from.longitude)
            .compareTo(b.metresTo(from.latitude, from.longitude));
        if (byDistance != 0) return byDistance;
        // Dart's sort is not stable, so ties need an explicit rule or entries
        // without a fix (all tied at infinity) would shuffle on every rebuild.
        return b.createdAt.compareTo(a.createdAt);
      });
  }
}
