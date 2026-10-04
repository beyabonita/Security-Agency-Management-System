import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/duty_requests.dart';
import 'package:flutter_application_1/models/accomplishment_photo.dart';
import 'package:flutter_application_1/incident_report.dart';
import 'package:flutter_application_1/widgets/incident_in_app_camera.dart';
import 'package:flutter_application_1/services/incident_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <Map<String, dynamic>>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final token =
        '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'guard', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 7200})))}.test';
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
      httpClient: MockClient((request) async {
        dynamic body = {};
        if (request.url.path == '/auth/v1/token') {
          body = {
            'access_token': token,
            'refresh_token': 'test-refresh',
            'expires_in': 7200,
            'token_type': 'bearer',
            'user': {
              'id': 'guard',
              'aud': 'authenticated',
              'email': 'guard@example.test',
              'created_at': DateTime.now().toIso8601String(),
              'app_metadata': {},
              'user_metadata': {},
            },
          };
        } else if (request.url.path.startsWith('/storage/v1/object/')) {
          calls.add({
            'path': request.url.path,
            'payload': request.url.path.contains('/accomplishment-photos/')
                ? base64Encode(request.bodyBytes)
                : request.body,
          });
          body = {'Key': 'incident-videos/guard/incident.mp4'};
        } else {
          calls.add({
            'path': request.url.path,
            ...jsonDecode(request.body) as Map<String, dynamic>,
          });
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'guard@example.test',
      password: 'test-only',
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(calls.clear);
  testWidgets(
    'short accomplishment entries submit without character minimum prompts',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: AccomplishmentReportScreen(
            scheduleId: 'duty',
            pickPhoto: () async => AccomplishmentPhoto(
              name: 'report.jpg',
              bytes: Uint8List.fromList(
                img.encodeJpg(img.Image(width: 8, height: 8)),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Upload photo report'));
      await tester.pumpAndSettle();
      expect(find.textContaining('characters'), findsNothing);
      await tester.enterText(find.byType(TextField).at(0), 'OK');
      await tester.enterText(find.byType(TextField).at(1), 'Done');
      await tester.ensureVisible(find.text('Submit report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      final reportCall = calls.singleWhere(
        (call) => call['path'] == '/rest/v1/rpc/submit_accomplishment_report',
      );
      expect(reportCall['p_summary'], 'OK');
      expect(reportCall['p_detailed_narrative'], 'Done');
      expect(reportCall['p_photo_path'], startsWith('guard/'));
      expect(reportCall['p_photo_name'], 'report.jpg');
    },
  );
  testWidgets('empty accomplishment text is still required', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccomplishmentReportScreen(
          scheduleId: 'duty',
          pickPhoto: () async => AccomplishmentPhoto(
            name: 'report.jpg',
            bytes: Uint8List.fromList(
              img.encodeJpg(img.Image(width: 8, height: 8)),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Upload photo report'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit report'));
    await tester.pump();
    expect(calls, isEmpty);
    expect(
      find.text('Complete the required summary and detailed narrative.'),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
  });
  test('emergency alert requires a narrative and accepts short text', () async {
    final photo = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 8, height: 8)),
    );
    for (final remarks in ['', '   ']) {
      await expectLater(
        IncidentService.submitReport(
          category: 'other',
          photoBytes: photo,
          capturedAt: DateTime.now().toUtc(),
          remarks: remarks,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('incident narrative'),
          ),
        ),
      );
    }
    expect(calls, isEmpty);
    await IncidentService.submitReport(
      category: 'other',
      photoBytes: photo,
      capturedAt: DateTime.now().toUtc(),
      remarks: 'Help',
    );
    expect(calls.last['p_guard_remarks'], 'Help');
    expect(calls.last['p_category'], 'other');
    expect(IncidentService.categories['other'], 'Emergency');
  });
  test('a narrative does not bypass required evidence', () async {
    await expectLater(
      IncidentService.submitReport(
        category: 'medical',
        photoBytes: Uint8List(0),
        remarks: 'Help',
        capturedAt: DateTime.now().toUtc(),
      ),
      throwsA(isA<Exception>()),
    );
    expect(calls, isEmpty);
  });
  test(
    'video-only alert uploads video without manufacturing a photo',
    () async {
      await IncidentService.submitReport(
        category: 'other',
        remarks: 'Help',
        capturedAt: DateTime.now().toUtc(),
        videoBytes: Uint8List.fromList([1, 2, 3]),
        videoDurationSeconds: 5,
        videoContentType: 'video/mp4',
      );
      final report = calls.last;
      expect(report['p_photo_data'], isNull);
      expect(report['p_video_path'], endsWith('.mp4'));
      expect(report['p_video_duration_seconds'], 5);
      expect(calls.first['payload'], contains(String.fromCharCodes([1, 2, 3])));
    },
  );
  test(
    'video-only alerts still reject invalid duration, stale capture and blank narrative before upload',
    () async {
      for (final input in [
        (duration: 16, captured: DateTime.now().toUtc(), narrative: 'Help'),
        (duration: 5, captured: DateTime.utc(2000), narrative: 'Help'),
        (duration: 5, captured: DateTime.now().toUtc(), narrative: '  '),
      ]) {
        await expectLater(
          IncidentService.submitReport(
            category: 'other',
            remarks: input.narrative,
            capturedAt: input.captured,
            videoBytes: Uint8List.fromList([1, 2, 3]),
            videoDurationSeconds: input.duration,
          ),
          throwsA(isA<Exception>()),
        );
      }
      expect(calls, isEmpty);
    },
  );
  testWidgets(
    'recorded video enables Send; retake discards it and sends only the new recording',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: IncidentReportScreen()));
      await tester.pump();
      expect(find.text('Capture photo or video to continue'), findsOneWidget);
      var camera = tester.widget<IncidentInAppCamera>(
        find.byType(IncidentInAppCamera),
      );
      camera.onVideoCaptured!(
        Uint8List.fromList([1, 2]),
        const Duration(seconds: 4),
        'video/mp4',
      );
      await tester.pumpAndSettle();
      expect(find.text('Video ready'), findsOneWidget);
      expect(find.byType(IncidentInAppCamera), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send emergency alert'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Retake video'));
      await tester.pump();
      expect(find.text('Video ready'), findsNothing);
      expect(find.text('Capture photo or video to continue'), findsOneWidget);
      camera = tester.widget<IncidentInAppCamera>(
        find.byType(IncidentInAppCamera),
      );
      camera.onVideoCaptured!(
        Uint8List.fromList([3, 4]),
        const Duration(seconds: 7),
        'video/mp4',
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Need assistance');
      await tester.tap(find.text('Send emergency alert'));
      await tester.pumpAndSettle();
      expect(calls.first['payload'], contains(String.fromCharCodes([3, 4])));
      expect(
        calls.first['payload'],
        isNot(contains(String.fromCharCodes([1, 2]))),
      );
      expect(calls.last['p_photo_data'], isNull);
      expect(calls.last['p_video_duration_seconds'], 7);
    },
  );
}
