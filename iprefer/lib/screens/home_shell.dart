import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/archive_export_runner.dart';
import '../data/archive_view.dart';
import '../data/entry_store.dart';
import '../data/session.dart';
import '../theme.dart';
import 'archive_screen.dart';
import 'compose_screen.dart';
import 'map_screen.dart';

/// Two ways into the same record: the timeline (when) and the map (where).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  /// Whether the search field has replaced the title.
  ///
  /// Deliberately not in [ArchiveView]: the *query* is shared state (it
  /// narrows both tabs), but whether a text field is on screen is this
  /// widget's own business.
  bool _searching = false;

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  /// The shared view, held so [_syncField] can be attached to and detached
  /// from it.
  ///
  /// Read with `context.read`, i.e. without subscribing: the app builds exactly
  /// one [ArchiveView] as a field of its root state and hands the same instance
  /// out for the process's lifetime (see `main.dart`), so there is no swap to
  /// miss. A listening read would subscribe this whole shell to the view and
  /// rebuild the bar, both tabs and the FAB on every keystroke of a search —
  /// paying for a rebuild path that cannot happen. The identity check below is
  /// what would catch it if that construction ever changed.
  ArchiveView? _view;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final view = context.read<ArchiveView>();
    if (identical(view, _view)) return;
    _view?.removeListener(_syncField);
    _view = view..addListener(_syncField);
  }

  /// Keeps the field showing whatever is actually filtering.
  ///
  /// The query is shared state and the empty states clear it — from deep
  /// inside the body, where this controller is unreachable. Without this the
  /// field would still read "kangaroo" over an unfiltered archive, and the
  /// next backspace would silently re-narrow it to "kangaro".
  ///
  /// Runs off the notification rather than in build, so mutating the
  /// controller never lands mid-frame. Self-inflicted changes (the user
  /// typing) arrive here with the text already equal, and stop.
  void _syncField() {
    final query = _view?.query ?? '';
    if (_searchController.text == query) return;
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  @override
  void dispose() {
    _view?.removeListener(_syncField);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// True while the zip is being written. Held in state, not a bare field:
  /// the menu item has to *look* unavailable, or a second tap is a control
  /// that silently does nothing.
  bool _exporting = false;

  final ArchiveExportRunner _exportRunner = ArchiveExportRunner();

  Future<void> _export() async {
    if (_exporting) return;

    final store = context.read<EntryStore>();
    final messenger = ScaffoldMessenger.of(context);
    // Resolved here, before the first await, and passed down. iPad anchors the
    // share sheet to this rect, and a RenderBox read after an await can be
    // detached — signing out mid-pack swaps this whole screen out, and asking
    // a detached box for its position throws, turning a successful export into
    // "couldn't pack your archive" on the login screen.
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;

    setState(() => _exporting = true);
    try {
      await _exportRunner.run(
        store: store,
        now: DateTime.now(),
        origin: origin,
        // Said as it happens rather than from the return value: the missing-
        // photo warning has to be on screen before the sheet opens.
        onOutcome: (outcome) {
          final line = _exportMessage(outcome);
          if (line != null) {
            messenger.showSnackBar(SnackBar(content: Text(line)));
          }
        },
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// What an export is worth saying out loud. Null for the ordinary success:
  /// the share sheet appearing is its own confirmation, and a snackbar under
  /// it would only be read after the moment it belonged to.
  String? _exportMessage(ExportOutcome outcome) {
    switch (outcome.status) {
      case ExportStatus.nothingToSave:
        return 'nothing to save yet';
      case ExportStatus.failed:
        return "couldn't pack your archive — try again";
      case ExportStatus.packed:
        final n = outcome.missingPhotos;
        if (n == 0) return null;
        return "$n photo${n == 1 ? '' : 's'} "
            "${n == 1 ? "wasn't" : "weren't"} on this phone — "
            'the words are still in the copy';
    }
  }

  void _compose() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ComposeScreen()),
    );
  }

  void _openSearch() {
    // Seeded from the view, not blanked: a query survives a tab switch and a
    // closed field, so re-opening must show what is actually being filtered.
    _syncField();
    setState(() => _searching = true);
    _searchFocus.requestFocus();
  }

  /// Closes the field *and* drops the query — closing search that kept
  /// filtering would leave the archive narrowed with nothing on screen saying
  /// why. The controller follows via [_syncField].
  void _closeSearch() {
    _view?.clearQuery();
    _searchFocus.unfocus();
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The shell is the root route, so with the field open an Android back
      // gesture had nothing above it to pop and left the app instead — losing
      // the timeline to close a search box. Back now means "out of search"
      // exactly as the arrow does, and only then means "out of the app".
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _closeSearch();
      },
      child: Scaffold(
        appBar: AppBar(
          // "I prefer" keeps its capital everywhere it appears as the phrase —
          // it is the app's name and the card's signature line, not body copy.
          // The lowercase voice applies to what the app *says*, not to what it
          // is called. ("places" is body copy, so it stays lowercase.)
          title: _searching
              ? _SearchField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: (q) => context.read<ArchiveView>().setQuery(q),
                )
              : Text(_tab == 0 ? 'I prefer' : 'places'),
          leading: _searching
              ? IconButton(
                  tooltip: 'close search',
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: _closeSearch,
                )
              : null,
          actions: [
            if (_searching)
              // A real app-bar action rather than the field's suffixIcon: as a
              // suffix it either shrinks below a comfortable hit target or its
              // 48 pt height sets the row and pushes the text up off the back
              // arrow's line.
              //
              // The slot keeps its width when empty. The title is sized from
              // whatever `actions` leaves, so appearing and disappearing would
              // jog the field 40 px sideways on the first and last character.
              SizedBox(
                width: 48,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: 'clear',
                          icon: const Icon(Icons.close, size: 20),
                          // Empties the query but keeps the field open and
                          // focused — "search for something else", not "stop
                          // searching". The controller follows via _syncField.
                          onPressed: () {
                            _view?.clearQuery();
                            _searchFocus.requestFocus();
                          },
                        ),
                ),
              ),
            if (!_searching)
              IconButton(
                tooltip: 'search',
                icon: const Icon(Icons.search, size: 22),
                onPressed: _openSearch,
              ),
            // Load-bearing, not cosmetic: ArchiveView.reset() cannot reach
            // _searching or the controller, so signing out from an open search
            // would leave a stale field over a cleared query. Hiding the whole
            // menu means the only way out of search is _closeSearch.
            //
            // A menu rather than a third icon: the bar has to hold the title as
            // well, and two of these are things you do once in a while, not
            // controls you want under your thumb.
            if (!_searching)
              PopupMenuButton<_Overflow>(
                tooltip: 'more',
                icon: const Icon(Icons.more_vert, size: 20),
                position: PopupMenuPosition.under,
                onSelected: (item) {
                  switch (item) {
                    case _Overflow.export:
                      _export();
                    case _Overflow.signOut:
                      // Just the sign-out. Clearing what the last account left
                      // behind — the filter, the sort, the outbox — belongs to
                      // main.dart, which watches the session and does it on the
                      // signed-in→out edge however sign-out was reached. Doing
                      // it here as well only meant it happened twice on the one
                      // path a button can reach.
                      context.read<Session>().signOut();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _Overflow.export,
                    enabled: !_exporting,
                    child: Text(
                      _exporting
                          ? 'packing your archive…'
                          : 'save a copy of everything',
                    ),
                  ),
                  const PopupMenuItem(
                    value: _Overflow.signOut,
                    child: Text('sign out'),
                  ),
                ],
              ),
          ],
        ),
        body: IndexedStack(
          index: _tab,
          children: const [ArchiveScreen(), MapScreen()],
        ),
        // Kept while searching. "I looked for it, it isn't there, so let me
        // record it" is exactly the moment compose is wanted, and hiding the
        // button made reaching it cost the query.
        //
        // Bare of colours on purpose: fill and corner come from
        // floatingActionButtonTheme, because this is the same gesture as a
        // filled button and should not be able to drift from one.
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _compose,
          icon: const Icon(Icons.add),
          label: const Text('record'),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.schedule_outlined),
              selectedIcon: Icon(Icons.schedule),
              label: 'timeline',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'map',
            ),
          ],
        ),
      ),
    );
  }
}

/// The app bar's search input.
///
/// Deliberately unadorned — no fill, no box. It is standing in for the title,
/// so it should read as the title having become editable rather than as a
/// control dropped on top of the page.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      // Results are live, so the search key has nothing left to submit — but
      // it must still put the keyboard away. On iOS there is no system gesture
      // that does, and the only other exit is the back arrow, which also drops
      // the query: "let me see the results" would have cost the search.
      onSubmitted: (_) => focusNode.unfocus(),
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      style: TextStyle(fontSize: 18, color: context.colors.ink),
      decoration: InputDecoration(
        // Every border, or the app bar grows an outline mid-height.
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        hintText: 'search what you liked',
        hintStyle: TextStyle(fontSize: 18, color: context.colors.muted),
      ),
    );
  }
}

/// The app bar's overflow items.
enum _Overflow { export, signOut }
