import 'package:hive/hive.dart';

/// One recorded preference: a photo, a line, a moment.
///
/// The `text` holds only the user's words — the "I prefer" prefix lives in the
/// card layout, not the data, so it never gets double-rendered or edited away.
class Entry {
  Entry({
    required this.id,
    required this.localPath,
    required this.text,
    required this.createdAt,
  });

  final String id;

  /// Absolute path to the saved photo on disk (copied into app documents).
  final String localPath;

  /// The "I prefer ..." line, without the prefix.
  final String text;

  final DateTime createdAt;
}

/// Hand-written Hive adapter so the project builds without code generation
/// (no build_runner step needed for the MVP).
class EntryAdapter extends TypeAdapter<Entry> {
  @override
  final int typeId = 1;

  @override
  Entry read(BinaryReader reader) {
    final fields = <int, dynamic>{};
    final count = reader.readByte();
    for (var i = 0; i < count; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return Entry(
      id: fields[0] as String,
      localPath: fields[1] as String,
      text: fields[2] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(fields[3] as int),
    );
  }

  @override
  void write(BinaryWriter writer, Entry obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.localPath)
      ..writeByte(2)
      ..write(obj.text)
      ..writeByte(3)
      ..write(obj.createdAt.millisecondsSinceEpoch);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntryAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}
