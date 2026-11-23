import 'dart:math' as math;
import '../models/ai_runtime_config_model.dart';
import '../models/transaction_model.dart';
import '../models/wallet_model.dart';
import '../models/budget_model.dart';
import '../models/category_model.dart';
import '../models/saving_goal_model.dart';
import '../models/user_model.dart';
import '../models/financial_issue.dart';
import '../models/monthly_financial_plan.dart';
import '../services/firestore_service.dart';
import '../services/financial_analytics_service.dart';
import '../services/financial_context_revision_tracker.dart';
import '../l10n/app_localizations.dart';
import '../utils/category_localization_helper.dart';
import '../utils/formatters.dart';
import 'language_controller.dart';

/// Loại thẻ Insight hiển thị tương tác trong cuộc trò chuyện
enum ChatInsightCardType {
  none,
  budgetOverrun,
  savingGoalProgress,
  cashFlowSnapshot,
  emptyDataPrompt,
}

/// Dữ liệu của thẻ Insight trong tin nhắn AI
class ChatInsightCardData {
  final ChatInsightCardType type;
  final String title;
  final String subtitle;
  final String primaryMetric;
  final String? secondaryMetric;
  final double? progressPercent; // 0.0 -> 1.0
  final String actionLabel;
  final String? targetId; // categoryId, goalId...
  /// Đánh dấu trạng thái cảnh báo đỏ (ví dụ ngân sách vượt hạn mức).
  /// Khi `type == ChatInsightCardType.budgetOverrun` và `isAlert == false`,
  /// UI hiển thị tông xanh tích cực cho ngân sách đang an toàn.
  final bool isAlert;

  const ChatInsightCardData({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.primaryMetric,
    this.secondaryMetric,
    this.progressPercent,
    required this.actionLabel,
    this.targetId,
    bool? isAlert,
  }) : isAlert = isAlert ?? (type == ChatInsightCardType.budgetOverrun);

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'title': title,
      'subtitle': subtitle,
      'primaryMetric': primaryMetric,
      'secondaryMetric': secondaryMetric,
      'progressPercent': progressPercent,
      'actionLabel': actionLabel,
      'targetId': targetId,
      'isAlert': isAlert,
    };
  }

  factory ChatInsightCardData.fromMap(Map<String, dynamic> map) {
    final typeName = map['type'] as String? ?? 'none';
    final cardType = ChatInsightCardType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => ChatInsightCardType.none,
    );
    final bool resolvedIsAlert;
    if (map['isAlert'] is bool) {
      resolvedIsAlert = map['isAlert'] as bool;
    } else if (cardType == ChatInsightCardType.budgetOverrun) {
      final sec = (map['secondaryMetric'] as String?)?.toLowerCase() ?? '';
      final isExplicitSafe =
          sec.contains('an toàn') || sec.contains('on track');
      resolvedIsAlert = !isExplicitSafe;
    } else {
      resolvedIsAlert = false;
    }
    return ChatInsightCardData(
      type: cardType,
      title: map['title'] ?? '',
      subtitle: map['subtitle'] ?? '',
      primaryMetric: map['primaryMetric'] ?? '',
      secondaryMetric: map['secondaryMetric'],
      progressPercent: (map['progressPercent'] as num?)?.toDouble(),
      actionLabel:
          map['actionLabel'] ?? AppLocalizations.tr('svc_chat_view_details'),
      targetId: map['targetId'],
      isAlert: resolvedIsAlert,
    );
  }
}

/// Chip câu hỏi gợi ý có ngữ cảnh
class DynamicPromptChip {
  final String label;
  final String
      category; // 'featured' | 'overview' | 'expense' | 'budget' | 'saving'
  final bool isAlert;
  final String? icon;

  const DynamicPromptChip({
    required this.label,
    required this.category,
    this.isAlert = false,
    this.icon,
  });
}

/// Kết quả tổng hợp dữ liệu tài chính phục vụ AI Chat
class FinancialChatContext {
  final String rawPromptContext;
  final double incomeThisMonth;
  final double expenseThisMonth;
  final double netCashFlow;
  final int savingsRate;
  final double totalActiveBalance;
  final double averageMonthlySavings;
  final List<Budget> overBudgets;
  final List<Budget> nearLimitBudgets;
  final List<Budget> budgets;
  final Map<String, double> currentExpenseByCat;
  final List<SavingGoal> savingGoals;
  final List<FinancialIssue> issues;
  final List<DynamicPromptChip> dynamicPrompts;
  final bool hasSufficientData;
  final bool isEmptyData;
  final DataSufficiencyTier dataTier;
  final MonthlyFinancialPlan? activePlan;
  final String revisionSignature;
  final int mutationVersion;

  const FinancialChatContext({
    required this.rawPromptContext,
    required this.incomeThisMonth,
    required this.expenseThisMonth,
    required this.netCashFlow,
    required this.savingsRate,
    required this.totalActiveBalance,
    required this.averageMonthlySavings,
    required this.overBudgets,
    required this.nearLimitBudgets,
    this.budgets = const [],
    this.currentExpenseByCat = const {},
    required this.savingGoals,
    required this.issues,
    required this.dynamicPrompts,
    required this.hasSufficientData,
    required this.isEmptyData,
    this.dataTier = DataSufficiencyTier.preliminary,
    this.activePlan,
    this.revisionSignature = '',
    this.mutationVersion = 0,
  });
}

/// ============================================================
/// FINANCIAL CHAT CONTEXT SERVICE
/// Tổng hợp, tính toán định lượng toàn bộ số liệu tài chính của user
/// để làm ngữ cảnh chuẩn xác cho Gemini, không để AI tự đoán mò.
/// ============================================================
class FinancialChatContextService {
  FirestoreService? _firestoreService;
  final FinancialAnalyticsService _analyticsService;
  final FinancialHeuristicsConfig? _heuristicsOverride;

  FinancialChatContextService({
    FirestoreService? firestoreService,
    FinancialAnalyticsService? analyticsService,
    FinancialHeuristicsConfig? heuristicsOverride,
  })  : _firestoreService = firestoreService,
        _heuristicsOverride = heuristicsOverride,
        _analyticsService = analyticsService ??
            FinancialAnalyticsService(heuristicsOverride: heuristicsOverride);

  FirestoreService get _resolvedFirestore =>
      _firestoreService ??= FirestoreService();

  FinancialHeuristicsConfig get effectiveHeuristics =>
      _heuristicsOverride ?? FinancialHeuristicsConfig.defaults();

