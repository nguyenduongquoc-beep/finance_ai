import '../models/recurring_transaction_model.dart';

/// Lớp hỗ trợ chứa 1 kỳ sắp tới của 1 schedule
class UpcomingOccurrence {
  final RecurringTransactionSchedule schedule;
  final DateTime dueDate;

  const UpcomingOccurrence({
    required this.schedule,
    required this.dueDate,
  });
}

/// Kết quả tổng hợp thu/chi định kỳ còn lại trong phần cuối tháng
class PlannedRemainingAmounts {
  final double plannedRemainingIncome;
  final double plannedRemainingExpense;

  const PlannedRemainingAmounts({
    required this.plannedRemainingIncome,
    required this.plannedRemainingExpense,
  });
}

/// Kết quả đánh giá thời hạn chờ xác nhận 3 ngày (grace period) cho lịch manualConfirmation
class ManualGraceEvaluation {
  final RecurringTransactionSchedule schedule;
  final List<DateTime> skippedDates;
  final DateTime newNextDueDate;
  final int daysOverdueOnCurrentCycle;
  final int remainingGraceDays;
  final bool isCurrentlyDueWithinGrace;

  const ManualGraceEvaluation({
    required this.schedule,
    required this.skippedDates,
    required this.newNextDueDate,
    required this.daysOverdueOnCurrentCycle,
    required this.remainingGraceDays,
    required this.isCurrentlyDueWithinGrace,
  });

  bool get wasAutoSkipped => skippedDates.isNotEmpty;
}

/// ============================================================
/// RECURRING TRANSACTION SERVICE (DART THUẦN — KHÔNG IMPORT FIREBASE)
/// ============================================================
class RecurringTransactionService {
  /// Số ngày chờ xử lý (grace period) đối với lịch cần người dùng xác nhận,
  /// được tính từ ngày đến hạn thực tế (nextDueDate).
  static const int manualConfirmationGraceDays = 3;

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Chênh lệch số ngày theo lịch (dùng UTC date-only để tránh sai lệch DST).
  static int calendarDaysBetween(DateTime fromDate, DateTime toDate) {
    final fromUtc = DateTime.utc(fromDate.year, fromDate.month, fromDate.day);
    final toUtc = DateTime.utc(toDate.year, toDate.month, toDate.day);
    return toUtc.difference(fromUtc).inDays;
  }

  /// Đánh giá chu kỳ chờ xác nhận 3 ngày cho lịch `manualConfirmation`.
  /// - Chỉ áp dụng cho `isActive && postingMode == postingModeManual`.
  /// - Tuyệt đối KHÔNG áp dụng cho `postingModeAuto`.
  /// - Mốc 3 ngày luôn tính từ `schedule.nextDueDate` thực tế, KHÔNG tính từ `reminderDaysBefore`.
  ManualGraceEvaluation evaluateManualGracePeriod({
    required RecurringTransactionSchedule schedule,
    DateTime? referenceDate,
    int graceDays = manualConfirmationGraceDays,
    int catchUpCap = 120,
  }) {
    final ref = dateOnly(referenceDate ?? DateTime.now());
    var cursor = dateOnly(schedule.nextDueDate);

    if (!schedule.isActive ||
        schedule.postingMode != RecurringTransactionSchedule.postingModeManual) {
      final diff = calendarDaysBetween(cursor, ref);
      return ManualGraceEvaluation(
        schedule: schedule,
        skippedDates: const [],
        newNextDueDate: schedule.nextDueDate,
        daysOverdueOnCurrentCycle: diff,
        remainingGraceDays: 0,
        isCurrentlyDueWithinGrace: false,
      );
    }

    final skipped = <DateTime>[];
    var guard = 0;
    while (calendarDaysBetween(cursor, ref) >= graceDays &&
        guard < catchUpCap) {
      skipped.add(cursor);
      final nextCursor = nextOccurrenceAfter(
        DateTime(
          cursor.year,
          cursor.month,
          cursor.day,
          schedule.startDate.hour,
          schedule.startDate.minute,
          schedule.startDate.second,
        ),
        schedule.frequency,
        schedule.startDate,
      );
      cursor = dateOnly(nextCursor);
      guard++;
    }

    final newNextDueDate = skipped.isEmpty
        ? schedule.nextDueDate
        : DateTime(
            cursor.year,
            cursor.month,
            cursor.day,
            schedule.nextDueDate.hour,
            schedule.nextDueDate.minute,
            schedule.nextDueDate.second,
          );

    final daysOverdue = calendarDaysBetween(cursor, ref);
    final isWithinGrace = daysOverdue >= 0 && daysOverdue < graceDays;
    final remaining = isWithinGrace
        ? (graceDays - daysOverdue).clamp(0, graceDays)
        : 0;

    return ManualGraceEvaluation(
      schedule: schedule,
      skippedDates: skipped,
      newNextDueDate: newNextDueDate,
      daysOverdueOnCurrentCycle: daysOverdue,
      remainingGraceDays: remaining,
      isCurrentlyDueWithinGrace: isWithinGrace,
    );
  }

