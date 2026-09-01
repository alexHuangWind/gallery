import 'package:flutter_test/flutter_test.dart';
import 'package:iprefer/models/entry.dart';

Entry _at(String id, {double? lat, double? lng, required int daysAgo}) => Entry(
      id: id,
      localPath: '$id.jpg',
      text: id,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        1700000000000 - daysAgo * 86400000,
      ),
      latitude: lat,
      longitude: lng,
    );

void main() {
  // Origin: Fitzroy, Melbourne.
  const oLat = -37.7983;
  const oLng = 144.9784;

  group('sortedByDistanceFrom', () {
    test('puts the closest entry ahead of the most recent', () {
      final sorted = sortedByDistanceFrom([
        _at('sydney', lat: -33.8688, lng: 151.2093, daysAgo: 1), // recent, far
        _at('here', lat: oLat, lng: oLng, daysAgo: 30), // old, right here
      ], oLat, oLng);

      expect(sorted.map((e) => e.id), ['here', 'sydney']);
    });

    test('orders several places by real distance', () {
      final sorted = sortedByDistanceFrom([
        _at('far', lat: -37.8083, lng: oLng, daysAgo: 1), // ~1.1 km
        _at('near', lat: -37.7988, lng: oLng, daysAgo: 2), // ~55 m
        _at('mid', lat: -37.8028, lng: oLng, daysAgo: 3), // ~500 m
      ], oLat, oLng);

      expect(sorted.map((e) => e.id), ['near', 'mid', 'far']);
    });

    test('entries without a fix sort last, newest among themselves', () {
      final sorted = sortedByDistanceFrom([
        _at('nowhere-old', daysAgo: 9),
        _at('somewhere', lat: oLat, lng: oLng, daysAgo: 40),
        _at('nowhere-new', daysAgo: 2),
      ], oLat, oLng);

      // Unlocated entries all tie at infinity, so the explicit tiebreak has to
      // hold them newest-first rather than leaving it to an unstable sort.
      expect(sorted.map((e) => e.id),
          ['somewhere', 'nowhere-new', 'nowhere-old']);
    });

    test('an antipodal entry still sorts behind a near one, not ahead of the '
        'entries with no location at all', () {
      // Haversine can produce NaN here without a clamp, and NaN outranks
      // infinity in Dart's compareTo — which would put the far side of the
      // globe behind entries that have no place at all.
      final sorted = sortedByDistanceFrom([
        _at('placeless', daysAgo: 1),
        _at('antipode', lat: -69.51232454868148, lng: -93.4187717400493, daysAgo: 2),
        _at('here', lat: oLat, lng: oLng, daysAgo: 3),
      ], 69.51232454868148, 86.5812282599507);

      expect(sorted.map((e) => e.id), ['here', 'antipode', 'placeless']);
    });

    test('neither drops nor duplicates entries', () {
      final entries = [
        _at('a', lat: oLat, lng: oLng, daysAgo: 1),
        _at('b', daysAgo: 2),
        _at('c', lat: -33.8688, lng: 151.2093, daysAgo: 3),
      ];
      final sorted = sortedByDistanceFrom(entries, oLat, oLng);

      expect(sorted.length, entries.length);
      expect(sorted.map((e) => e.id).toSet(), {'a', 'b', 'c'});
    });
  });
}