  Future<FinancialChatContext> buildContext(String userId) async {
    final now = DateTime.now();
    final startOfTwoMonthsAgo = DateTime(now.year, now.month - 2, 1);
    final endOfCurrentMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    final currentMonthStr = AppFormatters.month(now);

    Future<List<AppTransaction>> fetchWindowTransactions() async {
      try {
        return await _resolvedFirestore.getTransactionsByDateWindow(
          userId,
          from: startOfTwoMonthsAgo,
          to: endOfCurrentMonth,
        );
      } catch (_) {
        return await _resolvedFirestore.getTransactionsSafely(userId);
      }
    }

    // Lấy song song dữ liệu trong cửa sổ phân tích 3 tháng từ Firestore
    final results = await Future.wait<dynamic>([
      fetchWindowTransactions(),
      _resolvedFirestore.getWalletsSafely(userId),
      _resolvedFirestore.getBudgetsSafely(userId, month: currentMonthStr),
      _resolvedFirestore.getCategoriesSafely(userId),
      _resolvedFirestore.getSavingGoalsSafely(userId),
      _resolvedFirestore.getUserProfile(userId),
      _resolvedFirestore.getMonthlyPlan(userId, currentMonthStr),
    ]);

    final allTransactions = results[0] as List<AppTransaction>;
    final wallets = results[1] as List<Wallet>;
    final budgets = results[2] as List<Budget>;
    final categories = results[3] as List<Category>;
    final savingGoals = results[4] as List<SavingGoal>;
    final userProfile = results[5] as AppUser?;
    final activePlan = results[6] as MonthlyFinancialPlan?;

    return buildContextFromData(
      allTransactions: allTransactions,
      wallets: wallets,
      budgets: budgets,
      categories: categories,
      savingGoals: savingGoals,
      userProfile: userProfile,
      declaredMonthlyIncome: userProfile?.monthlyIncome,
      activePlan: activePlan,
      referenceDate: now,
    );
  }

  /// Phương thức thuần (Pure, không phụ thuộc Firestore/userId) để tổng hợp ngữ cảnh tài chính.
  /// Dùng chung 100% logic cho cả luồng User thực tế và AI Sandbox / Unit Test.
  FinancialChatContext buildContextFromData({
    List<AppTransaction>? allTransactions,
    List<AppTransaction>? currentMonthTx,
    List<AppTransaction>? lastMonthTx,
    List<AppTransaction>? twoMonthsAgoTx,
    required List<Wallet> wallets,
    required List<Budget> budgets,
    required List<Category> categories,
    required List<SavingGoal> savingGoals,
    double? declaredMonthlyIncome,
    AppUser? userProfile,
    MonthlyFinancialPlan? activePlan,
    FinancialHeuristicsConfig? heuristicsOverride,
    List<String>? customSuggestedPrompts,
    DateTime? referenceDate,
  }) {
    final h = heuristicsOverride ?? effectiveHeuristics;
    final now = referenceDate ?? DateTime.now();
    final startOfCurrentMonth = DateTime(now.year, now.month, 1);
    final endOfCurrentMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    final startOfLastMonth = DateTime(now.year, now.month - 1, 1);
    final endOfLastMonth = DateTime(now.year, now.month, 0, 23, 59, 59);

    final startOfTwoMonthsAgo = DateTime(now.year, now.month - 2, 1);
    final ninetyDaysAgo = now.subtract(const Duration(days: 90));

    final List<AppTransaction> resolvedAllTx;
    final List<AppTransaction> resolvedCurrentMonthTx;
    final List<AppTransaction> resolvedLastMonthTx;
    final List<AppTransaction> resolvedTwoMonthsAgoTx;

    if (currentMonthTx != null ||
        lastMonthTx != null ||
        twoMonthsAgoTx != null) {
      resolvedCurrentMonthTx = currentMonthTx ?? const [];
      resolvedLastMonthTx = lastMonthTx ?? const [];
      resolvedTwoMonthsAgoTx = twoMonthsAgoTx ?? const [];
      resolvedAllTx = allTransactions ??
          <AppTransaction>[
            ...resolvedCurrentMonthTx,
            ...resolvedLastMonthTx,
            ...resolvedTwoMonthsAgoTx,
          ];
    } else {
      resolvedAllTx = allTransactions ?? const [];
      resolvedCurrentMonthTx = resolvedAllTx.where((t) {
        return t.date.isAfter(
                startOfCurrentMonth.subtract(const Duration(seconds: 1))) &&
            t.date.isBefore(endOfCurrentMonth.add(const Duration(seconds: 1)));
      }).toList();

      resolvedLastMonthTx = resolvedAllTx.where((t) {
        return t.date
                .isAfter(startOfLastMonth.subtract(const Duration(seconds: 1))) &&
            t.date.isBefore(endOfLastMonth.add(const Duration(seconds: 1)));
      }).toList();

      resolvedTwoMonthsAgoTx = resolvedAllTx.where((t) {
        return t.date.isAfter(
                startOfTwoMonthsAgo.subtract(const Duration(seconds: 1))) &&
            t.date.isBefore(startOfLastMonth);
      }).toList();
    }

    // 1. Tính toán định lượng tháng hiện tại
    final incomeThisMonth = resolvedCurrentMonthTx
        .where((t) => t.type == 'income')
        .fold<double>(0.0, (sum, t) => sum + t.amount);

    final expenseThisMonth = resolvedCurrentMonthTx
        .where((t) => t.type == 'expense')
        .fold<double>(0.0, (sum, t) => sum + t.amount);

    final netCashFlow = incomeThisMonth - expenseThisMonth;
    final savingsRate = incomeThisMonth > 0 && netCashFlow > 0
        ? ((netCashFlow / incomeThisMonth) * 100).clamp(0, 100).round()
        : 0;

    // Chi tiêu theo danh mục tháng này
    final Map<String, double> currentExpenseByCat = {};
    for (final t in resolvedCurrentMonthTx.where((t) => t.type == 'expense')) {
      currentExpenseByCat[t.categoryId] =
          (currentExpenseByCat[t.categoryId] ?? 0) + t.amount;
    }

    // 2. Tính toán định lượng tháng trước
    final incomeLastMonth = resolvedLastMonthTx
        .where((t) => t.type == 'income')
        .fold<double>(0.0, (sum, t) => sum + t.amount);

    final expenseLastMonth = resolvedLastMonthTx
        .where((t) => t.type == 'expense')
        .fold<double>(0.0, (sum, t) => sum + t.amount);

    final netLastMonth = incomeLastMonth - expenseLastMonth;

    final Map<String, double> lastExpenseByCat = {};
    for (final t in resolvedLastMonthTx.where((t) => t.type == 'expense')) {
      lastExpenseByCat[t.categoryId] =
          (lastExpenseByCat[t.categoryId] ?? 0) + t.amount;
    }

    // 3. Tính toán tháng trước nữa để có trung bình 3 tháng
    final incomeTwoMonthsAgo = resolvedTwoMonthsAgoTx
        .where((t) => t.type == 'income')
        .fold<double>(0.0, (sum, t) => sum + t.amount);
    final expenseTwoMonthsAgo = resolvedTwoMonthsAgoTx
        .where((t) => t.type == 'expense')
        .fold<double>(0.0, (sum, t) => sum + t.amount);
    final netTwoMonthsAgo = incomeTwoMonthsAgo - expenseTwoMonthsAgo;

    final List<double> recentNets = [];
    if (resolvedCurrentMonthTx.isNotEmpty) recentNets.add(netCashFlow);
    if (resolvedLastMonthTx.isNotEmpty) recentNets.add(netLastMonth);
    if (resolvedTwoMonthsAgoTx.isNotEmpty) recentNets.add(netTwoMonthsAgo);

    final averageMonthlySavings = recentNets.isNotEmpty
        ? recentNets.fold<double>(0.0, (a, b) => a + b) / recentNets.length
        : 0.0;

    // 4. Số dư ví hoạt động
    final totalActiveBalance = wallets
        .where((w) => w.isActive)
        .fold<double>(0.0, (sum, w) => sum + w.balance);

    // 5. Ngân sách & Hạn mức (theo ngưỡng budgetNearLimitRatio động)
    final List<Budget> overBudgets = [];
    final List<Budget> nearLimitBudgets = [];

    for (final b in budgets) {
      final spent = currentExpenseByCat[b.categoryId] ?? 0;
      if (b.isOverBudget(spent)) {
        overBudgets.add(b);
      } else if (b.limit > 0 && spent >= b.limit * h.budgetNearLimitRatio) {
        nearLimitBudgets.add(b);
      }
    }

    final effectiveDeclaredIncome =
        declaredMonthlyIncome ?? userProfile?.monthlyIncome ?? 0.0;

    // 6. Phát hiện vấn đề tài chính định lượng (Issues)
    final issues = _analyticsService.detectIssues(
      currentMonthTx: resolvedCurrentMonthTx,
      lastMonthTx: resolvedLastMonthTx,
      categories: categories,
      monthlyIncome: effectiveDeclaredIncome > 0
          ? effectiveDeclaredIncome
          : incomeThisMonth,
      heuristicsOverride: h,
    );

    // 7. Đánh giá chất lượng dữ liệu đa chiều (Tier 0 -> Tier 4)
    final sufficiency = _analyticsService.assessDataSufficiency(
      currentMonthTx: resolvedCurrentMonthTx,
      historicalMonthsTx: [resolvedLastMonthTx, resolvedTwoMonthsAgoTx],
      currentBudgets: budgets,
      wallets: wallets,
      savingGoals: savingGoals,
      activePlan: activePlan,
      referenceToday: now,
    );
    final ninetyDaysTx =
        resolvedAllTx.where((t) => t.date.isAfter(ninetyDaysAgo)).toList();
    final isEmptyData = sufficiency.tier == DataSufficiencyTier.empty;
    final hasSufficientData =
        sufficiency.tier != DataSufficiencyTier.empty &&
            sufficiency.tier != DataSufficiencyTier.preliminary &&
            ninetyDaysTx.length >= 5;

    final revisionSignature =
        FinancialContextRevisionTracker.computeRevisionSignature(
      transactions: resolvedAllTx,
      budgets: budgets,
      categories: categories,
      savingGoals: savingGoals,
      wallets: wallets,
      activePlan: activePlan,
    );

    // 8. Tạo Prompts gợi ý động theo ngữ cảnh thực tế
    final defaultCustomPrompts = AiRuntimeConfig.defaults()
        .customSuggestedChatPrompts
        .values
        .expand((list) => list)
        .toList();
    final dynamicPrompts = _generateDynamicPrompts(
      isEmptyData: isEmptyData,
      netCashFlow: netCashFlow,
      overBudgets: overBudgets,
      savingGoals: savingGoals,
      categories: categories,
      currentExpenseByCat: currentExpenseByCat,
      issues: issues,
      customSuggestedPrompts: customSuggestedPrompts ?? defaultCustomPrompts,
    );

    // 9. Xây dựng chuỗi prompt context hoàn chỉnh (đã lọc PII và kiểm soát kích thước)
    final rawPromptContext = _formatContextString(
      userProfile: userProfile,
      declaredMonthlyIncome: effectiveDeclaredIncome,
      now: now,
      incomeThisMonth: incomeThisMonth,
      expenseThisMonth: expenseThisMonth,
      netCashFlow: netCashFlow,
      savingsRate: savingsRate,
      incomeLastMonth: incomeLastMonth,
      expenseLastMonth: expenseLastMonth,
      averageMonthlySavings: averageMonthlySavings,
      totalActiveBalance: totalActiveBalance,
      currentExpenseByCat: currentExpenseByCat,
      lastExpenseByCat: lastExpenseByCat,
      categories: categories,
      budgets: budgets,
      overBudgets: overBudgets,
      nearLimitBudgets: nearLimitBudgets,
      savingGoals: savingGoals,
      issues: issues,
      isEmptyData: isEmptyData,
      hasSufficientData: hasSufficientData,
      totalTxCount: resolvedAllTx.length,
      sufficiency: sufficiency,
      activePlan: activePlan,
      currentMonthTx: resolvedCurrentMonthTx,
      heuristics: h,
    );

    return FinancialChatContext(
      rawPromptContext: rawPromptContext,
      incomeThisMonth: incomeThisMonth,
      expenseThisMonth: expenseThisMonth,
      netCashFlow: netCashFlow,
      savingsRate: savingsRate,
      totalActiveBalance: totalActiveBalance,
      averageMonthlySavings: averageMonthlySavings,
      overBudgets: overBudgets,
      nearLimitBudgets: nearLimitBudgets,
      budgets: budgets,
      currentExpenseByCat: currentExpenseByCat,
      savingGoals: savingGoals,
      issues: issues,
      dynamicPrompts: dynamicPrompts,
      hasSufficientData: hasSufficientData,
      isEmptyData: isEmptyData,
      dataTier: sufficiency.tier,
      activePlan: activePlan,
      revisionSignature: revisionSignature,
      mutationVersion: FinancialContextRevisionTracker.localMutationVersion,
    );
  }

