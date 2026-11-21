// ============================================================
// MONTHLY FINANCIAL PLAN & CLOSED-LOOP AI PLANNING MODELS
// Firestore collection: monthly_plans/{planId}
// ============================================================

import 'package:flutter/widgets.dart';
import '../l10n/app_localizations.dart';

/// 5 cấp độ đủ dữ liệu (Data Sufficiency Tiers)
enum DataSufficiencyTier {
  /// Tier 0: Chưa có bất kỳ dữ liệu tài chính hữu ích nào (transactions, budgets, wallets, savingGoals, monthly_plans)
  empty,

  /// Tier 1: Dữ liệu sơ bộ (< 5 giao dịch chi tiêu HOẶC < 3 ngày có giao dịch trong tháng)
  preliminary,

  /// Tier 2: Đủ dữ liệu phân tích trong tháng (>= 5 giao dịch chi tiêu trên >= 3 ngày), nhưng chưa có tháng lịch sử hợp lệ
  currentMonthAnalysis,

  /// Tier 3: Đủ dữ liệu so sánh 1-1 với tháng liền trước (MoM Comparison: qualifiedHistoryMonths == 1)
  monthOverMonthComparison,

  /// Tier 4: Đủ dữ liệu nhận diện xu hướng đa tháng (Multi-Month Trend: qualifiedHistoryMonths >= 2)
  multiMonthTrend,
}

/// Đánh giá chi tiết về độ đủ dữ liệu
class DataSufficiencyAssessment {
  final DataSufficiencyTier tier;
  final int expenseTxCount;
  final int totalTxCount;
  final int activeDaysCount;
  final int expenseCategoriesCovered;
  final int qualifiedHistoryMonths;
  final bool isPartialMonth;
  final int daysElapsedInMonth;
  final int totalDaysInMonth;
  final bool hasIncomeData;
  final bool hasBudgetData;
  final bool hasWalletBalance;
  final bool hasSavingGoals;
  final bool hasActivePlan;
  final String limitationNote;

  const DataSufficiencyAssessment({
    required this.tier,
    required this.expenseTxCount,
    required this.totalTxCount,
    required this.activeDaysCount,
    required this.expenseCategoriesCovered,
    required this.qualifiedHistoryMonths,
    required this.isPartialMonth,
    required this.daysElapsedInMonth,
    required this.totalDaysInMonth,
    required this.hasIncomeData,
    required this.hasBudgetData,
    required this.hasWalletBalance,
    required this.hasSavingGoals,
    required this.hasActivePlan,
    required this.limitationNote,
  });

  bool get canForecastEndOfMonth =>
      tier == DataSufficiencyTier.currentMonthAnalysis ||
      tier == DataSufficiencyTier.monthOverMonthComparison ||
      tier == DataSufficiencyTier.multiMonthTrend;

  bool get canCompareMonthOverMonth =>
      tier == DataSufficiencyTier.monthOverMonthComparison ||
      tier == DataSufficiencyTier.multiMonthTrend;

  bool get canAnalyzeMultiMonthTrend =>
      tier == DataSufficiencyTier.multiMonthTrend;

  String get tierLocalizationKey {
    switch (tier) {
      case DataSufficiencyTier.empty:
        return 'ai_ins_tier_empty';
      case DataSufficiencyTier.preliminary:
        return 'ai_ins_tier_preliminary';
      case DataSufficiencyTier.currentMonthAnalysis:
        return 'ai_ins_tier_current_month';
      case DataSufficiencyTier.monthOverMonthComparison:
        return 'ai_ins_tier_mom';
      case DataSufficiencyTier.multiMonthTrend:
        return 'ai_ins_tier_multi_month';
    }
  }

  String get tierLabel => AppLocalizations.tr(tierLocalizationKey);

  String tierLabelWithContext(BuildContext context) =>
      context.tr(tierLocalizationKey);
}

