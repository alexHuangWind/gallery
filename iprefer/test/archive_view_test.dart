import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iprefer/data/archive_view.dart';
import 'package:iprefer/data/location_service.dart';
import 'package:iprefer/models/entry.dart';

/// Tier 1 exercises the pure view-state logic, which needs no seam at all.
/// Tier 2 drives the "nearest" sort state machine through the injected getFix,
/// pinning the rules the README documents: a failed refresh keeps the old
/// origin, "unavailable" only when there was never a fix, and the locating
/// latch always releases.
void main() {
  final when = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  Entry entryAt(String id, {double? lat, double? lng, DateTime? createdAt}) =>
      Entry(
        id: id,
        localPath: '$id.jpg',
        text: 'thing $id',
        createdAt: createdAt ?? when,
        latitude: lat,
        longitude: lng,
      );

  group('tags (no seam needed)', () {
    test('toggle selects and unselects', () {
      final view = ArchiveView();
      var notified = 0;
      view.addListener(() => notified++);

      view.toggle('wine');
      expect(view.isSelected('wine'), isTrue);
      view.toggle('wine');
      expect(view.isSelected('wine'), isFalse);
      expect(notified, 2);
    });

    test('clear only notifies when there was something to clear', () {
      final view = ArchiveView();
      var notified = 0;
      view.addListener(() => notified++);

      view.clear();
      expect(notified, 0);

      view.toggle('wine');
      view.clear();
      expect(view.isEmpty, isTrue);
      expect(notified, 2);
    });

    test('effective hides vanished tags without mutating the selection', () {
      final view = ArchiveView();
      view.toggle('wine');
      view.toggle('dish');

      expect(view.effective(['wine']), {'wine'});
      // The selection itself is untouched — that's prune's job.
      expect(view.selected, {'wine', 'dish'});
    });

    test('prune drops selections whose tag no longer exists', () {
      final view = ArchiveView();
      var notified = 0;
      view.toggle('wine');
      view.toggle('dish');
      view.addListener(() => notified++);

      view.prune(['wine']);
      expect(view.selected, {'wine'});
      expect(notified, 1);

      // Pruning again with nothing stale must not notify.
      view.prune(['wine']);
      expect(notified, 1);
    });

    test('reset restores every default', () async {
      final view = ArchiveView(getFix: ({bool prompt = false}) async => null);
      view.toggle('wine');
      await view.setSort(ArchiveSort.nearest);

      view.reset();

      expect(view.isEmpty, isTrue);
      expect(view.sort, ArchiveSort.newest);
      expect(view.origin, isNull);
      expect(view.locating, isFalse);
      expect(view.originUnavailable, isFalse);
    });
  });

  group('nearest-sort state machine (injected getFix)', () {
    const fitzroy =
        PlaceFix(latitude: -37.7983, longitude: 144.9784, label: 'fitzroy');

    test('a successful fix lands as the origin', () async {
      bool? promptedWith;
      final view = ArchiveView(getFix: ({bool prompt = false}) async {
        promptedWith = prompt;
        return fitzroy;
      });

      await view.setSort(ArchiveSort.nearest);

      expect(view.origin, fitzroy);
      expect(view.locating, isFalse);
      expect(view.originUnavailable, isFalse);
      // The user explicitly asked for distance sort, so prompting is allowed.
      expect(promptedWith, isTrue);
    });

    test('no fix and no history reads as unavailable', () async {
      final view = ArchiveView(getFix: ({bool prompt = false}) async => null);

      await view.setSort(ArchiveSort.nearest);

      expect(view.origin, isNull);
      expect(view.originUnavailable, isTrue);
      expect(view.locating, isFalse);
    });

    test('a failed refresh keeps the previous origin', () async {
      var calls = 0;
      final view = ArchiveView(getFix: ({bool prompt = false}) async {
        calls++;
        return calls == 1 ? fitzroy : null;
      });

      await view.setSort(ArchiveSort.nearest);
      await view.refreshOrigin();

      // The stale-but-real fix beats no fix at all.
      expect(view.origin, fitzroy);
      expect(view.originUnavailable, isFalse);
    });

    test('a second resolve cannot start while one is in flight', () async {
      var calls = 0;
      final gate = Completer<PlaceFix?>();
      final view = ArchiveView(getFix: ({bool prompt = false}) {
        calls++;
        return gate.future;
      });

      final first = view.setSort(ArchiveSort.nearest);
      expect(view.locating, isTrue);

      // Re-entering while locating must not fire a second platform request.
      final second = view.refreshOrigin();
      expect(calls, 1);

      gate.complete(fitzroy);
      await Future.wait([first, second]);

      expect(view.locating, isFalse);
      expect(view.origin, fitzroy);
    });

    test('order sorts by distance only with a nearest sort AND an origin',
        () async {
      final entries = [
        entryAt('far', lat: -37.90, lng: 144.9784), // newest-first input order
        entryAt('near', lat: -37.80, lng: 144.9784),
      ];

      final unresolved =
          ArchiveView(getFix: ({bool prompt = false}) async => null);
      await unresolved.setSort(ArchiveSort.nearest);
      // No origin: the incoming (newest-first) order must survive untouched.
      expect(unresolved.order(entries).map((e) => e.id), ['far', 'near']);

      final resolved =
          ArchiveView(getFix: ({bool prompt = false}) async => fitzroy);
      await resolved.setSort(ArchiveSort.nearest);
      expect(resolved.order(entries).map((e) => e.id), ['near', 'far']);

      resolved.reset();
      // Back on newest: input order again.
      expect(resolved.order(entries).map((e) => e.id), ['far', 'near']);
    });
  });
}
