import 'dart:math' as math;
import '../models/ai_runtime_config_model.dart';
import '../models/budget_model.dart';
import '../models/transaction_model.dart';
import '../models/category_model.dart';
import '../models/financial_issue.dart';
import '../models/financial_forecast_result.dart';
import '../models/monthly_financial_plan.dart';
import '../models/saving_goal_model.dart';
import '../models/wallet_model.dart';
import '../utils/formatters.dart';
import 'ai_config_sync_service.dart';

/// ============================================================
/// FINANCIAL ANALYTICS SERVICE
/// Tính toán chỉ số tài chính & phát hiện vấn đề bằng NGƯỠNG CỤ THỂ.
/// Toàn bộ hàm trong file này là DART THUẦN — không gọi Gemini/AI.
/// Đây là tầng phân tích độc lập, phục vụ đúng yêu cầu hội đồng:
/// "hệ thống phải tự tính toán, không giao phó hết cho AI".
/// ============================================================
class FinancialAnalyticsService {
  // Ngưỡng mặc định — dùng làm cơ sở fallback khi chưa có cấu hình từ xa
  static const double kCategorySpikeThreshold = 0.30; // tăng >30% so tháng trước
  static const double kCategoryShareThreshold = 0.25; // 1 danh mục chiếm >25% thu nhập
  static const double kLowSavingRateThreshold = 0.20; // tỷ lệ tiết kiệm <20%

  final FinancialHeuristicsConfig? _heuristicsOverride;

  FinancialAnalyticsService({FinancialHeuristicsConfig? heuristicsOverride})
      : _heuristicsOverride = heuristicsOverride;

  /// Lấy bộ ngưỡng định lượng đang hiệu lực (ưu tiên override từ Sandbox/Test,
  /// sau đó đến cấu hình Published trong AiConfigSyncService, cuối cùng là mặc định).
  FinancialHeuristicsConfig get effectiveHeuristics =>
      _heuristicsOverride ?? AiConfigSyncService.instance.currentHeuristics;

  /// Tính "Điểm tin cậy" — mức độ vi phạm ngưỡng càng xa, tin cậy càng cao
  double _calculateConfidence(double currentValue, double thresholdValue) {
    if (thresholdValue == 0) return 60;
    final deviation = (currentValue - thresholdValue).abs() / thresholdValue;
    return (60 + deviation * 100).clamp(60, 99).toDouble();
  }

  Map<String, double> _sumByCategory(List<AppTransaction> transactions) {
    final Map<String, double> result = {};
    for (final tx in transactions.where((t) => t.type == 'expense')) {
      result[tx.categoryId] = (result[tx.categoryId] ?? 0) + tx.amount;
    }
    return result;
  }

  /// Phát hiện danh sách vấn đề tài chính của tháng hiện tại, so với tháng trước.
  /// Cấu trúc chuẩn: Vấn đề → Nguyên nhân → Tác động → Đề xuất.
  List<FinancialIssue> detectIssues({
    required List<AppTransaction> currentMonthTx,
    required List<AppTransaction> lastMonthTx,
    required List<Category> categories,
    required double monthlyIncome,
    FinancialHeuristicsConfig? heuristicsOverride,
  }) {
    final h = heuristicsOverride ?? effectiveHeuristics;
    final spikeThreshold = h.categorySpikeRatio;
    final shareThreshold = h.categoryIncomeShareThreshold;
    final lowSavingThreshold = h.minRecommendedSavingRate;
    final incomeDropWarnThreshold = h.incomeDropWarningRatio;
    final incomeDropCritThreshold = h.incomeDropCriticalRatio;

    final issues = <FinancialIssue>[];

    final currentByCategory = _sumByCategory(currentMonthTx);
    final lastByCategory = _sumByCategory(lastMonthTx);

    final totalExpense =
        currentByCategory.values.fold<double>(0, (a, b) => a + b);
    final totalIncome = currentMonthTx
        .where((t) => t.type == 'income')
        .fold<double>(0, (a, t) => a + t.amount);
    final effectiveIncome = totalIncome > 0 ? totalIncome : monthlyIncome;

    // 1. Phát hiện danh mục tăng đột biến so với tháng trước
    currentByCategory.forEach((categoryId, currentAmount) {
      final lastAmount = lastByCategory[categoryId] ?? 0;
      if (lastAmount > 0) {
        final percentChange = (currentAmount - lastAmount) / lastAmount;
        if (percentChange > spikeThreshold) {
          final catName = categories
              .firstWhere(
                (c) => c.categoryId == categoryId,
                orElse: () => Category(
                  categoryId: categoryId,
                  userId: '',
                  name: 'Khác',
                  type: 'expense',
                  icon: 'category',
                  color: 0xFF9E9E9E,
                ),
              )
              .name;
          final threshold = lastAmount * (1 + spikeThreshold);
          final diff = currentAmount - lastAmount;
          final criticalSpike = math.max(0.5, spikeThreshold + 0.20);

          issues.add(FinancialIssue(
            title:
                '$catName tăng ${(percentChange * 100).round()}% so với tháng trước',
            description:
                'Tháng trước: ${lastAmount.round()}đ → Tháng này: ${currentAmount.round()}đ',
            severity: percentChange > criticalSpike
                ? IssueSeverity.critical
                : IssueSeverity.warning,
            category: IssueCategory.spike,
            confidenceScore: _calculateConfidence(currentAmount, threshold),
            categoryName: catName,
            currentValue: currentAmount,
            thresholdValue: threshold,
            rootCause:
                'Chi tiêu danh mục $catName tăng đột biến ${(percentChange * 100).round()}% so với mức trung bình tháng trước (${AppFormatters.compactCurrency(lastAmount, unit: 'đ')}).',
            impact:
                'Làm phát sinh thêm ${AppFormatters.compactCurrency(diff, unit: 'đ')} ngoài định mức, thu hẹp thặng dư dòng tiền.',
            recommendation:
                'Đặt hạn mức tối đa ${AppFormatters.compactCurrency(threshold, unit: 'đ')} và rà soát các khoản chi lớn trong các tuần tiếp theo.',
          ));
        }
      }
    });

    // 2. Phát hiện danh mục chiếm tỷ trọng quá lớn trong thu nhập
    if (effectiveIncome > 0) {
      currentByCategory.forEach((categoryId, amount) {
        final share = amount / effectiveIncome;
        if (share > shareThreshold) {
          final catName = categories
              .firstWhere(
                (c) => c.categoryId == categoryId,
                orElse: () => Category(
                  categoryId: categoryId,
                  userId: '',
                  name: 'Khác',
                  type: 'expense',
                  icon: 'category',
                  color: 0xFF9E9E9E,
                ),
              )
              .name;
          final shareRecPct = (shareThreshold * 100).round();
          final criticalShare = math.max(0.4, shareThreshold + 0.15);
          issues.add(FinancialIssue(
            title:
                '$catName chiếm ${(share * 100).round()}% thu nhập tháng này',
            description:
                'Vượt ngưỡng khuyến nghị $shareRecPct%',
            severity:
                share > criticalShare ? IssueSeverity.critical : IssueSeverity.warning,
            category: IssueCategory.budgetShare,
            confidenceScore:
                _calculateConfidence(share, shareThreshold),
            categoryName: catName,
            currentValue: share,
            thresholdValue: shareThreshold,
            rootCause:
                'Một danh mục duy nhất ($catName) chiếm tới ${(share * 100).round()}% tổng thu nhập.',
            impact:
                'Gây mất cân bằng cơ cấu chi tiêu, làm giảm khả năng ứng phó khi có biến cố tài chính.',
            recommendation:
                'Cân đối tinh giản các khoản chi chưa cấp thiết trong nhóm $catName về dưới $shareRecPct% thu nhập.',
          ));
        }
      });
    }

    // 3. Phát hiện tỷ lệ tiết kiệm thấp
    if (effectiveIncome > 0) {
      final savingRate = (effectiveIncome - totalExpense) / effectiveIncome;
      if (savingRate < lowSavingThreshold) {
        final lowSavingPct = (lowSavingThreshold * 100).round();
        issues.add(FinancialIssue(
          title: 'Tỷ lệ tiết kiệm chỉ đạt ${(savingRate * 100).round()}%',
          description:
              'Thấp hơn ngưỡng khuyến nghị $lowSavingPct%',
          severity:
              savingRate < 0.05 ? IssueSeverity.critical : IssueSeverity.warning,
          category: IssueCategory.lowSaving,
          confidenceScore:
              _calculateConfidence(savingRate, lowSavingThreshold),
          currentValue: savingRate,
          thresholdValue: lowSavingThreshold,
          rootCause:
              'Chi tiêu đã chiếm ${(totalExpense / effectiveIncome * 100).round()}% tổng thu nhập trong kỳ.',
          impact:
              'Khả năng tích lũy tài sản và tiến độ các mục tiêu tiết kiệm bị đình trệ.',
          recommendation:
              'Cắt giảm bớt các khoản chi linh hoạt (mua sắm, giải trí) để nâng tỷ lệ tích lũy lên tối thiểu $lowSavingPct%.',
        ));
      }
    }

    // 4. Phát hiện dòng tiền âm (Chi vượt thu)
    if (totalIncome > 0 && totalExpense > totalIncome) {
      final deficit = totalExpense - totalIncome;
      issues.add(FinancialIssue(
        title:
            'Chi tiêu vượt thu nhập ${AppFormatters.compactCurrency(deficit, unit: 'đ')}',
        description: 'Dòng tiền tháng này đang bị âm',
        severity: IssueSeverity.critical,
        category: IssueCategory.negativeCashflow,
        confidenceScore: 95.0,
        currentValue: deficit,
        thresholdValue: 0,
        rootCause:
            'Tổng chi tiêu (${AppFormatters.compactCurrency(totalExpense, unit: 'đ')}) vượt quá tổng thu (${AppFormatters.compactCurrency(totalIncome, unit: 'đ')}).',
        impact:
            'Dòng tiền thâm hụt trực tiếp làm suy giảm số dư các ví tài khoản.',
        recommendation:
            'Tạm dừng các khoản chi tiêu không bắt buộc để chặn đà suy giảm số dư.',
      ));
    }

    // 5. Phát hiện thu nhập sụt giảm mạnh so với tháng trước (>20% mặc định)
    final lastMonthIncome = lastMonthTx
        .where((t) => t.type == 'income')
        .fold<double>(0, (a, t) => a + t.amount);
    if (lastMonthIncome > 0 && totalIncome > 0) {
      final dropRate = (lastMonthIncome - totalIncome) / lastMonthIncome;
      if (dropRate > incomeDropWarnThreshold) {
        issues.add(FinancialIssue(
          title: 'Thu nhập giảm ${(dropRate * 100).round()}% so với tháng trước',
          description:
              'Tháng trước: ${AppFormatters.compactCurrency(lastMonthIncome, unit: 'đ')} → Tháng này: ${AppFormatters.compactCurrency(totalIncome, unit: 'đ')}',
          severity:
              dropRate > incomeDropCritThreshold ? IssueSeverity.critical : IssueSeverity.warning,
          category: IssueCategory.incomeDrop,
          confidenceScore: 90.0,
          currentValue: dropRate,
          thresholdValue: incomeDropWarnThreshold,
          rootCause:
              'Các nguồn thu trong kỳ ghi nhận sụt giảm ${(dropRate * 100).round()}%.',
          impact:
              'Thu hẹp hạn mức chi tiêu an toàn và khả năng tích lũy tiền mặt.',
          recommendation:
              'Chủ động thắt chặt ngân sách chi tiêu để duy trì trạng thái dòng tiền cân bằng.',
        ));
      }
    }

    return issues;
  }