/// Chế độ xác định thu nhập tham chiếu
enum IncomeStabilityMode {
  /// Người dùng chủ động nhập/xác nhận thu nhập dự kiến
  declared,

  /// Thu nhập lịch sử ổn định (CV <= 0.15)
  stable,

  /// Thu nhập lịch sử biến động mạnh (CV > 0.15) -> dùng mức thận trọng (Conservative Baseline)
  variable,

  /// Chỉ có dữ liệu thu nhập của 1 tháng (tháng hiện tại hoặc 1 tháng trước)
  singleMonth,

  /// Không có dữ liệu thu nhập (Tuyệt đối không lấy tổng ngân sách làm thu nhập)
  noIncomeBasis,
}

/// Kết quả đánh giá thu nhập tham chiếu
class ReferenceIncomeAssessment {
  final IncomeStabilityMode mode;
  final double referenceIncome;
  final double actualCurrentMonthIncome;
  final double historicalMeanIncome;
  final double historicalStdDevIncome;
  final double currentTotalBudget; // Giữ tách biệt tuyệt đối với thu nhập
  final bool isIncomeLikelyIncompleteInCurrentMonth;
  final String explanation;

  const ReferenceIncomeAssessment({
    required this.mode,
    required this.referenceIncome,
    required this.actualCurrentMonthIncome,
    required this.historicalMeanIncome,
    required this.historicalStdDevIncome,
    required this.currentTotalBudget,
    required this.isIncomeLikelyIncompleteInCurrentMonth,
    required this.explanation,
  });

  bool get hasIncomeBasis =>
      mode != IncomeStabilityMode.noIncomeBasis && referenceIncome > 0;
}

/// Trạng thái vòng đời của Kế hoạch tài chính tháng
enum PlanLifecycleStatus {
  draft,
  approved,
  active,
  completed,
  superseded,
}

extension PlanLifecycleStatusLocalization on PlanLifecycleStatus {
  String get localizationKey {
    switch (this) {
      case PlanLifecycleStatus.draft:
        return 'ai_ins_plan_status_draft';
      case PlanLifecycleStatus.approved:
        return 'ai_ins_plan_status_approved';
      case PlanLifecycleStatus.active:
        return 'ai_ins_plan_status_active';
      case PlanLifecycleStatus.completed:
        return 'ai_ins_plan_status_completed';
      case PlanLifecycleStatus.superseded:
        return 'ai_ins_plan_status_superseded';
    }
  }

  String get localizedLabel => AppLocalizations.tr(localizationKey);

  String localizedLabelWithContext(BuildContext context) =>
      context.tr(localizationKey);
}

/// Hạng mục phân bổ ngân sách cho từng danh mục trong kế hoạch tháng
class PlannedCategoryAllocation {
  final String categoryId;
  final String categoryName;
  final bool isEssential;
  final double sourceMonthSpent; // Thực chi ở tháng nguồn phân tích
  final double regularBaselineSpent; // Chi tiêu thường xuyên (đã bóc tách outlier đột biến)
  final double historicalMedian; // Trung vị lịch sử (nếu có)
  final double? existingBudget; // Ngân sách hiện có ở tháng áp dụng tại thời điểm tạo
  final double floorLimit; // Mức sàn tối thiểu khả thi trong 1 tháng
  final double recommendedLimit; // Hạn mức đề xuất trong kế hoạch
  final double deltaFromCurrent; // Chênh lệch (recommendedLimit - sourceMonthSpent)
  final String calculationBasis; // Căn cứ tính toán minh bạch từ thuật toán Dart
  final String aiActionTip; // Gợi ý hành động cụ thể từ AI

  const PlannedCategoryAllocation({
    required this.categoryId,
    required this.categoryName,
    required this.isEssential,
    required this.sourceMonthSpent,
    required this.regularBaselineSpent,
    required this.historicalMedian,
    this.existingBudget,
    required this.floorLimit,
    required this.recommendedLimit,
    required this.deltaFromCurrent,
    required this.calculationBasis,
    required this.aiActionTip,
  });

