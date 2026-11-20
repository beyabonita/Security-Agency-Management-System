import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/homepage.dart';
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

  testWidgets(
    'GuardScheduleCalendarScreen shows monthly pills and Submit Accomplishment Report on accomplished shift',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      String keyFor(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final todayKey = keyFor(now);
      final otherDay = DateTime(now.year, now.month, now.day == 15 ? 14 : 15);
      final otherKey = keyFor(otherDay);
      final otherNextKey = keyFor(otherDay.add(const Duration(days: 1)));

      final schedules = [
        {
          'id': 'sched-done-1',
          'user_id': 'guard-1',
          'duty_date': todayKey,
          'start_at': '${todayKey}T06:00:00+08:00',
          'end_at': '${todayKey}T18:00:00+08:00',
          'location_label': 'Water District',
          'location_address': 'Silay City',
          'approval_status': 'approved',
          'marked_done': false,
          'attendance_sessions': [
            {
              'status': 'closed',
              'clock_in_at': '${todayKey}T05:59:00+08:00',
              'clock_out_at': '${todayKey}T18:01:00+08:00',
            },
          ],
        },
        {
          'id': 'sched-upcoming-2',
          'user_id': 'guard-1',
          'duty_date': otherKey,
          'start_at': '${otherKey}T18:00:00+08:00',
          'end_at': '${otherNextKey}T06:00:00+08:00',
          'location_label': 'Water District',
          'approval_status': 'approved',
          'marked_done': false,
          'attendance_sessions': <Map<String, dynamic>>[],
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: GuardScheduleCalendarScreen(
            userId: 'guard-1',
            initialSchedules: schedules,
            subscribeRealtime: false,
            loadSchedules: () async => schedules,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify weekday headers and shift pills on calendar grid
      expect(find.text('Sun'), findsOneWidget);
      expect(find.text('Sat'), findsOneWidget);
      expect(find.text('6A–6P'), findsOneWidget);
      expect(find.text('6P–6A'), findsOneWidget);

      // Tap accomplished shift date -> shows Submit Accomplishment Report button
      await tester.tap(find.byKey(ValueKey('calendarDayCell_$todayKey')));
      await tester.pumpAndSettle();
      expect(find.text('Morning / Day'), findsWidgets);
      expect(
        find.byKey(const ValueKey('submitAccomplishmentButton_sched-done-1')),
        findsOneWidget,
      );
      expect(find.text('Submit Accomplishment Report'), findsOneWidget);

      // Close bottom sheet
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // Tap non-clocked shift date -> no Submit Accomplishment Report button
      await tester.tap(find.byKey(ValueKey('calendarDayCell_$otherKey')));
      await tester.pumpAndSettle();
      expect(find.text('Submit Accomplishment Report'), findsNothing);
      expect(
        find.byKey(const ValueKey('submitAccomplishmentButton_sched-upcoming-2')),
        findsNothing,
      );
    },
  );
}
