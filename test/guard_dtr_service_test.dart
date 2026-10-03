import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/models/guard_dtr.dart';
import 'package:flutter_application_1/services/guard_dtr_pdf.dart';
import 'package:flutter_application_1/services/guard_dtr_service.dart';

class SavePicker extends FilePickerPlatform {
  String? name;
  String? mime;
  Uint8List? data;
  bool cancel = false;
  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    name = fileName;
    data = bytes;
    mime = mimeType;
    return cancel ? null : Uri.parse('content://test/dtr.pdf');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'save passes PDF bytes and filename to phone picker and respects cancellation',
    () async {
      final original = FilePickerPlatform.instance;
      final picker = SavePicker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = original);
      final r = GuardDtr(
        period: GuardDtrPeriod(2026, 9, false),
        guardName: 'José Dela Cruz',
        sessions: [],
      );
      expect(await GuardDtrPdf.save(r), true);
      expect(picker.name, r.fileName);
      expect(picker.mime, 'application/pdf');
      expect(ascii.decode(picker.data!.take(5).toList()), '%PDF-');
      picker.cancel = true;
      expect(await GuardDtrPdf.save(r), false);
    },
  );
  test(
    'report queries only signed-in guard and selected cutoff, including paginated records',
    () async {
      final requests = <Uri>[];
      final token =
          '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'guard', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 7200})))}.test';
      final client = SupabaseClient(
        'http://127.0.0.1:1',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
          dynamic body;
          if (r.url.path == '/auth/v1/token') {
            body = {
              'access_token': token,
              'refresh_token': 'test-refresh',
              'expires_in': 7200,
              'token_type': 'bearer',
              'user': {
                'id': 'guard',
                'aud': 'authenticated',
                'email': 'guard@example.test',
                'created_at': '2026-09-01T00:00:00Z',
                'app_metadata': {},
                'user_metadata': {},
              },
            };
          } else if (r.url.path.endsWith('/profiles')) {
            expect(r.url.queryParameters['id'], 'eq.guard');
            body = {
              'first_name': 'Juan',
              'middle_initial': 'D',
              'last_name': 'Dela Cruz',
            };
          } else {
            requests.add(r.url);
            expect(r.url.queryParameters['user_id'], 'eq.guard');
            expect(r.url.queryParametersAll['duty_date'], [
              'gte.2026-09-01',
              'lte.2026-09-15',
            ]);
            final offset = int.parse(r.url.queryParameters['offset']!);
            body = List.generate(
              offset == 0 ? 500 : 1,
              (i) => {
                'id': '${offset + i}',
                'schedule_id': 's',
                'duty_date': '2026-09-13',
                'location_label': 'Post',
                'scheduled_start_at': '2026-09-13T06:00:00+08:00',
                'scheduled_end_at': '2026-09-13T18:00:00+08:00',
                'clock_in_at': '2026-09-13T06:00:00+08:00',
                'clock_out_at': '2026-09-13T18:00:00+08:00',
                'status': 'closed',
              },
            );
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
            request: r,
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        email: 'guard@example.test',
        password: 'test-only',
      );
      final r = await GuardDtrService(
        client,
      ).load(GuardDtrPeriod(2026, 9, false));
      expect(requests.length, 2);
      expect(r.rows.length, 515);
      expect(r.guardName, 'Juan D. Dela Cruz');
      expect(r.totalMinutes, 501 * 720);
    },
  );
  test('signed-out account cannot load a report', () async {
    final client = SupabaseClient(
      'http://127.0.0.1:1',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    await expectLater(
      GuardDtrService(client).load(GuardDtrPeriod(2026, 9, false)),
      throwsStateError,
    );
  });
}
