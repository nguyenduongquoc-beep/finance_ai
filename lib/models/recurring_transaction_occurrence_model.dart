/// ============================================================
/// RECURRING TRANSACTION OCCURRENCE AUDIT MODEL
/// Firestore collection: recurringTransactionOccurrences/{scheduleId}_{occurrenceKey}
/// ============================================================
class RecurringTransactionOccurrence {
  final String userId;
  final String scheduleId;
  final String occurrenceKey;
  final DateTime scheduledDate;
  final String action; // confirmed | skipped | deferred
  final DateTime actionAt;
  final String? transactionId;
  final DateTime? deferredTo;

  RecurringTransactionOccurrence({
    required this.userId,
    required this.scheduleId,
    required this.occurrenceKey,
    required this.scheduledDate,
    required this.action,
    required this.actionAt,
    this.transactionId,
    this.deferredTo,
  });

  factory RecurringTransactionOccurrence.fromMap(
      Map<String, dynamic> map, String id) {
    return RecurringTransactionOccurrence(
      userId: map['userId'] ?? '',
      scheduleId: map['scheduleId'] ?? '',
      occurrenceKey: map['occurrenceKey'] ?? '',
      scheduledDate: map['scheduledDate'] != null
          ? DateTime.parse(map['scheduledDate'])
          : DateTime.now(),
      action: map['action'] ?? 'confirmed',
      actionAt: map['actionAt'] != null
          ? DateTime.parse(map['actionAt'])
          : DateTime.now(),
      transactionId: map['transactionId'],
      deferredTo: map['deferredTo'] != null
          ? DateTime.parse(map['deferredTo'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'scheduleId': scheduleId,
      'occurrenceKey': occurrenceKey,
      'scheduledDate': scheduledDate.toIso8601String(),
      'action': action,
      'actionAt': actionAt.toIso8601String(),
      if (transactionId != null) 'transactionId': transactionId,
      if (deferredTo != null) 'deferredTo': deferredTo!.toIso8601String(),
    };
  }
}