  /// Sinh danh sách các chip gợi ý thích ứng theo tình hình thực tế
  List<DynamicPromptChip> _generateDynamicPrompts({
    required bool isEmptyData,
    required double netCashFlow,
    required List<Budget> overBudgets,
    required List<SavingGoal> savingGoals,
    required List<Category> categories,
    required Map<String, double> currentExpenseByCat,
    required List<FinancialIssue> issues,
    List<String> customSuggestedPrompts = const [],
  }) {
    final List<DynamicPromptChip> prompts = [];

    if (isEmptyData) {
      prompts.add(DynamicPromptChip(
        label: AppLocalizations.tr('svc_chat_prompt_empty_1'),
        category: 'featured',
        icon: '💡',
      ));
      prompts.add(DynamicPromptChip(
        label: AppLocalizations.tr('svc_chat_prompt_empty_2'),
        category: 'overview',
      ));
      prompts.add(DynamicPromptChip(
        label: AppLocalizations.tr('svc_chat_prompt_empty_3'),
        category: 'saving',
      ));
      return prompts;
    }

    // 1. Nhóm Nổi Bật / Cảnh Báo theo tình trạng thực tế
    if (overBudgets.isNotEmpty) {
      prompts.add(DynamicPromptChip(
        label: AppLocalizations.tr('svc_chat_prompt_over_budget'),
        category: 'featured',
        isAlert: true,
        icon: '⚠️',
      ));
    }

    if (netCashFlow < 0) {
      prompts.add(DynamicPromptChip(
        label: AppLocalizations.tr('svc_chat_prompt_neg_cf'),
        category: 'featured',
        isAlert: true,
        icon: '⚠️',
      ));
    }

    if (issues.any((i) => i.category == IssueCategory.spike)) {
      prompts.add(DynamicPromptChip(
        label: AppLocalizations.tr('svc_chat_prompt_spike'),
        category: 'featured',
        isAlert: true,
        icon: '📈',
      ));
    }

    if (savingGoals.isNotEmpty) {
      prompts.add(DynamicPromptChip(
        label: AppLocalizations.tr('svc_chat_prompt_goal_due'),
        category: 'featured',
        icon: '🎯',
      ));
    }

    // Luôn bổ sung các câu hỏi chiến lược giá trị cao trong nhóm Nổi bật
    prompts.add(DynamicPromptChip(
      label: AppLocalizations.tr('svc_chat_prompt_issue'),
      category: 'featured',
      icon: '🔥',
    ));
    prompts.add(DynamicPromptChip(
      label: AppLocalizations.tr('svc_chat_prompt_improve'),
      category: 'featured',
      icon: '💡',
    ));
    prompts.add(DynamicPromptChip(
      label: AppLocalizations.tr('svc_chat_prompt_save_more'),
      category: 'featured',
      icon: '💎',
    ));
    prompts.add(DynamicPromptChip(
      label: AppLocalizations.tr('svc_chat_prompt_feasible'),
      category: 'featured',
      icon: '🎯',
    ));

    // 2. Nhóm Tổng quan
    prompts.add(DynamicPromptChip(
      label: AppLocalizations.tr('svc_chat_prompt_ov_status'),
      category: 'overview',
    ));
    prompts.add(DynamicPromptChip(
      label: AppLocalizations.tr('svc_chat_prompt_ov_change'),
      category: 'overview',
    ));
    prompts.add(DynamicPromptChip(
      label: AppLocalizations.tr('svc_chat_prompt_ov_left'),
      category: 'overview',
    ));

    // 3. Nhóm Chi tiêu
    prompts.add(DynamicPromptChip(
      label: AppLocalizations.tr('svc_chat_prompt_exp_top'),
      category: 'expense',
    ));
    prompts.add(DynamicPromptChip(
      label: AppLocalizations.tr('svc_chat_prompt_exp_cut'),
      category: 'expense',
    ));
    prompts.add(DynamicPromptChip(
      label: AppLocalizations.tr('svc_chat_prompt_exp_more'),
      category: 'expense',
    ));

    // 4. Nhóm Ngân sách
    prompts.add(DynamicPromptChip(
      label: AppLocalizations.tr('svc_chat_prompt_bud_use'),
      category: 'budget',
    ));
    prompts.add(DynamicPromptChip(
      label: AppLocalizations.tr('svc_chat_prompt_bud_end'),
      category: 'budget',
    ));

    // 5. Nhóm Tiết kiệm & Mục tiêu
    prompts.add(DynamicPromptChip(
      label: AppLocalizations.tr('svc_chat_prompt_sav_howmuch'),
      category: 'saving',
    ));
    prompts.add(DynamicPromptChip(
      label: AppLocalizations.tr('svc_chat_prompt_sav_2m'),
      category: 'saving',
    ));
    prompts.add(DynamicPromptChip(
      label: AppLocalizations.tr('svc_chat_prompt_sav_10m'),
      category: 'saving',
    ));

    // Bổ sung các câu hỏi gợi ý tùy chỉnh từ Admin (nếu chưa trùng lặp)
    final existingLabels =
        prompts.map((p) => p.label.trim().toLowerCase()).toSet();
    for (final customLabel in customSuggestedPrompts.take(10)) {
      final trimmed = customLabel.trim();
      if (trimmed.isNotEmpty &&
          !existingLabels.contains(trimmed.toLowerCase())) {
        prompts.add(DynamicPromptChip(
          label: trimmed,
          category: 'featured',
          icon: '✨',
        ));
        existingLabels.add(trimmed.toLowerCase());
      }
    }

    return prompts;
  }

