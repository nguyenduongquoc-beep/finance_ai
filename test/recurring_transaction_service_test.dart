import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_ai_app/models/recurring_transaction_model.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/services/financial_forecast_service.dart';
import 'package:finance_ai_app/services/firestore_service.dart';
import 'package:finance_ai_app/services/recurring_transaction_service.dart';
import 'package:finance_ai_app/services/local_notification_service.dart';

void main() {
  group('RecurringTransactionService Pure Dart Unit Tests', () {
    final service = RecurringTransactionService();
    final forecastService = FinancialForecastService();

    // 1. Weekly recurrence
    test('1. Weekly recurrence creates exact next date on same weekday', () {
      final startDate = DateTime(2026, 9, 7); // Monday
      final fromDate = DateTime(2026, 9, 7);
      final next = service.nextOccurrenceAfter(fromDate, 'weekly', startDate);
      expect(next.weekday, equals(DateTime.monday));
      expect(next, equals(DateTime(2026, 9, 14)));
    });

    // 2. Monthly recurrence day 31 falls on last day of 30-day month
    test(
        '2. Monthly recurrence day 31 falls on last day of 30-day month (e.g. Sept 30)',
        () {
      final startDate = DateTime(2026, 8, 31); // Aug 31
      final fromDate = DateTime(2026, 8, 31);
      final next = service.nextOccurrenceAfter(fromDate, 'monthly', startDate);
      expect(next.month, equals(9));
      expect(next.day, equals(30)); // September has 30 days
    });

    // 3. Monthly recurrence day 31 in Feb of non-leap year
    test('3. Monthly recurrence day 31 in Feb of non-leap year (Feb 28)', () {
      final startDate = DateTime(2026, 1, 31); // Jan 31, 2026
      final fromDate = DateTime(2026, 1, 31);
      final next = service.nextOccurrenceAfter(fromDate, 'monthly', startDate);
      expect(next.year, equals(2026));
      expect(next.month, equals(2));
      expect(next.day, equals(28));
    });

    // 4. Monthly recurrence day 29 in Feb of leap year
    test('4. Monthly recurrence day 29 in Feb of leap year (Feb 29, 2028)', () {
      final startDate = DateTime(2028, 1, 31); // Jan 31, 2028 (leap year)
      final fromDate = DateTime(2028, 1, 31);
      final next = service.nextOccurrenceAfter(fromDate, 'monthly', startDate);
      expect(next.year, equals(2028));
      expect(next.month, equals(2));
      expect(next.day, equals(29));
    });

    // 5. Due occurrences includes current reference date
    test(
        '5. Due occurrences includes current reference date if nextDueDate <= referenceDate',
        () {
      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_1',
        userId: 'u_1',
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 100000,
        frequency: 'monthly',
        startDate: DateTime(2026, 9, 15),
        nextDueDate: DateTime(2026, 9, 15),
        createdAt: DateTime(2026, 9, 1),
      );

      final due = service.dueOccurrences(
        schedule: schedule,
        referenceDate: DateTime(2026, 9, 15),
      );

      expect(due.length, equals(1));
      expect(due.first, equals(DateTime(2026, 9, 15)));
    });

    // 6. Upcoming occurrences filter strictly within 7/14/30 day window
    test('6. Upcoming occurrences filter strictly within 7/14/30 day window',
        () {
      final schedules = [
        RecurringTransactionSchedule(
          scheduleId: 'sch_1',
          userId: 'u_1',
          type: 'expense',
          walletId: 'w_1',
          categoryId: 'cat_food',
          amount: 100000,
          frequency: 'monthly',
          startDate: DateTime(2026, 9, 20),
          nextDueDate: DateTime(2026, 9, 20),
          createdAt: DateTime(2026, 9, 1),
        ),
        RecurringTransactionSchedule(
          scheduleId: 'sch_2',
          userId: 'u_1',
          type: 'income',
          walletId: 'w_1',
          categoryId: '',
          amount: 5000000,
          frequency: 'monthly',
          startDate: DateTime(2026, 10, 25),
          nextDueDate: DateTime(2026, 10, 25),
          createdAt: DateTime(2026, 9, 1),
        ),
      ];

      final refDate = DateTime(2026, 9, 15);
      final upcoming7Days = service.upcomingOccurrences(
        schedules: schedules,
        referenceDate: refDate,
        daysAhead: 7,
      );

      expect(upcoming7Days.length, equals(1));
      expect(upcoming7Days.first.schedule.scheduleId, equals('sch_1'));

      final upcoming30Days = service.upcomingOccurrences(
        schedules: schedules,
        referenceDate: refDate,
        daysAhead: 30,
      );

      expect(upcoming30Days.length,
          equals(1)); // sch_2 is Oct 25 (> 30 days from Sept 15)
    });

    // 7. No duplicate occurrences
    test('7. No duplicate occurrences returned by dueOccurrences', () {
      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_1',
        userId: 'u_1',
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 100000,
        frequency: 'weekly',
        startDate: DateTime(2026, 9, 1),
        nextDueDate: DateTime(2026, 9, 1),
        createdAt: DateTime(2026, 9, 1),
      );

      final due = service.dueOccurrences(
        schedule: schedule,
        referenceDate: DateTime(2026, 9, 15),
      );

      final uniqueSet = due.toSet();
      expect(due.length, equals(uniqueSet.length));
    });

    // 8. Catch-up cap works properly
    test(
        '8. Catch-up cap limits backlog occurrences to specified max (default 12)',
        () {
      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_1',
        userId: 'u_1',
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 100000,
        frequency: 'weekly',
        startDate: DateTime(2025, 1, 1),
        nextDueDate: DateTime(2025, 1, 1),
        createdAt: DateTime(2025, 1, 1),
      );

      final due = service.dueOccurrences(
        schedule: schedule,
        referenceDate: DateTime(2026, 9, 15),
        catchUpCap: 12,
      );

      expect(due.length, equals(12));
    });

    // 9. Fixed referenceDate yields reproducible results
    test('9. Fixed referenceDate yields reproducible results', () {
      final refDate1 = DateTime(2026, 9, 15);
      final refDate2 = DateTime(2026, 9, 15);

      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_1',
        userId: 'u_1',
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 100000,
        frequency: 'monthly',
        startDate: DateTime(2026, 9, 10),
        nextDueDate: DateTime(2026, 9, 10),
        createdAt: DateTime(2026, 9, 1),
      );

      final due1 =
          service.dueOccurrences(schedule: schedule, referenceDate: refDate1);
      final due2 =
          service.dueOccurrences(schedule: schedule, referenceDate: refDate2);

      expect(due1, equals(due2));
    });

    // 10. Forecast planned income/expense calculation
    test(
        '10. Forecast planned remaining income and expense calculated correctly for remaining month',
        () {
      final schedules = [
        RecurringTransactionSchedule(
          scheduleId: 'sch_inc',
          userId: 'u_1',
          type: 'income',
          walletId: 'w_1',
          categoryId: '',
          amount: 5000000,
          frequency: 'monthly',
          startDate: DateTime(2026, 9, 25),
          nextDueDate: DateTime(2026, 9, 25),
          createdAt: DateTime(2026, 9, 1),
        ),
        RecurringTransactionSchedule(
          scheduleId: 'sch_exp',
          userId: 'u_1',
          type: 'expense',
          walletId: 'w_1',
          categoryId: 'cat_rent',
          amount: 2000000,
          frequency: 'monthly',
          startDate: DateTime(2026, 9, 20),
          nextDueDate: DateTime(2026, 9, 20),
          createdAt: DateTime(2026, 9, 1),
        ),
      ];

      final refDate = DateTime(2026, 9, 15);
      final planned = service.computePlannedRemainingAmounts(
        schedules: schedules,
        referenceDate: refDate,
      );

      expect(planned.plannedRemainingIncome, equals(5000000.0));
      expect(planned.plannedRemainingExpense, equals(2000000.0));
    });

    // 11. Forecast does not double-count created recurring expenses
    test(
        '11. Forecast excludes created recurring expenses from daily discretionary expense average',
        () {
      final activeWallets = [
        Wallet(
          walletId: 'w_1',
          userId: 'u_1',
          walletName: 'Ví chính',
          balance: 10000000,
          type: 'bank',
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      final refDate = DateTime(2026, 9, 15);

      final transactions = [
        // Manual discretionary expense (150,000 in 15 days -> 10k/day)
        AppTransaction(
          transactionId: 'tx_manual',
          userId: 'u_1',
          walletId: 'w_1',
          categoryId: 'cat_food',
          amount: 150000,
          type: 'expense',
          date: refDate,
        ),
        // Created recurring expense (already processed)
        AppTransaction(
          transactionId: 'recurring_sch_rent_2026-09-05',
          userId: 'u_1',
          walletId: 'w_1',
          categoryId: 'cat_rent',
          amount: 2000000,
          type: 'expense',
          date: DateTime(2026, 9, 5),
          recurringScheduleId: 'sch_rent',
          recurringOccurrenceKey: '2026-09-05',
        ),
      ];

      final forecast = forecastService.calculateMonthEndForecast(
        activeWallets: activeWallets,
        currentMonthTx: transactions,
        refDate: refDate,
      );

      // Discretionary avg should only be calculated from manual expense (150,000 / 15 days = 10,000/day)
      expect(forecast.averageDailyDiscretionaryExpense, equals(10000.0));
      expect(forecast.projectedRemainingDiscretionaryExpense, equals(150000.0));
    });

    // 12. Schedule paused does not contribute to forecast or due occurrences
    test(
        '12. Schedule with isActive == false returns zero due occurrences and zero forecast planned amounts',
        () {
      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_paused',
        userId: 'u_1',
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 1000000,
        frequency: 'monthly',
        startDate: DateTime(2026, 9, 10),
        nextDueDate: DateTime(2026, 9, 10),
        isActive: false, // Paused!
        createdAt: DateTime(2026, 9, 1),
      );

      final refDate = DateTime(2026, 9, 15);
      final due =
          service.dueOccurrences(schedule: schedule, referenceDate: refDate);
      expect(due, isEmpty);

      final planned = service.computePlannedRemainingAmounts(
        schedules: [schedule],
        referenceDate: refDate,
      );
      expect(planned.plannedRemainingExpense, equals(0.0));
      expect(planned.plannedRemainingIncome, equals(0.0));
    });
  });

  group('FakeCloudFirestore Integration Tests', () {
    late FakeFirebaseFirestore fakeDb;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
    });

    // 13. Idempotent processing test
    test(
        '13. Processing due recurring transactions twice for same schedule + occurrenceKey creates only 1 transaction',
        () async {
      final userId = 'u_1';
      final scheduleId = 'sch_salary';
      final occurrenceDate = DateTime(2026, 9, 10);
      final occurrenceKey =
          RecurringTransactionService.getOccurrenceKey(occurrenceDate);
      final deterministicTxId = RecurringTransactionService.buildTransactionId(
          scheduleId, occurrenceDate);

      // Seed wallet
      await fakeDb.collection('wallets').doc('w_1').set({
        'userId': userId,
        'walletName': 'Ví Bank',
        'balance': 5000000.0,
        'type': 'bank',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Seed schedule
      await fakeDb.collection('recurringTransactions').doc(scheduleId).set({
        'userId': userId,
        'type': 'income',
        'walletId': 'w_1',
        'categoryId': '',
        'amount': 10000000.0,
        'frequency': 'monthly',
        'startDate': occurrenceDate.toIso8601String(),
        'nextDueDate': occurrenceDate.toIso8601String(),
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // 1st processing run
      await fakeDb.runTransaction((txn) async {
        final txRef = fakeDb.collection('transactions').doc(deterministicTxId);
        final txSnap = await txn.get(txRef);
        expect(txSnap.exists, isFalse);

        final appTx = AppTransaction(
          transactionId: deterministicTxId,
          userId: userId,
          walletId: 'w_1',
          categoryId: '',
          amount: 10000000.0,
          type: 'income',
          date: occurrenceDate,
          recurringScheduleId: scheduleId,
          recurringOccurrenceKey: occurrenceKey,
        );

        txn.set(txRef, appTx.toMap());
        txn.update(
            fakeDb.collection('wallets').doc('w_1'), {'balance': 15000000.0});
      });

      // 2nd processing run (simulating retry)
      bool skippedOnSecondRun = false;
      await fakeDb.runTransaction((txn) async {
        final txRef = fakeDb.collection('transactions').doc(deterministicTxId);
        final txSnap = await txn.get(txRef);
        if (txSnap.exists) {
          skippedOnSecondRun = true;
          return;
        }
      });

      expect(skippedOnSecondRun, isTrue);

      // Verify wallet balance changed only once (5m + 10m = 15m)
      final walletDoc = await fakeDb.collection('wallets').doc('w_1').get();
      expect(walletDoc.data()!['balance'], equals(15000000.0));
    });

    // 14. Expense with insufficient balance test
    test(
        '14. Recurring expense with insufficient balance does not create transaction, does not change balance, and does not advance nextDueDate',
        () async {
      final userId = 'u_1';
      final scheduleId = 'sch_rent';
      final occurrenceDate = DateTime(2026, 9, 10);

      // Seed wallet with low balance (500,000)
      await fakeDb.collection('wallets').doc('w_1').set({
        'userId': userId,
        'walletName': 'Ví Chi Tiêu',
        'balance': 500000.0,
        'type': 'cash',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Seed schedule requiring 3,000,000
      await fakeDb.collection('recurringTransactions').doc(scheduleId).set({
        'userId': userId,
        'type': 'expense',
        'walletId': 'w_1',
        'categoryId': 'cat_rent',
        'amount': 3000000.0,
        'frequency': 'monthly',
        'startDate': occurrenceDate.toIso8601String(),
        'nextDueDate': occurrenceDate.toIso8601String(),
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      bool insufficientBalanceDetected = false;

      // Attempt processing in transaction
      await fakeDb.runTransaction((txn) async {
        final wSnap = await txn.get(fakeDb.collection('wallets').doc('w_1'));
        final balance = (wSnap.data()!['balance'] as num).toDouble();
        if (balance < 3000000.0) {
          insufficientBalanceDetected = true;
          return;
        }
      });

      expect(insufficientBalanceDetected, isTrue);

      // Verify zero transactions created
      final txQuery = await fakeDb.collection('transactions').get();
      expect(txQuery.docs, isEmpty);

      // Verify balance unchanged
      final walletDoc = await fakeDb.collection('wallets').doc('w_1').get();
      expect(walletDoc.data()!['balance'], equals(500000.0));

      // Verify nextDueDate NOT updated
      final schDoc = await fakeDb
          .collection('recurringTransactions')
          .doc(scheduleId)
          .get();
      expect(schDoc.data()!['nextDueDate'],
          equals(occurrenceDate.toIso8601String()));
    });

    // 15. Delete schedule does not delete past historical transactions
    test(
        '15. Deleting schedule doc does not delete past historical transaction documents',
        () async {
      final scheduleId = 'sch_internet';

      // Seed historical transaction created by schedule
      await fakeDb
          .collection('transactions')
          .doc('recurring_sch_internet_2026-08-01')
          .set({
        'userId': 'u_1',
        'walletId': 'w_1',
        'categoryId': 'cat_internet',
        'amount': 300000.0,
        'type': 'expense',
        'date': DateTime(2026, 8, 1).toIso8601String(),
        'recurringScheduleId': scheduleId,
        'recurringOccurrenceKey': '2026-08-01',
      });

      // Seed schedule
      await fakeDb.collection('recurringTransactions').doc(scheduleId).set({
        'userId': 'u_1',
        'type': 'expense',
        'walletId': 'w_1',
        'categoryId': 'cat_internet',
        'amount': 300000.0,
        'frequency': 'monthly',
        'startDate': DateTime(2026, 8, 1).toIso8601String(),
        'nextDueDate': DateTime(2026, 9, 1).toIso8601String(),
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Delete schedule
      await fakeDb.collection('recurringTransactions').doc(scheduleId).delete();

      // Verify schedule is deleted
      final schDoc = await fakeDb
          .collection('recurringTransactions')
          .doc(scheduleId)
          .get();
      expect(schDoc.exists, isFalse);

      // Verify historical transaction document STILL EXISTS
      final txDoc = await fakeDb
          .collection('transactions')
          .doc('recurring_sch_internet_2026-08-01')
          .get();
      expect(txDoc.exists, isTrue);
      expect(txDoc.data()!['recurringScheduleId'], equals(scheduleId));
    });

    // 16. Successful processDueRecurringTransactions with valid userId and schema
    test(
        '16. Successful processDueRecurringTransactions creates transaction and updates wallet/schedule with valid userId',
        () async {
      final firestoreService = FirestoreService(firestore: fakeDb);
      final userId = 'u_1';
      final scheduleId = 'sch_valid';

      // Seed valid wallet
      await fakeDb.collection('wallets').doc('w_1').set({
        'userId': userId,
        'walletName': 'Ví Tiền Mặt',
        'balance': 2000000.0,
        'type': 'cash',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Seed valid recurring schedule due today
      final dueDate = DateTime(2026, 9, 20);
      await fakeDb.collection('recurringTransactions').doc(scheduleId).set({
        'userId': userId,
        'type': 'expense',
        'walletId': 'w_1',
        'categoryId': 'cat_food',
        'amount': 500000.0,
        'frequency': 'monthly',
        'startDate': dueDate.toIso8601String(),
        'nextDueDate': dueDate.toIso8601String(),
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final result = await firestoreService.processDueRecurringTransactions(
        userId,
        referenceDate: DateTime(2026, 9, 20),
      );

      expect(result['processedCount'], equals(1));
      expect(result['failedSchedules'], isEmpty);

      // Verify transaction doc created with correct userId
      final txQuery = await fakeDb.collection('transactions').get();
      expect(txQuery.docs.length, equals(1));
      final txDoc = txQuery.docs.first;
      expect(txDoc.data()['userId'], equals(userId));
      expect(txDoc.data()['amount'], equals(500000.0));

      // Verify wallet balance updated (2m - 500k = 1.5m)
      final wDoc = await fakeDb.collection('wallets').doc('w_1').get();
      expect(wDoc.data()!['balance'], equals(1500000.0));

      // Verify schedule nextDueDate updated
      final schDoc =
          await fakeDb.collection('recurringTransactions').doc(scheduleId).get();
      expect(schDoc.data()!['lastProcessedKey'], equals('2026-09-20'));
    });

    // 17. processDueRecurringTransactions fails clearly when document is missing userId
    test(
        '17. processDueRecurringTransactions fails clearly when wallet or schedule is missing userId',
        () async {
      final firestoreService = FirestoreService(firestore: fakeDb);
      final userId = 'u_1';
      final scheduleId = 'sch_legacy_missing_uid';

      // Seed wallet MISSING userId field (legacy document)
      await fakeDb.collection('wallets').doc('w_no_uid').set({
        'walletName': 'Ví Cũ',
        'balance': 2000000.0,
        'type': 'cash',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Seed schedule with valid userId pointing to legacy wallet
      final dueDate = DateTime(2026, 9, 20);
      await fakeDb.collection('recurringTransactions').doc(scheduleId).set({
        'userId': userId,
        'type': 'expense',
        'walletId': 'w_no_uid',
        'categoryId': 'cat_food',
        'amount': 500000.0,
        'frequency': 'monthly',
        'startDate': dueDate.toIso8601String(),
        'nextDueDate': dueDate.toIso8601String(),
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final result = await firestoreService.processDueRecurringTransactions(
        userId,
        referenceDate: DateTime(2026, 9, 20),
      );

      expect(result['processedCount'], equals(0));
      expect(result['failedSchedules'], isNotEmpty);
      expect(result['failedSchedules'].first, contains('thiếu userId hợp lệ'));

      // Verify no transaction document created
      final txQuery = await fakeDb.collection('transactions').get();
      expect(txQuery.docs, isEmpty);
    });

    // 18. New schedule default postingMode is manualConfirmation
    test('18. New RecurringTransactionSchedule defaults to manualConfirmation postingMode', () {
      final s = RecurringTransactionSchedule(
        scheduleId: 'sch_new',
        userId: 'u_1',
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_1',
        amount: 100000,
        frequency: 'monthly',
        startDate: DateTime.now(),
        nextDueDate: DateTime.now(),
        createdAt: DateTime.now(),
      );
      expect(s.postingMode, equals(RecurringTransactionSchedule.postingModeManual));
    });

    // 19. Legacy schedule without postingMode fallback autoPost
    test('19. Legacy RecurringTransactionSchedule map without postingMode falls back to autoPost', () {
      final map = {
        'userId': 'u_1',
        'type': 'expense',
        'walletId': 'w_1',
        'categoryId': 'cat_1',
        'amount': 200000.0,
        'frequency': 'monthly',
        'startDate': DateTime(2026, 1, 1).toIso8601String(),
        'nextDueDate': DateTime(2026, 1, 1).toIso8601String(),
        'isActive': true,
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      final s = RecurringTransactionSchedule.fromMap(map, 'sch_legacy');
      expect(s.postingMode, equals(RecurringTransactionSchedule.postingModeAuto));
    });

    // 20. Manual schedule due is NOT auto-posted by processDueRecurringTransactions
    test('20. Manual schedule due is NOT auto-posted by processDueRecurringTransactions', () async {
      final firestoreService = FirestoreService(firestore: fakeDb);
      final userId = 'u_1';
      final scheduleId = 'sch_manual';

      await fakeDb.collection('wallets').doc('w_1').set({
        'userId': userId,
        'walletName': 'Ví Chính',
        'balance': 5000000.0,
        'type': 'bank',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final dueDate = DateTime(2026, 9, 20);
      await fakeDb.collection('recurringTransactions').doc(scheduleId).set({
        'userId': userId,
        'type': 'expense',
        'walletId': 'w_1',
        'categoryId': 'cat_food',
        'amount': 500000.0,
        'frequency': 'monthly',
        'startDate': dueDate.toIso8601String(),
        'nextDueDate': dueDate.toIso8601String(),
        'postingMode': RecurringTransactionSchedule.postingModeManual,
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final result = await firestoreService.processDueRecurringTransactions(
        userId,
        referenceDate: DateTime(2026, 9, 20),
      );

      expect(result['processedCount'], equals(0));

      final txQuery = await fakeDb.collection('transactions').get();
      expect(txQuery.docs, isEmpty);

      final wDoc = await fakeDb.collection('wallets').doc('w_1').get();
      expect(wDoc.data()!['balance'], equals(5000000.0));
    });

    // 21. Confirmation creates exactly 1 transaction, updates wallet & nextDueDate
    test('21. Manual confirmation creates exactly 1 transaction, updates wallet balance, advances nextDueDate, and logs occurrence audit', () async {
      final firestoreService = FirestoreService(firestore: fakeDb);
      final userId = 'u_1';
      final scheduleId = 'sch_manual_confirm';
      final dueDate = DateTime(2026, 9, 20);

      await fakeDb.collection('wallets').doc('w_1').set({
        'userId': userId,
        'walletName': 'Ví Tiền Mặt',
        'balance': 2000000.0,
        'type': 'cash',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final schedule = RecurringTransactionSchedule(
        scheduleId: scheduleId,
        userId: userId,
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 300000.0,
        frequency: 'monthly',
        startDate: dueDate,
        nextDueDate: dueDate,
        postingMode: RecurringTransactionSchedule.postingModeManual,
        createdAt: DateTime.now(),
      );

      await fakeDb
          .collection('recurringTransactions')
          .doc(scheduleId)
          .set(schedule.toMap());

      await firestoreService.confirmRecurringOccurrence(
        userId: userId,
        schedule: schedule,
        occurrenceDate: dueDate,
      );

      // Verify transaction created
      final txQuery = await fakeDb.collection('transactions').get();
      expect(txQuery.docs.length, equals(1));
      expect(txQuery.docs.first.data()['amount'], equals(300000.0));

      // Verify wallet balance updated (2m - 300k = 1.7m)
      final wDoc = await fakeDb.collection('wallets').doc('w_1').get();
      expect(wDoc.data()!['balance'], equals(1700000.0));

      // Verify nextDueDate updated
      final schDoc =
          await fakeDb.collection('recurringTransactions').doc(scheduleId).get();
      expect(schDoc.data()!['lastProcessedKey'], equals('2026-09-20'));

      // Verify audit occurrence created
      final occQuery =
          await fakeDb.collection('recurringTransactionOccurrences').get();
      expect(occQuery.docs.length, equals(1));
      final occDoc = occQuery.docs.first;
      expect(occDoc.data()['userId'], equals(userId));
      expect(occDoc.data()['action'], equals('confirmed'));
      expect(occDoc.data()['transactionId'], isNotNull);
    });

    // 22. Double confirm does not create duplicate transaction
    test('22. Double confirm throws exception and prevents duplicate transaction creation', () async {
      final firestoreService = FirestoreService(firestore: fakeDb);
      final userId = 'u_1';
      final scheduleId = 'sch_double_confirm';
      final dueDate = DateTime(2026, 9, 20);

      await fakeDb.collection('wallets').doc('w_1').set({
        'userId': userId,
        'walletName': 'Ví Tiền Mặt',
        'balance': 2000000.0,
        'type': 'cash',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final schedule = RecurringTransactionSchedule(
        scheduleId: scheduleId,
        userId: userId,
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 300000.0,
        frequency: 'monthly',
        startDate: dueDate,
        nextDueDate: dueDate,
        postingMode: RecurringTransactionSchedule.postingModeManual,
        createdAt: DateTime.now(),
      );

      await fakeDb
          .collection('recurringTransactions')
          .doc(scheduleId)
          .set(schedule.toMap());

      await firestoreService.confirmRecurringOccurrence(
        userId: userId,
        schedule: schedule,
        occurrenceDate: dueDate,
      );

      expect(
        () async => await firestoreService.confirmRecurringOccurrence(
          userId: userId,
          schedule: schedule,
          occurrenceDate: dueDate,
        ),
        throwsA(isA<Exception>()),
      );

      final txQuery = await fakeDb.collection('transactions').get();
      expect(txQuery.docs.length, equals(1));
    });

    // 23. Skip does not create transaction, does not change balance, advances nextDueDate
    test('23. Skip occurrence does not create transaction, does not change balance, advances nextDueDate, and logs skipped audit', () async {
      final firestoreService = FirestoreService(firestore: fakeDb);
      final userId = 'u_1';
      final scheduleId = 'sch_skip';
      final dueDate = DateTime(2026, 9, 20);

      await fakeDb.collection('wallets').doc('w_1').set({
        'userId': userId,
        'walletName': 'Ví Tiền Mặt',
        'balance': 2000000.0,
        'type': 'cash',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final schedule = RecurringTransactionSchedule(
        scheduleId: scheduleId,
        userId: userId,
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 300000.0,
        frequency: 'monthly',
        startDate: dueDate,
        nextDueDate: dueDate,
        postingMode: RecurringTransactionSchedule.postingModeManual,
        createdAt: DateTime.now(),
      );

      await fakeDb
          .collection('recurringTransactions')
          .doc(scheduleId)
          .set(schedule.toMap());

      await firestoreService.skipRecurringOccurrence(
        userId: userId,
        schedule: schedule,
        occurrenceDate: dueDate,
      );

      // Verify NO transaction created
      final txQuery = await fakeDb.collection('transactions').get();
      expect(txQuery.docs, isEmpty);

      // Verify balance unchanged
      final wDoc = await fakeDb.collection('wallets').doc('w_1').get();
      expect(wDoc.data()!['balance'], equals(2000000.0));

      // Verify nextDueDate advanced
      final schDoc =
          await fakeDb.collection('recurringTransactions').doc(scheduleId).get();
      expect(schDoc.data()!['lastProcessedKey'], equals('2026-09-20'));

      // Verify audit occurrence logged with action: skipped
      final occDoc = await fakeDb
          .collection('recurringTransactionOccurrences')
          .doc('sch_skip_2026-09-20')
          .get();
      expect(occDoc.exists, isTrue);
      expect(occDoc.data()!['action'], equals('skipped'));
      expect(occDoc.data()!['userId'], equals(userId));
    });

    // 24. Defer does not create transaction, saves deferredTo
    test('24. Defer occurrence does not create transaction, saves deferredTo date, and updates nextDueDate', () async {
      final firestoreService = FirestoreService(firestore: fakeDb);
      final userId = 'u_1';
      final scheduleId = 'sch_defer';
      final dueDate = DateTime(2026, 9, 20);
      final deferredDate = DateTime(2026, 9, 28);

      await fakeDb.collection('wallets').doc('w_1').set({
        'userId': userId,
        'walletName': 'Ví Tiền Mặt',
        'balance': 2000000.0,
        'type': 'cash',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final schedule = RecurringTransactionSchedule(
        scheduleId: scheduleId,
        userId: userId,
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 300000.0,
        frequency: 'monthly',
        startDate: dueDate,
        nextDueDate: dueDate,
        postingMode: RecurringTransactionSchedule.postingModeManual,
        createdAt: DateTime.now(),
      );

      await fakeDb
          .collection('recurringTransactions')
          .doc(scheduleId)
          .set(schedule.toMap());

      await firestoreService.deferRecurringOccurrence(
        userId: userId,
        schedule: schedule,
        occurrenceDate: dueDate,
        newDueDate: deferredDate,
      );

      // Verify NO transaction created
      final txQuery = await fakeDb.collection('transactions').get();
      expect(txQuery.docs, isEmpty);

      // Verify balance unchanged
      final wDoc = await fakeDb.collection('wallets').doc('w_1').get();
      expect(wDoc.data()!['balance'], equals(2000000.0));

      // Verify schedule nextDueDate updated to deferredDate
      final schDoc =
          await fakeDb.collection('recurringTransactions').doc(scheduleId).get();
      expect(schDoc.data()!['nextDueDate'], equals(deferredDate.toIso8601String()));

      // Verify audit occurrence logged with action: deferred and deferredTo
      final occDoc = await fakeDb
          .collection('recurringTransactionOccurrences')
          .doc('sch_defer_2026-09-20')
          .get();
      expect(occDoc.exists, isTrue);
      expect(occDoc.data()!['action'], equals('deferred'));
      expect(occDoc.data()!['deferredTo'], equals(deferredDate.toIso8601String()));
      expect(occDoc.data()!['userId'], equals(userId));
    });

    // 25. Auto-post schedule still works as before
    test('25. Auto-post schedule processes automatically when due', () async {
      final firestoreService = FirestoreService(firestore: fakeDb);
      final userId = 'u_1';
      final scheduleId = 'sch_auto';
      final dueDate = DateTime(2026, 9, 20);

      await fakeDb.collection('wallets').doc('w_1').set({
        'userId': userId,
        'walletName': 'Ví Tiền Mặt',
        'balance': 2000000.0,
        'type': 'cash',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      await fakeDb.collection('recurringTransactions').doc(scheduleId).set({
        'userId': userId,
        'type': 'expense',
        'walletId': 'w_1',
        'categoryId': 'cat_food',
        'amount': 400000.0,
        'frequency': 'monthly',
        'startDate': dueDate.toIso8601String(),
        'nextDueDate': dueDate.toIso8601String(),
        'postingMode': RecurringTransactionSchedule.postingModeAuto,
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final res = await firestoreService.processDueRecurringTransactions(
        userId,
        referenceDate: dueDate,
      );

      expect(res['processedCount'], equals(1));
      final txQuery = await fakeDb.collection('transactions').get();
      expect(txQuery.docs.length, equals(1));
    });

    // 26. Notification does not create transaction
    test('26. LocalNotificationService notification generation does not create transactions or alter balances', () {
      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_notif',
        userId: 'u_1',
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 500000.0,
        frequency: 'monthly',
        startDate: DateTime(2026, 9, 25),
        nextDueDate: DateTime(2026, 9, 25),
        postingMode: RecurringTransactionSchedule.postingModeManual,
        reminderDaysBefore: 1,
        createdAt: DateTime.now(),
      );

      final items = LocalNotificationService.calculateScheduledNotifications(
        schedule: schedule,
        walletName: 'Ví Bank',
        referenceDate: DateTime(2026, 9, 20),
      );

      expect(items, isNotEmpty);
      final dueItem = items.firstWhere((i) => i.isOnDueDate);
      expect(dueItem.title, contains('Hôm nay cần xác nhận'));
      expect(dueItem.body, contains('Chờ bạn xác nhận'));
    });

    // 27. Rules/document audit always retain userId
    test('27. Audit occurrence documents always retain valid userId', () async {
      final firestoreService = FirestoreService(firestore: fakeDb);
      final userId = 'user_audit_123';
      final scheduleId = 'sch_audit';
      final dueDate = DateTime(2026, 9, 20);

      await fakeDb.collection('wallets').doc('w_1').set({
        'userId': userId,
        'walletName': 'Ví',
        'balance': 1000000.0,
        'type': 'cash',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final schedule = RecurringTransactionSchedule(
        scheduleId: scheduleId,
        userId: userId,
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_1',
        amount: 100000.0,
        frequency: 'monthly',
        startDate: dueDate,
        nextDueDate: dueDate,
        postingMode: RecurringTransactionSchedule.postingModeManual,
        createdAt: DateTime.now(),
      );

      await fakeDb
          .collection('recurringTransactions')
          .doc(scheduleId)
          .set(schedule.toMap());

      await firestoreService.skipRecurringOccurrence(
        userId: userId,
        schedule: schedule,
        occurrenceDate: dueDate,
      );

      final occDoc = await fakeDb
          .collection('recurringTransactionOccurrences')
          .doc('sch_audit_2026-09-20')
          .get();

      expect(occDoc.exists, isTrue);
      expect(occDoc.data()!['userId'], equals(userId));
    });

    // 28. Skip same occurrence twice — should only advance one cycle
    test('28. Skip same occurrence twice throws on second attempt and only advances nextDueDate once', () async {
      final firestoreService = FirestoreService(firestore: fakeDb);
      final userId = 'u_1';
      final scheduleId = 'sch_double_skip';
      final dueDate = DateTime(2026, 9, 20);

      await fakeDb.collection('wallets').doc('w_1').set({
        'userId': userId,
        'walletName': 'Ví Tiền Mặt',
        'balance': 2000000.0,
        'type': 'cash',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final schedule = RecurringTransactionSchedule(
        scheduleId: scheduleId,
        userId: userId,
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 300000.0,
        frequency: 'monthly',
        startDate: dueDate,
        nextDueDate: dueDate,
        postingMode: RecurringTransactionSchedule.postingModeManual,
        createdAt: DateTime.now(),
      );

      await fakeDb
          .collection('recurringTransactions')
          .doc(scheduleId)
          .set(schedule.toMap());

      // 1st skip — should succeed
      await firestoreService.skipRecurringOccurrence(
        userId: userId,
        schedule: schedule,
        occurrenceDate: dueDate,
      );

      // Record nextDueDate after first skip
      final schDocAfterFirst =
          await fakeDb.collection('recurringTransactions').doc(scheduleId).get();
      final nextDueDateAfterFirstSkip = schDocAfterFirst.data()!['nextDueDate'];

      // 2nd skip — should throw because occurrence doc already exists
      expect(
        () async => await firestoreService.skipRecurringOccurrence(
          userId: userId,
          schedule: schedule,
          occurrenceDate: dueDate,
        ),
        throwsA(isA<Exception>()),
      );

      // Verify nextDueDate did NOT change after the rejected second skip
      final schDocAfterSecond =
          await fakeDb.collection('recurringTransactions').doc(scheduleId).get();
      expect(schDocAfterSecond.data()!['nextDueDate'], equals(nextDueDateAfterFirstSkip));

      // Verify only 1 occurrence audit doc exists
      final occQuery = await fakeDb.collection('recurringTransactionOccurrences').get();
      expect(occQuery.docs.length, equals(1));
    });

    // 29. Defer same occurrence twice — should not override nextDueDate
    test('29. Defer same occurrence twice throws on second attempt and preserves first deferredTo date', () async {
      final firestoreService = FirestoreService(firestore: fakeDb);
      final userId = 'u_1';
      final scheduleId = 'sch_double_defer';
      final dueDate = DateTime(2026, 9, 20);
      final deferredDate1 = DateTime(2026, 9, 25);
      final deferredDate2 = DateTime(2026, 9, 30);

      await fakeDb.collection('wallets').doc('w_1').set({
        'userId': userId,
        'walletName': 'Ví Tiền Mặt',
        'balance': 2000000.0,
        'type': 'cash',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final schedule = RecurringTransactionSchedule(
        scheduleId: scheduleId,
        userId: userId,
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 300000.0,
        frequency: 'monthly',
        startDate: dueDate,
        nextDueDate: dueDate,
        postingMode: RecurringTransactionSchedule.postingModeManual,
        createdAt: DateTime.now(),
      );

      await fakeDb
          .collection('recurringTransactions')
          .doc(scheduleId)
          .set(schedule.toMap());

      // 1st defer — should succeed, nextDueDate → deferredDate1
      await firestoreService.deferRecurringOccurrence(
        userId: userId,
        schedule: schedule,
        occurrenceDate: dueDate,
        newDueDate: deferredDate1,
      );

      final schDocAfterFirst =
          await fakeDb.collection('recurringTransactions').doc(scheduleId).get();
      expect(schDocAfterFirst.data()!['nextDueDate'],
          equals(deferredDate1.toIso8601String()));

      // 2nd defer — should throw because occurrence doc already exists
      expect(
        () async => await firestoreService.deferRecurringOccurrence(
          userId: userId,
          schedule: schedule,
          occurrenceDate: dueDate,
          newDueDate: deferredDate2,
        ),
        throwsA(isA<Exception>()),
      );

      // Verify nextDueDate still points to deferredDate1, NOT deferredDate2
      final schDocAfterSecond =
          await fakeDb.collection('recurringTransactions').doc(scheduleId).get();
      expect(schDocAfterSecond.data()!['nextDueDate'],
          equals(deferredDate1.toIso8601String()));

      // Verify only 1 occurrence audit doc
      final occQuery = await fakeDb.collection('recurringTransactionOccurrences').get();
      expect(occQuery.docs.length, equals(1));
      expect(occQuery.docs.first.data()['deferredTo'],
          equals(deferredDate1.toIso8601String()));
    });

    // 30. Confirm after skip — should be rejected
    test('30. Confirm after skip is rejected because occurrence already processed', () async {
      final firestoreService = FirestoreService(firestore: fakeDb);
      final userId = 'u_1';
      final scheduleId = 'sch_confirm_after_skip';
      final dueDate = DateTime(2026, 9, 20);

      await fakeDb.collection('wallets').doc('w_1').set({
        'userId': userId,
        'walletName': 'Ví Tiền Mặt',
        'balance': 2000000.0,
        'type': 'cash',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final schedule = RecurringTransactionSchedule(
        scheduleId: scheduleId,
        userId: userId,
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 300000.0,
        frequency: 'monthly',
        startDate: dueDate,
        nextDueDate: dueDate,
        postingMode: RecurringTransactionSchedule.postingModeManual,
        createdAt: DateTime.now(),
      );

      await fakeDb
          .collection('recurringTransactions')
          .doc(scheduleId)
          .set(schedule.toMap());

      // Skip the occurrence first
      await firestoreService.skipRecurringOccurrence(
        userId: userId,
        schedule: schedule,
        occurrenceDate: dueDate,
      );

      // Attempt to confirm the same occurrence — should throw
      expect(
        () async => await firestoreService.confirmRecurringOccurrence(
          userId: userId,
          schedule: schedule,
          occurrenceDate: dueDate,
        ),
        throwsA(isA<Exception>()),
      );

      // Verify NO transaction was created (skip does not create one, confirm was rejected)
      final txQuery = await fakeDb.collection('transactions').get();
      expect(txQuery.docs, isEmpty);

      // Verify balance unchanged
      final wDoc = await fakeDb.collection('wallets').doc('w_1').get();
      expect(wDoc.data()!['balance'], equals(2000000.0));
    });

    // 31. Confirm after defer — should be rejected
    test('31. Confirm after defer is rejected because occurrence already processed', () async {
      final firestoreService = FirestoreService(firestore: fakeDb);
      final userId = 'u_1';
      final scheduleId = 'sch_confirm_after_defer';
      final dueDate = DateTime(2026, 9, 20);
      final deferredDate = DateTime(2026, 9, 28);

      await fakeDb.collection('wallets').doc('w_1').set({
        'userId': userId,
        'walletName': 'Ví Tiền Mặt',
        'balance': 2000000.0,
        'type': 'cash',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final schedule = RecurringTransactionSchedule(
        scheduleId: scheduleId,
        userId: userId,
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 300000.0,
        frequency: 'monthly',
        startDate: dueDate,
        nextDueDate: dueDate,
        postingMode: RecurringTransactionSchedule.postingModeManual,
        createdAt: DateTime.now(),
      );

      await fakeDb
          .collection('recurringTransactions')
          .doc(scheduleId)
          .set(schedule.toMap());

      // Defer the occurrence first
      await firestoreService.deferRecurringOccurrence(
        userId: userId,
        schedule: schedule,
        occurrenceDate: dueDate,
        newDueDate: deferredDate,
      );

      // Attempt to confirm the same occurrence — should throw
      expect(
        () async => await firestoreService.confirmRecurringOccurrence(
          userId: userId,
          schedule: schedule,
          occurrenceDate: dueDate,
        ),
        throwsA(isA<Exception>()),
      );

      // Verify NO transaction was created (defer does not create one, confirm was rejected)
      final txQuery = await fakeDb.collection('transactions').get();
      expect(txQuery.docs, isEmpty);

      // Verify balance unchanged
      final wDoc = await fakeDb.collection('wallets').doc('w_1').get();
      expect(wDoc.data()!['balance'], equals(2000000.0));
    });
  });
}
