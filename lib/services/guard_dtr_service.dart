import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/attendance_session.dart';
import '../models/guard_dtr.dart';
import 'user_profile_service.dart';

class GuardDtrService {
  GuardDtrService(this.client);
  final SupabaseClient client;

  /// Own-account only; never accepts a caller-supplied guard identifier.
  Future<GuardDtr> load(GuardDtrPeriod period) async {
    final id = client.auth.currentUser?.id;
    if (id == null) throw StateError('Please sign in to view your DTR.');
    final profile = await client
        .from('profiles')
        .select('first_name,middle_initial,last_name')
        .eq('id', id)
        .single();
    final sessions = <AttendanceSession>[];
    const pageSize = 500;
    for (var offset = 0; ; offset += pageSize) {
      final rows = await client
          .from('attendance_sessions')
          .select()
          .eq('user_id', id)
          .gte('duty_date', period.start)
          .lte('duty_date', period.end)
          .order('id')
          .range(offset, offset + pageSize - 1);
      sessions.addAll(rows.map(AttendanceSession.fromRow));
      if (rows.length < pageSize) break;
    }
    if (client.auth.currentUser?.id != id) {
      throw StateError('Your account changed. Please reopen your DTR.');
    }
    return GuardDtr(
      period: period,
      guardName: UserProfileService.displayName(profile),
      sessions: sessions,
    );
  }
}