  /// Chọn lọc tối đa [maxCount] (mặc định 5) chip gợi ý động thông minh nhất
  /// cho thanh gợi ý 1 hàng gọn trên giao diện AI Chat:
  /// - Ưu tiên 1: Các chip cảnh báo đỏ (`isAlert == true`: vượt ngân sách, dòng tiền âm, chi đột biến).
  /// - Ưu tiên 2: Các câu hỏi sát ngữ cảnh nhất theo đa dạng khía cạnh (mục tiêu, ngân sách, tổng quan, chi tiêu, tiết kiệm).
  static List<DynamicPromptChip> selectCompactPrompts(
    List<DynamicPromptChip> allPrompts, {
    int maxCount = 5,
    bool hasNearLimitBudgets = false,
  }) {
    if (allPrompts.length <= maxCount) {
      return List<DynamicPromptChip>.unmodifiable(allPrompts);
    }

    final selected = <DynamicPromptChip>[];
    final seenLabels = <String>{};

    bool addIfEligible(DynamicPromptChip chip) {
      if (selected.length >= maxCount) return false;
      final key = chip.label.trim().toLowerCase();
      if (key.isEmpty || seenLabels.contains(key)) return false;
      seenLabels.add(key);
      selected.add(chip);
      return true;
    }

    // 1. Ưu tiên cao nhất: Toàn bộ chip cảnh báo đỏ
    for (final chip in allPrompts.where((p) => p.isAlert)) {
      addIfEligible(chip);
    }

    // 2. Ưu tiên chip mục tiêu tiết kiệm (nếu người dùng có mục tiêu)
    for (final chip in allPrompts
        .where((p) => !p.isAlert && p.category == 'featured' && p.icon == '🎯')) {
      if (addIfEligible(chip)) break;
    }

    // 3. Nếu có ngân sách gần chạm hạn mức, ưu tiên chip kiểm tra ngân sách
    if (hasNearLimitBudgets) {
      for (final chip in allPrompts.where((p) => !p.isAlert && p.category == 'budget')) {
        if (addIfEligible(chip)) break;
      }
    }

    // 4. Lấp đầy cân bằng đa dạng góc nhìn (Tổng quan -> Chi tiêu -> Tiết kiệm -> Ngân sách -> Nổi bật)
    const priorityCategories = [
      'overview',
      'expense',
      'saving',
      'budget',
      'featured',
    ];
    for (final cat in priorityCategories) {
      if (selected.length >= maxCount) break;
      for (final chip in allPrompts.where((p) => !p.isAlert && p.category == cat)) {
        if (addIfEligible(chip)) break;
      }
    }

    // 5. Fallback bổ sung nếu danh sách nguồn có ít phân nhóm
    for (final chip in allPrompts) {
      if (selected.length >= maxCount) break;
      addIfEligible(chip);
    }

    return List<DynamicPromptChip>.unmodifiable(selected);
  }

  /// Lọc PII khỏi tên hiển thị (không bao giờ gửi email, SĐT hoặc UID cho Gemini)
  static String _sanitizeDisplayName(String? rawName) {
    if (rawName == null || rawName.trim().isEmpty) return AppLocalizations.tr('svc_chat_guest');
    var cleaned = rawName.trim();
    if (cleaned.contains('@')) {
      cleaned = cleaned.split('@').first.trim();
    }
    cleaned = cleaned.replaceAll(RegExp(r'\b\d{9,12}\b'), AppLocalizations.tr('svc_chat_hidden_phone'));
    if (cleaned.isEmpty) return AppLocalizations.tr('svc_chat_guest');
    return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
  }

