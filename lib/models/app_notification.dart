class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.priority,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.requiresAcknowledgement,
    this.actionKey,
    this.entityId,
    this.readAt,
    this.acknowledgedAt,
    this.expiresAt,
    this.metadata = const {},
  });

  final String id;
  final String kind;
  final String priority;
  final String title;
  final String message;
  final String? actionKey;
  final String? entityId;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? acknowledgedAt;
  final DateTime? expiresAt;
  final bool requiresAcknowledgement;
  final Map<String, dynamic> metadata;

  bool get isUnread => readAt == null;
  bool get isCritical => priority == 'critical';
  bool get needsAcknowledgement =>
      requiresAcknowledgement && acknowledgedAt == null;
  bool get isExpired => expiresAt?.isBefore(DateTime.now().toUtc()) ?? false;

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    DateTime? parseOptional(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString())?.toUtc();
    }

    final createdAt = parseOptional(map['created_at']);
    return AppNotification(
      id: map['id']?.toString() ?? '',
      kind: map['kind']?.toString() ?? 'system',
      priority: map['priority']?.toString() ?? 'normal',
      title: map['title']?.toString() ?? 'Security Agency Management System',
      message: map['message']?.toString() ?? '',
      actionKey: map['action_key']?.toString(),
      entityId: map['entity_id']?.toString(),
      createdAt:
          createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      readAt: parseOptional(map['read_at']),
      acknowledgedAt: parseOptional(map['acknowledged_at']),
      expiresAt: parseOptional(map['expires_at']),
      requiresAcknowledgement: map['requires_ack'] == true,
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : const {},
    );
  }
}
