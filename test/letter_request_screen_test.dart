import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/letter_request.dart';
import 'package:flutter_application_1/models/request_letter.dart';
import 'package:flutter_application_1/services/duty_request_service.dart';

final duty = <String, dynamic>{
  'id': 'schedule-1',
  'start_at': '2026-09-06T00:00:00Z',
  'end_at': '2026-09-06T04:00:00Z',
  'duty_date': '2026-09-06',
  'dtr_period': 'morning',
  'location_label': 'Agency branch',
};

class FakeGateway implements DutyRequestGateway {
  @override
  Future<void> respondToSwap(String requestId, bool approve) async {
    responses.add({'id': requestId, 'approve': approve});
    requests = requests
        .map(
          (r) => {
            ...r,
            'guard_response': approve ? 'approved' : 'declined',
            'status': approve ? 'pending_admin' : 'rejected',
          },
        )
        .toList();
  }

  final responses = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> schedules = [duty];
  List<Map<String, dynamic>> requests = [];
  final submissions = <Map<String, dynamic>>[];
  Object? submitError;
  Object? loadError;
  Object? swapError;
  List<Map<String, dynamic>> options = [
    {
      ...duty,
      'id': 'schedule-2',
      'guard_name': 'Other Guard',
      'location_label': 'Other post',
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> swapOptions(String scheduleId) async {
    if (swapError != null) throw swapError!;
    return options;
  }

  @override
  Future<DutyRequestData> load() async {
    if (loadError != null) throw loadError!;
    return DutyRequestData(schedules: schedules, requests: requests);
  }

  @override
  Future<void> submit({
    required String scheduleId,
    required String reason,
    required String requestType,
    required RequestLetter letter,
    String? targetScheduleId,
  }) async {
    submissions.add({
      'schedule': scheduleId,
      'reason': reason,
      'type': requestType,
      'letter': letter,
      'target': targetScheduleId,
    });
    if (submitError != null) throw submitError!;
    requests = [
      {
        'requested_schedule_id': scheduleId,
        'request_type': requestType,
        'reason': reason,
        'letter_name': letter.name,
        'status': 'pending_admin',
      },
    ];
  }

  @override
  Future<void> discard(RequestLetter letter) async {}
}

RequestLetter attachment() => RequestLetter(
  name: 'absence.pdf',
  bytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
);

Future<void> render(
  WidgetTester tester,
  FakeGateway gateway, {
  Future<RequestLetter?> Function()? pick,
  double width = 430,
}) async {
  tester.view.physicalSize = Size(width, 1300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: ShiftChangeRequestScreen(
        gateway: gateway,
        pickLetter: pick ?? () async => attachment(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String label) async {
  final finder = find.text(label).last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> chooseDuty(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('2026-09-06 · Morning').last);
  await tester.pumpAndSettle();
}

void main() {
  for (final approve in [true, false]) {
    testWidgets(
      'Incoming swap can be ${approve ? 'approved' : 'declined'} by the selected Guard',
      (tester) async {
        final gateway = FakeGateway()
          ..schedules = []
          ..requests = [
            {
              'id': 'invitation',
              'is_incoming': true,
              'request_type': 'swap',
              'status': 'pending_admin',
              'guard_response': 'pending',
              'reason': 'Exchange duties',
              'exchange_snapshot': {
                'requester_name': 'Juan',
                'target_name': 'Maria',
                'offered': duty,
                'requested': {...duty, 'location_label': 'Other post'},
              },
            },
          ];
        await render(tester, gateway);
        await tapText(tester, approve ? 'Approve swap' : 'Decline swap');
        await tapText(tester, approve ? 'Accept swap' : 'Decline swap');
        expect(gateway.responses, [
          {'id': 'invitation', 'approve': approve},
        ]);
        expect(
          find.textContaining(
            approve
                ? 'Awaiting Operational Head approval'
                : 'Declined by Guard',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('attendance relation accepts current and legacy Supabase shapes', () {
    expect(scheduleHasAttendance(null), isFalse);
    expect(scheduleHasAttendance(<String, dynamic>{}), isFalse);
    expect(scheduleHasAttendance({'id': 'session-1'}), isTrue);
    expect(scheduleHasAttendance(<dynamic>[]), isFalse);
    expect(
      scheduleHasAttendance(<dynamic>[
        {'id': 'session-1'},
      ]),
      isTrue,
    );
  });

  test('load failures never use the submission error message', () {
    expect(
      dutyRequestLoadErrorMessage(Exception('offline')),
      contains('Could not load'),
    );
    expect(
      dutyRequestLoadErrorMessage(Exception('offline')),
      isNot(contains('confirm submission')),
    );
  });

  testWidgets('Letter form fits a narrow phone after selecting a duty', (
    tester,
  ) async {
    await render(tester, FakeGateway(), width: 320);
    await chooseDuty(tester);
    await tapText(tester, 'Attach request letter');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Absence form remains visible without schedules, with safe disabled submission',
    (tester) async {
      final gateway = FakeGateway()..schedules = [];
      await render(tester, gateway);
      expect(find.text('Absent'), findsOneWidget);
      expect(
        find.textContaining('Choose a duty scheduled today'),
        findsOneWidget,
      );
      expect(find.text('Attach request letter'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(gateway.submissions, isEmpty);
    },
  );
  testWidgets(
    'Guard can attach an absence letter and send selected period to Operational Head',
    (tester) async {
      final gateway = FakeGateway();
      await render(tester, gateway);
      await chooseDuty(tester);
      expect(find.textContaining('8:00 AM–12:00 PM'), findsWidgets);
      await tester.enterText(
        find.byType(TextField),
        'Medical appointment for morning duty.',
      );
      await tapText(tester, 'Attach request letter');
      expect(find.text('absence.pdf'), findsOneWidget);
      await tapText(tester, 'Send to Operations Head');
      expect(gateway.submissions.single['type'], 'absence');
      expect(gateway.submissions.single['schedule'], 'schedule-1');
      expect(gateway.requests.single['status'], 'pending_admin');
      expect(
        find.text('Request and letter sent to Operations Head.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'All available duties already have a pending request',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Swap selection preserves its request type and attachment', (
    tester,
  ) async {
    final gateway = FakeGateway();
    await render(tester, gateway);
    await tapText(tester, 'Swap Duty');
    await chooseDuty(tester);
    await tester.enterText(
      find.byType(TextField),
      'Please arrange another guard to cover this period.',
    );
    await tapText(tester, 'Attach request letter');
    await tester.ensureVisible(
      find.byType(DropdownButtonFormField<String>).last,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other Guard').last);
    await tester.pumpAndSettle();
    await tapText(tester, 'Send to selected Guard');
    expect(gateway.submissions.single['type'], 'swap');
    expect(gateway.submissions.single['target'], 'schedule-2');
    expect(gateway.submissions.single['letter'], isA<RequestLetter>());
  });
  testWidgets(
    'Timed-in Guard can request replacement without an exchange target',
    (tester) async {
      final gateway = FakeGateway()
        ..schedules = [
          {
            ...duty,
            'attendance_sessions': {'id': 'open-session', 'status': 'open'},
          },
        ]
        ..options = [];
      await render(tester, gateway);
      await chooseDuty(tester);
      await tapText(tester, 'Swap Duty');
      expect(find.text('Request a replacement Guard'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'Feeling unwell and need someone to relieve me.',
      );
      await tapText(tester, 'Attach request letter');
      await tapText(tester, 'Send to Operations Head');
      expect(gateway.submissions.single['type'], 'swap');
      expect(gateway.submissions.single['target'], isNull);
    },
  );
  testWidgets(
    'Swap requires a peer duty and remains usable when none are available',
    (tester) async {
      final gateway = FakeGateway()..options = [];
      await render(tester, gateway, width: 320);
      await tapText(tester, 'Swap Duty');
      await chooseDuty(tester);
      expect(find.textContaining('No eligible duties to swap'), findsOneWidget);
      await tapText(tester, 'Attach request letter');
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.text('absence.pdf'), findsOneWidget);
      expect(gateway.submissions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Swap picker retry retains the attachment and absence does not need a peer',
    (tester) async {
      final gateway = FakeGateway()..swapError = Exception('offline');
      await render(tester, gateway);
      await chooseDuty(tester);
      await tapText(tester, 'Attach request letter');
      await tapText(tester, 'Swap Duty');
      expect(
        find.textContaining('Could not load other Guards'),
        findsOneWidget,
      );
      gateway.swapError = null;
      await tapText(tester, 'Retry swap options');
      expect(find.text('absence.pdf'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
      await tapText(tester, 'Absent');
      await tester.enterText(find.byType(TextField), 'Family appointment.');
      await tapText(tester, 'Send to Operations Head');
      expect(gateway.submissions.single['type'], 'absence');
      expect(gateway.submissions.single['target'], isNull);
    },
  );
  testWidgets('Missing letter is rejected without calling submission', (
    tester,
  ) async {
    final gateway = FakeGateway();
    await render(tester, gateway);
    await chooseDuty(tester);
    await tester.enterText(find.byType(TextField), 'Medical appointment.');
    await tapText(tester, 'Send to Operations Head');
    expect(gateway.submissions, isEmpty);
    expect(
      find.text('Choose a duty, enter a reason, and attach your letter.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'Upload denial shows actionable error and retains attachment for retry',
    (tester) async {
      final gateway = FakeGateway()
        ..submitError = const StorageException('Denied', statusCode: '403');
      await render(tester, gateway);
      await chooseDuty(tester);
      await tester.enterText(find.byType(TextField), 'Medical appointment.');
      await tapText(tester, 'Attach request letter');
      await tapText(tester, 'Send to Operations Head');
      expect(
        find.textContaining('The letter upload was denied'),
        findsOneWidget,
      );
      expect(find.text('absence.pdf'), findsOneWidget);
      final first = gateway.submissions.single['letter'];
      gateway.submitError = null;
      await tapText(tester, 'Send to Operations Head');
      expect(gateway.submissions.last['letter'], same(first));
      expect(gateway.requests.single['status'], 'pending_admin');
    },
  );
  testWidgets('Cancelling replacement keeps previously attached file', (
    tester,
  ) async {
    final gateway = FakeGateway();
    var picks = 0;
    await render(
      tester,
      gateway,
      pick: () async => ++picks == 1 ? attachment() : null,
    );
    await tapText(tester, 'Attach request letter');
    await tapText(tester, 'Replace letter');
    expect(find.text('absence.pdf'), findsOneWidget);
    expect(gateway.submissions, isEmpty);
  });
  testWidgets('Picker validation is shown without erasing the request reason', (
    tester,
  ) async {
    final gateway = FakeGateway();
    await render(
      tester,
      gateway,
      pick: () async =>
          throw const FormatException('The letter must be 5 MB or smaller.'),
    );
    await tester.enterText(find.byType(TextField), 'Medical appointment.');
    await tapText(tester, 'Attach request letter');
    expect(find.text('The letter must be 5 MB or smaller.'), findsOneWidget);
    expect(find.text('Medical appointment.'), findsOneWidget);
  });
}
