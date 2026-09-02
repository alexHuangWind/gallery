import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
// These reach into Hive's internals to hand-build bytes in the shapes older
// versions of the app wrote. Isolated in its own file: if a Hive upgrade moves
// these paths, only this file fails rather than the whole suite.
// ignore: implementation_imports
import 'package:hive/src/binary/binary_reader_impl.dart';
// ignore: implementation_imports
import 'package:hive/src/binary/binary_writer_impl.dart';
// ignore: implementation_imports
import 'package:hive/src/hive_impl.dart';
import 'package:iprefer/models/entry.dart';

void main() {
// The claim that older records still load was previously only asserted in a
// comment: the round-trip tests in entry_adapter_test.dart write with the
// CURRENT adapter, which always emits every field. These hand-build the older
// on-disk shapes so a field renumbering fails here, not in the field.
  group('legacy records still read', () {
    Entry readFrom(void Function(BinaryWriter) write) {
      final hive = HiveImpl();
      final writer = BinaryWriterImpl(hive);
      write(writer);
      return EntryAdapter().read(BinaryReaderImpl(writer.toBytes(), hive));
    }

    test('a 4-field record from before location existed', () {
      final e = readFrom((w) => w
        ..writeByte(4)
        ..writeByte(0)
        ..write('legacy-1')
        ..writeByte(1)
        ..write('legacy-1.jpg')
        ..writeByte(2)
        ..write('a flat white before the world wakes up')
        ..writeByte(3)
        ..write(1700000000000));

      expect(e.id, 'legacy-1');
      expect(e.text, 'a flat white before the world wakes up');
      expect(e.hasLocation, isFalse);
      expect(e.tags, isEmpty);
    });

    test('a 7-field record from before tags existed', () {
      final e = readFrom((w) => w
        ..writeByte(7)
        ..writeByte(0)
        ..write('legacy-2')
        ..writeByte(1)
        ..write('legacy-2.jpg')
        ..writeByte(2)
        ..write('ferns that uncurl like a slow question')
        ..writeByte(3)
        ..write(1700000000000)
        ..writeByte(4)
        ..write(-37.7983)
        ..writeByte(5)
        ..write(144.9784)
        ..writeByte(6)
        ..write('fitzroy'));

      expect(e.id, 'legacy-2');
      expect(e.hasLocation, isTrue);
      expect(e.placeLabel, 'fitzroy');
      expect(e.tags, isEmpty);
    });

    test('a record holding an un-normalized tag is normalized on read', () {
      // Written before the constructor enforced normalization. Left raw, the
      // filter chip would read "Wine" while hasTag compared against "wine",
      // emptying the timeline under a lit chip.
      final e = readFrom((w) => w
        ..writeByte(8)
        ..writeByte(0)
        ..write('legacy-3')
        ..writeByte(1)
        ..write('legacy-3.jpg')
        ..writeByte(2)
        ..write('a jug of milk')
        ..writeByte(3)
        ..write(1700000000000)
        ..writeByte(4)
        ..write(null)
        ..writeByte(5)
        ..write(null)
        ..writeByte(6)
        ..write(null)
        ..writeByte(7)
        ..write(<String>['Wine', ' WINE ']));

      expect(e.tags, ['wine']);
      expect(e.hasTag('wine'), isTrue);
    });
  });
}
