import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/attendance_session.dart';
import 'package:flutter_application_1/models/guard_dtr.dart';
import 'package:flutter_application_1/widgets/overtime_timeout_dialog.dart';
import 'package:flutter_application_1/widgets/attendance_actual_times.dart';

AttendanceSession sample({bool claim = true, bool approved = false}) =>
    AttendanceSession.fromRow({
      'id': 'session',
      'schedule_id': 'shift',
      'duty_date': '2026-09-13',
      'location_label': 'Post',
      'status': 'closed',
      'scheduled_start_at': '2026-09-13T06:00:00+08:00',
      'scheduled_end_at': '2026-09-13T18:00:00+08:00',
      'clock_in_at': '2026-09-13T06:00:00+08:00',
      'clock_out_at': claim
          ? '2026-09-13T20:00:00+08:00'
          : '2026-09-13T18:00:00+08:00',
      'timeout_submitted_at': claim
          ? '2026-09-13T20:00:00+08:00'
          : '2026-09-13T18:03:00+08:00',
      'overtime_requested': claim,
      'timeout_verified_at': approved ? '2026-09-14T06:00:00+08:00' : null,
    });
void main() {
  test(
    '2-hour overtime waits for approval before Time Out and hours appear',
    () {
      final pending = GuardDtr(
        period: GuardDtrPeriod(2026, 9, false),
        guardName: 'Guard',
        sessions: [sample()],
      );
      final row = pending.rows[12];
      expect(row[3], '');
      expect(row[4], '');
      expect(row[5], '');
      expect(pending.totalMinutes, 0);
      final approved = GuardDtr(
        period: GuardDtrPeriod(2026, 9, false),
        guardName: 'Guard',
        sessions: [sample(approved: true)],
      );
      expect(approved.rows[12].sublist(3), ['8:00 PM', '2:00', '14:00']);
      expect(approved.totalMinutes, 840);
      expect(approved.overtimeMinutes, 120);
    },
  );
  test(
    'no overtime uses 6 PM and 12 hours without review, preserving 6:03 PM submission',
    () {
      final s = sample(claim: false);
      expect(s.needsTimeoutReview, false);
      expect(s.timeoutSubmittedAt!.isAfter(s.clockOutAt!), true);
      final r = GuardDtr(
        period: GuardDtrPeriod(2026, 9, false),
        guardName: 'Guard',
        sessions: [s],
      );
      expect(r.rows[12].sublist(3), ['6:00 PM', '0:00', '12:00']);
      expect(r.notes, isEmpty);
    },
  );
  for (final choice in {
    'Yes, request approval': true,
    'No, use scheduled end': false,
    'Cancel': null,
  }.entries) {
    testWidgets('overtime dialog: ${choice.key}', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool? answer;
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  answer = await askOvertimeTimeout(context, '6:00 PM');
                  completed = true;
                },
                child: const Text('Time Out'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Time Out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice.key));
      await tester.pumpAndSettle();
      expect(completed, true);
      expect(answer, choice.value);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'guard sees actual submission separately from scheduled DTR end',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttendanceActualTimes(session: sample(claim: false)),
          ),
        ),
      );
      expect(find.textContaining('No overtime requested'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AttendanceActualTimes(session: sample())),
        ),
      );
      expect(
        find.text('Overtime awaiting Operations Head approval'),
        findsOneWidget,
      );
    },
  );
}
