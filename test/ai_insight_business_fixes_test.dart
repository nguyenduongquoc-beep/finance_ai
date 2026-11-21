import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_ai_app/l10n/app_localizations.dart';
import 'package:finance_ai_app/models/ai_runtime_config_model.dart';
import 'package:finance_ai_app/models/budget_model.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/financial_forecast_result.dart';
import 'package:finance_ai_app/models/monthly_financial_plan.dart';
import 'package:finance_ai_app/models/recurring_transaction_model.dart';
import 'package:finance_ai_app/models/saving_goal_model.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/screens/ai/ai_insight_screen.dart';
import 'package:finance_ai_app/services/ai_prompt_builder.dart';
import 'package:finance_ai_app/services/ai_service.dart';
import 'package:finance_ai_app/services/financial_analytics_service.dart';
import 'package:finance_ai_app/services/financial_context_revision_tracker.dart';
import 'package:finance_ai_app/services/financial_export_service.dart';
import 'package:finance_ai_app/services/financial_forecast_service.dart';
import 'package:finance_ai_app/services/firestore_service.dart';
import 'package:finance_ai_app/services/language_controller.dart';
import 'package:finance_ai_app/utils/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LanguageController.loadSavedLanguage();
    await LanguageController.setLanguage('vi');
  });

  AppTransaction makeTx({
    required String id,
    required String type,
    required double amount,
    required String categoryId,
    required DateTime date,
    String userId = 'u1',
    String walletId = 'w1',
  }) {
    return AppTransaction(
      transactionId: id,
      userId: userId,
      walletId: walletId,
      categoryId: categoryId,
      amount: amount,
      type: type,
      date: date,
    );
  }

  MonthlyFinancialPlan makePlan({
    required String targetMonth,
    required PlanLifecycleStatus status,
    double referenceIncome = 20000000,
    double essentialCap = 8000000,
    double flexibleCap = 6000000,
    double targetSaving = 6000000,
  }) {
    final allocs = [
      PlannedCategoryAllocation(
        categoryId: 'c_ess',
        categoryName: 'Tiền nhà',
        isEssential: true,
        sourceMonthSpent: essentialCap,
        regularBaselineSpent: essentialCap,
        historicalMedian: essentialCap,
        floorLimit: essentialCap,
        recommendedLimit: essentialCap,
        deltaFromCurrent: 0,
        calculationBasis: 'Chi phí thiết yếu',
        aiActionTip: 'Giữ nguyên chi phí cố định',
      ),
      PlannedCategoryAllocation(
        categoryId: 'c_flex',
        categoryName: 'Ăn uống',
        isEssential: false,
        sourceMonthSpent: flexibleCap,
        regularBaselineSpent: flexibleCap,
        historicalMedian: flexibleCap,
        floorLimit: flexibleCap * 0.7,
        recommendedLimit: flexibleCap,
        deltaFromCurrent: 0,
        calculationBasis: 'Chi phí linh hoạt',
        aiActionTip: 'Chia ngân sách theo tuần',
      ),
    ];

    final now = DateTime(2026, 11, 21);
    return MonthlyFinancialPlan(
      planId: 'u1_${targetMonth.replaceAll('/', '-')}',
      userId: 'u1',
      sourceMonth: '11/2026',
      targetMonth: targetMonth,
      status: status,
      dataTierUsed: DataSufficiencyTier.currentMonthAnalysis,
      incomeMode: IncomeStabilityMode.stable,
      referenceIncome: referenceIncome,
      essentialExpenseCap: essentialCap,
      flexibleExpenseCap: flexibleCap,
      targetSavingAmount: targetSaving,
      desiredGoalSavingAmount: targetSaving,
      isSavingGoalFeasible: true,
      currentAllocations: allocs,
      originalSnapshot: PlanSnapshotData(
        referenceIncome: referenceIncome,
        essentialExpenseTotal: essentialCap,
        flexibleExpenseTotal: flexibleCap,
        targetSavingAmount: targetSaving,
        allocations: allocs,
        capturedAt: now,
      ),
      aiExecutiveSummary: 'Kế hoạch mẫu.',
      createdAt: now,
      updatedAt: now,
    );
  }

  group('1 & 2. Cấu hình hằng số chuẩn & AiService isEnabled=false fallback mượt mà',
      () {
    test(
      'AiService dùng trực tiếp AiRuntimeConfig.defaults() và khi isEnabled=false bỏ qua gọi Gemini',
      () async {
        // Mặc định dùng trực tiếp cấu hình chuẩn cố định (không đọc Firestore)
        final defaultAi = AiService(allowMissingApiKeyForTest: true);
        expect(defaultAi.effectiveRuntimeConfig.isEnabled, isTrue);
        expect(
          defaultAi.effectiveRuntimeConfig.primaryModel,
          AiRuntimeConfig.kDefaultPrimaryModel,
        );

        // Xác minh AiService.explainFinancialInsightsStructured bỏ qua gọi Gemini API hoàn toàn khi isEnabled=false
        int geminiCallCount = 0;
        final aiService = AiService(
          allowMissingApiKeyForTest: true,
          runtimeConfigOverride:
              AiRuntimeConfig.defaults().copyWith(isEnabled: false),
          contentGeneratorOverride: (modelName, content, temp) async {
            geminiCallCount++;
            return '{"executiveSummary": "Should never be called"}';
          },
        );

        final forecastService = FinancialForecastService();
        final summary = forecastService.generateSummary(
          activeWallets: [
            Wallet(
              walletId: 'w1',
              userId: 'u1',
              walletName: 'Ví chính',
              balance: 15000000,
              type: 'bank',
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
          currentMonthBudgets: const [],
          categories: const [],
          currentMonthTx: [
            makeTx(
              id: 't_inc',
              type: 'income',
              amount: 20000000,
              categoryId: 'c_inc',
              date: DateTime(2026, 11, 5),
            ),
            makeTx(
              id: 't_exp',
              type: 'expense',
              amount: 8000000,
              categoryId: 'c_ess',
              date: DateTime(2026, 11, 10),
            ),
          ],
          preceding3MonthsTx: const [[], [], []],
          monthlyIncome: 20000000,
          issues: const [],
          refDate: DateTime(2026, 11, 21),
        );

        final draftPlan = makePlan(
          targetMonth: '12/2026',
          status: PlanLifecycleStatus.draft,
        );

        final insight = await aiService.explainFinancialInsightsStructured(
          summary: summary,
          draftPlan: draftPlan,
        );

        expect(geminiCallCount, 0);
        expect(insight.isFromFallback, isTrue);
        expect(insight.executiveSummary, isNotEmpty);
        expect(insight.behavioralInsights, isNotEmpty);
        expect(insight.savingStrategyNote, isNotEmpty);
      },
    );
  });

  group('3. computeIncomeAnalytics & generateSummary không đếm trùng m1Tx', () {
    final analytics = FinancialAnalyticsService();
    final forecast = FinancialForecastService();
    final incomeCategories = [
      Category(
        categoryId: 'c_sal',
        userId: 'u1',
        name: 'Lương',
        type: 'income',
        icon: 'payments',
        color: 0xFF4CAF50,
      ),
    ];

    test(
      '1 tháng lịch sử (m1=10M, cur=20M): CV thực tế = 0.333 (Biến động nhẹ), không bị lặp m1 thành Biến động mạnh',
      () {
        // Nếu m1 bị cộng 2 lần: [10M, 10M, 20M] -> mean=13.33M, std=4.714M, CV=0.3536 > 0.35 (SAI: Biến động mạnh)
        // Không lặp m1: [10M, 20M] -> mean=15M, std=5M, CV=0.3333 <= 0.35 (ĐÚNG: Biến động nhẹ)
        final m1 = [
          makeTx(
            id: 'in_m1',
            type: 'income',
            amount: 10000000,
            categoryId: 'c_sal',
            date: DateTime(2026, 10, 5),
          ),
        ];
        final cur = [
          makeTx(
            id: 'in_cur',
            type: 'income',
            amount: 20000000,
            categoryId: 'c_sal',
            date: DateTime(2026, 11, 5),
          ),
        ];

        // Kiểm tra qua FinancialForecastService.generateSummary (luồng thật của AI Insight)
        final summary = forecast.generateSummary(
          activeWallets: const [],
          currentMonthBudgets: const [],
          categories: incomeCategories,
          currentMonthTx: cur,
          preceding3MonthsTx: [const [], const [], m1],
          monthlyIncome: 20000000,
          issues: const [],
          refDate: DateTime(2026, 11, 21),
        );

        expect(summary.incomeAnalytics.growthRate, closeTo(1.0, 0.001));
        expect(
          summary.incomeAnalytics.stability,
          AppLocalizations.tr('svc_fa_stab_mild'),
        );

        // Kiểm tra cả khi gọi trực tiếp computeIncomeAnalytics với precedingMonthsTx chứa bản sao m1
        final directWithCopy = analytics.computeIncomeAnalytics(
          currentMonthTx: cur,
          lastMonthTx: m1,
          categories: incomeCategories,
          precedingMonthsTx: [List<AppTransaction>.from(m1)],
        );
        expect(directWithCopy.growthRate, closeTo(1.0, 0.001));
        expect(
          directWithCopy.stability,
          AppLocalizations.tr('svc_fa_stab_mild'),
        );
      },
    );

    test(
      '2 tháng và >= 3 tháng lịch sử: giữ nguyên các tháng có cùng mức lương nhưng khác txId và tính CV chính xác',
      () {
        final m3 = [
          makeTx(
            id: 'in_m3',
            type: 'income',
            amount: 15000000,
            categoryId: 'c_sal',
            date: DateTime(2026, 8, 5),
          ),
        ];
        final m2 = [
          makeTx(
            id: 'in_m2',
            type: 'income',
            amount: 15000000,
            categoryId: 'c_sal',
            date: DateTime(2026, 9, 5),
          ),
        ];
        final m1 = [
          makeTx(
            id: 'in_m1',
            type: 'income',
            amount: 15000000,
            categoryId: 'c_sal',
            date: DateTime(2026, 10, 5),
          ),
        ];
        final cur = [
          makeTx(
            id: 'in_cur',
            type: 'income',
            amount: 15000000,
            categoryId: 'c_sal',
            date: DateTime(2026, 11, 5),
          ),
        ];

        // 3 tháng lịch sử đều 15M -> Ổn định, tăng trưởng 0%
        final stableSummary = forecast.generateSummary(
          activeWallets: const [],
          currentMonthBudgets: const [],
          categories: incomeCategories,
          currentMonthTx: cur,
          preceding3MonthsTx: [m3, m2, m1],
          monthlyIncome: 15000000,
          issues: const [],
          refDate: DateTime(2026, 11, 21),
        );
        expect(stableSummary.incomeAnalytics.growthRate, closeTo(0.0, 0.001));
        expect(
          stableSummary.incomeAnalytics.stability,
          AppLocalizations.tr('svc_fa_stab_stable'),
        );

        // 2 tháng lịch sử: m2=20M, m1=5M, cur=20M
        // Không lặp m1: [20M, 5M, 20M] -> mean=15M, std=7.071M, CV=0.4714 (> 0.35 -> Biến động mạnh)
        // Kiểm tra thêm trường hợp biên: m2=20M, m1=20M, cur=10M -> [20, 20, 10] mean=16.67, std=4.714, CV=0.283 (Biến động nhẹ)
        final m2High = [
          makeTx(
            id: 'in_m2_h',
            type: 'income',
            amount: 20000000,
            categoryId: 'c_sal',
            date: DateTime(2026, 9, 5),
          ),
        ];
        final m1High = [
          makeTx(
            id: 'in_m1_h',
            type: 'income',
            amount: 20000000,
            categoryId: 'c_sal',
            date: DateTime(2026, 10, 5),
          ),
        ];
        final curLow = [
          makeTx(
            id: 'in_cur_l',
            type: 'income',
            amount: 10000000,
            categoryId: 'c_sal',
            date: DateTime(2026, 11, 5),
          ),
        ];
        final twoMonthSummary = forecast.generateSummary(
          activeWallets: const [],
          currentMonthBudgets: const [],
          categories: incomeCategories,
          currentMonthTx: curLow,
          preceding3MonthsTx: [const [], m2High, m1High],
          monthlyIncome: 10000000,
          issues: const [],
          refDate: DateTime(2026, 11, 21),
        );
        expect(twoMonthSummary.incomeAnalytics.growthRate, closeTo(-0.5, 0.001));
        expect(
          twoMonthSummary.incomeAnalytics.stability,
          AppLocalizations.tr('svc_fa_stab_mild'),
        );
      },
    );
  });

  group('4. Thống nhất Điểm Sức khỏe Tài chính giữa AI Insight và Export PDF',
      () {
    test(
      'FinancialForecastService.generateSummary và FinancialExportService.buildReportData trả về cùng healthScore & healthRating',
      () {
        final analytics = FinancialAnalyticsService();
        final forecast = FinancialForecastService();
        final exportService = FinancialExportService(
          analyticsService: analytics,
          forecastService: forecast,
        );

        final refDate = DateTime(2026, 11, 20);
        final wallets = [
          Wallet(
            walletId: 'w1',
            userId: 'u1',
            walletName: 'Ngân hàng',
            balance: 4000000,
            type: 'bank',
            isActive: true,
            createdAt: DateTime(2026, 1, 1),
          ),
        ];
        final categories = [
          Category(
            categoryId: 'c_food',
            userId: 'u1',
            name: 'Ăn uống',
            type: 'expense',
            icon: 'restaurant',
            color: 0xFFFF7043,
          ),
          Category(
            categoryId: 'c_shop',
            userId: 'u1',
            name: 'Mua sắm',
            type: 'expense',
            icon: 'shopping_bag',
            color: 0xFFAB47BC,
          ),
          Category(
            categoryId: 'c_sal',
            userId: 'u1',
            name: 'Lương',
            type: 'income',
            icon: 'payments',
            color: 0xFF4CAF50,
          ),
        ];
        final budgets = [
          Budget(
            budgetId: 'b_food',
            userId: 'u1',
            categoryId: 'c_food',
            limit: 3000000,
            month: '11/2026',
          ),
          Budget(
            budgetId: 'b_shop',
            userId: 'u1',
            categoryId: 'c_shop',
            limit: 2000000,
            month: '11/2026',
          ),
        ];
        final goals = [
          SavingGoal(
            goalId: 'g1',
            userId: 'u1',
            name: 'Quỹ dự phòng',
            targetAmount: 30000000,
            savedAmount: 5000000,
            months: 10,
            createdAt: DateTime(2026, 1, 1),
          ),
        ];
        final recurring = [
          RecurringTransactionSchedule(
            scheduleId: 'r1',
            userId: 'u1',
            type: 'expense',
            walletId: 'w1',
            categoryId: 'c_food',
            amount: 1000000,
            note: 'Tiền internet',
            frequency: 'monthly',
            startDate: DateTime(2026, 1, 25),
            nextDueDate: DateTime(2026, 11, 25),
            isActive: true,
            createdAt: DateTime(2026, 1, 1),
          ),
        ];

        final m3 = [
          makeTx(
            id: 'm3_f',
            type: 'expense',
            amount: 2000000,
            categoryId: 'c_food',
            date: DateTime(2026, 8, 10),
          ),
        ];
        final m2 = [
          makeTx(
            id: 'm2_f',
            type: 'expense',
            amount: 2000000,
            categoryId: 'c_food',
            date: DateTime(2026, 9, 10),
          ),
        ];
        final m1 = [
          makeTx(
            id: 'm1_inc',
            type: 'income',
            amount: 12000000,
            categoryId: 'c_sal',
            date: DateTime(2026, 10, 5),
          ),
          makeTx(
            id: 'm1_f',
            type: 'expense',
            amount: 2000000,
            categoryId: 'c_food',
            date: DateTime(2026, 10, 10),
          ),
        ];
        final cur = [
          makeTx(
            id: 'cur_inc',
            type: 'income',
            amount: 10000000,
            categoryId: 'c_sal',
            date: DateTime(2026, 11, 5),
          ),
          // Vượt ngân sách c_food (4M > 3M) và vượt mạnh lịch sử (2M) -> bị cap chống phạt trùng 20đ
          makeTx(
            id: 'cur_f',
            type: 'expense',
            amount: 4000000,
            categoryId: 'c_food',
            date: DateTime(2026, 11, 12),
          ),
          // Chi 5M mua sắm -> vượt ngân sách c_shop (5M > 2M), tổng chi 9M/10M (tiết kiệm 10% < 20%)
          makeTx(
            id: 'cur_s',
            type: 'expense',
            amount: 5000000,
            categoryId: 'c_shop',
            date: DateTime(2026, 11, 15),
          ),
        ];

        final issues = analytics.detectIssues(
          currentMonthTx: cur,
          lastMonthTx: m1,
          categories: categories,
          monthlyIncome: 10000000,
        );

        final insightSummary = forecast.generateSummary(
          activeWallets: wallets,
          currentMonthBudgets: budgets,
          categories: categories,
          currentMonthTx: cur,
          preceding3MonthsTx: [m3, m2, m1],
          monthlyIncome: 10000000,
          issues: issues,
          savingGoals: goals,
          recurringSchedules: recurring,
          refDate: refDate,
        );

        final exportReport = exportService.buildReportData(
          currentPeriodTx: cur,
          wallets: wallets,
          categories: categories,
          budgets: budgets,
          savingGoals: goals,
          periodLabel: 'Tháng 11/2026',
          isCurrentMonth: true,
          lastMonthTx: m1,
          preceding3MonthsTx: [m3, m2, m1],
          monthlyIncome: 10000000,
          recurringSchedules: recurring,
          refDate: refDate,
        );

        expect(exportReport.healthScore, equals(insightSummary.healthScore));
        expect(exportReport.healthRating, equals(insightSummary.healthRating));

        // Kiểm tra thêm tháng quá khứ (isCurrentMonth: false): không có monthEndForecast nhưng vẫn chấm điểm ổn định
        final pastReport = exportService.buildReportData(
          currentPeriodTx: m1,
          wallets: wallets,
          categories: categories,
          budgets: budgets,
          savingGoals: goals,
          periodLabel: 'Tháng 10/2026',
          isCurrentMonth: false,
          refDate: refDate,
        );
        expect(pastReport.monthEndForecast, isNull);
        expect(pastReport.healthScore, inInclusiveRange(0, 100));
        expect(
          pastReport.healthRating,
          equals(forecast.resolveHealthRating(pastReport.healthScore)),
        );
      },
    );
  });

  group('5. Màu trạng thái BudgetForecastStatus.warning', () {
    test('Phân tách rõ 4 màu cho exceeded, atRisk, warning và safe', () {
      expect(
        AiInsightScreen.budgetForecastStatusColor(BudgetForecastStatus.exceeded),
        equals(AppColors.expense),
      );
      expect(
        AiInsightScreen.budgetForecastStatusColor(BudgetForecastStatus.atRisk),
        equals(Colors.deepOrange),
      );
      expect(
        AiInsightScreen.budgetForecastStatusColor(BudgetForecastStatus.warning),
        equals(AppColors.warning),
      );
      expect(
        AiInsightScreen.budgetForecastStatusColor(BudgetForecastStatus.warning),
        isNot(equals(AppColors.income)),
      );
      expect(
        AiInsightScreen.budgetForecastStatusColor(BudgetForecastStatus.safe),
        equals(AppColors.income),
      );
    });
  });

  group('6. updateUserProfile kích hoạt FinancialContextRevisionTracker', () {
    test(
      'Cập nhật monthlyIncome qua FirestoreService.updateUserProfile tăng localMutationVersion',
      () async {
        final fakeFirestore = FakeFirebaseFirestore();
        final firestoreService = FirestoreService(firestore: fakeFirestore);

        await fakeFirestore.collection('users').doc('u1').set({
          'name': 'Tester',
          'email': 'tester@example.com',
          'monthlyIncome': 12000000,
        });

        final beforeVersion =
            FinancialContextRevisionTracker.localMutationVersion;

        await firestoreService.updateUserProfile('u1', {
          'monthlyIncome': 25000000.0,
        });

        expect(
          FinancialContextRevisionTracker.localMutationVersion,
          equals(beforeVersion + 1),
        );

        final updatedDoc =
            await fakeFirestore.collection('users').doc('u1').get();
        expect(updatedDoc.data()?['monthlyIncome'], equals(25000000.0));
      },
    );
  });

  group('7. Kế hoạch tháng tương lai (T+1) không chấm điểm sớm trên Tracker', () {
    final analytics = FinancialAnalyticsService();

    test(
      'evaluatePlanExecution đánh dấu isUpcoming=true và không chấm điểm giả 60/100 cho tháng T+1',
      () {
        final upcomingPlan = makePlan(
          targetMonth: '12/2026',
          status: PlanLifecycleStatus.approved,
        );

        final tracker = analytics.evaluatePlanExecution(
          plan: upcomingPlan,
          targetMonthTx: const [],
          referenceToday: DateTime(2026, 11, 21),
        );

        expect(tracker.isUpcoming, isTrue);
        expect(tracker.elapsedMonthRatio, equals(0.0));
        expect(tracker.overallAdherenceScore, equals(0.0));
        expect(tracker.budgetAdherenceScore, equals(0.0));
        expect(tracker.savingAdherenceScore, equals(0.0));
        expect(tracker.needsRebalance, isFalse);
        expect(tracker.activationDateLabel, equals('01/12/2026'));
        expect(tracker.categoryStatuses.every((c) => c.isUpcoming), isTrue);

        // Ngược lại, kế hoạch tháng hiện tại vẫn chấm điểm bình thường
        final currentPlan = makePlan(
          targetMonth: '11/2026',
          status: PlanLifecycleStatus.active,
        );
        final activeTracker = analytics.evaluatePlanExecution(
          plan: currentPlan,
          targetMonthTx: [
            makeTx(
              id: 't_in',
              type: 'income',
              amount: 20000000,
              categoryId: 'c_inc',
              date: DateTime(2026, 11, 5),
            ),
            makeTx(
              id: 't_e1',
              type: 'expense',
              amount: 8000000,
              categoryId: 'c_ess',
              date: DateTime(2026, 11, 6),
            ),
          ],
          referenceToday: DateTime(2026, 11, 21),
        );
        expect(activeTracker.isUpcoming, isFalse);
        expect(activeTracker.overallAdherenceScore, greaterThan(0));
      },
    );

    testWidgets(
      'AiUpcomingPlanCard hiển thị đúng VI/EN, không hiện điểm 60/100 và không tràn layout ở 320dp x 1.2x',
      (tester) async {
        final upcomingPlan = makePlan(
          targetMonth: '12/2026',
          status: PlanLifecycleStatus.approved,
        );

        for (final lang in ['vi', 'en']) {
          await LanguageController.setLanguage(lang);
          await tester.binding.setSurfaceSize(const Size(320, 700));

          final errors = <FlutterErrorDetails>[];
          final prevOnError = FlutterError.onError;
          FlutterError.onError = (details) => errors.add(details);

          try {
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(lang),
                supportedLocales: const [Locale('vi'), Locale('en')],
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.2),
                  ),
                  child: child ?? const SizedBox.shrink(),
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: AiUpcomingPlanCard(
                      plan: upcomingPlan,
                      onAdjust: () {},
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            if (lang == 'vi') {
              expect(
                find.text('Đã phê duyệt — Chờ kích hoạt ngày 01/12/2026'),
                findsOneWidget,
              );
              expect(find.text('Ngân sách dự kiến'), findsOneWidget);
              expect(find.text('Tiết kiệm dự kiến'), findsOneWidget);
            } else {
              expect(
                find.text('Approved — Scheduled to activate on 01/12/2026'),
                findsOneWidget,
              );
              expect(find.text('Planned Budget'), findsOneWidget);
              expect(find.text('Planned Savings'), findsOneWidget);
            }

            // Không hiển thị điểm thực thi giả 60/100 hay bất kỳ điểm /100 nào
            expect(find.textContaining('/100'), findsNothing);
            expect(errors, isEmpty, reason: 'Layout errors in $lang: $errors');
          } finally {
            FlutterError.onError = prevOnError;
            await tester.binding.setSurfaceSize(null);
          }
        }
      },
    );
  });

  group('8. Bộ chọn tháng mục tiêu (T vs T+1) & Trạng thái áp dụng (active vs approved)',
      () {
    testWidgets(
      'AiTargetMonthSelector chuyển đổi mượt giữa T và T+1, hỗ trợ VI/EN không tràn ở 320dp x 1.2x',
      (tester) async {
        for (final lang in ['vi', 'en']) {
          await LanguageController.setLanguage(lang);
          await tester.binding.setSurfaceSize(const Size(320, 700));

          String selected = '12/2026';
          final tapped = <String>[];
          final errors = <FlutterErrorDetails>[];
          final prevOnError = FlutterError.onError;
          FlutterError.onError = (details) => errors.add(details);

          try {
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(lang),
                supportedLocales: const [Locale('vi'), Locale('en')],
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.2),
                  ),
                  child: child ?? const SizedBox.shrink(),
                ),
                home: StatefulBuilder(
                  builder: (context, setState) => Scaffold(
                    body: Padding(
                      padding: const EdgeInsets.all(16),
                      child: AiTargetMonthSelector(
                        currentMonth: '11/2026',
                        nextMonth: '12/2026',
                        selectedMonth: selected,
                        onSelected: (month) {
                          tapped.add(month);
                          setState(() => selected = month);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            final currentLabel =
                lang == 'vi' ? 'Tháng này (11/2026)' : 'This Month (11/2026)';
            final nextLabel =
                lang == 'vi' ? 'Tháng sau (12/2026)' : 'Next Month (12/2026)';

            expect(find.text(currentLabel), findsOneWidget);
            expect(find.text(nextLabel), findsOneWidget);

            await tester.tap(find.text(currentLabel));
            await tester.pumpAndSettle();
            expect(selected, equals('11/2026'));

            await tester.tap(find.text(nextLabel));
            await tester.pumpAndSettle();
            expect(selected, equals('12/2026'));
            expect(tapped, equals(['11/2026', '12/2026']));
            expect(errors, isEmpty, reason: 'Layout errors in $lang: $errors');
          } finally {
            FlutterError.onError = prevOnError;
            await tester.binding.setSurfaceSize(null);
          }
        }
      },
    );

    test(
      'commitMonthlyPlanTransactionally phân biệt active (tháng T) vs approved (tháng T+1) và giữ nguyên kiểm tra OCC',
      () async {
        final fakeFirestore = FakeFirebaseFirestore();
        final firestoreService = FirestoreService(firestore: fakeFirestore);
        final refDate = DateTime(2026, 11, 21);

        // Áp dụng cho Tháng hiện tại (T = 11/2026) -> status = active
        final currentPlanDraft = makePlan(
          targetMonth: '11/2026',
          status: PlanLifecycleStatus.draft,
        );
        final committedCurrent =
            await firestoreService.commitMonthlyPlanTransactionally(
          planToCommit: currentPlanDraft,
          selectedCategoryIds: {'c_ess', 'c_flex'},
          expectedExistingBudgets: const {},
          submissionToken: 'tok_current_11_2026',
          currentReferenceDate: refDate,
        );
        expect(committedCurrent.status, equals(PlanLifecycleStatus.active));

        // Áp dụng cho Tháng kế tiếp (T+1 = 12/2026) -> status = approved
        final nextPlanDraft = makePlan(
          targetMonth: '12/2026',
          status: PlanLifecycleStatus.draft,
        );
        final committedNext =
            await firestoreService.commitMonthlyPlanTransactionally(
          planToCommit: nextPlanDraft,
          selectedCategoryIds: {'c_ess'},
          expectedExistingBudgets: const {},
          submissionToken: 'tok_next_12_2026',
          currentReferenceDate: refDate,
        );
        expect(committedNext.status, equals(PlanLifecycleStatus.approved));

        // Kiểm tra OCC: nếu ngân sách tháng T đã bị đổi so với expectedExistingBudgets -> ném PlanBudgetConflictException
        await expectLater(
          () => firestoreService.commitMonthlyPlanTransactionally(
            planToCommit: currentPlanDraft,
            selectedCategoryIds: {'c_ess'},
            expectedExistingBudgets: const {'c_ess': 1000000.0},
            submissionToken: 'tok_conflict_11_2026',
            currentReferenceDate: refDate,
          ),
          throwsA(isA<PlanBudgetConflictException>()),
        );
      },
    );
  });

  group('9. Loại bỏ mâu thuẫn trạng thái giữa Mục tiêu tiết kiệm con và Tổng quan',
      () {
    final analytics = FinancialAnalyticsService();

    test(
      'Nhiều mục tiêu: mỗi mục tiêu < netCashFlow nhưng tổng > netCashFlow -> báo sharedSurplusTight (Vàng), không báo xanh Đúng tiến độ',
      () async {
        final goals = [
          SavingGoal(
            goalId: 'g1',
            userId: 'u1',
            name: 'Laptop',
            targetAmount: 30000000,
            savedAmount: 0,
            months: 10, // Cần 3.000.000/tháng
            createdAt: DateTime(2026, 1, 1),
          ),
          SavingGoal(
            goalId: 'g2',
            userId: 'u1',
            name: 'Du lịch',
            targetAmount: 18000000,
            savedAmount: 0,
            months: 6, // Cần 3.000.000/tháng
            createdAt: DateTime(2026, 1, 2),
          ),
        ];

        // Tổng cần = 6M/tháng, thặng dư = 4M/tháng (riêng từng mục tiêu 3M <= 4M, nhưng song song thiếu 2M)
        await LanguageController.setLanguage('vi');
        final viAssessment = analytics.evaluateSavingGoals(
          goals: goals,
          netCashFlow: 4000000,
        );
        expect(viAssessment.canFulfillAllGoals, isFalse);
        expect(viAssessment.gapAmount, equals(2000000.0));
        expect(viAssessment.goals.length, equals(2));
        for (final item in viAssessment.goals) {
          expect(
            item.feasibilityStatus,
            equals(GoalFeasibilityStatus.sharedSurplusTight),
          );
          expect(item.isAtRisk, isTrue);
          expect(item.allocatedMonthlyCashFlow, closeTo(2000000.0, 1.0));
          expect(item.statusText, equals('Cần chia sẻ thặng dư'));
          expect(item.suggestion, contains('chạy riêng'));
        }
        expect(
          AiInsightScreen.goalFeasibilityStatusColor(
            GoalFeasibilityStatus.sharedSurplusTight,
          ),
          equals(AppColors.warning),
        );

        // Kiểm tra song ngữ tiếng Anh
        await LanguageController.setLanguage('en');
        final enAssessment = analytics.evaluateSavingGoals(
          goals: goals,
          netCashFlow: 4000000,
        );
        for (final item in enAssessment.goals) {
          expect(
            item.feasibilityStatus,
            equals(GoalFeasibilityStatus.sharedSurplusTight),
          );
          expect(item.statusText, equals('Shared Surplus Tight'));
          expect(item.suggestion, contains('Feasible solo'));
        }
        await LanguageController.setLanguage('vi');
      },
    );

    test(
      'Hỗn hợp mục tiêu quá sức (atRisk) + mục tiêu chia sẻ thặng dư (sharedSurplusTight) và trường hợp đủ toàn bộ (onTrack)',
      () {
        final mixedGoals = [
          SavingGoal(
            goalId: 'g_big',
            userId: 'u1',
            name: 'Mua xe',
            targetAmount: 50000000,
            savedAmount: 0,
            months: 10, // Cần 5M/tháng (> 4M) -> atRisk
            createdAt: DateTime(2026, 1, 1),
          ),
          SavingGoal(
            goalId: 'g_small',
            userId: 'u1',
            name: 'Quỹ dự phòng',
            targetAmount: 12000000,
            savedAmount: 0,
            months: 6, // Cần 2M/tháng (<= 4M, tổng 7M > 4M) -> sharedSurplusTight
            createdAt: DateTime(2026, 1, 2),
          ),
        ];

        final mixed = analytics.evaluateSavingGoals(
          goals: mixedGoals,
          netCashFlow: 4000000,
        );
        expect(mixed.canFulfillAllGoals, isFalse);
        expect(
          mixed.goals[0].feasibilityStatus,
          equals(GoalFeasibilityStatus.atRisk),
        );
        expect(
          mixed.goals[1].feasibilityStatus,
          equals(GoalFeasibilityStatus.sharedSurplusTight),
        );
        expect(
          mixed.goals.any(
            (g) => g.feasibilityStatus == GoalFeasibilityStatus.onTrack,
          ),
          isFalse,
        );

        // Khi thặng dư = 8M >= tổng 7M -> tất cả đều onTrack (Xanh lá)
        final sufficient = analytics.evaluateSavingGoals(
          goals: mixedGoals,
          netCashFlow: 8000000,
        );
        expect(sufficient.canFulfillAllGoals, isTrue);
        expect(
          sufficient.goals.every(
            (g) =>
                g.feasibilityStatus == GoalFeasibilityStatus.onTrack &&
                !g.isAtRisk,
          ),
          isTrue,
        );
        expect(
          AiInsightScreen.goalFeasibilityStatusColor(
            GoalFeasibilityStatus.onTrack,
          ),
          equals(AppColors.income),
        );
        expect(
          AiInsightScreen.goalFeasibilityStatusColor(
            GoalFeasibilityStatus.atRisk,
          ),
          equals(AppColors.expense),
        );
      },
    );
  });

  group('10. Tối ưu tính lười (lazy/on-demand) cho summary.actionPlan', () {
    test(
      'generateSummary không tính actionPlan trong luồng AI Insight bình thường; chỉ tính và cache khi fallback đọc tới',
      () {
        final forecast = FinancialForecastService();
        final categories = [
          Category(
            categoryId: 'c_food',
            userId: 'u1',
            name: 'Ăn uống',
            type: 'expense',
            icon: 'restaurant',
            color: 0xFFFF7043,
          ),
        ];
        final budgets = [
          Budget(
            budgetId: 'b1',
            userId: 'u1',
            categoryId: 'c_food',
            limit: 2000000,
            month: '11/2026',
          ),
        ];
        final tx = [
          makeTx(
            id: 't_inc',
            type: 'income',
            amount: 15000000,
            categoryId: 'c_inc',
            date: DateTime(2026, 11, 5),
          ),
          makeTx(
            id: 't_exp',
            type: 'expense',
            amount: 3500000,
            categoryId: 'c_food',
            date: DateTime(2026, 11, 10),
          ),
        ];

        final summary = forecast.generateSummary(
          activeWallets: const [],
          currentMonthBudgets: budgets,
          categories: categories,
          currentMonthTx: tx,
          preceding3MonthsTx: const [[], [], []],
          monthlyIncome: 15000000,
          issues: const [],
          refDate: DateTime(2026, 11, 21),
        );

        // Chưa từng đọc actionPlan -> không tính thừa
        expect(summary.hasComputedActionPlan, isFalse);

        // Luồng chính (Structured Plan Prompt) không chạm vào summary.actionPlan
        final draftPlan = makePlan(
          targetMonth: '12/2026',
          status: PlanLifecycleStatus.draft,
        );
        AiPromptBuilder.buildStructuredPlanPrompt(
          summary: summary,
          draftPlan: draftPlan,
        );
        expect(summary.hasComputedActionPlan, isFalse);

        // Luồng fallback (buildFinancialInsightsPrompt khi draftPlan == null) mới kích hoạt tính lười
        final legacyPrompt = AiPromptBuilder.buildFinancialInsightsPrompt(
          summary,
        );
        expect(summary.hasComputedActionPlan, isTrue);
        expect(legacyPrompt, contains('KẾ HOẠCH HÀNH ĐỘNG ĐỀ XUẤT'));

        // Các lần đọc tiếp theo trả về đúng instance đã cache
        final firstPlan = summary.actionPlan;
        final secondPlan = summary.actionPlan;
        expect(identical(firstPlan, secondPlan), isTrue);
        expect(firstPlan.items, isNotEmpty);
      },
    );
  });
}
