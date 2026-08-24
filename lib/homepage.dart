import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/attendance.dart';
import 'package:flutter_application_1/models/app_notification.dart';
import 'package:flutter_application_1/notifications.dart';
import 'package:flutter_application_1/services/attendance_service.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/schedule_service.dart';
import 'package:flutter_application_1/services/user_profile_service.dart';
import 'package:flutter_application_1/incident_report.dart';
import 'package:flutter_application_1/duty_requests.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/time_logs.dart';
import 'package:flutter_application_1/widgets/guard_ui.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  StreamSubscription<List<AppNotification>>? _notificationSubscription;
  List<AppNotification> _notifications = const [];
  final Set<String> _knownNotificationIds = <String>{};
  bool _notificationsSeeded = false;
  bool _criticalDialogOpen = false;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      _notificationSubscription = NotificationService.watch(user.id).listen(
        _handleNotifications,
        onError: (_) {
          // The inbox page exposes a retry state. Keep the duty dashboard usable.
        },
      );
    }
  }

  void _handleNotifications(List<AppNotification> notifications) {
    final newNotifications = _notificationsSeeded
        ? notifications
              .where((item) => !_knownNotificationIds.contains(item.id))
              .toList()
        : const <AppNotification>[];
    final pendingCritical = notifications
        .where((item) => item.needsAcknowledgement)
        .firstOrNull;
    _knownNotificationIds
      ..clear()
      ..addAll(notifications.map((item) => item.id));
    _notificationsSeeded = true;
    if (mounted) setState(() => _notifications = notifications);
    final notificationToShow =
        pendingCritical ??
        (newNotifications.isEmpty ? null : newNotifications.first);
    if (notificationToShow != null &&
        !(notificationToShow.isCritical && _criticalDialogOpen)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showIncomingNotification(notificationToShow);
      });
    }
  }

  Future<void> _showIncomingNotification(AppNotification notification) async {
    if (notification.isCritical &&
        notification.needsAcknowledgement &&
        !_criticalDialogOpen) {
      _criticalDialogOpen = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: AlertDialog(
            icon: const Icon(
              Icons.notification_important_rounded,
              color: AppColors.error,
              size: 36,
            ),
            title: Text(notification.title),
            content: Text(notification.message),
            actions: [
              FilledButton.icon(
                onPressed: () async {
                  try {
                    await NotificationService.acknowledge(notification.id);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (error) {
                    if (!dialogContext.mounted) return;
                    ScaffoldMessenger.of(
                      dialogContext,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Acknowledge'),
              ),
            ],
          ),
        ),
      );
      _criticalDialogOpen = false;
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: notification.priority == 'high'
              ? const Duration(seconds: 8)
              : const Duration(seconds: 5),
          content: Row(
            children: [
              const Icon(Icons.notifications_active, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${notification.title}\n${notification.message}'),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: _openNotifications,
          ),
        ),
      );
  }

  void _openNotifications() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _signOut() async {
    final confirmed = await showGuardConfirmation(
      context,
      title: 'Sign out?',
      message: 'You will need your username and password to sign in again.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!confirmed) return;
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: AppColors.scaffold,
        body: GuardLoadingView(label: 'Preparing your duty workspace…'),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: StreamBuilder<Map<String, dynamic>?>(
          stream: UserProfileService.profileStream(user.id),
          builder: (context, profileSnap) {
            final profile = profileSnap.data;
            final loginFallback = UserProfileService.displayLoginId({
              'email': user.email ?? '',
            });
            final displayName = profile != null
                ? UserProfileService.displayName(profile)
                : loginFallback.isNotEmpty
                ? loginFallback
                : 'Guard';
            final isActive = profile?['active'] != false;

            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - value)),
                  child: child,
                ),
              ),
              child: CustomScrollView(
                slivers: [
                  // ── App Bar ───────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const SentinelBrandMark(size: 40),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Sentinel Link',
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 1.25,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Hello, ${displayName.split(' ').first} 👋',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.text,
                                          fontSize: 21,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _NotificationButton(
                            notifications: _notifications,
                            onTap: _openNotifications,
                          ),
                          const SizedBox(width: 8),
                          // Sign out
                          _GlassButton(
                            icon: Icons.logout_rounded,
                            color: AppColors.primary,
                            onTap: _signOut,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ── Status card ───────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: _StatusCard(
                        displayName: displayName,
                        isActive: isActive,
                        employmentCategory:
                            profile?['employment_category']?.toString() ??
                            'regular',
                      ),
                    ),
                  ),

                  // ── Quick actions ─────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: _SectionLabel(label: 'DUTY ACTIONS'),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: _ActionCard(
                        icon: Icons.fingerprint_rounded,
                        label: 'Time In / Out',
                        subtitle: 'Verify your post and record attendance',
                        color: AppColors.primary,
                        horizontal: true,
                        emphasized: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const Attendance()),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ActionCard(
                              icon: Icons.history_rounded,
                              label: 'Duty Logs',
                              subtitle: 'View DTR',
                              color: AppColors.primaryLight,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const TimeLogsScreen(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ActionCard(
                              icon: Icons.swap_horiz_rounded,
                              label: 'Shift Change',
                              subtitle: 'Send request',
                              color: AppColors.secondary,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const ShiftChangeRequestScreen(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: _ActionCard(
                        icon: Icons.emergency_rounded,
                        label: 'Emergency Alert',
                        subtitle: 'Capture and send an incident immediately',
                        color: AppColors.error,
                        horizontal: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const IncidentReportScreen(),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── My Schedule ───────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: _SectionLabel(label: 'MY SCHEDULE'),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      child: _SchedulesCard(userId: user.id),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Status card ─────────────────────────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.displayName,
    required this.isActive,
    required this.employmentCategory,
  });
  final String displayName;
  final bool isActive;
  final String employmentCategory;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isActive
              ? [const Color(0xFFDC2626), const Color(0xFFB91C1C)]
              : [const Color(0xFF374151), const Color(0xFF1F2937)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color:
                (isActive ? const Color(0xFFDC2626) : const Color(0xFF374151))
                    .withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isActive ? Icons.shield_rounded : Icons.block_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFFF87171),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isActive
                            ? '${employmentCategory == 'contract' ? 'Contract' : 'Regular'} Guard • Active'
                            : 'Account Disabled',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Action card ─────────────────────────────────────────────────────────────
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.horizontal = false,
    this.emphasized = false,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool horizontal;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final iconBox = Container(
      width: horizontal ? 46 : 44,
      height: horizontal ? 46 : 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: emphasized ? 0.16 : 0.11),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: color, size: horizontal ? 23 : 22),
    );
    final labels = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: EdgeInsets.all(horizontal ? 16 : 17),
          decoration: AppColors.card(
            radius: 18,
            color: emphasized
                ? color.withValues(alpha: 0.035)
                : AppColors.surface,
            borderColor: emphasized
                ? color.withValues(alpha: 0.22)
                : AppColors.border,
          ),
          child: horizontal
              ? Row(
                  children: [
                    iconBox,
                    const SizedBox(width: 14),
                    Expanded(child: labels),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: color.withValues(alpha: 0.7),
                      size: 16,
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [iconBox, const SizedBox(height: 12), labels],
                ),
        ),
      ),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        label,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(child: Container(height: 1, color: AppColors.border)),
    ],
  );
}

