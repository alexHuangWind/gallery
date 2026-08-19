import 'package:flutter_test/flutter_test.dart';
import 'package:iprefer/models/entry.dart';

Entry _tagged(String id, List<String> tags) => Entry(
      id: id,
      localPath: '/photos/$id.jpg',
      text: id,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      tags: tags,
    );

void main() {
  group('normalizeTags', () {
    test('lowercases and trims', () {
      expect(normalizeTags(['  Wine ', 'DISH']), ['wine', 'dish']);
    });

    test('dedupes case- and space-variants into one tag', () {
      // The whole point: "Wine" and " wine " must not become two shelves.
      expect(normalizeTags(['Wine', 'wine', ' WINE ']), ['wine']);
    });

    test('drops a leading hash', () {
      expect(normalizeTags(['#grocery', '##wine']), ['grocery', 'wine']);
    });

    test('collapses internal whitespace', () {
      expect(normalizeTags(['red   wine']), ['red wine']);
    });

    test('discards empties', () {
      expect(normalizeTags(['', '   ', '#', 'wine']), ['wine']);
    });

    test('caps runaway length', () {
      final long = 'a' * 100;
      final result = normalizeTags([long]);
      expect(result.single.length, 24);
    });

    test('preserves the order tags were added in', () {
      expect(normalizeTags(['dish', 'wine', 'grocery']),
          ['dish', 'wine', 'grocery']);
    });
  });

  group('Entry.hasTag', () {
    test('matches regardless of the caller casing', () {
      final e = _tagged('a', const ['wine']);
      expect(e.hasTag('wine'), isTrue);
      expect(e.hasTag('WINE'), isTrue);
      expect(e.hasTag(' wine '), isTrue);
      expect(e.hasTag('dish'), isFalse);
    });

    test('an untagged entry matches nothing', () {
      expect(_tagged('a', const []).hasTag('wine'), isFalse);
    });
  });

  group('tag filtering semantics', () {
    // Mirrors EntryStore.withTags: every selected tag must be present (AND).
    List<Entry> withTags(List<Entry> all, Set<String> tags) =>
        tags.isEmpty ? all : all.where((e) => tags.every(e.hasTag)).toList();

    final entries = [
      _tagged('a', const ['wine', 'dish']),
      _tagged('b', const ['wine']),
      _tagged('c', const ['grocery']),
      _tagged('d', const []),
    ];

    test('an empty filter keeps everything', () {
      expect(withTags(entries, {}).length, 4);
    });

    test('one tag keeps every entry carrying it', () {
      expect(withTags(entries, {'wine'}).map((e) => e.id), ['a', 'b']);
    });

    test('two tags narrow rather than widen', () {
      expect(withTags(entries, {'wine', 'dish'}).map((e) => e.id), ['a']);
    });

    test('an unmatched combination yields nothing', () {
      expect(withTags(entries, {'wine', 'grocery'}), isEmpty);
    });
  });
}
