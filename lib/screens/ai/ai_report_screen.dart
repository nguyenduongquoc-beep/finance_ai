import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/transaction_model.dart';
import '../../models/category_model.dart';
import '../../models/budget_model.dart';
import '../../models/recurring_transaction_model.dart';
import '../../models/saving_goal_model.dart';
import '../../models/user_model.dart';
import '../../models/wallet_model.dart';
import '../../services/financial_analytics_service.dart';
import '../../services/financial_export_service.dart';
import '../../services/firestore_service.dart';
import '../../services/language_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/category_icons.dart';
import '../../utils/category_localization_helper.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/spending_trend_bar_chart.dart';
import 'ai_insight_screen.dart';

enum _InsightType { warning, positive, success, info }

class _ReportInsight {
  final String title;
  final String description;
  final String tag;
  final String? metricBadge;
  final _InsightType type;

  _ReportInsight({
    required this.title,
    required this.description,
    required this.tag,
    this.metricBadge,
    required this.type,
  });
}

/// 19. Báo cáo AI - Màn hình báo cáo tài chính tháng (Redesign hiện đại & phong cách)
class AiReportScreen extends StatefulWidget {
  const AiReportScreen({super.key});

  @override
  State<AiReportScreen> createState() => _AiReportScreenState();
}

class _AiReportScreenState extends State<AiReportScreen> {
  final _firestoreService = FirestoreService();
  final _exportService = FinancialExportService();

  bool _isLoading = true;
  bool _isExportingPdf = false;
  bool _isExportingCsv = false;
  String? _errorMessage;

  double _totalExpense = 0;
  double _savings = 0;
  double _lastMonthExpense = 0;
  double? _percentChange;

  Map<String, double> _categoryTotals = {};
  Map<String, double> _lastCategoryTotals = {};
  Map<String, int> _categoryTxCounts = {};
  List<Category> _categories = [];
  int _selectedCategoryIndex = 0;

  List<double> _trendAmounts = [0, 0, 0];
  List<String> _trendMonthLabels = ['', '', ''];

  List<_ReportInsight> _insights = [];
  String _lastLocaleCode = LanguageController.currentLocale.value.languageCode;

  // Palette màu chuẩn cho biểu đồ cơ cấu chi tiêu
  final List<Color> _chartColors = const [
    Color(0xFF10B981), // Emerald
    Color(0xFF3B82F6), // Royal Blue
    Color(0xFFF59E0B), // Amber
    Color(0xFF8B5CF6), // Violet
    Color(0xFFEF4444), // Coral Red
    Color(0xFF06B6D4), // Cyan
    Color(0xFFEC4899), // Rose Pink
  ];

  @override
  void initState() {
    super.initState();
    LanguageController.currentLocale.addListener(_onLocaleChanged);
    _loadReportData();
  }

  void _onLocaleChanged() {
    final nextCode = LanguageController.currentLocale.value.languageCode;
    if (nextCode == _lastLocaleCode || !mounted) return;
    _lastLocaleCode = nextCode;
    _loadReportData();
  }

  @override
  void dispose() {
    LanguageController.currentLocale.removeListener(_onLocaleChanged);
    super.dispose();
  }

  Future<void> _loadReportData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();

    final monthStart = DateTime(now.year, now.month, 1);

    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = DateTime(now.year, now.month, 0, 23, 59, 59);

    final twoMonthsAgoStart = DateTime(now.year, now.month - 2, 1);
    final twoMonthsAgoEnd = DateTime(now.year, now.month - 1, 0, 23, 59, 59);