  /// Số ngày còn lại trong cửa sổ xác nhận 3 ngày (0..3) cho kỳ hiện tại.
  int manualConfirmationRemainingGraceDays(
    RecurringTransactionSchedule schedule, {
    DateTime? referenceDate,
  }) {
    final eval = evaluateManualGracePeriod(
      schedule: schedule,
      referenceDate: referenceDate,
    );
    return eval.remainingGraceDays;
  }

  /// Sinh khóa kỳ hạn từ DateTime (VD: "2026-09-30")
  static String getOccurrenceKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Sinh document ID xác định cho transaction lặp: `recurring_{scheduleId}_{occurrenceKey}`
  static String buildTransactionId(String scheduleId, DateTime occurrenceDate) {
    final key = getOccurrenceKey(occurrenceDate);
    return 'recurring_${scheduleId}_$key';
  }

  /// Tính ngày đến hạn tiếp theo strictly sau [fromDate]
  DateTime nextOccurrenceAfter(
      DateTime fromDate, String frequency, DateTime startDate) {
    if (frequency == 'weekly') {
      var nextDate = DateTime(fromDate.year, fromDate.month, fromDate.day + 1);
      while (nextDate.weekday != startDate.weekday) {
        nextDate = nextDate.add(const Duration(days: 1));
      }
      return DateTime(
        nextDate.year,
        nextDate.month,
        nextDate.day,
        startDate.hour,
        startDate.minute,
        startDate.second,
      );
    } else {
      // Monthly recurrence
      int targetYear = fromDate.year;
      int targetMonth = fromDate.month + 1;
      if (targetMonth > 12) {
        targetYear++;
        targetMonth = 1;
      }

      while (true) {
        final lastDayOfTargetMonth =
            DateTime(targetYear, targetMonth + 1, 0).day;
        final targetDay = startDate.day.clamp(1, lastDayOfTargetMonth);
        final candidate = DateTime(
          targetYear,
          targetMonth,
          targetDay,
          startDate.hour,
          startDate.minute,
          startDate.second,
        );

        if (candidate.isAfter(fromDate)) {
          return candidate;
        }

        targetMonth++;
        if (targetMonth > 12) {
          targetYear++;
          targetMonth = 1;
        }
      }
    }
  }

  /// Trả về danh sách các kỳ đến hạn <= [referenceDate] từ nextDueDate của schedule
  List<DateTime> dueOccurrences({
    required RecurringTransactionSchedule schedule,
    required DateTime referenceDate,
    int catchUpCap = 12,
  }) {
    if (!schedule.isActive) return [];

    final results = <DateTime>[];
    var current = schedule.nextDueDate;

    // So sánh theo mốc thời gian / ngày
    while (!current.isAfter(referenceDate) && results.length < catchUpCap) {
      results.add(current);
      final next =
          nextOccurrenceAfter(current, schedule.frequency, schedule.startDate);
      if (!next.isAfter(current)) break; // Safety against infinite loop
      current = next;
    }

    return results;
  }

