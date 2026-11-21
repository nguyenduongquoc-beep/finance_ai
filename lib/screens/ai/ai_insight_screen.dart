import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
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
import '../../models/monthly_financial_plan.dart';
import '../../services/firestore_service.dart';
import '../../services/ai_service.dart';
import '../../services/financial_analytics_service.dart';
import '../../services/financial_context_revision_tracker.dart';
import '../../services/financial_forecast_service.dart';
import '../../services/language_controller.dart';
import '../../utils/category_localization_helper.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/weekly_heatmap_card.dart';
import 'ai_chat_screen.dart';

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
  final bool isActive;

  const AiInsightScreen({super.key, this.isActive = true});

  /// Ánh xạ màu hiển thị cho từng trạng thái dự báo ngân sách danh mục.
  static Color budgetForecastStatusColor(BudgetForecastStatus status) {
    return switch (status) {
      BudgetForecastStatus.exceeded => AppColors.expense,
      BudgetForecastStatus.atRisk => Colors.deepOrange,
      BudgetForecastStatus.warning => AppColors.warning,
      BudgetForecastStatus.safe => AppColors.income,
    };
  }

  /// Ánh xạ màu hiển thị cho 3 trạng thái khả thi của từng mục tiêu tiết kiệm.
  static Color goalFeasibilityStatusColor(GoalFeasibilityStatus status) {
    return switch (status) {
      GoalFeasibilityStatus.onTrack => AppColors.income,
      GoalFeasibilityStatus.sharedSurplusTight => AppColors.warning,
      GoalFeasibilityStatus.atRisk => AppColors.expense,
    };
  }

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

  // Closed-Loop AI Financial Planning State
  DataSufficiencyAssessment? _sufficiency;
  ReferenceIncomeAssessment? _incomeAssessment;
  MonthlyFinancialPlan? _draftMonthlyPlan;
  MonthlyFinancialPlan? _committedPlan;
  PlanExecutionTrackerResult? _planExecutionResult;
  AiStructuredPlanInsight? _structuredAiInsight;
  double? _userDeclaredExpectedIncome;
  String _currentMonthStr = '';
  String _nextMonthStr = '';
  String _selectedTargetMonth = '';
  bool _isCommittingPlan = false;
  bool _suppressMutationAutoReload = false;

  // Gemini AI state
  bool _isLoadingAiExplanation = false;
  String? _aiExplanation;
  String? _aiErrorMessage;
  String _lastLocaleCode = LanguageController.currentLocale.value.languageCode;
  int _loadedMutationVersion = -1;
  bool _needsRefresh = false;
  int _insightLoadSeq = 0;

  @override
  void initState() {
    super.initState();
    LanguageController.currentLocale.addListener(_onLocaleChanged);
    FinancialContextRevisionTracker.versionNotifier
        .addListener(_onFinancialDataMutated);
    final now = DateTime.now();
    _currentMonthStr = DateFormat('MM/yyyy').format(now);
    final nextMonthDate = DateTime(now.year, now.month + 1, 1);
    _nextMonthStr = DateFormat('MM/yyyy').format(nextMonthDate);
    _selectedTargetMonth = _nextMonthStr;
    _loadInsights();
  }

  Future<void> _onTargetMonthChanged(String nextTargetMonth) async {
    if (nextTargetMonth == _selectedTargetMonth ||
        _isLoading ||
        _isCommittingPlan) {
      return;
    }
    setState(() {
      _selectedTargetMonth = nextTargetMonth;
    });
    await _loadInsights();
  }

  @override
  void didUpdateWidget(covariant AiInsightScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive && mounted) {
      final bool versionChanged = _loadedMutationVersion !=
          FinancialContextRevisionTracker.localMutationVersion;
      if ((_needsRefresh || versionChanged) &&
          !_isLoading &&
          !_isCommittingPlan) {
        _loadInsights();
      }
    }
  }

  void _onFinancialDataMutated() {
    if (!mounted) return;
    if (_suppressMutationAutoReload) return;
    _needsRefresh = true;
    if (widget.isActive && !_isLoading && !_isCommittingPlan) {
      _loadInsights();
    }
  }

  void _onLocaleChanged() {
    final nextCode = LanguageController.currentLocale.value.languageCode;
    if (nextCode == _lastLocaleCode || !mounted) return;
    _lastLocaleCode = nextCode;
    _loadInsights();
  }

  @override
  void dispose() {
    LanguageController.currentLocale.removeListener(_onLocaleChanged);
    FinancialContextRevisionTracker.versionNotifier
        .removeListener(_onFinancialDataMutated);
    super.dispose();
  }

  /// Tải dữ liệu toàn diện trong cửa sổ 4 tháng (Bounded Query) và tính toán Dart thuần
  Future<void> _loadInsights() async {
    final int loadSeq = ++_insightLoadSeq;
    final int capturingMutationVersion =
        FinancialContextRevisionTracker.localMutationVersion;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _needsRefresh = false;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();
    final monthStr = DateFormat('MM/yyyy').format(now);
    final nextMonthStr =
        DateFormat('MM/yyyy').format(DateTime(now.year, now.month + 1, 1));
    _currentMonthStr = monthStr;
    _nextMonthStr = nextMonthStr;
    if (_selectedTargetMonth != monthStr &&
        _selectedTargetMonth != nextMonthStr) {
      _selectedTargetMonth = nextMonthStr;
    }

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
      Future<List<AppTransaction>> fetchWindowTransactions() async {
        try {
          return await _firestoreService.getTransactionsByDateWindow(
            uid,
            from: m3Start,
            to: monthEnd,
          );
        } catch (_) {
          return await _firestoreService.getTransactionsSafely(uid);
        }
      }

      final results = await Future.wait<dynamic>([
        _firestoreService.getWalletsSafely(uid), // 0: List<Wallet>
        _firestoreService.getCategoriesSafely(uid), // 1: List<Category>
        _firestoreService.getBudgetsSafely(uid, month: monthStr), // 2: List<Budget>
        fetchWindowTransactions(), // 3: Window transactions (m3Start..monthEnd)
        _firestoreService.getUserProfile(uid), // 4: AppUser?
        _firestoreService.streamRecurringTransactions(uid).first, // 5: Recurring
        _firestoreService.getSavingGoalsSafely(uid), // 6: Saving goals
        _firestoreService.getMonthlyPlan(uid, monthStr), // 7: Active plan this month (T)
        _firestoreService.getMonthlyPlan(uid, nextMonthStr), // 8: Plan for next month (T+1)
        _firestoreService.getBudgetsSafely(uid, month: nextMonthStr), // 9: Next month budgets (T+1)
      ]);

      final wallets = results[0] as List<Wallet>;
      final categories = results[1] as List<Category>;
      final currentBudgets = results[2] as List<Budget>;
      final windowTx = results[3] as List<AppTransaction>;
      final userProfile = results[4] as AppUser?;
      final recurringSchedules =
          results[5] as List<RecurringTransactionSchedule>;
      final savingGoals = results[6] as List<SavingGoal>;
      final activePlanThisMonth = results[7] as MonthlyFinancialPlan?;
      final nextMonthPlan = results[8] as MonthlyFinancialPlan?;
      final nextMonthBudgets = results[9] as List<Budget>;

      final currentMonthTx = windowTx
          .where((t) =>
              t.date.isAfter(monthStart.subtract(const Duration(seconds: 1))) &&
              t.date.isBefore(monthEnd.add(const Duration(seconds: 1))))
          .toList();
      final m1Tx = windowTx
          .where((t) =>
              t.date.isAfter(m1Start.subtract(const Duration(seconds: 1))) &&
              t.date.isBefore(m1End.add(const Duration(seconds: 1))))
          .toList();
      final m2Tx = windowTx
          .where((t) =>
              t.date.isAfter(m2Start.subtract(const Duration(seconds: 1))) &&
              t.date.isBefore(m2End.add(const Duration(seconds: 1))))
          .toList();
      final m3Tx = windowTx
          .where((t) =>
              t.date.isAfter(m3Start.subtract(const Duration(seconds: 1))) &&
              t.date.isBefore(m3End.add(const Duration(seconds: 1))))
          .toList();
      final last30DaysTx =
          windowTx.where((t) => t.date.isAfter(last30Days)).toList();

      final selectedMonthPlan = _selectedTargetMonth == monthStr
          ? activePlanThisMonth
          : nextMonthPlan;
      final committed =
          selectedMonthPlan ?? activePlanThisMonth ?? nextMonthPlan;
      final declaredIncome = _userDeclaredExpectedIncome ??
          ((userProfile != null && userProfile.monthlyIncome > 0)
              ? userProfile.monthlyIncome
              : null);

      final sufficiency = _analyticsService.assessDataSufficiency(
        currentMonthTx: currentMonthTx,
        historicalMonthsTx: [m1Tx, m2Tx, m3Tx],
        currentBudgets: currentBudgets,
        wallets: wallets,
        savingGoals: savingGoals,
        activePlan: committed,
        referenceToday: now,
      );

      final incomeAssessment = _analyticsService.determineReferenceIncome(
        currentMonthTx: currentMonthTx,
        historicalMonthsTx: [m1Tx, m2Tx, m3Tx],
        currentBudgets: currentBudgets,
        declaredExpectedIncome: declaredIncome,
        isPartialMonth: sufficiency.isPartialMonth,
      );

      final draftPlan = _analyticsService.buildSequentialMonthlyPlan(
        userId: uid,
        sourceMonth: monthStr,
        targetMonth: _selectedTargetMonth,
        sourceMonthTx: currentMonthTx,
        historicalMonthsTx: [m1Tx, m2Tx, m3Tx],
        categories: categories,
        existingTargetBudgets: _selectedTargetMonth == monthStr
            ? currentBudgets
            : nextMonthBudgets,
        savingGoals: savingGoals,
        wallets: wallets,
        declaredExpectedIncome: declaredIncome,
        referenceToday: now,
      );

      PlanExecutionTrackerResult? trackerResult;
      if (committed != null) {
        final trackedTx = committed.targetMonth == monthStr
            ? currentMonthTx
            : <AppTransaction>[];
        trackerResult = _analyticsService.evaluatePlanExecution(
          plan: committed,
          targetMonthTx: trackedTx,
          referenceToday: now,
        );
      }

      final monthlyIncome = incomeAssessment.referenceIncome;

      // 1. Phân tích phát hiện vấn đề bằng Dart thuần
      final issues = _analyticsService.detectIssues(
        currentMonthTx: currentMonthTx,
        lastMonthTx: sufficiency.canCompareMonthOverMonth ? m1Tx : const [],
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

      if (!mounted || loadSeq != _insightLoadSeq) return;
      _loadedMutationVersion = capturingMutationVersion;
      final bool mutatedWhileLoading = _loadedMutationVersion !=
          FinancialContextRevisionTracker.localMutationVersion;
      _needsRefresh = mutatedWhileLoading;

      setState(() {
        _sufficiency = sufficiency;
        _incomeAssessment = incomeAssessment;
        _draftMonthlyPlan = draftPlan;
        _committedPlan = committed;
        _planExecutionResult = trackerResult;
        _forecastSummary = summary;
        _weeklyHeatmap = heatmap;
        _isLoading = false;
      });

      if (mutatedWhileLoading && widget.isActive) {
        await _loadInsights();
        return;
      }

      // Gọi Gemini diễn giải có cấu trúc
      _fetchAiExplanation(summary, draftPlan: draftPlan, loadSeq: loadSeq);
    } catch (e, stackTrace) {
      debugPrint('AI Financial Insights Data Load error: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted || loadSeq != _insightLoadSeq) return;
      setState(() {
        _errorMessage = AppLocalizations.tr('ai_ins_load_error');
        _isLoading = false;
      });
    }
  }

  /// Gọi Gemini diễn giải số liệu theo cấu trúc JSON và gắn gợi ý vào từng danh mục kế hoạch
  Future<void> _fetchAiExplanation(
    FinancialInsightSummary summary, {
    MonthlyFinancialPlan? draftPlan,
    int? loadSeq,
  }) async {
    if (!mounted) return;
    final int activeSeq = loadSeq ?? _insightLoadSeq;
    final plan = draftPlan ?? _draftMonthlyPlan;
    setState(() {
      _isLoadingAiExplanation = true;
      _aiErrorMessage = null;
    });

    try {
      if (plan != null) {
        final structured = await _aiService.explainFinancialInsightsStructured(
          summary: summary,
          draftPlan: plan,
        );
        if (!mounted || activeSeq != _insightLoadSeq) return;
        final updatedAllocations = plan.currentAllocations.map((a) {
          final localizedName =
              CategoryLocalizationHelper.localizeName(a.categoryName);
          final tip = structured.categoryActionTips[a.categoryName] ??
              structured.categoryActionTips[localizedName];
          if (tip != null && tip.isNotEmpty) {
            return a.copyWith(aiActionTip: tip);
          }
          return a;
        }).toList();

        setState(() {
          _structuredAiInsight = structured;
          _draftMonthlyPlan = plan.copyWith(
            currentAllocations: updatedAllocations,
            aiExecutiveSummary: structured.executiveSummary,
            behavioralInsights: structured.behavioralInsights,
          );
          _aiExplanation = structured.executiveSummary;
          _isLoadingAiExplanation = false;
        });
      } else {
        if (!_aiService.effectiveRuntimeConfig.isEnabled) {
          if (!mounted || activeSeq != _insightLoadSeq) return;
          setState(() {
            _aiExplanation = null;
            _aiErrorMessage = null;
            _isLoadingAiExplanation = false;
          });
          return;
        }
        final explanation = await _aiService.explainFinancialInsights(summary);
        if (!mounted || activeSeq != _insightLoadSeq) return;
        setState(() {
          _aiExplanation = explanation;
          _isLoadingAiExplanation = false;
        });
      }
    } catch (e) {
      debugPrint('Gemini explanation error: $e');
      if (!mounted || activeSeq != _insightLoadSeq) return;
      final msg = AiService.isNoNetworkException(e)
          ? AppLocalizations.tr('ai_ins_no_network')
          : AppLocalizations.tr('ai_ins_ai_fallback_note');
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
            Expanded(
              child: Text(
                context.tr('ai_ins_title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: context.tr('ai_ins_refresh_tooltip'),
              onPressed: _loadInsights,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AiChatScreen()),
          );
        },
        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
        label: Text(
          context.tr('ai_ins_ask_bot'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
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
              context.tr('ai_ins_loading'),
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
                _errorMessage ?? context.tr('ai_ins_no_data'),
                textAlign: TextAlign.center,
                style: TextStyle(color: context.appTextSecondary),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadInsights,
                icon: const Icon(Icons.refresh),
                label: Text(context.tr('common_retry')),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // 0. Cấp độ dữ liệu & Cơ sở thu nhập tham chiếu
        if (_sufficiency != null && _incomeAssessment != null) ...[
          _buildDataSufficiencyAndIncomeBanner(
              _sufficiency!, _incomeAssessment!),
          const SizedBox(height: 16),
        ],

        // 0b. Theo dõi thực thi Kế hoạch Tài chính Tháng đã cam kết (nếu có)
        if (_committedPlan != null && _planExecutionResult != null) ...[
          _buildCommittedPlanTrackerSection(
              _committedPlan!, _planExecutionResult!),
          const SizedBox(height: 16),
        ],

        // 1. Điểm sức khỏe tài chính (Health Score & Strengths/Deductions)
        _buildHealthScoreSection(summary),
        const SizedBox(height: 16),

        // 2. Kế hoạch Tài chính Tháng bằng AI (Đa yếu tố + Xem trước & Áp dụng)
        if (_draftMonthlyPlan != null) ...[
          _buildClosedLoopPlanSection(_draftMonthlyPlan!),
          const SizedBox(height: 16),
        ],

        // 3. Nhận định Cố vấn AI có cấu trúc từ Gemini
        _buildAiExplanationSection(summary),
        const SizedBox(height: 16),

        // 4. Dòng tiền ròng & Tỷ lệ tiết kiệm (Net Cash Flow & Savings Rate)
        _buildCashFlowSection(summary.cashFlowAnalytics),
        const SizedBox(height: 16),

        // 5. Phân tích Cơ cấu Thu nhập & Độ ổn định (Income Analytics)
        _buildIncomeSection(summary.incomeAnalytics),
        const SizedBox(height: 16),

        // 6. Phát hiện Vấn đề Tài chính 4 bước
        _buildIssuesSection(summary.issues),
        const SizedBox(height: 16),

        // 7. Đánh giá Tính khả thi Mục tiêu Tiết kiệm
        if (summary.savingsGoalAssessment != null) ...[
          _buildSavingsGoalSection(summary.savingsGoalAssessment!),
          const SizedBox(height: 16),
        ],

        // 8. Nhịp độ Chi tiêu Theo Tuần
        WeeklyHeatmapCard(heatmapData: _weeklyHeatmap),
        const SizedBox(height: 16),

        // 9. Chi tiết Dự báo Số dư, Ngân sách & Bất thường
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
                      context.tr('ai_ins_health_title'),
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
                context.tr(
                  'ai_ins_strengths_title',
                  params: {'count': '${summary.strengths.length}'},
                ),
                style: const TextStyle(
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
                  context.tr(
                    'ai_ins_deductions_title',
                    params: {'count': '${summary.deductions.length}'},
                  ),
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
                          context.tr(
                            'ai_ins_points_deducted',
                            params: {'pts': '${d.points}'},
                          ),
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
                  context.tr('ai_ins_cashflow_title'),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 135),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: netColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      cashFlow.sustainabilityStatus,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: netColor,
                      ),
                    ),
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
                      Text(
                        context.tr('ai_ins_total_income'),
                        style: TextStyle(
                            fontSize: 11, color: context.appTextSecondary),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '+${AppFormatters.compactCurrency(cashFlow.totalIncome)}',
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
                      Text(
                        context.tr('ai_ins_total_expense'),
                        style: TextStyle(
                            fontSize: 11, color: context.appTextSecondary),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '-${AppFormatters.compactCurrency(cashFlow.totalExpense)}',
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
                      Text(
                        context.tr('ai_ins_remaining_money'),
                        style: TextStyle(
                            fontSize: 11, color: context.appTextSecondary),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${cashFlow.isPositive ? '+' : ''}${AppFormatters.compactCurrency(cashFlow.netCashFlow)}',
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
                    Expanded(
                      child: Text(
                        context.tr('ai_ins_save_rate_label'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: context.appTextPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 145),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          context.tr(
                            'ai_ins_save_rate_value',
                            params: {'pct': '${cashFlow.savingsRate.round()}'},
                          ),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: netColor,
                          ),
                        ),
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
                      context.tr('ai_ins_income_section_title'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr(
                        'ai_ins_income_stability',
                        params: {'stability': income.stability},
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (income.lastMonthIncome > 0) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 135),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: growthColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
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
                            context.tr('ai_ins_vs_m1', params: {
                              'pct':
                                  '${(income.growthRate * 100).abs().round()}',
                            }),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: growthColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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
              context.tr('ai_ins_income_sources_title'),
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
                            CategoryLocalizationHelper.localizeNameWithContext(
                                context, s.categoryName),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: context.appTextPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 150),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              '${AppFormatters.compactCurrency(s.amount)} ($pctDisplay%)',
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.appTextPrimary,
                              ),
                            ),
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
                      context.tr('ai_ins_issues_title'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('ai_ins_issues_sub'),
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
                    context.tr(
                      'ai_ins_issues_count',
                      params: {'count': '${issues.length}'},
                    ),
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
                      context.tr('ai_ins_no_issues'),
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
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      isCritical
                          ? context.tr('ai_ins_severity_critical')
                          : context.tr('ai_ins_severity_warning'),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 1. Nguyên nhân
          _buildStepRow(
            icon: Icons.search_rounded,
            label: context.tr('ai_ins_cause_label'),
            content: issue.effectiveRootCause,
            context: context,
          ),
          const SizedBox(height: 4),

          // 2. Tác động
          _buildStepRow(
            icon: Icons.flash_on_rounded,
            label: context.tr('ai_ins_impact_label'),
            content: issue.effectiveImpact,
            context: context,
          ),
          const SizedBox(height: 4),

          // 3. Đề xuất
          _buildStepRow(
            icon: Icons.lightbulb_outline_rounded,
            label: context.tr('ai_ins_action_label'),
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
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 74, maxWidth: 108),
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isHighlight ? AppColors.income : context.appTextSecondary,
            ),
          ),
        ),
        const SizedBox(width: 4),
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
                  context.tr('ai_ins_goal_eval_title'),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 135),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isSufficient ? AppColors.income : AppColors.expense)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      isSufficient
                          ? context.tr('ai_ins_goal_sufficient')
                          : context.tr('ai_ins_goal_shortfall'),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color:
                            isSufficient ? AppColors.income : AppColors.expense,
                      ),
                    ),
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
                    Expanded(
                      child: Text(
                        context.tr('ai_ins_goal_needed'),
                        style: TextStyle(
                            fontSize: 12, color: context.appTextSecondary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${AppFormatters.compactCurrency(assessment.totalMonthlyRequired)}${context.tr('ai_ins_per_month_suffix')}',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: context.appTextPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        context.tr('ai_ins_goal_avail'),
                        style: TextStyle(
                            fontSize: 12, color: context.appTextSecondary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${AppFormatters.compactCurrency(assessment.availableCashFlow)}${context.tr('ai_ins_per_month_suffix')}',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: assessment.availableCashFlow >= 0
                                ? AppColors.income
                                : AppColors.expense,
                          ),
                        ),
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
                  AiInsightScreen.goalFeasibilityStatusColor(g.feasibilityStatus);

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
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 145),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              '${AppFormatters.compactCurrency(g.monthlyRequired)}${context.tr('ai_ins_per_month_suffix')}',
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
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
                        Expanded(
                          child: Text(
                            context.tr(
                              'ai_ins_goal_progress_rem',
                              params: {
                                'pct': '$pct',
                                'months': '${g.monthsRemaining}',
                              },
                            ),
                            style: TextStyle(
                                fontSize: 11, color: context.appTextSecondary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            g.statusText,
                            textAlign: TextAlign.end,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
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
  // 6A. BANNER CẤP ĐỘ DỮ LIỆU & CƠ SỞ THU NHẬP THAM CHIẾU
  // ============================================================
  Widget _buildDataSufficiencyAndIncomeBanner(
    DataSufficiencyAssessment sufficiency,
    ReferenceIncomeAssessment income,
  ) {
    final tierColor = switch (sufficiency.tier) {
      DataSufficiencyTier.empty => AppColors.expense,
      DataSufficiencyTier.preliminary => AppColors.warning,
      DataSufficiencyTier.currentMonthAnalysis => AppColors.info,
      DataSufficiencyTier.monthOverMonthComparison => AppColors.primary,
      DataSufficiencyTier.multiMonthTrend => AppColors.income,
    };

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AiSufficiencyHeaderRow(
            tierLabel: sufficiency.tierLabelWithContext(context),
            tierColor: tierColor,
            declareIncomeLabel: context.tr('ai_ins_declare_income_btn'),
            onDeclareIncome: _showEditExpectedIncomeDialog,
          ),
          const SizedBox(height: 8),
          Text(
            sufficiency.limitationNote,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: context.appTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: income.hasIncomeBasis
                  ? AppColors.primary.withValues(alpha: 0.06)
                  : AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: income.hasIncomeBasis
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : AppColors.warning.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  income.hasIncomeBasis
                      ? Icons.account_balance_wallet_outlined
                      : Icons.warning_amber_rounded,
                  size: 16,
                  color: income.hasIncomeBasis
                      ? AppColors.primary
                      : AppColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    income.hasIncomeBasis
                        ? context.tr(
                            'ai_ins_ref_income_line',
                            params: {
                              'amount': AppFormatters.currency(
                                  income.referenceIncome),
                              'explanation': income.explanation,
                            },
                          )
                        : income.explanation,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: context.appTextPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditExpectedIncomeDialog() async {
    final currentIncome = _incomeAssessment?.referenceIncome ?? 0;
    final ctrl = TextEditingController(
      text: currentIncome > 0 ? AppFormatters.number(currentIncome) : '',
    );

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('ai_ins_income_dlg_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('ai_ins_income_dlg_desc'),
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: const [CurrencyInputFormatter()],
              decoration: InputDecoration(
                labelText: context.tr('ai_ins_income_input_label'),
                hintText: context.tr('ai_ins_income_input_hint'),
                prefixIcon: const Icon(Icons.payments_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () {
              final val = AppFormatters.parseCurrencyInput(ctrl.text);
              if (val > 0) {
                Navigator.pop(ctx, val);
              }
            },
            child: Text(context.tr('ai_ins_income_dlg_submit')),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _userDeclaredExpectedIncome = result;
      });
      final uid = FirebaseAuth.instance.currentUser?.uid;
      _suppressMutationAutoReload = true;
      try {
        if (uid != null && uid.isNotEmpty) {
          try {
            await _firestoreService.updateUserProfile(
              uid,
              {'monthlyIncome': result},
            );
          } catch (_) {}
        }
      } finally {
        _suppressMutationAutoReload = false;
      }
      if (mounted) {
        await _loadInsights();
      }
    }
  }

  // ============================================================
  // 6B. THEO DÕI THỰC THI KẾ HOẠCH TÀI CHÍNH THÁNG (DUAL TRACKING)
  // ============================================================
  Widget _buildCommittedPlanTrackerSection(
    MonthlyFinancialPlan plan,
    PlanExecutionTrackerResult tracker,
  ) {
    if (tracker.isUpcoming) {
      return AiUpcomingPlanCard(
        plan: plan,
        onAdjust: () => _openRebalancePlanSheet(plan, tracker),
      );
    }

    final overallScore = tracker.overallAdherenceScore.round();
    final scoreColor = overallScore >= 75
        ? AppColors.income
        : overallScore >= 50
            ? AppColors.warning
            : AppColors.expense;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.track_changes_rounded,
                  color: scoreColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(
                        'ai_ins_plan_tracker_title',
                        params: {
                          'month': plan.targetMonth,
                          'rev': '${plan.revision}',
                        },
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr(
                        'ai_ins_plan_tracker_sub',
                        params: {
                          'status': plan.status.localizedLabelWithContext(
                            context,
                          ),
                        },
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '$overallScore/100',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: scoreColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildTrackerMetricBox(
                  label: context.tr('ai_ins_budget_adherence'),
                  value:
                      '${tracker.budgetAdherenceScore.toStringAsFixed(0)}%',
                  subText: context.tr(
                    'ai_ins_spent_over_planned',
                    params: {
                      'actual': AppFormatters.compactCurrency(
                          tracker.actualTotalExpense),
                      'planned': AppFormatters.compactCurrency(
                          plan.plannedTotalExpense),
                    },
                  ),
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildTrackerMetricBox(
                  label: context.tr('ai_ins_saving_execution'),
                  value:
                      '${tracker.savingAdherenceScore.toStringAsFixed(0)}%',
                  subText: context.tr(
                    'ai_ins_net_surplus_ratio',
                    params: {
                      'actual': AppFormatters.compactCurrency(
                          tracker.totalNetCashflowSurplus),
                      'target': AppFormatters.compactCurrency(
                          plan.targetSavingAmount),
                    },
                  ),
                  color: AppColors.income,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'ai_ins_goal_unallocated_note',
              params: {
                'deposited':
                    AppFormatters.currency(tracker.netGoalContributions),
                'unallocated':
                    AppFormatters.currency(tracker.unallocatedWalletSurplus),
              },
            ),
            style: TextStyle(fontSize: 11, color: context.appTextSecondary),
          ),
          if (tracker.categoryStatuses
              .any((c) => c.isExceeded || c.isPacingFast)) ...[
            const SizedBox(height: 10),
            ...tracker.categoryStatuses
                .where((c) => c.isExceeded || c.isPacingFast)
                .take(3)
                .map((c) {
              final isEx = c.isExceeded;
              final clr = isEx ? AppColors.expense : AppColors.warning;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: clr.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      isEx
                          ? Icons.error_outline_rounded
                          : Icons.warning_amber_rounded,
                      size: 16,
                      color: clr,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${CategoryLocalizationHelper.localizeNameWithContext(context, c.categoryName)} (${c.isEssential ? context.tr('ai_ins_cat_essential') : context.tr('ai_ins_cat_flexible')}): ${AppFormatters.compactCurrency(c.actualSpent)} / ${AppFormatters.compactCurrency(c.plannedLimit)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.appTextPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openRebalancePlanSheet(plan, tracker),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.tune_rounded, size: 16),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            context.tr('ai_ins_rebalance_btn'),
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrackerMetricBox({
    required String label,
    required String value,
    required String subText,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: context.appTextSecondary),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subText,
            style: TextStyle(fontSize: 10.5, color: context.appTextSecondary),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 6C. KẾ HOẠCH TÀI CHÍNH THÁNG BẰNG AI (CLOSED-LOOP PLANNING)
  // ============================================================
  Widget _buildClosedLoopPlanSection(MonthlyFinancialPlan plan) {
    final essentialAllocations =
        plan.currentAllocations.where((a) => a.isEssential).toList();
    final flexibleAllocations =
        plan.currentAllocations.where((a) => !a.isEssential).toList();
    final now = DateTime.now();
    final currentMonth = _currentMonthStr.isNotEmpty
        ? _currentMonthStr
        : DateFormat('MM/yyyy').format(now);
    final nextMonth = _nextMonthStr.isNotEmpty
        ? _nextMonthStr
        : DateFormat('MM/yyyy').format(DateTime(now.year, now.month + 1, 1));
    final bool isCurrentTargetMonth = plan.targetMonth == currentMonth;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                      context.tr(
                        'ai_ins_monthly_plan_title',
                        params: {'month': plan.targetMonth},
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('ai_ins_monthly_plan_sub'),
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
          AiTargetMonthSelector(
            currentMonth: currentMonth,
            nextMonth: nextMonth,
            selectedMonth: _selectedTargetMonth.isNotEmpty
                ? _selectedTargetMonth
                : plan.targetMonth,
            enabled: !_isLoading && !_isCommittingPlan,
            onSelected: _onTargetMonthChanged,
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: (isCurrentTargetMonth
                      ? AppColors.income
                      : AppColors.primary)
                  .withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (isCurrentTargetMonth
                        ? AppColors.income
                        : AppColors.primary)
                    .withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isCurrentTargetMonth
                      ? Icons.play_circle_outline_rounded
                      : Icons.event_available_rounded,
                  size: 15,
                  color: isCurrentTargetMonth
                      ? AppColors.income
                      : AppColors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isCurrentTargetMonth
                        ? context.tr('ai_ins_target_mode_active_hint')
                        : context.tr(
                            'ai_ins_target_mode_approved_hint',
                            params: {'month': plan.targetMonth},
                          ),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: context.appTextPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Cảnh báo nếu thiếu thu nhập tham chiếu hoặc thâm hụt thiết yếu hoặc mục tiêu không khả thi
          if (plan.incomeMode == IncomeStabilityMode.noIncomeBasis)
            _buildPlanWarningBox(
              icon: Icons.info_outline_rounded,
              color: AppColors.warning,
              message: context.tr('ai_ins_no_income_plan_note'),
            )
          else if (plan.isEssentialDeficit)
            _buildPlanWarningBox(
              icon: Icons.report_problem_rounded,
              color: AppColors.expense,
              message: context.tr(
                'ai_ins_essential_exceeds_income',
                params: {
                  'essential': AppFormatters.currency(plan.essentialExpenseCap),
                  'income': AppFormatters.currency(plan.referenceIncome),
                },
              ),
            )
          else if (!plan.isSavingGoalFeasible && plan.infeasibleSavingGap > 0)
            _buildPlanWarningBox(
              icon: Icons.warning_amber_rounded,
              color: AppColors.warning,
              message:
                  '${context.tr('ai_ins_saving_infeasible_note', params: {'desired': AppFormatters.currency(plan.desiredGoalSavingAmount), 'gap': AppFormatters.currency(plan.infeasibleSavingGap)})}${plan.recommendedGoalMonths != null ? context.tr('ai_ins_saving_infeasible_extend', params: {'months': '${plan.recommendedGoalMonths}'}) : ''}',
            ),

          // Tóm tắt cân bằng ngân sách: E_essential + E_flexible + S_planned <= I_ref
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.income.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.income.withValues(alpha: 0.24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(
                    'ai_ins_budget_balance_header',
                    params: {'month': plan.targetMonth},
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildPlanBalanceMetricTile(
                        context.tr('ai_ins_ref_income_chip'),
                        AppFormatters.compactCurrency(plan.referenceIncome),
                        AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildPlanBalanceMetricTile(
                        context.tr('ai_ins_essential_chip'),
                        AppFormatters.compactCurrency(plan.essentialExpenseCap),
                        Colors.teal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildPlanBalanceMetricTile(
                        context.tr('ai_ins_flexible_chip'),
                        AppFormatters.compactCurrency(plan.flexibleExpenseCap),
                        Colors.deepOrange,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildPlanBalanceMetricTile(
                        context.tr('ai_ins_feasible_saving_chip'),
                        AppFormatters.compactCurrency(plan.targetSavingAmount),
                        AppColors.income,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          if (plan.currentAllocations.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                context.tr('ai_ins_no_expense_cats'),
                style: TextStyle(fontSize: 12, color: context.appTextSecondary),
              ),
            )
          else ...[
            if (flexibleAllocations.isNotEmpty) ...[
              Text(
                context.tr(
                  'ai_ins_flex_alloc_title',
                  params: {'count': '${flexibleAllocations.length}'},
                ),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: context.appTextPrimary,
                ),
              ),
              const SizedBox(height: 6),
              ...flexibleAllocations.map(_buildAllocationTile),
              const SizedBox(height: 8),
            ],
            if (essentialAllocations.isNotEmpty) ...[
              Text(
                context.tr(
                  'ai_ins_ess_alloc_title',
                  params: {'count': '${essentialAllocations.length}'},
                ),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: context.appTextPrimary,
                ),
              ),
              const SizedBox(height: 6),
              ...essentialAllocations.map(_buildAllocationTile),
            ],
          ],

          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isCommittingPlan || plan.currentAllocations.isEmpty
                  ? null
                  : () => _openPlanPreviewAndConfirmSheet(plan),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.fact_check_outlined, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        context.tr(
                          'ai_ins_preview_apply_btn',
                          params: {'month': plan.targetMonth},
                        ),
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanWarningBox({
    required IconData icon,
    required Color color,
    required String message,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: context.appTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanBalanceMetricTile(
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: context.appTextSecondary,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllocationTile(PlannedCategoryAllocation item) {
    final reduction = (item.sourceMonthSpent - item.recommendedLimit)
        .clamp(0.0, double.infinity);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.appBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: item.isEssential
                        ? Colors.teal.withValues(alpha: 0.12)
                        : Colors.deepOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.isEssential
                          ? context.tr('ai_ins_cat_essential')
                          : context.tr('ai_ins_cat_flexible'),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: item.isEssential
                            ? Colors.teal
                            : Colors.deepOrange,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  CategoryLocalizationHelper.localizeNameWithContext(
                      context, item.categoryName),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        AppFormatters.compactCurrency(item.recommendedLimit),
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    if (reduction > 0)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '(-${AppFormatters.compactCurrency(reduction)})',
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.income,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.calculationBasis,
            style: TextStyle(fontSize: 11, color: context.appTextSecondary),
          ),
          if (item.aiActionTip.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              context.tr(
                'ai_ins_ai_tip_prefix',
                params: {'tip': item.aiActionTip},
              ),
              style: const TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: AppColors.aiAccent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Bước Xem trước & Xác nhận trước khi áp dụng Kế hoạch vào Budgets
  /// Đọc lại ngân sách hiện tại, cho phép chọn từng danh mục, kiểm tra xung đột (Optimistic Concurrency)
  Future<void> _openPlanPreviewAndConfirmSheet(
    MonthlyFinancialPlan initialPlan,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    // Đọc lại ngân sách mới nhất của tháng đích để hiển thị so sánh chính xác
    final latestBudgets = await _firestoreService.getBudgetsSafely(
      uid,
      month: initialPlan.targetMonth,
    );
    if (!mounted) return;

    final existingByCatId = <String, double?>{
      for (final b in latestBudgets) b.categoryId: b.limit,
    };

    final editableAllocations = initialPlan.currentAllocations
        .map((a) => a.copyWith(
              existingBudget: existingByCatId[a.categoryId],
            ))
        .toList();

    final selectedCategoryIds = <String>{
      for (final a in editableAllocations) a.categoryId,
    };

    final submissionToken =
        '${uid}_${initialPlan.targetMonth}_${DateTime.now().millisecondsSinceEpoch}';
    final currentMonthStr = DateFormat('MM/yyyy').format(DateTime.now());
    final bool willActivateImmediately =
        initialPlan.targetMonth == currentMonthStr;
    final PlanLifecycleStatus expectedStatus = willActivateImmediately
        ? PlanLifecycleStatus.active
        : PlanLifecycleStatus.approved;
    final Color statusBadgeColor =
        willActivateImmediately ? AppColors.income : AppColors.primary;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.82,
              maxChildSize: 0.94,
              minChildSize: 0.5,
              builder: (_, scrollCtrl) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.fact_check_rounded,
                              color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.tr(
                                'ai_ins_preview_sheet_title',
                                params: {'month': initialPlan.targetMonth},
                              ),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetCtx),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusBadgeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: statusBadgeColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              willActivateImmediately
                                  ? Icons.bolt_rounded
                                  : Icons.schedule_rounded,
                              size: 15,
                              color: statusBadgeColor,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${expectedStatus.localizedLabelWithContext(context)} • ${willActivateImmediately ? context.tr('ai_ins_target_mode_active_hint') : context.tr('ai_ins_plan_upcoming_status', params: {'month': initialPlan.targetMonth})}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: statusBadgeColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        context.tr('ai_ins_preview_sheet_note'),
                        style: const TextStyle(fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollCtrl,
                          itemCount: editableAllocations.length,
                          itemBuilder: (_, idx) {
                            final item = editableAllocations[idx];
                            final hasExisting = item.existingBudget != null &&
                                item.existingBudget! > 0;
                            final isSelected =
                                selectedCategoryIds.contains(item.categoryId);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: CheckboxListTile(
                                value: isSelected,
                                onChanged: isSubmitting
                                    ? null
                                    : (val) {
                                        setSheetState(() {
                                          if (val == true) {
                                            selectedCategoryIds
                                                .add(item.categoryId);
                                          } else {
                                            selectedCategoryIds
                                                .remove(item.categoryId);
                                          }
                                        });
                                      },
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${CategoryLocalizationHelper.localizeNameWithContext(ctx, item.categoryName)} (${item.isEssential ? context.tr('ai_ins_cat_essential') : context.tr('ai_ins_cat_flexible')})',
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: isSubmitting
                                          ? null
                                          : () async {
                                              final edited =
                                                  await _promptEditLimitDialog(
                                                CategoryLocalizationHelper
                                                    .localizeNameWithContext(
                                                        ctx, item.categoryName),
                                                item.recommendedLimit,
                                              );
                                              if (edited != null) {
                                                setSheetState(() {
                                                  editableAllocations[idx] =
                                                      item.copyWith(
                                                          recommendedLimit:
                                                              edited);
                                                });
                                              }
                                            },
                                      child: Text(
                                        AppFormatters.currency(
                                            item.recommendedLimit),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  hasExisting
                                      ? context.tr(
                                          'ai_ins_budget_diff_existing',
                                          params: {
                                            'existing': AppFormatters.currency(
                                                item.existingBudget!),
                                            'proposed': AppFormatters.currency(
                                                item.recommendedLimit),
                                          },
                                        )
                                      : context.tr(
                                          'ai_ins_budget_diff_new',
                                          params: {
                                            'month': initialPlan.targetMonth,
                                            'proposed': AppFormatters.currency(
                                                item.recommendedLimit),
                                          },
                                        ),
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  setSheetState(() => isSubmitting = true);
                                  setState(() => _isCommittingPlan = true);
                                  try {
                                    final totalEss = editableAllocations
                                        .where((a) => a.isEssential)
                                        .fold(0.0,
                                            (s, a) => s + a.recommendedLimit);
                                    final totalFlex = editableAllocations
                                        .where((a) => !a.isEssential)
                                        .fold(0.0,
                                            (s, a) => s + a.recommendedLimit);
                                    final newSavings = (initialPlan
                                                .referenceIncome -
                                            totalEss -
                                            totalFlex)
                                        .clamp(0.0, double.infinity);

                                    final planToCommit = initialPlan.copyWith(
                                      currentAllocations: editableAllocations,
                                      essentialExpenseCap: totalEss,
                                      flexibleExpenseCap: totalFlex,
                                      targetSavingAmount: newSavings,
                                    );

                                    final committedPlan = await _firestoreService
                                        .commitMonthlyPlanTransactionally(
                                      planToCommit: planToCommit,
                                      selectedCategoryIds: selectedCategoryIds,
                                      expectedExistingBudgets: existingByCatId,
                                      submissionToken: submissionToken,
                                    );

                                    if (sheetCtx.mounted) {
                                      Navigator.pop(sheetCtx);
                                    }
                                    if (!mounted) return;
                                    final bool isActivated =
                                        committedPlan.status ==
                                            PlanLifecycleStatus.active;
                                    AppSnackbar.show(
                                      context,
                                      AppLocalizations.tr(
                                        isActivated
                                            ? 'ai_ins_plan_activated_ok'
                                            : 'ai_ins_plan_approved_scheduled_ok',
                                        params: {
                                          'month': initialPlan.targetMonth,
                                        },
                                      ),
                                    );
                                    await _loadInsights();
                                  } on PlanBudgetConflictException catch (e) {
                                    if (sheetCtx.mounted) {
                                      Navigator.pop(sheetCtx);
                                    }
                                    if (!mounted) return;
                                    AppSnackbar.show(
                                      context,
                                      e.message,
                                      isError: true,
                                    );
                                    await _loadInsights();
                                  } catch (e) {
                                    if (!mounted) return;
                                    setSheetState(() => isSubmitting = false);
                                    AppSnackbar.show(
                                      context,
                                      AppLocalizations.tr(
                                        'ai_ins_plan_save_err',
                                        params: {'error': '$e'},
                                      ),
                                      isError: true,
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isCommittingPlan = false);
                                    }
                                  }
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              isSubmitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.check_circle_outline,
                                      size: 18),
                              const SizedBox(width: 8),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    isSubmitting
                                        ? context.tr('ai_ins_saving_plan_btn')
                                        : (willActivateImmediately
                                            ? context.tr(
                                                'ai_ins_approve_active_btn')
                                            : context.tr(
                                                'ai_ins_approve_scheduled_btn')),
                                    maxLines: 1,
                                    softWrap: false,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<double?> _promptEditLimitDialog(
      String categoryName, double currentLimit) async {
    final ctrl = TextEditingController(
      text: currentLimit > 0 ? AppFormatters.number(currentLimit) : '0',
    );
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          context.tr(
            'ai_ins_edit_limit_title',
            params: {'category': categoryName},
          ),
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: const [CurrencyInputFormatter()],
          decoration: InputDecoration(
            labelText: context.tr('ai_ins_new_limit_label'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              final val = AppFormatters.parseCurrencyInput(ctrl.text);
              if (val >= 0) {
                Navigator.pop(ctx, val);
              }
            },
            child: Text(context.tr('common_save')),
          ),
        ],
      ),
    );
  }

  /// Tái cân bằng Kế hoạch giữa tháng (Mid-month Rebalancing)
  /// Giữ nguyên originalSnapshot, ghi vào adjustmentHistory, KHÔNG sửa SavingGoal gốc
  Future<void> _openRebalancePlanSheet(
    MonthlyFinancialPlan plan,
    PlanExecutionTrackerResult tracker,
  ) async {
    final reasonCtrl = TextEditingController(
      text: context.tr('ai_ins_rebalance_default_reason'),
    );
    final updatedAllocations = List<PlannedCategoryAllocation>.from(
      plan.currentAllocations,
    );
    double newSavingTarget = plan.targetSavingAmount;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune_rounded,
                            color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.tr(
                              'ai_ins_rebalance_title',
                              params: {'month': plan.targetMonth},
                            ),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.tr('ai_ins_rebalance_note'),
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonCtrl,
                      decoration: InputDecoration(
                        labelText: context.tr('ai_ins_rebalance_reason_label'),
                        prefixIcon: const Icon(Icons.edit_note),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(updatedAllocations.length, (i) {
                      final a = updatedAllocations[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${CategoryLocalizationHelper.localizeNameWithContext(context, a.categoryName)} (${a.isEssential ? context.tr('ai_ins_cat_essential') : context.tr('ai_ins_cat_flexible')})',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          context.tr(
                            'ai_ins_current_limit_line',
                            params: {
                              'amount':
                                  AppFormatters.currency(a.recommendedLimit),
                            },
                          ),
                        ),
                        trailing: TextButton.icon(
                          onPressed: () async {
                            final val = await _promptEditLimitDialog(
                              CategoryLocalizationHelper.localizeNameWithContext(
                                  context, a.categoryName),
                              a.recommendedLimit,
                            );
                            if (val != null) {
                              setSheetState(() {
                                updatedAllocations[i] =
                                    a.copyWith(recommendedLimit: val);
                                final totalPlanned = updatedAllocations.fold(
                                    0.0,
                                    (s, item) => s + item.recommendedLimit);
                                newSavingTarget =
                                    (plan.referenceIncome - totalPlanned)
                                        .clamp(0.0, double.infinity);
                              });
                            }
                          },
                          icon: const Icon(Icons.edit, size: 15),
                          label: Text(context.tr('common_edit')),
                        ),
                      );
                    }),
                    const Divider(),
                    Text(
                      context.tr(
                        'ai_ins_rebalance_new_saving',
                        params: {
                          'amount': AppFormatters.currency(newSavingTarget),
                        },
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.income,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                setSheetState(() => isSaving = true);
                                setState(() => _isCommittingPlan = true);
                                try {
                                  final reasonText =
                                      reasonCtrl.text.trim().isEmpty
                                          ? AppLocalizations.tr(
                                              'ai_ins_rebalance_fallback_reason')
                                          : reasonCtrl.text.trim();
                                  await _firestoreService
                                      .rebalanceMonthlyPlanTransactionally(
                                    userId: plan.userId,
                                    targetMonth: plan.targetMonth,
                                    updatedAllocations: updatedAllocations,
                                    updatedTargetSaving: newSavingTarget,
                                    updatedReferenceIncome:
                                        plan.referenceIncome,
                                    reason: reasonText,
                                    strategy: 'reallocate_categories',
                                    summary: AppLocalizations.tr(
                                      'ai_ins_rebalance_log_note',
                                      params: {'month': plan.targetMonth},
                                    ),
                                  );
                                  if (sheetCtx.mounted) {
                                    Navigator.pop(sheetCtx);
                                  }
                                  if (!mounted) return;
                                  AppSnackbar.show(
                                    context,
                                    AppLocalizations.tr(
                                      'ai_ins_rebalance_ok',
                                      params: {'rev': '${plan.revision + 1}'},
                                    ),
                                  );
                                  await _loadInsights();
                                } catch (e) {
                                  if (!mounted) return;
                                  setSheetState(() => isSaving = false);
                                  AppSnackbar.show(
                                    context,
                                    AppLocalizations.tr(
                                      'ai_ins_rebalance_err',
                                      params: {'error': '$e'},
                                    ),
                                    isError: true,
                                  );
                                } finally {
                                  if (mounted) {
                                    setState(() => _isCommittingPlan = false);
                                  }
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 48),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.save_outlined, size: 18),
                            const SizedBox(width: 8),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  context.tr('ai_ins_rebalance_save_btn'),
                                  maxLines: 1,
                                  softWrap: false,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // 7. NHẬN ĐỊNH CỐ VẤN AI TỪ GEMINI SECTION (STRUCTURED JSON + FALLBACK)
  // ============================================================
  Widget _buildAiExplanationSection(FinancialInsightSummary summary) {
    final structured = _structuredAiInsight;
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
                      context.tr('ai_ins_gemini_title'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      structured != null
                          ? (structured.isFromFallback
                              ? context.tr('ai_ins_gemini_sub_offline')
                              : context.tr('ai_ins_gemini_sub_online'))
                          : context.tr('ai_ins_gemini_sub_default'),
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
                tooltip: context.tr('ai_ins_refresh_ai_tooltip'),
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
                      context.tr('ai_ins_gemini_loading'),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    _aiExplanation!,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.55,
                      color: context.appTextPrimary,
                    ),
                  ),
                  if (structured != null &&
                      structured.behavioralInsights.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      context.tr('ai_ins_behavior_title'),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...structured.behavioralInsights.map(
                      (b) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• $b',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: context.appTextPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (structured != null &&
                      structured.savingStrategyNote.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      context.tr('ai_ins_strategy_title'),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.income,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '🎯 ${structured.savingStrategyNote}',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: context.appTextPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            )
          else
            Text(
              context.tr('ai_ins_gemini_empty'),
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
                  context.tr('ai_ins_forecast_title'),
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
          AiForecastHeadlineRow(
            label: context.tr('ai_ins_forecast_eom'),
            amountText:
                AppFormatters.compactCurrency(forecast.projectedEndBalance),
            amountColor: isNegative ? AppColors.expense : AppColors.income,
          ),
          const SizedBox(height: 8),
          _buildMetricRow(
              context.tr('ai_ins_cur_total_bal'),
              AppFormatters.compactCurrency(forecast.currentTotalBalance)),
          _buildMetricRow(
              context.tr('ai_ins_mtd_spend'),
              AppFormatters.compactCurrency(forecast.monthToDateExpense)),
          _buildMetricRow(
              context.tr('ai_ins_daily_flex_avg'),
              AppFormatters.compactCurrency(
                  forecast.averageDailyDiscretionaryExpense)),
          if (forecast.plannedRemainingIncome > 0)
            _buildMetricRow(context.tr('ai_ins_upcoming_rec_in'),
                '+${AppFormatters.compactCurrency(forecast.plannedRemainingIncome)}'),
          if (forecast.plannedRemainingExpense > 0)
            _buildMetricRow(context.tr('ai_ins_upcoming_rec_out'),
                '-${AppFormatters.compactCurrency(forecast.plannedRemainingExpense)}'),
          _buildMetricRow(
            context.tr('ai_ins_days_remaining'),
            context.tr(
              'ai_ins_days_value',
              params: {'days': '${forecast.remainingDays}'},
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetForecastSubSection(List<BudgetForecast> forecasts) {
    if (forecasts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          context.tr('ai_ins_no_budgets'),
          style: TextStyle(fontSize: 12, color: context.appTextSecondary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('ai_ins_cat_budget_status'),
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.appTextPrimary),
        ),
        const SizedBox(height: 6),
        ...forecasts.map((b) {
          final color = AiInsightScreen.budgetForecastStatusColor(b.status);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    CategoryLocalizationHelper.localizeNameWithContext(
                        context, b.categoryName),
                    style:
                        TextStyle(fontSize: 12, color: context.appTextPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 165),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${AppFormatters.compactCurrency(b.spent)} / ${AppFormatters.compactCurrency(b.limit)} (${(b.percentUsed * 100).round()}%)',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
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
          context.tr('ai_ins_no_anomalies'),
          style: TextStyle(fontSize: 12, color: context.appTextSecondary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr(
            'ai_ins_anomalies_title',
            params: {'count': '${anomalies.length}'},
          ),
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
              context.tr(
                'ai_ins_anomaly_line',
                params: {
                  'category': CategoryLocalizationHelper.localizeNameWithContext(
                      context, a.categoryName),
                  'spent': AppFormatters.compactCurrency(a.currentSpend),
                  'pct': '$percentOver',
                  'excess': AppFormatters.compactCurrency(a.excessAmount),
                },
              ),
              style: TextStyle(fontSize: 12, color: context.appTextSecondary),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return AiInsightMetricRow(label: label, value: value);
  }
}

/// Bộ chọn tháng mục tiêu cho Kế hoạch Tài chính Tháng (Tháng hiện tại T vs Tháng kế tiếp T+1).
class AiTargetMonthSelector extends StatelessWidget {
  final String currentMonth;
  final String nextMonth;
  final String selectedMonth;
  final bool enabled;
  final ValueChanged<String> onSelected;

  const AiTargetMonthSelector({
    super.key,
    required this.currentMonth,
    required this.nextMonth,
    required this.selectedMonth,
    required this.onSelected,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final bool isCurrentSelected = selectedMonth == currentMonth;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.appBackground,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildOption(
              context: context,
              label: context.tr(
                'ai_ins_target_month_current',
                params: {'month': currentMonth},
              ),
              isSelected: isCurrentSelected,
              onTap: enabled ? () => onSelected(currentMonth) : null,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildOption(
              context: context,
              label: context.tr(
                'ai_ins_target_month_next',
                params: {'month': nextMonth},
              ),
              isSelected: !isCurrentSelected,
              onTap: enabled ? () => onSelected(nextMonth) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : context.appTextSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thẻ trạng thái cho Kế hoạch Tài chính Tháng tương lai (T+1) đã phê duyệt
/// nhưng chưa tới ngày 01/{targetMonth} để bắt đầu chấm điểm thực thi.
class AiUpcomingPlanCard extends StatelessWidget {
  final MonthlyFinancialPlan plan;
  final VoidCallback? onAdjust;

  const AiUpcomingPlanCard({
    super.key,
    required this.plan,
    this.onAdjust,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.event_available_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr(
                    'ai_ins_plan_upcoming_title',
                    params: {
                      'month': plan.targetMonth,
                      'rev': '${plan.revision}',
                    },
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 115),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      context.tr('ai_ins_plan_upcoming_badge'),
                      maxLines: 1,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr(
                          'ai_ins_plan_upcoming_status',
                          params: {'month': plan.targetMonth},
                        ),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: context.appTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.tr(
                          'ai_ins_plan_upcoming_note',
                          params: {'month': plan.targetMonth},
                        ),
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: context.appTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryBox(
                  context: context,
                  label: context.tr('ai_ins_plan_upcoming_planned_budget'),
                  value:
                      AppFormatters.compactCurrency(plan.plannedTotalExpense),
                  subText: context.tr(
                    'ai_ins_plan_upcoming_budget_split',
                    params: {
                      'ess':
                          AppFormatters.compactCurrency(plan.essentialExpenseCap),
                      'flex':
                          AppFormatters.compactCurrency(plan.flexibleExpenseCap),
                    },
                  ),
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSummaryBox(
                  context: context,
                  label: context.tr('ai_ins_plan_upcoming_target_saving'),
                  value: AppFormatters.compactCurrency(plan.targetSavingAmount),
                  subText: context.tr(
                    'ai_ins_plan_upcoming_ref_income',
                    params: {
                      'income':
                          AppFormatters.compactCurrency(plan.referenceIncome),
                    },
                  ),
                  color: AppColors.income,
                ),
              ),
            ],
          ),
          if (onAdjust != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onAdjust,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.tune_rounded, size: 16),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          context.tr(
                            'ai_ins_plan_upcoming_adjust_btn',
                            params: {'month': plan.targetMonth},
                          ),
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryBox({
    required BuildContext context,
    required String label,
    required String value,
    required String subText,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: context.appTextSecondary),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: context.appTextSecondary),
          ),
        ],
      ),
    );
  }
}

/// Hàng tiêu đề thẻ mức độ dữ liệu đầu kỳ và nút khai báo thu nhập dự kiến.
class AiSufficiencyHeaderRow extends StatelessWidget {
  final String tierLabel;
  final Color tierColor;
  final String declareIncomeLabel;
  final VoidCallback onDeclareIncome;

  const AiSufficiencyHeaderRow({
    super.key,
    required this.tierLabel,
    required this.tierColor,
    required this.declareIncomeLabel,
    required this.onDeclareIncome,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: tierColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: tierColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_user_outlined,
                      size: 14, color: tierColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      tierLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: tierColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 165),
          child: TextButton.icon(
            onPressed: onDeclareIncome,
            icon: const Icon(Icons.edit_note_rounded, size: 16),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                declareIncomeLabel,
                maxLines: 1,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
      ],
    );
  }
}

/// Hàng tiêu đề dự báo số dư cuối tháng, chống tràn pixel ở mọi ngôn ngữ.
class AiForecastHeadlineRow extends StatelessWidget {
  final String label;
  final String amountText;
  final Color amountColor;

  const AiForecastHeadlineRow({
    super.key,
    required this.label,
    required this.amountText,
    required this.amountColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.appTextPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 145),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              amountText,
              maxLines: 1,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: amountColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Hàng chỉ số chi tiết (nhãn + giá trị căn phải) trong phân tích dự báo.
class AiInsightMetricRow extends StatelessWidget {
  final String label;
  final String value;

  const AiInsightMetricRow({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: context.appTextSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.appTextPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