  /// Định dạng chuỗi context chi tiết và chặt chẽ cho Gemini (đã lọc PII & giới hạn kích thước)
  String _formatContextString({
    required AppUser? userProfile,
    double declaredMonthlyIncome = 0,
    required DateTime now,
    required double incomeThisMonth,
    required double expenseThisMonth,
    required double netCashFlow,
    required int savingsRate,
    required double incomeLastMonth,
    required double expenseLastMonth,
    required double averageMonthlySavings,
    required double totalActiveBalance,
    required Map<String, double> currentExpenseByCat,
    required Map<String, double> lastExpenseByCat,
    required List<Category> categories,
    required List<Budget> budgets,
    required List<Budget> overBudgets,
    required List<Budget> nearLimitBudgets,
    required List<SavingGoal> savingGoals,
    required List<FinancialIssue> issues,
    required bool isEmptyData,
    required bool hasSufficientData,
    required int totalTxCount,
    DataSufficiencyAssessment? sufficiency,
    MonthlyFinancialPlan? activePlan,
    List<AppTransaction> currentMonthTx = const [],
    required FinancialHeuristicsConfig heuristics,
  }) {
    final buffer = StringBuffer();
    final monthStr = '${now.month}/${now.year}';
    final dayOfMonth = now.day;
    final effectiveDeclared = declaredMonthlyIncome > 0
        ? declaredMonthlyIncome
        : (userProfile?.monthlyIncome ?? 0.0);

    if (LanguageController.isEnglish) {
      buffer.writeln('=== USER ACTUAL FINANCIAL DATA ===');
      buffer.writeln('- User: ${_sanitizeDisplayName(userProfile?.name)}');
      if (effectiveDeclared > 0) {
        buffer.writeln(
            '- Declared expected monthly income in profile: ${AppFormatters.number(effectiveDeclared)} VND/month (AI Note: Use as baseline for 50/30/20 or planning only; DO NOT add to actual wallet balance or recorded transaction income)');
      }
      buffer.writeln('- Analysis date: Day $dayOfMonth of $monthStr');
      buffer.writeln('- Total recorded transactions: $totalTxCount transactions');
      if (sufficiency != null) {
        buffer.writeln(
            '- Data sufficiency tier (${sufficiency.tier.name}): ${sufficiency.limitationNote}');
      }

      if (isEmptyData) {
        buffer.writeln('\n[DATA STATUS]: NO TRANSACTIONS YET.');
        buffer.writeln(
            'AI Instruction: Gently remind the user to add income and expense transactions to enable personalized financial analysis.');
        return buffer.toString();
      }

      if (!hasSufficientData) {
        buffer.writeln(
            '\n[DATA STATUS]: LIMITED DATA ($totalTxCount transactions).');
        buffer.writeln(
            'AI Instruction: Explicitly note that data covers only a short period and is insufficient for long-term trend conclusions.');
      }

      // 1. Current month metrics
      buffer.writeln('\n1. THIS MONTH OVERVIEW ($monthStr):');
      buffer.writeln('- Total income: ${AppFormatters.number(incomeThisMonth)} VND');
      buffer.writeln('- Total expense: ${AppFormatters.number(expenseThisMonth)} VND');
      buffer.writeln(
          '- Net Cash Flow (Income - Expense): ${netCashFlow >= 0 ? '+' : ''}${AppFormatters.number(netCashFlow)} VND (${netCashFlow >= 0 ? 'SURPLUS' : 'DEFICIT'})');
      buffer.writeln('- Savings rate: $savingsRate%');
      buffer.writeln(
          '- Total active wallet balance: ${AppFormatters.number(totalActiveBalance)} VND');

      // 2. Last month comparison
      buffer.writeln('\n2. COMPARISON WITH LAST MONTH:');
      buffer.writeln(
          '- Last month income: ${AppFormatters.number(incomeLastMonth)} VND');
      buffer.writeln(
          '- Last month expense: ${AppFormatters.number(expenseLastMonth)} VND');
      final diffExpense = expenseThisMonth - expenseLastMonth;
      buffer.writeln(
          '- Expense change: ${diffExpense >= 0 ? 'Increased +' : 'Decreased '}${AppFormatters.number(diffExpense.abs())} VND');
      buffer.writeln(
          '- 3-month average monthly savings: ${AppFormatters.number(averageMonthlySavings)} VND/month');

      // 3. Category breakdown
      buffer.writeln('\n3. THIS MONTH SPENDING BY CATEGORY:');
      final sortedCatEntries = currentExpenseByCat.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      for (final entry in sortedCatEntries) {
        final cat = categories.firstWhere(
          (c) => c.categoryId == entry.key,
          orElse: () => Category(
              categoryId: entry.key,
              userId: '',
              name: 'Other',
              type: 'expense',
              icon: '',
              color: 0),
        );
        final share = expenseThisMonth > 0
            ? (entry.value / expenseThisMonth * 100).round()
            : 0;
        final lastVal = lastExpenseByCat[entry.key] ?? 0;
        final diff = entry.value - lastVal;
        final diffStr = lastVal > 0
            ? ' (vs last month: ${diff >= 0 ? '+' : ''}${((diff / lastVal) * 100).round()}%)'
            : ' (no spending last month)';
        final displayCatName = CategoryLocalizationHelper.localizeName(cat.name);
        buffer.writeln(
            '- $displayCatName: ${AppFormatters.number(entry.value)} VND ($share% of total)$diffStr');
      }

      // 4. Budget status
      final nearLimitPctThreshold =
          (heuristics.budgetNearLimitRatio * 100).round();
      buffer.writeln('\n4. THIS MONTH BUDGET STATUS:');
      if (budgets.isEmpty) {
        buffer.writeln('- The user has not set up any budgets for this month.');
      } else {
        for (final b in budgets) {
          final spent = currentExpenseByCat[b.categoryId] ?? 0;
          final percent = b.limit > 0 ? (spent / b.limit * 100).round() : 0;
          final cat = categories.firstWhere(
            (c) => c.categoryId == b.categoryId,
            orElse: () => Category(
                categoryId: b.categoryId,
                userId: '',
                name: 'Other',
                type: 'expense',
                icon: '',
                color: 0),
          );
          final status = spent > b.limit
              ? '⚠️ OVER BUDGET (+${AppFormatters.number(spent - b.limit)} VND)'
              : (percent >= nearLimitPctThreshold
                  ? '⚡ NEAR LIMIT ($percent%)'
                  : 'Safe ($percent%)');
          final displayCatName = CategoryLocalizationHelper.localizeName(cat.name);
          buffer.writeln(
              '- $displayCatName: spent ${AppFormatters.number(spent)}/${AppFormatters.number(b.limit)} VND → $status');
        }
      }

      // 5. Saving goals
      buffer.writeln('\n5. SAVING GOAL PROGRESS:');
      if (savingGoals.isEmpty) {
        buffer.writeln('- The user does not have any active saving goals.');
      } else {
        for (final g in savingGoals) {
          final percent = (g.percentComplete * 100).round();
          final remaining = math.max(0.0, g.targetAmount - g.savedAmount);
          buffer.writeln(
              '- "${g.name}": Saved ${AppFormatters.number(g.savedAmount)}/${AppFormatters.number(g.targetAmount)} VND ($percent%), short ${AppFormatters.number(remaining)} VND, requires ${AppFormatters.number(g.monthlyRequired)} VND/month over ${g.months} months.');
        }
      }

      // 6. Detected issues
      buffer.writeln('\n6. QUANTITATIVE FINANCIAL ALERTS:');
      if (issues.isEmpty) {
        buffer.writeln('- No critical anomalies detected.');
      } else {
        for (final issue in issues) {
          buffer.writeln(
              '- [${issue.severity.name.toUpperCase()}] ${issue.title}: ${issue.rootCause}. Impact: ${issue.impact}. Recommendation: ${issue.recommendation}');
        }
      }

      // 7. Active plan
      if (activePlan != null) {
        final exec = _analyticsService.evaluatePlanExecution(
          plan: activePlan,
          targetMonthTx: currentMonthTx,
          referenceToday: now,
        );
        buffer.writeln(
            '\n7. COMMITTED MONTHLY FINANCIAL PLAN (${activePlan.targetMonth} - Status: ${activePlan.status.name}, Revision v${activePlan.revision}):');
        buffer.writeln(
            '- Plan reference income: ${AppFormatters.number(activePlan.referenceIncome)} VND');
        buffer.writeln(
            '- Essential expense cap: ${AppFormatters.number(activePlan.essentialExpenseCap)} VND | Flexible expense cap: ${AppFormatters.number(activePlan.flexibleExpenseCap)} VND');
        buffer.writeln(
            '- Monthly saving target: ${AppFormatters.number(activePlan.targetSavingAmount)} VND (Actual saved: ${AppFormatters.number(exec.effectiveMonthlySaved)} VND, deposited to goals: ${AppFormatters.number(exec.netGoalContributions)} VND, unallocated wallet surplus: ${AppFormatters.number(exec.unallocatedWalletSurplus)} VND)');
        buffer.writeln(
            '- Composite plan adherence score: ${exec.overallAdherenceScore.round()}/100 (${exec.onTrackCategoryCount}/${exec.categoryStatuses.length} categories on track)');
      }

      return buffer.toString();
    }

    buffer.writeln('=== DỮ LIỆU TÀI CHÍNH THỰC TẾ CỦA NGƯỜI DÙNG ===');
    buffer.writeln('- Người dùng: ${_sanitizeDisplayName(userProfile?.name)}');
    if (effectiveDeclared > 0) {
      buffer.writeln(
          '- Thu nhập kỳ vọng khai báo trong hồ sơ: ${AppFormatters.number(effectiveDeclared)} đ/tháng (Lưu ý AI: Dùng làm tham chiếu cơ sở cho quy tắc 50/30/20 hoặc lập kế hoạch, KHÔNG tự cộng vào số dư thực tế hay tổng thu giao dịch)');
    }
    buffer.writeln('- Thời điểm phân tích: Ngày $dayOfMonth tháng $monthStr');
    buffer.writeln('- Tổng số giao dịch đã ghi nhận: $totalTxCount giao dịch');
    if (sufficiency != null) {
      buffer.writeln(
          '- Cấp độ dữ liệu (${sufficiency.tier.name}): ${sufficiency.limitationNote}');
    }

    if (isEmptyData) {
      buffer.writeln('\n[TRẠNG THÁI DỮ LIỆU]: CHƯA CÓ GIAO DỊCH NÀO.');
      buffer.writeln(
          'Yêu cầu AI: Nhắc nhở người dùng thêm giao dịch thu và chi để có dữ liệu phân tích.');
      return buffer.toString();
    }

    if (!hasSufficientData) {
      buffer.writeln(
          '\n[TRẠNG THÁI DỮ LIỆU]: DỮ LIỆU HẠN CHẾ ($totalTxCount giao dịch).');
      buffer.writeln(
          'Yêu cầu AI: Khi trả lời, nêu rõ dữ liệu mới chỉ ghi nhận trong thời gian ngắn, chưa đủ để kết luận xu hướng dài hạn.');
    }

    // 1. Chỉ số tháng hiện tại
    buffer.writeln('\n1. TỔNG QUAN THÁNG NÀY ($monthStr):');
    buffer
        .writeln('- Tổng thu nhập: ${AppFormatters.number(incomeThisMonth)} đ');
    buffer.writeln(
        '- Tổng chi tiêu: ${AppFormatters.number(expenseThisMonth)} đ');
    buffer.writeln(
        '- Dòng tiền ròng (Thu - Chi): ${netCashFlow >= 0 ? '+' : ''}${AppFormatters.number(netCashFlow)} đ (${netCashFlow >= 0 ? 'DƯ' : 'THÂM HỤT'})');
    buffer.writeln('- Tỷ lệ tiết kiệm: $savingsRate%');
    buffer.writeln(
        '- Tổng số dư các ví khả dụng: ${AppFormatters.number(totalActiveBalance)} đ');

    // 2. So sánh với tháng trước
    buffer.writeln('\n2. SO SÁNH VỚI THÁNG TRƯỚC:');
    buffer.writeln(
        '- Thu nhập tháng trước: ${AppFormatters.number(incomeLastMonth)} đ');
    buffer.writeln(
        '- Chi tiêu tháng trước: ${AppFormatters.number(expenseLastMonth)} đ');
    final diffExpense = expenseThisMonth - expenseLastMonth;
    buffer.writeln(
        '- Biến động chi tiêu: ${diffExpense >= 0 ? 'Tăng +' : 'Giảm '}${AppFormatters.number(diffExpense.abs())} đ');
    buffer.writeln(
        '- Mức tiết kiệm trung bình 3 tháng gần nhất: ${AppFormatters.number(averageMonthlySavings)} đ/tháng');

    // 3. Chi tiêu chi tiết theo danh mục tháng này
    buffer.writeln('\n3. CHI TIÊU THEO DANH MỤC THÁNG NÀY:');
    final sortedCatEntries = currentExpenseByCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in sortedCatEntries) {
      final cat = categories.firstWhere(
        (c) => c.categoryId == entry.key,
        orElse: () => Category(
            categoryId: entry.key,
            userId: '',
            name: 'Khác',
            type: 'expense',
            icon: '',
            color: 0),
      );
      final share = expenseThisMonth > 0
          ? (entry.value / expenseThisMonth * 100).round()
          : 0;
      final lastVal = lastExpenseByCat[entry.key] ?? 0;
      final diff = entry.value - lastVal;
      final diffStr = lastVal > 0
          ? ' (so tháng trước: ${diff >= 0 ? '+' : ''}${((diff / lastVal) * 100).round()}%)'
          : ' (tháng trước không chi)';
      final displayCatName = CategoryLocalizationHelper.localizeName(cat.name);
      buffer.writeln(
          '- $displayCatName: ${AppFormatters.number(entry.value)} đ ($share% tổng chi)$diffStr');
    }

