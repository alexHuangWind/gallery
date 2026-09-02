import 'package:flutter_test/flutter_test.dart';
import 'package:iprefer/data/sync/sync_op.dart';
import 'package:iprefer/models/entry.dart';

/// What the read path does with bytes we did not write.
///
/// The rule these pin: parsing a page of the server's log must not be able to
/// throw its way out of the pull loop. The cursor only advances after a page is
/// applied, so a hard cast on one bad record would make the client re-request
/// that same page forever — sync frozen for that account, on every device, with
/// no way out but a reinstall. Anything defaultable is defaulted; only a
/// missing id or seq is refused, and refused as a [MalformedSyncOp] the caller
/// can catch per op.
void main() {
  group('Entry.fromSyncJson', () {
    Map<String, Object?> wire(Map<String, Object?> overrides) => {
          'id': 'abc-123',
          'text': 'a flat white before the world wakes up',
          'createdAt': 1700000000000,
          'photoName': 'abc-123.jpg',
          ...overrides,
        };

    test('a null createdAt parses at the epoch, not at now', () {
      final entry = Entry.fromSyncJson(wire({'createdAt': null}));

      // Epoch so the record settles at the bottom of the timeline instead of
      // taking the top of it, at a different time, on every sync.
      expect(entry.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(entry.text, 'a flat white before the world wakes up');
    });

    test('a createdAt of the wrong type parses at the epoch', () {
      final entry = Entry.fromSyncJson(wire({'createdAt': '1700000000000'}));

      expect(entry.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('a missing id is refused by name', () {
      expect(
        () => Entry.fromSyncJson(wire({'id': null})),
        throwsA(isA<MalformedSyncOp>()
            .having((e) => e.field, 'field', 'id')
            .having((e) => e.message, 'message', contains('id'))),
      );
      // An id of the wrong type is the same thing: nothing can invent one, and
      // it is the box key.
      expect(
        () => Entry.fromSyncJson(wire({'id': 7})),
        throwsA(isA<MalformedSyncOp>()),
      );
      expect(
        () => Entry.fromSyncJson(wire({'id': ''})),
        throwsA(isA<MalformedSyncOp>()),
      );
    });

    test('tags that are not a list come back empty', () {
      expect(Entry.fromSyncJson(wire({'tags': 'wine'})).tags, isEmpty);
      expect(Entry.fromSyncJson(wire({'tags': null})).tags, isEmpty);
      expect(
          Entry.fromSyncJson(wire({
            'tags': {'wine': 1}
          })).tags,
          isEmpty);
      // A real list still normalizes as usual.
      expect(
          Entry.fromSyncJson(wire({
            'tags': ['Wine', ' wine ']
          })).tags,
          ['wine']);
    });

    test('coordinates that arrived as strings are dropped, not parsed', () {
      // A dot in the wrong place is worse than no dot: recall would offer the
      // wrong memory at the wrong café.
      final entry = Entry.fromSyncJson(
          wire({'latitude': '-36.8485', 'longitude': '174.7633'}));

      expect(entry.latitude, isNull);
      expect(entry.longitude, isNull);
      expect(entry.hasLocation, isFalse);
    });

    test('a text or placeLabel of the wrong type degrades, never throws', () {
      final entry =
          Entry.fromSyncJson(wire({'text': 42, 'placeLabel': const []}));

      expect(entry.text, '');
      expect(entry.placeLabel, isNull);
    });

    test('a missing photoName falls back to the server naming rule', () {
      expect(Entry.fromSyncJson(wire({'photoName': null})).localPath,
          'abc-123.jpg');
      expect(
          Entry.fromSyncJson(wire({'photoName': ''})).localPath, 'abc-123.jpg');
    });
  });

  group('SyncOp.fromJson', () {
    test('a missing entryId is refused by name', () {
      expect(
        () => SyncOp.fromJson({'type': 'create', 'payload': const {}}),
        throwsA(
            isA<MalformedSyncOp>().having((e) => e.field, 'field', 'entryId')),
      );
    });

    test('an unknown type reads as a create, as it always did', () {
      final op = SyncOp.fromJson({'type': 'sideways', 'entryId': 'e1'});

      expect(op.type, SyncOpType.create);
      expect(op.entryId, 'e1');
    });

    test('a payload of the wrong shape is treated as absent', () {
      // The applier already skips a create with no payload, so this degrades
      // to "one entry didn't arrive" instead of stalling the whole log.
      final op = SyncOp.fromJson(
          {'type': 'create', 'entryId': 'e1', 'payload': 'not a map'});

      expect(op.payload, isNull);
    });
  });

  group('RemoteOp.fromJson', () {
    test('a missing seq is refused by name', () {
      // Defaulting the cursor either rewinds the client to the start of the
      // log or marks an op applied that never was.
      expect(
        () => RemoteOp.fromJson({'type': 'delete', 'entryId': 'e1'}),
        throwsA(isA<MalformedSyncOp>().having((e) => e.field, 'field', 'seq')),
      );
    });

    test('a well-formed op still parses', () {
      final remote = RemoteOp.fromJson({
        'seq': 12,
        'type': 'delete',
        'entryId': 'e1',
      });

      expect(remote.seq, 12);
      expect(remote.op.type, SyncOpType.delete);
      expect(remote.op.entryId, 'e1');
    });
  });
}