// ─── Glass button ─────────────────────────────────────────────────────────────
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GuardIconButton(
    icon: icon,
    tooltip: icon == Icons.logout_rounded ? 'Sign out' : 'Action',
    color: color,
    onPressed: onTap,
  );
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.notifications, required this.onTap});

  final List<AppNotification> notifications;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = notifications.where((item) => item.isUnread).length;
    final hasCritical = notifications.any((item) => item.needsAcknowledgement);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GuardIconButton(
          icon: hasCritical
              ? Icons.notification_important_rounded
              : Icons.notifications_none_rounded,
          tooltip: hasCritical
              ? 'Critical notification awaiting acknowledgement'
              : '$unread unread notification${unread == 1 ? '' : 's'}',
          color: hasCritical ? AppColors.error : AppColors.primary,
          onPressed: onTap,
        ),
        if (unread > 0 || hasCritical)
          Positioned(
            top: -5,
            right: -5,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: hasCritical ? AppColors.error : AppColors.primary,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                hasCritical
                    ? '!'
                    : unread > 99
                    ? '99+'
                    : '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Schedules card ───────────────────────────────────────────────────────────
class _SchedulesCard extends StatelessWidget {
  const _SchedulesCard({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppColors.card(radius: 20),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('schedules')
            .stream(primaryKey: ['id'])
            .eq('user_id', userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 150,
              child: GuardLoadingView(label: 'Loading your schedule…'),
            );
          }

          if (snapshot.hasError) {
            return const GuardEmptyState(
              icon: Icons.sync_problem_rounded,
              title: 'Schedule unavailable',
              message:
                  'Could not load your duties. Check your connection and try again.',
            );
          }

          final schedules = snapshot.data ?? [];
          if (schedules.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    color: AppColors.textHint,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No schedules assigned yet',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Your admin assigns duty sites and times under Schedule.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final sorted = schedules.toList()
            ..sort(
              (a, b) => _scheduleSortKey(b).compareTo(_scheduleSortKey(a)),
            );

          return Column(
            children: sorted.map((schedule) {
              return _ScheduleTile(
                scheduleId: schedule['id'].toString(),
                data: schedule,
              );
            }).toList(),
          );
        },
      ),
    );
  }

  static bool _hasLocation(Map<String, dynamic> data) {
    final label = data['location_label']?.toString();
    if (label != null && label.isNotEmpty) return true;
    return false;
  }

  static String _locationLine(Map<String, dynamic> data) {
    final label = data['location_label']?.toString();
    final address = data['location_address']?.toString();
    if (label != null && label.isNotEmpty) {
      if (address != null && address.isNotEmpty) {
        return 'Duty site: $label\n$address';
      }
      return 'Duty site: $label';
    }
    return 'Duty site: not assigned — ask your admin';
  }

  static String _scheduleSortKey(Map<String, dynamic> data) {
    final start = _parseDateTime(data['start_at']);
    if (start != null) return start.toIso8601String();
    return '';
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }

  static String _formatTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$hour12:$minute $period';
  }

  static String _formatDate(DateTime dt) {
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
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  static String _formatDuration(DateTime start, DateTime end) {
    return AttendanceService.formatDurationLabel(start, end);
  }

  static ({String dateLine, String dutyHoursLine}) _formatScheduleLines(
    Map<String, dynamic> data,
  ) {
    final start = _parseDateTime(data['start_at']);
    final end = _parseDateTime(data['end_at']);
    if (start != null && end != null) {
      final sameDay =
          start.year == end.year &&
          start.month == end.month &&
          start.day == end.day;
      final dateLine = sameDay
          ? _formatDate(start)
          : '${_formatDate(start)} → ${_formatDate(end)}';
      final duration = _formatDuration(start, end);
      final dutyHoursLine =
          'Duty hours: ${_formatTime(start)} – ${_formatTime(end)} ($duration)';
      return (dateLine: dateLine, dutyHoursLine: dutyHoursLine);
    }

    return (dateLine: '—', dutyHoursLine: 'Duty hours: not set');
  }
}

