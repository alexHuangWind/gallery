/// The server's wire rules, restated on the client — the mirror of
/// `server/src/validate.ts`.
///
/// This exists because the server validates a push as a *batch* and throws on
/// the first bad op: one unsendable op doesn't fail alone, it 400s the whole
/// request and stops every other entry on the phone from ever backing up. The
/// queue is retried forever, so that state never clears by itself.
///
/// Nothing here is a second opinion about what a good entry is — it is a copy
/// of someone else's rules, and the only correct response to a mismatch is to
/// make it agree again. Both halves live in exactly two files: this one and
/// `server/src/validate.ts`. Change one, change the other.
library;

import 'sync_op.dart';

/// Kept in step with `MAX_TEXT_LENGTH` / `MAX_TAGS` / `MAX_TAG_LENGTH`.
const int kMaxTextLength = 2000;
const int kMaxTags = 32;
const int kMaxTagLength = 40;

/// Allowlist, not a pattern — the same set the server will accept as an object
/// key. image_picker only ever produces these.
const Set<String> kPhotoExtensions = {'jpg', 'jpeg', 'png', 'heic', 'heif', 'webp'};

final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Why the server would reject [op], in the server's own words — or null when
/// it would accept it.
///
/// Pure, so the outbox can ask before writing a row and so the rules can be
/// tested without a server or a box.
String? syncOpProblem(SyncOp op) {
  if (!_isEntryId(op.entryId)) return 'entryId must be a uuid';
  // A delete carries nothing else; its id is the whole op.
  if (op.type == SyncOpType.delete) return null;

  final Map<String, Object?>? payload = op.payload;
  if (payload == null) return 'a create must carry a payload';
  return _entryProblem(payload, op.entryId);
}

bool _isEntryId(String value) => _uuid.hasMatch(value);

String? _entryProblem(Map<String, Object?> payload, String entryId) {
  // A torn Hive record reads back as id: '' / text: '' (EntryAdapter softens
  // every cast so one bad row can't black-screen the app at startup). That
  // entry is unsendable, and this is where it stops being everyone else's
  // problem.
  if (payload['id'] != entryId) return 'payload.id must match the op entry id';

  final Object? text = payload['text'];
  if (text is! String) return 'text must be a string';
  if (text.isEmpty) return 'text must not be empty';
  // Runes, like the server's spread-then-count: an emoji is one character
  // there and two UTF-16 units here.
  if (text.runes.length > kMaxTextLength) return 'text is too long';

  final Object? createdAt = payload['createdAt'];
  if (createdAt is! num || !createdAt.isFinite) return 'createdAt must be a number';

  final Object? latitude = payload['latitude'];
  final Object? longitude = payload['longitude'];
  final String? latProblem = _coordinateProblem(latitude, 'latitude', 90);
  if (latProblem != null) return latProblem;
  final String? lngProblem = _coordinateProblem(longitude, 'longitude', 180);
  if (lngProblem != null) return lngProblem;
  // Half a fix is not a fix — the client stores both or neither.
  if ((latitude == null) != (longitude == null)) {
    return 'latitude and longitude must agree';
  }

  final Object? placeLabel = payload['placeLabel'];
  if (placeLabel != null && placeLabel is! String) {
    return 'placeLabel must be a string or null';
  }

  final Object? tags = payload['tags'];
  if (tags != null) {
    if (tags is! List) return 'tags must be an array';
    // normalizeTags caps a tag's length but not how many there are, so a
    // paste-happy compose screen can still build an entry past the server's
    // limit.
    if (tags.length > kMaxTags) return 'too many tags';
    for (final Object? tag in tags) {
      if (tag is! String) return 'tags must be strings';
      if (tag.runes.length > kMaxTagLength) return 'tag is too long';
    }
  }

  return _photoNameProblem(payload['photoName'], entryId);
}

String? _coordinateProblem(Object? value, String label, num limit) {
  if (value == null) return null;
  if (value is! num || !value.isFinite) return '$label must be a finite number';
  if (value.abs() > limit) return '$label out of range';
  return null;
}

/// The photo name must be exactly `<entryId>.<ext>`: the server derives its
/// object key from it, so a name that doesn't match is either unstorable or a
/// way to point one entry at another entry's photo.
String? _photoNameProblem(Object? name, String entryId) {
  if (name is! String) return 'photoName must be a string';
  final int dot = name.lastIndexOf('.');
  if (dot <= 0) return 'photoName must have an extension';
  if (name.substring(0, dot) != entryId) {
    return 'photoName must start with the entry id';
  }
  if (!kPhotoExtensions.contains(name.substring(dot + 1).toLowerCase())) {
    // Reachable from a record written before photos were named after their
    // entry, where the extension came off whatever the picker handed us.
    return 'photoName has an unsupported extension';
  }
  return null;
}
