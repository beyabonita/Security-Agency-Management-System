import 'package:flutter_application_1/models/app_notification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppNotification', () {
    test('maps critical acknowledgement state and metadata', () {
      final notification = AppNotification.fromMap({
        'id': 'notification-1',
        'kind': 'emergency',
        'priority': 'critical',
        'title': 'Emergency alert',
        'message': 'Immediate review required.',
        'requires_ack': true,
        'created_at': '2026-08-23T01:02:03Z',
        'metadata': {'category': 'fire'},
      });

      expect(notification.isCritical, isTrue);
      expect(notification.isUnread, isTrue);
      expect(notification.needsAcknowledgement, isTrue);
      expect(notification.metadata['category'], 'fire');
      expect(notification.createdAt.isUtc, isTrue);
    });

    test('treats acknowledged and expired notifications correctly', () {
      final notification = AppNotification.fromMap({
        'id': 'notification-2',
        'kind': 'system',
        'priority': 'critical',
        'title': 'Maintenance',
        'message': 'Maintenance completed.',
        'requires_ack': true,
        'read_at': '2026-08-22T01:02:03Z',
        'acknowledged_at': '2026-08-22T01:03:03Z',
        'created_at': '2026-08-22T01:02:03Z',
        'expires_at': '2026-08-22T02:02:03Z',
      });

      expect(notification.isUnread, isFalse);
      expect(notification.needsAcknowledgement, isFalse);
      expect(notification.isExpired, isTrue);
    });

    test('uses safe defaults for optional values', () {
      final notification = AppNotification.fromMap({
        'id': 'notification-3',
        'title': 'Account update',
        'message': 'Your account was updated.',
      });

      expect(notification.kind, 'system');
      expect(notification.priority, 'normal');
      expect(notification.metadata, isEmpty);
      expect(notification.requiresAcknowledgement, isFalse);
    });
  });
}