// ─── Single schedule row with Mark as done ───────────────────────────────────
class _ScheduleTile extends StatefulWidget {
  const _ScheduleTile({required this.scheduleId, required this.data});

  final String scheduleId;
  final Map<String, dynamic> data;

  @override
  State<_ScheduleTile> createState() => _ScheduleTileState();
}

class _ScheduleTileState extends State<_ScheduleTile> {
  @override
  Widget build(BuildContext context) {
    final s = widget.data;
    const accent = AppColors.primary;
    final scheduleLines = _SchedulesCard._formatScheduleLines(s);
    final markedDone = ScheduleService.isMarkedDone(s);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  markedDone
                      ? Icons.check_circle_rounded
                      : Icons.schedule_rounded,
                  color: markedDone ? AppColors.success : accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            scheduleLines.dateLine,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (markedDone)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.success.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            child: const Text(
                              'Done',
                              style: TextStyle(
                                color: AppColors.success,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      scheduleLines.dutyHoursLine,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _SchedulesCard._locationLine(s),
                      style: TextStyle(
                        color: _SchedulesCard._hasLocation(s)
                            ? AppColors.textMuted
                            : AppColors.warning,
                        fontSize: 12,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!markedDone) ...[
            const SizedBox(height: 8),
            Text(
              ScheduleService.isScheduleEnded(s)
                  ? 'Time Out at the post to complete this duty.'
                  : 'Use Attendance at your scheduled post.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ] else if (markedDone) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      AccomplishmentReportScreen(scheduleId: widget.scheduleId),
                ),
              ),
              icon: const Icon(Icons.assignment_turned_in_outlined),
              label: const Text('Submit accomplishment report'),
            ),
          ],
        ],
      ),
    );
  }
}