  /// 2. Phân tích cơ cấu và biến động thu nhập
  IncomeAnalytics computeIncomeAnalytics({
    required List<AppTransaction> currentMonthTx,
    required List<AppTransaction> lastMonthTx,
    required List<Category> categories,
    List<List<AppTransaction>>? precedingMonthsTx,
    double fallbackMonthlyIncome = 0,
  }) {
    final currentIncomeTx =
        currentMonthTx.where((t) => t.type == 'income').toList();
    final lastIncomeTx = lastMonthTx.where((t) => t.type == 'income').toList();

    double currentTotalIncome =
        currentIncomeTx.fold<double>(0, (sum, t) => sum + t.amount);
    if (currentTotalIncome == 0 && fallbackMonthlyIncome > 0) {
      currentTotalIncome = fallbackMonthlyIncome;
    }

    final double lastTotalIncome =
        lastIncomeTx.fold<double>(0, (sum, t) => sum + t.amount);
    final double growthRate = lastTotalIncome > 0
        ? (currentTotalIncome - lastTotalIncome) / lastTotalIncome
        : 0.0;

    // Nguồn thu nhập theo category
    final Map<String, double> incomeByCategory = {};
    for (final tx in currentIncomeTx) {
      incomeByCategory[tx.categoryId] =
          (incomeByCategory[tx.categoryId] ?? 0) + tx.amount;
    }

    final List<IncomeSourceBreakdown> sources = [];
    final sortedSources = incomeByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in sortedSources) {
      final catName = categories
          .firstWhere(
            (c) => c.categoryId == entry.key,
            orElse: () => Category(
              categoryId: entry.key,
              userId: '',
              name: 'Thu nhập khác',
              type: 'income',
              icon: 'account_balance_wallet',
              color: 0xFF4CAF50,
            ),
          )
          .name;
      final pct =
          currentTotalIncome > 0 ? (entry.value / currentTotalIncome) : 0.0;
      sources.add(IncomeSourceBreakdown(
        categoryId: entry.key,
        categoryName: catName,
        amount: entry.value,
        percentage: pct,
      ));
    }

    // Đánh giá mức độ ổn định thu nhập
    String stability = 'Ổn định';
    if (precedingMonthsTx != null && precedingMonthsTx.isNotEmpty) {
      final List<double> history = [];
      for (final mTx in precedingMonthsTx) {
        final val = mTx
            .where((t) => t.type == 'income')
            .fold<double>(0, (sum, t) => sum + t.amount);
        if (val > 0) history.add(val);
      }
      if (lastTotalIncome > 0) history.add(lastTotalIncome);
      if (currentTotalIncome > 0) history.add(currentTotalIncome);

      if (history.length >= 2) {
        final avg = history.reduce((a, b) => a + b) / history.length;
        if (avg > 0) {
          final variance = history
                  .map((x) => (x - avg) * (x - avg))
                  .reduce((a, b) => a + b) /
              history.length;
          final stdDev = math.sqrt(variance);
          final cv = stdDev / avg;
          if (cv > 0.35) {
            stability = 'Biến động mạnh';
          } else if (cv > 0.15) {
            stability = 'Biến động nhẹ';
          }
        }
      }
    }

    // Câu bình luận phân tích ý nghĩa
    final topSourceName = sources.isNotEmpty ? sources.first.categoryName : null;
    final topSourcePct =
        sources.isNotEmpty ? (sources.first.percentage * 100).round() : 0;
    String commentary;

    if (currentTotalIncome == 0) {
      commentary = 'Chưa ghi nhận nguồn thu nhập trong tháng này.';
    } else if (lastTotalIncome > 0) {
      final growthPct = (growthRate * 100).round();
      if (growthRate >= 0.05) {
        commentary =
            'Thu nhập tháng này tăng $growthPct% so với tháng trước'
            '${topSourceName != null ? ', chủ yếu từ nguồn $topSourceName ($topSourcePct%)' : ''}.'
            ' Mức độ nguồn thu $stability.';
      } else if (growthRate <= -0.05) {
        commentary =
            'Thu nhập tháng này giảm ${-growthPct}% so với tháng trước.'
            ' Khuyến nghị điều chỉnh kế hoạch chi tiêu phù hợp.';
      } else {
        commentary =
            'Thu nhập duy trì ổn định so với tháng trước'
            '${topSourceName != null ? ' (nguồn chính: $topSourceName chiếm $topSourcePct%)' : ''}.';
      }
    } else {
      commentary =
          'Tổng thu nhập đạt ${AppFormatters.compactCurrency(currentTotalIncome, unit: 'đ')}'
          '${topSourceName != null ? ', chủ yếu từ nguồn $topSourceName' : ''}.';
    }

