import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/schedule_service.dart';
import 'package:flutter_application_1/widgets/attendance_punch_action.dart';

void main() {
  test(
    'My Schedule excludes approved absences, drafts and reassigned duties',
    () {
      final rows = [
        {'id': 'morning', 'user_id': 'guard', 'approval_status': 'cancelled'},
        {'id': 'afternoon', 'user_id': 'guard', 'approval_status': 'approved'},
        {'id': 'exchange', 'user_id': 'guard', 'approval_status': 'changed'},
        {'id': 'draft', 'user_id': 'guard', 'approval_status': 'draft'},
        {'id': 'other', 'user_id': 'other', 'approval_status': 'approved'},
        {
          'id': 'done',
          'user_id': 'guard',
          'approval_status': 'approved',
          'marked_done': true,
        },
      ];
      expect(
        ScheduleService.visibleSchedules(rows, 'guard').map((r) => r['id']),
        ['afternoon', 'exchange', 'done'],
      );
      expect(
        rows.first['approval_status'],
        'cancelled',
      ); // Audit row is not deleted.
    },
  );
  testWidgets(
    'One button changes from Time In to Time Out using confirmed duty state',
    (tester) async {
      final actions = <String>[];
      Future<void> render(
        bool open, {
        bool loading = false,
        bool busy = false,
        bool enabled = true,
      }) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttendancePunchAction(
              hasOpenDuty: open,
              loading: loading,
              busy: busy,
              enabled: enabled,
              onPunch: actions.add,
              recordedTime: open ? '8:00 AM' : null,
            ),
          ),
        ),
      );
      await render(false);
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.tap(find.text('Time In'));
      expect(actions, ['clock_in']);
      await render(true);
      expect(find.text('Time In'), findsNothing);
      expect(find.text('Time In recorded at 8:00 AM'), findsOneWidget);
      await tester.tap(find.text('Time Out'));
      expect(actions, ['clock_in', 'clock_out']);
      await render(false, loading: true);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await render(true, busy: true);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await render(false, enabled: false);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await render(false);
      expect(find.text('Time In'), findsOneWidget);
    },
  );
}
