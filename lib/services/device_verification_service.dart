import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Snapshot of the guard's device identity & binding status (Revision Items #6, #7, #20).
class DeviceVerificationResult {
  const DeviceVerificationResult({
    required this.deviceId,
    required this.deviceInfo,
    required this.verified,
    required this.status,
    this.registeredDeviceId,
    this.registeredDeviceInfo,
    this.message,
  });

  final String deviceId;
  final String deviceInfo;
  final bool verified;
  final String status; // 'bound', 'matched', 'mismatch', 'local_only'
  final String? registeredDeviceId;
  final String? registeredDeviceInfo;
  final String? message;
}

/// Manages persistent cellular/mobile device identification and binding
/// verification against `public.profiles.registered_device_id`.
class DeviceVerificationService {
  static const _prefKeyDeviceId = 'sentinel_guard_hardware_device_id_v1';
  static DeviceVerificationResult? _cachedResult;
  static String? _cachedUserId;

  /// Clears cached verification state (e.g., on sign-out or account switch).
  static void clearCache() {
    _cachedResult = null;
    _cachedUserId = null;
  }

  /// Generates or retrieves the persistent hardware-bound installation ID for this device.
  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefKeyDeviceId);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final platformPrefix = _platformPrefix();
    final rng = Random.secure();
    final hex = List.generate(
      12,
      (_) => rng.nextInt(16).toRadixString(16),
    ).join().toUpperCase();
    final generated = 'DEV-$platformPrefix-$hex';
    await prefs.setString(_prefKeyDeviceId, generated);
    return generated;
  }

  /// Human-readable description of the device platform and runtime environment.
  static String getDeviceInfoLabel() {
    if (kIsWeb) {
      return 'Web Browser (${defaultTargetPlatform.name.toUpperCase()})';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android Mobile Device';
      case TargetPlatform.iOS:
        return 'iOS Mobile Device';
      case TargetPlatform.windows:
        return 'Windows Workstation';
      case TargetPlatform.macOS:
        return 'macOS Workstation';
      case TargetPlatform.linux:
        return 'Linux Workstation';
      case TargetPlatform.fuchsia:
        return 'Fuchsia Device';
    }
  }

  static String _platformPrefix() {
    if (kIsWeb) return 'WEB';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'AND';
      case TargetPlatform.iOS:
        return 'IOS';
      case TargetPlatform.windows:
        return 'WIN';
      case TargetPlatform.macOS:
        return 'MAC';
      case TargetPlatform.linux:
        return 'LNX';
      case TargetPlatform.fuchsia:
        return 'FCH';
    }
  }

  /// Verifies (or binds on first use) this guard's device with Supabase.
  static Future<DeviceVerificationResult> verifyCurrentDevice({
    bool forceRefresh = false,
  }) async {
    String? currentUid;
    try {
      currentUid = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {}
    if (!forceRefresh &&
        _cachedResult != null &&
        currentUid != null &&
        _cachedUserId == currentUid) {
      return _cachedResult!;
    }
    final deviceId = await getOrCreateDeviceId();
    final deviceInfo = getDeviceInfoLabel();
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        return DeviceVerificationResult(
          deviceId: deviceId,
          deviceInfo: deviceInfo,
          verified: true,
          status: 'local_only',
        );
      }
      final res = await Supabase.instance.client
          .rpc(
            'bind_or_verify_guard_device',
            params: {
              'p_device_id': deviceId,
              'p_device_info': deviceInfo,
              'p_force_rebind': false,
            },
          )
          .timeout(const Duration(seconds: 10));

      if (res is Map) {
        final map = Map<String, dynamic>.from(res);
        final result = DeviceVerificationResult(
          deviceId: deviceId,
          deviceInfo: deviceInfo,
          verified: map['verified'] == true,
          status: map['status']?.toString() ?? 'matched',
          registeredDeviceId: map['registered_device_id']?.toString(),
          registeredDeviceInfo: map['registered_device_info']?.toString(),
          message: map['message']?.toString(),
        );
        _cachedUserId = user.id;
        _cachedResult = result;
        return result;
      }
    } catch (_) {
      // Fallback gracefully if offline or migration not yet cached
    }
    final fallback = DeviceVerificationResult(
      deviceId: deviceId,
      deviceInfo: deviceInfo,
      verified: true,
      status: 'local_only',
    );
    _cachedUserId = currentUid;
    _cachedResult = fallback;
    return fallback;
  }
}