    return IncomeAnalytics(
      currentMonthIncome: currentTotalIncome,
      lastMonthIncome: lastTotalIncome,
      growthRate: growthRate,
      sources: sources,
      stability: stability,
      commentary: commentary,
    );
  }

  /// 3. Phân tích dòng tiền & khả năng giữ lại (Net Cash Flow & Savings Rate)
  CashFlowAnalytics computeCashFlowAnalytics({
    required double currentMonthIncome,
    required double currentMonthExpense,
    required double lastMonthIncome,
    required double lastMonthExpense,
  }) {
    final netCashFlow = currentMonthIncome - currentMonthExpense;
    final savingsRate = currentMonthIncome > 0
        ? (netCashFlow / currentMonthIncome * 100)
        : 0.0;
    final isPositive = netCashFlow >= 0;

    final lastMonthNetCashFlow = lastMonthIncome - lastMonthExpense;
    final netCashFlowChange = netCashFlow - lastMonthNetCashFlow;

    final String sustainabilityStatus;
    if (!isPositive) {
      sustainabilityStatus = 'Thâm hụt rủi ro';
    } else if (savingsRate >= 30) {
      sustainabilityStatus = 'Rất vững chắc';
    } else if (savingsRate >= 15) {
      sustainabilityStatus = 'Bền vững';
    } else {
      sustainabilityStatus = 'Cần chú ý';
    }

    final String summaryComment;
    final double minRecSavePct =
        effectiveHeuristics.minRecommendedSavingRate * 100;
    if (isPositive) {
      summaryComment =
          'Bạn có thu nhập ${AppFormatters.compactCurrency(currentMonthIncome, unit: 'đ')} '
          'và chi tiêu ${AppFormatters.compactCurrency(currentMonthExpense, unit: 'đ')}, '
          'còn lại ${AppFormatters.compactCurrency(netCashFlow, unit: 'đ')} '
          '(${savingsRate.round()}% thu nhập). Dòng tiền tích cực, khả năng tiết kiệm ${savingsRate >= minRecSavePct ? 'rất tốt' : 'ổn định'}.';
    } else {
      final deficit = -netCashFlow;
      summaryComment =
          'Chi tiêu đang vượt thu nhập ${AppFormatters.compactCurrency(deficit, unit: 'đ')}. '
          'Nếu xu hướng này tiếp tục, số dư các ví có nguy cơ suy giảm nhanh chóng trong các tháng tiếp theo.';
    }

    return CashFlowAnalytics(
      totalIncome: currentMonthIncome,
      totalExpense: currentMonthExpense,
      netCashFlow: netCashFlow,
      savingsRate: savingsRate,
      isPositive: isPositive,
      lastMonthNetCashFlow: lastMonthNetCashFlow,
      netCashFlowChange: netCashFlowChange,
      sustainabilityStatus: sustainabilityStatus,
      summaryComment: summaryComment,
    );
  }

  /// 4. Đánh giá tính khả thi mục tiêu tiết kiệm
  SavingsGoalAssessment evaluateSavingGoals({
    required List<SavingGoal> goals,
    required double netCashFlow,
  }) {
    final activeGoals =
        goals.where((g) => g.savedAmount < g.targetAmount).toList();
    if (activeGoals.isEmpty) {
      return const SavingsGoalAssessment(
        totalMonthlyRequired: 0,
        availableCashFlow: 0,
        gapAmount: 0,
        canFulfillAllGoals: true,
        goals: [],
        overallAdvice:
            'Bạn chưa có mục tiêu tiết kiệm nào đang hoạt động. Hãy tạo mục tiêu để định hướng tài chính hiệu quả hơn.',
      );
    }

    double totalMonthlyRequired = 0;
    final List<GoalFeasibilityItem> items = [];

    for (final g in activeGoals) {
      final monthlyReq = g.monthlyRequired;
      totalMonthlyRequired += monthlyReq;

      final isAtRisk = netCashFlow < monthlyReq || netCashFlow <= 0;
      final statusText = isAtRisk
          ? (netCashFlow <= 0 ? 'Nguy cơ trễ hạn cao' : 'Tiến độ bị chậm')
          : 'Đang đúng tiến độ';

      String suggestion;
      if (isAtRisk) {
        final deficit = (monthlyReq - (netCashFlow > 0 ? netCashFlow : 0)).round();
        final remainingAmount = g.targetAmount - g.savedAmount;
        final achievableMonths = (netCashFlow > 100000)
            ? (remainingAmount / netCashFlow).ceil()
            : (g.months + 3);
        final extraMonths = (achievableMonths - g.months).clamp(1, 24);

        suggestion =
            'Thiếu ${AppFormatters.compactCurrency(deficit.toDouble(), unit: 'đ')}/tháng. '
            'Đề xuất: Tối ưu chi tiêu hoặc gia hạn thêm $extraMonths tháng.';
      } else {
        suggestion = 'Thặng dư dòng tiền đủ để tích lũy đều đặn mỗi tháng.';
      }

      items.add(GoalFeasibilityItem(
        goalId: g.goalId,
        goalName: g.name,
        targetAmount: g.targetAmount,
        savedAmount: g.savedAmount,
        monthlyRequired: monthlyReq,
        monthsRemaining: g.months,
        percentComplete: g.percentComplete,
        isAtRisk: isAtRisk,
        statusText: statusText,
        suggestion: suggestion,
      ));
    }

    final gapAmount =
        (totalMonthlyRequired - netCashFlow).clamp(0.0, double.infinity).toDouble();
    final canFulfill = netCashFlow >= totalMonthlyRequired && netCashFlow > 0;

    final String overallAdvice;
    if (canFulfill) {
      overallAdvice =
          'Dòng tiền thặng dư (${AppFormatters.compactCurrency(netCashFlow, unit: 'đ')}) '
          'hoàn toàn đáp ứng đủ tổng mức tích lũy cho ${items.length} mục tiêu '
          '(${AppFormatters.compactCurrency(totalMonthlyRequired, unit: 'đ')}/tháng).';
    } else {
      overallAdvice =
          'Tổng nhu cầu tích lũy là ${AppFormatters.compactCurrency(totalMonthlyRequired, unit: 'đ')}/tháng, '
          'thặng dư dòng tiền hiện thiếu hụt ${AppFormatters.compactCurrency(gapAmount, unit: 'đ')}. '
          'Cần thực hiện kế hoạch cắt giảm chi tiêu bên dưới.';
    }

    return SavingsGoalAssessment(
      totalMonthlyRequired: totalMonthlyRequired,
      availableCashFlow: netCashFlow,
      gapAmount: gapAmount,
      canFulfillAllGoals: canFulfill,
      goals: items,
      overallAdvice: overallAdvice,
    );
  }

  /// 5. Tạo kế hoạch hành động cải thiện cụ thể tháng tới (Action Plan)
  FinancialActionPlan generateActionPlan({
    required List<AppTransaction> currentMonthTx,
    required List<Category> categories,
    required List<BudgetForecast> budgetForecasts,
    required List<SpendingAnomaly> anomalies,
    required List<FinancialIssue> issues,
    required double netCashFlow,
    double savingsShortfall = 0,
  }) {
    final Map<String, double> spentByCategory = _sumByCategory(currentMonthTx);
    final List<ActionPlanItem> items = [];
    final Set<String> processedCategoryIds = {};

    // 1. Ưu tiên các danh mục vượt hoặc có nguy cơ vượt ngân sách
    for (final b in budgetForecasts) {
      if (b.status == BudgetForecastStatus.exceeded ||
          b.status == BudgetForecastStatus.atRisk) {
        final spent = b.spent;
        final excess = (spent - b.limit).clamp(0.0, double.infinity).toDouble();
        double reduction = excess > 0 ? (excess * 1.1) : (spent * 0.15);
        reduction = (reduction / 50000).ceil() * 50000.0;
        reduction = reduction.clamp(50000.0, spent * 0.4).toDouble();

        final targetBudget = (spent - reduction).clamp(0.0, double.infinity).toDouble();

        items.add(ActionPlanItem(
          categoryName: b.categoryName,
          actionTitle: 'Giảm chi tiêu ${b.categoryName}',
          currentSpend: spent,
          targetReduction: reduction,
          suggestedBudget: targetBudget,
          rationales: b.status == BudgetForecastStatus.exceeded
              ? 'Đã vượt hạn mức ngân sách ${AppFormatters.compactCurrency(excess, unit: 'đ')}'
              : 'Có nguy cơ vượt hạn mức trước khi kết thúc tháng',
        ));
        processedCategoryIds.add(b.categoryId);
      }
    }

    // 2. Các danh mục có chi tiêu bất thường (Anomaly) chưa được thêm
    for (final a in anomalies) {
      if (!processedCategoryIds.contains(a.categoryId)) {
        double reduction = a.excessAmount * 0.7;
        reduction = (reduction / 50000).ceil() * 50000.0;
        reduction = reduction.clamp(50000.0, a.currentSpend * 0.35).toDouble();

        final targetBudget =
            (a.currentSpend - reduction).clamp(0.0, double.infinity).toDouble();

        items.add(ActionPlanItem(
          categoryName: a.categoryName,
          actionTitle: 'Tối ưu danh mục ${a.categoryName}',
          currentSpend: a.currentSpend,
          targetReduction: reduction,
          suggestedBudget: targetBudget,
          rationales:
              'Chi tiêu đột biến cao hơn ${(a.excessRatio * 100 - 100).round()}% so với mức thông thường',
        ));
        processedCategoryIds.add(a.categoryId);
      }
    }

    // 3. Nếu chưa đủ đề xuất, chọn các danh mục chi tiêu lớn nhất để tối ưu
    if (items.length < 3) {
      final sortedExpenses = spentByCategory.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      for (final entry in sortedExpenses) {
        if (items.length >= 3) break;
        if (processedCategoryIds.contains(entry.key)) continue;

        final cat = categories.firstWhere(
          (c) => c.categoryId == entry.key,
          orElse: () => Category(
            categoryId: entry.key,
            userId: '',
            name: 'Khác',
            type: 'expense',
            icon: '',
            color: 0,
          ),
        );

        if (entry.value >= 300000) {
          double reduction = (entry.value * 0.15 / 50000).ceil() * 50000.0;
          reduction = reduction.clamp(50000.0, entry.value * 0.25);
          final targetBudget = entry.value - reduction;

          items.add(ActionPlanItem(
            categoryName: cat.name,
            actionTitle: 'Cân đối lại ${cat.name}',
            currentSpend: entry.value,
            targetReduction: reduction,
            suggestedBudget: targetBudget,
            rationales: 'Danh mục chi tiêu lớn, có thể tinh giản 15% chi phí linh hoạt',
          ));
          processedCategoryIds.add(entry.key);
        }
      }
    }

    final totalProjectedSavings =
        items.fold<double>(0, (sum, i) => sum + i.targetReduction);
    final targetMonthlySavings =
        savingsShortfall > 0 ? savingsShortfall : totalProjectedSavings;

    final actionSummary = items.isEmpty
        ? 'Duy trì kỷ luật chi tiêu hiện tại. Tất cả các danh mục đều đang trong giới hạn an toàn.'
        : 'Mục tiêu: Tiết kiệm thêm ${AppFormatters.compactCurrency(totalProjectedSavings, unit: 'đ')}/tháng '
            'bằng cách tối ưu ${items.length} danh mục chi tiêu lớn.';

    return FinancialActionPlan(
      targetMonthlySavings: targetMonthlySavings,
      items: items,
      totalProjectedSavings: totalProjectedSavings,
      actionSummary: actionSummary,
    );
  }

  /// 6. Trích xuất danh sách điểm mạnh tài chính để đánh giá công tâm
  List<String> extractStrengths({
    required CashFlowAnalytics cashFlow,
    required IncomeAnalytics income,
    required List<BudgetForecast> budgetForecasts,
    required List<SpendingAnomaly> anomalies,
  }) {
    final strengths = <String>[];
    final double minRecSavePct =
        effectiveHeuristics.minRecommendedSavingRate * 100;
    if (cashFlow.isPositive && cashFlow.savingsRate >= minRecSavePct) {
      strengths.add(
          'Tỷ lệ tiết kiệm đạt chuẩn tốt (${cashFlow.savingsRate.round()}%)');
    }
    if (cashFlow.isPositive) {
      strengths.add(
          'Dòng tiền ròng duy trì thặng dư dương (+${AppFormatters.compactCurrency(cashFlow.netCashFlow, unit: 'đ')})');
    }
    if (income.growthRate > 0.03) {
      strengths.add(
          'Thu nhập tăng trưởng (+${(income.growthRate * 100).round()}% so với tháng trước)');
    }
    if (income.stability == 'Ổn định') {
      strengths.add('Nguồn thu nhập duy trì ổn định');
    }
    final allBudgetsSafe = budgetForecasts.isNotEmpty &&
        budgetForecasts.every((b) => b.status == BudgetForecastStatus.safe);
    if (allBudgetsSafe) {
      strengths.add('Tuân thủ ngân sách xuất sắc (100% danh mục an toàn)');
    }
    if (anomalies.isEmpty) {
      strengths.add('Không có khoản chi tiêu phát sinh bất thường');
    }
    if (strengths.isEmpty) {
      strengths.add('Đã chủ động ghi chép và theo dõi giao dịch định kỳ');
    }
    return strengths;
  }

  /// Tính Điểm sức khỏe tài chính (0-100) có khử trùng lặp theo danh mục
  /// để đồng bộ kết quả giữa AiInsightScreen và FinancialExportService.
  int calculateHealthScore(List<FinancialIssue> issues) {
    double penalty = 0;
    final Set<String> penalizedCategories = {};
    for (final issue in issues) {
      if (issue.categoryName != null && issue.categoryName!.isNotEmpty) {
        if (!penalizedCategories.contains(issue.categoryName)) {
          penalty += issue.severity == IssueSeverity.critical ? 20 : 10;
          penalizedCategories.add(issue.categoryName!);
        }
      } else {
        penalty += issue.severity == IssueSeverity.critical ? 20 : 10;
      }
    }
    return (100 - penalty).clamp(0, 100).round();
  }

  /// ============================================================
  /// 7. ĐÁNH GIÁ ĐỘ ĐỦ DỮ LIỆU ĐA CHIỀU (5 CẤP ĐỘ: TIER 0 -> TIER 4)
  /// - Tier 0 kiểm tra toàn bộ: transactions, budgets, wallets, savingGoals, monthly_plans.
  /// - Không bắt buộc phải có >= 2 danh mục chi tiêu mới được phân tích.
  /// - Phân biệt rõ so sánh 1 tháng liền kề (Tier 3) và xu hướng đa tháng (Tier 4).
  /// - Xét đến tháng chưa hoàn tất (isPartialMonth).
  /// ============================================================
  DataSufficiencyAssessment assessDataSufficiency({
    required List<AppTransaction> currentMonthTx,
    required List<List<AppTransaction>> historicalMonthsTx,
    List<Budget> currentBudgets = const [],
    List<Wallet> wallets = const [],
    List<SavingGoal> savingGoals = const [],
    MonthlyFinancialPlan? activePlan,
    DateTime? analysisMonthDate,
    DateTime? referenceToday,
  }) {
    final now = referenceToday ?? DateTime.now();
    final targetDate = analysisMonthDate ?? DateTime(now.year, now.month, 1);
    final totalDaysInMonth =
        DateTime(targetDate.year, targetDate.month + 1, 0).day;
    final bool isCurrentCalendarMonth =
        targetDate.year == now.year && targetDate.month == now.month;
    final bool isPartialMonth =
        isCurrentCalendarMonth && now.day < totalDaysInMonth;
    final int daysElapsed = isCurrentCalendarMonth
        ? now.day.clamp(1, totalDaysInMonth)
        : totalDaysInMonth;

    final expenseTx =
        currentMonthTx.where((t) => t.type == 'expense').toList();
    final incomeTx = currentMonthTx.where((t) => t.type == 'income').toList();

    final Set<String> activeDayKeys = currentMonthTx
        .map((t) =>
            '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}')
        .toSet();
    final Set<String> expenseCategoryIds =
        expenseTx.map((t) => t.categoryId).toSet();

    int qualifiedHistoryMonths = 0;
    for (final monthTx in historicalMonthsTx) {
      final histExpenses = monthTx.where((t) => t.type == 'expense').toList();
      final histDays = monthTx
          .map((t) => '${t.date.year}-${t.date.month}-${t.date.day}')
          .toSet();
      if (histExpenses.length >= 5 && histDays.length >= 3) {
        qualifiedHistoryMonths++;
      }
    }

    final bool hasIncomeData = incomeTx.isNotEmpty ||
        historicalMonthsTx.any((m) => m.any((t) => t.type == 'income'));
    final bool hasBudgetData = currentBudgets.isNotEmpty;
    final bool hasWalletBalance =
        wallets.any((w) => w.isActive && w.balance > 0);
    final bool hasSavingGoals = savingGoals.isNotEmpty;
    final bool hasActivePlan = activePlan != null;
    final bool hasAnyHistoryTx =
        historicalMonthsTx.any((m) => m.isNotEmpty);

    if (currentMonthTx.isEmpty &&
        !hasAnyHistoryTx &&
        !hasBudgetData &&
        !hasWalletBalance &&
        !hasSavingGoals &&
        !hasActivePlan) {
      return DataSufficiencyAssessment(
        tier: DataSufficiencyTier.empty,
        expenseTxCount: 0,
        totalTxCount: 0,
        activeDaysCount: 0,
        expenseCategoriesCovered: 0,
        qualifiedHistoryMonths: 0,
        isPartialMonth: isPartialMonth,
        daysElapsedInMonth: daysElapsed,
        totalDaysInMonth: totalDaysInMonth,
        hasIncomeData: false,
        hasBudgetData: false,
        hasWalletBalance: false,
        hasSavingGoals: false,
        hasActivePlan: false,
        limitationNote:
            'Chưa có giao dịch, ngân sách, ví có số dư hay mục tiêu tiết kiệm nào. Hãy nhập giao dịch hoặc thiết lập ngân sách đầu tiên.',
      );
    }

    final bool currentMonthDenseEnough =
        expenseTx.length >= 5 && activeDayKeys.length >= 3;

    if (!currentMonthDenseEnough) {
      return DataSufficiencyAssessment(
        tier: DataSufficiencyTier.preliminary,
        expenseTxCount: expenseTx.length,
        totalTxCount: currentMonthTx.length,
        activeDaysCount: activeDayKeys.length,
        expenseCategoriesCovered: expenseCategoryIds.length,
        qualifiedHistoryMonths: qualifiedHistoryMonths,
        isPartialMonth: isPartialMonth,
        daysElapsedInMonth: daysElapsed,
        totalDaysInMonth: totalDaysInMonth,
        hasIncomeData: hasIncomeData,
        hasBudgetData: hasBudgetData,
        hasWalletBalance: hasWalletBalance,
        hasSavingGoals: hasSavingGoals,
        hasActivePlan: hasActivePlan,
        limitationNote:
            'Dữ liệu chi tiêu trong tháng còn ít (${expenseTx.length} giao dịch trên ${activeDayKeys.length} ngày). Hệ thống chỉ đưa ra nhận xét sơ bộ về cơ cấu hiện tại và không ngoại suy dự báo cuối tháng.',
      );
    }

    if (qualifiedHistoryMonths == 0) {
      return DataSufficiencyAssessment(
        tier: DataSufficiencyTier.currentMonthAnalysis,
        expenseTxCount: expenseTx.length,
        totalTxCount: currentMonthTx.length,
        activeDaysCount: activeDayKeys.length,
        expenseCategoriesCovered: expenseCategoryIds.length,
        qualifiedHistoryMonths: 0,
        isPartialMonth: isPartialMonth,
        daysElapsedInMonth: daysElapsed,
        totalDaysInMonth: totalDaysInMonth,
        hasIncomeData: hasIncomeData,
        hasBudgetData: hasBudgetData,
        hasWalletBalance: hasWalletBalance,
        hasSavingGoals: hasSavingGoals,
        hasActivePlan: hasActivePlan,
        limitationNote: isPartialMonth
            ? 'Đủ dữ liệu phân tích trong tháng (tính đến ngày $daysElapsed/$totalDaysInMonth). Chưa có tháng lịch sử liền kề đủ chuẩn nên không so sánh biến động liên tháng (MoM).'
            : 'Đủ dữ liệu phân tích trong tháng. Chưa có dữ liệu lịch sử tháng trước để so sánh liên tháng.',
      );
    }

    if (qualifiedHistoryMonths == 1) {
      return DataSufficiencyAssessment(
        tier: DataSufficiencyTier.monthOverMonthComparison,
        expenseTxCount: expenseTx.length,
        totalTxCount: currentMonthTx.length,
        activeDaysCount: activeDayKeys.length,
        expenseCategoriesCovered: expenseCategoryIds.length,
        qualifiedHistoryMonths: 1,
        isPartialMonth: isPartialMonth,
        daysElapsedInMonth: daysElapsed,
        totalDaysInMonth: totalDaysInMonth,
        hasIncomeData: hasIncomeData,
        hasBudgetData: hasBudgetData,
        hasWalletBalance: hasWalletBalance,
        hasSavingGoals: hasSavingGoals,
        hasActivePlan: hasActivePlan,
        limitationNote:
            'Đủ dữ liệu để phân tích trong tháng và so sánh với 1 tháng liền trước (MoM). Chưa kết luận xu hướng dài hạn đa tháng.',
      );
    }

    return DataSufficiencyAssessment(
      tier: DataSufficiencyTier.multiMonthTrend,
      expenseTxCount: expenseTx.length,
      totalTxCount: currentMonthTx.length,
      activeDaysCount: activeDayKeys.length,
      expenseCategoriesCovered: expenseCategoryIds.length,
      qualifiedHistoryMonths: qualifiedHistoryMonths,
      isPartialMonth: isPartialMonth,
      daysElapsedInMonth: daysElapsed,
      totalDaysInMonth: totalDaysInMonth,
      hasIncomeData: hasIncomeData,
      hasBudgetData: hasBudgetData,
      hasWalletBalance: hasWalletBalance,
      hasSavingGoals: hasSavingGoals,
      hasActivePlan: hasActivePlan,
      limitationNote: isPartialMonth
          ? 'Đủ dữ liệu phân tích xu hướng qua ${qualifiedHistoryMonths + 1} tháng (tháng hiện tại tính đến ngày $daysElapsed/$totalDaysInMonth).'
          : 'Đủ dữ liệu phân tích xu hướng đa tháng và hành vi chi tiêu toàn diện.',
    );
  }

  /// ============================================================
  /// 8. XÁC ĐỊNH THU NHẬP THAM CHIẾU (KHÔNG BAO GIỜ LẤY BUDGET LÀM INCOME)
  /// ============================================================
  ReferenceIncomeAssessment determineReferenceIncome({
    required List<AppTransaction> currentMonthTx,
    required List<List<AppTransaction>> historicalMonthsTx,
    List<Budget> currentBudgets = const [],
    double? declaredExpectedIncome,
    bool isPartialMonth = false,
  }) {
    final actualCurrentIncome = currentMonthTx
        .where((t) => t.type == 'income')
        .fold<double>(0, (s, t) => s + t.amount);

    final historicalIncomes = historicalMonthsTx
        .map((m) => m
            .where((t) => t.type == 'income')
            .fold<double>(0, (s, t) => s + t.amount))
        .where((inc) => inc > 0)
        .toList();

    final currentTotalBudget =
        currentBudgets.fold<double>(0, (s, b) => s + b.limit);

    double histMean = 0;
    double histStdDev = 0;
    if (historicalIncomes.isNotEmpty) {
      histMean =
          historicalIncomes.reduce((a, b) => a + b) / historicalIncomes.length;
      if (historicalIncomes.length >= 2) {
        final variance = historicalIncomes
                .map((x) => math.pow(x - histMean, 2))
                .reduce((a, b) => a + b) /
            historicalIncomes.length;
        histStdDev = math.sqrt(variance);
      }
    }

    if (declaredExpectedIncome != null && declaredExpectedIncome > 0) {
      return ReferenceIncomeAssessment(
        mode: IncomeStabilityMode.declared,
        referenceIncome: declaredExpectedIncome,
        actualCurrentMonthIncome: actualCurrentIncome,
        historicalMeanIncome: histMean,
        historicalStdDevIncome: histStdDev,
        currentTotalBudget: currentTotalBudget,
        isIncomeLikelyIncompleteInCurrentMonth: isPartialMonth &&
            actualCurrentIncome < declaredExpectedIncome * 0.85,
        explanation:
            'Sử dụng mức thu nhập dự kiến do bạn xác nhận (${AppFormatters.compactCurrency(declaredExpectedIncome, unit: 'đ')}).',
      );
    }

    if (historicalIncomes.length >= 2 && histMean > 0) {
      final cv = histStdDev / histMean;
      final bool incompleteCurrent =
          isPartialMonth && actualCurrentIncome < histMean * 0.85;

      if (cv <= 0.15) {
        final refIncome = incompleteCurrent
            ? histMean
            : (actualCurrentIncome > 0
                ? (actualCurrentIncome + histMean) / 2
                : histMean);
        return ReferenceIncomeAssessment(
          mode: IncomeStabilityMode.stable,
          referenceIncome: _roundMoney(refIncome),
          actualCurrentMonthIncome: actualCurrentIncome,
          historicalMeanIncome: histMean,
          historicalStdDevIncome: histStdDev,
          currentTotalBudget: currentTotalBudget,
          isIncomeLikelyIncompleteInCurrentMonth: incompleteCurrent,
          explanation: incompleteCurrent
              ? 'Thu nhập các tháng trước ổn định (~${AppFormatters.compactCurrency(histMean, unit: 'đ')}/tháng). Tháng này chưa ghi nhận đủ kỳ lương nên tạm tham chiếu mức ổn định lịch sử.'
              : 'Thu nhập duy trì ổn định qua các tháng (~${AppFormatters.compactCurrency(refIncome, unit: 'đ')}/tháng).',
        );
      } else {
        final minHist = historicalIncomes.reduce(math.min);
        final conservativeIncome =
            math.max(minHist, histMean - 0.5 * histStdDev);
        return ReferenceIncomeAssessment(
          mode: IncomeStabilityMode.variable,
          referenceIncome: _roundMoney(conservativeIncome),
          actualCurrentMonthIncome: actualCurrentIncome,
          historicalMeanIncome: histMean,
          historicalStdDevIncome: histStdDev,
          currentTotalBudget: currentTotalBudget,
          isIncomeLikelyIncompleteInCurrentMonth: incompleteCurrent,
          explanation:
              'Thu nhập có độ biến động giữa các tháng (CV ${(cv * 100).round()}%). Hệ thống dùng mức thu nhập thận trọng (${AppFormatters.compactCurrency(conservativeIncome, unit: 'đ')}) để lập kế hoạch an toàn.',
        );
      }
    }

    if (historicalIncomes.length == 1) {
      final singleHist = historicalIncomes.first;
      final bool incompleteCurrent =
          isPartialMonth && actualCurrentIncome < singleHist * 0.85;
      final refIncome = incompleteCurrent
          ? singleHist
          : (actualCurrentIncome > 0 ? actualCurrentIncome : singleHist);
      return ReferenceIncomeAssessment(
        mode: IncomeStabilityMode.singleMonth,
        referenceIncome: _roundMoney(refIncome),
        actualCurrentMonthIncome: actualCurrentIncome,
        historicalMeanIncome: singleHist,
        historicalStdDevIncome: 0,
        currentTotalBudget: currentTotalBudget,
        isIncomeLikelyIncompleteInCurrentMonth: incompleteCurrent,
        explanation:
            'Tham chiếu từ dữ liệu thu nhập 1 tháng (${AppFormatters.compactCurrency(refIncome, unit: 'đ')}). Bạn có thể nhập Thu nhập dự kiến để điều chỉnh chính xác hơn.',
      );
    }

    if (actualCurrentIncome > 0) {
      return ReferenceIncomeAssessment(
        mode: IncomeStabilityMode.singleMonth,
        referenceIncome: _roundMoney(actualCurrentIncome),
        actualCurrentMonthIncome: actualCurrentIncome,
        historicalMeanIncome: 0,
        historicalStdDevIncome: 0,
        currentTotalBudget: currentTotalBudget,
        isIncomeLikelyIncompleteInCurrentMonth: isPartialMonth,
        explanation: isPartialMonth
            ? 'Tính theo thu nhập đã ghi nhận từ đầu tháng (${AppFormatters.compactCurrency(actualCurrentIncome, unit: 'đ')}). Nếu cuối tháng còn khoản thu khác, bạn có thể cập nhật Thu nhập dự kiến.'
            : 'Tham chiếu theo thu nhập thực tế trong tháng (${AppFormatters.compactCurrency(actualCurrentIncome, unit: 'đ')}).',
      );
    }

    return ReferenceIncomeAssessment(
      mode: IncomeStabilityMode.noIncomeBasis,
      referenceIncome: 0,
      actualCurrentMonthIncome: 0,
      historicalMeanIncome: 0,
      historicalStdDevIncome: 0,
      currentTotalBudget: currentTotalBudget,
      isIncomeLikelyIncompleteInCurrentMonth: true,
      explanation:
          'Chưa có dữ liệu thu nhập. Hệ thống không tự suy đoán thu nhập từ ngân sách chi tiêu; chỉ phân tích cơ cấu chi tiêu và tiến độ ngân sách hiện tại.',
    );
  }

  /// ============================================================
  /// 9. THUẬT TOÁN LẬP KẾ HOẠCH TÀI CHÍNH THÁNG BẬC THANG (SEQUENTIAL ALLOCATION)
  /// ============================================================
  MonthlyFinancialPlan buildSequentialMonthlyPlan({
    required String userId,
    required String sourceMonth,
    required String targetMonth,
    required List<AppTransaction> sourceMonthTx,
    required List<List<AppTransaction>> historicalMonthsTx,
    required List<Category> categories,
    required List<Budget> existingTargetBudgets,
    required List<SavingGoal> savingGoals,
    List<Wallet> wallets = const [],
    double? declaredExpectedIncome,
    double? defaultSavingRateWhenNoGoal,
    DateTime? referenceToday,
    FinancialHeuristicsConfig? heuristicsOverride,
  }) {
    final h = heuristicsOverride ?? effectiveHeuristics;
    final effectiveDefaultSavingRate =
        defaultSavingRateWhenNoGoal ?? h.defaultSavingRateNoGoal;
    final double floorRatio = h.flexibleSpendFloorRatio;
    final now = referenceToday ?? DateTime.now();
    final sufficiency = assessDataSufficiency(
      currentMonthTx: sourceMonthTx,
      historicalMonthsTx: historicalMonthsTx,
      currentBudgets: existingTargetBudgets,
      wallets: wallets,
      savingGoals: savingGoals,
      referenceToday: now,
    );

    final incomeAssessment = determineReferenceIncome(
      currentMonthTx: sourceMonthTx,
      historicalMonthsTx: historicalMonthsTx,
      currentBudgets: existingTargetBudgets,
      declaredExpectedIncome: declaredExpectedIncome,
      isPartialMonth: sufficiency.isPartialMonth,
    );

    final double refIncome = incomeAssessment.referenceIncome;
    final bool hasIncome = incomeAssessment.hasIncomeBasis;

    final Map<String, Category> catMap = {
      for (final c in categories) c.categoryId: c,
    };
    final Map<String, double> existingBudgetMap = {
      for (final b in existingTargetBudgets) b.categoryId: b.limit,
    };

    final Map<String, List<AppTransaction>> expenseTxByCat = {};
    for (final tx in sourceMonthTx.where((t) => t.type == 'expense')) {
      expenseTxByCat.putIfAbsent(tx.categoryId, () => []).add(tx);
    }

    final Map<String, double> histMedianByCat =
        _computeHistoricalMediansByCategory(
      historicalMonthsTx: historicalMonthsTx,
    );

    final Set<String> relevantCategoryIds = {
      ...expenseTxByCat.keys,
      ...existingBudgetMap.keys,
    };

    final List<_CategoryWorkingStat> essentialStats = [];
    final List<_CategoryWorkingStat> flexibleStats = [];

    for (final catId in relevantCategoryIds) {
      final cat = catMap[catId] ??
          Category(
            categoryId: catId,
            userId: userId,
            name: 'Danh mục khác',
            type: 'expense',
            icon: 'category',
            color: 0xFF9E9E9E,
          );
      final txList = expenseTxByCat[catId] ?? const [];
      final rawSpent = txList.fold<double>(0, (s, t) => s + t.amount);
      final regularSpent = _extractRegularCategorySpend(txList);
      final histMed = histMedianByCat[catId] ?? 0.0;
      final existingB = existingBudgetMap[catId];

      final stat = _CategoryWorkingStat(
        category: cat,
        sourceSpent: rawSpent,
        regularSpent: regularSpent,
        historicalMedian: histMed,
        existingBudget: existingB,
      );

      if (cat.isEssential) {
        essentialStats.add(stat);
      } else {
        flexibleStats.add(stat);
      }
    }

    final Map<String, double> essentialLimits = {};
    final Map<String, String> essentialBasis = {};
    double totalEssentialPlanned = 0;

    for (final s in essentialStats) {
      double limit;
      String basis;
      if (s.historicalMedian > 0 &&
          s.sourceSpent > s.historicalMedian * 1.25 &&
          s.regularSpent < s.sourceSpent) {
        limit = _roundMoney(math.max(s.regularSpent, s.historicalMedian));
        basis =
            'Danh mục thiết yếu có khoản phát sinh đột biến trong kỳ phân tích; đưa về mức chi thiết yếu ổn định (${AppFormatters.compactCurrency(limit, unit: 'đ')}).';
      } else if (s.sourceSpent > 0) {
        limit = _roundMoney(s.sourceSpent);
        basis =
            'Giữ nguyên mức chi phí thiết yếu (${AppFormatters.compactCurrency(limit, unit: 'đ')}) — không cắt giảm chi phí thiết yếu.';
      } else if (s.existingBudget != null && s.existingBudget! > 0) {
        limit = _roundMoney(s.existingBudget!);
        basis =
            'Duy trì theo hạn mức ngân sách thiết yếu đã đặt (${AppFormatters.compactCurrency(limit, unit: 'đ')}).';
      } else {
        limit = _roundMoney(s.historicalMedian);
        basis = 'Tham chiếu theo mức trung vị lịch sử của danh mục thiết yếu.';
      }
      essentialLimits[s.category.categoryId] = limit;
      essentialBasis[s.category.categoryId] = basis;
      totalEssentialPlanned += limit;
    }

    final double totalGoalRequired = savingGoals.fold<double>(
      0,
      (sum, g) => sum + g.monthlyRequired,
    );
    final double remainingGoalTotal = savingGoals.fold<double>(
      0,
      (sum, g) => sum + math.max(0.0, g.targetAmount - g.savedAmount),
    );
    final double desiredSaving = hasIncome
        ? (totalGoalRequired > 0
            ? totalGoalRequired
            : _roundMoney(
                refIncome * effectiveDefaultSavingRate.clamp(0.0, 0.5)))
        : totalGoalRequired;

    if (!hasIncome) {
      final List<PlannedCategoryAllocation> noIncomeAllocations = [];
      double flexSum = 0;
      for (final s in essentialStats) {
        final rec = essentialLimits[s.category.categoryId] ?? s.sourceSpent;
        noIncomeAllocations.add(
          PlannedCategoryAllocation(
            categoryId: s.category.categoryId,
            categoryName: s.category.name,
            isEssential: true,
            sourceMonthSpent: s.sourceSpent,
            regularBaselineSpent: s.regularSpent,
            historicalMedian: s.historicalMedian,
            existingBudget: s.existingBudget,
            floorLimit: rec,
            recommendedLimit: rec,
            deltaFromCurrent: rec - s.sourceSpent,
            calculationBasis: essentialBasis[s.category.categoryId] ?? '',
            aiActionTip:
                'Duy trì theo dõi hóa đơn/chi phí thiết yếu định kỳ trong tháng.',
          ),
        );
      }
      for (final s in flexibleStats) {
        final anchor = (s.existingBudget != null && s.existingBudget! > 0)
            ? s.existingBudget!
            : (s.historicalMedian > 0 ? s.historicalMedian : s.regularSpent);
        final rec = _roundMoney(anchor > 0 ? anchor : s.sourceSpent);
        flexSum += rec;
        noIncomeAllocations.add(
          PlannedCategoryAllocation(
            categoryId: s.category.categoryId,
            categoryName: s.category.name,
            isEssential: false,
            sourceMonthSpent: s.sourceSpent,
            regularBaselineSpent: s.regularSpent,
            historicalMedian: s.historicalMedian,
            existingBudget: s.existingBudget,
            floorLimit: _roundMoney(rec * floorRatio),
            recommendedLimit: rec,
            deltaFromCurrent: rec - s.sourceSpent,
            calculationBasis: s.existingBudget != null
                ? 'Chưa có dữ liệu thu nhập; đối chiếu theo hạn mức ngân sách hiện tại (${AppFormatters.compactCurrency(s.existingBudget!, unit: 'đ')}).'
                : 'Chưa có dữ liệu thu nhập; giữ ở mức chi tiêu thường xuyên.',
            aiActionTip:
                'Hãy bổ sung giao dịch Thu nhập hoặc nhập Thu nhập dự kiến để hệ thống tính toán mục tiêu tiết kiệm chính xác.',
          ),
        );
      }

      final snapshot = PlanSnapshotData(
        referenceIncome: 0,
        essentialExpenseTotal: totalEssentialPlanned,
        flexibleExpenseTotal: flexSum,
        targetSavingAmount: 0,
        allocations: noIncomeAllocations,
        capturedAt: now,
      );

      return MonthlyFinancialPlan(
        planId: '${userId}_${targetMonth.replaceAll('/', '-')}',
        userId: userId,
        sourceMonth: sourceMonth,
        targetMonth: targetMonth,
        status: PlanLifecycleStatus.draft,
        dataTierUsed: sufficiency.tier,
        incomeMode: IncomeStabilityMode.noIncomeBasis,
        referenceIncome: 0,
        essentialExpenseCap: totalEssentialPlanned,
        flexibleExpenseCap: flexSum,
        targetSavingAmount: 0,
        desiredGoalSavingAmount: desiredSaving,
        isSavingGoalFeasible: desiredSaving == 0,
        infeasibleSavingGap: desiredSaving,
        isEssentialDeficit: false,
        currentAllocations: noIncomeAllocations,
        originalSnapshot: snapshot,
        aiExecutiveSummary:
            'Chưa có dữ liệu thu nhập nên hệ thống chỉ thiết lập khung kiểm soát chi tiêu theo ngân sách và lịch sử hiện có. Vui lòng nhập Thu nhập dự kiến để tính kế hoạch tiết kiệm.',
        behavioralInsights: [
          incomeAssessment.explanation,
          sufficiency.limitationNote,
        ],
        createdAt: now,
        updatedAt: now,
      );
    }

    if (totalEssentialPlanned >= refIncome) {
      final List<PlannedCategoryAllocation> deficitAllocations = [];
      for (final s in essentialStats) {
        final rec = essentialLimits[s.category.categoryId] ?? s.sourceSpent;
        deficitAllocations.add(
          PlannedCategoryAllocation(
            categoryId: s.category.categoryId,
            categoryName: s.category.name,
            isEssential: true,
            sourceMonthSpent: s.sourceSpent,
            regularBaselineSpent: s.regularSpent,
            historicalMedian: s.historicalMedian,
            existingBudget: s.existingBudget,
            floorLimit: rec,
            recommendedLimit: rec,
            deltaFromCurrent: rec - s.sourceSpent,
            calculationBasis:
                'Chi phí thiết yếu được giữ nguyên (${AppFormatters.compactCurrency(rec, unit: 'đ')}), nhưng tổng nhóm thiết yếu đã vượt thu nhập tham chiếu.',
            aiActionTip:
                'Kiểm tra xem danh mục này có khoản chi linh hoạt nào bị gộp nhầm vào nhóm Thiết yếu hay không.',
          ),
        );
      }
      for (final s in flexibleStats) {
        deficitAllocations.add(
          PlannedCategoryAllocation(
            categoryId: s.category.categoryId,
            categoryName: s.category.name,
            isEssential: false,
            sourceMonthSpent: s.sourceSpent,
            regularBaselineSpent: s.regularSpent,
            historicalMedian: s.historicalMedian,
            existingBudget: s.existingBudget,
            floorLimit: 0,
            recommendedLimit: 0,
            deltaFromCurrent: -s.sourceSpent,
            calculationBasis:
                'Thu nhập tham chiếu không đủ bù đắp chi phí thiết yếu nên không còn dư địa cho chi tiêu linh hoạt.',
            aiActionTip:
                'Tạm dừng tối đa các khoản chi không bắt buộc cho đến khi cân đối lại nguồn thu hoặc cơ cấu chi thiết yếu.',
          ),
        );
      }

      final snapshot = PlanSnapshotData(
        referenceIncome: refIncome,
        essentialExpenseTotal: totalEssentialPlanned,
        flexibleExpenseTotal: 0,
        targetSavingAmount: 0,
        allocations: deficitAllocations,
        capturedAt: now,
      );

      return MonthlyFinancialPlan(
        planId: '${userId}_${targetMonth.replaceAll('/', '-')}',
        userId: userId,
        sourceMonth: sourceMonth,
        targetMonth: targetMonth,
        status: PlanLifecycleStatus.draft,
        dataTierUsed: sufficiency.tier,
        incomeMode: incomeAssessment.mode,
        referenceIncome: refIncome,
        essentialExpenseCap: totalEssentialPlanned,
        flexibleExpenseCap: 0,
        targetSavingAmount: 0,
        desiredGoalSavingAmount: desiredSaving,
        isSavingGoalFeasible: false,
        infeasibleSavingGap: desiredSaving,
        isEssentialDeficit: true,
        currentAllocations: deficitAllocations,
        originalSnapshot: snapshot,
        aiExecutiveSummary:
            'Cảnh báo: Tổng chi phí thiết yếu (${AppFormatters.compactCurrency(totalEssentialPlanned, unit: 'đ')}) đang vượt quá thu nhập tham chiếu (${AppFormatters.compactCurrency(refIncome, unit: 'đ')}). Hệ thống không tự ý cắt giảm chi phí thiết yếu; bạn cần rà soát lại phân loại Thiết yếu/Linh hoạt hoặc cập nhật thu nhập.',
        behavioralInsights: [
          'Chi phí thiết yếu vượt thu nhập ${AppFormatters.compactCurrency(totalEssentialPlanned - refIncome, unit: 'đ')}.',
          incomeAssessment.explanation,
        ],
        createdAt: now,
        updatedAt: now,
      );
    }

    final double availableAfterEssential = refIncome - totalEssentialPlanned;

    final Map<String, double> flexCurrentRef = {};
    final Map<String, double> flexPrimaryExcess = {};
    final Map<String, double> flexNormalBase = {};
    final Map<String, double> flexFloor = {};

    double totalFlexCurrent = 0;
    double totalFlexFloor = 0;
    double totalPrimaryExcess = 0;

    for (final s in flexibleStats) {
      final catId = s.category.categoryId;
      final currentRef = s.sourceSpent > 0
          ? s.sourceSpent
          : (s.existingBudget ?? s.historicalMedian);

      final double overBudget = (s.existingBudget != null &&
              s.existingBudget! > 0 &&
              currentRef > s.existingBudget!)
          ? (currentRef - s.existingBudget!)
          : 0.0;
      final double overHist =
          (s.historicalMedian > 0 && currentRef > s.historicalMedian)
              ? (currentRef - s.historicalMedian)
              : 0.0;

      final double primaryExcess = math.max(overBudget, overHist);
      final double normalBase = math.max(0.0, currentRef - primaryExcess);
      final double floor = _roundMoney(normalBase * floorRatio);

      flexCurrentRef[catId] = currentRef;
      flexPrimaryExcess[catId] = primaryExcess;
      flexNormalBase[catId] = normalBase;
      flexFloor[catId] = floor;

      totalFlexCurrent += currentRef;
      totalFlexFloor += floor;
      totalPrimaryExcess += primaryExcess;
    }

    if (totalFlexFloor > availableAfterEssential && totalFlexFloor > 0) {
      final scale = availableAfterEssential / totalFlexFloor;
      totalFlexFloor = 0;
      for (final s in flexibleStats) {
        final catId = s.category.categoryId;
        final scaledFloor = _roundMoney((flexFloor[catId] ?? 0) * scale);
        flexFloor[catId] = scaledFloor;
        totalFlexFloor += scaledFloor;
      }
    }

    final double maxFlexibleAllowedForDesiredSaving =
        math.max(0.0, availableAfterEssential - desiredSaving);
    final double neededCutFromFlex =
        math.max(0.0, totalFlexCurrent - maxFlexibleAllowedForDesiredSaving);
    final double maxPossibleCutFromFlex =
        math.max(0.0, totalFlexCurrent - totalFlexFloor);

    final Map<String, double> flexRecommended = {};
    final Map<String, String> flexBasis = {};

    if (flexibleStats.isEmpty || neededCutFromFlex > maxPossibleCutFromFlex) {
      for (final s in flexibleStats) {
        final catId = s.category.categoryId;
        final floorVal = flexFloor[catId] ?? 0.0;
        flexRecommended[catId] = floorVal;
        flexBasis[catId] =
            'Đã tối ưu tối đa về ngưỡng sàn khả thi trong tháng (${AppFormatters.compactCurrency(floorVal, unit: 'đ')}) để ưu tiên dòng tiền cho mục tiêu tiết kiệm.';
      }
    } else if (neededCutFromFlex <= 0) {
      final double capRatio = totalFlexCurrent > availableAfterEssential &&
              totalFlexCurrent > 0
          ? (availableAfterEssential / totalFlexCurrent)
          : 1.0;
      for (final s in flexibleStats) {
        final catId = s.category.categoryId;
        final cur = flexCurrentRef[catId] ?? 0.0;
        final rec = _roundMoney(cur * capRatio);
        flexRecommended[catId] = rec;
        flexBasis[catId] =
            'Chi tiêu đang nằm trong giới hạn cân đối với thu nhập và mục tiêu tiết kiệm.';
      }
    } else {
      if (neededCutFromFlex <= totalPrimaryExcess && totalPrimaryExcess > 0) {
        for (final s in flexibleStats) {
          final catId = s.category.categoryId;
          final cur = flexCurrentRef[catId] ?? 0.0;
          final excess = flexPrimaryExcess[catId] ?? 0.0;
          final cut = neededCutFromFlex * (excess / totalPrimaryExcess);
          final rec = _roundMoney(math.max(flexFloor[catId] ?? 0.0, cur - cut));
          flexRecommended[catId] = rec;
          flexBasis[catId] = excess > 0
              ? 'Điều chỉnh giảm phần chi vượt ngân sách/trung vị lịch sử (${AppFormatters.compactCurrency(cur - rec, unit: 'đ')}) để đạt mục tiêu tiết kiệm.'
              : 'Giữ nguyên mức chi tiêu ổn định.';
        }
      } else {
        final double remainingToCut =
            math.max(0.0, neededCutFromFlex - totalPrimaryExcess);
        final double totalPhase2Capacity =
            math.max(1.0, maxPossibleCutFromFlex - totalPrimaryExcess);

        for (final s in flexibleStats) {
          final catId = s.category.categoryId;
          final normal = flexNormalBase[catId] ?? 0.0;
          final floor = flexFloor[catId] ?? 0.0;
          final phase2Room = math.max(0.0, normal - floor);
          final phase2Cut =
              remainingToCut * (phase2Room / totalPhase2Capacity);
          final rec = _roundMoney(math.max(floor, normal - phase2Cut));
          flexRecommended[catId] = rec;
          final totalCut = (flexCurrentRef[catId] ?? 0.0) - rec;
          flexBasis[catId] = totalCut > 0
              ? 'Loại bỏ phần chi vượt ngưỡng và tinh giản thêm ${AppFormatters.compactCurrency(phase2Cut, unit: 'đ')} chi phí linh hoạt (tổng giảm ${AppFormatters.compactCurrency(totalCut, unit: 'đ')}).'
              : 'Duy trì trong hạn mức ổn định.';
        }
      }
    }

    double totalFlexiblePlanned = flexRecommended.values.fold<double>(
      0,
      (s, v) => s + v,
    );

    if (totalFlexiblePlanned > availableAfterEssential &&
        flexibleStats.isNotEmpty) {
      final diff = totalFlexiblePlanned - availableAfterEssential;
      final firstId = flexibleStats.first.category.categoryId;
      flexRecommended[firstId] =
          math.max(0.0, (flexRecommended[firstId] ?? 0.0) - diff);
      totalFlexiblePlanned = flexRecommended.values.fold<double>(
        0,
        (s, v) => s + v,
      );
    }

    final double maxAchievableSaving =
        math.max(0.0, availableAfterEssential - totalFlexiblePlanned);
    final double plannedSaving = math.min(
        desiredSaving > 0 ? desiredSaving : maxAchievableSaving,
        maxAchievableSaving);
    final bool isGoalFeasible = desiredSaving <= maxAchievableSaving + 1000.0;
    final double infeasibleGap =
        isGoalFeasible ? 0.0 : math.max(0.0, desiredSaving - plannedSaving);

    int? recommendedMonths;
    if (!isGoalFeasible && remainingGoalTotal > 0 && plannedSaving > 0) {
      recommendedMonths = (remainingGoalTotal / plannedSaving).ceil();
    }

    final List<PlannedCategoryAllocation> allocations = [];
    for (final s in essentialStats) {
      final catId = s.category.categoryId;
      final rec = essentialLimits[catId] ?? s.sourceSpent;
      allocations.add(
        PlannedCategoryAllocation(
          categoryId: catId,
          categoryName: s.category.name,
          isEssential: true,
          sourceMonthSpent: s.sourceSpent,
          regularBaselineSpent: s.regularSpent,
          historicalMedian: s.historicalMedian,
          existingBudget: s.existingBudget,
          floorLimit: rec,
          recommendedLimit: rec,
          deltaFromCurrent: rec - s.sourceSpent,
          calculationBasis: essentialBasis[catId] ?? '',
          aiActionTip:
              'Khoản chi thiết yếu được bảo toàn hạn mức; nên thanh toán đúng kỳ hạn để tránh phí phạt.',
        ),
      );
    }

    for (final s in flexibleStats) {
      final catId = s.category.categoryId;
      final rec = flexRecommended[catId] ?? 0.0;
      final floor = flexFloor[catId] ?? 0.0;
      allocations.add(
        PlannedCategoryAllocation(
          categoryId: catId,
          categoryName: s.category.name,
          isEssential: false,
          sourceMonthSpent: s.sourceSpent,
          regularBaselineSpent: s.regularSpent,
          historicalMedian: s.historicalMedian,
          existingBudget: s.existingBudget,
          floorLimit: floor,
          recommendedLimit: rec,
          deltaFromCurrent: rec - s.sourceSpent,
          calculationBasis: flexBasis[catId] ?? '',
          aiActionTip: rec < s.sourceSpent
              ? 'Chia hạn mức ${AppFormatters.compactCurrency(rec, unit: 'đ')} thành trần chi tiêu theo từng tuần (~${AppFormatters.compactCurrency(rec / 4, unit: 'đ')}/tuần).'
              : 'Duy trì thói quen chi tiêu hợp lý hiện tại.',
        ),
      );
    }

    final snapshot = PlanSnapshotData(
      referenceIncome: refIncome,
      essentialExpenseTotal: totalEssentialPlanned,
      flexibleExpenseTotal: totalFlexiblePlanned,
      targetSavingAmount: plannedSaving,
      allocations: allocations,
      capturedAt: now,
    );

    final String summaryText = isGoalFeasible
        ? 'Kế hoạch tháng $targetMonth cân đối trên thu nhập tham chiếu ${AppFormatters.compactCurrency(refIncome, unit: 'đ')}: bảo toàn ${AppFormatters.compactCurrency(totalEssentialPlanned, unit: 'đ')} chi phí thiết yếu, giới hạn ${AppFormatters.compactCurrency(totalFlexiblePlanned, unit: 'đ')} chi phí linh hoạt và dành ${AppFormatters.compactCurrency(plannedSaving, unit: 'đ')} cho tiết kiệm.'
        : 'Với thu nhập tham chiếu ${AppFormatters.compactCurrency(refIncome, unit: 'đ')} và chi phí thiết yếu ${AppFormatters.compactCurrency(totalEssentialPlanned, unit: 'đ')}, mức tiết kiệm khả thi tối đa là ${AppFormatters.compactCurrency(plannedSaving, unit: 'đ')}/tháng (thiếu ${AppFormatters.compactCurrency(infeasibleGap, unit: 'đ')}/tháng so với mục tiêu ${AppFormatters.compactCurrency(desiredSaving, unit: 'đ')}).${recommendedMonths != null ? ' Khuyến nghị giãn thời hạn mục tiêu sang $recommendedMonths tháng.' : ''}';

    return MonthlyFinancialPlan(
      planId: '${userId}_${targetMonth.replaceAll('/', '-')}',
      userId: userId,
      sourceMonth: sourceMonth,
      targetMonth: targetMonth,
      status: PlanLifecycleStatus.draft,
      dataTierUsed: sufficiency.tier,
      incomeMode: incomeAssessment.mode,
      referenceIncome: refIncome,
      essentialExpenseCap: totalEssentialPlanned,
      flexibleExpenseCap: totalFlexiblePlanned,
      targetSavingAmount: plannedSaving,
      desiredGoalSavingAmount: desiredSaving,
      isSavingGoalFeasible: isGoalFeasible,
      infeasibleSavingGap: infeasibleGap,
      recommendedGoalMonths: recommendedMonths,
      isEssentialDeficit: false,
      currentAllocations: allocations,
      originalSnapshot: snapshot,
      aiExecutiveSummary: summaryText,
      behavioralInsights: [
        incomeAssessment.explanation,
        sufficiency.limitationNote,
      ],
      createdAt: now,
      updatedAt: now,
    );
  }

  /// ============================================================
  /// 10. ĐÁNH GIÁ & THEO DÕI THỰC THI KẾ HOẠCH KÉP (KHÔNG TÍNH TRÙNG TIẾT KIỆM)
  /// ============================================================
  PlanExecutionTrackerResult evaluatePlanExecution({
    required MonthlyFinancialPlan plan,
    required List<AppTransaction> targetMonthTx,
    DateTime? referenceToday,
  }) {
    final now = referenceToday ?? DateTime.now();
    final parts = plan.targetMonth.split('/');
    final int m =
        parts.length == 2 ? (int.tryParse(parts[0]) ?? now.month) : now.month;
    final int y =
        parts.length == 2 ? (int.tryParse(parts[1]) ?? now.year) : now.year;
    final int totalDays = DateTime(y, m + 1, 0).day;

    double elapsedRatio = 1.0;
    if (now.year == y && now.month == m) {
      elapsedRatio = (now.day / totalDays).clamp(0.05, 1.0);
    } else if (DateTime(y, m, 1).isAfter(now)) {
      elapsedRatio = 0.0;
    }

    final Map<String, double> actualByCategory = _sumByCategory(targetMonthTx);
    final double actualTotalExpense = targetMonthTx
        .where((t) => t.type == 'expense')
        .fold<double>(0, (s, t) => s + t.amount);
    final double actualIncome = targetMonthTx
        .where((t) => t.type == 'income')
        .fold<double>(0, (s, t) => s + t.amount);

    final double goalDeposits = targetMonthTx
        .where((t) => t.type == 'goal_deposit')
        .fold<double>(0, (s, t) => s + t.amount);
    final double goalWithdrawals = targetMonthTx
        .where((t) => t.type == 'goal_withdraw')
        .fold<double>(0, (s, t) => s + t.amount);
    final double netGoalContributions =
        math.max(0.0, goalDeposits - goalWithdrawals);

    final List<CategoryAdherenceStatus> catStatuses = [];
    int onTrackCount = 0;
    int exceededCount = 0;
    double totalOverrun = 0;

    for (final alloc in plan.currentAllocations) {
      final spent = actualByCategory[alloc.categoryId] ?? 0.0;
      final limit = alloc.recommendedLimit;
      final remaining = limit - spent;
      final ratio = limit > 0 ? (spent / limit) : (spent > 0 ? 1.5 : 0.0);

      String status;
      if (spent > limit && limit >= 0) {
        status = 'exceeded';
        exceededCount++;
        totalOverrun += (spent - limit);
      } else if (elapsedRatio > 0 &&
          ratio > (elapsedRatio + 0.15) &&
          ratio >= 0.75) {
        status = 'pacing_fast';
      } else {
        status = 'on_track';
        onTrackCount++;
      }

      catStatuses.add(
        CategoryAdherenceStatus(
          categoryId: alloc.categoryId,
          categoryName: alloc.categoryName,
          isEssential: alloc.isEssential,
          plannedLimit: limit,
          actualSpent: spent,
          remainingAmount: remaining,
          usageRatio: ratio,
          status: status,
        ),
      );
    }

    final double plannedTotalExpense = plan.plannedTotalExpense;
    final double budgetUsageRatio = plannedTotalExpense > 0
        ? (actualTotalExpense / plannedTotalExpense)
        : 0.0;

    double budgetAdherenceScore = 100.0;
    if (catStatuses.isNotEmpty) {
      final categoryComplianceRate = onTrackCount / catStatuses.length;
      final overrunPenalty = plannedTotalExpense > 0
          ? ((totalOverrun / plannedTotalExpense) * 60).clamp(0.0, 60.0)
          : 0.0;
      budgetAdherenceScore =
          (categoryComplianceRate * 100.0 - overrunPenalty).clamp(0.0, 100.0);
    }

    final double totalNetCashflowSurplus = actualIncome - actualTotalExpense;
    final double unallocatedWalletSurplus =
        math.max(0.0, totalNetCashflowSurplus - netGoalContributions);

    final double effectiveMonthlySaved = actualIncome > 0
        ? math.max(netGoalContributions, math.max(0.0, totalNetCashflowSurplus))
        : netGoalContributions;

    final double savingTarget = plan.targetSavingAmount;
    final double savingExecutionRatio = savingTarget > 0
        ? (effectiveMonthlySaved / savingTarget).clamp(0.0, 2.0)
        : 1.0;

    final double savingAdherenceScore = savingTarget > 0
        ? ((effectiveMonthlySaved / savingTarget) * 100.0).clamp(0.0, 100.0)
        : 100.0;

    final double budgetWeight = effectiveHeuristics.planBudgetAdherenceWeight;
    final double savingWeight = effectiveHeuristics.planSavingAdherenceWeight;
    final double overallScore =
        (budgetWeight * budgetAdherenceScore + savingWeight * savingAdherenceScore)
            .clamp(0.0, 100.0);

    return PlanExecutionTrackerResult(
      targetMonth: plan.targetMonth,
      elapsedMonthRatio: elapsedRatio,
      plannedTotalExpense: plannedTotalExpense,
      actualTotalExpense: actualTotalExpense,
      budgetUsageRatio: budgetUsageRatio,
      budgetAdherenceScore: budgetAdherenceScore,
      onTrackCategoryCount: onTrackCount,
      exceededCategoryCount: exceededCount,
      categoryStatuses: catStatuses,
      targetSavingAmount: savingTarget,
      actualIncomeInMonth: actualIncome,
      netGoalContributions: netGoalContributions,
      totalNetCashflowSurplus: totalNetCashflowSurplus,
      unallocatedWalletSurplus: unallocatedWalletSurplus,
      effectiveMonthlySaved: effectiveMonthlySaved,
      savingExecutionRatio: savingExecutionRatio,
      savingAdherenceScore: savingAdherenceScore,
      overallAdherenceScore: overallScore,
      needsRebalance: exceededCount > 0 || totalOverrun > 0,
      totalOverrunAmount: totalOverrun,
    );
  }

  Map<String, double> _computeHistoricalMediansByCategory({
    required List<List<AppTransaction>> historicalMonthsTx,
  }) {
    final Map<String, List<double>> historyByCat = {};
    for (final monthTx in historicalMonthsTx) {
      if (monthTx.isEmpty) continue;
      final sumMap = _sumByCategory(monthTx);
      for (final entry in sumMap.entries) {
        if (entry.value > 0) {
          historyByCat.putIfAbsent(entry.key, () => []).add(entry.value);
        }
      }
    }
    final Map<String, double> medians = {};
    for (final entry in historyByCat.entries) {
      final list = List<double>.from(entry.value)..sort();
      final mid = list.length ~/ 2;
      if (list.length.isOdd) {
        medians[entry.key] = list[mid];
      } else {
        medians[entry.key] = (list[mid - 1] + list[mid]) / 2.0;
      }
    }
    return medians;
  }

  double _extractRegularCategorySpend(List<AppTransaction> txList) {
    if (txList.isEmpty) return 0.0;
    final total = txList.fold<double>(0, (s, t) => s + t.amount);
    if (txList.length < 4) return total;

    final mean = total / txList.length;
    final variance = txList
            .map((t) => math.pow(t.amount - mean, 2))
            .reduce((a, b) => a + b) /
        txList.length;
    final stdDev = math.sqrt(variance);
    if (stdDev <= 0) return total;

    final threshold = mean + 2.0 * stdDev;
    double regularSum = 0;
    for (final tx in txList) {
      if (tx.amount > threshold && tx.amount > mean * 2.5) {
        regularSum += mean;
      } else {
        regularSum += tx.amount;
      }
    }
    return regularSum;
  }

  double _roundMoney(double value) {
    if (value <= 0) return 0.0;
    if (value < 10000) return value.roundToDouble();
    return ((value / 10000).round() * 10000).toDouble();
  }

  /// Tính tần suất chi tiêu theo tuần (heatmap).
  /// Trả về Map<TênDanhMục, List<int>> — mỗi phần tử trong List là mức độ đậm
  /// nhạt (0-4) của chi tiêu vào đúng thứ đó trong tuần (index 0=Thứ 2 ... 6=CN).
  Map<String, List<int>> computeWeeklyHeatmap(
    List<AppTransaction> transactions,
    List<Category> categories, {
    int topN = 4,
  }) {
    final Map<String, List<double>> sums = {}; // tên danh mục -> tổng theo 7 thứ
    for (final tx in transactions.where((t) => t.type == 'expense')) {
      final cat = categories.firstWhere(
        (c) => c.categoryId == tx.categoryId,
        orElse: () => Category(
          categoryId: tx.categoryId,
          userId: '',
          name: 'Khác',
          type: 'expense',
          icon: 'category',
          color: 0xFF9E9E9E,
        ),
      );
      final weekday = tx.date.weekday - 1; // 0 = Thứ 2
      sums.putIfAbsent(cat.name, () => List.filled(7, 0));
      sums[cat.name]![weekday] += tx.amount;
    }
    // Chỉ giữ topN danh mục theo tổng chi tiêu, chuẩn hóa mỗi ô về thang 0-4
    final sortedEntries = sums.entries.toList()
      ..sort((a, b) => b.value
          .reduce((x, y) => x + y)
          .compareTo(a.value.reduce((x, y) => x + y)));
    final top = sortedEntries.take(topN);

    final result = <String, List<int>>{};
    for (final entry in top) {
      final maxVal = entry.value.reduce((a, b) => a > b ? a : b);
      result[entry.key] = entry.value
          .map((v) => maxVal == 0 ? 0 : (v / maxVal * 4).round().clamp(0, 4))
          .toList();
    }
    return result;
  }
}

class _CategoryWorkingStat {
  final Category category;
  final double sourceSpent;
  final double regularSpent;
  final double historicalMedian;
  final double? existingBudget;

  const _CategoryWorkingStat({
    required this.category,
    required this.sourceSpent,
    required this.regularSpent,
    required this.historicalMedian,
    this.existingBudget,
  });
}
