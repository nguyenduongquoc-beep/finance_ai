import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../models/financial_forecast_result.dart';
import '../../models/financial_issue.dart';
import '../../models/transaction_model.dart';
import '../../models/category_model.dart';
import '../../models/budget_model.dart';
import '../../models/wallet_model.dart';
import '../../models/user_model.dart';
import '../../models/recurring_transaction_model.dart';
import '../../models/saving_goal_model.dart';
import '../../services/firestore_service.dart';
import '../../services/ai_service.dart';
import '../../services/financial_analytics_service.dart';
import '../../services/financial_forecast_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_card.dart';
import '../../widgets/weekly_heatmap_card.dart';

/// ============================================================
/// AI FINANCIAL INSIGHTS SCREEN
/// 1. Điểm sức khỏe tài chính & Điểm mạnh / Yếu (Health Score)
/// 2. Phân tích Dòng tiền & Khả năng giữ lại (Net Cash Flow & Savings Rate)
/// 3. Phân tích Thu nhập & Độ ổn định (Income Analytics)
/// 4. Phát hiện vấn đề 4 bước: Vấn đề → Nguyên nhân → Tác động → Đề xuất
/// 5. Đánh giá Tính khả thi Mục tiêu Tiết kiệm (Savings Goal Feasibility)
/// 6. Kế hoạch Hành động Cụ thể Tháng tới (Action Plan)
/// 7. Cố vấn Tài chính AI từ Gemini (AI Financial Advisor)
/// 8. Nhịp độ chi tiêu theo tuần (Spending Rhythm Heatmap)
/// 9. Tra cứu Dự báo Số dư, Ngân sách & Bất thường (Chi tiết)
/// ============================================================
class AiInsightScreen extends StatefulWidget {
  const AiInsightScreen({super.key});

  @override
  State<AiInsightScreen> createState() => _AiInsightScreenState();
}

class _AiInsightScreenState extends State<AiInsightScreen> {
  final _aiService = AiService();
  final _firestoreService = FirestoreService();
  final _analyticsService = FinancialAnalyticsService();
  final _forecastService = FinancialForecastService();

  bool _isLoading = true;
  String? _errorMessage;

  FinancialInsightSummary? _forecastSummary;
  Map<String, List<int>> _weeklyHeatmap = {};

  // Gemini AI state
  bool _isLoadingAiExplanation = false;
  String? _aiExplanation;
  String? _aiErrorMessage;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  /// Tải dữ liệu toàn diện qua Future.wait và tính toán Dart thuần
  Future<void> _loadInsights() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();
    final monthStr = DateFormat('MM/yyyy').format(now);

    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    final m1Start = DateTime(now.year, now.month - 1, 1);
    final m1End = DateTime(now.year, now.month, 0, 23, 59, 59);

    final m2Start = DateTime(now.year, now.month - 2, 1);
    final m2End = DateTime(now.year, now.month - 1, 0, 23, 59, 59);

    final m3Start = DateTime(now.year, now.month - 3, 1);
    final m3End = DateTime(now.year, now.month - 2, 0, 23, 59, 59);

    final last30Days = now.subtract(const Duration(days: 30));

