import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_ai_app/models/monthly_financial_plan.dart';
import 'package:finance_ai_app/models/notification_model.dart';
import 'package:finance_ai_app/models/recurring_transaction_model.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/services/language_controller.dart';
import 'package:finance_ai_app/services/local_notification_service.dart';
import 'package:finance_ai_app/l10n/app_localizations.dart';
import 'package:finance_ai_app/utils/category_localization_helper.dart';
import 'package:finance_ai_app/utils/formatters.dart';
import 'package:finance_ai_app/utils/notification_localization_helper.dart';
import 'package:finance_ai_app/utils/transaction_note_localization_helper.dart';
import 'package:finance_ai_app/utils/wallet_localization_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LanguageController.loadSavedLanguage();
  });

  group('1. LanguageController & Persistence Tests', () {
    test('1.1. Mặc định là Tiếng Việt', () {
      expect(LanguageController.currentLanguageCode, 'vi');
      expect(LanguageController.isVietnamese, isTrue);
      expect(LanguageController.isEnglish, isFalse);
      expect(LanguageController.currentLanguageName, 'Tiếng Việt');
      expect(LanguageController.currentLanguageFlag, '🇻🇳');
    });

    test('1.2. Đổi sang Tiếng Anh (en) thành công và lưu vào SharedPreferences',
        () async {
      await LanguageController.setLanguage('en');

      expect(LanguageController.currentLanguageCode, 'en');
      expect(LanguageController.isEnglish, isTrue);
      expect(LanguageController.isVietnamese, isFalse);
      expect(LanguageController.currentLanguageName, 'English');
      expect(LanguageController.currentLanguageFlag, '🇺🇸');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_language'), 'en');
    });

    test('1.3. Nạp lại ngôn ngữ đã lưu khi khởi động ứng dụng', () async {
      SharedPreferences.setMockInitialValues({'app_language': 'en'});
      await LanguageController.loadSavedLanguage();

      expect(LanguageController.currentLanguageCode, 'en');
      expect(LanguageController.isEnglish, isTrue);

      // Đổi lại Tiếng Việt
      await LanguageController.setLanguage('vi');
      expect(LanguageController.currentLanguageCode, 'vi');
      expect(LanguageController.isVietnamese, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_language'), 'vi');
    });
  });

  group('2. AppLocalizations Dictionary & Interpolation Tests', () {
    test('2.1. Tra cứu từ điển Tiếng Việt chuẩn xác', () async {
      await LanguageController.setLanguage('vi');

      expect(AppLocalizations.tr('nav_home'), 'Trang chủ');
      expect(AppLocalizations.tr('nav_transactions'), 'Giao dịch');
      expect(AppLocalizations.tr('profile_title'), 'Cá nhân');
      expect(AppLocalizations.tr('profile_menu_language'), 'Ngôn ngữ hiển thị');
      expect(AppLocalizations.tr('profile_logout_btn'), 'Đăng xuất tài khoản');
      expect(AppLocalizations.tr('home_total_balance'), 'Tổng tài sản');
    });

    test('2.2. Tra cứu từ điển Tiếng Anh chuẩn xác', () async {
      await LanguageController.setLanguage('en');

      expect(AppLocalizations.tr('nav_home'), 'Home');
      expect(AppLocalizations.tr('nav_transactions'), 'Transactions');
      expect(AppLocalizations.tr('profile_title'), 'Profile');
      expect(AppLocalizations.tr('profile_menu_language'), 'Display Language');
      expect(AppLocalizations.tr('profile_logout_btn'), 'Log Out Account');
      expect(AppLocalizations.tr('home_total_balance'), 'Total Balance');
    });

    test('2.3. Hỗ trợ thay thế biến tham số (Interpolation)', () async {
      await LanguageController.setLanguage('vi');
      final viWallets = AppLocalizations.tr(
        'home_wallets_count',
        params: {'count': '3'},
      );
      expect(viWallets, '3 ví');

      final viSpent = AppLocalizations.tr(
        'home_spent_percentage',
        params: {'percent': '65'},
      );
      expect(viSpent, 'Đã chi 65% thu nhập tháng này');

      await LanguageController.setLanguage('en');
      final enWallets = AppLocalizations.tr(
        'home_wallets_count',
        params: {'count': '3'},
      );
      expect(enWallets, '3 wallets');

      final enSpent = AppLocalizations.tr(
        'home_spent_percentage',
        params: {'percent': '65'},
      );
      expect(enSpent, 'Spent 65% of income this month');
    });

    test('2.4. Cơ chế fallback khi key không có trong từ điển tiếng Anh',
        () async {
      await LanguageController.setLanguage('en');
      // Nếu có key chỉ có trong tiếng Việt, fallback về tiếng Việt
      final fallbackResult = AppLocalizations.tr('non_existent_key_123');
      expect(fallbackResult, 'non_existent_key_123');
    });
  });

  group('3. Widget / BuildContext Localization Extension Tests', () {
    testWidgets('3.1. context.tr phản hồi đúng theo Locale của MaterialApp',
        (tester) async {
      await LanguageController.setLanguage('vi');

      late String testTextVi;
      late String testTextEn;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('vi', 'VN'),
          supportedLocales: LanguageController.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) {
              testTextVi = context.tr('profile_title');
              return Text(testTextVi);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(testTextVi, 'Cá nhân');

      await LanguageController.setLanguage('en');
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en', 'US'),
          supportedLocales: LanguageController.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) {
              testTextEn = context.tr('profile_title');
              return Text(testTextEn);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(testTextEn, 'Profile');
    });
  });

  group('4. Full Dictionary Parity, Non-Empty & Placeholder Consistency Tests',
      () {
    test('4.1. Từ điển _vi và _en có tập key giống hệt nhau', () {
      final viKeys = AppLocalizations.viKeys.keys.toSet();
      final enKeys = AppLocalizations.enKeys.keys.toSet();

      expect(viKeys.length, greaterThanOrEqualTo(1500));
      expect(viKeys.difference(enKeys), isEmpty,
          reason: 'Các key có trong _vi nhưng thiếu trong _en');
      expect(enKeys.difference(viKeys), isEmpty,
          reason: 'Các key dư trong _en không có trong _vi');
    });

    test('4.2. Không có giá trị dịch nào bị rỗng trong _vi và _en', () {
      final emptyVi = AppLocalizations.viKeys.entries
          .where((e) => e.value.trim().isEmpty)
          .map((e) => e.key)
          .toList();
      final emptyEn = AppLocalizations.enKeys.entries
          .where((e) => e.value.trim().isEmpty)
          .map((e) => e.key)
          .toList();

      expect(emptyVi, isEmpty);
      expect(emptyEn, isEmpty);
    });

    test('4.3. Tập placeholder {param} của mọi key khớp 100% giữa _vi và _en',
        () {
      final placeholderRegex = RegExp(r'\{([a-zA-Z0-9_]+)\}');
      final mismatches = <String>[];

      for (final entry in AppLocalizations.viKeys.entries) {
        final enValue = AppLocalizations.enKeys[entry.key];
        if (enValue == null) continue;

        final viParams = placeholderRegex
            .allMatches(entry.value)
            .map((m) => m.group(1)!)
            .toList()
          ..sort();
        final enParams = placeholderRegex
            .allMatches(enValue)
            .map((m) => m.group(1)!)
            .toList()
          ..sort();

        if (viParams.join(',') != enParams.join(',')) {
          mismatches.add('${entry.key}: vi=$viParams vs en=$enParams');
        }
      }

      expect(mismatches, isEmpty);
    });

    test('4.4. Tham số thay thế hoạt động đúng ở cả hai ngôn ngữ cho nhóm mới',
        () async {
      await LanguageController.setLanguage('vi');
      expect(
        AppLocalizations.tr('rec_dlg_defer_desc', params: {
          'oldDate': '01/11/2026',
          'newDate': '05/11/2026',
        }),
        'Dời ngày đến hạn từ 01/11/2026 sang ngày 05/11/2026.',
      );
      expect(AppLocalizations.tr('rec_form_save_btn'), 'Lưu lịch định kỳ');

      await LanguageController.setLanguage('en');
      expect(
        AppLocalizations.tr('rec_dlg_defer_desc', params: {
          'oldDate': '01/11/2026',
          'newDate': '05/11/2026',
        }),
        'Move due date from 01/11/2026 to 05/11/2026.',
      );
      expect(AppLocalizations.tr('rec_form_save_btn'), 'Save Schedule');
      expect(
        AppLocalizations.tr('rec_form_sum_inc_cycle', params: {
          'cycle': AppLocalizations.tr('rec_form_cycle_monthly'),
        }),
        'Income (monthly):',
      );
    });
  });

  group('5. AppFormatters Locale Switching Tests', () {
    test('5.1. AppFormatters.currency đổi hậu tố VNĐ / VND theo ngôn ngữ',
        () async {
      await LanguageController.setLanguage('vi');
      expect(AppFormatters.currency(50000), contains('VNĐ'));

      await LanguageController.setLanguage('en');
      final enCurrency = AppFormatters.currency(50000);
      expect(enCurrency, contains('VND'));
      expect(enCurrency.contains('VNĐ'), isFalse);
    });

    test('5.2. AppFormatters.compactCurrency đổi tỷ / B theo ngôn ngữ',
        () async {
      await LanguageController.setLanguage('vi');
      expect(AppFormatters.compactCurrency(1500000000), contains('tỷ'));

      await LanguageController.setLanguage('en');
      final enCompact = AppFormatters.compactCurrency(1500000000);
      expect(enCompact, contains('B'));
      expect(enCompact.contains('tỷ'), isFalse);

      await LanguageController.setLanguage('vi');
    });
  });

  group('6. CategoryLocalizationHelper & Auth Method Removal Tests', () {
    test('6.1. Không còn key profile_menu_auth_method và _en không chứa VNĐ hay đ',
        () {
      expect(AppLocalizations.viKeys.containsKey('profile_menu_auth_method'),
          isFalse);
      expect(AppLocalizations.enKeys.containsKey('profile_menu_auth_method'),
          isFalse);

      final leftoverVnd = <String>[];
      final dongUnitPattern = RegExp(r'(^|[\s\d\)\}])đ($|[\s\.\,\)\!])');
      for (final entry in AppLocalizations.enKeys.entries) {
        if (entry.value.contains('VNĐ') ||
            dongUnitPattern.hasMatch(entry.value)) {
          leftoverVnd.add('${entry.key}: ${entry.value}');
        }
      }
      expect(leftoverVnd, isEmpty);
    });

    test('6.2. Tự động dịch danh mục hệ thống giữa VI và EN, giữ nguyên danh mục cá nhân',
        () async {
      await LanguageController.setLanguage('en');
      expect(CategoryLocalizationHelper.localizeName('Ăn uống'), 'Food');
      expect(CategoryLocalizationHelper.localizeName('Di chuyển'), 'Transport');
      expect(CategoryLocalizationHelper.localizeName('Du lịch'), 'Travel');
      expect(CategoryLocalizationHelper.localizeName('Lương'), 'Salary');
      expect(
          CategoryLocalizationHelper.localizeName('Y tế / Sức khỏe'),
          'Healthcare & Wellness');

      // Danh mục tùy chỉnh của người dùng không bị tự động dịch
      expect(CategoryLocalizationHelper.localizeName('Trà sữa'), 'Trà sữa');
      expect(
          CategoryLocalizationHelper.localizeName('Quỹ ăn vặt'), 'Quỹ ăn vặt');

      await LanguageController.setLanguage('vi');
      expect(CategoryLocalizationHelper.localizeName('Food'), 'Ăn uống');
      expect(CategoryLocalizationHelper.localizeName('Transport'), 'Di chuyển');
      expect(
          CategoryLocalizationHelper.localizeName('Custom Hobby'), 'Custom Hobby');
    });

    test('6.3. allSearchVariants hỗ trợ tìm kiếm đa ngôn ngữ cho danh mục hệ thống',
        () {
      final variants = CategoryLocalizationHelper.allSearchVariants('Ăn uống');
      expect(variants, contains('Ăn uống'));
      expect(variants, contains('Food'));

      final customVariants =
          CategoryLocalizationHelper.allSearchVariants('Quỹ trà sữa');
      expect(customVariants, equals(['Quỹ trà sữa']));
    });
  });

  group('7. Goal Notes, Notifications & System Cash Wallet Localization Tests',
      () {
    test('7.1. WalletLocalizationHelper dịch ví Tiền mặt mặc định, giữ nguyên ví người dùng đặt',
        () async {
      final presetCash = Wallet(
        walletId: 'w_cash',
        userId: 'u1',
        walletName: 'Tiền mặt',
        balance: 1000000,
        type: 'cash',
        isUserNamed: false,
        createdAt: DateTime(2026, 11, 1),
      );
      final customNamedCash = Wallet(
        walletId: 'w_custom_cash',
        userId: 'u1',
        walletName: 'Tiền mặt',
        balance: 500000,
        type: 'cash',
        isUserNamed: true,
        createdAt: DateTime(2026, 11, 1),
      );
      final brandWallet = Wallet(
        walletId: 'w_mb',
        userId: 'u1',
        walletName: 'MB Bank',
        balance: 2000000,
        type: 'bank',
        createdAt: DateTime(2026, 11, 1),
      );

      await LanguageController.setLanguage('en');
      expect(WalletLocalizationHelper.localizeWallet(presetCash), 'Cash');
      expect(
        WalletLocalizationHelper.localizeWallet(customNamedCash),
        'Tiền mặt',
      );
      expect(WalletLocalizationHelper.localizeWallet(brandWallet), 'MB Bank');

      await LanguageController.setLanguage('vi');
      expect(WalletLocalizationHelper.localizeWallet(presetCash), 'Tiền mặt');
    });

    test('7.2. TransactionNoteLocalizationHelper dịch động ghi chú nạp/rút mục tiêu giữa VI và EN',
        () async {
      final presetCash = Wallet(
        walletId: 'w_cash',
        userId: 'u1',
        walletName: 'Tiền mặt',
        balance: 1000000,
        type: 'cash',
        isUserNamed: false,
        createdAt: DateTime(2026, 11, 1),
      );

      final viDeposit = AppTransaction(
        transactionId: 'tx_1',
        userId: 'u1',
        walletId: 'w_cash',
        categoryId: '',
        amount: 2000000,
        type: 'goal_deposit',
        goalId: 'g_1',
        note: 'Nạp vào mục tiêu "Laptop" từ ví Tiền mặt',
        date: DateTime(2026, 11, 14),
      );
      final legacyViDeposit = AppTransaction(
        transactionId: 'tx_2',
        userId: 'u1',
        walletId: 'w_mb',
        categoryId: '',
        amount: 10000000,
        type: 'goal_deposit',
        goalId: 'g_1',
        note: 'Nạp vào mục tiêu tiết kiệm "Laptop" từ ví MB Bank',
        date: DateTime(2026, 11, 14),
      );
      final viWithdraw = AppTransaction(
        transactionId: 'tx_3',
        userId: 'u1',
        walletId: 'w_cash',
        categoryId: '',
        amount: 2000000,
        type: 'goal_withdraw',
        goalId: 'g_1',
        note: 'Rút từ mục tiêu "Laptop" hoàn trả về ví Tiền mặt',
        date: DateTime(2026, 11, 14),
      );
      final regularExpense = AppTransaction(
        transactionId: 'tx_4',
        userId: 'u1',
        walletId: 'w_cash',
        categoryId: 'cat_food',
        amount: 50000,
        type: 'expense',
        note: 'Nạp năng lượng buổi sáng',
        date: DateTime(2026, 11, 14),
      );

      await LanguageController.setLanguage('en');
      expect(
        TransactionNoteLocalizationHelper.localizeNote(
          viDeposit,
          wallet: presetCash,
        ),
        'Deposit to goal "Laptop" from Cash',
      );
      expect(
        TransactionNoteLocalizationHelper.localizeNote(legacyViDeposit),
        'Deposit to goal "Laptop" from MB Bank',
      );
      expect(
        TransactionNoteLocalizationHelper.localizeNote(
          viWithdraw,
          wallet: presetCash,
        ),
        'Withdraw from goal "Laptop" back to Cash',
      );
      expect(
        TransactionNoteLocalizationHelper.localizeNote(regularExpense),
        'Nạp năng lượng buổi sáng',
      );

      final enDeposit = AppTransaction(
        transactionId: 'tx_5',
        userId: 'u1',
        walletId: 'w_cash',
        categoryId: '',
        amount: 50000,
        type: 'goal_deposit',
        goalId: 'g_1',
        note: 'Deposit to goal "Laptop" from Cash',
        date: DateTime(2026, 11, 15),
      );
      await LanguageController.setLanguage('vi');
      expect(
        TransactionNoteLocalizationHelper.localizeNote(
          enDeposit,
          wallet: presetCash,
        ),
        'Nạp vào mục tiêu "Laptop" từ ví Tiền mặt',
      );
    });

    test('7.3. NotificationLocalizationHelper dịch động cả thông báo cũ trong Firestore và thông báo có key',
        () async {
      final legacyRecurringNotif = AppNotification(
        notificationId: 'n_1',
        userId: 'u1',
        title: 'Khoản Du lịch đến hạn hôm nay',
        content: 'Khoản chi 50.000 VNĐ cần bạn xác nhận để ghi nhận vào sổ.',
        type: 'recurring_due',
        createdAt: DateTime(2026, 11, 16, 16, 14),
        scheduleId: 's_1',
        occurrenceKey: '2026-11-16',
      );
      final legacyBudgetNotif = AppNotification(
        notificationId: 'n_2',
        userId: 'u1',
        title: 'Cảnh báo ngân sách',
        content: 'Bạn đã tiêu vượt 80% ngân sách tháng 11/2026 cho danh mục này.',
        type: 'budget',
        createdAt: DateTime(2026, 11, 12, 21, 55),
      );
      final keyedCustomNotif = AppNotification(
        notificationId: 'n_3',
        userId: 'u1',
        title: 'Khoản Thuê nhà tháng 11 đến hạn hôm nay',
        content: 'Khoản chi 3.000.000 VNĐ sẽ được tự động hạch toán.',
        type: 'recurring_due',
        createdAt: DateTime(2026, 11, 16),
        titleKey: 'svc_fs_rec_today_title',
        titleParams: const {'name': 'Thuê nhà tháng 11'},
        contentKey: 'svc_fs_rec_today_auto',
        contentParams: const {
          'dir': 'expense',
          'amount': '3.000.000 VNĐ',
        },
      );

      await LanguageController.setLanguage('en');
      expect(
        NotificationLocalizationHelper.localizeTitle(legacyRecurringNotif),
        'Travel is due today',
      );
      expect(
        NotificationLocalizationHelper.localizeContent(legacyRecurringNotif),
        'Recurring expense of 50.000 VND awaits your confirmation.',
      );
      expect(
        NotificationLocalizationHelper.localizeTitle(legacyBudgetNotif),
        'Budget Alert',
      );
      expect(
        NotificationLocalizationHelper.localizeContent(legacyBudgetNotif),
        'You have spent over 80% of your 11/2026 budget for this category.',
      );
      expect(
        NotificationLocalizationHelper.localizeTitle(keyedCustomNotif),
        'Thuê nhà tháng 11 is due today',
      );
      expect(
        NotificationLocalizationHelper.localizeContent(keyedCustomNotif),
        'Recurring expense of 3.000.000 VND will be posted automatically.',
      );

      await LanguageController.setLanguage('vi');
      expect(
        NotificationLocalizationHelper.localizeTitle(keyedCustomNotif),
        'Khoản Thuê nhà tháng 11 đến hạn hôm nay',
      );
      expect(
        NotificationLocalizationHelper.localizeContent(legacyBudgetNotif),
        'Bạn đã tiêu vượt 80% ngân sách tháng 11/2026 cho danh mục này.',
      );
    });

    test('7.4. LocalNotificationService đồng bộ ngôn ngữ tên danh mục và ví Tiền mặt',
        () async {
      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_travel',
        userId: 'u1',
        type: 'expense',
        walletId: 'w_cash',
        categoryId: 'cat_travel',
        note: 'Du lịch',
        amount: 50000,
        frequency: 'monthly',
        startDate: DateTime(2026, 11, 20),
        nextDueDate: DateTime(2026, 11, 20),
        isActive: true,
        createdAt: DateTime(2026, 11, 1),
        reminderDaysBefore: 1,
        postingMode: RecurringTransactionSchedule.postingModeManual,
      );

      await LanguageController.setLanguage('en');
      final enItems = LocalNotificationService.calculateScheduledNotifications(
        schedule: schedule,
        walletName: 'Tiền mặt',
        referenceDate: DateTime(2026, 11, 16, 10, 0),
        maxDaysAhead: 10,
      );
      expect(enItems, isNotEmpty);
      expect(enItems.first.title, contains('Travel'));
      expect(enItems.first.body, contains('Wallet: Cash'));

      await LanguageController.setLanguage('vi');
    });

    test('7.5. DataSufficiencyAssessment.tierLabel và PlanLifecycleStatus đồng bộ VI/EN',
        () async {
      const prelim = DataSufficiencyAssessment(
        tier: DataSufficiencyTier.preliminary,
        expenseTxCount: 4,
        totalTxCount: 4,
        activeDaysCount: 4,
        expenseCategoriesCovered: 2,
        qualifiedHistoryMonths: 0,
        isPartialMonth: true,
        daysElapsedInMonth: 16,
        totalDaysInMonth: 30,
        hasIncomeData: true,
        hasBudgetData: false,
        hasWalletBalance: true,
        hasSavingGoals: false,
        hasActivePlan: false,
        limitationNote: '',
      );

      await LanguageController.setLanguage('vi');
      expect(prelim.tierLabel, 'Dữ liệu sơ bộ đầu kỳ');
      expect(PlanLifecycleStatus.approved.localizedLabel, 'Đã phê duyệt');

      await LanguageController.setLanguage('en');
      expect(prelim.tierLabel, 'Early Preliminary Data');
      expect(PlanLifecycleStatus.approved.localizedLabel, 'Approved');

      await LanguageController.setLanguage('vi');
    });
  });
}
