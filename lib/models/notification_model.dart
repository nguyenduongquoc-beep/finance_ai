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
  final String? titleKey;
  final Map<String, String>? titleParams;
  final String? contentKey;
  final Map<String, String>? contentParams;

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
    this.titleKey,
    this.titleParams,
    this.contentKey,
    this.contentParams,
  });

  bool get isUnread => status.trim().toLowerCase() != 'read';

  static Map<String, String>? _parseStringMap(dynamic raw) {
    if (raw is! Map) return null;
    final parsed = <String, String>{};
    raw.forEach((key, value) {
      if (key != null && value != null) {
        parsed[key.toString()] = value.toString();
      }
    });
    return parsed.isEmpty ? null : parsed;
  }

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

    final rawContent = map['content'];
    final legacyBody = map['body'];
    final resolvedContent =
        (rawContent is String && rawContent.trim().isNotEmpty)
            ? rawContent
            : (legacyBody is String
                ? legacyBody
                : (rawContent?.toString() ?? ''));

    return AppNotification(
      notificationId: id,
      userId: map['userId'] ?? '',
      title: map['title'] ?? '',
      content: resolvedContent,
      status: resolvedStatus,
      type: map['type'] ?? 'reminder',
      createdAt: parsedDate,
      scheduleId: map['scheduleId'],
      occurrenceKey: map['occurrenceKey'],
      titleKey: map['titleKey']?.toString(),
      titleParams: _parseStringMap(map['titleParams']),
      contentKey: map['contentKey']?.toString(),
      contentParams: _parseStringMap(map['contentParams']),
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
      if (titleKey != null) 'titleKey': titleKey,
      if (titleParams != null && titleParams!.isNotEmpty)
        'titleParams': titleParams,
      if (contentKey != null) 'contentKey': contentKey,
      if (contentParams != null && contentParams!.isNotEmpty)
        'contentParams': contentParams,
    };
  }
}
