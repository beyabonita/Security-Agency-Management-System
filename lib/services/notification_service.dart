import 'package:flutter_application_1/models/app_notification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class NotificationService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Stream<List<AppNotification>> watch(String userId) {
    return _client
        .from('user_notifications')
        .stream(primaryKey: ['id'])
        .eq('recipient_id', userId)
        .order('created_at', ascending: false)
        .limit(75)
        .map(
          (rows) => rows
              .map(AppNotification.fromMap)
              .where((notification) => !notification.isExpired)
              .toList(growable: false),
        );
  }

  static Future<void> markRead(String notificationId) async {
    await _client.rpc(
      'mark_notification_read',
      params: {'p_notification_id': notificationId},
    );
  }

  static Future<void> acknowledge(String notificationId) async {
    await _client.rpc(
      'acknowledge_notification',
      params: {'p_notification_id': notificationId},
    );
  }

  static Future<int> markAllRead() async {
    final result = await _client.rpc('mark_all_notifications_read');
    return result is num ? result.toInt() : 0;
  }
}
