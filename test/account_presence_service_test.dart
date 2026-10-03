import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/account_presence_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('app reports contact while signed in and stops after sign out', () async {
    final calls = <String>[];
    final token =
        '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'guard', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})))}.test';
    final client = SupabaseClient(
      'https://presence.example.test',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        calls.add(request.url.path);
        final body = request.url.path == '/auth/v1/token'
            ? {
                'access_token': token,
                'refresh_token': 'test-refresh',
                'expires_in': 3600,
                'token_type': 'bearer',
                'user': {
                  'id': 'guard',
                  'aud': 'authenticated',
                  'email': 'guard@example.test',
                  'created_at': DateTime.now().toIso8601String(),
                  'app_metadata': {},
                  'user_metadata': {},
                },
              }
            : {};
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final service = AccountPresenceService(client);
    service.start();
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);
    await client.auth.signInWithPassword(
      email: 'guard@example.test',
      password: 'testing-only',
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      calls.where((path) => path.endsWith('/touch_account_presence')).length,
      1,
    );
    await service.heartbeat();
    expect(
      calls.where((path) => path.endsWith('/touch_account_presence')).length,
      2,
    );
    await client.auth.signOut();
    await Future<void>.delayed(Duration.zero);
    await service.heartbeat();
    expect(
      calls.where((path) => path.endsWith('/touch_account_presence')).length,
      2,
    );
    service.dispose();
    await client.dispose();
  });
}
