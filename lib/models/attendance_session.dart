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
  });

  final String id;
  final String scheduleId;
  final String dutyDate;
  final String locationLabel;
  final DateTime scheduledStartAt;
  final DateTime scheduledEndAt;
  final DateTime clockInAt;
  final DateTime? clockOutAt;
  final String status;

  bool get isOpen => status == 'open' && clockOutAt == null;
  bool get isClosed => status == 'closed' && clockOutAt != null;

  Duration get workedDuration {
    final end = clockOutAt;
    if (end == null || end.isBefore(clockInAt)) return Duration.zero;
    return end.difference(clockInAt);
  }

  Duration get scheduledDuration => scheduledEndAt.difference(scheduledStartAt);

  Duration get lateDuration => clockInAt.isAfter(scheduledStartAt)
      ? clockInAt.difference(scheduledStartAt)
      : Duration.zero;

  Duration get undertimeDuration {
    final end = clockOutAt;
    if (end == null || !end.isBefore(scheduledEndAt)) return Duration.zero;
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
      scheduledStartAt: parseRequired('scheduled_start_at'),
      scheduledEndAt: parseRequired('scheduled_end_at'),
      clockInAt: parseRequired('clock_in_at'),
      clockOutAt: parseOptional('clock_out_at'),
      status: row['status']?.toString() ?? 'open',
    );
  }
}
