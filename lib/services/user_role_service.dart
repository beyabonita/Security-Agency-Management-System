import 'package:flutter_application_1/services/user_profile_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserRoleService {
  static Future<String?> getRole(String uid) async =>
      (await UserProfileService.getProfile(uid))?['role']?.toString();

  static Future<String?> currentUserRole() async {
    final user = Supabase.instance.client.auth.currentUser;
    return user == null ? null : getRole(user.id);
  }

  static Future<bool> isAdmin() async => await currentUserRole() == 'admin';
}
