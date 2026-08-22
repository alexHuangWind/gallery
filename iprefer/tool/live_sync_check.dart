/// Wire-contract check: the real Dart client against the real Worker.
///
///   cd server && npm run dev        # in one terminal
///   dart run tool/live_sync_check.dart
///
/// The unit tests in test/sync_test.dart cover the orchestration against a
/// fake. They cannot catch the one thing this catches: a field name or an
/// encoding that Dart and TypeScript disagree about. Kept out of test/ so
/// `flutter test` never depends on a running server.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:iprefer/data/sync/sync_api.dart';
import 'package:iprefer/data/sync/sync_op.dart';
import 'package:iprefer/models/entry.dart';

const baseUrl = 'http://127.0.0.1:8787';

var passed = 0;
final failures = <String>[];

void check(String name, bool ok, [String? detail]) {
  if (ok) {
    passed++;
    print('  ok  $name');
  } else {
    failures.add(name);
    print('FAIL  $name${detail == null ? '' : ' — $detail'}');
  }
}

Future<void> main() async {
  print('live wire check against $baseUrl\n');

  final auth = await http.post(
    Uri.parse('$baseUrl/v1/auth/dev'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'localId': 'wirecheck-${DateTime.now().microsecondsSinceEpoch}'}),
  );
  if (auth.statusCode != 200) {
    stderr.writeln('could not get a dev token (HTTP ${auth.statusCode}).');
    stderr.writeln('is `npm run dev` running in server/?');
    exit(1);
  }
  final token = (jsonDecode(auth.body) as Map)['token'] as String;
  final api = HttpSyncApi(baseUrl: baseUrl, token: token);

  // A deliberately awkward entry: unicode, an emoji tag, a real fix, and a
  // millisecond timestamp — every field the server validates.
  final id = '5f2b1c34-9a7e-4d10-b8c6-0e1a2b3c4d5e';
  final entry = Entry(
    id: id,
    localPath: '$id.jpg',
    text: 'ferns that uncurl like a slow question — 蕨类',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1755000000123),
    latitude: -36.8485,
    longitude: 174.7633,
    placeLabel: 'fitzroy',
    tags: const ['plants', '🍷 wine'],
  );

  // --- push ---------------------------------------------------------------
  await api.push([SyncOp.create(entry)]);
  check('the server accepts a create built by the Dart client', true);

  // --- pull it back -------------------------------------------------------
  final page = await api.pull(since: 0);
  check('pull returns the op', page.ops.length == 1, 'got ${page.ops.length}');

  final back = Entry.fromSyncJson(page.ops.single.op.payload!);
  check('text survives unicode', back.text == entry.text, back.text);
  check('createdAt keeps millisecond precision',
      back.createdAt == entry.createdAt, '${back.createdAt}');
  check('latitude survives', back.latitude == entry.latitude, '${back.latitude}');
  check('placeLabel survives', back.placeLabel == entry.placeLabel);
  check('tags survive, emoji included',
      back.tags.join(',') == entry.tags.join(','), back.tags.join(','));
  check('photoName maps back to localPath', back.localPath == '$id.jpg', back.localPath);
  check('the cursor is the last seq', page.seq == page.ops.single.seq);

  // --- idempotency across the real wire -----------------------------------
  await api.push([SyncOp.create(entry)]);
  final again = await api.pull(since: 0);
  check('re-pushing does not duplicate on the server', again.ops.length == 1,
      'got ${again.ops.length}');

  // --- photos -------------------------------------------------------------
  final bytes = Uint8List.fromList(List.generate(4096, (i) => i % 251));
  await api.uploadPhoto(entry.syncPhotoName, bytes);
  final fetched = await api.downloadPhoto(entry.syncPhotoName);
  check('photo bytes round-trip exactly',
      fetched != null && fetched.length == bytes.length && fetched[4095] == bytes[4095]);

  final absent = await api.downloadPhoto('00000000-0000-4000-8000-000000000000.jpg');
  check('a missing photo comes back as null, not an error', absent == null);

  // --- delete -------------------------------------------------------------
  await api.push([SyncOp.delete(id)]);
  final afterDelete = await api.pull(since: page.seq);
  check('the delete arrives as its own op',
      afterDelete.ops.length == 1 && afterDelete.ops.single.op.type == SyncOpType.delete);

  print('\n$passed passed, ${failures.length} failed');
  if (failures.isNotEmpty) {
    print('failed: ${failures.join(', ')}');
    exit(1);
  }
}
