import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/services/attendance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var response = <String, dynamic>{};
  var status = 200;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/v1/attendance_sessions');
        return http.Response(
          jsonEncode(response),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    status = 200;
    response = {
      'id': 'session',
      'schedule_id': 'duty',
      'duty_date': '2026-09-08',
      'scheduled_start_at': '2026-09-08T00:00:00Z',
      'scheduled_end_at': '2026-09-08T08:00:00Z',
      'clock_in_at': '2026-09-08T00:05:00Z',
      'status': 'open',
    };
  });
  test(
    'attendance becomes ready from REST without a realtime connection',
    () async {
      final session = await AttendanceService.openSessionStream(
        'guard',
      ).first.timeout(const Duration(seconds: 2));
      expect(session?.id, 'session');
      expect(Supabase.instance.client.getChannels(), isEmpty);
    },
  );
  test('repeated attendance refreshes each get confirmed data', () async {
    for (var i = 0; i < 3; i++) {
      final session = await AttendanceService.openSessionStream(
        'guard',
      ).first.timeout(const Duration(seconds: 2));
      expect(session?.isOpen, isTrue);
    }
  });
  test(
    'failed attendance fetch exposes a retryable error instead of waiting',
    () async {
      status = 400;
      response = {'message': 'Attendance unavailable', 'code': 'TEST'};
      await expectLater(
        AttendanceService.openSessionStream('guard').first,
        throwsA(isA<PostgrestException>()),
      );
    },
  );
  test(
    'latest attendance restores both recorded punches after screen reopening',
    () async {
      response['status'] = 'closed';
      response['clock_out_at'] = '2026-09-08T08:00:00Z';
      response['location_id'] = 'original-post';
      final session = await AttendanceService.latestSessionStream(
        'guard',
      ).first;
      expect(session?.isClosed, isTrue);
      expect(session?.locationId, 'original-post');
      expect(session?.clockOutAt?.toUtc(), DateTime.utc(2026, 9, 8, 8));
    },
  );
}
