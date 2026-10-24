import 'financial_issue.dart';

/// Trạng thái dự báo ngân sách
enum BudgetForecastStatus {
  safe, // An toàn
  warning, // Cảnh báo (dùng >=80% hoặc sắp chạm hạn mức trong 7 ngày)
  atRisk, // Có nguy cơ vượt trong tháng hiện tại
  exceeded, // Đã vượt hạn mức
}

/// 1. Dự báo số dư cuối tháng
class MonthEndForecast {
  final double currentTotalBalance;
  final double monthToDateExpense;
  final double monthToDateIncome;
  final double averageDailyExpense;
  final int elapsedDays;
  final int remainingDays;
  final int totalDaysInMonth;
  final double projectedRemainingExpense;
  final double projectedEndBalance;
  final bool hasEnoughData;
  final double plannedRemainingIncome;
  final double plannedRemainingExpense;
  final double averageDailyDiscretionaryExpense;
  final double projectedRemainingDiscretionaryExpense;

  const MonthEndForecast({
    required this.currentTotalBalance,
    required this.monthToDateExpense,
    required this.monthToDateIncome,
    required this.averageDailyExpense,
    required this.elapsedDays,
    required this.remainingDays,
    required this.totalDaysInMonth,
    required this.projectedRemainingExpense,
    required this.projectedEndBalance,
    required this.hasEnoughData,
    this.plannedRemainingIncome = 0,
    this.plannedRemainingExpense = 0,
    double? averageDailyDiscretionaryExpense,
    double? projectedRemainingDiscretionaryExpense,
  })  : averageDailyDiscretionaryExpense =
            averageDailyDiscretionaryExpense ?? averageDailyExpense,
        projectedRemainingDiscretionaryExpense =
            projectedRemainingDiscretionaryExpense ?? projectedRemainingExpense;
}

/// 2. Dự báo nguy cơ vượt ngân sách cho từng danh mục
class BudgetForecast {
  final String budgetId;
  final String categoryId;
  final String categoryName;
  final double limit;
  final double spent;
  final double dailyPace;
  final double percentUsed;
  final DateTime? estimatedExceededDate;
  final int? daysToLimit;
  final BudgetForecastStatus status;

  const BudgetForecast({
    required this.budgetId,
    required this.categoryId,
    required this.categoryName,
    required this.limit,
    required this.spent,
    required this.dailyPace,
    required this.percentUsed,
    this.estimatedExceededDate,
    this.daysToLimit,
    required this.status,
  });
}

/// 3. Chi tiêu bất thường so với lịch sử 3 tháng trước
class SpendingAnomaly {
  final String categoryId;
  final String categoryName;
  final double currentSpend;
  final double expectedSpendToDate;
  final double averageMonthlySpend;
  final double excessAmount;
  final double excessRatio; // ví dụ 1.35 = vượt 35%
  final int monthsOfHistory;
  final IssueSeverity severity;

  const SpendingAnomaly({
    required this.categoryId,
    required this.categoryName,
    required this.currentSpend,
    required this.expectedSpendToDate,
    required this.averageMonthlySpend,
    required this.excessAmount,
    required this.excessRatio,
    required this.monthsOfHistory,
    required this.severity,
  });
}

/// 4. Chi tiết khoản trừ điểm sức khỏe tài chính
class HealthScoreDeduction {
  final String reason;
  final int points;
  final String? categoryId;

  const HealthScoreDeduction({
    required this.reason,
    required this.points,
    this.categoryId,
  });
}

/// 5. Phân bổ nguồn thu nhập
class IncomeSourceBreakdown {
  final String categoryId;
  final String categoryName;
  final double amount;
  final double percentage; // 0.0 - 1.0

  const IncomeSourceBreakdown({
    required this.categoryId,
    required this.categoryName,
    required this.amount,
    required this.percentage,
  });
}

/// 6. Phân tích chi tiết thu nhập
class IncomeAnalytics {
  final double currentMonthIncome;
  final double lastMonthIncome;
  final double growthRate; // (current - last) / last
  final List<IncomeSourceBreakdown> sources;
  final String stability; // 'Ổn định' | 'Biến động nhẹ' | 'Biến động mạnh'
  final String commentary;

  const IncomeAnalytics({
    required this.currentMonthIncome,
    required this.lastMonthIncome,
    required this.growthRate,
    required this.sources,
    required this.stability,
    required this.commentary,
  });
}

