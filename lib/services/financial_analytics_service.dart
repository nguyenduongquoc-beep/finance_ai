import 'dart:math' as math;
import '../models/transaction_model.dart';
import '../models/category_model.dart';
import '../models/financial_issue.dart';
import '../models/financial_forecast_result.dart';
import '../models/saving_goal_model.dart';
import '../utils/formatters.dart';

/// ============================================================
/// FINANCIAL ANALYTICS SERVICE
/// Tính toán chỉ số tài chính & phát hiện vấn đề bằng NGƯỠNG CỤ THỂ.
/// Toàn bộ hàm trong file này là DART THUẦN — không gọi Gemini/AI.
/// Đây là tầng phân tích độc lập, phục vụ đúng yêu cầu hội đồng:
/// "hệ thống phải tự tính toán, không giao phó hết cho AI".
/// ============================================================
class FinancialAnalyticsService {
  // Ngưỡng phát hiện vấn đề — có thể tinh chỉnh, để hằng số cho dễ đọc/sửa
  static const double kCategorySpikeThreshold = 0.30; // tăng >30% so tháng trước
  static const double kCategoryShareThreshold = 0.25; // 1 danh mục chiếm >25% thu nhập
  static const double kLowSavingRateThreshold = 0.20; // tỷ lệ tiết kiệm <20%

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
  }) {
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
        if (percentChange > kCategorySpikeThreshold) {
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
          final threshold = lastAmount * (1 + kCategorySpikeThreshold);
          final diff = currentAmount - lastAmount;

          issues.add(FinancialIssue(
            title:
                '$catName tăng ${(percentChange * 100).round()}% so với tháng trước',
            description:
                'Tháng trước: ${lastAmount.round()}đ → Tháng này: ${currentAmount.round()}đ',
            severity: percentChange > 0.5
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
        if (share > kCategoryShareThreshold) {
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
          issues.add(FinancialIssue(
            title:
                '$catName chiếm ${(share * 100).round()}% thu nhập tháng này',
            description:
                'Vượt ngưỡng khuyến nghị ${(kCategoryShareThreshold * 100).round()}%',
            severity:
                share > 0.4 ? IssueSeverity.critical : IssueSeverity.warning,
            category: IssueCategory.budgetShare,
            confidenceScore:
                _calculateConfidence(share, kCategoryShareThreshold),
            categoryName: catName,
            currentValue: share,
            thresholdValue: kCategoryShareThreshold,
            rootCause:
                'Một danh mục duy nhất ($catName) chiếm tới ${(share * 100).round()}% tổng thu nhập.',
            impact:
                'Gây mất cân bằng cơ cấu chi tiêu, làm giảm khả năng ứng phó khi có biến cố tài chính.',
            recommendation:
                'Cân đối tinh giản các khoản chi chưa cấp thiết trong nhóm $catName về dưới 25% thu nhập.',
          ));
        }
      });
    }

    // 3. Phát hiện tỷ lệ tiết kiệm thấp
    if (effectiveIncome > 0) {
      final savingRate = (effectiveIncome - totalExpense) / effectiveIncome;
      if (savingRate < kLowSavingRateThreshold) {
        issues.add(FinancialIssue(
          title: 'Tỷ lệ tiết kiệm chỉ đạt ${(savingRate * 100).round()}%',
          description:
              'Thấp hơn ngưỡng khuyến nghị ${(kLowSavingRateThreshold * 100).round()}%',
          severity:
              savingRate < 0.05 ? IssueSeverity.critical : IssueSeverity.warning,
          category: IssueCategory.lowSaving,
          confidenceScore:
              _calculateConfidence(savingRate, kLowSavingRateThreshold),
          currentValue: savingRate,
          thresholdValue: kLowSavingRateThreshold,
          rootCause:
              'Chi tiêu đã chiếm ${(totalExpense / effectiveIncome * 100).round()}% tổng thu nhập trong kỳ.',
          impact:
              'Khả năng tích lũy tài sản và tiến độ các mục tiêu tiết kiệm bị đình trệ.',
          recommendation:
              'Cắt giảm bớt các khoản chi linh hoạt (mua sắm, giải trí) để nâng tỷ lệ tích lũy lên tối thiểu 20%.',
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

    // 5. Phát hiện thu nhập sụt giảm mạnh so với tháng trước (>20%)
    final lastMonthIncome = lastMonthTx
        .where((t) => t.type == 'income')
        .fold<double>(0, (a, t) => a + t.amount);
    if (lastMonthIncome > 0 && totalIncome > 0) {
      final dropRate = (lastMonthIncome - totalIncome) / lastMonthIncome;
      if (dropRate > 0.20) {
        issues.add(FinancialIssue(
          title: 'Thu nhập giảm ${(dropRate * 100).round()}% so với tháng trước',
          description:
              'Tháng trước: ${AppFormatters.compactCurrency(lastMonthIncome, unit: 'đ')} → Tháng này: ${AppFormatters.compactCurrency(totalIncome, unit: 'đ')}',
          severity:
              dropRate > 0.40 ? IssueSeverity.critical : IssueSeverity.warning,
          category: IssueCategory.incomeDrop,
          confidenceScore: 90.0,
          currentValue: dropRate,
          thresholdValue: 0.20,
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
    if (isPositive) {
      summaryComment =
          'Bạn có thu nhập ${AppFormatters.compactCurrency(currentMonthIncome, unit: 'đ')} '
          'và chi tiêu ${AppFormatters.compactCurrency(currentMonthExpense, unit: 'đ')}, '
          'còn lại ${AppFormatters.compactCurrency(netCashFlow, unit: 'đ')} '
          '(${savingsRate.round()}% thu nhập). Dòng tiền tích cực, khả năng tiết kiệm ${savingsRate >= 20 ? 'rất tốt' : 'ổn định'}.';
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
    if (cashFlow.isPositive && cashFlow.savingsRate >= 20) {
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

  /// Tính Điểm sức khỏe tài chính (0-100).
  /// Công thức: điểm khởi đầu 100, trừ điểm theo mức độ nghiêm trọng của
  /// từng vấn đề đã phát hiện (critical trừ nhiều hơn warning), tối thiểu 0.
  int calculateHealthScore(List<FinancialIssue> issues) {
    double score = 100;
    for (final issue in issues) {
      score -= issue.severity == IssueSeverity.critical ? 20 : 10;
    }
    return score.clamp(0, 100).round();
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
