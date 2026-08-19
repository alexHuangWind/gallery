import 'package:flutter/foundation.dart';

/// Which tags the archive is currently narrowed to.
///
/// Shared by the timeline and the map on purpose: picking "wine" and switching
/// to the map should answer "where do I like wine?" rather than silently
/// resetting. One filter, two views of the same narrowed set.
class TagFilter extends ChangeNotifier {
  final Set<String> _selected = <String>{};

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
  /// the last "wine" entry would strand the archive on a filter matching
  /// nothing, with the chip that set it no longer on screen to unset it.
  Set<String> effective(Iterable<String> available) {
    if (_selected.isEmpty) return const {};
    final keep = available.toSet();
    return _selected.where(keep.contains).toSet();
  }
}