  factory PlannedCategoryAllocation.fromMap(Map<String, dynamic> map) {
    return PlannedCategoryAllocation(
      categoryId: (map['categoryId'] ?? '').toString(),
      categoryName: (map['categoryName'] ?? '').toString(),
      isEssential: map['isEssential'] == true,
      sourceMonthSpent: _toDouble(map['sourceMonthSpent']),
      regularBaselineSpent: _toDouble(map['regularBaselineSpent']),
      historicalMedian: _toDouble(map['historicalMedian']),
      existingBudget: map['existingBudget'] != null
          ? _toDouble(map['existingBudget'])
          : null,
      floorLimit: _toDouble(map['floorLimit']),
      recommendedLimit: _toDouble(map['recommendedLimit']),
      deltaFromCurrent: _toDouble(map['deltaFromCurrent']),
      calculationBasis: (map['calculationBasis'] ?? '').toString(),
      aiActionTip: (map['aiActionTip'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'categoryId': categoryId,
      'categoryName': categoryName,
      'isEssential': isEssential,
      'sourceMonthSpent': sourceMonthSpent,
      'regularBaselineSpent': regularBaselineSpent,
      'historicalMedian': historicalMedian,
      'existingBudget': existingBudget,
      'floorLimit': floorLimit,
      'recommendedLimit': recommendedLimit,
      'deltaFromCurrent': deltaFromCurrent,
      'calculationBasis': calculationBasis,
      'aiActionTip': aiActionTip,
    };
  }

  PlannedCategoryAllocation copyWith({
    String? categoryId,
    String? categoryName,
    bool? isEssential,
    double? sourceMonthSpent,
    double? regularBaselineSpent,
    double? historicalMedian,
    double? existingBudget,
    double? floorLimit,
    double? recommendedLimit,
    double? deltaFromCurrent,
    String? calculationBasis,
    String? aiActionTip,
  }) {
    final nextRec = recommendedLimit ?? this.recommendedLimit;
    final nextSource = sourceMonthSpent ?? this.sourceMonthSpent;
    return PlannedCategoryAllocation(
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      isEssential: isEssential ?? this.isEssential,
      sourceMonthSpent: nextSource,
      regularBaselineSpent: regularBaselineSpent ?? this.regularBaselineSpent,
      historicalMedian: historicalMedian ?? this.historicalMedian,
      existingBudget: existingBudget ?? this.existingBudget,
      floorLimit: floorLimit ?? this.floorLimit,
      recommendedLimit: nextRec,
      deltaFromCurrent: deltaFromCurrent ?? (nextRec - nextSource),
      calculationBasis: calculationBasis ?? this.calculationBasis,
      aiActionTip: aiActionTip ?? this.aiActionTip,
    );
  }
}

/// Bản chụp bất biến (Immutable Original Snapshot) khi kế hoạch được phê duyệt lần đầu
class PlanSnapshotData {
  final double referenceIncome;
  final double essentialExpenseTotal;
  final double flexibleExpenseTotal;
  final double targetSavingAmount;
  final List<PlannedCategoryAllocation> allocations;
  final DateTime capturedAt;

  const PlanSnapshotData({
    required this.referenceIncome,
    required this.essentialExpenseTotal,
    required this.flexibleExpenseTotal,
    required this.targetSavingAmount,
    required this.allocations,
    required this.capturedAt,
  });

  factory PlanSnapshotData.fromMap(Map<String, dynamic> map) {
    final rawList = (map['allocations'] as List<dynamic>?) ?? const [];
    return PlanSnapshotData(
      referenceIncome: _toDouble(map['referenceIncome']),
      essentialExpenseTotal: _toDouble(map['essentialExpenseTotal']),
      flexibleExpenseTotal: _toDouble(map['flexibleExpenseTotal']),
      targetSavingAmount: _toDouble(map['targetSavingAmount']),
      allocations: rawList
          .whereType<Map>()
          .map((e) =>
              PlannedCategoryAllocation.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      capturedAt: _parseDateTime(map['capturedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'referenceIncome': referenceIncome,
      'essentialExpenseTotal': essentialExpenseTotal,
      'flexibleExpenseTotal': flexibleExpenseTotal,
      'targetSavingAmount': targetSavingAmount,
      'allocations': allocations.map((e) => e.toMap()).toList(),
      'capturedAt': capturedAt.toIso8601String(),
    };
  }

  PlanSnapshotData copyWith({
    double? referenceIncome,
    double? essentialExpenseTotal,
    double? flexibleExpenseTotal,
    double? targetSavingAmount,
    List<PlannedCategoryAllocation>? allocations,
    DateTime? capturedAt,
  }) {
    return PlanSnapshotData(
      referenceIncome: referenceIncome ?? this.referenceIncome,
      essentialExpenseTotal:
          essentialExpenseTotal ?? this.essentialExpenseTotal,
      flexibleExpenseTotal: flexibleExpenseTotal ?? this.flexibleExpenseTotal,
      targetSavingAmount: targetSavingAmount ?? this.targetSavingAmount,
      allocations: allocations ?? this.allocations,
      capturedAt: capturedAt ?? this.capturedAt,
    );
  }
}

/// Lịch sử mỗi lần điều chỉnh kế hoạch giữa tháng (Rebalance Audit Log)
class PlanAdjustmentLog {
  final DateTime adjustedAt;
  final String reason;
  final String strategy; // 'reallocate_categories' | 'adjust_monthly_saving' | 'update_income'
  final double previousTargetSaving;
  final double newTargetSaving;
  final String summary;

  const PlanAdjustmentLog({
    required this.adjustedAt,
    required this.reason,
    required this.strategy,
    required this.previousTargetSaving,
    required this.newTargetSaving,
    required this.summary,
  });

  factory PlanAdjustmentLog.fromMap(Map<String, dynamic> map) {
    return PlanAdjustmentLog(
      adjustedAt: _parseDateTime(map['adjustedAt']),
      reason: (map['reason'] ?? '').toString(),
      strategy: (map['strategy'] ?? 'reallocate_categories').toString(),
      previousTargetSaving: _toDouble(map['previousTargetSaving']),
      newTargetSaving: _toDouble(map['newTargetSaving']),
      summary: (map['summary'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'adjustedAt': adjustedAt.toIso8601String(),
      'reason': reason,
      'strategy': strategy,
      'previousTargetSaving': previousTargetSaving,
      'newTargetSaving': newTargetSaving,
      'summary': summary,
    };
  }
}

/// Bản Kế hoạch Tài chính Tháng lưu trong collection `monthly_plans`
class MonthlyFinancialPlan {
  final String planId;
  final String userId;
  final String sourceMonth; // Định dạng "MM/yyyy" (tháng nguồn phân tích)
  final String targetMonth; // Định dạng "MM/yyyy" (tháng áp dụng kế hoạch)
  final PlanLifecycleStatus status;
  final DataSufficiencyTier dataTierUsed;
  final IncomeStabilityMode incomeMode;
  final double referenceIncome;
  final double essentialExpenseCap;
  final double flexibleExpenseCap;
  final double targetSavingAmount; // Mục tiêu tiết kiệm riêng của tháng targetMonth
  final double desiredGoalSavingAmount; // Nhu cầu tiết kiệm gốc từ SavingGoal (nếu có)
  final bool isSavingGoalFeasible;
  final double infeasibleSavingGap;
  final int? recommendedGoalMonths;
  final bool isEssentialDeficit; // true khi bản thân chi phí thiết yếu đã >= thu nhập tham chiếu
  final List<PlannedCategoryAllocation> currentAllocations;
  final List<String> selectedCategoryIds;
  final PlanSnapshotData originalSnapshot;
  final List<PlanAdjustmentLog> adjustmentHistory;
  final String aiExecutiveSummary;
  final List<String> behavioralInsights;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MonthlyFinancialPlan({
    required this.planId,
    required this.userId,
    required this.sourceMonth,
    required this.targetMonth,
    required this.status,
    required this.dataTierUsed,
    required this.incomeMode,
    required this.referenceIncome,
    required this.essentialExpenseCap,
    required this.flexibleExpenseCap,
    required this.targetSavingAmount,
    this.desiredGoalSavingAmount = 0,
    required this.isSavingGoalFeasible,
    this.infeasibleSavingGap = 0,
    this.recommendedGoalMonths,
    this.isEssentialDeficit = false,
    required this.currentAllocations,
    this.selectedCategoryIds = const [],
    required this.originalSnapshot,
    this.adjustmentHistory = const [],
    required this.aiExecutiveSummary,
    this.behavioralInsights = const [],
    this.revision = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  double get plannedTotalExpense => essentialExpenseCap + flexibleExpenseCap;

  /// Kiểm tra bất biến cân bằng ngân sách (Khi có thu nhập và không bị thâm hụt thiết yếu)
  bool get satisfiesBudgetBalanceInvariant {
    if (referenceIncome <= 0 || isEssentialDeficit) return true;
    // Cho phép sai số làm tròn <= 1.0 VND
    return (plannedTotalExpense + targetSavingAmount) <=
        (referenceIncome + 1.0);
  }

  factory MonthlyFinancialPlan.fromMap(Map<String, dynamic> map, String id) {
    final allocList = (map['currentAllocations'] as List<dynamic>?) ?? const [];
    final parsedAllocations = allocList
        .whereType<Map>()
        .map((e) =>
            PlannedCategoryAllocation.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    final adjList = (map['adjustmentHistory'] as List<dynamic>?) ?? const [];
    final parsedAdjustments = adjList
        .whereType<Map>()
        .map((e) => PlanAdjustmentLog.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    final rawOrig = map['originalSnapshot'];
    final origSnapshot = rawOrig is Map
        ? PlanSnapshotData.fromMap(Map<String, dynamic>.from(rawOrig))
        : PlanSnapshotData(
            referenceIncome: _toDouble(map['referenceIncome']),
            essentialExpenseTotal: _toDouble(map['essentialExpenseCap']),
            flexibleExpenseTotal: _toDouble(map['flexibleExpenseCap']),
            targetSavingAmount: _toDouble(map['targetSavingAmount']),
            allocations: parsedAllocations,
            capturedAt: _parseDateTime(map['createdAt']),
          );

    return MonthlyFinancialPlan(
      planId: id,
      userId: (map['userId'] ?? '').toString(),
      sourceMonth: (map['sourceMonth'] ?? map['targetMonth'] ?? '').toString(),
      targetMonth: (map['targetMonth'] ?? '').toString(),
      status: _parseStatus((map['status'] ?? 'draft').toString()),
      dataTierUsed: _parseTier((map['dataTierUsed'] ?? 'preliminary').toString()),
      incomeMode:
          _parseIncomeMode((map['incomeMode'] ?? 'noIncomeBasis').toString()),
      referenceIncome: _toDouble(map['referenceIncome']),
      essentialExpenseCap: _toDouble(map['essentialExpenseCap']),
      flexibleExpenseCap: _toDouble(map['flexibleExpenseCap']),
      targetSavingAmount: _toDouble(map['targetSavingAmount']),
      desiredGoalSavingAmount: _toDouble(map['desiredGoalSavingAmount']),
      isSavingGoalFeasible: map['isSavingGoalFeasible'] != false,
      infeasibleSavingGap: _toDouble(map['infeasibleSavingGap']),
      recommendedGoalMonths: map['recommendedGoalMonths'] is num
          ? (map['recommendedGoalMonths'] as num).toInt()
          : null,
      isEssentialDeficit: map['isEssentialDeficit'] == true,
      currentAllocations: parsedAllocations,
      selectedCategoryIds:
          ((map['selectedCategoryIds'] as List<dynamic>?) ?? const [])
              .map((e) => e.toString())
              .toList(),
      originalSnapshot: origSnapshot,
      adjustmentHistory: parsedAdjustments,
      aiExecutiveSummary: (map['aiExecutiveSummary'] ?? '').toString(),
      behavioralInsights: ((map['behavioralInsights'] as List<dynamic>?) ??
              const [])
          .map((e) => e.toString())
          .toList(),
      revision: map['revision'] is num ? (map['revision'] as num).toInt() : 1,
      createdAt: _parseDateTime(map['createdAt']),
      updatedAt: _parseDateTime(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'sourceMonth': sourceMonth,
      'targetMonth': targetMonth,
      'status': status.name,
      'dataTierUsed': dataTierUsed.name,
      'incomeMode': incomeMode.name,
      'referenceIncome': referenceIncome,
      'essentialExpenseCap': essentialExpenseCap,
      'flexibleExpenseCap': flexibleExpenseCap,
      'targetSavingAmount': targetSavingAmount,
      'desiredGoalSavingAmount': desiredGoalSavingAmount,
      'isSavingGoalFeasible': isSavingGoalFeasible,
      'infeasibleSavingGap': infeasibleSavingGap,
      'recommendedGoalMonths': recommendedGoalMonths,
      'isEssentialDeficit': isEssentialDeficit,
      'currentAllocations': currentAllocations.map((e) => e.toMap()).toList(),
      'selectedCategoryIds': selectedCategoryIds,
      'originalSnapshot': originalSnapshot.toMap(),
      'adjustmentHistory': adjustmentHistory.map((e) => e.toMap()).toList(),
      'aiExecutiveSummary': aiExecutiveSummary,
      'behavioralInsights': behavioralInsights,
      'revision': revision,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  MonthlyFinancialPlan copyWith({
    String? planId,
    String? userId,
    String? sourceMonth,
    String? targetMonth,
    PlanLifecycleStatus? status,
    DataSufficiencyTier? dataTierUsed,
    IncomeStabilityMode? incomeMode,
    double? referenceIncome,
    double? essentialExpenseCap,
    double? flexibleExpenseCap,
    double? targetSavingAmount,
    double? desiredGoalSavingAmount,
    bool? isSavingGoalFeasible,
    double? infeasibleSavingGap,
    int? recommendedGoalMonths,
    bool? isEssentialDeficit,
    List<PlannedCategoryAllocation>? currentAllocations,
    List<String>? selectedCategoryIds,
    PlanSnapshotData? originalSnapshot,
    List<PlanAdjustmentLog>? adjustmentHistory,
    String? aiExecutiveSummary,
    List<String>? behavioralInsights,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MonthlyFinancialPlan(
      planId: planId ?? this.planId,
      userId: userId ?? this.userId,
      sourceMonth: sourceMonth ?? this.sourceMonth,
      targetMonth: targetMonth ?? this.targetMonth,
      status: status ?? this.status,
      dataTierUsed: dataTierUsed ?? this.dataTierUsed,
      incomeMode: incomeMode ?? this.incomeMode,
      referenceIncome: referenceIncome ?? this.referenceIncome,
      essentialExpenseCap: essentialExpenseCap ?? this.essentialExpenseCap,
      flexibleExpenseCap: flexibleExpenseCap ?? this.flexibleExpenseCap,
      targetSavingAmount: targetSavingAmount ?? this.targetSavingAmount,
      desiredGoalSavingAmount:
          desiredGoalSavingAmount ?? this.desiredGoalSavingAmount,
      isSavingGoalFeasible: isSavingGoalFeasible ?? this.isSavingGoalFeasible,
      infeasibleSavingGap: infeasibleSavingGap ?? this.infeasibleSavingGap,
      recommendedGoalMonths:
          recommendedGoalMonths ?? this.recommendedGoalMonths,
      isEssentialDeficit: isEssentialDeficit ?? this.isEssentialDeficit,
      currentAllocations: currentAllocations ?? this.currentAllocations,
      selectedCategoryIds: selectedCategoryIds ?? this.selectedCategoryIds,
      originalSnapshot: originalSnapshot ?? this.originalSnapshot,
      adjustmentHistory: adjustmentHistory ?? this.adjustmentHistory,
      aiExecutiveSummary: aiExecutiveSummary ?? this.aiExecutiveSummary,
      behavioralInsights: behavioralInsights ?? this.behavioralInsights,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Trạng thái thực thi của từng danh mục trong kế hoạch
class CategoryAdherenceStatus {
  final String categoryId;
  final String categoryName;
  final bool isEssential;
  final double plannedLimit;
  final double actualSpent;
  final double remainingAmount;
  final double usageRatio; // actualSpent / plannedLimit
  final String status; // 'on_track' | 'pacing_fast' | 'exceeded' | 'upcoming'

  const CategoryAdherenceStatus({
    required this.categoryId,
    required this.categoryName,
    required this.isEssential,
    required this.plannedLimit,
    required this.actualSpent,
    required this.remainingAmount,
    required this.usageRatio,
    required this.status,
  });

  bool get isExceeded => status == 'exceeded';
  bool get isPacingFast => status == 'pacing_fast';
  bool get isOnTrack => status == 'on_track';
  bool get isUpcoming => status == 'upcoming';
}

/// Kết quả theo dõi thực thi kép (Ngân sách + Tiết kiệm không tính trùng)
class PlanExecutionTrackerResult {
  final String targetMonth;
  final double elapsedMonthRatio;

  /// `true` khi tháng áp dụng kế hoạch nằm trong tương lai (chưa bắt đầu thực thi)
  final bool isUpcoming;

  // 1. Chiều Ngân sách
  final double plannedTotalExpense;
  final double actualTotalExpense;
  final double budgetUsageRatio;
  final double budgetAdherenceScore; // 0..100
  final int onTrackCategoryCount;
  final int exceededCategoryCount;
  final List<CategoryAdherenceStatus> categoryStatuses;

  // 2. Chiều Tiết kiệm (Không tính trùng giữa goal_deposit và thặng dư dòng tiền)
  final double targetSavingAmount;
  final double actualIncomeInMonth;
  final double netGoalContributions; // = sum(goal_deposit) - sum(goal_withdraw)
  final double totalNetCashflowSurplus; // = actualIncomeInMonth - actualTotalExpense
  final double unallocatedWalletSurplus; // = max(0, totalNetCashflowSurplus - netGoalContributions)
  final double effectiveMonthlySaved; // = netGoalContributions + unallocatedWalletSurplus (không bao giờ tính trùng)
  final double savingExecutionRatio;
  final double savingAdherenceScore; // 0..100

  // 3. Tổng hợp & Gợi ý điều chỉnh
  final double overallAdherenceScore; // 0.6 * budgetAdherenceScore + 0.4 * savingAdherenceScore
  final bool needsRebalance;
  final double totalOverrunAmount;

  String get activationDateLabel => '01/$targetMonth';

  const PlanExecutionTrackerResult({
    required this.targetMonth,
    required this.elapsedMonthRatio,
    this.isUpcoming = false,
    required this.plannedTotalExpense,
    required this.actualTotalExpense,
    required this.budgetUsageRatio,
    required this.budgetAdherenceScore,
    required this.onTrackCategoryCount,
    required this.exceededCategoryCount,
    required this.categoryStatuses,
    required this.targetSavingAmount,
    required this.actualIncomeInMonth,
    required this.netGoalContributions,
    required this.totalNetCashflowSurplus,
    required this.unallocatedWalletSurplus,
    required this.effectiveMonthlySaved,
    required this.savingExecutionRatio,
    required this.savingAdherenceScore,
    required this.overallAdherenceScore,
    required this.needsRebalance,
    required this.totalOverrunAmount,
  });
}

/// Phản hồi JSON có cấu trúc từ Gemini AI sau khi đã qua hậu kiểm (Post-Validation)
class AiStructuredPlanInsight {
  final String executiveSummary;
  final List<String> behavioralInsights;
  final Map<String, String> categoryActionTips;
  final String savingStrategyNote;
  final bool isFromFallback;

  const AiStructuredPlanInsight({
    required this.executiveSummary,
    required this.behavioralInsights,
    required this.categoryActionTips,
    required this.savingStrategyNote,
    this.isFromFallback = false,
  });
}

/// Thông báo hệ thống do Admin quản lý (Collection: system_announcements)
class SystemAnnouncement {
  final String id;
  final String title;
  final String content;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const SystemAnnouncement({
    required this.id,
    required this.title,
    required this.content,
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
  });

  factory SystemAnnouncement.fromMap(Map<String, dynamic> map, String id) {
    return SystemAnnouncement(
      id: id,
      title: (map['title'] ?? '').toString(),
      content: (map['content'] ?? '').toString(),
      isActive: map['isActive'] != false,
      createdAt: _parseDateTime(map['createdAt']),
      updatedAt:
          map['updatedAt'] != null ? _parseDateTime(map['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'content': content,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  SystemAnnouncement copyWith({
    String? id,
    String? title,
    String? content,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SystemAnnouncement(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Mẫu danh mục hệ thống do Admin quản lý (Collection: system_categories)
class SystemCategoryTemplate {
  final String id;
  final String name;
  final String type; // 'expense' | 'income'
  final String icon;
  final int color;
  final bool isEssential;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SystemCategoryTemplate({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
    this.isEssential = false,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory SystemCategoryTemplate.fromMap(Map<String, dynamic> map, String id) {
    return SystemCategoryTemplate(
      id: id,
      name: (map['name'] ?? '').toString(),
      type: (map['type'] ?? 'expense').toString(),
      icon: (map['icon'] ?? 'category').toString(),
      color: map['color'] is num ? (map['color'] as num).toInt() : 0xFF1F6F8B,
      isEssential: map['isEssential'] == true,
      isActive: map['isActive'] != false,
      createdAt:
          map['createdAt'] != null ? _parseDateTime(map['createdAt']) : null,
      updatedAt:
          map['updatedAt'] != null ? _parseDateTime(map['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'icon': icon,
      'color': color,
      'isEssential': isEssential,
      'isActive': isActive,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  SystemCategoryTemplate copyWith({
    String? id,
    String? name,
    String? type,
    String? icon,
    int? color,
    bool? isEssential,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SystemCategoryTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      isEssential: isEssential ?? this.isEssential,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

double _toDouble(dynamic val) {
  if (val == null) return 0.0;
  if (val is num) return val.toDouble();
  if (val is String) return double.tryParse(val) ?? 0.0;
  return 0.0;
}

DateTime _parseDateTime(dynamic val) {
  if (val == null) return DateTime.now();
  if (val is DateTime) return val;
  if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
  try {
    return (val as dynamic).toDate() as DateTime;
  } catch (_) {
    return DateTime.now();
  }
}

PlanLifecycleStatus _parseStatus(String raw) {
  for (final s in PlanLifecycleStatus.values) {
    if (s.name == raw) return s;
  }
  return PlanLifecycleStatus.draft;
}

DataSufficiencyTier _parseTier(String raw) {
  for (final t in DataSufficiencyTier.values) {
    if (t.name == raw) return t;
  }
  return DataSufficiencyTier.preliminary;
}

IncomeStabilityMode _parseIncomeMode(String raw) {
  for (final m in IncomeStabilityMode.values) {
    if (m.name == raw) return m;
  }
  return IncomeStabilityMode.noIncomeBasis;
}