    // 4. Tình trạng Ngân sách
    final nearLimitPctThreshold =
        (heuristics.budgetNearLimitRatio * 100).round();
    buffer.writeln('\n4. TÌNH TRẠNG NGÂN SÁCH THÁNG NÀY:');
    if (budgets.isEmpty) {
      buffer.writeln('- Người dùng chưa thiết lập ngân sách cho tháng này.');
    } else {
      for (final b in budgets) {
        final spent = currentExpenseByCat[b.categoryId] ?? 0;
        final percent = b.limit > 0 ? (spent / b.limit * 100).round() : 0;
        final cat = categories.firstWhere(
          (c) => c.categoryId == b.categoryId,
          orElse: () => Category(
              categoryId: b.categoryId,
              userId: '',
              name: 'Khác',
              type: 'expense',
              icon: '',
              color: 0),
        );
        final status = spent > b.limit
            ? '⚠️ VƯỢT NGÂN SÁCH (+${AppFormatters.number(spent - b.limit)} đ)'
            : (percent >= nearLimitPctThreshold
                ? '⚡ SẮP CHẠM HẠN MỨC ($percent%)'
                : 'An toàn ($percent%)');
        final displayCatName = CategoryLocalizationHelper.localizeName(cat.name);
        buffer.writeln(
            '- $displayCatName: đã chi ${AppFormatters.number(spent)}/${AppFormatters.number(b.limit)} đ → $status');
      }
    }