    try {
      Future<List<AppTransaction>> loadWindowTx() async {
        try {
          return await _firestoreService.getTransactionsByDateWindow(
            uid,
            from: twoMonthsAgoStart,
            to: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
          );
        } catch (_) {
          return await _firestoreService.getTransactionsSafely(uid);
        }
      }

      final results = await Future.wait<dynamic>([
        loadWindowTx(),
        _firestoreService.getCategoriesSafely(uid),
        _firestoreService.getBudgetsSafely(uid, month: AppFormatters.month(now)),
        _firestoreService.getSavingGoalsSafely(uid),
      ]);

      final allWindowTx = results[0] as List<AppTransaction>;
      final List<AppTransaction> currentTx = allWindowTx
          .where((t) =>
              t.date.isAfter(monthStart.subtract(const Duration(seconds: 1))))
          .toList();
      final List<AppTransaction> lastMonthTx = allWindowTx
          .where((t) =>
              t.date.isAfter(
                  lastMonthStart.subtract(const Duration(seconds: 1))) &&
              t.date.isBefore(lastMonthEnd.add(const Duration(seconds: 1))))
          .toList();
      final List<AppTransaction> twoMonthsAgoTx = allWindowTx
          .where((t) =>
              t.date.isAfter(
                  twoMonthsAgoStart.subtract(const Duration(seconds: 1))) &&
              t.date.isBefore(twoMonthsAgoEnd.add(const Duration(seconds: 1))))
          .toList();
      final categories = results[1] as List<Category>;
      final budgets = results[2] as List<Budget>;
      final savingGoals = results[3] as List<SavingGoal>;

      // 1. Tính tổng thu/chi tháng này
      double totalExp = 0;
      double totalInc = 0;
      for (final tx in currentTx) {
        if (tx.type == 'expense') {
          totalExp += tx.amount;
        } else if (tx.type == 'income') {
          totalInc += tx.amount;
        }
      }
      final sav = totalInc - totalExp;

      // 2. Tính tổng chi tháng trước & 2 tháng trước
      final lastExp = lastMonthTx
          .where((t) => t.type == 'expense')
          .fold<double>(0, (a, t) => a + t.amount);

      final twoMonthsAgoExp = twoMonthsAgoTx
          .where((t) => t.type == 'expense')
          .fold<double>(0, (a, t) => a + t.amount);

      // % Thay đổi chi tiêu so với tháng trước
      double? pChange;
      if (lastExp > 0) {
        pChange = ((totalExp - lastExp) / lastExp) * 100;
      }

      // 3. Gom chi tiêu theo danh mục tháng này & tháng trước + đếm số giao dịch
      final Map<String, double> catTotals = {};
      final Map<String, int> catTxCounts = {};
      for (final tx in currentTx.where((t) => t.type == 'expense')) {
        catTotals[tx.categoryId] = (catTotals[tx.categoryId] ?? 0) + tx.amount;
        catTxCounts[tx.categoryId] = (catTxCounts[tx.categoryId] ?? 0) + 1;
      }

      final Map<String, double> lastCatTotals = {};
      for (final tx in lastMonthTx.where((t) => t.type == 'expense')) {
        lastCatTotals[tx.categoryId] =
            (lastCatTotals[tx.categoryId] ?? 0) + tx.amount;
      }

      // 4. Nhãn & số tiền biểu đồ 3 tháng
      final m2 = DateTime(now.year, now.month - 2, 1).month;
      final m1 = DateTime(now.year, now.month - 1, 1).month;
      final m0 = now.month;
      final month2Label = AppLocalizations.tr('common_month_short_$m2');
      final month1Label = AppLocalizations.tr('common_month_short_$m1');
      final month0Label = AppLocalizations.tr('common_month_short_$m0');

      final trendAmts = [twoMonthsAgoExp, lastExp, totalExp];
      final trendLabels = [month2Label, month1Label, month0Label];

      // 5. Sinh danh sách Đánh giá quan trọng từ AI (Logic Dart thuần từ số liệu thật)
      final generatedInsights = _generateInsights(
        budgets: budgets,
        categories: categories,
        catTotals: catTotals,
        lastCatTotals: lastCatTotals,
        savingGoals: savingGoals,
        totalExp: totalExp,
        totalInc: totalInc,
        lastExp: lastExp,
        percentChange: pChange,
      );

      if (!mounted) return;
      setState(() {
        _totalExpense = totalExp;
        _savings = sav;
        _lastMonthExpense = lastExp;
        _percentChange = pChange;

        _categoryTotals = catTotals;
        _lastCategoryTotals = lastCatTotals;
        _categoryTxCounts = catTxCounts;
        _categories = categories;
        _selectedCategoryIndex = 0;

        _trendAmounts = trendAmts;
        _trendMonthLabels = trendLabels;
        _insights = generatedInsights;

        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('AI Report Data Load error: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _errorMessage = AppLocalizations.tr('ai_rep_load_error');
        _isLoading = false;
      });
    }
  }

