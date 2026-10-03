import 'package:flutter_application_1/models/attendance_session.dart';
import 'package:flutter_application_1/models/dtr_alignment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DTR cutoff', () {
    test('uses the first semi-monthly period through day 15', () {
      final period = DtrAlignment.cutoffForDutyDate('2026-09-15');

      expect(period?.startDate, '2026-09-01');
      expect(period?.endDate, '2026-09-15');
      expect(period?.label, 'Sep 1–15, 2026');
    });

    test('uses the real month end for the second period', () {
      final period = DtrAlignment.cutoffForDutyDate('2028-02-16');

      expect(period?.startDate, '2028-02-16');
      expect(period?.endDate, '2028-02-29');
      expect(period?.label, 'Feb 16–29, 2028');
      expect(DtrAlignment.cutoffForDutyDate('2026-02-31'), isNull);
    });
  });

  group('scheduled DTR placement', () {
    test('explicit Morning owns noon and late afternoon OUT values', () {
      expect(DtrAlignment.mappingLabel(
        dutyDate: '2026-09-15',
        scheduledStartAt: DateTime.utc(2026, 9, 15, 0),
        scheduledEndAt: DateTime.utc(2026, 9, 15, 4, 15),
        period: 'morning',
      ), 'Morning IN → Morning OUT');
      expect(DtrAlignment.cellLabel(DateTime.utc(2026, 9, 15, 4),
        isTimeIn: false, dutyDate: '2026-09-15'), 'Morning OUT');
      expect(DtrAlignment.cellLabel(DateTime.utc(2026, 9, 15, 4),
        isTimeIn: true, dutyDate: '2026-09-15'), 'Afternoon IN');
    });

    test('next-day overtime remains in original duty cutoff and OT columns', () {
      expect(DtrAlignment.mappingLabel(
        dutyDate: '2026-09-15',
        scheduledStartAt: DateTime.utc(2026, 9, 15, 21),
        scheduledEndAt: DateTime.utc(2026, 9, 15, 23),
        period: 'overtime',
      ), 'Overtime IN (+1) → Overtime OUT (+1)');
      expect(DtrAlignment.cutoffLabel('2026-09-15'), 'Sep 1–15, 2026');
    });

    test('uses Philippine calendar date at UTC boundary', () {
      expect(DtrAlignment.dateString(DateTime.utc(2026, 9, 15, 16)), '2026-09-16');
      expect(DtrAlignment.dateString(DateTime.utc(2026, 9, 15, 15, 59)), '2026-09-15');
      expect(DtrAlignment.normalizePeriod(' OVERTIME '), 'overtime');
      expect(DtrAlignment.normalizePeriod('invalid'), 'auto');
      expect(DtrAlignment.normalizePeriod(null), 'auto');
    });

    test('maps a daytime duty into morning IN and afternoon OUT', () {
      final mapping = DtrAlignment.mappingLabel(
        dutyDate: '2026-09-03',
        scheduledStartAt: DateTime.utc(2026, 9, 3, 0),
        scheduledEndAt: DateTime.utc(2026, 9, 3, 9),
      );

      expect(mapping, 'Morning IN → Afternoon OUT');
    });

    test('keeps an overnight OUT on the original row and marks next day', () {
      final mapping = DtrAlignment.mappingLabel(
        dutyDate: '2026-09-03',
        scheduledStartAt: DateTime.utc(2026, 9, 3, 12),
        scheduledEndAt: DateTime.utc(2026, 9, 3, 21),
      );

      expect(mapping, 'Afternoon IN → Morning OUT (+1)');
    });

    test('actual late punch does not change its scheduled DTR column', () {
      final session = AttendanceSession(
        id: 'session-1',
        scheduleId: 'schedule-1',
        dutyDate: '2026-09-03',
        locationLabel: 'Main Gate',
        scheduledStartAt: DateTime.utc(2026, 9, 3, 0),
        scheduledEndAt: DateTime.utc(2026, 9, 3, 9),
        clockInAt: DateTime.utc(2026, 9, 3, 4, 5),
        clockOutAt: DateTime.utc(2026, 9, 3, 9, 10),
        status: 'closed',
      );

      expect(session.dtrTimeInColumn, 'Morning IN');
      expect(session.dtrTimeOutColumn, 'Afternoon OUT');
      expect(session.dtrMappingLabel, 'Morning IN → Afternoon OUT');
    });
  });
}
