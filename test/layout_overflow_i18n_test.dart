import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_ai_app/l10n/app_localizations.dart';
import 'package:finance_ai_app/models/budget_model.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/quick_template.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/screens/about_app_screen.dart';
import 'package:finance_ai_app/screens/ai/ai_insight_screen.dart';
import 'package:finance_ai_app/screens/ai/ai_report_screen.dart';
import 'package:finance_ai_app/screens/auth/forgot_password_screen.dart';
import 'package:finance_ai_app/services/language_controller.dart';
import 'package:finance_ai_app/utils/constants.dart';
import 'package:finance_ai_app/widgets/app_button.dart';
import 'package:finance_ai_app/widgets/budget_month_selector.dart';
import 'package:finance_ai_app/widgets/budget_progress_card.dart';
import 'package:finance_ai_app/widgets/dashboard_chart.dart';
import 'package:finance_ai_app/widgets/quick_template_chip.dart';
import 'package:finance_ai_app/widgets/spending_trend_bar_chart.dart';
import 'package:finance_ai_app/widgets/stream_error_widget.dart';
import 'package:finance_ai_app/widgets/transaction_card.dart';
import 'package:finance_ai_app/widgets/wallet_card.dart';
import 'package:finance_ai_app/widgets/weekly_heatmap_card.dart';

