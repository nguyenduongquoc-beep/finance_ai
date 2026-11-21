import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/ai_runtime_config_model.dart';
import 'package:finance_ai_app/models/budget_model.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/financial_forecast_result.dart';
import 'package:finance_ai_app/models/financial_issue.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/user_model.dart';
import 'package:finance_ai_app/services/ai_service.dart';
import 'package:finance_ai_app/services/financial_analytics_service.dart';
import 'package:finance_ai_app/services/financial_chat_context_service.dart';
import 'package:finance_ai_app/services/financial_forecast_service.dart';
import 'package:finance_ai_app/services/transaction_intelligence_service.dart';

void main() {
  group('Giai đoạn 1.1: Gemini Model Whitelist & AiRuntimeConfig', () {
    test('1. Chỉ chấp nhận các Model ID trong Whitelist, phân loại kênh phát hành và không dùng alias động làm fallback duy nhất', () {
      expect(isSupportedGeminiModelId('gemini-3.5-flash'), isTrue);
      expect(isSupportedGeminiModelId('gemini-3.5-flash-lite'), isTrue);
      expect(isSupportedGeminiModelId('gemini-3.6-flash'), isTrue);
      expect(isSupportedGeminiModelId('gemini-3.7-flash'), isTrue);
      expect(isSupportedGeminiModelId('gemini-3.8-flash'), isTrue);
      expect(isSupportedGeminiModelId('gemini-3-flash-preview'), isTrue);
      expect(isSupportedGeminiModelId('gemini-2.5-flash'), isTrue);
      expect(isSupportedGeminiModelId('gemini-1.0-pro-legacy'), isFalse);
      expect(isSupportedGeminiModelId('custom-unverified-model'), isFalse);

      // Phân loại rõ Stable / Preview / Legacy / Mutable Alias
      expect(findGeminiModelDescriptor('gemini-3.5-flash')?.isStable, isTrue);
      expect(findGeminiModelDescriptor('gemini-3.8-flash')?.isStable, isTrue);
      expect(findGeminiModelDescriptor('gemini-2.5-flash')?.isLegacy, isTrue);
      expect(
        findGeminiModelDescriptor('gemini-2.5-flash')?.isRecommendedPrimary,
        isFalse,
      );
      expect(
        findGeminiModelDescriptor('gemini-flash-latest')?.isMutableAlias,
        isTrue,
      );

      // Không cho phép dùng alias động làm model chính hoặc làm fallback duy nhất
      final chainWithOnlyAlias = sanitizeGeminiModelChain(
        primaryModel: 'gemini-flash-latest',
        fallbackModels: const ['gemini-flash-latest'],
      );
      expect(chainWithOnlyAlias.first, 'gemini-3.5-flash');
      // Phải tự động chèn model ổn định đứng trước gemini-flash-latest
      expect(chainWithOnlyAlias[1], 'gemini-3.5-flash-lite');
      expect(chainWithOnlyAlias.last, 'gemini-flash-latest');

      final chain = sanitizeGeminiModelChain(
        primaryModel: 'invalid-model-id',
        fallbackModels: const ['gemini-2.5-flash', 'invalid-2', 'gemini-3.5-flash'],
      );
      expect(chain.first, 'gemini-3.5-flash');
      expect(chain.contains('gemini-2.5-flash'), isTrue);
      expect(chain.contains('invalid-model-id'), isFalse);
      expect(chain.contains('invalid-2'), isFalse);
    });

    test('2. AiRuntimeConfig clamp temperature, maxChatHistoryMessages, chặn API Key/Secret và báo lỗi raw input sai', () {
      final clamped = AiRuntimeConfig.fromMap(const {
        'version': 3,
        'primaryModel': 'unknown-model',
        'temperature': 5.0,
        'maxChatHistoryMessages': 999,
      });

      expect(clamped.version, 3);
      expect(clamped.primaryModel, 'gemini-3.5-flash');
      expect(clamped.temperature, AiRuntimeConfig.kMaxTemperature);
      expect(clamped.maxChatHistoryMessages, AiRuntimeConfig.kMaxChatHistory);

      final errors = AiRuntimeConfig.validateRawInput(const {
        'primaryModel': 'arbitrary-model',
        'fallbackModels': ['gemini-flash-latest'], // Chỉ có alias động
        'temperature': 0.95,
        'maxChatHistoryMessages': 2,
        'apiKey': 'AIzaSySecretKeyShouldBeRejected',
        'prompts': {'chatSystemInstruction': ''},
      });
      expect(errors.length, greaterThanOrEqualTo(5));
      expect(
        errors.any((e) => e.contains('API Key') || e.contains('bí mật')),
        isTrue,
      );
      expect(
        errors.any((e) => e.contains('alias động')),
        isTrue,
      );
    });
  });

  group('Giai đoạn 1.3: FinancialHeuristicsConfig & Tính nhất quán ngưỡng định lượng', () {
    test('5. Clamp an toàn và đảm bảo tính nhất quán giữa các cặp ngưỡng cảnh báo/nghiêm trọng', () {
      final config = FinancialHeuristicsConfig.fromMap(const {
        'version': 2,
        'minRecommendedSavingRate': 0.18,
        'defaultSavingRateNoGoal': 0.30, // Lớn hơn minRecommendedSavingRate -> phải bị hạ xuống <= 0.18
        'categoryForecastWarningRatio': 1.50,
        'categoryForecastCriticalRatio': 1.45, // Nhỏ hơn warning -> phải tự nâng lên >= 1.65
        'txAnomalyWarningMultiplier': 3.0,
        'txAnomalyCriticalMultiplier': 3.2, // Chênh < 1.0x -> phải tự nâng lên >= 4.0
        'planBudgetAdherenceWeight': 0.65,
      });

      expect(config.minRecommendedSavingRate, 0.18);
      expect(config.defaultSavingRateNoGoal, 0.18);
      expect(config.categoryForecastCriticalRatio, closeTo(1.65, 0.001));
      expect(config.txAnomalyCriticalMultiplier, closeTo(4.0, 0.001));
      expect(
        config.planBudgetAdherenceWeight + config.planSavingAdherenceWeight,
        closeTo(1.0, 0.0001),
      );
    });
  });

  group('Giai đoạn 1.4: TransactionIntelligenceConfig & Phát hiện xung đột từ khóa', () {
    test('6. Ngăn gán vào nhóm không chuẩn, phát hiện trùng lặp không dấu và xung đột chéo giữa các nhóm', () {
      const builtInExpense = <String, List<String>>{
        'di chuyen': ['grab', 'xanh sm', 'xang'],
        'an uong': ['highlands', 'starbucks', 'ca phe'],
      };
      const addedExpense = <String, List<String>>{
        'an uong': ['katinat'],
      };

      // 6a. Trùng từ khóa đã có (không phân biệt hoa thường & dấu tiếng Việt)
      final dupCheck = TransactionIntelligenceConfig.validateCandidateKeyword(
        rawKeyword: 'Cà Phê',
        targetGroupKey: 'an uong',
        isIncomeGroup: false,
        builtInKeywordsByGroup: builtInExpense,
        addedKeywordsByGroup: addedExpense,
      );
      expect(dupCheck.isValid, isFalse);
      expect(dupCheck.errorMessage, contains('đã tồn tại'));

      // 6b. Xung đột chéo: thêm "grab" vào nhóm "an uong" khi "grab" đang thuộc "di chuyen"
      final crossConflict =
          TransactionIntelligenceConfig.validateCandidateKeyword(
        rawKeyword: 'Grab',
        targetGroupKey: 'an uong',
        isIncomeGroup: false,
        builtInKeywordsByGroup: builtInExpense,
        addedKeywordsByGroup: addedExpense,
      );
      expect(crossConflict.isValid, isFalse);
      expect(crossConflict.conflictingGroupKey, 'di chuyen');
      expect(crossConflict.errorMessage, contains('Xung đột từ khóa'));

      // 6c. Không cho phép truyền categoryId cá nhân làm groupKey
      final invalidGroup =
          TransactionIntelligenceConfig.validateCandidateKeyword(
        rawKeyword: 'phe la',
        targetGroupKey: 'user_personal_cat_123',
        isIncomeGroup: false,
        builtInKeywordsByGroup: builtInExpense,
        addedKeywordsByGroup: addedExpense,
      );
      expect(invalidGroup.isValid, isFalse);

      // 6d. Từ khóa mới hợp lệ ("Phê La" -> "phe la")
      final validNew = TransactionIntelligenceConfig.validateCandidateKeyword(
        rawKeyword: 'Phê La',
        targetGroupKey: 'an uong',
        isIncomeGroup: false,
        builtInKeywordsByGroup: builtInExpense,
        addedKeywordsByGroup: addedExpense,
      );
      expect(validNew.isValid, isTrue);
      expect(validNew.normalizedKeyword, 'phe la');
    });
  });

  group('Giai đoạn 1.5: FinancialKnowledgeArticle (Giới hạn tiêm Tri thức chuẩn cố định)', () {
    test('8. Giới hạn tối đa 3 đoạn tri thức (<= 300 ký tự/đoạn) được tiêm vào Prompt theo đúng triggerCondition', () {
      final customArticles = List.generate(
        5,
        (i) => FinancialKnowledgeArticle(
          articleId: 'kb_$i',
          title: 'Chiến lược $i',
          topic: 'saving_strategy',
          triggerCondition: KnowledgeTriggerCondition.lowSavingRate,
          priority: i + 1,
          summaryForUser: 'Tóm tắt $i',
          aiGroundingSnippet: 'A' * 400, // Vượt 300 ký tự
        ),
      );

      // Khi tỷ lệ tiết kiệm thấp -> Chọn tối đa 3 bài có priority cao nhất (5, 4, 3)
      final snippets = FinancialKnowledgeArticle.selectSnippetsForPrompt(
        isLowSavingRate: true,
        overrideArticles: customArticles,
      );

      expect(
        snippets.length,
        FinancialKnowledgeArticle.kMaxInjectedSnippetsPerPrompt,
      );
      expect(snippets.first, contains('Chiến lược 4')); // priority = 5
      // Mỗi đoạn đã bị cắt về <= 300 ký tự nội dung
      for (final s in snippets) {
        expect(s.length, lessThanOrEqualTo(330));
      }
    });
  });

  group('Giai đoạn 2.1: Tích hợp FinancialAnalyticsService với cấu hình động', () {
    final testCategories = <Category>[
      Category(
        categoryId: 'cat_food',
        userId: 'u1',
        name: 'Ăn uống',
        type: 'expense',
        icon: 'restaurant',
        color: 0xFFFF7043,
      ),
      Category(
        categoryId: 'cat_shopping',
        userId: 'u1',
        name: 'Mua sắm',
        type: 'expense',
        icon: 'shopping_bag',
        color: 0xFFAB47BC,
      ),
      Category(
        categoryId: 'cat_salary',
        userId: 'u1',
        name: 'Lương',
        type: 'income',
        icon: 'payments',
        color: 0xFF4CAF50,
      ),
    ];

    final lastMonthTx = <AppTransaction>[
      AppTransaction(
        transactionId: 'tx_last_1',
        userId: 'u1',
        walletId: 'w1',
        categoryId: 'cat_salary',
        amount: 20000000,
        type: 'income',
        date: DateTime(2026, 10, 5),
        note: 'Lương tháng 10',
      ),
      AppTransaction(
        transactionId: 'tx_last_2',
        userId: 'u1',
        walletId: 'w1',
        categoryId: 'cat_shopping',
        amount: 2000000,
        type: 'expense',
        date: DateTime(2026, 10, 12),
        note: 'Mua quần áo',
      ),
    ];

    final currentMonthTx = <AppTransaction>[
      AppTransaction(
        transactionId: 'tx_cur_1',
        userId: 'u1',
        walletId: 'w1',
        categoryId: 'cat_salary',
        amount: 20000000,
        type: 'income',
        date: DateTime(2026, 11, 5),
        note: 'Lương tháng 11',
      ),
      AppTransaction(
        transactionId: 'tx_cur_2',
        userId: 'u1',
        walletId: 'w1',
        categoryId: 'cat_shopping',
        amount: 2700000, // Tăng +35% (+700.000đ) so với 2.000.000đ tháng trước
        type: 'expense',
        date: DateTime(2026, 11, 10),
        note: 'Mua đồ gia dụng',
      ),
      AppTransaction(
        transactionId: 'tx_cur_3',
        userId: 'u1',
        walletId: 'w1',
        categoryId: 'cat_food',
        amount: 14300000, // Tổng chi = 17.000.000đ -> Tiết kiệm 3.000.000đ (15% thu nhập)
        type: 'expense',
        date: DateTime(2026, 11, 12),
        note: 'Chi phí sinh hoạt & ăn uống',
      ),
    ];

    test('10. Phát hiện vấn đề, lập kế hoạch tháng và chấm điểm tuân thủ phản ánh chính xác ngưỡng FinancialHeuristicsConfig', () {
      // 10a. Với ngưỡng mặc định (spike >= 30%, minSaving >= 20%): phát hiện cả spike lẫn lowSaving
      final defaultAnalytics = FinancialAnalyticsService(
        heuristicsOverride: FinancialHeuristicsConfig.defaults(),
      );
      final defaultIssues = defaultAnalytics.detectIssues(
        currentMonthTx: currentMonthTx,
        lastMonthTx: lastMonthTx,
        categories: testCategories,
        monthlyIncome: 20000000,
      );
      expect(
        defaultIssues.any((i) => i.category == IssueCategory.spike),
        isTrue,
      );
      expect(
        defaultIssues.any((i) => i.category == IssueCategory.lowSaving),
        isTrue,
      );

      // 10b. Khi Admin nâng ngưỡng spike lên 45% và hạ minRecommendedSavingRate xuống 12%: không còn cảnh báo
      final relaxedConfig = FinancialHeuristicsConfig.fromMap(const {
        'version': 2,
        'categorySpikeRatio': 0.45,
        'minRecommendedSavingRate': 0.12,
        'defaultSavingRateNoGoal': 0.10,
        'flexibleSpendFloorRatio': 0.75,
      });
      final customAnalytics = FinancialAnalyticsService(
        heuristicsOverride: relaxedConfig,
      );
      final customIssues = customAnalytics.detectIssues(
        currentMonthTx: currentMonthTx,
        lastMonthTx: lastMonthTx,
        categories: testCategories,
        monthlyIncome: 20000000,
      );
      expect(
        customIssues.any((i) => i.category == IssueCategory.spike),
        isFalse,
      );
      expect(
        customIssues.any((i) => i.category == IssueCategory.lowSaving),
        isFalse,
      );

      // 10c. Lập kế hoạch tháng khi chưa có mục tiêu tiết kiệm dùng đúng defaultSavingRateNoGoal
      final defaultPlan = defaultAnalytics.buildSequentialMonthlyPlan(
        userId: 'u1',
        targetMonth: '12/2026',
        sourceMonth: '11/2026',
        sourceMonthTx: lastMonthTx,
        historicalMonthsTx: [currentMonthTx],
        categories: testCategories,
        existingTargetBudgets: const [],
        savingGoals: const [],
        wallets: const [],
        declaredExpectedIncome: 20000000,
      );
      final customPlan = customAnalytics.buildSequentialMonthlyPlan(
        userId: 'u1',
        targetMonth: '12/2026',
        sourceMonth: '11/2026',
        sourceMonthTx: lastMonthTx,
        historicalMonthsTx: [currentMonthTx],
        categories: testCategories,
        existingTargetBudgets: const [],
        savingGoals: const [],
        wallets: const [],
        declaredExpectedIncome: 20000000,
      );
      // Mặc định: 15% của 20 triệu = 3.000.000đ; Custom: 10% của 20 triệu = 2.000.000đ
      expect(defaultPlan.targetSavingAmount, closeTo(3000000, 1));
      expect(customPlan.targetSavingAmount, closeTo(2000000, 1));
    });
  });

  group('Giai đoạn 2.2: Tích hợp FinancialForecastService & Tách biệt ngưỡng Danh mục vs Giao dịch', () {
    final catFood = Category(
      categoryId: 'cat_food',
      userId: 'u1',
      name: 'Ăn uống',
      type: 'expense',
      icon: 'restaurant',
      color: 0xFFFF7043,
    );

    test('11. Dự báo ngân sách, bất thường cấp danh mục và điểm sức khỏe hoạt động độc lập theo FinancialHeuristicsConfig', () {
      final budgets = [
        Budget(
          budgetId: 'b_food',
          userId: 'u1',
          categoryId: 'cat_food',
          limit: 5000000,
          month: '11/2026',
        ),
      ];
      // Đã chi 4.200.000đ / 5.000.000đ (84% hạn mức) ở ngày 28/30 (tốc độ 150k/ngày -> hết tháng 4.5M < 5M)
      final currentTx = [
        AppTransaction(
          transactionId: 'tx_1',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 4200000,
          type: 'expense',
          date: DateTime(2026, 11, 10),
        ),
      ];

      final defaultForecastSvc = FinancialForecastService(
        heuristicsOverride: FinancialHeuristicsConfig.defaults(),
      );
      final strictNearLimitSvc = FinancialForecastService(
        heuristicsOverride: FinancialHeuristicsConfig.fromMap(const {
          'budgetNearLimitRatio': 0.90, // Chỉ báo warning khi >= 90%
          'healthNegativeBalancePenalty': 10,
          'healthBudgetExceededPenalty': 5,
        }),
      );

      final fDefault = defaultForecastSvc.calculateBudgetForecasts(
        currentMonthBudgets: budgets,
        currentMonthTx: currentTx,
        categories: [catFood],
        refDate: DateTime(2026, 11, 28),
      );
      final fCustom = strictNearLimitSvc.calculateBudgetForecasts(
        currentMonthBudgets: budgets,
        currentMonthTx: currentTx,
        categories: [catFood],
        refDate: DateTime(2026, 11, 28),
      );

      // Ở mức 84%: mặc định (>=80%) là warning, còn ngưỡng 90% vẫn là safe
      expect(fDefault.first.status, BudgetForecastStatus.warning);
      expect(fCustom.first.status, BudgetForecastStatus.safe);

      // Kiểm tra điểm sức khỏe với bộ mức phạt tùy chỉnh
      const negMonthEnd = MonthEndForecast(
        currentTotalBalance: 2000000,
        monthToDateExpense: 10000000,
        monthToDateIncome: 8000000,
        averageDailyExpense: 500000,
        elapsedDays: 20,
        remainingDays: 10,
        totalDaysInMonth: 30,
        projectedRemainingExpense: 5000000,
        projectedEndBalance: -2000000,
        hasEnoughData: true,
      );
      final defaultDeductions = <HealthScoreDeduction>[];
      final customDeductions = <HealthScoreDeduction>[];
      final defaultHealth = defaultForecastSvc.calculateOverallHealthScore(
        monthEndForecast: negMonthEnd,
        budgetForecasts: const [],
        anomalies: const [],
        issues: const [],
        outDeductions: defaultDeductions,
      );
      final customHealth = strictNearLimitSvc.calculateOverallHealthScore(
        monthEndForecast: negMonthEnd,
        budgetForecasts: const [],
        anomalies: const [],
        issues: const [],
        outDeductions: customDeductions,
      );
      // Mặc định trừ 25 điểm (còn 75), cấu hình mới trừ 10 điểm (còn 90)
      expect(defaultHealth, 75);
      expect(customHealth, 90);
    });
  });

  group('Giai đoạn 2.3: Tích hợp TransactionIntelligenceService & Bảo vệ từ khóa hệ thống', () {
    final userCategories = <Category>[
      Category(
        categoryId: 'cat_food_user',
        userId: 'u1',
        name: 'Ăn uống',
        type: 'expense',
        icon: 'restaurant',
        color: 0xFFFF7043,
      ),
      Category(
        categoryId: 'cat_move_user',
        userId: 'u1',
        name: 'Di chuyển',
        type: 'expense',
        icon: 'directions_car',
        color: 0xFF42A5F5,
      ),
      Category(
        categoryId: 'cat_shop_user',
        userId: 'u1',
        name: 'Mua sắm',
        type: 'expense',
        icon: 'shopping_bag',
        color: 0xFFAB47BC,
      ),
    ];

    test('12. Nhận diện thương hiệu mới từ Admin Rules nhưng chống ghi đè từ khóa hệ thống (Built-in Precedence)', () {
      // Trước khi có từ khóa Admin: "Phê La" chưa được nhận diện
      final defaultIntel = TransactionIntelligenceService(
        rulesOverride: TransactionIntelligenceConfig.defaults(),
        heuristicsOverride: FinancialHeuristicsConfig.defaults(),
      );
      final beforeSuggestion = defaultIntel.suggestCategory(
        note: 'Ghé Phê La Hồ Tùng Mậu',
        transactionType: 'expense',
        categories: userCategories,
      );
      expect(beforeSuggestion.categoryId, isEmpty);

      // Khi Admin bổ sung từ khóa "phe la" vào nhóm "an uong", kèm một rule cố tình ghi đè "grab" sang "an uong"
      // và một từ khóa mơ hồ "voucher" xuất hiện ở cả 2 nhóm "an uong" và "mua sam"
      const customRules = TransactionIntelligenceConfig(
        version: 2,
        addedExpenseKeywords: {
          'an uong': ['phe la', 'grab', 'voucher'],
          'mua sam': ['voucher'],
        },
        customPaymentProviders: [
          CustomPaymentProviderRule(
            key: 'phe_la_pay',
            displayLabel: 'Ví Phê La',
            walletType: 'eWallet',
            receiptKeywords: ['phe la pay'],
            walletNameAliases: ['phe la', 'momo'],
          ),
        ],
      );

      final customIntel = TransactionIntelligenceService(
        rulesOverride: customRules,
        heuristicsOverride: FinancialHeuristicsConfig.fromMap(const {
          'txAnomalyWarningMultiplier': 3.5,
          'txAnomalyCriticalMultiplier': 5.0,
        }),
      );

      // 12a. Thương hiệu mới "Phê La" được gợi ý chính xác vào danh mục Ăn uống của User
      final pheLaSuggestion = customIntel.suggestCategory(
        note: 'Ghé Phê La Hồ Tùng Mậu',
        transactionType: 'expense',
        categories: userCategories,
      );
      expect(pheLaSuggestion.source, 'keyword');
      expect(pheLaSuggestion.categoryId, 'cat_food_user');

      // 12b. Từ khóa hệ thống "Grab" VẪN thuộc Di chuyển, không bị rule Admin ghi đè sang Ăn uống
      final grabSuggestion = customIntel.suggestCategory(
        note: 'Đặt xe Grab đi làm',
        transactionType: 'expense',
        categories: userCategories,
      );
      expect(grabSuggestion.source, 'keyword');
      expect(grabSuggestion.categoryId, 'cat_move_user');

      // 12c. Từ khóa mơ hồ "voucher" bị trùng giữa 2 nhóm Admin sẽ tự động bị loại bỏ để tránh gợi ý sai
      final ambiguousSuggestion = customIntel.suggestCategory(
        note: 'voucher giảm giá',
        transactionType: 'expense',
        categories: userCategories,
      );
      expect(ambiguousSuggestion.categoryId, isEmpty);

      // 12d. Kiểm tra ngưỡng bất thường giao dịch đơn lẻ hoạt động theo heuristicsOverride (warning = 3.5x vs mặc định 2.0x)
      final historyTx = List.generate(
        6,
        (i) => AppTransaction(
          transactionId: 'h_$i',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food_user',
          amount: 100000, // Trung vị = 100.000đ
          type: 'expense',
          date: DateTime(2026, 11, 1 + i),
        ),
      );
      // Giao dịch 300.000đ (gấp 3.0 lần, chênh +200.000đ): cảnh báo ở cấu hình mặc định (2.0x), nhưng an toàn ở cấu hình mới (3.5x)
      final anomalyDefault = defaultIntel.detectAnomaly(
        amount: 300000,
        categoryId: 'cat_food_user',
        categoryName: 'Ăn uống',
        transactionType: 'expense',
        userHistory: historyTx,
        currentDate: DateTime(2026, 11, 14),
      );
      final anomalyCustom = customIntel.detectAnomaly(
        amount: 300000,
        categoryId: 'cat_food_user',
        categoryName: 'Ăn uống',
        transactionType: 'expense',
        userHistory: historyTx,
        currentDate: DateTime(2026, 11, 14),
      );
      expect(anomalyDefault.isAnomalous, isTrue);
      expect(anomalyDefault.severity, 'warning');
      expect(anomalyCustom.isAnomalous, isFalse);
    });
  });

  group('Giai đoạn 2.4: FinancialChatContextService.buildContextFromData (Thuần, dùng chung Sandbox & Lọc PII)', () {
    test('13. buildContextFromData chạy độc lập không cần Firebase trên toàn bộ 4 hồ sơ giả lập và lọc sạch PII', () {
      final contextService = FinancialChatContextService(
        heuristicsOverride: FinancialHeuristicsConfig.defaults(),
      );

      final personas = SyntheticPersona.builtInPersonas(
        referenceDate: DateTime(2026, 11, 14),
      );
      expect(personas.length, 3);

      for (final p in personas) {
        final ctx = contextService.buildContextFromData(
          currentMonthTx: p.currentMonthTx,
          lastMonthTx:
              p.historicalMonthsTx.isNotEmpty ? p.historicalMonthsTx[0] : const [],
          twoMonthsAgoTx:
              p.historicalMonthsTx.length > 1 ? p.historicalMonthsTx[1] : const [],
          wallets: p.wallets,
          budgets: p.currentBudgets,
          categories: p.categories,
          savingGoals: p.savingGoals,
          declaredMonthlyIncome: p.declaredMonthlyIncome,
          customSuggestedPrompts: const ['Câu hỏi gợi ý từ Admin 1'],
          referenceDate: DateTime(2026, 11, 14),
        );
        expect(ctx.rawPromptContext, contains('DỮ LIỆU TÀI CHÍNH THỰC TẾ'));
        if (!ctx.isEmptyData) {
          expect(
            ctx.dynamicPrompts.any((c) => c.label == 'Câu hỏi gợi ý từ Admin 1'),
            isTrue,
          );
        }
      }

      // Kiểm tra lọc PII khi truyền AppUser chứa email, UID và SĐT trong tên
      final piiUser = AppUser(
        uid: 'SENSITIVE_UID_999888',
        name: 'Nguyễn Văn A 0912345678',
        email: 'private_email_secret@gmail.com',
        monthlyIncome: 25000000,
        createdAt: DateTime(2026, 1, 1),
      );
      final p0 = personas[1];
      final piiContext = contextService.buildContextFromData(
        currentMonthTx: p0.currentMonthTx,
        lastMonthTx:
            p0.historicalMonthsTx.isNotEmpty ? p0.historicalMonthsTx[0] : const [],
        twoMonthsAgoTx:
            p0.historicalMonthsTx.length > 1 ? p0.historicalMonthsTx[1] : const [],
        wallets: p0.wallets,
        budgets: p0.currentBudgets,
        categories: p0.categories,
        savingGoals: p0.savingGoals,
        userProfile: piiUser,
        referenceDate: DateTime(2026, 11, 14),
      );

      expect(piiContext.rawPromptContext, isNot(contains('SENSITIVE_UID_999888')));
      expect(
        piiContext.rawPromptContext,
        isNot(contains('private_email_secret@gmail.com')),
      );
      expect(piiContext.rawPromptContext, isNot(contains('0912345678')));
    });
  });

  group('Giai đoạn 2.5: AiService & Kiểm chứng cô lập Draft vs Published toàn hệ thống', () {
    test('14. AiService thực thi đúng Model Fallback Chain, ghi nhận lastModelUsed, giới hạn lịch sử chat và giữ khóa nguyên tắc cốt lõi', () async {
      final customRuntime = AiRuntimeConfig.defaults().copyWith(
        primaryModel: 'gemini-3.8-flash',
        fallbackModels: const ['gemini-3.5-flash', 'gemini-3.5-flash-lite'],
        temperature: 0.25,
        maxChatHistoryMessages: 4,
        chatSystemInstruction: 'Ưu tiên gợi ý chia ngân sách theo tuần.',
      );

      final attemptedModels = <String>[];
      final aiService = AiService(
        runtimeConfigOverride: customRuntime,
        allowMissingApiKeyForTest: true,
        contentGeneratorOverride: (modelName, content, temp) async {
          attemptedModels.add(modelName);
          if (modelName == 'gemini-3.8-flash') {
            throw Exception('Model 404 or overloaded');
          }
          return 'Phản hồi từ $modelName ở temp=$temp';
        },
      );

      // 14a. Tự động fallback từ gemini-3.8-flash sang gemini-3.5-flash và lưu đúng lastModelUsed
      final reply = await aiService.chatWithFinancialData(
        userQuestion: 'Tình hình chi tiêu tháng này thế nào?',
        contextData: 'Tổng thu: 20.000.000 đ, Tổng chi: 15.000.000 đ (THÂM HỤT)',
      );
      expect(reply, contains('gemini-3.5-flash'));
      expect(aiService.lastModelUsed, 'gemini-3.5-flash');
      expect(attemptedModels, equals(['gemini-3.8-flash', 'gemini-3.5-flash']));

      // 14b. Kiểm tra giới hạn sliding window theo maxChatHistoryMessages = 4 (1 system + tối đa 4 message)
      for (var i = 0; i < 6; i++) {
        await aiService.chatWithFinancialData(
          userQuestion: 'Câu hỏi $i',
          contextData: 'Dữ liệu $i',
        );
      }
      expect(aiService.chatHistoryLength, lessThanOrEqualTo(6));

      // 14c. Kiểm tra System Prompt luôn khóa cứng DATA GROUNDING, STRICT DOMAIN SCOPE và tiêm <= 3 bài tri thức
      final builtPrompt = aiService.buildSystemCfpPromptForContext(
        'Dòng tiền ròng: -2.000.000 đ (THÂM HỤT)\n⚠️ VƯỢT NGÂN SÁCH',
      );
      expect(builtPrompt, contains('DATA GROUNDING'));
      expect(builtPrompt, contains('STRICT DOMAIN SCOPE'));
      expect(builtPrompt, contains('CƠ SỞ TRI THỨC TÀI CHÍNH CHUẨN HÓA'));
      expect(builtPrompt, contains('Ưu tiên gợi ý chia ngân sách theo tuần.'));

      // 14d. Khi gặp lỗi mất mạng (SocketException), dừng ngay không thử model dự phòng tiếp theo
      final offlineCalls = <String>[];
      final offlineAi = AiService(
        runtimeConfigOverride: customRuntime,
        allowMissingApiKeyForTest: true,
        contentGeneratorOverride: (modelName, content, temp) async {
          offlineCalls.add(modelName);
          throw const SocketException('Failed host lookup');
        },
      );
      await expectLater(
        () => offlineAi.chatWithFinancialData(
          userQuestion: 'Test offline',
          contextData: 'Dữ liệu',
        ),
        throwsA(predicate((Object? e) => e != null && AiService.isNoNetworkException(e))),
      );
      expect(offlineCalls.length, 1);
    });

    test('15. Toàn bộ Service Mobile mặc định chạy độc lập bằng hằng số chuẩn cố định (không phụ thuộc Admin Config/Firestore)', () {
      final analyticsSvc = FinancialAnalyticsService();
      final forecastSvc = FinancialForecastService();
      final chatContextSvc = FinancialChatContextService();
      final txIntelSvc = TransactionIntelligenceService();
      final aiSvc = AiService(allowMissingApiKeyForTest: true);

      final defaultHeuristics = FinancialHeuristicsConfig.defaults();
      final defaultRuntime = AiRuntimeConfig.defaults();

      expect(
        analyticsSvc.effectiveHeuristics.categorySpikeRatio,
        defaultHeuristics.categorySpikeRatio,
      );
      expect(
        forecastSvc.effectiveHeuristics.budgetNearLimitRatio,
        defaultHeuristics.budgetNearLimitRatio,
      );
      expect(
        chatContextSvc.effectiveHeuristics.minRecommendedSavingRate,
        defaultHeuristics.minRecommendedSavingRate,
      );
      expect(
        txIntelSvc.effectiveHeuristics.txAnomalyWarningMultiplier,
        defaultHeuristics.txAnomalyWarningMultiplier,
      );
      expect(txIntelSvc.effectiveRules.addedExpenseKeywords, isEmpty);
      expect(aiSvc.effectiveRuntimeConfig.primaryModel, defaultRuntime.primaryModel);
      expect(aiSvc.effectiveRuntimeConfig.temperature, defaultRuntime.temperature);
      expect(aiSvc.effectiveRuntimeConfig.isEnabled, isTrue);
    });
  });
}
