class LocationIntegrityService {
  static const maxFixAge = Duration(seconds: 45);

  /// Returns a user-facing explanation when a location fix is not suitable
  /// for attendance. Device location can still be spoofed by a compromised
  /// device; this rejects the common weak or mock-location cases.
  static String? validationError({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime capturedAt,
    required bool isMocked,
    DateTime? now,
  }) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return 'The device returned invalid location coordinates. Refresh and try again.';
    }
    if (isMocked) {
      return 'Mock or simulated locations cannot be used for attendance.';
    }
    if (!accuracyMeters.isFinite || accuracyMeters <= 0) {
      return 'The device did not provide a usable GPS accuracy. Refresh your location and try again.';
    }
    final capturedAtUtc = capturedAt.toUtc();
    final nowUtc = (now ?? DateTime.now()).toUtc();
    if (nowUtc.difference(capturedAtUtc).abs() > maxFixAge) {
      return 'Your location fix is too old. Refresh your location and try again.';
    }
    return null;
  }
}
