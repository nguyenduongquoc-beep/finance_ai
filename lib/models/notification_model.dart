/// ============================================================
/// NOTIFICATION MODEL
/// Firestore collection: notifications/{notificationId}
/// ============================================================
class AppNotification {
  final String notificationId;
  final String userId;
  final String title;
  final String content;
  final String status; // read | unread
  final String
      type; // budget | reminder | ai_insight | recurring_due | recurring_reminder | recurring_failed | recurring_success
  final DateTime createdAt;
  final String? scheduleId;
  final String? occurrenceKey;

  AppNotification({
    required this.notificationId,
    required this.userId,
    required this.title,
    required this.content,
    this.status = 'unread',
    this.type = 'reminder',
    required this.createdAt,
    this.scheduleId,
    this.occurrenceKey,
  });

  bool get isUnread => status.trim().toLowerCase() != 'read';

  factory AppNotification.fromMap(Map<String, dynamic> map, String id) {
    DateTime parsedDate = DateTime.now();
    final rawDate = map['createdAt'];
    if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else if (rawDate != null) {
      try {
        parsedDate = (rawDate as dynamic).toDate();
      } catch (_) {}
    }

    String resolvedStatus = 'unread';
    final rawStatus = map['status'];
    if (rawStatus is String && rawStatus.trim().isNotEmpty) {
      resolvedStatus =
          rawStatus.trim().toLowerCase() == 'read' ? 'read' : 'unread';
    } else if (map['isRead'] is bool) {
      resolvedStatus = (map['isRead'] as bool) ? 'read' : 'unread';
    }

    return AppNotification(
      notificationId: id,
      userId: map['userId'] ?? '',
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      status: resolvedStatus,
      type: map['type'] ?? 'reminder',
      createdAt: parsedDate,
      scheduleId: map['scheduleId'],
      occurrenceKey: map['occurrenceKey'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'title': title,
      'content': content,
      'status': status,
      'type': type,
      'createdAt': createdAt.toIso8601String(),
      if (scheduleId != null) 'scheduleId': scheduleId,
      if (occurrenceKey != null) 'occurrenceKey': occurrenceKey,
    };
  }
}
