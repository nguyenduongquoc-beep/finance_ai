import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/financial_issue.dart';
import 'package:finance_ai_app/models/saving_goal_model.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/services/financial_analytics_service.dart';

void main() {
  group('FinancialAnalyticsService Tests', () {
    final analyticsService = FinancialAnalyticsService();

    final testCategories = [
      Category(
        categoryId: 'cat_food',
        userId: 'user_1',
        name: 'Ăn uống',
        type: 'expense',
        icon: 'restaurant',
        color: 0xFFD32F2F,
      ),
      Category(
        categoryId: 'cat_shopping',
        userId: 'user_1',
        name: 'Mua sắm',
        type: 'expense',
        icon: 'shopping_bag',
        color: 0xFFE64A19,
      ),
    ];

    test('detectIssues: category spike threshold (>30% spike)', () {
      final lastMonthTx = [
        AppTransaction(
          transactionId: 'tx1',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 100000,
          type: 'expense',
          date: DateTime.now().subtract(const Duration(days: 35)),
        ),
      ];

      final currentMonthTx = [
        AppTransaction(
          transactionId: 'tx2',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 140000, // Spike of 40% (>30%)
          type: 'expense',
          date: DateTime.now(),
        ),
      ];

      final issues = analyticsService.detectIssues(
        currentMonthTx: currentMonthTx,
        lastMonthTx: lastMonthTx,
        categories: testCategories,
        monthlyIncome: 1000000, // Large income to avoid other warnings
      );

      final foodSpikeIssue = issues.firstWhere((i) => i.title.contains('Ăn uống tăng'));
      expect(foodSpikeIssue, isNotNull);
      expect(foodSpikeIssue.severity, equals(IssueSeverity.warning));
      expect(foodSpikeIssue.currentValue, equals(140000.0));
    });

    test('detectIssues: category share threshold (>25% of income)', () {
      final lastMonthTx = <AppTransaction>[];

      final currentMonthTx = [
        AppTransaction(
          transactionId: 'tx3',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 300000, // 30% of monthly income (1,000,000)
          type: 'expense',
          date: DateTime.now(),
        ),
      ];

      final issues = analyticsService.detectIssues(
        currentMonthTx: currentMonthTx,
        lastMonthTx: lastMonthTx,
        categories: testCategories,
        monthlyIncome: 1000000,
      );

      final foodShareIssue = issues.firstWhere((i) => i.title.contains('chiếm 30% thu nhập'));
      expect(foodShareIssue, isNotNull);
      expect(foodShareIssue.severity, equals(IssueSeverity.warning));
    });

    test('detectIssues: low saving rate (<20%)', () {
      final lastMonthTx = <AppTransaction>[];

      final currentMonthTx = [
        AppTransaction(
          transactionId: 'tx4',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 850000, // 85% of monthly income, so savings rate is 15% (<20%)
          type: 'expense',
          date: DateTime.now(),
        ),
      ];

      final issues = analyticsService.detectIssues(
        currentMonthTx: currentMonthTx,
        lastMonthTx: lastMonthTx,
        categories: testCategories,
        monthlyIncome: 1000000,
      );

      final lowSavingIssue = issues.firstWhere((i) => i.title.contains('Tỷ lệ tiết kiệm chỉ đạt 15%'));
      expect(lowSavingIssue, isNotNull);
      expect(lowSavingIssue.severity, equals(IssueSeverity.warning));
    });

    test('calculateHealthScore', () {
      final issues = [
        FinancialIssue(
          title: 'Issue 1',
          description: 'Desc 1',
          severity: IssueSeverity.warning,
          category: IssueCategory.spike,
          confidenceScore: 80.0,
        ),
        FinancialIssue(
          title: 'Issue 2',
          description: 'Desc 2',
          severity: IssueSeverity.critical,
          category: IssueCategory.spike,
          confidenceScore: 80.0,
        ),
      ];

      // Starts at 100.
      // Warning subtracts 10, Critical subtracts 20.
      // 100 - 10 - 20 = 70.
      final score = analyticsService.calculateHealthScore(issues);
      expect(score, equals(70));
    });

    test('computeIncomeAnalytics: growth rate, source breakdown and commentary', () {
      final incomeCategories = [
        Category(
          categoryId: 'cat_salary',
          userId: 'user_1',
          name: 'Lương',
          type: 'income',
          icon: 'payments',
          color: 0xFF4CAF50,
        ),
      ];

      final lastMonthTx = [
        AppTransaction(
          transactionId: 'in_1',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_salary',
          amount: 10000000,
          type: 'income',
          date: DateTime.now().subtract(const Duration(days: 35)),
        ),
      ];

      final currentMonthTx = [
        AppTransaction(
          transactionId: 'in_2',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_salary',
          amount: 12000000, // +20% growth
          type: 'income',
          date: DateTime.now(),
        ),
      ];

      final incomeResult = analyticsService.computeIncomeAnalytics(
        currentMonthTx: currentMonthTx,
        lastMonthTx: lastMonthTx,
        categories: incomeCategories,
      );

      expect(incomeResult.currentMonthIncome, equals(12000000.0));
      expect(incomeResult.lastMonthIncome, equals(10000000.0));
      expect(incomeResult.growthRate, closeTo(0.20, 0.001));
      expect(incomeResult.sources.length, equals(1));
      expect(incomeResult.sources.first.categoryName, equals('Lương'));
      expect(incomeResult.sources.first.percentage, equals(1.0));
      expect(incomeResult.commentary.contains('tăng 20%'), isTrue);
    });

    test('computeCashFlowAnalytics: net cash flow, savings rate, and status', () {
      final cashFlow = analyticsService.computeCashFlowAnalytics(
        currentMonthIncome: 15000000,
        currentMonthExpense: 10800000,
        lastMonthIncome: 15000000,
        lastMonthExpense: 12000000,
      );

      expect(cashFlow.netCashFlow, equals(4200000.0));
      expect(cashFlow.savingsRate, closeTo(28.0, 0.1));
      expect(cashFlow.isPositive, isTrue);
      expect(cashFlow.sustainabilityStatus, equals('Bền vững'));
      expect(cashFlow.summaryComment.contains('4.200.000'), isTrue);
    });

    test('evaluateSavingGoals: detects shortfall and calculates gap', () {
      final goals = [
        SavingGoal(
          goalId: 'g1',
          userId: 'user_1',
          name: 'Mua xe máy',
          targetAmount: 30000000,
          savedAmount: 10000000,
          months: 10, // Cần 2,000,000 / tháng
          createdAt: DateTime.now(),
        ),
      ];

      // Net cash flow chỉ có 1,200,000 -> thiếu 800,000
      final assessment = analyticsService.evaluateSavingGoals(
        goals: goals,
        netCashFlow: 1200000,
      );

      expect(assessment.totalMonthlyRequired, equals(2000000.0));
      expect(assessment.availableCashFlow, equals(1200000.0));
      expect(assessment.gapAmount, equals(800000.0));
      expect(assessment.canFulfillAllGoals, isFalse);
      expect(assessment.goals.first.isAtRisk, isTrue);
      expect(assessment.goals.first.suggestion.contains('Thiếu'), isTrue);
    });
  });
}
