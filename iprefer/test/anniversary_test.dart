import 'package:flutter_test/flutter_test.dart';
import 'package:iprefer/models/entry.dart';

/// "On this day" is the retention mechanic on the time axis, and its whole
/// job is to be right about dates. Calls the production function directly.
void main() {
  var n = 0;
  Entry at(DateTime when, {String text = 'a thing', List<String>? tags}) => Entry(
        id: 'id-${n++}',
        localPath: 'p.jpg',
        text: text,
        createdAt: when,
        tags: tags,
      );

  final today = DateTime(2026, 8, 25, 14, 30);

  test('an empty archive has nothing to say', () {
    expect(anniversaryOn(const [], today), isNull);
  });

  test('a day the archive knows nothing about stays silent', () {
    final entries = [at(DateTime(2025, 3, 14)), at(DateTime(2024, 11, 2))];

    expect(anniversaryOn(entries, today), isNull);
  });

  group('years', () {
    test('the same date a year back reads as "a year ago today"', () {
      final entries = [at(DateTime(2025, 8, 25, 9), text: 'a flat white')];

      final result = anniversaryOn(entries, today)!;

      expect(result.label, 'a year ago today');
      expect(result.entries.single.text, 'a flat white');
    });

    test('two years back is pluralised', () {
      final entries = [at(DateTime(2024, 8, 25))];

      expect(anniversaryOn(entries, today)!.label, '2 years ago today');
    });

    test('the most distant anniversary wins', () {
      final entries = [at(DateTime(2025, 8, 25)), at(DateTime(2023, 8, 25))];

      final result = anniversaryOn(entries, today)!;

      // Three years back is the one you have had time to forget.
      expect(result.label, '3 years ago today');
      expect(result.entries.length, 1);
    });

    test('several entries from the same anniversary all come back, newest first',
        () {
      final entries = [
        at(DateTime(2025, 8, 25, 8), text: 'morning'),
        at(DateTime(2025, 8, 25, 20), text: 'evening'),
      ];

      final result = anniversaryOn(entries, today)!;

      expect(result.entries.map((e) => e.text), ['evening', 'morning']);
    });
  });

  group('the month fallback', () {
    test('a young archive is not silent until its first birthday', () {
      // The whole reason the fallback exists: this app is weeks old.
      final entries = [at(DateTime(2026, 7, 25), text: 'last month')];

      final result = anniversaryOn(entries, today)!;

      expect(result.label, 'a month ago today');
      expect(result.entries.single.text, 'last month');
    });

    test('months are counted across a year boundary', () {
      final entries = [at(DateTime(2025, 12, 25))];

      expect(anniversaryOn(entries, today)!.label, '8 months ago today');
    });

    test('a year match always beats a month match', () {
      final entries = [
        at(DateTime(2026, 7, 25), text: 'a month ago'),
        at(DateTime(2025, 8, 25), text: 'a year ago'),
      ];

      final result = anniversaryOn(entries, today)!;

      expect(result.label, 'a year ago today');
      expect(result.entries.single.text, 'a year ago');
    });
  });

  group('boundaries', () {
    test("today's own entries are not a memory", () {
      final entries = [at(DateTime(2026, 8, 25, 6)), at(DateTime(2026, 8, 25, 23))];

      // Being handed back what you recorded this morning is not a memory,
      // it is the timeline you are already looking at.
      expect(anniversaryOn(entries, today), isNull);
    });

    test('the day before is not an anniversary of anything', () {
      expect(anniversaryOn([at(DateTime(2026, 8, 24))], today), isNull);
    });

    test('a future entry is ignored rather than counted backwards', () {
      // A clock rolled forward and back would otherwise produce a negative
      // interval and a nonsense label.
      expect(anniversaryOn([at(DateTime(2027, 8, 25))], today), isNull);
    });

    test('the same day of an earlier month, not the same date, is a month match',
        () {
      final entries = [at(DateTime(2026, 6, 25))];

      expect(anniversaryOn(entries, today)!.label, '2 months ago today');
    });

    test('a month with no such day simply has no match', () {
      // Nothing can be recorded on 31 February, so a 31st never gets a false
      // month match from a short month.
      final endOfMonth = DateTime(2026, 3, 31);
      final entries = [at(DateTime(2026, 2, 28))];

      expect(anniversaryOn(entries, endOfMonth), isNull);
    });
  });

  test('it composes with the tag filter', () {
    final entries = [
      at(DateTime(2025, 8, 25), text: 'wine one', tags: const ['wine']),
      at(DateTime(2025, 8, 25), text: 'a dish', tags: const ['dish']),
    ];

    // The timeline passes an already-filtered list, so the anniversary
    // inherits whatever chip is lit.
    final filtered = entriesWithAnyTag(entries, {'wine'});
    final result = anniversaryOn(filtered, today)!;

    expect(result.entries.single.text, 'wine one');
  });
}
