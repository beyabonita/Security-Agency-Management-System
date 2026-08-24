import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_application_1/models/attendance_session.dart';
import 'package:flutter_application_1/services/attendance_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/widgets/guard_ui.dart';

class TimeLogsScreen extends StatelessWidget {
  const TimeLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: AppColors.scaffold,
        body: Center(
          child: Text(
            'Please log in to view your duty records.',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            GuardPageTopBar(
              title: 'Duty time records',
              subtitle: 'Scheduled shifts, attendance, and worked time',
              onBack: () => Navigator.pop(context),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<List<AttendanceSession>>(
                stream: AttendanceService.sessionsStream(user.id),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const _ErrorState();
                  }
                  if (!snapshot.hasData) {
                    return const GuardLoadingView(
                      label: 'Loading duty records…',
                    );
                  }
                  final sessions = snapshot.data!;
                  if (sessions.isEmpty) return const _EmptyState();

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: sessions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) =>
                        _SessionCard(session: sessions[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});
  final AttendanceSession session;

  @override
  Widget build(BuildContext context) {
    final isOpen = session.isOpen;
    final statusColor = isOpen ? AppColors.warning : AppColors.success;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppColors.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isOpen ? Icons.timelapse_rounded : Icons.task_alt_rounded,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDate(session.dutyDate),
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      session.locationLabel.isEmpty
                          ? 'Scheduled duty post'
                          : session.locationLabel,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(
                label: isOpen ? 'Open' : 'Completed',
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Scheduled: ${AttendanceService.formatTime(session.scheduledStartAt)} – ${AttendanceService.formatTime(session.scheduledEndAt)}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TimeDetail(
                  label: 'Time In',
                  value: AttendanceService.formatTime(session.clockInAt),
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeDetail(
                  label: 'Time Out',
                  value: AttendanceService.formatTime(session.clockOutAt),
                  color: isOpen ? AppColors.textMuted : AppColors.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeDetail(
                  label: 'Worked',
                  value: isOpen
                      ? 'In progress'
                      : AttendanceService.formatDuration(
                          session.workedDuration,
                        ),
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (session.isClosed &&
              (session.lateDuration > Duration.zero ||
                  session.undertimeDuration > Duration.zero)) ...[
            const SizedBox(height: 12),
            Text(
              [
                if (session.lateDuration > Duration.zero)
                  'Late ${AttendanceService.formatDuration(session.lateDuration)}',
                if (session.undertimeDuration > Duration.zero)
                  'Undertime ${AttendanceService.formatDuration(session.undertimeDuration)}',
              ].join(' • '),
              style: const TextStyle(color: AppColors.warning, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );
}

class _TimeDetail extends StatelessWidget {
  const _TimeDetail({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const GuardEmptyState(
    icon: Icons.history_rounded,
    title: 'No duty records yet',
    message:
        'Time In from Attendance to begin your first scheduled duty record.',
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState();

  @override
  Widget build(BuildContext context) => const GuardEmptyState(
    icon: Icons.cloud_off_rounded,
    title: 'Could not load duty records',
    message: 'Check your connection, then return to this page to try again.',
  );
}
