import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_application_1/utils/auth_username.dart' as auth_user;
import 'package:supabase_flutter/supabase_flutter.dart';

class UserProfileService {
  static final _profiles = Supabase.instance.client.from('profiles');

  static const List<int> _avatarPalette = <int>[
    0xFFB91C1C, // Crimson
    0xFF9F1239, // Rose maroon
    0xFF0F766E, // Deep teal
    0xFF1D4ED8, // Royal blue
    0xFF6D28D9, // Violet
    0xFFB45309, // Amber bronze
    0xFF15803D, // Forest green
    0xFF334155, // Slate
  ];

  static String displayLoginId(Map<String, dynamic>? data) =>
      auth_user.displayLoginId(data);

  static String displayName(Map<String, dynamic> data) {
    final first = data['first_name']?.toString().trim() ?? '';
    final middle = data['middle_initial']?.toString().trim() ?? '';
    final last = data['last_name']?.toString().trim() ?? '';
    if (first.isEmpty && last.isEmpty) return 'Security Guard';
    final mi = middle.isNotEmpty ? '$middle. ' : '';
    return '$first $mi$last'.trim();
  }

  static String initialsFor(
    Map<String, dynamic>? data, {
    String? fallbackName,
  }) {
    final first = data?['first_name']?.toString().trim() ?? '';
    final last = data?['last_name']?.toString().trim() ?? '';
    if (first.isNotEmpty || last.isNotEmpty) {
      final a = first.isNotEmpty ? first[0] : '';
      final b = last.isNotEmpty
          ? last[0]
          : (first.length > 1 ? first[1] : '');
      final combined = '$a$b'.toUpperCase();
      if (combined.isNotEmpty) return combined;
    }
    final name = (fallbackName ?? '').trim();
    if (name.isNotEmpty) {
      final parts = name
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
      }
      if (parts.length == 1) {
        final word = parts.first;
        return (word.length >= 2 ? word.substring(0, 2) : word).toUpperCase();
      }
    }
    return 'SG';
  }

  static int avatarColorValueFor(String seed) {
    final normalized = seed.trim().toLowerCase();
    if (normalized.isEmpty) return _avatarPalette.first;
    var hash = 0;
    for (var i = 0; i < normalized.length; i++) {
      hash = ((hash * 31) + normalized.codeUnitAt(i)) & 0x7fffffff;
    }
    return _avatarPalette[hash % _avatarPalette.length];
  }

  static Future<Map<String, dynamic>?> getProfile(String uid) async =>
      await _profiles.select().eq('id', uid).maybeSingle();

  static Stream<Map<String, dynamic>?> profileStream(String uid) => _profiles
      .stream(primaryKey: ['id'])
      .eq('id', uid)
      .map((rows) => rows.isEmpty ? null : rows.first);

  static Future<Map<String, dynamic>> getOwnGuardProfileDetails() async {
    try {
      final res = await Supabase.instance.client.rpc(
        'get_own_guard_profile_details',
      );
      if (res is Map<String, dynamic>) return res;
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (_) {
      // Fallback to direct row select if RPC is not yet available
    }
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) throw Exception('Not signed in.');
    final fallback = await getProfile(uid);
    if (fallback == null) throw Exception('Account profile not found.');
    return fallback;
  }

  static Future<Map<String, dynamic>> updateOwnGuardProfile({
    required String mobileNumber,
    required String completeAddress,
    required String emergencyContact,
  }) async {
    try {
      final res = await Supabase.instance.client.rpc(
        'update_own_guard_profile',
        params: {
          'p_mobile_number': mobileNumber.trim(),
          'p_complete_address': completeAddress.trim(),
          'p_emergency_contact': emergencyContact.trim(),
          'p_strict_payload': {
            'mobile_number': mobileNumber.trim(),
            'complete_address': completeAddress.trim(),
            'emergency_contact': emergencyContact.trim(),
          },
        },
      );
      if (res is Map<String, dynamic>) return res;
      if (res is Map) return Map<String, dynamic>.from(res);
      return const <String, dynamic>{};
    } on PostgrestException catch (error) {
      throw Exception(
        error.message.trim().isNotEmpty
            ? error.message.trim()
            : 'Could not save profile changes.',
      );
    }
  }

  static Future<String> uploadOwnProfilePhoto(Uint8List jpegBytes) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'profile-photo',
        body: {
          'action': 'upload',
          'photoBase64': base64Encode(jpegBytes),
          'mimeType': 'image/jpeg',
        },
      );
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error'].toString());
      }
      final url = data is Map ? data['profilePhotoUrl']?.toString() : null;
      if (url == null || url.isEmpty) {
        throw Exception('Server did not return a profile photo URL.');
      }
      return url;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception('Could not upload profile photo (${error.status}).');
    }
  }

  static Future<void> removeOwnProfilePhoto() async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'profile-photo',
        body: {'action': 'remove'},
      );
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error'].toString());
      }
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception('Could not remove profile photo (${error.status}).');
    }
  }

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
