import 'attendance_session.dart';

/// The same cutoff, Philippine time and verified-hours rules as web DtrReport.
class GuardDtrPeriod {
  GuardDtrPeriod(this.year, this.month, this.secondHalf);
  final int year;
  final int month;
  final bool secondHalf;
  int get firstDay => secondHalf ? 16 : 1;
  int get lastDay => secondHalf ? DateTime.utc(year, month + 1, 0).day : 15;
  String date(int day) => '$year-${pad(month)}-${pad(day)}';
  String get start => date(firstDay);
  String get end => date(lastDay);
  String get monthLabel => '${months[month - 1]} $year';
  String get label =>
      '${months[month - 1]} $firstDay, $year - ${months[month - 1]} $lastDay, $year';
  static const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static String pad(int n) => n.toString().padLeft(2, '0');
}

class GuardDtr {
  GuardDtr({
    required this.period,
    required this.guardName,
    required List<AttendanceSession> sessions,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final included =
        sessions
            .where(
              (s) =>
                  s.dutyDate.compareTo(period.start) >= 0 &&
                  s.dutyDate.compareTo(period.end) <= 0,
            )
            .toList()
          ..sort((a, b) => a.scheduledStartAt.compareTo(b.scheduledStartAt));
    final sites = included
        .map((s) => s.locationLabel.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    detachment = sites.length == 1
        ? sites.first
        : sites.isEmpty
        ? '-'
        : 'Multiple deployment sites';
    for (var day = period.firstDay; day <= period.lastDay; day++) {
      final dutyDate = period.date(day);
      final entries = included.where((s) => s.dutyDate == dutyDate).toList();
      if (entries.isEmpty) rows.add(['$day', '', '', '', '', '']);
      if (entries.isNotEmpty &&
          entries.every((s) => s.clockOutAt != null && !review(s, at))) {
        completedDays++;
      }
      for (final s in entries) {
        final pending = review(s, at);
        final out = s.clockOutAt;
        final minutes = out == null || pending
            ? 0
            : out.difference(s.clockInAt).inMinutes.clamp(0, 1 << 40);
        final overtimeStart = s.clockInAt.isAfter(s.scheduledEndAt)
            ? s.clockInAt
            : s.scheduledEndAt;
        final overtime = out == null || pending
            ? 0
            : out.difference(overtimeStart).inMinutes.clamp(0, 1 << 40);
        totalMinutes += minutes;
        overtimeMinutes += overtime;
        final scheduled = (s.scheduledDuration.inMilliseconds / 60000)
            .round()
            .clamp(0, 1 << 40);
        final planned = scheduled < 60
            ? '$scheduled min'
            : scheduled == 60
            ? '1 hr'
            : scheduled % 60 == 0
            ? '${scheduled ~/ 60} hrs'
            : '${scheduled ~/ 60}h ${scheduled % 60}m';
        rows.add([
          '$day',
          '${punch(s.scheduledStartAt, dutyDate)} – ${punch(s.scheduledEndAt, dutyDate)}\n$planned scheduled${s.dtrPeriod == 'overtime' ? '\nOvertime assignment' : ''}${s.locationLabel.isEmpty ? '' : '\n${s.locationLabel}'}',
          punch(s.clockInAt, dutyDate),
          out == null || s.overtimeApprovalPending ? '' : punch(out, dutyDate),
          out == null || pending ? '' : hours(overtime),
          out == null || pending ? '' : hours(minutes),
        ]);
        final note = s.overtimeApprovalPending
            ? 'Overtime Time Out awaiting Operations Head approval; hours excluded.'
            : pending
            ? '${out == null ? 'Missing' : 'Late'} Time Out - awaiting Operations Head verification; hours excluded.'
            : s.timeoutVerifiedAt != null
            ? 'Time Out verified by Operations Head.'
            : s.clockOutLocationStatus == 'unavailable'
            ? 'Time Out recorded; GPS unavailable.'
            : s.clockOutLocationStatus == 'outside_post'
            ? 'Time Out recorded outside the assigned post; review location.'
            : '';
        if (note.isNotEmpty) notes.add('$dutyDate: $note');
      }
    }
  }

  final GuardDtrPeriod period;
  final String guardName;
  late final String detachment;
  final List<List<String>> rows = [];
  final List<String> notes = [];
  int totalMinutes = 0;
  int overtimeMinutes = 0;
  int completedDays = 0;
  static const agency = 'TWENTY TWENTY SECURITY AGENCY, INC.';
  static const address1 = 'P. Hernaez Ext. (Fronting Villa Celia Subd.)';
  static const address2 =
      'Brgy. Taculing, Bacolod City, Negros Occidental 6100';
  static const contact =
      'Email: ttwenty2016@yahoo.com | Tel: (034) 466-5235 | Mobile: 09056654294';
  static const title = 'DAILY TIME RECORD - GUARD SHIFTS';
  static const columns = [
    'Duty\nDate',
    'Assigned shift / Site',
    'Actual\nTime In',
    'Actual\nTime Out',
    'Total Overtime\nHours',
    'Total Worked\nHours',
  ];
  static const footnote =
      'Overnight times are marked next day. Hours use H:MM. Overtime is already included in Total Worked Hours. Unverified Time Outs are excluded from totals.';
  String get fileName =>
      'DTR_${guardName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}_${period.start}_${period.end}.pdf';
  static String hours(int minutes) =>
      '${minutes ~/ 60}:${GuardDtrPeriod.pad(minutes % 60)}';
  static bool review(AttendanceSession s, DateTime now) =>
      s.timeoutVerifiedAt == null &&
      (s.clockOutAt != null
          ? s.clockOutAt!.isAfter(s.scheduledEndAt)
          : s.status == 'missed_timeout' || !s.scheduledEndAt.isAfter(now));
  static DateTime philippineTime(DateTime date) =>
      date.toUtc().add(const Duration(hours: 8));
  static String punch(DateTime value, String dutyDate) {
    final date = philippineTime(value);
    final day = DateTime.utc(date.year, date.month, date.day);
    final offset = day
        .difference(DateTime.parse('${dutyDate}T00:00:00Z'))
        .inDays;
    final suffix = offset == 1
        ? ' (next day)'
        : offset == -1
        ? ' (previous day)'
        : offset > 1
        ? ' ($offset days later)'
        : offset < -1
        ? ' (${-offset} days earlier)'
        : '';
    return '${date.hour % 12 == 0 ? 12 : date.hour % 12}:${GuardDtrPeriod.pad(date.minute)} ${date.hour < 12 ? 'AM' : 'PM'}$suffix';
  }
}
