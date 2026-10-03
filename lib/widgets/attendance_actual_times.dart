import 'package:flutter/material.dart';
import '../models/attendance_session.dart';
import '../services/attendance_service.dart';
import '../theme/app_colors.dart';

/// Recorded punches, including the date so overnight duties are unambiguous.
class AttendanceActualTimes extends StatelessWidget {
  const AttendanceActualTimes({super.key, this.session});
  final AttendanceSession? session;

  static String timestamp(DateTime? value) {
    if (value == null) return 'Not recorded';
    final local = value.toLocal();
    const months = [
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
    return '${months[local.month - 1]} ${local.day}, ${local.year} · ${AttendanceService.formatTime(local)}';
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.of(context).accent.withValues(alpha: .055),
      border: Border.all(
        color: AppColors.of(context).accent.withValues(alpha: .18),
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Actual Time In',
          style: TextStyle(
            color: AppColors.of(context).accent,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(timestamp(session?.clockInAt)),
        const SizedBox(height: 14),
        Text(
          'Actual Time Out',
          style: TextStyle(
            color: AppColors.of(context).accent,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(timestamp(session?.timeoutSubmittedAt ?? session?.clockOutAt)),
        if (session?.overtimeApprovalPending == true)
          const Text('Overtime awaiting Operations Head approval'),
        if (session?.overtimeRequested == false &&
            session?.timeoutSubmittedAt != null &&
            session!.timeoutSubmittedAt!.isAfter(session!.scheduledEndAt))
          Text(
            'DTR Time Out: ${timestamp(session?.clockOutAt)} · No overtime requested',
          ),
      ],
    ),
  );
}
