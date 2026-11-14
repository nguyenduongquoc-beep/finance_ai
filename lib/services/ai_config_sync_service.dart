import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/ai_runtime_config_model.dart';

/// ============================================================================
/// AI CONFIG SYNC SERVICE
/// Đồng bộ cấu hình ĐÃ XUẤT BẢN (`published_configs` & `financial_knowledge_published`)
/// từ Firestore về ứng dụng User với:
/// 1. Bộ nhớ đệm trên RAM (In-Memory Cache) kèm kiểm tra `version` và TTL.
/// 2. Cơ chế Safe Fallback 100% về hằng số mặc định trong code khi mất mạng,
///    chưa khởi tạo Firebase (trong Widget/Unit Test) hoặc chưa có cấu hình trên Server.
/// 3. Tuyệt đối KHÔNG đọc `draft_configs` hay `financial_knowledge_drafts` từ phía User.
/// 4. Lọc và giới hạn dung lượng tiêm Tri thức Tài chính (`<= 3` bài x `300` ký tự).
/// ============================================================================
class AiConfigSyncService {
  static const String kPublishedConfigsCollection = 'published_configs';
  static const String kDraftConfigsCollection = 'draft_configs';
  static const String kConfigVersionsCollection = 'config_versions';
  static const String kPublishedKnowledgeCollection =
      'financial_knowledge_published';
  static const String kDraftKnowledgeCollection = 'financial_knowledge_drafts';
  static const String kFeedbackReportsCollection = 'ai_feedback_reports';

  static const String kDocAiRuntime = 'ai_runtime';
  static const String kDocFinancialHeuristics = 'financial_heuristics';
  static const String kDocTransactionRules = 'transaction_rules';

  static const Duration defaultCacheTtl = Duration(minutes: 5);

  static final AiConfigSyncService instance = AiConfigSyncService._internal();

  FirebaseFirestore? _customFirestore;
  Duration cacheTtl;

  /// Công tắc khẩn cấp: nếu bật `true`, toàn bộ ứng dụng bỏ qua cấu hình từ xa
  /// và dùng 100% giá trị mặc định cố định trong code.
  bool useHardcodedDefaultsOnly = false;

  AiRuntimeConfig _cachedAiRuntime = AiRuntimeConfig.defaults();
  FinancialHeuristicsConfig _cachedHeuristics =
      FinancialHeuristicsConfig.defaults();
  TransactionIntelligenceConfig _cachedTxRules =
      TransactionIntelligenceConfig.defaults();
  List<FinancialKnowledgeArticle> _cachedKnowledge =
      FinancialKnowledgeArticle.defaultArticles();

  DateTime? _lastSyncAt;

  AiConfigSyncService._internal({
    FirebaseFirestore? firestore,
    this.cacheTtl = defaultCacheTtl,
  }) : _customFirestore = firestore;

  /// Constructor dành riêng cho Unit Test với `FakeFirebaseFirestore`
  factory AiConfigSyncService.forTest({
    required FirebaseFirestore firestore,
    Duration cacheTtl = defaultCacheTtl,
  }) {
    return AiConfigSyncService._internal(
      firestore: firestore,
      cacheTtl: cacheTtl,
    );
  }

  /// Cấu hình Firestore giả lập cho Singleton trong môi trường Test
  void configureForTesting({
    FirebaseFirestore? firestore,
    bool resetCache = true,
  }) {
    _customFirestore = firestore;
    if (resetCache) {
      resetToDefaults();
    }
  }

  /// Khôi phục toàn bộ bộ nhớ đệm về giá trị mặc định trong code
  void resetToDefaults() {
    _cachedAiRuntime = AiRuntimeConfig.defaults();
    _cachedHeuristics = FinancialHeuristicsConfig.defaults();
    _cachedTxRules = TransactionIntelligenceConfig.defaults();
    _cachedKnowledge = FinancialKnowledgeArticle.defaultArticles();
    _lastSyncAt = null;
    useHardcodedDefaultsOnly = false;
  }

  AiRuntimeConfig get currentAiRuntime => useHardcodedDefaultsOnly
      ? AiRuntimeConfig.defaults()
      : (_cachedAiRuntime.isEnabled
          ? _cachedAiRuntime
          : AiRuntimeConfig.defaults());

  FinancialHeuristicsConfig get currentHeuristics => useHardcodedDefaultsOnly
      ? FinancialHeuristicsConfig.defaults()
      : _cachedHeuristics;

  TransactionIntelligenceConfig get currentTransactionRules =>
      useHardcodedDefaultsOnly
          ? TransactionIntelligenceConfig.defaults()
          : _cachedTxRules;

  List<FinancialKnowledgeArticle> get currentKnowledgeArticles =>
      useHardcodedDefaultsOnly
          ? FinancialKnowledgeArticle.defaultArticles()
          : _cachedKnowledge;

  bool get isCacheFresh {
    if (_lastSyncAt == null) return false;
    return DateTime.now().difference(_lastSyncAt!) < cacheTtl;
  }

