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
  /// [getFix] exists as a seam: production wiring keeps the default (the real
  /// location stack), tests inject a fake to drive the sort state machine
  /// deterministically. It is the only injection point this class needs.
  ArchiveView({Future<PlaceFix?> Function({bool prompt}) getFix = LocationService.current})
      : _getFix = getFix;

  final Future<PlaceFix?> Function({bool prompt}) _getFix;

  final Set<String> _selected = <String>{};
  String _query = '';
  ArchiveSort _sort = ArchiveSort.newest;

  PlaceFix? _origin;
  bool _locating = false;
  bool _originUnavailable = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// notifyListeners() throws once disposed, and [_resolveOrigin] notifies
  /// across a gap that can run for ten seconds plus a network geocode.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Clears everything view-related. Called on sign-out so the next user does
  /// not inherit the previous one's filter, sort, or last known coordinates.
  void reset() {
    _selected.clear();
    _query = '';
    _sort = ArchiveSort.newest;
    _origin = null;
    _locating = false;
    _originUnavailable = false;
    _notify();
  }

  // --- tags -------------------------------------------------------------

  Set<String> get selected => Set.unmodifiable(_selected);

  bool get isEmpty => _selected.isEmpty;

  bool isSelected(String tag) => _selected.contains(tag);

  void toggle(String tag) {
    if (!_selected.remove(tag)) _selected.add(tag);
    _notify();
  }

  void clear() {
    if (_selected.isEmpty) return;
    _selected.clear();
    _notify();
  }

  /// Forgets selections whose tag no longer exists anywhere.
  ///
  /// [effective] hides such a selection from the current build, but it stays in
  /// `_selected` — so deleting your last "wine" entry and later recording a new
  /// one would make the archive collapse back onto a filter you cleared days
  /// ago and never re-applied. Must be called outside build (it notifies);
  /// main.dart drives it from the store's own change notification.
  void prune(Iterable<String> available) {
    if (_selected.isEmpty) return;
    final keep = available.toSet();
    final before = _selected.length;
    _selected.removeWhere((t) => !keep.contains(t));
    if (_selected.length != before) _notify();
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

  // --- search -----------------------------------------------------------

  /// What the archive is being searched for. Empty means no search.
  ///
  /// Lives here rather than in the timeline so it narrows the map too: having
  /// typed "flat white", switching tabs should answer "where do I drink flat
  /// whites?" — the same reasoning that made tags shared state.
  String get query => _query;

  /// True once a search is narrowing things — i.e. after non-blank input.
  ///
  /// Distinct from "the search field is open": an open, empty field filters
  /// nothing, so the archive must not claim to be showing search results.
  bool get isSearching => _query.trim().isNotEmpty;

  void setQuery(String query) {
    if (_query == query) return;
    _query = query;
    _notify();
  }

  void clearQuery() => setQuery('');

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
    _notify();
    if (sort == ArchiveSort.nearest) await _resolveOrigin();
  }

  /// Re-reads the current position. Exposed so the "try again" affordance can
  /// retry after the user grants permission in system settings.
  Future<void> refreshOrigin() => _resolveOrigin();

  Future<void> _resolveOrigin() async {
    if (_locating) return;
    _locating = true;
    _originUnavailable = false;
    _notify();

    // prompt: true is right here and nowhere else on this screen — the user
    // just asked to sort by distance, so the permission dialog has an obvious
    // reason attached.
    final fix = await _getFix(prompt: true);

    _origin = fix ?? _origin;
    _originUnavailable = fix == null && _origin == null;
    _locating = false;
    _notify();
  }

  /// Applies [sort] to an already-filtered list.
  ///
  /// Falls back to the incoming order (newest first, as the store returns it)
  /// when distance sorting was asked for but no fix is available — a missing
  /// location degrades the ordering, it never empties the archive.
  List<Entry> order(List<Entry> entries) {
    final from = _origin;
    if (_sort != ArchiveSort.nearest || from == null) return entries;

    return sortedByDistanceFrom(entries, from.latitude, from.longitude);
  }

  /// [entries] narrowed by the current search.
  List<Entry> matching(List<Entry> entries) =>
      _query.trim().isEmpty ? entries : entriesMatching(entries, _query);

  /// Everything this view does to an already tag-filtered list: search, then
  /// sort. One call so the timeline and the map cannot apply one and forget
  /// the other.
  List<Entry> arrange(List<Entry> entries) => order(matching(entries));
}
