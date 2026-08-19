import 'package:flutter_test/flutter_test.dart';
import 'package:iprefer/models/entry.dart';

Entry _at(String id, {double? lat, double? lng, required int daysAgo}) => Entry(
      id: id,
      localPath: '/photos/$id.jpg',
      text: id,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        1700000000000 - daysAgo * 86400000,
      ),
      latitude: lat,
      longitude: lng,
    );

/// Mirrors ArchiveView.order for ArchiveSort.nearest, including the explicit
/// tiebreak that stands in for Dart's non-stable sort.
List<Entry> byDistance(List<Entry> entries, double lat, double lng) =>
    [...entries]..sort((a, b) {
      final d = a.metresTo(lat, lng).compareTo(b.metresTo(lat, lng));
      if (d != 0) return d;
      return b.createdAt.compareTo(a.createdAt);
    });

void main() {
  // Origin: Fitzroy, Melbourne.
  const oLat = -37.7983;
  const oLng = 144.9784;

  test('newest-first orders by recency regardless of place', () {
    final entries = [
      _at('old', lat: oLat, lng: oLng, daysAgo: 10),
      _at('new', lat: -33.8688, lng: 151.2093, daysAgo: 1),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    expect(entries.map((e) => e.id), ['new', 'old']);
  });

  test('nearest-first puts the closest entry ahead of the most recent', () {
    final entries = [
      // Recent but ~713 km away.
      _at('sydney', lat: -33.8688, lng: 151.2093, daysAgo: 1),
      // Older but right here.
      _at('here', lat: oLat, lng: oLng, daysAgo: 30),
    ];

    expect(byDistance(entries, oLat, oLng).map((e) => e.id),
        ['here', 'sydney']);
  });

  test('nearest-first orders several places by real distance', () {
    final entries = [
      _at('far', lat: -37.8083, lng: oLng, daysAgo: 1), // ~1.1 km
      _at('near', lat: -37.7988, lng: oLng, daysAgo: 2), // ~55 m
      _at('mid', lat: -37.8028, lng: oLng, daysAgo: 3), // ~500 m
    ];

    expect(byDistance(entries, oLat, oLng).map((e) => e.id),
        ['near', 'mid', 'far']);
  });

  test('entries without a fix sort last, newest among themselves', () {
    final entries = [
      _at('nowhere-old', daysAgo: 9),
      _at('somewhere', lat: oLat, lng: oLng, daysAgo: 40),
      _at('nowhere-new', daysAgo: 2),
    ];

    // All unlocated entries tie at infinity, so the tiebreak must hold them in
    // newest-first order rather than leaving it to an unstable sort.
    expect(byDistance(entries, oLat, oLng).map((e) => e.id),
        ['somewhere', 'nowhere-new', 'nowhere-old']);
  });

  test('sorting by distance does not drop or duplicate entries', () {
    final entries = [
      _at('a', lat: oLat, lng: oLng, daysAgo: 1),
      _at('b', daysAgo: 2),
      _at('c', lat: -33.8688, lng: 151.2093, daysAgo: 3),
    ];

    final sorted = byDistance(entries, oLat, oLng);
    expect(sorted.length, entries.length);
    expect(sorted.map((e) => e.id).toSet(), {'a', 'b', 'c'});
  });
}