  /// Sinh danh sách insight từ dữ liệu thật (Dart thuần, không bịa số liệu)
  List<_ReportInsight> _generateInsights({
    required List<Budget> budgets,
    required List<Category> categories,
    required Map<String, double> catTotals,
    required Map<String, double> lastCatTotals,
    required List<SavingGoal> savingGoals,
    required double totalExp,
    required double totalInc,
    required double lastExp,
    required double? percentChange,
  }) {
    final List<_ReportInsight> result = [];

    // 1. Phân tích Ngân sách hoặc Tỷ trọng danh mục lớn nhất
    Budget? alertBudget;
    double alertSpent = 0;
    for (final b in budgets) {
      final spent = catTotals[b.categoryId] ?? 0;
      if (b.isOverBudget(spent) || b.isNearLimit(spent)) {
        alertBudget = b;
        alertSpent = spent;
        break;
      }
    }

    if (alertBudget != null) {
      final cat = categories
          .where((c) => c.categoryId == alertBudget!.categoryId)
          .firstOrNull;
      final catName = cat != null
          ? CategoryLocalizationHelper.localizeName(cat.name)
          : AppLocalizations.tr('ai_rep_default_cat');
      final usedPct = (alertBudget.percentUsed(alertSpent) * 100).round();
      if (alertBudget.isOverBudget(alertSpent)) {
        result.add(_ReportInsight(
          tag: AppLocalizations.tr('ai_rep_tag_budget'),
          metricBadge: AppLocalizations.tr(
            'ai_rep_badge_over_pct',
            params: {'pct': '${usedPct - 100}'},
          ),
          title: AppLocalizations.tr(
            'ai_rep_title_over_budget',
            params: {'category': catName},
          ),
          description: AppLocalizations.tr(
            'ai_rep_desc_over_budget',
            params: {
              'spent': AppFormatters.compactCurrency(alertSpent, unit: '₫'),
              'limit':
                  AppFormatters.compactCurrency(alertBudget.limit, unit: '₫'),
            },
          ),
          type: _InsightType.warning,
        ));
      } else {
        result.add(_ReportInsight(
          tag: AppLocalizations.tr('ai_rep_tag_budget'),
          metricBadge: AppLocalizations.tr(
            'ai_rep_badge_hit_pct',
            params: {'pct': '$usedPct'},
          ),
          title: AppLocalizations.tr(
            'ai_rep_title_near_budget',
            params: {'category': catName},
          ),
          description: AppLocalizations.tr(
            'ai_rep_desc_near_budget',
            params: {
              'spent': AppFormatters.compactCurrency(alertSpent, unit: '₫'),
              'limit':
                  AppFormatters.compactCurrency(alertBudget.limit, unit: '₫'),
            },
          ),
          type: _InsightType.warning,
        ));
      }
    } else if (catTotals.isNotEmpty && totalExp > 0) {
      final sortedCats = catTotals.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topEntry = sortedCats.first;
      final topCat = categories
          .where((c) => c.categoryId == topEntry.key)
          .firstOrNull;
      final topName = topCat != null
          ? CategoryLocalizationHelper.localizeName(topCat.name)
          : AppLocalizations.tr('common_other');
      final topPct = ((topEntry.value / totalExp) * 100).round();

      if (topPct >= 55) {
        result.add(_ReportInsight(
          tag: AppLocalizations.tr('ai_rep_tag_focus'),
          metricBadge: AppLocalizations.tr(
            'ai_rep_badge_pct_total',
            params: {'pct': '$topPct'},
          ),
          title: AppLocalizations.tr(
            'ai_rep_title_top_cat',
            params: {'category': topName},
          ),
          description: AppLocalizations.tr(
            'ai_rep_desc_top_cat',
            params: {
              'category': topName,
              'pct': '$topPct',
              'amount':
                  AppFormatters.compactCurrency(topEntry.value, unit: '₫'),
            },
          ),
          type: topPct >= 70 ? _InsightType.warning : _InsightType.info,
        ));
      } else {
        result.add(_ReportInsight(
          tag: AppLocalizations.tr('ai_rep_tag_structure'),
          metricBadge: AppLocalizations.tr(
            'ai_rep_badge_top1',
            params: {'pct': '$topPct'},
          ),
          title: AppLocalizations.tr('ai_rep_title_balanced'),
          description: AppLocalizations.tr(
            'ai_rep_desc_balanced',
            params: {
              'category': topName,
              'amount':
                  AppFormatters.compactCurrency(topEntry.value, unit: '₫'),
              'pct': '$topPct',
            },
          ),
          type: _InsightType.positive,
        ));
      }
    }

    // 2. Phân tích Xu hướng kỳ này so với tháng trước
    String? reducedCatName;
    double maxReducedPct = 0;
    double maxReducedDiff = 0;
    lastCatTotals.forEach((catId, lastAmt) {
      if (lastAmt > 0) {
        final curAmt = catTotals[catId] ?? 0;
        final pct = ((lastAmt - curAmt) / lastAmt) * 100;
        if (pct >= 10 && pct > maxReducedPct) {
          maxReducedPct = pct;
          maxReducedDiff = lastAmt - curAmt;
          final cat =
              categories.where((c) => c.categoryId == catId).firstOrNull;
          reducedCatName = cat != null
              ? CategoryLocalizationHelper.localizeName(cat.name)
              : null;
        }
      }
    });

    if (percentChange != null && percentChange <= -5) {
      final savedVsLast = lastExp - totalExp;
      final extraCat = reducedCatName != null
          ? AppLocalizations.tr(
              'ai_rep_desc_saved_cat_extra',
              params: {
                'category': reducedCatName!,
                'pct': '${maxReducedPct.round()}',
              },
            )
          : '';
      result.add(_ReportInsight(
        tag: AppLocalizations.tr('ai_rep_tag_good_trend'),
        metricBadge: AppLocalizations.tr(
          'ai_rep_badge_dec_pct',
          params: {'pct': percentChange.abs().toStringAsFixed(1)},
        ),
        title: reducedCatName != null
            ? AppLocalizations.tr(
                'ai_rep_title_cut_cat',
                params: {'category': reducedCatName!},
              )
            : AppLocalizations.tr('ai_rep_title_cool_down'),
        description: AppLocalizations.tr(
          'ai_rep_desc_saved_vs_last',
          params: {
            'amount': AppFormatters.compactCurrency(savedVsLast, unit: '₫'),
            'extra': extraCat,
          },
        ),
        type: _InsightType.positive,
      ));
    } else if (percentChange != null && percentChange >= 10) {
      final extraVsLast = totalExp - lastExp;
      result.add(_ReportInsight(
        tag: AppLocalizations.tr('ai_rep_tag_spend_var'),
        metricBadge: AppLocalizations.tr(
          'ai_rep_badge_inc_pct',
          params: {'pct': percentChange.toStringAsFixed(1)},
        ),
        title: AppLocalizations.tr('ai_rep_title_spend_up'),
        description: AppLocalizations.tr(
          'ai_rep_desc_spend_up',
          params: {
            'amount': AppFormatters.compactCurrency(extraVsLast, unit: '₫'),
          },
        ),
        type: _InsightType.warning,
      ));
    } else if (reducedCatName != null) {
      result.add(_ReportInsight(
        tag: AppLocalizations.tr('ai_rep_tag_opt_group'),
        metricBadge: '-${maxReducedPct.round()}%',
        title: AppLocalizations.tr(
          'ai_rep_title_cat_saved',
          params: {'category': reducedCatName!},
        ),
        description: AppLocalizations.tr(
          'ai_rep_desc_cat_saved',
          params: {
            'category': reducedCatName!,
            'amount': AppFormatters.compactCurrency(maxReducedDiff, unit: '₫'),
          },
        ),
        type: _InsightType.positive,
      ));
    }

    // 3. Phân tích Cân đối Thu - Chi & Mục tiêu tiết kiệm
    SavingGoal? completedGoal;
    SavingGoal? activeGoal;
    for (final g in savingGoals) {
      if (g.targetAmount > 0) {
        final pct = g.savedAmount / g.targetAmount;
        if (pct >= 1.0) {
          completedGoal = g;
          break;
        } else if (pct >= 0.25 && activeGoal == null) {
          activeGoal = g;
        }
      }
    }

    final netSav = totalInc - totalExp;
    if (totalInc == 0 && totalExp > 0) {
      result.add(_ReportInsight(
        tag: AppLocalizations.tr('ai_rep_tag_cashflow'),
        metricBadge: AppLocalizations.tr('ai_rep_badge_no_income'),
        title: AppLocalizations.tr('ai_rep_title_no_income'),
        description: AppLocalizations.tr(
          'ai_rep_desc_no_income',
          params: {'amount': AppFormatters.compactCurrency(totalExp, unit: '₫')},
        ),
        type: _InsightType.warning,
      ));
    } else if (netSav < 0 && totalInc > 0) {
      result.add(_ReportInsight(
        tag: AppLocalizations.tr('ai_rep_tag_cashflow'),
        metricBadge: AppLocalizations.tr(
          'ai_rep_badge_deficit',
          params: {
            'amount': AppFormatters.compactCurrency(netSav.abs(), unit: '₫'),
          },
        ),
        title: AppLocalizations.tr('ai_rep_title_over_income'),
        description: AppLocalizations.tr(
          'ai_rep_desc_over_income',
          params: {
            'amount': AppFormatters.compactCurrency(netSav.abs(), unit: '₫'),
          },
        ),
        type: _InsightType.warning,
      ));
    } else if (completedGoal != null) {
      result.add(_ReportInsight(
        tag: AppLocalizations.tr('ai_rep_tag_saving'),
        metricBadge: AppLocalizations.tr('ai_rep_badge_goal_100'),
        title: AppLocalizations.tr('ai_rep_title_goal_done'),
        description: AppLocalizations.tr(
          'ai_rep_desc_goal_done',
          params: {
            'amount': AppFormatters.compactCurrency(
              completedGoal.targetAmount,
              unit: '₫',
            ),
            'name': completedGoal.name,
          },
        ),
        type: _InsightType.success,
      ));
    } else if (activeGoal != null) {
      final pct =
          (activeGoal.savedAmount / activeGoal.targetAmount * 100).round();
      result.add(_ReportInsight(
        tag: AppLocalizations.tr('ai_rep_tag_saving'),
        metricBadge: AppLocalizations.tr(
          'ai_rep_badge_goal_pct',
          params: {'pct': '$pct'},
        ),
        title: AppLocalizations.tr('ai_rep_title_goal_progress'),
        description: AppLocalizations.tr(
          'ai_rep_desc_goal_progress',
          params: {
            'name': activeGoal.name,
            'saved':
                AppFormatters.compactCurrency(activeGoal.savedAmount, unit: '₫'),
            'target': AppFormatters.compactCurrency(
              activeGoal.targetAmount,
              unit: '₫',
            ),
          },
        ),
        type: _InsightType.success,
      ));
    } else if (totalInc > 0 && netSav >= 0) {
      final saveRate = ((netSav / totalInc) * 100).round();
      result.add(_ReportInsight(
        tag: AppLocalizations.tr('ai_rep_tag_cashflow'),
        metricBadge: AppLocalizations.tr(
          'ai_rep_badge_save_rate',
          params: {'pct': '$saveRate'},
        ),
        title: AppLocalizations.tr('ai_rep_title_surplus'),
        description: AppLocalizations.tr(
          'ai_rep_desc_surplus',
          params: {
            'amount': AppFormatters.compactCurrency(netSav, unit: '₫'),
            'pct': '$saveRate',
          },
        ),
        type: _InsightType.success,
      ));
    }

    return result.take(3).toList();
  }

