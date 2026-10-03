import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/attendance_session.dart';
import 'package:flutter_application_1/services/attendance_state_controller.dart';
import 'package:flutter_application_1/widgets/attendance_actual_times.dart';

AttendanceSession sample({bool closed = false}) => AttendanceSession(
  id: 'session',
  scheduleId: 'night-shift',
  dutyDate: '2026-09-13',
  locationLabel: 'Post',
  locationId: 'original-post',
  scheduledStartAt: DateTime(2026, 9, 13, 18),
  scheduledEndAt: DateTime(2026, 9, 14, 6),
  clockInAt: DateTime(2026, 9, 13, 18, 3),
  clockOutAt: closed ? DateTime(2026, 9, 14, 5, 58) : null,
  status: closed ? 'closed' : 'open',
);
void main() {
  testWidgets(
    'shows actual overnight dates and empty Time Out without DTR mapping',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AttendanceActualTimes(session: sample())),
        ),
      );
      expect(find.text('Actual Time In'), findsOneWidget);
      expect(find.text('Sep 13, 2026 · 6:03 PM'), findsOneWidget);
      expect(find.text('Actual Time Out'), findsOneWidget);
      expect(find.text('Not recorded'), findsOneWidget);
      expect(find.text('DTR'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttendanceActualTimes(session: sample(closed: true)),
          ),
        ),
      );
      expect(find.text('Sep 14, 2026 · 5:58 AM'), findsOneWidget);
      expect(find.text('Not recorded'), findsNothing);
    },
  );
  testWidgets(
    'no attendance never displays scheduled times as actual punches',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AttendanceActualTimes())),
      );
      expect(find.text('Not recorded'), findsNWidgets(2));
    },
  );
  test(
    'closed punches remain visible through refresh without retaining Time Out action',
    () async {
      final pending = Completer<AttendanceSession?>();
      final state = AttendanceStateController(
        loadSession: () => pending.future,
      );
      state.accept(sample());
      final refresh = state.refresh();
      state.accept(sample(closed: true));
      pending.complete(sample());
      await refresh;
      expect(state.session, isNull);
      expect(state.latestSession?.clockOutAt, DateTime(2026, 9, 14, 5, 58));
      state.dispose();
    },
  );
  test('reopening attendance loads the latest completed punches', () async {
    final state = AttendanceStateController(
      loadSession: () async => sample(closed: true),
    );
    await state.refresh();
    expect(state.session, isNull);
    expect(state.latestSession?.isClosed, isTrue);
    state.dispose();
  });
}
