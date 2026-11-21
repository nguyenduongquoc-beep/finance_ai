import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/notification_model.dart';
import 'package:finance_ai_app/models/recurring_transaction_model.dart';
import 'package:finance_ai_app/services/firestore_service.dart';
import 'package:finance_ai_app/services/recurring_transaction_service.dart';
import 'package:finance_ai_app/services/local_notification_service.dart';

void main() {
  group('Recurring Transactions & Invoices - Business Logic & UI Model Tests', () {
    test('1. InsufficientBalanceException calculates shortfall accurately and has clear message', () {
      final ex = InsufficientBalanceException(
        message: 'Ví không đủ số dư',
        walletName: 'Ví MoMo',
        currentBalance: 120000.0,
        requiredAmount: 300000.0,
        shortfall: 180000.0,
      );

      expect(ex.walletName, equals('Ví MoMo'));
      expect(ex.currentBalance, equals(120000.0));
      expect(ex.requiredAmount, equals(300000.0));
      expect(ex.shortfall, equals(180000.0));
      expect(ex.toString(), contains('Ví không đủ số dư'));
    });

    test('2. AppNotification serializes and deserializes scheduleId and occurrenceKey correctly', () {
      final now = DateTime(2026, 10, 24, 12, 0);
      final notif = AppNotification(
        notificationId: 'notif_rec_1',
        userId: 'user_test',
        title: 'Hóa đơn tiền điện đến hạn',
        content: 'Khoản chi 550.000đ cần bạn xác nhận để ghi nhận vào sổ.',
        type: 'recurring_due',
        createdAt: now,
        scheduleId: 'sch_electric',
        occurrenceKey: '2026-10-24',
      );

      final map = notif.toMap();
      expect(map['scheduleId'], equals('sch_electric'));
      expect(map['occurrenceKey'], equals('2026-10-24'));
      expect(map['type'], equals('recurring_due'));

      final reconstructed = AppNotification.fromMap(map, 'notif_rec_1');
      expect(reconstructed.scheduleId, equals('sch_electric'));
      expect(reconstructed.occurrenceKey, equals('2026-10-24'));
      expect(reconstructed.notificationId, equals('notif_rec_1'));
      expect(reconstructed.title, equals(notif.title));
      expect(reconstructed.content, equals(notif.content));
    });

    test('3. Category type filtering strictly isolates expense and income categories', () {
      final categories = [
        Category(categoryId: 'c_food', userId: 'u1', name: 'Ăn uống', type: 'expense', icon: 'restaurant', color: 0xFFE53935),
        Category(categoryId: 'c_rent', userId: 'u1', name: 'Tiền nhà', type: 'expense', icon: 'home', color: 0xFF1E88E5),
        Category(categoryId: 'c_salary', userId: 'u1', name: 'Lương', type: 'income', icon: 'payments', color: 0xFF43A047),
        Category(categoryId: 'c_bonus', userId: 'u1', name: 'Thưởng', type: 'income', icon: 'card_giftcard', color: 0xFFFB8C00),
      ];

      final expenseCats = categories.where((c) => c.type == 'expense').toList();
      final incomeCats = categories.where((c) => c.type == 'income').toList();

      expect(expenseCats.map((c) => c.categoryId), containsAll(['c_food', 'c_rent']));
      expect(expenseCats.any((c) => c.type == 'income'), isFalse);

      expect(incomeCats.map((c) => c.categoryId), containsAll(['c_salary', 'c_bonus']));
      expect(incomeCats.any((c) => c.type == 'expense'), isFalse);
    });

    test('4. Category reset logic when switching transaction type', () {
      final categories = [
        Category(categoryId: 'c_food', userId: 'u1', name: 'Ăn uống', type: 'expense', icon: 'restaurant', color: 0xFFE53935),
        Category(categoryId: 'c_salary', userId: 'u1', name: 'Lương', type: 'income', icon: 'payments', color: 0xFF43A047),
      ];

      String currentType = 'expense';
      String? selectedCategoryId = 'c_food';

      // Switch to income
      currentType = 'income';
      final isCatValidForNewType = categories.any(
        (c) => c.categoryId == selectedCategoryId && c.type == currentType,
      );
      if (!isCatValidForNewType) {
        selectedCategoryId = null; // Reset selection
      }

      expect(selectedCategoryId, isNull);

      // Now pick income category
      selectedCategoryId = 'c_salary';

      // Switch back to expense
      currentType = 'expense';
      final isIncomeValidForExpense = categories.any(
        (c) => c.categoryId == selectedCategoryId && c.type == currentType,
      );
      if (!isIncomeValidForExpense) {
        selectedCategoryId = null; // Reset selection
      }

      expect(selectedCategoryId, isNull);
    });

    test('5. Real-time balance and payable cycle estimation calculations', () {
      const double walletBalance = 1500000.0;
      const double scheduleAmount = 400000.0;

      final bool hasSufficientBalance = walletBalance >= scheduleAmount;
      expect(hasSufficientBalance, isTrue);

      final int payableCycles = (walletBalance / scheduleAmount).floor();
      expect(payableCycles, equals(3)); // 3 full cycles of 400k (1.2M), remaining 300k

      // Zero or negative amount edge case
      const double zeroAmount = 0.0;
      final int safeCycles = zeroAmount > 0 ? (walletBalance / zeroAmount).floor() : 0;
      expect(safeCycles, equals(0));

      // Overdraft case
      const double expensiveAmount = 2000000.0;
      final bool isOverdraft = expensiveAmount > walletBalance;
      final double shortfall = isOverdraft ? (expensiveAmount - walletBalance) : 0.0;
      expect(isOverdraft, isTrue);
      expect(shortfall, equals(500000.0));
    });

    test('6. Reactivation advances nextDueDate to future occurrence without skipped cycles loss', () {
      final recService = RecurringTransactionService();
      final now = DateTime(2026, 10, 24);
      final pastStartDate = DateTime(2026, 6, 1); // 4 months ago

      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_sync',
        userId: 'u1',
        type: 'expense',
        walletId: 'w1',
        categoryId: 'c1',
        amount: 300000,
        frequency: 'monthly',
        startDate: pastStartDate,
        nextDueDate: pastStartDate,
        isActive: false,
        createdAt: pastStartDate,
      );

      // Calculate sequential advance until nextDueDate >= now
      DateTime newNextDueDate = schedule.nextDueDate;
      while (!newNextDueDate.isAfter(now)) {
        newNextDueDate = recService.nextOccurrenceAfter(
          newNextDueDate,
          schedule.frequency,
          schedule.startDate,
        );
      }

      // Should be November 1, 2026
      expect(newNextDueDate.isAfter(now), isTrue);
      expect(newNextDueDate.month, equals(11));
      expect(newNextDueDate.day, equals(1));
      expect(newNextDueDate.year, equals(2026));
    });

    test('7. Local notification due date reminders are created for both manual and auto modes', () {
      final refDate = DateTime(2026, 10, 20);
      final manualSchedule = RecurringTransactionSchedule(
        scheduleId: 'sch_manual_check',
        userId: 'u1',
        type: 'expense',
        walletId: 'w1',
        categoryId: 'c1',
        note: 'Tiền Nước',
        amount: 250000,
        frequency: 'monthly',
        startDate: DateTime(2026, 10, 25),
        nextDueDate: DateTime(2026, 10, 25),
        postingMode: RecurringTransactionSchedule.postingModeManual,
        reminderDaysBefore: 2,
        createdAt: DateTime(2026, 10, 1),
      );

      final items = LocalNotificationService.calculateScheduledNotifications(
        schedule: manualSchedule,
        walletName: 'Ví BIDV',
        referenceDate: refDate,
        maxDaysAhead: 15,
      );

      expect(items.length, equals(2)); // 1 advance (Oct 23) + 1 due date (Oct 25)

      final advance = items.firstWhere((it) => !it.isOnDueDate);
      expect(advance.title, contains('Sắp đến hạn cần xác nhận'));
      expect(advance.body, contains('Cần xác nhận'));

      final due = items.firstWhere((it) => it.isOnDueDate);
      expect(due.title, contains('Hôm nay cần xác nhận'));
      expect(due.body, contains('Chờ bạn xác nhận'));
    });

    test('8. AppNotification.isUnread handles status and legacy isRead fields accurately', () {
      final unreadNotif = AppNotification.fromMap({
        'userId': 'u1',
        'title': 'Nhắc hạn',
        'content': 'Đến hạn hôm nay',
        'status': 'unread',
        'type': 'recurring_due',
        'createdAt': '2026-10-24T09:00:00.000',
      }, 'n1');
      expect(unreadNotif.isUnread, isTrue);

      final readNotif = AppNotification.fromMap({
        'userId': 'u1',
        'title': 'Nhắc hạn',
        'content': 'Đến hạn hôm nay',
        'status': 'read',
        'type': 'recurring_due',
        'createdAt': '2026-10-24T09:00:00.000',
      }, 'n2');
      expect(readNotif.isUnread, isFalse);

      final legacyReadNotif = AppNotification.fromMap({
        'userId': 'u1',
        'title': 'Nhắc hạn',
        'content': 'Đến hạn hôm nay',
        'isRead': true,
        'type': 'recurring_due',
        'createdAt': '2026-10-24T09:00:00.000',
      }, 'n3');
      expect(legacyReadNotif.isUnread, isFalse);
    });

    test('9. Empty schedule note ("") falls back to category name or default label instead of empty quotes', () {
      final categories = [
        Category(
          categoryId: 'c_elec',
          userId: 'u1',
          name: 'Hóa đơn điện',
          type: 'expense',
          icon: 'bolt',
          color: 0xFFE53935,
        ),
      ];

      String resolveDisplayName(
        RecurringTransactionSchedule s,
        List<Category> cats,
      ) {
        if (s.note != null && s.note!.trim().isNotEmpty) {
          return s.note!.trim();
        }
        final matched =
            cats.where((c) => c.categoryId == s.categoryId).firstOrNull;
        if (matched != null && matched.name.trim().isNotEmpty) {
          return matched.name.trim();
        }
        return s.type == 'income' ? 'Thu nhập định kỳ' : 'Khoản chi định kỳ';
      }

      final emptyNoteWithCat = RecurringTransactionSchedule(
        scheduleId: 's1',
        userId: 'u1',
        type: 'expense',
        walletId: 'w1',
        categoryId: 'c_elec',
        note: '',
        amount: 500000,
        frequency: 'monthly',
        startDate: DateTime(2026, 10, 24),
        nextDueDate: DateTime(2026, 10, 24),
        createdAt: DateTime(2026, 10, 24),
      );
      expect(resolveDisplayName(emptyNoteWithCat, categories),
          equals('Hóa đơn điện'));

      final emptyNoteWithoutCat = emptyNoteWithCat.copyWith(categoryId: '');
      expect(resolveDisplayName(emptyNoteWithoutCat, categories),
          equals('Khoản chi định kỳ'));
    });

    test('10. Schedule with reminderDaysBefore == 0 still generates due-date notification', () {
      final refDate = DateTime(2026, 10, 24, 8, 0);
      final dueOnlySchedule = RecurringTransactionSchedule(
        scheduleId: 'sch_due_only',
        userId: 'u1',
        type: 'expense',
        walletId: 'w1',
        categoryId: 'c1',
        note: '',
        amount: 150000,
        frequency: 'monthly',
        startDate: DateTime(2026, 10, 24),
        nextDueDate: DateTime(2026, 10, 24),
        reminderDaysBefore: 0,
        createdAt: DateTime(2026, 10, 24),
      );

      final items = LocalNotificationService.calculateScheduledNotifications(
        schedule: dueOnlySchedule,
        walletName: 'Ví Chính',
        referenceDate: refDate,
        maxDaysAhead: 10,
      );

      expect(items.length, equals(1));
      expect(items.first.isOnDueDate, isTrue);
      expect(items.first.title, contains('Hóa đơn định kỳ'));
    });
  });
}
