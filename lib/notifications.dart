import 'package:flutter/material.dart';
import 'package:flutter_application_1/duty_requests.dart';
import 'package:flutter_application_1/models/app_notification.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/widgets/guard_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _markingAll = false;

  Future<void> _markAll() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      final count = await NotificationService.markAllRead();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'No unread notifications.'
                : '$count notification${count == 1 ? '' : 's'} marked as read.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _openNotification(AppNotification notification) async {
    if (notification.needsAcknowledgement) {
      await _acknowledge(notification);
    } else if (notification.isUnread) {
      try {
        await NotificationService.markRead(notification.id);
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
        return;
      }
    }
    if (!mounted) return;
    if (notification.actionKey == 'shift_request') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ShiftChangeRequestScreen()),
      );
    }
  }

  Future<void> _acknowledge(AppNotification notification) async {
    try {
      await NotificationService.acknowledge(notification.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Critical notification acknowledged.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Scaffold(
      backgroundColor: AppColors.of(context).scaffold,
      body: SafeArea(
        child: GuardAmbientBackground(
          child: Column(
            children: [
              GuardPageTopBar(
                title: 'Notifications',
                subtitle: 'Duty updates and important alerts',
                onBack: () => Navigator.pop(context),
                trailing: TextButton(
                  onPressed: _markingAll || user == null ? null : _markAll,
                  child: Text(_markingAll ? 'Updating…' : 'Mark all read'),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: user == null
                    ? const GuardEmptyState(
                        icon: Icons.lock_outline_rounded,
                        title: 'Session expired',
                        message: 'Sign in again to view your notifications.',
                      )
                    : StreamBuilder<List<AppNotification>>(
                        stream: NotificationService.watch(user.id),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return const GuardEmptyState(
                              icon: Icons.notifications_off_outlined,
                              title: 'Notifications unavailable',
                              message:
                                  'Check your connection and try opening this page again.',
                            );
                          }
                          if (!snapshot.hasData) {
                            return const GuardLoadingView(
                              label: 'Loading notifications…',
                            );
                          }
                          final notifications = snapshot.data!;
                          if (notifications.isEmpty) {
                            return const GuardEmptyState(
                              icon: Icons.notifications_none_rounded,
                              title: 'You are all caught up',
                              message:
                                  'Schedule, assignment, request, and system updates will appear here.',
                            );
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 2, 20, 30),
                            itemCount: notifications.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final notification = notifications[index];
                              return _NotificationCard(
                                notification: notification,
                                onOpen: () => _openNotification(notification),
                                onAcknowledge: notification.needsAcknowledgement
                                    ? () => _acknowledge(notification)
                                    : null,
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onOpen,
    this.onAcknowledge,
  });

  final AppNotification notification;
  final VoidCallback onOpen;
  final VoidCallback? onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final color = _priorityColor(context, notification.priority);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: notification.isUnread
                ? color.withValues(alpha: 0.055)
                : AppColors.of(context).surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: notification.isCritical
                  ? color.withValues(alpha: 0.42)
                  : AppColors.of(context).border,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0B451014),
                blurRadius: 18,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  _kindIcon(notification.kind),
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              color: AppColors.of(context).text,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (notification.isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 4, left: 8),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      notification.message,
                      style: TextStyle(
                        color: AppColors.of(context).textMuted,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _PriorityChip(
                          priority: notification.priority,
                          color: color,
                        ),
                        Text(
                          _relativeTime(notification.createdAt),
                          style: TextStyle(
                            color: AppColors.of(context).textHint,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (onAcknowledge != null)
                          TextButton.icon(
                            onPressed: onAcknowledge,
                            icon: const Icon(
                              Icons.verified_user_outlined,
                              size: 16,
                            ),
                            label: const Text('Acknowledge'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority, required this.color});
  final String priority;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      priority.toUpperCase(),
      style: TextStyle(
        color: color,
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    ),
  );
}

Color _priorityColor(BuildContext context, String priority) =>
    switch (priority) {
      'critical' => AppColors.of(context).error,
      'high' => AppColors.of(context).warning,
      'low' => AppColors.of(context).textMuted,
      _ => AppColors.of(context).accent,
    };

IconData _kindIcon(String kind) => switch (kind) {
  'emergency' => Icons.emergency_rounded,
  'incident_status' => Icons.health_and_safety_rounded,
  'schedule' => Icons.event_rounded,
  'assignment' => Icons.location_on_rounded,
  'shift_request' => Icons.swap_horiz_rounded,
  'accomplishment' => Icons.assignment_turned_in_rounded,
  'account' => Icons.manage_accounts_rounded,
  _ => Icons.campaign_rounded,
};

String _relativeTime(DateTime value) {
  final difference = DateTime.now().toUtc().difference(value.toUtc());
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes} min ago';
  if (difference.inDays < 1) return '${difference.inHours} hr ago';
  if (difference.inDays < 7) {
    return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
  }
  final local = value.toLocal();
  return '${local.month}/${local.day}/${local.year}';
}

String _friendlyError(Object error) {
  final message = error.toString().replaceFirst('Exception: ', '');
  return message.isEmpty
      ? 'The notification action could not be completed.'
      : message;
}
