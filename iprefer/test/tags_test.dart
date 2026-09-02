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

  group('Entry normalizes its own tags', () {
    test('the constructor normalizes, so no caller can store a raw tag', () {
      final e = _tagged('a', const ['  Wine ', '#DISH', 'wine']);
      expect(e.tags, ['wine', 'dish']);
    });

    test('emoji tags are not truncated into the same lone surrogate', () {
      // Both are 25 UTF-16 code units; a naive cut at 24 leaves the identical
      // high surrogate and silently merges two different shelves into one.
      final wine = normalizeTags(['${'a' * 23}🍷']).single;
      final beer = normalizeTags(['${'a' * 23}🍺']).single;
      expect(wine, isNot(equals(beer)));
    });
  });

  group('Entry.hasTag', () {
    test('matches regardless of how the caller wrote the query', () {
      final e = _tagged('a', const ['wine']);
      expect(e.hasTag('wine'), isTrue);
      expect(e.hasTag('WINE'), isTrue);
      expect(e.hasTag(' wine '), isTrue);
      // hasTag must apply every rule normalizeTags does, not just some.
      expect(e.hasTag('#Wine'), isTrue);
      expect(e.hasTag('dish'), isFalse);
    });

    test('matches a stored tag whose internal spacing was collapsed', () {
      final e = _tagged('a', const ['red wine']);
      expect(e.hasTag('red   wine'), isTrue);
    });

    test('an untagged entry matches nothing', () {
      expect(_tagged('a', const []).hasTag('wine'), isFalse);
    });
  });

  group('entriesWithAnyTag', () {
    final entries = [
      _tagged('a', const ['wine', 'dish']),
      _tagged('b', const ['wine']),
      _tagged('c', const ['grocery']),
      _tagged('d', const []),
    ];

    test('an empty filter keeps everything', () {
      expect(entriesWithAnyTag(entries, {}).length, 4);
    });

    test('one tag keeps every entry carrying it', () {
      expect(entriesWithAnyTag(entries, {'wine'}).map((e) => e.id), ['a', 'b']);
    });

    test('more tags widen the result rather than narrowing it', () {
      expect(entriesWithAnyTag(entries, {'wine', 'grocery'}).map((e) => e.id),
          ['a', 'b', 'c']);
    });

    test('a tag already covered by another adds nothing new', () {
      // 'dish' only appears on 'a', which 'wine' already matched.
      expect(entriesWithAnyTag(entries, {'wine', 'dish'}).map((e) => e.id),
          ['a', 'b']);
    });

    test('untagged entries are excluded once any filter is on', () {
      expect(entriesWithAnyTag(entries, {'wine'}).map((e) => e.id),
          isNot(contains('d')));
    });

    test('matches a query the user typed loosely', () {
      // The chip label and the stored tag both went through normalizeTags, so
      // a filter must still match when the caller did not normalize.
      expect(
          entriesWithAnyTag(entries, {'#Wine'}).map((e) => e.id), ['a', 'b']);
    });
  });
}
