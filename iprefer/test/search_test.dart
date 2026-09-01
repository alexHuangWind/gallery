import 'package:flutter_test/flutter_test.dart';
import 'package:iprefer/data/archive_view.dart';
import 'package:iprefer/models/entry.dart';

/// Search is the first filter in the app that can legitimately match nothing,
/// so these pin both halves: what it finds, and what the archive does when it
/// finds nothing.
void main() {
  final when = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  Entry make(
    String id, {
    String text = '',
    String? place,
    List<String> tags = const [],
  }) =>
      Entry(
        id: id,
        localPath: '$id.jpg',
        text: text,
        createdAt: when,
        placeLabel: place,
        tags: tags,
      );

  final flatWhite = make('a',
      text: 'a flat white before the world wakes up',
      place: 'Cuba Street',
      tags: const ['coffee']);
  final ferns = make('b',
      text: 'ferns that uncurl like a slow question',
      place: 'Zealandia',
      tags: const ['plants']);
  final untagged = make('c', text: 'the smell of rain on hot concrete');

  final all = [flatWhite, ferns, untagged];

  List<String> ids(List<Entry> entries) => entries.map((e) => e.id).toList();

  group('entriesMatching', () {
    test('matches the line', () {
      expect(ids(entriesMatching(all, 'uncurl')), ['b']);
    });

    test('matches a tag', () {
      expect(ids(entriesMatching(all, 'coffee')), ['a']);
    });

    test('matches the place', () {
      expect(ids(entriesMatching(all, 'zealandia')), ['b']);
    });

    test('is case-insensitive and matches inside words', () {
      // "fern" must find "ferns" — someone recalling an entry types the word
      // they remember, not the exact inflection they wrote.
      expect(ids(entriesMatching(all, 'FERN')), ['b']);
    });

    test('several words mean all of them, across fields', () {
      // "flat" from the line, "cuba" from the place — one entry satisfies both.
      expect(ids(entriesMatching(all, 'flat cuba')), ['a']);
      expect(entriesMatching(all, 'flat zealandia'), isEmpty);
    });

    test('extra whitespace between terms is ignored', () {
      expect(ids(entriesMatching(all, '  flat   white  ')), ['a']);
    });

    test('a term cannot span two tags', () {
      final e = make('d', tags: const ['red', 'wine']);
      expect(entriesMatching([e], 'redwine'), isEmpty);
      expect(ids(entriesMatching([e], 'red wine')), ['d']);
    });

    test('an entry with no place or tags is still searchable', () {
      expect(ids(entriesMatching(all, 'concrete')), ['c']);
    });

    test('no match comes back empty rather than unfiltered', () {
      expect(entriesMatching(all, 'kangaroo'), isEmpty);
    });

    test('every kind of blank query filters nothing', () {
      // trim() and \s+ disagree on a few separators — U+0085 (NEL) among them
      // — so a "blank" query could survive the split as one literal term and
      // match nothing, which is the opposite of what the contract promises.
      for (final blank in ['', '   ', '\t', '\n', '\u0085', ' \u0085 ']) {
        expect(ids(entriesMatching(all, blank)), ['a', 'b', 'c'],
            reason: 'blank query ${blank.codeUnits}');
      }
    });

    test('a stray separator around a real term does not break it', () {
      // Pasted queries pick these up.
      expect(ids(entriesMatching(all, 'ferns\u0085')), ['b']);
      expect(ids(entriesMatching(all, '\nferns\t')), ['b']);
    });

    test('preserves the incoming order', () {
      expect(ids(entriesMatching(all, 'the')), ['a', 'c']);
    });
  });

  group('ArchiveView', () {
    test('setQuery notifies, and only when the value changes', () {
      final view = ArchiveView();
      var notified = 0;
      view.addListener(() => notified++);

      view.setQuery('fern');
      view.setQuery('fern');
      expect(notified, 1);

      view.setQuery('ferns');
      expect(notified, 2);
    });

    test('isSearching ignores whitespace', () {
      // An open, empty field filters nothing, so the archive must not claim to
      // be showing search results.
      final view = ArchiveView();
      expect(view.isSearching, isFalse);
      view.setQuery('   ');
      expect(view.isSearching, isFalse);
      view.setQuery(' fern ');
      expect(view.isSearching, isTrue);
    });

    test('clearQuery empties it', () {
      final view = ArchiveView()..setQuery('fern');
      view.clearQuery();
      expect(view.query, '');
      expect(view.isSearching, isFalse);
    });

    test('reset drops the query with everything else', () {
      // Sign-out. The next person on this phone must not inherit a search.
      final view = ArchiveView()
        ..setQuery('fern')
        ..toggle('plants');
      view.reset();
      expect(view.query, '');
      expect(view.isEmpty, isTrue);
    });

    test('matching applies the query, arrange also sorts', () {
      final view = ArchiveView()..setQuery('fern');
      expect(ids(view.matching(all)), ['b']);
      // No origin, so the sort is a no-op — but arrange must still search.
      expect(ids(view.arrange(all)), ['b']);
    });

    test('an unset query leaves the list alone', () {
      final view = ArchiveView();
      expect(ids(view.arrange(all)), ['a', 'b', 'c']);
    });
  });
}
