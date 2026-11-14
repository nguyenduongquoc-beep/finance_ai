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
import '../services/ai_config_sync_service.dart';
import '../services/firestore_service.dart';
import '../services/financial_analytics_service.dart';
import '../services/financial_context_revision_tracker.dart';
import '../utils/formatters.dart';

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

  const ChatInsightCardData({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.primaryMetric,
    this.secondaryMetric,
    this.progressPercent,
    required this.actionLabel,
    this.targetId,
  });

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
    };
  }

  factory ChatInsightCardData.fromMap(Map<String, dynamic> map) {
    final typeName = map['type'] as String? ?? 'none';
    final cardType = ChatInsightCardType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => ChatInsightCardType.none,
    );
    return ChatInsightCardData(
      type: cardType,
      title: map['title'] ?? '',
      subtitle: map['subtitle'] ?? '',
      primaryMetric: map['primaryMetric'] ?? '',
      secondaryMetric: map['secondaryMetric'],
      progressPercent: (map['progressPercent'] as num?)?.toDouble(),
      actionLabel: map['actionLabel'] ?? 'Xem chi tiết',
      targetId: map['targetId'],
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
      _heuristicsOverride ?? AiConfigSyncService.instance.currentHeuristics;

  Future<FinancialChatContext> buildContext(String userId) async {
    await AiConfigSyncService.instance.syncPublishedConfigsIfNeeded();
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

    // 8. Tạo Prompts gợi ý động theo ngữ cảnh thực tế + gợi ý Admin (nếu có)
    final customFromConfig = AiConfigSyncService
        .instance.currentAiRuntime.customSuggestedChatPrompts.values
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
      customSuggestedPrompts: customSuggestedPrompts ?? customFromConfig,
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
      prompts.add(const DynamicPromptChip(
        label: 'Làm thế nào để bắt đầu quản lý tài chính?',
        category: 'featured',
        icon: '💡',
      ));
      prompts.add(const DynamicPromptChip(
        label: 'Ứng dụng có thể giúp gì cho tôi?',
        category: 'overview',
      ));
      prompts.add(const DynamicPromptChip(
        label: 'Nguyên tắc phân bổ thu nhập 50/30/20 là gì?',
        category: 'saving',
      ));
      return prompts;
    }

    // 1. Nhóm Nổi Bật / Cảnh Báo theo tình trạng thực tế
    if (overBudgets.isNotEmpty) {
      prompts.add(const DynamicPromptChip(
        label: 'Tôi đang vượt ngân sách ở đâu?',
        category: 'featured',
        isAlert: true,
        icon: '⚠️',
      ));
    }

    if (netCashFlow < 0) {
      prompts.add(const DynamicPromptChip(
        label: 'Tại sao tháng này tôi chi nhiều hơn thu?',
        category: 'featured',
        isAlert: true,
        icon: '⚠️',
      ));
    }

    if (issues.any((i) => i.category == IssueCategory.spike)) {
      prompts.add(const DynamicPromptChip(
        label: 'Khoản chi nào đang tăng bất thường?',
        category: 'featured',
        isAlert: true,
        icon: '📈',
      ));
    }

    if (savingGoals.isNotEmpty) {
      prompts.add(const DynamicPromptChip(
        label: 'Tôi có thể đạt mục tiêu đúng hạn không?',
        category: 'featured',
        icon: '🎯',
      ));
    }

    // Luôn bổ sung các câu hỏi chiến lược giá trị cao trong nhóm Nổi bật
    prompts.add(const DynamicPromptChip(
      label: 'Tôi đang có vấn đề tài chính nào cần chú ý?',
      category: 'featured',
      icon: '🔥',
    ));
    prompts.add(const DynamicPromptChip(
      label: 'Tôi nên cải thiện khoản chi nào trước?',
      category: 'featured',
      icon: '💡',
    ));
    prompts.add(const DynamicPromptChip(
      label: 'Làm thế nào để tôi tiết kiệm thêm mỗi tháng?',
      category: 'featured',
      icon: '💎',
    ));
    prompts.add(const DynamicPromptChip(
      label: 'Mục tiêu tài chính hiện tại có khả thi không?',
      category: 'featured',
      icon: '🎯',
    ));

    // 2. Nhóm Tổng quan
    prompts.add(const DynamicPromptChip(
      label: 'Tình hình tài chính tháng này của tôi thế nào?',
      category: 'overview',
    ));
    prompts.add(const DynamicPromptChip(
      label: 'Thu nhập và chi tiêu của tôi đang thay đổi ra sao?',
      category: 'overview',
    ));
    prompts.add(const DynamicPromptChip(
      label: 'Tôi còn lại bao nhiêu tiền trong tháng này?',
      category: 'overview',
    ));

    // 3. Nhóm Chi tiêu
    prompts.add(const DynamicPromptChip(
      label: 'Tôi đang tiêu nhiều nhất vào đâu?',
      category: 'expense',
    ));
    prompts.add(const DynamicPromptChip(
      label: 'Khoản chi nào tôi có thể cắt giảm?',
      category: 'expense',
    ));
    prompts.add(const DynamicPromptChip(
      label: 'Tại sao tháng này tôi chi nhiều hơn tháng trước?',
      category: 'expense',
    ));

    // 4. Nhóm Ngân sách
    prompts.add(const DynamicPromptChip(
      label: 'Tôi đang sử dụng ngân sách như thế nào?',
      category: 'budget',
    ));
    prompts.add(const DynamicPromptChip(
      label: 'Nếu cứ chi như hiện tại thì có đủ đến cuối tháng không?',
      category: 'budget',
    ));

    // 5. Nhóm Tiết kiệm & Mục tiêu
    prompts.add(const DynamicPromptChip(
      label: 'Tôi có thể tiết kiệm thêm bao nhiêu mỗi tháng?',
      category: 'saving',
    ));
    prompts.add(const DynamicPromptChip(
      label: 'Tôi nên giảm khoản nào để tiết kiệm thêm 2 triệu?',
      category: 'saving',
    ));
    prompts.add(const DynamicPromptChip(
      label: 'Tôi muốn tiết kiệm 10 triệu trong 3 tháng có khả thi không?',
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

  /// Lọc PII khỏi tên hiển thị (không bao giờ gửi email, SĐT hoặc UID cho Gemini)
  static String _sanitizeDisplayName(String? rawName) {
    if (rawName == null || rawName.trim().isEmpty) return 'Khách';
    var cleaned = rawName.trim();
    if (cleaned.contains('@')) {
      cleaned = cleaned.split('@').first.trim();
    }
    cleaned = cleaned.replaceAll(RegExp(r'\b\d{9,12}\b'), '[ẩn]');
    if (cleaned.isEmpty) return 'Khách';
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
      buffer.writeln(
          '- ${cat.name}: ${AppFormatters.number(entry.value)} đ ($share% tổng chi)$diffStr');
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
        buffer.writeln(
            '- ${cat.name}: đã chi ${AppFormatters.number(spent)}/${AppFormatters.number(b.limit)} đ → $status');
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
      return const ChatInsightCardData(
        type: ChatInsightCardType.emptyDataPrompt,
        title: 'Bắt đầu quản lý tài chính',
        subtitle: 'Thêm giao dịch đầu tiên để AI có thể phân tích cho bạn',
        primaryMetric: '0 giao dịch',
        actionLabel: 'Thêm giao dịch ngay',
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
        lowerQ.contains('bạn có thể làm gì') ||
        lowerQ.contains('bạn làm được gì') ||
        lowerQ.contains('giới thiệu');
    if (isGreeting) {
      return null;
    }

    // 1. Kiểm tra nếu câu hỏi về một danh mục cụ thể (VD: "ăn uống", "mua sắm", "di chuyển"...)
    Category? matchedCategory;
    for (final cat in categories) {
      final catNameLower = cat.name.toLowerCase();
      if (lowerQ.contains(catNameLower)) {
        matchedCategory = cat;
        break;
      }
    }

    if (matchedCategory != null) {
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
              ? 'Cảnh báo: ${matchedCategory.name}'
              : 'Ngân sách: ${matchedCategory.name}',
          subtitle: isOver
              ? 'Đã vượt hạn mức ngân sách tháng này'
              : 'Đã chi ${AppFormatters.compactCurrency(spentAmount)} / Hạn mức ${AppFormatters.compactCurrency(catBudget.limit)}',
          primaryMetric:
              'Hạn mức: ${AppFormatters.compactCurrency(catBudget.limit)}',
          secondaryMetric: isOver ? 'Cần kiểm soát' : 'Đang an toàn',
          progressPercent:
              catBudget.limit > 0 ? (spentAmount / catBudget.limit) : 0,
          actionLabel: 'Xem ngân sách',
          targetId: catBudget.budgetId,
        );
      } else if (spentAmount > 0) {
        return ChatInsightCardData(
          type: ChatInsightCardType.cashFlowSnapshot,
          title: 'Chi tiêu: ${matchedCategory.name}',
          subtitle:
              'Tổng chi tháng này: ${AppFormatters.compactCurrency(spentAmount)}',
          primaryMetric: '-${AppFormatters.compactCurrency(spentAmount)}',
          actionLabel: 'Xem giao dịch',
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
        lowerQ.contains('làm thế nào để tiết kiệm');

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
          lowerQ.contains('mục tiêu của tôi');

      if (matchedGoal != null || isAskingGoalStatus) {
        final g = matchedGoal ?? context.savingGoals.first;
        return ChatInsightCardData(
          type: ChatInsightCardType.savingGoalProgress,
          title: 'Mục tiêu: ${g.name}',
          subtitle:
              'Cần tiết kiệm ${AppFormatters.compactCurrency(g.monthlyRequired)}/tháng',
          primaryMetric:
              '${AppFormatters.compactCurrency(g.savedAmount)} / ${AppFormatters.compactCurrency(g.targetAmount)}',
          progressPercent: g.percentComplete,
          actionLabel: 'Xem mục tiêu',
          targetId: g.goalId,
        );
      }
    }

    // 3. Nếu câu hỏi hoặc câu trả lời liên quan đến vượt ngân sách / hạn mức
    if (lowerQ.contains('ngân sách') ||
        lowerQ.contains('hạn mức') ||
        lowerA.contains('vượt ngân sách')) {
      if (context.overBudgets.isNotEmpty) {
        final b = context.overBudgets.first;
        final cat = categories.firstWhere(
          (c) => c.categoryId == b.categoryId,
          orElse: () => Category(
              categoryId: b.categoryId,
              userId: '',
              name: 'Danh mục',
              type: 'expense',
              icon: '',
              color: 0),
        );
        return ChatInsightCardData(
          type: ChatInsightCardType.budgetOverrun,
          title: 'Cảnh báo: ${cat.name}',
          subtitle: 'Đã vượt hạn mức ngân sách tháng này',
          primaryMetric: 'Hạn mức: ${AppFormatters.compactCurrency(b.limit)}',
          secondaryMetric: 'Cần kiểm soát',
          actionLabel: 'Xem ngân sách',
          targetId: b.budgetId,
        );
      } else if (context.budgets.isNotEmpty) {
        return ChatInsightCardData(
          type: ChatInsightCardType.budgetOverrun,
          title: 'Ngân sách tháng này',
          subtitle: 'Tất cả ngân sách đang trong tầm kiểm soát',
          primaryMetric: '${context.budgets.length} ngân sách đang hoạt động',
          actionLabel: 'Xem ngân sách',
        );
      }
    }

    // 4. Nếu câu hỏi liên quan đến tổng quan, dòng tiền hoặc thu chi tháng này
    final isCashFlowQuery = lowerQ.contains('tháng này') ||
        lowerQ.contains('dòng tiền') ||
        lowerQ.contains('tổng quan') ||
        lowerQ.contains('thu nhập') ||
        (lowerQ.contains('chi tiêu') && !isGeneralAdvice);

    if (isCashFlowQuery) {
      return ChatInsightCardData(
        type: ChatInsightCardType.cashFlowSnapshot,
        title: 'Dòng tiền tháng này',
        subtitle:
            'Thu: +${AppFormatters.compactCurrency(context.incomeThisMonth)} • Chi: -${AppFormatters.compactCurrency(context.expenseThisMonth)}',
        primaryMetric:
            '${context.netCashFlow >= 0 ? '+' : ''}${AppFormatters.compactCurrency(context.netCashFlow)}',
        secondaryMetric: 'Tiết kiệm: ${context.savingsRate}%',
        actionLabel: 'Xem giao dịch',
      );
    }

    return null;
  }
}
