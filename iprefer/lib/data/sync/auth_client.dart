import 'dart:convert';

import 'package:http/http.dart' as http;

/// What the server hands back once it believes who you are.
class AppleSession {
  const AppleSession({required this.token, required this.userId});

  /// Bearer token for every subsequent call. Not a JWT we parse — opaque.
  final String token;

  /// Our server's id for this account. Deliberately not Apple's `sub`.
  final String userId;
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Exchanges an Apple identity token for a session with our backend.
///
/// Separated from [Session] so signing in can be tested without a device, a
/// developer account, or a network.
abstract class AuthClient {
  Future<AppleSession> exchangeAppleToken(String identityToken);
}

class HttpAuthClient implements AuthClient {
  HttpAuthClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  Future<AppleSession> exchangeAppleToken(String identityToken) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl/v1/auth/apple'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'identityToken': identityToken}),
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      // The server says 401 for anything it won't accept about the token
      // itself; everything else is ours or the network's.
      throw AuthException(
        res.statusCode == 401
            ? "apple couldn't confirm that sign-in"
            : "couldn't reach the server (${res.statusCode})",
      );
    }

    final body = jsonDecode(res.body) as Map<String, Object?>;
    final token = body['token'];
    final userId = body['userId'];
    if (token is! String || userId is! String) {
      throw AuthException('the server sent back an unexpected reply');
    }
    return AppleSession(token: token, userId: userId);
  }
}