  /// Chia phần trăm theo phương pháp Largest Remainder để tổng luôn bằng 100%
  List<int> _computeExactPercentages(
    List<MapEntry<String, double>> entries,
    double total,
  ) {
    if (entries.isEmpty || total <= 0) {
      return List.filled(entries.length, 0);
    }
    final raw = entries.map((e) => (e.value / total) * 100).toList();
    final floors = raw.map((p) => p.floor()).toList();
    final remainders =
        List.generate(entries.length, (i) => raw[i] - floors[i]);

    final sumFloors = floors.fold<int>(0, (a, b) => a + b);
    final diff = 100 - sumFloors;

    final indices = List.generate(entries.length, (i) => i);
    indices.sort((a, b) {
      final cmp = remainders[b].compareTo(remainders[a]);
      if (cmp != 0) return cmp;
      return entries[b].value.compareTo(entries[a].value);
    });

    for (var i = 0; i < diff && i < indices.length; i++) {
      floors[indices[i]] += 1;
    }
    return floors;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          context.tr('ai_rep_appbar_title'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Material(
                color: AppColors.aiAccent.withValues(alpha: 0.15),
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(
                    Icons.auto_awesome,
                    color: AppColors.aiAccent,
                    size: 22,
                  ),
                  tooltip: context.tr('ai_rep_insights_tooltip'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AiInsightScreen(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(now),
    );
  }

  Widget _buildBody(DateTime now) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              context.tr('ai_rep_loading'),
              style: TextStyle(color: context.appTextSecondary),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
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
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.appTextSecondary),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadReportData,
                icon: const Icon(Icons.refresh),
                label: Text(context.tr('common_retry')),
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Hero Card nền tối cố định
        _buildHeroCard(now),
        const SizedBox(height: 16),

        // 2. Card Cơ cấu chi tiêu (Hiện đại & Tương tác)
        _buildExpenseStructureCard(now),
        const SizedBox(height: 16),

        // 3. Card Xu hướng chi tiêu 3 tháng (Biểu đồ FinTech & KPI Strip)
        _buildTrendCard(),
        const SizedBox(height: 16),

        // 4. Card Đánh giá quan trọng từ AI (Thẻ nhận định thông minh)
        _buildInsightsCard(),
        const SizedBox(height: 24),

        // 5. Hàng nút action cuối trang
        _buildActionButtons(),
        const SizedBox(height: 16),
      ],
    );
  }

  // ============================================================
  // 1. HERO CARD (Khớp phong cách với Recurring Transaction Screen)
  // ============================================================
  Widget _buildHeroCard(DateTime now) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F6F8B), Color(0xFF134A5D)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: "BÁO CÁO THÁNG N" + badge "AI Generated"
          AiReportHeroHeaderRow(
            title: context.tr(
              'ai_rep_banner_title',
              params: {
                'month': '${now.month}',
                'year': '${now.year}',
              },
            ),
            badgeLabel: context.tr('ai_rep_ai_generated'),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('ai_rep_total_expense_month'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _totalExpense.abs() >= 1e9
                  ? AppFormatters.compactCurrency(_totalExpense)
                  : AppFormatters.currency(_totalExpense),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('ai_rep_net_savings'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          AppFormatters.compactCurrency(_savings),
                          style: TextStyle(
                            color: _savings >= 0
                                ? const Color(0xFF56D69B)
                                : const Color(0xFFFF8B80),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 32,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('ai_rep_vs_last_month'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (_lastMonthExpense == 0)
                        Text(
                          context.tr('ai_rep_no_prev_period'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 13,
                          ),
                        )
                      else if (_percentChange != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _percentChange! <= 0
                                  ? Icons.trending_down_rounded
                                  : Icons.trending_up_rounded,
                              size: 16,
                              color: _percentChange! <= 0
                                  ? const Color(0xFF56D69B)
                                  : const Color(0xFFFF8B80),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  context.tr(
                                    _percentChange! <= 0
                                        ? 'ai_rep_change_dec'
                                        : 'ai_rep_change_inc',
                                    params: {
                                      'pct': _percentChange!
                                          .abs()
                                          .toStringAsFixed(1),
                                    },
                                  ),
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: _percentChange! <= 0
                                        ? const Color(0xFF56D69B)
                                        : const Color(0xFFFF8B80),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          context.tr('ai_rep_no_prev_period'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 13,
                          ),
                        ),
                    ],
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
  // 2. CARD CƠ CẤU CHI TIÊU (Interactive Donut + Stacked Bar + Rich List)
  // ============================================================
  Widget _buildExpenseStructureCard(DateTime now) {
    final entries = _categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (a, e) => a + e.value);
    final percentages = _computeExactPercentages(entries, total);
    final safeSelectedIdx = entries.isEmpty
        ? 0
        : _selectedCategoryIndex.clamp(0, entries.length - 1);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.donut_large_rounded,
                  size: 19,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('ai_rep_spend_structure'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entries.isEmpty
                          ? context.tr(
                              'ai_rep_month_yr_label',
                              params: {
                                'month': '${now.month}',
                                'year': '${now.year}',
                              },
                            )
                          : context.tr('ai_rep_tap_chart_hint'),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (entries.isNotEmpty) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        context.tr(
                          'ai_rep_cat_count',
                          params: {'count': '${entries.length}'},
                        ),
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),

          if (entries.isEmpty || total <= 0)
            Container(
              height: 130,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.appInputFill.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.pie_chart_outline_rounded,
                    size: 36,
                    color: context.appTextSecondary.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('ai_rep_no_expense_month'),
                    style: TextStyle(
                      color: context.appTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // Hàng 1: Interactive Donut (Trái) + Spotlight Card của danh mục đang chọn (Phải)
            Row(
              children: [
                SizedBox(
                  width: 136,
                  height: 136,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          pieTouchData: PieTouchData(
                            touchCallback: (event, pieTouchResponse) {
                              if (event is FlTapUpEvent &&
                                  pieTouchResponse?.touchedSection != null) {
                                final idx = pieTouchResponse!
                                    .touchedSection!.touchedSectionIndex;
                                if (idx >= 0 && idx < entries.length) {
                                  setState(() => _selectedCategoryIndex = idx);
                                }
                              }
                            },
                          ),
                          sectionsSpace: 3,
                          centerSpaceRadius: 38,
                          startDegreeOffset: -90,
                          sections: List.generate(entries.length, (i) {
                            final isSelected = i == safeSelectedIdx;
                            final baseColor =
                                _chartColors[i % _chartColors.length];
                            return PieChartSectionData(
                              value: entries[i].value,
                              color: isSelected
                                  ? baseColor
                                  : baseColor.withValues(alpha: 0.78),
                              title: '',
                              radius: isSelected ? 27 : 22,
                              borderSide: isSelected
                                  ? BorderSide(
                                      color: context.appCard,
                                      width: 2,
                                    )
                                  : BorderSide.none,
                            );
                          }),
                        ),
                      ),
                      // Tâm Donut hiển thị % của danh mục đang chọn
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${percentages[safeSelectedIdx]}%',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _chartColors[
                                  safeSelectedIdx % _chartColors.length],
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                          Text(
                            context.tr('ai_rep_share_col'),
                            style: TextStyle(
                              fontSize: 10,
                              color: context.appTextSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // Spotlight Card cho danh mục đang chọn
                Expanded(
                  child: _buildCategorySpotlight(
                    entry: entries[safeSelectedIdx],
                    rank: safeSelectedIdx + 1,
                    percentage: percentages[safeSelectedIdx],
                    color: _chartColors[safeSelectedIdx % _chartColors.length],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Hàng 2: Thanh Stacked Progress Bar hiển thị trực quan tỷ trọng
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: List.generate(entries.length, (i) {
                    final flexVal =
                        ((entries[i].value / total) * 1000).round().clamp(15, 1000);
                    final color = _chartColors[i % _chartColors.length];
                    final isSelected = i == safeSelectedIdx;
                    return Expanded(
                      flex: flexVal,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedCategoryIndex = i),
                        child: Container(
                          margin: EdgeInsets.only(
                            right: i == entries.length - 1 ? 0 : 2,
                          ),
                          color: isSelected
                              ? color
                              : color.withValues(alpha: 0.72),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Hàng 3: Danh sách chi tiết các danh mục
            Column(
              children: List.generate(entries.length, (i) {
                final catId = entries[i].key;
                final amount = entries[i].value;
                final cat = _categories
                    .where((c) => c.categoryId == catId)
                    .firstOrNull;
                final catName = cat != null
                    ? CategoryLocalizationHelper.localizeNameWithContext(
                        context, cat.name)
                    : context.tr('common_other');
                final pct = percentages[i];
                final ratio = (amount / total).clamp(0.0, 1.0);
                final color = _chartColors[i % _chartColors.length];
                final isSelected = i == safeSelectedIdx;
                final txCount = _categoryTxCounts[catId] ?? 1;

                return Padding(
                  padding: EdgeInsets.only(
                    bottom: i == entries.length - 1 ? 0 : 8,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _selectedCategoryIndex = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withValues(
                                alpha: context.isDarkMode ? 0.14 : 0.07,
                              )
                            : context.isDarkMode
                                ? AppColors.slate900.withValues(alpha: 0.35)
                                : AppColors.slate50.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? color.withValues(alpha: 0.45)
                              : context.appBorder.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  categoryIconData(cat?.icon),
                                  size: 17,
                                  color: color,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      catName,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: context.appTextPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      context.tr(
                                        'ai_rep_tx_count',
                                        params: {'count': '$txCount'},
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
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    AppFormatters.compactCurrency(
                                      amount,
                                      unit: '₫',
                                    ),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: context.appTextPrimary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      '$pct%',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 4,
                              backgroundColor:
                                  context.appBorder.withValues(alpha: 0.5),
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  /// Thẻ Spotlight bên phải Donut hiển thị nổi bật danh mục đang được chọn
  Widget _buildCategorySpotlight({
    required MapEntry<String, double> entry,
    required int rank,
    required int percentage,
    required Color color,
  }) {
    final catId = entry.key;
    final amount = entry.value;
    final cat = _categories.where((c) => c.categoryId == catId).firstOrNull;
    final catName = cat != null
        ? CategoryLocalizationHelper.localizeNameWithContext(context, cat.name)
        : context.tr('common_other');
    final txCount = _categoryTxCounts[catId] ?? 1;
    final lastAmt = _lastCategoryTotals[catId] ?? 0;

    double? diffPct;
    if (lastAmt > 0) {
      diffPct = ((amount - lastAmt) / lastAmt) * 100;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDarkMode ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      context.tr(
                        'ai_rep_rank_badge',
                        params: {'rank': '$rank'},
                      ),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                categoryIconData(cat?.icon),
                size: 16,
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            catName,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: context.appTextPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              AppFormatters.compactCurrency(amount, unit: '₫'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.receipt_long_rounded,
                size: 12,
                color: context.appTextSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  diffPct != null
                      ? context.tr(
                          diffPct <= 0
                              ? 'ai_rep_cat_diff_dec'
                              : 'ai_rep_cat_diff_inc',
                          params: {
                            'count': '$txCount',
                            'pct': '${diffPct.abs().round()}',
                          },
                        )
                      : context.tr(
                          'ai_rep_cat_tx_in_month',
                          params: {'count': '$txCount'},
                        ),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: context.appTextSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 3. CARD XU HƯỚNG CHI TIÊU 3 THÁNG
  // ============================================================
  Widget _buildTrendCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.appBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWideHeader = constraints.maxWidth >= 380;

          final legendRow = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SpendingTrendBarChart.buildLegendDot(
                context,
                color: AppColors.primary,
                label: context.tr('trend_current_period'),
              ),
              const SizedBox(width: 14),
              SpendingTrendBarChart.buildLegendDot(
                context,
                color: AppColors.warning,
                label: context.tr('trend_peak_spend'),
              ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header + Legend
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.stacked_bar_chart_rounded,
                      size: 19,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('ai_rep_trend_3m_title'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5,
                            color: context.appTextPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.tr('ai_rep_trend_3m_sub'),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: context.appTextSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isWideHeader) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: legendRow,
                      ),
                    ),
                  ],
                ],
              ),
              if (!isWideHeader) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: legendRow,
                ),
              ],
              const SizedBox(height: 12),

              // Biểu đồ đường cong diện tích + dải tóm tắt 3 cột
              SpendingTrendBarChart(
                amounts: _trendAmounts,
                monthLabels: _trendMonthLabels,
                showLegend: false,
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // 4. CARD ĐÁNH GIÁ QUAN TRỌNG TỪ AI (Modern FinTech Insight Cards)
  // ============================================================
  Widget _buildInsightsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 19,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('ai_rep_key_findings_title'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('ai_rep_key_findings_sub'),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_insights.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    context.tr(
                      'ai_rep_insight_count',
                      params: {'count': '${_insights.length}'},
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          if (_insights.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.appInputFill.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    color: context.appTextSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('ai_rep_no_insights'),
                      style: TextStyle(
                        color: context.appTextSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: List.generate(_insights.length, (i) {
                final insight = _insights[i];
                final isLast = i == _insights.length - 1;

                final Color accentColor;
                final IconData iconData;

                switch (insight.type) {
                  case _InsightType.positive:
                    accentColor = AppColors.income;
                    iconData = Icons.trending_down_rounded;
                    break;
                  case _InsightType.warning:
                    accentColor = AppColors.warning;
                    iconData = Icons.warning_amber_rounded;
                    break;
                  case _InsightType.success:
                    accentColor = AppColors.income;
                    iconData = Icons.verified_rounded;
                    break;
                  case _InsightType.info:
                    accentColor = AppColors.primary;
                    iconData = Icons.lightbulb_outline_rounded;
                    break;
                }

                return Container(
                  margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(
                      alpha: context.isDarkMode ? 0.10 : 0.05,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Thanh điểm nhấn dọc bên trái
                        Container(
                          width: 4.5,
                          decoration: BoxDecoration(
                            color: accentColor,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(14),
                              bottomLeft: Radius.circular(14),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Hàng Tag + Metric Badge
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: accentColor.withValues(
                                          alpha: 0.16,
                                        ),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: Icon(
                                        iconData,
                                        color: accentColor,
                                        size: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        insight.tag,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                          color: accentColor,
                                        ),
                                      ),
                                    ),
                                    if (insight.metricBadge != null) ...[
                                      const SizedBox(width: 8),
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 135),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: context.appCard,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color: accentColor.withValues(
                                                alpha: 0.3,
                                              ),
                                            ),
                                          ),
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              insight.metricBadge!,
                                              maxLines: 1,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: accentColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  insight.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: context.appTextPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  insight.description,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: context.appTextSecondary,
                                    height: 1.4,
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
              }),
            ),

          const SizedBox(height: 14),
          // Nút điều hướng nhanh sang Trung tâm Phân tích & Dự báo AI chuyên sâu
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AiInsightScreen(),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(
                  alpha: context.isDarkMode ? 0.16 : 0.08,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.psychology_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('ai_rep_deep_cta'),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 13,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportPdfReport() async {
    if (_isExportingPdf) return;
    setState(() => _isExportingPdf = true);

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = DateTime(now.year, now.month, 0, 23, 59, 59);

    final twoMonthsAgoStart = DateTime(now.year, now.month - 2, 1);
    final twoMonthsAgoEnd = DateTime(now.year, now.month - 1, 0, 23, 59, 59);

    final threeMonthsAgoStart = DateTime(now.year, now.month - 3, 1);
    final threeMonthsAgoEnd = DateTime(now.year, now.month - 2, 0, 23, 59, 59);

    try {
      Future<List<AppTransaction>> fetchWindowTransactions() async {
        try {
          return await _firestoreService.getTransactionsByDateWindow(
            uid,
            from: threeMonthsAgoStart,
            to: monthEnd,
          );
        } catch (_) {
          return await _firestoreService.getTransactionsSafely(uid);
        }
      }

      final results = await Future.wait<dynamic>([
        fetchWindowTransactions(),
        _firestoreService.getWalletsSafely(uid),
        _firestoreService.getCategoriesSafely(uid),
        _firestoreService.getBudgetsSafely(uid, month: AppFormatters.month(now)),
        _firestoreService.getSavingGoalsSafely(uid),
        _firestoreService.getUserProfile(uid),
        _firestoreService.streamRecurringTransactions(uid).first,
      ]);

      final windowTx = results[0] as List<AppTransaction>;
      final wallets = results[1] as List<Wallet>;
      final categories = results[2] as List<Category>;
      final budgets = results[3] as List<Budget>;
      final savingGoals = results[4] as List<SavingGoal>;
      final userProfile = results[5] as AppUser?;
      final recurringSchedules =
          results[6] as List<RecurringTransactionSchedule>;

      final currentTx = windowTx
          .where((t) =>
              t.date.isAfter(monthStart.subtract(const Duration(seconds: 1))) &&
              t.date.isBefore(monthEnd.add(const Duration(seconds: 1))))
          .toList();
      final lastMonthTx = windowTx
          .where((t) =>
              t.date.isAfter(
                  lastMonthStart.subtract(const Duration(seconds: 1))) &&
              t.date.isBefore(lastMonthEnd.add(const Duration(seconds: 1))))
          .toList();
      final twoMonthsAgoTx = windowTx
          .where((t) =>
              t.date.isAfter(
                  twoMonthsAgoStart.subtract(const Duration(seconds: 1))) &&
              t.date.isBefore(twoMonthsAgoEnd.add(const Duration(seconds: 1))))
          .toList();
      final threeMonthsAgoTx = windowTx
          .where((t) =>
              t.date.isAfter(
                  threeMonthsAgoStart.subtract(const Duration(seconds: 1))) &&
              t.date.isBefore(
                  threeMonthsAgoEnd.add(const Duration(seconds: 1))))
          .toList();

      final analyticsService = FinancialAnalyticsService();
      final declaredIncome =
          (userProfile != null && userProfile.monthlyIncome > 0)
              ? userProfile.monthlyIncome
              : null;
      final sufficiency = analyticsService.assessDataSufficiency(
        currentMonthTx: currentTx,
        historicalMonthsTx: [lastMonthTx, twoMonthsAgoTx, threeMonthsAgoTx],
        currentBudgets: budgets,
        wallets: wallets,
        savingGoals: savingGoals,
        referenceToday: now,
      );
      final incomeAssessment = analyticsService.determineReferenceIncome(
        currentMonthTx: currentTx,
        historicalMonthsTx: [lastMonthTx, twoMonthsAgoTx, threeMonthsAgoTx],
        currentBudgets: budgets,
        declaredExpectedIncome: declaredIncome,
        isPartialMonth: sufficiency.isPartialMonth,
      );

      final reportData = _exportService.buildReportData(
        currentPeriodTx: currentTx,
        wallets: wallets,
        categories: categories,
        budgets: budgets,
        savingGoals: savingGoals,
        periodLabel: AppLocalizations.tr(
          'ai_rep_month_yr_label',
          params: {'month': '${now.month}', 'year': '${now.year}'},
        ),
        isCurrentMonth: true,
        lastMonthTx:
            sufficiency.canCompareMonthOverMonth ? lastMonthTx : const [],
        preceding3MonthsTx: [threeMonthsAgoTx, twoMonthsAgoTx, lastMonthTx],
        monthlyIncome: incomeAssessment.referenceIncome,
        recurringSchedules: recurringSchedules,
        refDate: now,
      );

      final pdfBytes =
          await _exportService.generateFinancialReportPdf(data: reportData);
      final filename =
          'finance_ai_report_${now.year}-${now.month.toString().padLeft(2, '0')}';
      final pdfFile = await _exportService.savePdfToFile(pdfBytes, filename);

      if (!mounted) return;
      AppSnackbar.show(context, AppLocalizations.tr('ai_rep_pdf_created'));

      await _exportService.shareFile(
        pdfFile.path,
        text: AppLocalizations.tr(
          'ai_rep_pdf_share_text',
          params: {'month': '${now.month}', 'year': '${now.year}'},
        ),
        subject: AppLocalizations.tr('ai_rep_pdf_share_subject'),
      );
    } catch (e) {
      debugPrint('Export PDF Error: $e');
      if (!mounted) return;
      AppSnackbar.show(
        context,
        AppLocalizations.tr('ai_rep_pdf_error', params: {'error': '$e'}),
      );
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
    }
  }

  Future<void> _exportCsvReport() async {
    if (_isExportingCsv) return;
    setState(() => _isExportingCsv = true);

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    try {
      final results = await Future.wait<dynamic>([
        _firestoreService
            .streamTransactions(uid, from: monthStart, to: monthEnd)
            .first,
        _firestoreService.streamCategories(uid).first,
        _firestoreService.streamWallets(uid).first,
        _firestoreService.streamSavingGoals(uid).first,
      ]);

      final transactions = results[0] as List<AppTransaction>;
      final categories = results[1] as List<Category>;
      final wallets = results[2] as List<Wallet>;
      final savingGoals = results[3] as List<SavingGoal>;

      final filename =
          'finance_ai_transactions_${now.year}-${now.month.toString().padLeft(2, '0')}';
      final csvFile = await _exportService.exportTransactionsCsv(
        transactions: transactions,
        categories: categories,
        wallets: wallets,
        savingGoals: savingGoals,
        filenamePrefix: filename,
      );

      if (!mounted) return;
      AppSnackbar.show(context, AppLocalizations.tr('ai_rep_csv_exported'));

      await _exportService.shareFile(
        csvFile.path,
        text: AppLocalizations.tr(
          'ai_rep_csv_share_text',
          params: {'month': '${now.month}', 'year': '${now.year}'},
        ),
        subject: AppLocalizations.tr('ai_rep_csv_share_subject'),
      );
    } catch (e) {
      debugPrint('Export CSV Error: $e');
      if (!mounted) return;
      final msg = e is ExportException
          ? e.message
          : AppLocalizations.tr('ai_rep_csv_error', params: {'error': '$e'});
      AppSnackbar.show(context, msg);
    } finally {
      if (mounted) {
        setState(() => _isExportingCsv = false);
      }
    }
  }

  // ============================================================
  // 5. HÀNG NÚT ACTION CUỐI TRANG
  // ============================================================
  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isExportingPdf ? null : _exportPdfReport,
                icon: const Icon(Icons.share_outlined, size: 18),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(context.tr('ai_rep_share_btn'), maxLines: 1),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.appTextPrimary,
                  side: BorderSide(color: context.appBorder),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _isExportingPdf ? null : _exportPdfReport,
                icon: _isExportingPdf
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _isExportingPdf
                        ? context.tr('ai_rep_exporting_pdf')
                        : context.tr('ai_rep_export_pdf_btn'),
                    maxLines: 1,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isExportingCsv ? null : _exportCsvReport,
            icon: _isExportingCsv
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.table_chart_outlined, size: 17),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _isExportingCsv
                    ? context.tr('ai_rep_exporting_csv')
                    : context.tr('ai_rep_export_csv_btn'),
                maxLines: 1,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.appTextSecondary,
              side: BorderSide(color: context.appBorder),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Hàng header trong hero card Báo cáo AI: tiêu đề tháng/năm và nhãn "AI Generated",
/// giữ bố cục cân đối và chống tràn pixel khi chuyển ngôn ngữ.
class AiReportHeroHeaderRow extends StatelessWidget {
  final String title;
  final String badgeLabel;

  const AiReportHeroHeaderRow({
    super.key,
    required this.title,
    required this.badgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 145),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 12,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    badgeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
