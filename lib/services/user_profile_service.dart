import 'package:flutter_application_1/utils/auth_username.dart' as auth_user;
import 'package:supabase_flutter/supabase_flutter.dart';

class UserProfileService {
  static final _profiles = Supabase.instance.client.from('profiles');

  static String displayLoginId(Map<String, dynamic>? data) =>
      auth_user.displayLoginId(data);

  static String displayName(Map<String, dynamic> data) {
    final first = data['first_name']?.toString() ?? '';
    final middle = data['middle_initial']?.toString() ?? '';
    final last = data['last_name']?.toString() ?? '';
    if (first.isEmpty && last.isEmpty) return 'Security Guard';
    final mi = middle.isNotEmpty ? '$middle. ' : '';
    return '$first $mi$last'.trim();
  }

  static Future<Map<String, dynamic>?> getProfile(String uid) async =>
      await _profiles.select().eq('id', uid).maybeSingle();

  static Stream<Map<String, dynamic>?> profileStream(String uid) => _profiles
      .stream(primaryKey: ['id'])
      .eq('id', uid)
      .map((rows) => rows.isEmpty ? null : rows.first);

  /// Returns null if login is allowed, otherwise an error message.
  static Future<String?> validateGuardLogin(String uid) async {
    final data = await getProfile(uid);
    if (data == null) {
      return 'Account profile not found. Contact your administrator.';
    }
    final role = data['role']?.toString();
    if (role == 'admin') {
      return 'admin';
    }
    if (role == 'it_admin') return 'it_admin';
    if (role == 'inspector') return 'Inspector accounts use the web panel.';
    if (data['active'] != true) {
      return 'Your account has been disabled. Contact your administrator.';
    }
    return null;
  }

  static Future<void> registerDeviceIfNeeded(
    String uid,
    String deviceId,
  ) async {
    await Supabase.instance.client.rpc(
      'register_device',
      params: {'p_device_id': deviceId},
    );
  }
}