  /// Trả về danh sách ngày đến hạn của 1 schedule trong khoảng N ngày tới (từ today đến today + daysAhead)
  List<DateTime> nextOccurrencesInWindow({
    required RecurringTransactionSchedule schedule,
    required DateTime referenceDate,
    required int daysAhead,
  }) {
    if (!schedule.isActive) return [];

    final results = <DateTime>[];
    final windowStart = DateTime(
        referenceDate.year, referenceDate.month, referenceDate.day);
    final windowEnd = DateTime(referenceDate.year, referenceDate.month,
        referenceDate.day + daysAhead, 23, 59, 59);

    var current = schedule.nextDueDate;
    while (current.isBefore(windowStart)) {
      final next =
          nextOccurrenceAfter(current, schedule.frequency, schedule.startDate);
      if (!next.isAfter(current)) break;
      current = next;
    }

    while (!current.isAfter(windowEnd)) {
      results.add(current);
      final next =
          nextOccurrenceAfter(current, schedule.frequency, schedule.startDate);
      if (!next.isAfter(current)) break;
      current = next;
    }

    return results;
  }

  /// Trả về các kỳ sắp đến hạn từ (referenceDate + 1 ngày) tới (referenceDate + daysAhead)
  List<UpcomingOccurrence> upcomingOccurrences({
    required List<RecurringTransactionSchedule> schedules,
    required DateTime referenceDate,
    required int daysAhead,
  }) {
    final results = <UpcomingOccurrence>[];
    final windowStart = DateTime(
        referenceDate.year, referenceDate.month, referenceDate.day + 1);
    final windowEnd = DateTime(referenceDate.year, referenceDate.month,
        referenceDate.day + daysAhead, 23, 59, 59);

    for (final schedule in schedules.where((s) => s.isActive)) {
      var current = schedule.nextDueDate;
      // Advance to window or referenceDate
      while (current.isBefore(windowStart)) {
        current = nextOccurrenceAfter(
            current, schedule.frequency, schedule.startDate);
      }

      while (!current.isAfter(windowEnd)) {
        results.add(UpcomingOccurrence(schedule: schedule, dueDate: current));
        current = nextOccurrenceAfter(
            current, schedule.frequency, schedule.startDate);
      }
    }

    results.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return results;
  }

  /// Tính tổng thu/chi định kỳ còn lại trong phần cuối tháng hiện tại
  /// CHỈ TÍNH CÁC KỲ CHƯA PHÁT SINH VÀ CÓ NGÀY ĐẾN HẠN > referenceDate (từ ngày mai đến cuối tháng)
  PlannedRemainingAmounts computePlannedRemainingAmounts({
    required List<RecurringTransactionSchedule> schedules,
    required DateTime referenceDate,
  }) {
    double plannedIncome = 0;
    double plannedExpense = 0;

    final windowStart = DateTime(
        referenceDate.year, referenceDate.month, referenceDate.day + 1);
    final monthEnd =
        DateTime(referenceDate.year, referenceDate.month + 1, 0, 23, 59, 59);

    if (windowStart.isAfter(monthEnd)) {
      return const PlannedRemainingAmounts(
        plannedRemainingIncome: 0,
        plannedRemainingExpense: 0,
      );
    }

    for (final schedule in schedules.where((s) => s.isActive)) {
      var current = schedule.nextDueDate;
      // Skip overdue / past occurrences
      while (current.isBefore(windowStart)) {
        current = nextOccurrenceAfter(
            current, schedule.frequency, schedule.startDate);
      }

      while (!current.isAfter(monthEnd)) {
        if (schedule.type == 'income') {
          plannedIncome += schedule.amount;
        } else if (schedule.type == 'expense') {
          plannedExpense += schedule.amount;
        }
        current = nextOccurrenceAfter(
            current, schedule.frequency, schedule.startDate);
      }
    }

    return PlannedRemainingAmounts(
      plannedRemainingIncome: plannedIncome,
      plannedRemainingExpense: plannedExpense,
    );
  }
}
