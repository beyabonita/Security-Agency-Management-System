import 'package:supabase_flutter/supabase_flutter.dart';

class DutyRequestService {
  static final _client = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> upcomingSchedules(
    String userId,
  ) async {
    final rows = await _client
        .from('schedules')
        .select()
        .eq('user_id', userId)
        .eq('approval_status', 'approved')
        .gt('start_at', DateTime.now().toUtc().toIso8601String())
        .order('start_at');
    return rows;
  }

  static Future<void> requestShiftChange({
    required String scheduleId,
    required String reason,
  }) => _client.rpc(
    'request_shift_swap',
    params: {'p_schedule_id': scheduleId, 'p_reason': reason.trim()},
  );

  static Future<void> submitAccomplishment({
    required String scheduleId,
    required String summary,
    required String narrative,
    required String issues,
  }) => _client.rpc(
    'submit_accomplishment_report',
    params: {
      'p_schedule_id': scheduleId,
      'p_summary': summary.trim(),
      'p_detailed_narrative': narrative.trim(),
      'p_issues_encountered': issues.trim(),
    },
  );
}
