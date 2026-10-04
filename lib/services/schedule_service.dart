import 'package:flutter_application_1/models/dtr_alignment.dart';
import 'package:flutter_application_1/models/geofence_site.dart';
import 'package:flutter_application_1/services/geofence_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AttendanceDutyContext {
  const AttendanceDutyContext({required this.schedules, required this.sites});

  final List<Map<String, dynamic>> schedules;
  final List<GeofenceSite> sites;

  Map<String, dynamic>? get primarySchedule {
    for (final schedule in schedules) {
      if (!ScheduleService.isMarkedDone(schedule) &&
          !ScheduleService.isScheduleEnded(schedule)) {
        return schedule;
      }
    }
    return null;
  }
}

class ScheduleService {
  static final _schedules = Supabase.instance.client.from('schedules');

  static bool canSubmitAccomplishment(Map<String, dynamic> schedule) {
    if (!const ['approved', 'changed'].contains(schedule['approval_status'])) {
      return false;
    }
    final raw = schedule['attendance_sessions'];
    final sessions = raw is List
        ? raw
        : raw is Map
        ? [raw]
        : const [];
    return sessions.any(
      (session) =>
          session is Map &&
          session['clock_in_at'] != null &&
          const ['open', 'closed'].contains(session['status']),
    );
  }

  /// Cancelled duties remain in the audit trail, never in a Guard's duty list.
  static List<Map<String, dynamic>> visibleSchedules(
    Iterable<Map<String, dynamic>> rows,
    String userId,
  ) => rows
      .where(
        (row) =>
            row['user_id'] == userId &&
            const ['approved', 'changed'].contains(row['approval_status']),
      )
      .toList();

  static DateTime? _parseTime(dynamic value) {
    if (value is DateTime) return value.toLocal();
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }

  static DateTime? scheduleStartAt(Map<String, dynamic>? schedule) =>
      schedule == null ? null : _parseTime(schedule['start_at']);

  static DateTime? scheduleEndAt(Map<String, dynamic>? schedule) =>
      schedule == null ? null : _parseTime(schedule['end_at']);

  static String? scheduleDutyDate(Map<String, dynamic>? schedule) {
    if (schedule == null) return null;
    for (final key in ['duty_date', 'date']) {
      final stored = schedule[key]?.toString();
      if (stored != null && DtrAlignment.cutoffForDutyDate(stored) != null) {
        return stored;
      }
    }
    final start = scheduleStartAt(schedule);
    return start == null ? null : DtrAlignment.dateString(start);
  }

  static String? dtrCutoffLabel(Map<String, dynamic>? schedule) {
    final dutyDate = scheduleDutyDate(schedule);
    return dutyDate == null ? null : DtrAlignment.cutoffLabel(dutyDate);
  }

  static String? dtrTimeInColumn(Map<String, dynamic>? schedule) {
    final dutyDate = scheduleDutyDate(schedule);
    final start = scheduleStartAt(schedule);
    if (dutyDate == null || start == null) return null;
    return DtrAlignment.cellLabel(
      start,
      isTimeIn: true,
      dutyDate: dutyDate,
      period: schedule?['dtr_period']?.toString() ?? 'auto',
    );
  }

  static String? dtrTimeOutColumn(Map<String, dynamic>? schedule) {
    final dutyDate = scheduleDutyDate(schedule);
    final end = scheduleEndAt(schedule);
    if (dutyDate == null || end == null) return null;
    return DtrAlignment.cellLabel(
      end,
      isTimeIn: false,
      dutyDate: dutyDate,
      period: schedule?['dtr_period']?.toString() ?? 'auto',
    );
  }

  static String? dtrMappingLabel(Map<String, dynamic>? schedule) {
    final timeIn = dtrTimeInColumn(schedule);
    final timeOut = dtrTimeOutColumn(schedule);
    return timeIn == null || timeOut == null ? null : '$timeIn → $timeOut';
  }

  static Future<List<Map<String, dynamic>>> schedulesForUserOnDay(
    String userId, {
    DateTime? on,
  }) async {
    final day = on ?? DateTime.now();
    final start = DateTime(day.year, day.month, day.day).toUtc();
    final end = start.add(const Duration(days: 1));
    final rows = await _schedules
        .select()
        .eq('user_id', userId)
        .inFilter('approval_status', ['approved', 'changed'])
        .lt('start_at', end.toIso8601String())
        .gt('end_at', start.toIso8601String());
    return rows;
  }

  static List<String> locationIdsFromSchedules(
    List<Map<String, dynamic>> schedules,
  ) => schedules
      .map((schedule) => schedule['location_id']?.toString())
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();

  /// Returns the sites a guard may need for attendance. The server is still
  /// authoritative; this window only lets the app show the relevant geofence
  /// before a shift begins and after an overnight shift crosses midnight.
  static Future<AttendanceDutyContext> loadAttendanceContext(
    String userId,
  ) async {
    final now = DateTime.now();
    final windowStart = now.subtract(const Duration(hours: 14)).toUtc();
    final windowEnd = now.add(const Duration(hours: 14)).toUtc();
    final schedules = await _schedules
        .select()
        .eq('user_id', userId)
        .inFilter('approval_status', ['approved', 'changed'])
        .lt('start_at', windowEnd.toIso8601String())
        .gt('end_at', windowStart.toIso8601String())
        .timeout(const Duration(seconds: 15));
    final attendanceSchedules =
        schedules.where((schedule) {
          final start = _parseTime(schedule['start_at']);
          final end = _parseTime(schedule['end_at']);
          return start != null &&
              end != null &&
              !isMarkedDone(schedule) &&
              !now.isBefore(start.subtract(const Duration(hours: 2))) &&
              now.isBefore(end);
        }).toList()..sort((left, right) {
          int rank(Map<String, dynamic> schedule) {
            if (isMarkedDone(schedule)) return 3;
            final start = _parseTime(schedule['start_at']);
            final end = _parseTime(schedule['end_at']);
            if (start == null || end == null) return 4;
            if (!now.isBefore(start.subtract(const Duration(hours: 2))) &&
                !now.isAfter(end)) {
              return 0;
            }
            if (now.isBefore(start)) return 1;
            return 2;
          }

          final rankComparison = rank(left).compareTo(rank(right));
          if (rankComparison != 0) return rankComparison;
          final leftStart = _parseTime(left['start_at']);
          final rightStart = _parseTime(right['start_at']);
          if (leftStart == null || rightStart == null) return 0;
          return leftStart.compareTo(rightStart);
        });
    final sites = await GeofenceService.loadSitesForUser(
      locationIdsFromSchedules(attendanceSchedules),
    );
    return AttendanceDutyContext(schedules: attendanceSchedules, sites: sites);
  }

  static Future<List<GeofenceSite>> loadAttendanceSites(String userId) async =>
      (await loadAttendanceContext(userId)).sites;

  @Deprecated('Use loadAttendanceSites for schedule-linked Time In/Out.')
  static Future<List<GeofenceSite>> loadCurrentDutySites(String userId) =>
      loadAttendanceSites(userId);

  static bool isMarkedDone(Map<String, dynamic> data) =>
      data['marked_done'] == true;

  static bool isScheduleEnded(Map<String, dynamic> data, [DateTime? when]) {
    final end = _parseTime(data['end_at']);
    return end != null && !(when ?? DateTime.now()).isBefore(end);
  }
}
