import 'package:flutter_application_1/models/attendance_session.dart';
import 'package:flutter_test/flutter_test.dart';

AttendanceSession buildSession({
  DateTime? scheduledStart,
  DateTime? scheduledEnd,
  DateTime? clockIn,
  DateTime? clockOut,
  String status = 'closed',
}) => AttendanceSession(
  id: 'session-1',
  scheduleId: 'schedule-1',
  dutyDate: '2026-08-22',
  locationLabel: 'North Gate',
  scheduledStartAt: scheduledStart ?? DateTime.utc(2026, 8, 22, 14),
  scheduledEndAt: scheduledEnd ?? DateTime.utc(2026, 8, 22, 22),
  clockInAt: clockIn ?? DateTime.utc(2026, 8, 22, 14, 10),
  clockOutAt: clockOut ?? DateTime.utc(2026, 8, 22, 22, 5),
  status: status,
  timeoutVerifiedAt: DateTime.utc(2026, 8, 23),
);

void main() {
  test('unverified next-day checkout does not count 24 hours', () {
    final row = <String, dynamic>{
      'id': 'late',
      'schedule_id': 'old',
      'duty_date': '2026-09-08',
      'scheduled_start_at': '2026-09-08T00:00:00Z',
      'scheduled_end_at': '2026-09-08T12:00:00Z',
      'clock_in_at': '2026-09-08T00:00:00Z',
      'clock_out_at': '2026-09-09T00:00:00Z',
      'status': 'closed',
    };
    final pending = AttendanceSession.fromRow(row);
    expect(pending.needsTimeoutReview, isTrue);
    expect(pending.clockOutAt, isNotNull);
    expect(pending.workedDuration, Duration.zero);
    row['clock_out_at'] = '2026-09-08T12:00:00Z';
    row['timeout_verified_at'] = '2026-09-09T01:00:00Z';
    final verified = AttendanceSession.fromRow(row);
    expect(verified.needsTimeoutReview, isFalse);
    expect(verified.workedDuration, const Duration(hours: 12));
    expect(verified.timeoutVerifiedAt, isNotNull);
  });
  test(
    'parses snapshotted DTR period without substituting actual punch columns',
    () {
      final session = AttendanceSession.fromRow({
        'id': 'split-1',
        'schedule_id': 'morning-1',
        'duty_date': '2026-09-15',
        'dtr_period': 'morning',
        'location_label': 'Main Gate',
        'scheduled_start_at': '2026-09-15T00:00:00Z',
        'scheduled_end_at': '2026-09-15T04:00:00Z',
        'clock_in_at': '2026-09-15T00:05:00Z',
        'clock_out_at': '2026-09-15T04:15:00Z',
        'status': 'closed',
        'timeout_verified_at': '2026-09-16T00:00:00Z',
      });
      expect(session.dtrPeriod, 'morning');
      expect(session.dtrMappingLabel, 'Morning IN → Morning OUT');
      expect(session.workedDuration, const Duration(hours: 4, minutes: 10));
      expect(session.lateDuration, const Duration(minutes: 5));
      expect(session.undertimeDuration, Duration.zero);
    },
  );

  test('next-day overtime keeps the originating DTR date', () {
    final session = AttendanceSession.fromRow({
      'id': 'ot-1',
      'schedule_id': 'ot-schedule',
      'duty_date': '2026-09-15',
      'dtr_period': 'overtime',
      'location_label': 'Main Gate',
      'scheduled_start_at': '2026-09-15T21:00:00Z',
      'scheduled_end_at': '2026-09-15T23:00:00Z',
      'clock_in_at': '2026-09-15T21:01:00Z',
      'clock_out_at': '2026-09-15T23:01:00Z',
      'status': 'closed',
      'timeout_verified_at': '2026-09-16T00:00:00Z',
    });
    expect(session.dutyDate, '2026-09-15');
    expect(session.dtrCutoffLabel, 'Sep 1–15, 2026');
    expect(session.dtrMappingLabel, 'Overtime IN (+1) → Overtime OUT (+1)');
    expect(session.workedDuration, const Duration(hours: 2));
  });

  test(
    'invalid required attendance timestamps fail instead of inventing punches',
    () {
      expect(
        () => AttendanceSession.fromRow({'id': 'invalid'}),
        throwsFormatException,
      );
    },
  );

  test('keeps an overnight duty as one session', () {
    final session = buildSession();

    expect(session.workedDuration, const Duration(hours: 7, minutes: 55));
    expect(session.lateDuration, const Duration(minutes: 10));
    expect(session.undertimeDuration, Duration.zero);
    expect(session.isClosed, isTrue);
  });

  test('reports undertime from the scheduled shift end', () {
    final session = buildSession(clockOut: DateTime.utc(2026, 8, 22, 21, 20));

    expect(session.undertimeDuration, const Duration(minutes: 40));
  });

  test('parses server rows and leaves an open session without a Time Out', () {
    final session = AttendanceSession.fromRow({
      'id': 'session-2',
      'schedule_id': 'schedule-2',
      'duty_date': '2026-08-22',
      'location_label': 'South Gate',
      'scheduled_start_at': '2026-08-22T14:00:00Z',
      'scheduled_end_at': '2026-08-22T22:00:00Z',
      'clock_in_at': '2026-08-22T14:00:00Z',
      'clock_out_at': null,
      'status': 'open',
    });

    expect(session.isOpen, isTrue);
    expect(session.clockOutAt, isNull);
    expect(session.workedDuration, Duration.zero);
  });
}
