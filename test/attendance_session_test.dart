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
);

void main() {
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
