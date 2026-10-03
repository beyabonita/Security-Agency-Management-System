import 'dart:async';

import 'package:flutter_application_1/models/attendance_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AttendanceService {
  static final _recorded = StreamController<AttendanceSession>.broadcast(
    sync: true,
  );
  static Stream<AttendanceSession> get recordedEvents => _recorded.stream;
  // Each stream needs its own realtime topic. Reusing a query builder reuses
  // its channel ID, so cancelling an old listener can close the new one.
  static SupabaseQueryBuilder get _sessions =>
      Supabase.instance.client.from('attendance_sessions');

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
    if (action == 'clock_in' &&
        openSession != null &&
        openSession.isActiveAt(DateTime.now())) {
      return 'Time In was recorded at ${formatTime(openSession.clockInAt)}. Record Time Out when this duty ends.';
    }
    if (action == 'clock_out' && openSession == null) {
      return 'Record Time In before Time Out.';
    }
    if (action == 'clock_out' && openSession != null && !openSession.isOpen) {
      return 'This duty is no longer open. Ask your Operations Head to review the missing Time Out.';
    }
    return null;
  }

  /// Keep late Time Out available until a new eligible duty takes precedence.
  static AttendanceSession? sessionForDuty(
    AttendanceSession? session,
    String? nextScheduleId, {
    DateTime? now,
  }) {
    if (session == null || !session.isOpen) return null;
    if (!session.isActiveAt(now ?? DateTime.now()) &&
        nextScheduleId != null &&
        nextScheduleId != session.scheduleId) {
      return null;
    }
    return session;
  }

  static Future<AttendanceSession?> loadLatestSession(String userId) async {
    final row = await _sessions
        .select()
        .eq('user_id', userId)
        .order('clock_in_at', ascending: false)
        .limit(1)
        .maybeSingle()
        .timeout(const Duration(seconds: 15));
    return row == null ? null : _sessionFrom(row);
  }

  static Stream<AttendanceSession?> latestSessionStream(String userId) async* {
    yield await loadLatestSession(userId);
    yield* sessionsStream(userId).map((sessions) {
      if (sessions.isEmpty) return null;
      sessions.sort((a, b) => b.clockInAt.compareTo(a.clockInAt));
      return sessions.first;
    });
  }

  static Future<AttendanceSession?> loadOpenSession(String userId) async {
    final row = await _sessions
        .select()
        .eq('user_id', userId)
        .eq('status', 'open')
        .order('clock_in_at', ascending: false)
        .limit(1)
        .maybeSingle()
        .timeout(const Duration(seconds: 15));
    return row == null ? null : _sessionFrom(row);
  }

  static Stream<AttendanceSession?> openSessionStream(String userId) async* {
    // The punch button must not wait for a websocket connection to become ready.
    yield await loadOpenSession(userId);
    yield* _sessions.stream(primaryKey: ['id']).eq('user_id', userId).map((
      rows,
    ) {
      // Only one server stream filter is supported. Filter status here so
      // a closing UPDATE removes the open duty immediately.
      rows = rows
          .where((row) => row['user_id'] == userId && row['status'] == 'open')
          .toList();
      if (rows.isEmpty) return null;
      rows.sort(
        (a, b) =>
            b['clock_in_at'].toString().compareTo(a['clock_in_at'].toString()),
      );
      return _sessionFrom(rows.first);
    });
  }

  static Stream<List<AttendanceSession>> sessionsStream(String userId) =>
      refreshAtShiftEnd(
        _sessions.stream(primaryKey: ['id']).eq('user_id', userId).map((rows) {
          final sessions = rows.map(_sessionFrom).toList()
            ..sort((a, b) => b.scheduledStartAt.compareTo(a.scheduledStartAt));
          return sessions;
        }),
      );

  /// A shift can end without a database update. Refresh its displayed status.
  static Stream<List<AttendanceSession>> refreshAtShiftEnd(
    Stream<List<AttendanceSession>> source,
  ) => Stream.multi((controller) {
    Timer? timer;
    void emit(List<AttendanceSession> sessions) {
      timer?.cancel();
      controller.add(sessions);
      final now = DateTime.now();
      final ends =
          sessions
              .where((s) => s.isActiveAt(now))
              .map((s) => s.scheduledEndAt)
              .toList()
            ..sort();
      if (ends.isNotEmpty) {
        timer = Timer(ends.first.difference(now), () => emit(sessions));
      }
    }

    final subscription = source.listen(
      emit,
      onError: controller.addError,
      onDone: () {
        timer?.cancel();
        controller.close();
      },
    );
    controller.onCancel = () {
      timer?.cancel();
      return subscription.cancel();
    };
    controller.onPause = subscription.pause;
    controller.onResume = subscription.resume;
  });

  static Future<AttendanceSession> recordEvent({
    required String action,
    required double latitude,
    required double longitude,
    String? sessionId,
    bool? claimOvertime,
  }) async {
    if (action == 'clock_out' && sessionId == null) {
      throw ArgumentError('A duty session is required for Time Out.');
    }
    final row = await Supabase.instance.client
        .rpc(
          action == 'clock_out'
              ? 'record_guard_timeout'
              : 'record_attendance_event',
          params: action == 'clock_out'
              ? {
                  'p_session_id': sessionId,
                  'p_claim_overtime': claimOvertime,
                  'p_latitude': latitude,
                  'p_longitude': longitude,
                }
              : {
                  'p_action': action,
                  'p_latitude': latitude,
                  'p_longitude': longitude,
                },
        )
        .timeout(const Duration(seconds: 20));
    final session = _sessionFrom(row);
    _recorded.add(session);
    return session;
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
