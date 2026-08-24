import 'package:flutter_application_1/models/attendance_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AttendanceService {
  static final _sessions = Supabase.instance.client.from('attendance_sessions');

  static AttendanceSession _sessionFrom(dynamic value) {
    if (value is Map<String, dynamic>) return AttendanceSession.fromRow(value);
    if (value is Map) {
      return AttendanceSession.fromRow(Map<String, dynamic>.from(value));
    }
    throw const FormatException('Attendance server response was invalid.');
  }

  static String? blockReasonForAction(
    String action,
    AttendanceSession? openSession,
  ) {
    if (action == 'clock_in' && openSession != null) {
      return 'Time In was recorded at ${formatTime(openSession.clockInAt)}. Record Time Out when this duty ends.';
    }
    if (action == 'clock_out' && openSession == null) {
      return 'Record Time In before Time Out.';
    }
    return null;
  }

  static Future<AttendanceSession?> loadOpenSession(String userId) async {
    final row = await _sessions
        .select()
        .eq('user_id', userId)
        .eq('status', 'open')
        .order('clock_in_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : _sessionFrom(row);
  }

  static Stream<AttendanceSession?> openSessionStream(String userId) =>
      _sessions
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .eq('status', 'open')
          .map((rows) {
            if (rows.isEmpty) return null;
            rows.sort(
              (a, b) => b['clock_in_at'].toString().compareTo(
                a['clock_in_at'].toString(),
              ),
            );
            return _sessionFrom(rows.first);
          });

  static Stream<List<AttendanceSession>> sessionsStream(String userId) =>
      _sessions.stream(primaryKey: ['id']).eq('user_id', userId).map((rows) {
        final sessions = rows.map(_sessionFrom).toList()
          ..sort((a, b) => b.scheduledStartAt.compareTo(a.scheduledStartAt));
        return sessions;
      });

  static Future<AttendanceSession> recordEvent({
    required String action,
    required double latitude,
    required double longitude,
  }) async {
    final row = await Supabase.instance.client.rpc(
      'record_attendance_event',
      params: {
        'p_action': action,
        'p_latitude': latitude,
        'p_longitude': longitude,
      },
    );
    return _sessionFrom(row);
  }

  static String formatTime(DateTime? date) {
    if (date == null) return '—';
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    return '${hour % 12 == 0 ? 12 : hour % 12}:$minute ${hour >= 12 ? 'PM' : 'AM'}';
  }

  static String formatDuration(Duration duration) {
    final minutes = duration.inMinutes.clamp(0, 1 << 30);
    if (minutes == 0) return '0 min';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return '$remainder min';
    if (remainder == 0) return hours == 1 ? '1 hr' : '$hours hrs';
    return '${hours}h ${remainder}m';
  }

  static String formatDurationLabel(DateTime start, DateTime end) =>
      formatDuration(
        end.isAfter(start) ? end.difference(start) : Duration.zero,
      );
}
