import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/archive_view.dart';
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
    return Scaffold(
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
          // Load-bearing, not cosmetic: ArchiveView.reset() below cannot
          // reach _searching or the controller, so signing out from an open
          // search would leave a stale field over a cleared query. Hiding the
          // control means the only way out of search is _closeSearch.
          if (!_searching)
            IconButton(
              tooltip: 'sign out',
              icon: const Icon(Icons.logout, size: 20),
              onPressed: () {
                // Reset BEFORE signOut: the next user must not inherit this
                // one's filter, sort, or last known coordinates. This is the
                // only sign-out path today; if Firebase ever adds another
                // (expiry, revocation), move this pairing into main.dart's
                // composition root next to the store→prune listener.
                context.read<ArchiveView>().reset();
                context.read<Session>().signOut();
              },
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        backgroundColor: context.colors.ink,
        foregroundColor: context.colors.paper,
        // 8dp like every real button; the default stadium pill reads as a
        // chip, and pills mean "selectable filter" everywhere else here.
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