    // 5. Mục tiêu tiết kiệm
    buffer.writeln('\n5. TIẾN ĐỘ MỤC TIÊU TIẾT KIỆM:');
    if (savingGoals.isEmpty) {
      buffer.writeln('- Người dùng chưa có mục tiêu tiết kiệm nào.');
    } else {
      for (final g in savingGoals) {
        final percent = (g.percentComplete * 100).round();
        final remaining = math.max(0.0, g.targetAmount - g.savedAmount);
        buffer.writeln(
            '- "${g.name}": Đã tích lũy ${AppFormatters.number(g.savedAmount)}/${AppFormatters.number(g.targetAmount)} đ ($percent%), còn thiếu ${AppFormatters.number(remaining)} đ, cần ${AppFormatters.number(g.monthlyRequired)} đ/tháng trong ${g.months} tháng.');
      }
    }

    // 6. Các vấn đề tài chính định lượng đã phát hiện
    buffer.writeln('\n6. CẢNH BÁO VẤN ĐỀ TÀI CHÍNH TỰ ĐỘNG PHÁT HIỆN:');
    if (issues.isEmpty) {
      buffer.writeln('- Không có cảnh báo bất thường nghiêm trọng.');
    } else {
      for (final issue in issues) {
        buffer.writeln(
            '- [${issue.severity.name.toUpperCase()}] ${issue.title}: ${issue.rootCause}. Tác động: ${issue.impact}. Đề xuất: ${issue.recommendation}');
      }
    }

    // 7. Kế hoạch tài chính tháng đã cam kết (nếu có)
    if (activePlan != null) {
      final exec = _analyticsService.evaluatePlanExecution(
        plan: activePlan,
        targetMonthTx: currentMonthTx,
        referenceToday: now,
      );
      buffer.writeln(
          '\n7. KẾ HOẠCH TÀI CHÍNH THÁNG ĐÃ CAM KẾT (${activePlan.targetMonth} - Trạng thái: ${activePlan.status.name}, Phiên bản v${activePlan.revision}):');
      buffer.writeln(
          '- Thu nhập tham chiếu kế hoạch: ${AppFormatters.number(activePlan.referenceIncome)} đ');
      buffer.writeln(
          '- Trần chi phí Thiết yếu: ${AppFormatters.number(activePlan.essentialExpenseCap)} đ | Trần chi phí Linh hoạt: ${AppFormatters.number(activePlan.flexibleExpenseCap)} đ');
      buffer.writeln(
          '- Mục tiêu tiết kiệm tháng: ${AppFormatters.number(activePlan.targetSavingAmount)} đ (Thực đạt: ${AppFormatters.number(exec.effectiveMonthlySaved)} đ, trong đó đã nạp vào mục tiêu: ${AppFormatters.number(exec.netGoalContributions)} đ, thặng dư còn trong ví: ${AppFormatters.number(exec.unallocatedWalletSurplus)} đ)');
      buffer.writeln(
          '- Điểm tuân thủ kế hoạch tổng hợp: ${exec.overallAdherenceScore.round()}/100 (${exec.onTrackCategoryCount}/${exec.categoryStatuses.length} danh mục đúng kế hoạch)');
    }