    try {
      final results = await Future.wait<dynamic>([
        _firestoreService.streamWallets(uid).first, // 0: List<Wallet>
        _firestoreService.streamCategories(uid).first, // 1: List<Category>
        _firestoreService
            .streamBudgets(uid, month: monthStr)
            .first, // 2: List<Budget>
        _firestoreService
            .streamTransactions(uid, from: monthStart, to: monthEnd)
            .first, // 3: Current month Tx
        _firestoreService
            .streamTransactions(uid, from: m1Start, to: m1End)
            .first, // 4: Month -1 Tx
        _firestoreService
            .streamTransactions(uid, from: m2Start, to: m2End)
            .first, // 5: Month -2 Tx
        _firestoreService
            .streamTransactions(uid, from: m3Start, to: m3End)
            .first, // 6: Month -3 Tx
        _firestoreService.getUserProfile(uid), // 7: AppUser?
        _firestoreService
            .streamTransactions(uid, from: last30Days)
            .first, // 8: Last 30 days Tx for heatmap
        _firestoreService
            .streamRecurringTransactions(uid)
            .first, // 9: Recurring schedules
        _firestoreService.streamSavingGoals(uid).first, // 10: Saving goals
      ]);

      final wallets = results[0] as List<Wallet>;
      final categories = results[1] as List<Category>;
      final currentBudgets = results[2] as List<Budget>;
      final currentMonthTx = results[3] as List<AppTransaction>;
      final m1Tx = results[4] as List<AppTransaction>;
      final m2Tx = results[5] as List<AppTransaction>;
      final m3Tx = results[6] as List<AppTransaction>;
      final userProfile = results[7] as AppUser?;
      final last30DaysTx = results[8] as List<AppTransaction>;
      final recurringSchedules =
          results[9] as List<RecurringTransactionSchedule>;
      final savingGoals = results[10] as List<SavingGoal>;

      final monthlyIncome = userProfile?.monthlyIncome ?? 0;

      // 1. Phân tích phát hiện vấn đề bằng Dart thuần
      final issues = _analyticsService.detectIssues(
        currentMonthTx: currentMonthTx,
        lastMonthTx: m1Tx,
        categories: categories,
        monthlyIncome: monthlyIncome,
      );

      // 2. Dự báo dòng tiền, thu nhập, ngân sách & mục tiêu bằng Dart thuần
      final summary = _forecastService.generateSummary(
        activeWallets: wallets,
        currentMonthBudgets: currentBudgets,
        categories: categories,
        currentMonthTx: currentMonthTx,
        preceding3MonthsTx: [m3Tx, m2Tx, m1Tx],
        monthlyIncome: monthlyIncome,
        issues: issues,
        savingGoals: savingGoals,
        recurringSchedules: recurringSchedules,
        refDate: now,
      );

      final heatmap =
          _analyticsService.computeWeeklyHeatmap(last30DaysTx, categories);

      if (!mounted) return;
      setState(() {
        _forecastSummary = summary;
        _weeklyHeatmap = heatmap;
        _isLoading = false;
      });

      // Lần đầu tải dữ liệu thành công -> Gọi Gemini cố vấn tài chính
      _fetchAiExplanation(summary);
    } catch (e, stackTrace) {
      debugPrint('AI Financial Insights Data Load error: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Không thể tải phân tích tài chính lúc này. Vui lòng kiểm tra kết nối.';
        _isLoading = false;
      });
    }
  }

  /// Gọi Gemini diễn giải số liệu
  Future<void> _fetchAiExplanation(FinancialInsightSummary summary) async {
    if (!mounted) return;
    setState(() {
      _isLoadingAiExplanation = true;
      _aiErrorMessage = null;
    });

    try {
      final explanation = await _aiService.explainFinancialInsights(summary);
      if (!mounted) return;
      setState(() {
        _aiExplanation = explanation;
        _isLoadingAiExplanation = false;
      });
    } catch (e) {
      debugPrint('Gemini explanation error: $e');
      if (!mounted) return;
      final msg = AiService.isNoNetworkException(e)
          ? 'Không có kết nối mạng.'
          : 'Chưa thể tải phân tích từ AI lúc này. Toàn bộ các chỉ số tài chính bên trên vẫn được tính chính xác từ dữ liệu của bạn.';
      setState(() {
        _aiErrorMessage = msg;
        _isLoadingAiExplanation = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.aiAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: AppColors.aiAccent,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            const Text('AI Financial Insights'),
          ],
        ),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Làm mới phân tích',
              onPressed: _loadInsights,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.aiAccent),
            const SizedBox(height: 16),
            Text(
              'Đang phân tích thu chi, dòng tiền & sức khỏe tài chính...',
              style: TextStyle(color: context.appTextSecondary),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null || _forecastSummary == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.expense, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Không có dữ liệu phân tích.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.appTextSecondary),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadInsights,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.aiAccent),
              ),
            ],
          ),
        ),
      );
    }

    final summary = _forecastSummary!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Điểm sức khỏe tài chính (Health Score & Strengths/Deductions)
        _buildHealthScoreSection(summary),
        const SizedBox(height: 16),

        // 2. Dòng tiền ròng & Tỷ lệ tiết kiệm (Net Cash Flow & Savings Rate)
        _buildCashFlowSection(summary.cashFlowAnalytics),
        const SizedBox(height: 16),

        // 3. Phân tích Cơ cấu Thu nhập & Độ ổn định (Income Analytics)
        _buildIncomeSection(summary.incomeAnalytics),
        const SizedBox(height: 16),

        // 4. Phát hiện Vấn đề Tài chính 4 bước (Vấn đề → Nguyên nhân → Tác động → Đề xuất)
        _buildIssuesSection(summary.issues),
        const SizedBox(height: 16),

        // 5. Đánh giá Tính khả thi Mục tiêu Tiết kiệm (Savings Goal Feasibility)
        if (summary.savingsGoalAssessment != null) ...[
          _buildSavingsGoalSection(summary.savingsGoalAssessment!),
          const SizedBox(height: 16),
        ],

        // 6. Kế hoạch Hành động Cụ thể Tháng tới (Action Plan)
        _buildActionPlanSection(summary.actionPlan),
        const SizedBox(height: 16),

        // 7. Nhận định Cố vấn AI từ Gemini (AI Financial Advisor)
        _buildAiExplanationSection(summary),
        const SizedBox(height: 16),

        // 8. Nhịp độ Chi tiêu Theo Tuần (Weekly Rhythm Heatmap)
        WeeklyHeatmapCard(heatmapData: _weeklyHeatmap),
        const SizedBox(height: 16),

        // 9. Chi tiết Dự báo Số dư, Ngân sách & Bất thường (Tra cứu bổ sung)
        _buildDetailedForecastSection(summary),
        const SizedBox(height: 24),
      ],
    );
  }

  // ============================================================
  // 1. ĐIỂM SỨC KHỎE TÀI CHÍNH CARD
  // ============================================================
  Widget _buildHealthScoreSection(FinancialInsightSummary summary) {
    final score = summary.healthScore;
    final Color scoreColor;
    final IconData scoreIcon;

    if (score >= 85) {
      scoreColor = AppColors.income;
      scoreIcon = Icons.sentiment_very_satisfied_rounded;
    } else if (score >= 70) {
      scoreColor = AppColors.primary;
      scoreIcon = Icons.sentiment_satisfied_rounded;
    } else if (score >= 50) {
      scoreColor = AppColors.warning;
      scoreIcon = Icons.sentiment_neutral_rounded;
    } else {
      scoreColor = AppColors.expense;
      scoreIcon = Icons.sentiment_very_dissatisfied_rounded;
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: scoreColor, width: 2.5),
                ),
                child: Center(
                  child: Text(
                    '$score',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: scoreColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sức khỏe tài chính',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(scoreIcon, size: 16, color: scoreColor),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: scoreColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            summary.healthRating,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scoreColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (score / 100).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: scoreColor.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: context.appBorder),
          const SizedBox(height: 8),

          // Điểm mạnh ghi nhận
          if (summary.strengths.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Điểm mạnh nổi bật (${summary.strengths.length})',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.income,
                ),
              ),
            ),
            ...summary.strengths.map(
              (s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 14, color: AppColors.income),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appTextPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Khoản trừ điểm
          if (summary.deductions.isNotEmpty) ...[
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                dense: true,
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Chi tiết lý do chấm điểm (${summary.deductions.length} điểm cần cải thiện)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.appTextSecondary,
                  ),
                ),
                children: summary.deductions.map((d) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.remove_circle_outline,
                            size: 14, color: AppColors.expense),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            d.reason,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.appTextPrimary,
                            ),
                          ),
                        ),
                        Text(
                          '-${d.points}đ',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.expense,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // 2. DÒNG TIỀN RÒNG & TỶ LỆ TIẾT KIỆM CARD
  // ============================================================
  Widget _buildCashFlowSection(CashFlowAnalytics cashFlow) {
    final netColor = cashFlow.isPositive ? AppColors.income : AppColors.expense;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: netColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: netColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Dòng tiền & Khả năng giữ lại',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: netColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  cashFlow.sustainabilityStatus,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: netColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 3 Cột số liệu: Thu - Chi - Còn lại
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: context.appBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.appBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text('Tổng thu',
                          style: TextStyle(
                              fontSize: 11, color: context.appTextSecondary)),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '+${AppFormatters.compactCurrency(cashFlow.totalIncome, unit: 'đ')}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.income,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 32, color: context.appBorder),
                Expanded(
                  child: Column(
                    children: [
                      Text('Tổng chi',
                          style: TextStyle(
                              fontSize: 11, color: context.appTextSecondary)),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '-${AppFormatters.compactCurrency(cashFlow.totalExpense, unit: 'đ')}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.expense,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 32, color: context.appBorder),
                Expanded(
                  child: Column(
                    children: [
                      Text('Số tiền còn lại',
                          style: TextStyle(
                              fontSize: 11, color: context.appTextSecondary)),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${cashFlow.isPositive ? '+' : ''}${AppFormatters.compactCurrency(cashFlow.netCashFlow, unit: 'đ')}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: netColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Đánh giá tỷ lệ giữ lại
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: netColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: netColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Tỷ lệ giữ lại / Tiết kiệm:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: context.appTextPrimary,
                      ),
                    ),
                    Text(
                      '${cashFlow.savingsRate.round()}% thu nhập',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: netColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  cashFlow.summaryComment,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: context.appTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 3. CƠ CẤU THU NHẬP & ĐỘ ỔN ĐỊNH CARD
  // ============================================================
  Widget _buildIncomeSection(IncomeAnalytics income) {
    final isGrowing = income.growthRate >= 0;
    final growthColor = isGrowing ? AppColors.income : AppColors.warning;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.income.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  color: AppColors.income,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cơ cấu & Xu hướng thu nhập',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Độ ổn định: ${income.stability}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (income.lastMonthIncome > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: growthColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isGrowing
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 12,
                        color: growthColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${(income.growthRate * 100).abs().round()}% so M-1',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: growthColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Lời bình luận ý nghĩa
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.appBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.appBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    income.commentary,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: context.appTextPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Phân bổ từng nguồn thu
          if (income.sources.isNotEmpty) ...[
            Text(
              'Tỷ trọng từng nguồn thu:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.appTextSecondary,
              ),
            ),
            const SizedBox(height: 8),
            ...income.sources.map((s) {
              final pctDisplay = (s.percentage * 100).round();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            s.categoryName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: context.appTextPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${AppFormatters.compactCurrency(s.amount, unit: 'đ')} ($pctDisplay%)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.appTextPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: s.percentage.clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor:
                            AppColors.income.withValues(alpha: 0.15),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.income),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // 4. PHÁT HIỆN VẤN ĐỀ TÀI CHÍNH 4 BƯỚC
  // ============================================================
  Widget _buildIssuesSection(List<FinancialIssue> issues) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.expense.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.policy_rounded,
                  color: AppColors.expense,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phát hiện vấn đề tài chính',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Vấn đề → Nguyên nhân → Tác động → Đề xuất',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (issues.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.expense.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${issues.length} vấn đề',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.expense,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: context.appBorder),
          const SizedBox(height: 8),
          if (issues.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.income.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: AppColors.income, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Rất tốt! Không phát hiện vấn đề tài chính đáng lo ngại nào trong tháng này.',
                      style: TextStyle(
                          fontSize: 13, color: context.appTextPrimary),
                    ),
                  ),
                ],
              ),
            )
          else
            ...issues.map((i) => _buildStructuredIssueCard(i)),
        ],
      ),
    );
  }

  Widget _buildStructuredIssueCard(FinancialIssue issue) {
    final isCritical = issue.severity == IssueSeverity.critical;
    final color = isCritical ? AppColors.expense : AppColors.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tiêu đề & Mức độ
          Row(
            children: [
              Icon(
                isCritical
                    ? Icons.warning_rounded
                    : Icons.error_outline_rounded,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  issue.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isCritical ? 'Nghiêm trọng' : 'Cảnh báo',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 1. Nguyên nhân
          _buildStepRow(
            icon: Icons.search_rounded,
            label: 'Nguyên nhân',
            content: issue.effectiveRootCause,
            context: context,
          ),
          const SizedBox(height: 4),

          // 2. Tác động
          _buildStepRow(
            icon: Icons.flash_on_rounded,
            label: 'Tác động',
            content: issue.effectiveImpact,
            context: context,
          ),
          const SizedBox(height: 4),

          // 3. Đề xuất
          _buildStepRow(
            icon: Icons.lightbulb_outline_rounded,
            label: 'Đề xuất',
            content: issue.effectiveRecommendation,
            context: context,
            isHighlight: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow({
    required IconData icon,
    required String label,
    required String content,
    required BuildContext context,
    bool isHighlight = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon,
            size: 14,
            color: isHighlight ? AppColors.income : context.appTextSecondary),
        const SizedBox(width: 6),
        SizedBox(
          width: 82,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isHighlight ? AppColors.income : context.appTextSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            content,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              fontWeight: isHighlight ? FontWeight.w500 : FontWeight.normal,
              color: context.appTextPrimary,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // 5. ĐÁNH GIÁ MỤC TIÊU TIẾT KIỆM (FEASIBILITY)
  // ============================================================
  Widget _buildSavingsGoalSection(SavingsGoalAssessment assessment) {
    final hasGoals = assessment.goals.isNotEmpty;
    final isSufficient = assessment.canFulfillAllGoals;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.savings_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Đánh giá Mục tiêu Tiết kiệm',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isSufficient ? AppColors.income : AppColors.expense)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isSufficient ? 'Đủ ngân sách' : 'Thiếu hụt thặng dư',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSufficient ? AppColors.income : AppColors.expense,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Tóm tắt chung
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.appBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.appBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Nhu cầu tích lũy:',
                      style: TextStyle(
                          fontSize: 12, color: context.appTextSecondary),
                    ),
                    Text(
                      '${AppFormatters.compactCurrency(assessment.totalMonthlyRequired, unit: 'đ')}/tháng',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.appTextPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Thặng dư khả dụng:',
                      style: TextStyle(
                          fontSize: 12, color: context.appTextSecondary),
                    ),
                    Text(
                      '${AppFormatters.compactCurrency(assessment.availableCashFlow, unit: 'đ')}/tháng',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: assessment.availableCashFlow >= 0
                            ? AppColors.income
                            : AppColors.expense,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  assessment.overallAdvice,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: context.appTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (hasGoals) ...[
            ...assessment.goals.map((g) {
              final pct = (g.percentComplete * 100).round();
              final statusColor =
                  g.isAtRisk ? AppColors.expense : AppColors.income;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            g.goalName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: context.appTextPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${AppFormatters.compactCurrency(g.monthlyRequired, unit: 'đ')}/tháng',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: g.percentComplete.clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: statusColor.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Đã đạt $pct% (${g.monthsRemaining} tháng còn lại)',
                          style: TextStyle(
                              fontSize: 11, color: context.appTextSecondary),
                        ),
                        Text(
                          g.statusText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      g.suggestion,
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // 6. KẾ HOẠCH HÀNH ĐỘNG CỤ THỂ THÁNG TỚI (ACTION PLAN)
  // ============================================================
  Widget _buildActionPlanSection(FinancialActionPlan actionPlan) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.income.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.playlist_add_check_circle_rounded,
                  color: AppColors.income,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kế hoạch Hành động Tháng tới',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Định mức cụ thể có thể áp dụng ngay',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Banner mục tiêu tiết kiệm
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.income.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.income.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.stars_rounded,
                    color: AppColors.income, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    actionPlan.actionSummary,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.appTextPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Từng mục cắt giảm đề xuất
          if (actionPlan.items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Chi tiêu hiện tại đang rất kỷ luật. Bạn không cần cắt giảm thêm danh mục nào.',
                style: TextStyle(fontSize: 12, color: context.appTextSecondary),
              ),
            )
          else
            ...actionPlan.items.map((item) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.appBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.appBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_downward_rounded,
                          size: 14, color: AppColors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.actionTitle,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.appTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Trần đề xuất: ${AppFormatters.compactCurrency(item.suggestedBudget, unit: 'đ')} • ${item.rationales}',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.appTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '-${AppFormatters.compactCurrency(item.targetReduction, unit: 'đ')}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.income,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ============================================================
  // 7. NHẬN ĐỊNH CỐ VẤN AI TỪ GEMINI SECTION
  // ============================================================
  Widget _buildAiExplanationSection(FinancialInsightSummary summary) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.aiAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome,
                    color: AppColors.aiAccent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cố vấn Tài chính AI (Gemini)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Nhận định & phân tích ngữ cảnh chuyên sâu',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: _isLoadingAiExplanation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.aiAccent,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded,
                        color: AppColors.aiAccent, size: 20),
                tooltip: 'Làm mới đề xuất AI',
                onPressed: _isLoadingAiExplanation
                    ? null
                    : () => _fetchAiExplanation(summary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: context.appBorder),
          const SizedBox(height: 8),
          if (_isLoadingAiExplanation)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: AppColors.aiAccent),
                    const SizedBox(height: 12),
                    Text(
                      'AI đang tổng hợp và phân tích chiến lược tài chính...',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_aiErrorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
              ),
              child: Text(
                _aiErrorMessage!,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: context.appTextPrimary,
                ),
              ),
            )
          else if (_aiExplanation != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.aiAccent.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.aiAccent.withValues(alpha: 0.2)),
              ),
              child: SelectableText(
                _aiExplanation!,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: context.appTextPrimary,
                ),
              ),
            )
          else
            Text(
              'Bấm "Làm mới đề xuất AI" để nhận tư vấn chuyên sâu từ Gemini.',
              style: TextStyle(fontSize: 13, color: context.appTextSecondary),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // 8. DỰ BÁO SỐ DƯ & NGÂN SÁCH CHI TIẾT (EXPANSION)
  // ============================================================
  Widget _buildDetailedForecastSection(FinancialInsightSummary summary) {
    return AppCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.assessment_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Chi tiết Dự báo Số dư & Ngân sách',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
            ],
          ),
          children: [
            const SizedBox(height: 8),
            _buildMonthEndForecastSubSection(summary.monthEndForecast),
            const SizedBox(height: 12),
            _buildBudgetForecastSubSection(summary.budgetForecasts),
            const SizedBox(height: 12),
            _buildSpendingAnomalySubSection(summary.anomalies),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthEndForecastSubSection(MonthEndForecast forecast) {
    final isNegative = forecast.projectedEndBalance < 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dự báo số dư cuối tháng:',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary),
              ),
              Text(
                AppFormatters.compactCurrency(forecast.projectedEndBalance,
                    unit: 'đ'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isNegative ? AppColors.expense : AppColors.income,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildMetricRow(
              'Tổng số dư hiện tại',
              AppFormatters.compactCurrency(forecast.currentTotalBalance,
                  unit: 'đ')),
          _buildMetricRow(
              'Chi tiêu từ đầu tháng',
              AppFormatters.compactCurrency(forecast.monthToDateExpense,
                  unit: 'đ')),
          _buildMetricRow(
              'Trung bình chi linh hoạt/ngày',
              AppFormatters.compactCurrency(
                  forecast.averageDailyDiscretionaryExpense,
                  unit: 'đ')),
          if (forecast.plannedRemainingIncome > 0)
            _buildMetricRow('Thu nhập định kỳ sắp tới',
                '+${AppFormatters.compactCurrency(forecast.plannedRemainingIncome, unit: 'đ')}'),
          if (forecast.plannedRemainingExpense > 0)
            _buildMetricRow('Chi phí định kỳ sắp tới',
                '-${AppFormatters.compactCurrency(forecast.plannedRemainingExpense, unit: 'đ')}'),
          _buildMetricRow('Số ngày còn lại', '${forecast.remainingDays} ngày'),
        ],
      ),
    );
  }

  Widget _buildBudgetForecastSubSection(List<BudgetForecast> forecasts) {
    if (forecasts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Chưa có ngân sách nào được thiết lập.',
          style: TextStyle(fontSize: 12, color: context.appTextSecondary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trạng thái ngân sách danh mục:',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.appTextPrimary),
        ),
        const SizedBox(height: 6),
        ...forecasts.map((b) {
          final isExceeded = b.status == BudgetForecastStatus.exceeded;
          final isAtRisk = b.status == BudgetForecastStatus.atRisk;
          final color = isExceeded
              ? AppColors.expense
              : (isAtRisk ? Colors.deepOrange : AppColors.income);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    b.categoryName,
                    style:
                        TextStyle(fontSize: 12, color: context.appTextPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${AppFormatters.compactCurrency(b.spent, unit: 'đ')} / ${AppFormatters.compactCurrency(b.limit, unit: 'đ')} (${(b.percentUsed * 100).round()}%)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSpendingAnomalySubSection(List<SpendingAnomaly> anomalies) {
    if (anomalies.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Không có chi tiêu bất thường so với 3 tháng trước.',
          style: TextStyle(fontSize: 12, color: context.appTextSecondary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chi tiêu bất thường (${anomalies.length} danh mục):',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.appTextPrimary),
        ),
        const SizedBox(height: 6),
        ...anomalies.map((a) {
          final percentOver = ((a.excessRatio * 100) - 100).round();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '• ${a.categoryName}: Đã chi ${AppFormatters.compactCurrency(a.currentSpend, unit: 'đ')} (Vượt +$percentOver%, chênh lệch +${AppFormatters.compactCurrency(a.excessAmount, unit: 'đ')})',
              style: TextStyle(fontSize: 12, color: context.appTextSecondary),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: context.appTextSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.appTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