/// 7. Phân tích dòng tiền & khả năng giữ lại (Net Cash Flow & Savings Rate)
class CashFlowAnalytics {
  final double totalIncome;
  final double totalExpense;
  final double netCashFlow; // totalIncome - totalExpense
  final double savingsRate; // netCashFlow / totalIncome * 100
  final bool isPositive;
  final double lastMonthNetCashFlow;
  final double netCashFlowChange;
  final String sustainabilityStatus; // 'Bền vững' | 'Khá tốt' | 'Cần chú ý' | 'Thâm hụt rủi ro'
  final String summaryComment;

  const CashFlowAnalytics({
    required this.totalIncome,
    required this.totalExpense,
    required this.netCashFlow,
    required this.savingsRate,
    required this.isPositive,
    required this.lastMonthNetCashFlow,
    required this.netCashFlowChange,
    required this.sustainabilityStatus,
    required this.summaryComment,
  });
}

/// 8. Đánh giá tính khả thi từng mục tiêu tiết kiệm
class GoalFeasibilityItem {
  final String goalId;
  final String goalName;
  final double targetAmount;
  final double savedAmount;
  final double monthlyRequired;
  final int monthsRemaining;
  final double percentComplete;
  final bool isAtRisk;
  final String statusText;
  final String suggestion;

  const GoalFeasibilityItem({
    required this.goalId,
    required this.goalName,
    required this.targetAmount,
    required this.savedAmount,
    required this.monthlyRequired,
    required this.monthsRemaining,
    required this.percentComplete,
    required this.isAtRisk,
    required this.statusText,
    required this.suggestion,
  });
}

/// 9. Tổng hợp đánh giá toàn bộ mục tiêu tiết kiệm
class SavingsGoalAssessment {
  final double totalMonthlyRequired;
  final double availableCashFlow;
  final double gapAmount; // số tiền còn thiếu mỗi tháng
  final bool canFulfillAllGoals;
  final List<GoalFeasibilityItem> goals;
  final String overallAdvice;

  const SavingsGoalAssessment({
    required this.totalMonthlyRequired,
    required this.availableCashFlow,
    required this.gapAmount,
    required this.canFulfillAllGoals,
    required this.goals,
    required this.overallAdvice,
  });
}

/// 10. Khoản đề xuất trong kế hoạch hành động
class ActionPlanItem {
  final String categoryName;
  final String actionTitle;
  final double currentSpend;
  final double targetReduction;
  final double suggestedBudget;
  final String rationales;

  const ActionPlanItem({
    required this.categoryName,
    required this.actionTitle,
    required this.currentSpend,
    required this.targetReduction,
    required this.suggestedBudget,
    required this.rationales,
  });
}

/// 11. Kế hoạch hành động cải thiện cụ thể tháng tới (Action Plan)
class FinancialActionPlan {
  final double targetMonthlySavings;
  final List<ActionPlanItem> items;
  final double totalProjectedSavings;
  final String actionSummary;

  const FinancialActionPlan({
    required this.targetMonthlySavings,
    required this.items,
    required this.totalProjectedSavings,
    required this.actionSummary,
  });
}

/// 12. Tổng hợp toàn bộ Insight & Trợ lý cố vấn tài chính
class FinancialInsightSummary {
  final MonthEndForecast monthEndForecast;
  final List<BudgetForecast> budgetForecasts;
  final List<SpendingAnomaly> anomalies;
  final List<FinancialIssue> issues;
  final int healthScore;
  final String healthRating; // Xuất sắc | Khá tốt | Cần theo dõi | Có rủi ro | Cần hành động ngay
  final List<HealthScoreDeduction> deductions;
  final List<String> strengths; // Điểm mạnh giúp cân bằng đánh giá
  final IncomeAnalytics incomeAnalytics;
  final CashFlowAnalytics cashFlowAnalytics;
  final SavingsGoalAssessment? savingsGoalAssessment;
  final FinancialActionPlan actionPlan;
  final DateTime referenceDate;

  const FinancialInsightSummary({
    required this.monthEndForecast,
    required this.budgetForecasts,
    required this.anomalies,
    required this.issues,
    required this.healthScore,
    required this.healthRating,
    required this.deductions,
    required this.referenceDate,
    required this.incomeAnalytics,
    required this.cashFlowAnalytics,
    this.savingsGoalAssessment,
    required this.actionPlan,
    this.strengths = const [],
  });
}
