import 'package:flutter_application_1/models/dtr_alignment.dart';

class AttendanceSession {
  const AttendanceSession({
    required this.id,
    required this.scheduleId,
    required this.dutyDate,
    required this.locationLabel,
    required this.scheduledStartAt,
    required this.scheduledEndAt,
    required this.clockInAt,
    this.clockOutAt,
    required this.status,
    this.dtrPeriod = 'auto',
    this.locationId = '',
    this.timeoutVerifiedAt,
    this.clockOutLocationStatus,
    this.timeoutSubmittedAt,
    this.overtimeRequested,
    this.forceAttendanceRequested = false,
    this.forceAttendanceReason,
    this.forceAttendanceStatus,
    this.distanceFromPostMeters,
    this.dualPointDistanceMeters,
    this.deviceId,
    this.deviceInfo,
    this.deviceVerified,
    this.clockInFacePhoto,
  });

  final String id;
  final String scheduleId;
  final String dutyDate;
  final String locationLabel;
  final String locationId;
  final DateTime scheduledStartAt;
  final DateTime scheduledEndAt;
  final DateTime clockInAt;
  final DateTime? clockOutAt;
  final String status;
  final String dtrPeriod;
  final DateTime? timeoutVerifiedAt;
  final String? clockOutLocationStatus;
  final DateTime? timeoutSubmittedAt;
  final bool? overtimeRequested;
  final bool forceAttendanceRequested;
  final String? forceAttendanceReason;
  final String? forceAttendanceStatus;
  final double? distanceFromPostMeters;
  final double? dualPointDistanceMeters;
  final String? deviceId;
  final String? deviceInfo;
  final bool? deviceVerified;
  final String? clockInFacePhoto;

  bool get overtimeApprovalPending =>
      overtimeRequested == true && needsTimeoutReview;

  bool get forceAttendancePending =>
      forceAttendanceRequested && forceAttendanceStatus == 'pending';

  bool get needsTimeoutReview =>
      clockOutAt != null &&
      clockOutAt!.isAfter(scheduledEndAt) &&
      timeoutVerifiedAt == null;

  bool get isOpen => status == 'open' && clockOutAt == null;
  bool get isClosed => status == 'closed' && clockOutAt != null;

  bool isActiveAt(DateTime now) => isOpen && now.isBefore(scheduledEndAt);

  bool isMissingTimeOutAt(DateTime now) =>
      clockOutAt == null &&
      (status == 'missed_timeout' || (isOpen && !now.isBefore(scheduledEndAt)));

  String get dtrCutoffLabel => DtrAlignment.cutoffLabel(dutyDate);

  String get dtrTimeInColumn => DtrAlignment.cellLabel(
    scheduledStartAt,
    isTimeIn: true,
    dutyDate: dutyDate,
    period: dtrPeriod,
  );

  String get dtrTimeOutColumn => DtrAlignment.cellLabel(
    scheduledEndAt,
    isTimeIn: false,
    dutyDate: dutyDate,
    period: dtrPeriod,
  );

  String get dtrMappingLabel => '$dtrTimeInColumn → $dtrTimeOutColumn';

  Duration get workedDuration {
    final end = clockOutAt;
    if (end == null || end.isBefore(clockInAt) || needsTimeoutReview) {
      return Duration.zero;
    }
    return end.difference(clockInAt);
  }

  Duration get scheduledDuration => scheduledEndAt.difference(scheduledStartAt);

  Duration get lateDuration => clockInAt.isAfter(scheduledStartAt)
      ? clockInAt.difference(scheduledStartAt)
      : Duration.zero;

  Duration get undertimeDuration {
    final end = clockOutAt;
    if (end == null || !end.isBefore(scheduledEndAt) || needsTimeoutReview) {
      return Duration.zero;
    }
    return scheduledEndAt.difference(end);
  }

  factory AttendanceSession.fromRow(Map<String, dynamic> row) {
    DateTime parseRequired(String key) {
      final value = DateTime.tryParse(row[key]?.toString() ?? '');
      if (value == null) {
        throw FormatException('Attendance session is missing $key.');
      }
      return value.toLocal();
    }

    DateTime? parseOptional(String key) {
      final raw = row[key];
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString())?.toLocal();
    }

    return AttendanceSession(
      id: row['id']?.toString() ?? '',
      scheduleId: row['schedule_id']?.toString() ?? '',
      dutyDate: row['duty_date']?.toString() ?? '',
      locationLabel: row['location_label']?.toString() ?? '',
      locationId: row['location_id']?.toString() ?? '',
      scheduledStartAt: parseRequired('scheduled_start_at'),
      scheduledEndAt: parseRequired('scheduled_end_at'),
      clockInAt: parseRequired('clock_in_at'),
      clockOutAt: parseOptional('clock_out_at'),
      status: row['status']?.toString() ?? 'open',
      dtrPeriod: DtrAlignment.normalizePeriod(row['dtr_period']?.toString()),
      timeoutVerifiedAt: parseOptional('timeout_verified_at'),
      clockOutLocationStatus: row['clock_out_location_status']?.toString(),
      timeoutSubmittedAt: parseOptional('timeout_submitted_at'),
      overtimeRequested: row['overtime_requested'] as bool?,
      forceAttendanceRequested: row['force_attendance_requested'] == true,
      forceAttendanceReason: row['force_attendance_reason']?.toString(),
      forceAttendanceStatus: row['force_attendance_status']?.toString(),
      distanceFromPostMeters: (row['distance_from_post_meters'] as num?)
          ?.toDouble(),
      dualPointDistanceMeters: (row['dual_point_distance_meters'] as num?)
          ?.toDouble(),
      deviceId: row['device_id']?.toString(),
      deviceInfo: row['device_info']?.toString(),
      deviceVerified: row['device_verified'] as bool?,
      clockInFacePhoto: row['clock_in_face_photo']?.toString(),
    );
  }
}
