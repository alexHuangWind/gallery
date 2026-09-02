import 'package:flutter_test/flutter_test.dart';
import 'package:iprefer/models/entry.dart';

Entry _at(String id, {double? lat, double? lng}) => Entry(
      id: id,
      localPath: '/photos/$id.jpg',
      text: id,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      latitude: lat,
      longitude: lng,
    );

void main() {
  group('haversineMetres', () {
    test('is zero for the same point', () {
      expect(haversineMetres(-37.7983, 144.9784, -37.7983, 144.9784),
          closeTo(0, 0.001));
    });

    test('matches a known short distance', () {
      // 0.001 degrees of latitude is ~111.2 m anywhere on the globe.
      final d = haversineMetres(-37.7983, 144.9784, -37.7993, 144.9784);
      expect(d, closeTo(111.2, 1.0));
    });

    test('matches a known long distance (Melbourne to Sydney ~713 km)', () {
      final d = haversineMetres(-37.8136, 144.9631, -33.8688, 151.2093);
      expect(d / 1000, closeTo(713, 10));
    });

    test('is symmetric', () {
      final a = haversineMetres(-37.81, 144.96, -33.86, 151.20);
      final b = haversineMetres(-33.86, 151.20, -37.81, 144.96);
      expect(a, closeTo(b, 0.001));
    });
  });

  group('Entry.metresTo', () {
    test('reports infinity when the entry has no fix', () {
      expect(_at('none').metresTo(-37.7983, 144.9784), double.infinity);
    });

    test('measures from the entry to the given point', () {
      final e = _at('here', lat: -37.7983, lng: 144.9784);
      expect(e.metresTo(-37.7993, 144.9784), closeTo(111.2, 1.0));
    });

    test('a 200 m radius admits a close point and rejects a far one', () {
      final e = _at('cafe', lat: -37.7983, lng: 144.9784);
      // ~55 m away
      expect(e.metresTo(-37.79880, 144.9784) <= 200, isTrue);
      // ~1.1 km away
      expect(e.metresTo(-37.80830, 144.9784) <= 200, isFalse);
    });
  });
}
