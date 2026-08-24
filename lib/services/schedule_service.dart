import 'package:flutter_application_1/models/geofence_site.dart';
import 'package:flutter_application_1/services/geofence_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ScheduleService {
  static final _schedules = Supabase.instance.client.from('schedules');

  static DateTime? _parseTime(dynamic value) {
    if (value is DateTime) return value.toLocal();
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
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
  static Future<List<GeofenceSite>> loadAttendanceSites(String userId) async {
    final now = DateTime.now();
    final windowStart = now.subtract(const Duration(hours: 14)).toUtc();
    final windowEnd = now.add(const Duration(hours: 14)).toUtc();
    final schedules = await _schedules
        .select()
        .eq('user_id', userId)
        .inFilter('approval_status', ['approved', 'changed'])
        .lt('start_at', windowEnd.toIso8601String())
        .gt('end_at', windowStart.toIso8601String());
    final attendanceSchedules = schedules.where((schedule) {
      final start = _parseTime(schedule['start_at']);
      final end = _parseTime(schedule['end_at']);
      return start != null &&
          end != null &&
          !now.isBefore(start.subtract(const Duration(hours: 2))) &&
          !now.isAfter(end.add(const Duration(hours: 12)));
    }).toList();
    return GeofenceService.loadSitesForUser(
      locationIdsFromSchedules(attendanceSchedules),
    );
  }

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
