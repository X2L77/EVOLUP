import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The user signed in by [SupabaseTestServer.signIn].
const testUserId = '11111111-1111-1111-1111-111111111111';

/// A fake HTTP server behind a real [SupabaseClient]: the real repositories
/// run against it, with no network and no Supabase project.
class SupabaseTestServer {
  SupabaseTestServer(this.handler);

  Future<http.Response> Function(http.Request request) handler;
  final requests = <http.Request>[];

  late final client = SupabaseClient(
    'http://localhost:54321',
    'publishable-test-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      requests.add(request);
      final response = await handler(request);
      // postgrest reads the request back from the response, as with a
      // real HTTP client.
      return http.Response.bytes(
        response.bodyBytes,
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    }),
  );

  /// Signs in locally (no request: the token is not a JWT, so it never
  /// expires and is not refreshed).
  Future<void> signIn() => client.auth.recoverSession(
    jsonEncode({
      'access_token': 'test-access-token',
      'token_type': 'bearer',
      'user': {'id': testUserId},
    }),
  );
}

/// A JSON answer, as PostgREST sends it.
http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
