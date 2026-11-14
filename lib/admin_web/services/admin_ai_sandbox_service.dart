import '../../models/ai_runtime_config_model.dart';
import '../../models/category_suggestion.dart';
import '../../models/financial_forecast_result.dart';
import '../../models/financial_issue.dart';
import '../../models/monthly_financial_plan.dart';
import '../../models/wallet_suggestion.dart';
import '../../services/ai_prompt_builder.dart';
import '../../services/financial_analytics_service.dart';
import '../../services/financial_chat_context_service.dart';
import '../../services/financial_forecast_service.dart';
import '../../services/transaction_intelligence_service.dart';
import 'admin_web_service.dart';

/// Kết quả mô phỏng định lượng thuần trên Synthetic Persona (Deterministic Sandbox)
class AdminSandboxSimulationResult {
  final String personaId;
  final String personaTitle;
  final int healthScore;
  final String healthRating;
  final List<FinancialIssue> issues;
  final MonthlyFinancialPlan monthlyPlan;
  final FinancialInsightSummary summary;
  final FinancialChatContext chatContext;
  final String systemPromptPreview;
  final String structuredPlanPromptPreview;
  final CategorySuggestion? sampleCategorySuggestion;
  final WalletSuggestion? sampleWalletSuggestion;

  const AdminSandboxSimulationResult({
    required this.personaId,
    required this.personaTitle,
    required this.healthScore,
    required this.healthRating,
    required this.issues,
    required this.monthlyPlan,
    required this.summary,
    required this.chatContext,
    required this.systemPromptPreview,
    required this.structuredPlanPromptPreview,
    this.sampleCategorySuggestion,
    this.sampleWalletSuggestion,
  });

  Map<String, dynamic> toVerificationSummary() {
    return {
      'personaId': personaId,
      'personaTitle': personaTitle,
      'healthScore': healthScore,
      'issuesCount': issues.length,
      'dataTier': monthlyPlan.dataTierUsed.name,
      'targetSavingAmount': monthlyPlan.targetSavingAmount.round(),
    };
  }
}

/// Service mô phỏng AI Sandbox & kiểm thử Prompt/Dictionary cho Admin Web.
/// Tuyệt đối KHÔNG import `AiService` hay `config/api_keys.dart`:
/// - Phần mô phỏng định lượng chạy thuần 100% trên Dart models/services với Synthetic Persona.
/// - Phần gọi Gemini trực tiếp chạy qua Cloud Function `adminRunSandbox` (Server Secret Manager).
class AdminAiSandboxService {
  const AdminAiSandboxService();

