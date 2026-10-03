import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/attendance_session.dart';
import 'package:flutter_application_1/services/attendance_service.dart';
import 'package:flutter_application_1/services/schedule_service.dart';

AttendanceSession session(DateTime end, {String status = 'open'}) =>
    AttendanceSession(
      id: 'old-session',
      scheduleId: 'old-duty',
      dutyDate: '2026-09-08',
      locationLabel: 'Gate',
      scheduledStartAt: end.subtract(const Duration(hours: 8)),
      scheduledEndAt: end,
      clockInAt: end.subtract(const Duration(hours: 8)),
      status: status,
    );

void main() {
  test(
    'ended overnight duty yields to the next duty without inventing Time Out',
    () {
      final end = DateTime.utc(2026, 9, 8, 2);
      final old = session(end);
      expect(old.isActiveAt(end.subtract(const Duration(seconds: 1))), isTrue);
      expect(old.isActiveAt(end), isFalse);
      expect(old.isMissingTimeOutAt(end), isTrue);
      expect(
        AttendanceService.sessionForDuty(old, 'new-duty', now: end),
        isNull,
      );
      expect(old.clockOutAt, isNull);
      expect(old.workedDuration, Duration.zero);
    },
  );

  test('an unended duty still blocks the next schedule', () {
    final now = DateTime.now();
    final active = session(now.add(const Duration(hours: 1)));
    expect(
      AttendanceService.sessionForDuty(active, 'new-duty', now: now),
      active,
    );
    expect(
      AttendanceService.blockReasonForAction('clock_in', active),
      isNotNull,
    );
  });

  test('late Time Out remains available for an explicit overtime choice', () {
    final now = DateTime.now();
    final ended = session(now.subtract(const Duration(minutes: 1)));
    expect(AttendanceService.sessionForDuty(ended, null, now: now), ended);
    expect(AttendanceService.blockReasonForAction('clock_out', ended), isNull);
    expect(AttendanceService.blockReasonForAction('clock_in', ended), isNull);
    expect(
      AttendanceService.blockReasonForAction('clock_out', null),
      isNotNull,
    );
  });

  test(
    'rolled over record stays incomplete and cannot become an open duty',
    () {
      final now = DateTime.now();
      final missed = session(now, status: 'missed_timeout');
      expect(missed.isMissingTimeOutAt(now), isTrue);
      expect(missed.isClosed, isFalse);
      expect(AttendanceService.sessionForDuty(missed, null, now: now), isNull);
    },
  );

  test('ended and completed schedules cannot remain the primary schedule', () {
    final now = DateTime.now();
    final context = AttendanceDutyContext(
      schedules: [
        {
          'id': 'ended',
          'end_at': now.subtract(const Duration(seconds: 1)).toIso8601String(),
        },
        {
          'id': 'done',
          'end_at': now.add(const Duration(hours: 1)).toIso8601String(),
          'marked_done': true,
        },
        {
          'id': 'next',
          'end_at': now.add(const Duration(hours: 2)).toIso8601String(),
        },
      ],
      sites: [],
    );
    expect(context.primarySchedule?['id'], 'next');
    expect(
      AttendanceDutyContext(
        schedules: [context.schedules.first],
        sites: [],
      ).primarySchedule,
      isNull,
    );
  });

  test(
    'duty log refreshes at shift end even without a database change',
    () async {
      final source = StreamController<List<AttendanceSession>>();
      final ended = Completer<void>();
      final old = session(DateTime.now().add(const Duration(milliseconds: 80)));
      var events = 0;
      final subscription = AttendanceService.refreshAtShiftEnd(source.stream)
          .listen((rows) {
            events++;
            if (events == 2) {
              expect(rows.single.isMissingTimeOutAt(DateTime.now()), isTrue);
              ended.complete();
            }
          });
      source.add([old]);
      await ended.future.timeout(const Duration(seconds: 3));
      await subscription.cancel();
      await source.close();
      expect(events, 2);
    },
  );
}
