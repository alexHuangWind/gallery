import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'sync_op.dart';

/// One page of the server's op log.
class PullPage {
  const PullPage({required this.ops, required this.seq, required this.hasMore});

  final List<RemoteOp> ops;
  final int seq;
  final bool hasMore;
}

/// Raised for anything the caller can't fix by retrying differently. The sync
/// service treats every failure the same way — try again later — so this
/// carries a message for logs, not a taxonomy.
class SyncApiException implements Exception {
  SyncApiException(this.message);
  final String message;
  @override
  String toString() => 'SyncApiException: $message';
}

/// The session token is no longer accepted.
///
/// Split out from [SyncApiException] because it is the one failure that
/// retrying cannot fix: tokens last 30 days, and a lapsed one makes every
/// sync fail identically to being offline. Without this distinction the app
/// would keep "trying again" forever while quietly not backing anything up —
/// the archive silently stops being safe and nothing ever says so.
class SyncAuthExpiredException extends SyncApiException {
  SyncAuthExpiredException() : super('the sync session has expired');
}

/// The server as the app sees it.
///
/// An interface rather than a concrete client so the sync service can be
/// tested against a fake — the orchestration (cursor handling, what bounces
/// back into the outbox) is where the bugs live, and none of it should need a
/// live server to pin down.
abstract class SyncApi {
  Future<int> push(List<SyncOp> ops);
  Future<PullPage> pull({required int since, int limit});
  Future<void> uploadPhoto(String name, Uint8List bytes);

  /// Null when the server has no photo under that name.
  Future<Uint8List?> downloadPhoto(String name);
}

/// Talks to `server/` over HTTP.
class HttpSyncApi implements SyncApi {
  HttpSyncApi({
    required this.baseUrl,
    required this.token,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String token;
  final Duration timeout;
  final http.Client _client;

  Map<String, String> get _headers => {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Never _fail(http.BaseResponse res, String what) {
    if (res.statusCode == 401) throw SyncAuthExpiredException();
    throw SyncApiException('$what failed: HTTP ${res.statusCode}');
  }

  @override
  Future<int> push(List<SyncOp> ops) async {
    final res = await _client
        .post(
          _uri('/v1/sync/push'),
          headers: _headers,
          body: jsonEncode({'ops': [for (final o in ops) o.toJson()]}),
        )
        .timeout(timeout);
    if (res.statusCode != 200) _fail(res, 'push');
    final body = jsonDecode(res.body) as Map<String, Object?>;
    return (body['seq'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<PullPage> pull({required int since, int limit = 200}) async {
    final res = await _client
        .get(
          _uri('/v1/sync/pull', {'since': '$since', 'limit': '$limit'}),
          headers: _headers,
        )
        .timeout(timeout);
    if (res.statusCode != 200) _fail(res, 'pull');
    final body = jsonDecode(res.body) as Map<String, Object?>;
    final raw = (body['ops'] as List?) ?? const [];
    return PullPage(
      ops: [
        for (final o in raw) RemoteOp.fromJson((o as Map).cast<String, Object?>()),
      ],
      seq: (body['seq'] as num?)?.toInt() ?? since,
      hasMore: body['hasMore'] == true,
    );
  }

  @override
  Future<void> uploadPhoto(String name, Uint8List bytes) async {
    final res = await _client
        .put(
          _uri('/v1/photos/$name'),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': _contentTypeFor(name),
          },
          body: bytes,
        )
        .timeout(timeout);
    if (res.statusCode != 204 && res.statusCode != 200) _fail(res, 'photo upload');
  }

  @override
  Future<Uint8List?> downloadPhoto(String name) async {
    final res = await _client
        .get(_uri('/v1/photos/$name'), headers: {'authorization': 'Bearer $token'})
        .timeout(timeout);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) _fail(res, 'photo download');
    return res.bodyBytes;
  }

  static String _contentTypeFor(String name) {
    final dot = name.lastIndexOf('.');
    switch (dot > 0 ? name.substring(dot + 1).toLowerCase() : '') {
      case 'png':
        return 'image/png';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}