  /// Chạy mô phỏng định lượng (Deterministic Sandbox) cho một [SyntheticPersona].
  AdminSandboxSimulationResult simulatePersona({
    required SyntheticPersona persona,
    required AiRuntimeConfig runtimeConfig,
    required FinancialHeuristicsConfig heuristicsConfig,
    required TransactionIntelligenceConfig transactionRules,
    List<FinancialKnowledgeArticle>? knowledgeArticles,
    String? sampleCategoryText,
    String? sampleReceiptText,
    DateTime? referenceDate,
  }) {
    final now = referenceDate ?? DateTime(2026, 11, 15);
    final lastMonthTx = persona.historicalMonthsTx.isNotEmpty
        ? persona.historicalMonthsTx.last
        : const <dynamic>[];

    final analytics = FinancialAnalyticsService(
      heuristicsOverride: heuristicsConfig,
    );
    final forecast = FinancialForecastService(
      heuristicsOverride: heuristicsConfig,
    );
    final chatContextService = FinancialChatContextService(
      analyticsService: analytics,
      heuristicsOverride: heuristicsConfig,
    );
    final txIntelligence = TransactionIntelligenceService(
      rulesOverride: transactionRules,
      heuristicsOverride: heuristicsConfig,
    );

    final issues = analytics.detectIssues(
      currentMonthTx: persona.currentMonthTx,
      lastMonthTx: lastMonthTx.cast(),
      categories: persona.categories,
      monthlyIncome: persona.declaredMonthlyIncome,
      heuristicsOverride: heuristicsConfig,
    );

    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final sourceMonthStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final targetMonthStr =
        '${nextMonth.year}-${nextMonth.month.toString().padLeft(2, '0')}';

    final monthlyPlan = analytics.buildSequentialMonthlyPlan(
      userId: persona.id,
      sourceMonth: sourceMonthStr,
      targetMonth: targetMonthStr,
      sourceMonthTx: persona.currentMonthTx,
      historicalMonthsTx: persona.historicalMonthsTx,
      categories: persona.categories,
      existingTargetBudgets: persona.currentBudgets,
      savingGoals: persona.savingGoals,
      wallets: persona.wallets,
      declaredExpectedIncome: persona.declaredMonthlyIncome,
      heuristicsOverride: heuristicsConfig,
      referenceToday: now,
    );

    final summary = forecast.generateSummary(
      activeWallets: persona.wallets,
      currentMonthBudgets: persona.currentBudgets,
      categories: persona.categories,
      currentMonthTx: persona.currentMonthTx,
      preceding3MonthsTx: persona.historicalMonthsTx,
      monthlyIncome: persona.declaredMonthlyIncome,
      issues: issues,
      savingGoals: persona.savingGoals,
      refDate: now,
    );

    final twoMonthsAgoTx = persona.historicalMonthsTx.length >= 2
        ? persona.historicalMonthsTx[persona.historicalMonthsTx.length - 2]
        : null;

    final chatContext = chatContextService.buildContextFromData(
      currentMonthTx: persona.currentMonthTx,
      lastMonthTx: lastMonthTx.cast(),
      twoMonthsAgoTx: twoMonthsAgoTx,
      wallets: persona.wallets,
      budgets: persona.currentBudgets,
      categories: persona.categories,
      savingGoals: persona.savingGoals,
      declaredMonthlyIncome: persona.declaredMonthlyIncome,
      activePlan: monthlyPlan,
      heuristicsOverride: heuristicsConfig,
      referenceDate: now,
    );

    final systemPromptPreview = AiPromptBuilder.buildSystemCfpPromptForContext(
      chatContext.rawPromptContext,
      runtimeConfig: runtimeConfig,
      overrideArticles: knowledgeArticles,
      hasBudgetOverrun: chatContext.overBudgets.isNotEmpty,
      isGoalInfeasible: !monthlyPlan.isSavingGoalFeasible,
    );

    final structuredPlanPromptPreview = AiPromptBuilder.buildStructuredPlanPrompt(
      summary: summary,
      draftPlan: monthlyPlan,
      runtimeConfig: runtimeConfig,
    );

    CategorySuggestion? catSuggestion;
    if (sampleCategoryText != null && sampleCategoryText.trim().isNotEmpty) {
      catSuggestion = txIntelligence.suggestCategory(
        note: sampleCategoryText.trim(),
        transactionType: 'expense',
        categories: persona.categories,
      );
    }

    WalletSuggestion? walletSuggestion;
    if (sampleReceiptText != null && sampleReceiptText.trim().isNotEmpty) {
      walletSuggestion = txIntelligence.suggestWallet(
        ocrRawText: sampleReceiptText.trim(),
        wallets: persona.wallets,
      );
    }

    return AdminSandboxSimulationResult(
      personaId: persona.id,
      personaTitle: persona.title,
      healthScore: summary.healthScore,
      healthRating: summary.healthRating,
      issues: issues,
      monthlyPlan: monthlyPlan,
      summary: summary,
      chatContext: chatContext,
      systemPromptPreview: systemPromptPreview,
      structuredPlanPromptPreview: structuredPlanPromptPreview,
      sampleCategorySuggestion: catSuggestion,
      sampleWalletSuggestion: walletSuggestion,
    );
  }

  /// Chạy thử Gemini Live Sandbox thông qua Cloud Function `adminRunSandbox`
  /// (Server-side Secret Manager giữ `GEMINI_API_KEY`).
  Future<AdminSandboxRunResult> testWithLiveGemini({
    required AdminWebService adminWebService,
    required String adminUid,
    required AdminSandboxSimulationResult simulation,
    required AiRuntimeConfig runtimeConfig,
    required String userQuestion,
    bool testStructuredPlanJson = false,
    Map<String, dynamic>? tokenClaimsOverride,
  }) {
    final prompt = testStructuredPlanJson
        ? simulation.structuredPlanPromptPreview
        : userQuestion.trim();
    final sysInstruction =
        testStructuredPlanJson ? null : simulation.systemPromptPreview;

    return adminWebService.runLiveGeminiSandbox(
      adminUid: adminUid,
      mode: testStructuredPlanJson ? 'structured_plan_json' : 'chat_prompt',
      prompt: prompt,
      systemInstruction: sysInstruction,
      primaryModel: runtimeConfig.primaryModel,
      fallbackModels: runtimeConfig.fallbackModels,
      temperature: runtimeConfig.temperature,
      expectStructuredPlanJson: testStructuredPlanJson,
      persona: SyntheticPersona(
        id: simulation.personaId,
        title: simulation.personaTitle,
        subtitle: '',
        declaredMonthlyIncome: 0,
        wallets: const [],
        categories: const [],
        currentBudgets: const [],
        savingGoals: const [],
        currentMonthTx: const [],
        historicalMonthsTx: const [],
      ),
      tokenClaimsOverride: tokenClaimsOverride,
    );
  }
}