  FirebaseFirestore? _resolveFirestoreSafely() {
    if (_customFirestore != null) return _customFirestore;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      // Khi chạy trong Unit/Widget test không gọi Firebase.initializeApp()
      return null;
    }
  }

  /// Đồng bộ toàn bộ cấu hình đã xuất bản (`published_configs` & `financial_knowledge_published`).
  /// Không bao giờ ném lỗi ra ngoài làm gián đoạn luồng của User.
  Future<void> syncPublishedConfigsIfNeeded({bool forceRefresh = false}) async {
    if (useHardcodedDefaultsOnly) return;
    if (!forceRefresh && isCacheFresh) return;

    final db = _resolveFirestoreSafely();
    if (db == null) return;

    try {
      final results = await Future.wait<dynamic>([
        db.collection(kPublishedConfigsCollection).doc(kDocAiRuntime).get(),
        db
            .collection(kPublishedConfigsCollection)
            .doc(kDocFinancialHeuristics)
            .get(),
        db
            .collection(kPublishedConfigsCollection)
            .doc(kDocTransactionRules)
            .get(),
        db.collection(kPublishedKnowledgeCollection).get(),
      ]);

      final aiDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      if (aiDoc.exists && aiDoc.data() != null) {
        final parsed = AiRuntimeConfig.fromMap(aiDoc.data());
        if (parsed.version >= _cachedAiRuntime.version || forceRefresh) {
          _cachedAiRuntime = parsed;
        }
      }

      final heurDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>;
      if (heurDoc.exists && heurDoc.data() != null) {
        final parsed = FinancialHeuristicsConfig.fromMap(heurDoc.data());
        if (parsed.version >= _cachedHeuristics.version || forceRefresh) {
          _cachedHeuristics = parsed;
        }
      }

      final txDoc = results[2] as DocumentSnapshot<Map<String, dynamic>>;
      if (txDoc.exists && txDoc.data() != null) {
        final parsed = TransactionIntelligenceConfig.fromMap(txDoc.data());
        if (parsed.version >= _cachedTxRules.version || forceRefresh) {
          _cachedTxRules = parsed;
        }
      }

      final kbSnap = results[3] as QuerySnapshot<Map<String, dynamic>>;
      if (kbSnap.docs.isNotEmpty) {
        final remoteArticles = kbSnap.docs
            .map((d) => FinancialKnowledgeArticle.fromMap(d.data(), docId: d.id))
            .where((a) =>
                a.articleId.isNotEmpty &&
                a.title.isNotEmpty &&
                a.aiGroundingSnippet.isNotEmpty)
            .toList();
        if (remoteArticles.isNotEmpty) {
          _cachedKnowledge = _mergeWithDefaultKnowledge(remoteArticles);
        }
      }

      _lastSyncAt = DateTime.now();
    } catch (e) {
      debugPrint(
        '[AiConfigSyncService] Sử dụng cấu hình mặc định an toàn (fallback): $e',
      );
    }
  }

  List<FinancialKnowledgeArticle> _mergeWithDefaultKnowledge(
    List<FinancialKnowledgeArticle> remoteArticles,
  ) {
    final mapById = <String, FinancialKnowledgeArticle>{
      for (final def in FinancialKnowledgeArticle.defaultArticles())
        def.articleId: def,
    };
    for (final rem in remoteArticles) {
      mapById[rem.articleId] = rem;
    }
    return mapById.values.toList();
  }

  /// Chọn lọc tối đa 3 đoạn tri thức tài chính (`<= 300` ký tự/đoạn) khớp với
  /// trạng thái định lượng thực tế của người dùng để tiêm vào Prompt gửi cho Gemini.
  List<FinancialKnowledgeArticle> selectMatchingKnowledgeArticles({
    bool isLowSavingRate = false,
    bool isEssentialDeficit = false,
    bool isVariableIncome = false,
    bool hasBudgetOverrun = false,
    bool isGoalInfeasible = false,
    List<FinancialKnowledgeArticle>? overrideArticles,
  }) {
    final source = overrideArticles ?? currentKnowledgeArticles;
    final matched = source.where((article) {
      if (!article.isActive || article.aiGroundingSnippet.trim().isEmpty) {
        return false;
      }
      switch (article.triggerCondition) {
        case KnowledgeTriggerCondition.always:
          return true;
        case KnowledgeTriggerCondition.lowSavingRate:
          return isLowSavingRate;
        case KnowledgeTriggerCondition.essentialDeficit:
          return isEssentialDeficit;
        case KnowledgeTriggerCondition.variableIncome:
          return isVariableIncome;
        case KnowledgeTriggerCondition.budgetOverrun:
          return hasBudgetOverrun;
        case KnowledgeTriggerCondition.infeasibleGoal:
          return isGoalInfeasible;
      }
    }).toList();

    matched.sort((a, b) => b.priority.compareTo(a.priority));

    return matched
        .take(FinancialKnowledgeArticle.kMaxInjectedSnippetsPerPrompt)
        .toList();
  }

  /// Trích xuất danh sách chuỗi chỉ dẫn ngắn gọn (đã giới hạn nghiêm ngặt độ dài) để tiêm vào Prompt
  List<String> selectKnowledgeSnippetsForPrompt({
    bool isLowSavingRate = false,
    bool isEssentialDeficit = false,
    bool isVariableIncome = false,
    bool hasBudgetOverrun = false,
    bool isGoalInfeasible = false,
    List<FinancialKnowledgeArticle>? overrideArticles,
  }) {
    final articles = selectMatchingKnowledgeArticles(
      isLowSavingRate: isLowSavingRate,
      isEssentialDeficit: isEssentialDeficit,
      isVariableIncome: isVariableIncome,
      hasBudgetOverrun: hasBudgetOverrun,
      isGoalInfeasible: isGoalInfeasible,
      overrideArticles: overrideArticles,
    );

    return articles.map((a) {
      final snippet = a.aiGroundingSnippet.trim();
      final bounded =
          snippet.length <= FinancialKnowledgeArticle.kMaxSnippetLength
              ? snippet
              : snippet.substring(
                  0,
                  FinancialKnowledgeArticle.kMaxSnippetLength,
                );
      return '- [${a.title}]: $bounded';
    }).toList();
  }
}