    return buffer.toString();
  }

  /// Trích xuất thẻ Insight phù hợp từ câu trả lời của AI hoặc câu hỏi người dùng
  ChatInsightCardData? detectInsightCard({
    required String question,
    required String answer,
    required FinancialChatContext context,
    required List<Category> categories,
  }) {
    if (context.isEmptyData) {
      return ChatInsightCardData(
        type: ChatInsightCardType.emptyDataPrompt,
        title: AppLocalizations.tr('svc_chat_empty_title'),
        subtitle: AppLocalizations.tr('svc_chat_empty_sub'),
        primaryMetric: AppLocalizations.tr('ai_chat_empty_card_metric'),
        actionLabel: AppLocalizations.tr('ai_chat_empty_card_action'),
      );
    }

    final lowerQ = question.toLowerCase();
    final lowerA = answer.toLowerCase();

    // 0. Bỏ qua câu hỏi chào hỏi xã giao hoặc giới thiệu chung
    final isGreeting = lowerQ.startsWith('chào') ||
        lowerQ.startsWith('hello') ||
        lowerQ.startsWith('hi') ||
        lowerQ == 'bạn là ai' ||
        lowerQ == 'bạn là ai?' ||
        lowerQ == 'who are you' ||
        lowerQ == 'who are you?' ||
        lowerQ.contains('bạn có thể làm gì') ||
        lowerQ.contains('bạn làm được gì') ||
        lowerQ.contains('giới thiệu') ||
        lowerQ.contains('what can you do') ||
        lowerQ.contains('introduce');
    if (isGreeting) {
      return null;
    }

    // 1. Kiểm tra nếu câu hỏi về một danh mục cụ thể (hỗ trợ cả tiếng Việt & tiếng Anh)
    Category? matchedCategory;
    for (final cat in categories) {
      final variants = CategoryLocalizationHelper.allSearchVariants(cat.name);
      if (variants.any((v) => lowerQ.contains(v.toLowerCase()))) {
        matchedCategory = cat;
        break;
      }
    }

    if (matchedCategory != null) {
      final displayCatName =
          CategoryLocalizationHelper.localizeName(matchedCategory.name);
      // Tìm xem có ngân sách cho danh mục này không
      final catBudget = context.budgets.cast<Budget?>().firstWhere(
            (b) => b?.categoryId == matchedCategory!.categoryId,
            orElse: () => null,
          );
      final spentAmount =
          context.currentExpenseByCat[matchedCategory.categoryId] ?? 0.0;

      if (catBudget != null) {
        final isOver = spentAmount > catBudget.limit;
        return ChatInsightCardData(
          type: ChatInsightCardType.budgetOverrun,
          title: isOver
              ? AppLocalizations.tr('ai_chat_budget_alert_title',
                  params: {'category': displayCatName})
              : AppLocalizations.tr('svc_chat_card_budget_title',
                  params: {'cat': displayCatName}),
          subtitle: isOver
              ? AppLocalizations.tr('ai_chat_budget_over_sub')
              : AppLocalizations.tr('svc_chat_card_budget_sub', params: {
                  'spent': AppFormatters.compactCurrency(spentAmount),
                  'limit': AppFormatters.compactCurrency(catBudget.limit),
                }),
          primaryMetric: AppLocalizations.tr('ai_chat_budget_limit_metric',
              params: {'amount': AppFormatters.compactCurrency(catBudget.limit)}),
          secondaryMetric: isOver ? AppLocalizations.tr('svc_chat_card_ctrl') : AppLocalizations.tr('svc_chat_card_safe'),
          progressPercent:
              catBudget.limit > 0 ? (spentAmount / catBudget.limit) : 0,
          actionLabel: AppLocalizations.tr('ai_chat_view_budget_btn'),
          targetId: catBudget.budgetId,
          isAlert: isOver,
        );
      } else if (spentAmount > 0) {
        return ChatInsightCardData(
          type: ChatInsightCardType.cashFlowSnapshot,
          title: AppLocalizations.tr('svc_chat_card_cat_spend',
              params: {'cat': displayCatName}),
          subtitle: AppLocalizations.tr('svc_chat_card_cat_spend_sub',
              params: {'amt': AppFormatters.compactCurrency(spentAmount)}),
          primaryMetric: '-${AppFormatters.compactCurrency(spentAmount)}',
          actionLabel: AppLocalizations.tr('svc_chat_view_tx'),
          targetId: matchedCategory.categoryId,
        );
      }
    }

    // 2. Kiểm tra nếu câu hỏi hoặc câu trả lời đề cập đến một MỤC TIÊU TIẾT KIỆM CỤ THỂ
    // (Phân biệt với lời khuyên tiết kiệm chung như "làm sao để tiết kiệm", "cách tiết kiệm")
    final isGeneralAdvice = lowerQ.contains('làm sao để tiết kiệm') ||
        lowerQ.contains('cách tiết kiệm') ||
        lowerQ.contains('tư vấn tiết kiệm') ||
        lowerQ.contains('mẹo tiết kiệm') ||
        lowerQ.contains('cắt giảm chi tiêu') ||
        lowerQ.contains('làm thế nào để tiết kiệm') ||
        lowerQ.contains('how to save') ||
        lowerQ.contains('saving tips') ||
        lowerQ.contains('save more') ||
        lowerQ.contains('cut spending') ||
        lowerQ.contains('cut back') ||
        lowerQ.contains('reduce spending');

    if (!isGeneralAdvice && context.savingGoals.isNotEmpty) {
      // 2a. Tìm mục tiêu trùng tên được nhắc đến trong câu hỏi hoặc câu trả lời
      SavingGoal? matchedGoal;
      for (final g in context.savingGoals) {
        final gNameLower = g.name.toLowerCase();
        if (lowerQ.contains(gNameLower) || lowerA.contains(gNameLower)) {
          matchedGoal = g;
          break;
        }
      }

      // 2b. Hoặc nếu người dùng hỏi trực tiếp về tiến độ mục tiêu tiết kiệm
      final isAskingGoalStatus = lowerQ.contains('tiến độ mục tiêu') ||
          lowerQ.contains('các mục tiêu') ||
          lowerQ.contains('mục tiêu tiết kiệm của tôi') ||
          lowerQ.contains('mục tiêu của tôi') ||
          lowerQ.contains('goal progress') ||
          lowerQ.contains('my goals') ||
          lowerQ.contains('saving goal') ||
          lowerQ.contains('savings goal') ||
          lowerQ.contains('achieve my goal') ||
          lowerQ.contains('on track');

      if (matchedGoal != null || isAskingGoalStatus) {
        final g = matchedGoal ?? context.savingGoals.first;
        return ChatInsightCardData(
          type: ChatInsightCardType.savingGoalProgress,
          title: AppLocalizations.tr('svc_chat_goal_title',
              params: {'goal': g.name}),
          subtitle: AppLocalizations.tr('svc_chat_goal_sub',
              params: {'amt': AppFormatters.compactCurrency(g.monthlyRequired)}),
          primaryMetric:
              '${AppFormatters.compactCurrency(g.savedAmount)} / ${AppFormatters.compactCurrency(g.targetAmount)}',
          progressPercent: g.percentComplete,
          actionLabel: AppLocalizations.tr('svc_chat_view_goal'),
          targetId: g.goalId,
        );
      }
    }

    // 3. Nếu câu hỏi hoặc câu trả lời liên quan đến vượt ngân sách / hạn mức
    if (lowerQ.contains('ngân sách') ||
        lowerQ.contains('hạn mức') ||
        lowerA.contains('vượt ngân sách') ||
        lowerQ.contains('budget') ||
        lowerQ.contains('limit') ||
        lowerA.contains('over budget') ||
        lowerA.contains('exceeded')) {
      if (context.overBudgets.isNotEmpty) {
        final b = context.overBudgets.first;
        final cat = categories.firstWhere(
          (c) => c.categoryId == b.categoryId,
          orElse: () => Category(
              categoryId: b.categoryId,
              userId: '',
              name: AppLocalizations.tr('ai_rep_default_cat'),
              type: 'expense',
              icon: '',
              color: 0),
        );
        return ChatInsightCardData(
          type: ChatInsightCardType.budgetOverrun,
          title: AppLocalizations.tr('ai_chat_budget_alert_title',
              params: {'category': CategoryLocalizationHelper.localizeName(cat.name)}),
          subtitle: AppLocalizations.tr('ai_chat_budget_over_sub'),
          primaryMetric: AppLocalizations.tr('ai_chat_budget_limit_metric',
              params: {'amount': AppFormatters.compactCurrency(b.limit)}),
          secondaryMetric: AppLocalizations.tr('svc_chat_card_ctrl'),
          actionLabel: AppLocalizations.tr('ai_chat_view_budget_btn'),
          targetId: b.budgetId,
          isAlert: true,
        );
      } else if (context.budgets.isNotEmpty) {
        return ChatInsightCardData(
          type: ChatInsightCardType.budgetOverrun,
          title: AppLocalizations.tr('svc_chat_budgets_all_title'),
          subtitle: AppLocalizations.tr('svc_chat_budgets_all_sub'),
          primaryMetric: AppLocalizations.tr('svc_chat_budgets_active_count',
              params: {'count': '${context.budgets.length}'}),
          secondaryMetric: AppLocalizations.tr('svc_chat_card_safe'),
          actionLabel: AppLocalizations.tr('ai_chat_view_budget_btn'),
          isAlert: false,
        );
      }
    }

    // 4. Nếu câu hỏi liên quan đến tổng quan, dòng tiền hoặc thu chi tháng này
    final isCashFlowQuery = lowerQ.contains('tháng này') ||
        lowerQ.contains('dòng tiền') ||
        lowerQ.contains('tổng quan') ||
        lowerQ.contains('thu nhập') ||
        (lowerQ.contains('chi tiêu') && !isGeneralAdvice) ||
        lowerQ.contains('this month') ||
        lowerQ.contains('cash flow') ||
        lowerQ.contains('overview') ||
        lowerQ.contains('income') ||
        ((lowerQ.contains('spending') || lowerQ.contains('expense')) &&
            !isGeneralAdvice);

    if (isCashFlowQuery) {
      return ChatInsightCardData(
        type: ChatInsightCardType.cashFlowSnapshot,
        title: AppLocalizations.tr('svc_chat_cf_title'),
        subtitle: AppLocalizations.tr('svc_chat_cf_sub', params: {
          'inc': AppFormatters.compactCurrency(context.incomeThisMonth),
          'exp': AppFormatters.compactCurrency(context.expenseThisMonth),
        }),
        primaryMetric:
            '${context.netCashFlow >= 0 ? '+' : ''}${AppFormatters.compactCurrency(context.netCashFlow)}',
        secondaryMetric: AppLocalizations.tr('svc_chat_cf_save',
            params: {'pct': '${context.savingsRate}'}),
        actionLabel: AppLocalizations.tr('svc_chat_view_tx'),
      );
    }

    return null;
  }
}