Future<void> _pumpAndAssertNoOverflow(
  WidgetTester tester, {
  required String langCode,
  required Size surfaceSize,
  double textScale = 1.0,
  required Widget Function(BuildContext context) builder,
}) async {
  await LanguageController.setLanguage(langCode);
  await tester.binding.setSurfaceSize(surfaceSize);

  final errors = <FlutterErrorDetails>[];
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.add(details);
  };

  try {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(langCode),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: Builder(builder: builder),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    final exception = tester.takeException();
    expect(exception, isNull,
        reason: 'Unexpected exception in $langCode @ $surfaceSize (scale=$textScale): $exception');
    expect(
      errors.map((e) => e.toString()).toList(),
      isEmpty,
      reason: 'Layout/Flutter errors detected in $langCode @ $surfaceSize (scale=$textScale)',
    );
  } finally {
    FlutterError.onError = previousOnError;
    await tester.binding.setSurfaceSize(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LanguageController.loadSavedLanguage();
  });

  group('Bilingual (VI/EN) Narrow-Screen Overflow Regression Tests', () {
    const viewports = [
      (size: Size(360, 780), scale: 1.0),
      (size: Size(320, 700), scale: 1.2),
    ];

    testWidgets(
      '1. AiReportHeroHeaderRow renders without overflow in VI and EN (including 320dp + 1.2x scale)',
      (tester) async {
        for (final lang in ['vi', 'en']) {
          for (final vp in viewports) {
            await _pumpAndAssertNoOverflow(
              tester,
              langCode: lang,
              surfaceSize: vp.size,
              textScale: vp.scale,
              builder: (context) => Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    color: const Color(0xFF1F6F8B),
                    child: AiReportHeroHeaderRow(
                      title: context.tr(
                        'ai_rep_banner_title',
                        params: {'month': '11', 'year': '2026'},
                      ),
                      badgeLabel: context.tr('ai_rep_ai_generated'),
                    ),
                  ),
                ),
              ),
            );
          }
        }
      },
    );

    testWidgets(
      '2. AiForecastHeadlineRow, AiInsightMetricRow, and AiSufficiencyHeaderRow render cleanly in VI and EN',
      (tester) async {
        for (final lang in ['vi', 'en']) {
          for (final vp in viewports) {
            await _pumpAndAssertNoOverflow(
              tester,
              langCode: lang,
              surfaceSize: vp.size,
              textScale: vp.scale,
              builder: (context) => Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    AiSufficiencyHeaderRow(
                      tierLabel: context.tr('ai_ins_tier_preliminary'),
                      tierColor: Colors.orange,
                      declareIncomeLabel:
                          context.tr('ai_ins_declare_income_btn'),
                      onDeclareIncome: () {},
                    ),
                    const SizedBox(height: 12),
                    AiForecastHeadlineRow(
                      label: context.tr('ai_ins_forecast_eom'),
                      amountText: '14.306.250 ₫',
                      amountColor: AppColors.income,
                    ),
                    AiInsightMetricRow(
                      label: context.tr('ai_ins_cur_total_bal'),
                      value: '17.950.000 ₫',
                    ),
                    AiInsightMetricRow(
                      label: context.tr('ai_ins_mtd_spend'),
                      value: '4.050.000 ₫',
                    ),
                    AiInsightMetricRow(
                      label: context.tr('ai_ins_daily_flex_avg'),
                      value: '253.125 ₫',
                    ),
                    AiInsightMetricRow(
                      label: context.tr('ai_ins_upcoming_rec_out'),
                      value: '-100.000 ₫',
                    ),
                    AiInsightMetricRow(
                      label: context.tr('ai_ins_days_remaining'),
                      value: context.tr('ai_ins_days_value', params: {'days': '14'}),
                    ),
                  ],
                ),
              ),
            );
          }
        }
      },
    );

    testWidgets(
      '3. WeeklyHeatmapCard & SpendingTrendBarChart render cleanly in VI and EN across narrow screens',
      (tester) async {
        for (final lang in ['vi', 'en']) {
          for (final vp in viewports) {
            await _pumpAndAssertNoOverflow(
              tester,
              langCode: lang,
              surfaceSize: vp.size,
              textScale: vp.scale,
              builder: (context) => Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const WeeklyHeatmapCard(
                      heatmapData: {
                        'Food': [0, 0, 0, 4, 0, 0, 0],
                        'Shopping': [1, 0, 2, 4, 0, 1, 0],
                      },
                    ),
                    const SizedBox(height: 12),
                    SpendingTrendBarChart(
                      amounts: const [1200000, 2500000, 4050000],
                      monthLabels: lang == 'vi'
                          ? const ['Tháng 9', 'Tháng 10', 'Tháng 11']
                          : const ['Sep', 'Oct', 'Nov'],
                      showLegend: true,
                    ),
                  ],
                ),
              ),
            );
          }
        }
      },
    );

    testWidgets(
      '4. Shared cards, buttons, month selector, and error retry widget never overflow in VI and EN',
      (tester) async {
        final now = DateTime(2026, 11, 16, 12, 0);
        final cat = Category(
          categoryId: 'c1',
          userId: 'u1',
          name: 'Mua sắm',
          type: 'expense',
          icon: 'shopping_bag',
          color: 0xFF2196F3,
        );
        final budget = Budget(
          budgetId: 'b1',
          userId: 'u1',
          categoryId: 'c1',
          limit: 5000000,
          month: '11/2026',
        );
        final wallet = Wallet(
          walletId: 'w1',
          userId: 'u1',
          walletName: 'Tiền mặt',
          balance: 15950000,
          type: 'cash',
          description: 'Ví chi tiêu hằng ngày rất dài',
          createdAt: now,
        );
        final tx = AppTransaction(
          transactionId: 't1',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'c1',
          amount: 1250000,
          type: 'goal_deposit',
          note: 'Nạp vào mục tiêu tiết kiệm "Laptop": từ ví Tiền mặt',
          date: now,
        );

        for (final lang in ['vi', 'en']) {
          for (final vp in viewports) {
            await _pumpAndAssertNoOverflow(
              tester,
              langCode: lang,
              surfaceSize: vp.size,
              textScale: vp.scale,
              builder: (context) => Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    BudgetMonthSelector(
                      month: DateTime(2026, 9, 1),
                      onTap: () {},
                      onPrevious: () {},
                      onNext: () {},
                    ),
                    const SizedBox(height: 12),
                    BudgetProgressCard(
                      budget: budget,
                      spentAmount: 6500000,
                      category: cat,
                    ),
                    const SizedBox(height: 12),
                    WalletCard(
                      wallet: wallet,
                      shareOfTotal: 0.89,
                      onMore: () {},
                    ),
                    const SizedBox(height: 8),
                    TransactionCard(
                      transaction: tx,
                      category: cat,
                      wallet: wallet,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AppOutlinedButton(
                            text: context.tr('ai_rep_share_btn'),
                            icon: Icons.share_outlined,
                            onPressed: () {},
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppButton(
                            text: context.tr('ai_rep_export_pdf_btn'),
                            icon: Icons.picture_as_pdf_outlined,
                            onPressed: () {},
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const CategoryPieChart(
                      categoryTotals: {
                        'Shopping': 1000000,
                        'Education': 500000,
                      },
                      colors: [Color(0xFF2196F3), Color(0xFF4CAF50)],
                    ),
                    const SizedBox(height: 12),
                    QuickTemplatePaginatedBar(
                      templates: [
                        QuickTemplate(
                          id: 'qt1',
                          title: 'Cà phê sáng',
                          amount: 35000,
                          type: 'expense',
                          walletId: 'w1',
                          categoryId: 'c1',
                          note: 'Cà phê',
                          location: '',
                          date: now,
                        ),
                      ],
                      onSelect: (_) {},
                    ),
                    const SizedBox(height: 12),
                    StreamErrorWidget(
                      error: 'Connection error',
                      onRetry: () {},
                    ),
                  ],
                ),
              ),
            );
          }
        }
      },
    );

    testWidgets(
      '5. Static screens (AboutAppScreen, ForgotPasswordScreen) render cleanly in VI and EN at 320dp',
      (tester) async {
        for (final lang in ['vi', 'en']) {
          for (final vp in viewports) {
            await _pumpAndAssertNoOverflow(
              tester,
              langCode: lang,
              surfaceSize: vp.size,
              textScale: vp.scale,
              builder: (_) => const AboutAppScreen(),
            );
            await _pumpAndAssertNoOverflow(
              tester,
              langCode: lang,
              surfaceSize: vp.size,
              textScale: vp.scale,
              builder: (_) => ForgotPasswordScreen(
                onSendResetEmail: (_) async {},
              ),
            );
          }
        }
      },
    );
  });
}
