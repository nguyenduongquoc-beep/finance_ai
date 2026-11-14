import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/ai_runtime_config_model.dart';
import 'package:finance_ai_app/services/ai_config_sync_service.dart';

void main() {
  group('Giai đoạn 1.1: Gemini Model Whitelist & AiRuntimeConfig', () {
    test('1. Chỉ chấp nhận các Model ID trong Whitelist và tự động fallback an toàn', () {
      expect(isSupportedGeminiModelId('gemini-3.5-flash'), isTrue);
      expect(isSupportedGeminiModelId('gemini-3.5-flash-lite'), isTrue);
      expect(isSupportedGeminiModelId('gemini-2.5-flash'), isTrue);
      expect(isSupportedGeminiModelId('gemini-1.0-pro-legacy'), isFalse);
      expect(isSupportedGeminiModelId('custom-unverified-model'), isFalse);

      final chain = sanitizeGeminiModelChain(
        primaryModel: 'invalid-model-id',
        fallbackModels: const ['gemini-2.5-flash', 'invalid-2', 'gemini-3.5-flash'],
      );
      expect(chain.first, 'gemini-3.5-flash');
      expect(chain.contains('gemini-2.5-flash'), isTrue);
      expect(chain.contains('invalid-model-id'), isFalse);
      expect(chain.contains('invalid-2'), isFalse);
    });

    test('2. AiRuntimeConfig clamp temperature, maxChatHistoryMessages và báo lỗi raw input sai', () {
      final clamped = AiRuntimeConfig.fromMap(const {
        'version': 3,
        'primaryModel': 'unknown-model',
        'temperature': 5.0,
        'maxChatHistoryMessages': 999,
      });

      expect(clamped.version, 3);
      expect(clamped.primaryModel, 'gemini-3.5-flash');
      expect(clamped.temperature, AiRuntimeConfig.kMaxTemperature);
      expect(clamped.maxChatHistoryMessages, AiRuntimeConfig.kMaxChatHistory);

      final errors = AiRuntimeConfig.validateRawInput(const {
        'primaryModel': 'arbitrary-model',
        'temperature': 0.95,
        'maxChatHistoryMessages': 2,
        'prompts': {'chatSystemInstruction': ''},
      });
      expect(errors.length, greaterThanOrEqualTo(4));
    });
  });

  group('Giai đoạn 1.2: Canonical SHA-256 Digest & Xác minh Sandbox Hash', () {
    test('3. SHA-256 chuẩn RFC 6234 và Canonical JSON bất biến với thứ tự key', () {
      // Vector chuẩn NIST cho chuỗi "abc"
      expect(
        sha256HexFromString('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );

      final mapA = <String, dynamic>{
        'b': 2,
        'a': 1,
        'nested': {'z': true, 'x': 'hello'},
      };
      final mapB = <String, dynamic>{
        'nested': {'x': 'hello', 'z': true},
        'a': 1,
        'b': 2.0,
      };

      expect(
        computeCanonicalConfigHash(mapA),
        equals(computeCanonicalConfigHash(mapB)),
      );
    });

    test('4. Khi nội dung Draft thay đổi dù chỉ 1 tham số, xác minh Sandbox trước đó mất hiệu lực ngay lập tức', () {
      final originalPayload = AiRuntimeConfig.defaults().toPayloadMap();
      final originalHash = computeCanonicalConfigHash(originalPayload);

      final verifiedEnvelope = DraftConfigEnvelope.fromMap(
        {
          'draftPayload': originalPayload,
          'draftHash': originalHash,
        },
        configType: 'ai_runtime',
        verificationDoc: {
          'verifiedDraftHash': originalHash,
          'verificationSignature': 'server_hmac_sig_01',
        },
      );
      expect(verifiedEnvelope.isSandboxVerificationValid, isTrue);

      // Admin chỉnh sửa temperature từ 0.35 -> 0.40 sau khi đã test Sandbox
      final modifiedPayload = AiRuntimeConfig.defaults()
          .copyWith(temperature: 0.40)
          .toPayloadMap();

      final modifiedEnvelope = DraftConfigEnvelope.fromMap(
        {
          'draftPayload': modifiedPayload,
          'draftHash': originalHash, // Kể cả client cố giữ draftHash cũ
        },
        configType: 'ai_runtime',
        verificationDoc: {
          'verifiedDraftHash': originalHash,
          'verificationSignature': 'server_hmac_sig_01',
        },
      );

      // Kết quả kiểm thử Sandbox lập tức mất hiệu lực vì nội dung thực tế đã thay đổi
      expect(modifiedEnvelope.isSandboxVerificationValid, isFalse);
    });
  });

  group('Giai đoạn 1.3: FinancialHeuristicsConfig & Tính nhất quán ngưỡng định lượng', () {
    test('5. Clamp an toàn và đảm bảo tính nhất quán giữa các cặp ngưỡng cảnh báo/nghiêm trọng', () {
      final config = FinancialHeuristicsConfig.fromMap(const {
        'version': 2,
        'minRecommendedSavingRate': 0.18,
        'defaultSavingRateNoGoal': 0.30, // Lớn hơn minRecommendedSavingRate -> phải bị hạ xuống <= 0.18
        'categoryForecastWarningRatio': 1.50,
        'categoryForecastCriticalRatio': 1.45, // Nhỏ hơn warning -> phải tự nâng lên >= 1.65
        'txAnomalyWarningMultiplier': 3.0,
        'txAnomalyCriticalMultiplier': 3.2, // Chênh < 1.0x -> phải tự nâng lên >= 4.0
        'planBudgetAdherenceWeight': 0.65,
      });

      expect(config.minRecommendedSavingRate, 0.18);
      expect(config.defaultSavingRateNoGoal, 0.18);
      expect(config.categoryForecastCriticalRatio, closeTo(1.65, 0.001));
      expect(config.txAnomalyCriticalMultiplier, closeTo(4.0, 0.001));
      expect(
        config.planBudgetAdherenceWeight + config.planSavingAdherenceWeight,
        closeTo(1.0, 0.0001),
      );
    });
  });

  group('Giai đoạn 1.4: TransactionIntelligenceConfig & Phát hiện xung đột từ khóa', () {
    test('6. Ngăn gán vào nhóm không chuẩn, phát hiện trùng lặp không dấu và xung đột chéo giữa các nhóm', () {
      const builtInExpense = <String, List<String>>{
        'di chuyen': ['grab', 'xanh sm', 'xang'],
        'an uong': ['highlands', 'starbucks', 'ca phe'],
      };
      const addedExpense = <String, List<String>>{
        'an uong': ['katinat'],
      };

      // 6a. Trùng từ khóa đã có (không phân biệt hoa thường & dấu tiếng Việt)
      final dupCheck = TransactionIntelligenceConfig.validateCandidateKeyword(
        rawKeyword: 'Cà Phê',
        targetGroupKey: 'an uong',
        isIncomeGroup: false,
        builtInKeywordsByGroup: builtInExpense,
        addedKeywordsByGroup: addedExpense,
      );
      expect(dupCheck.isValid, isFalse);
      expect(dupCheck.errorMessage, contains('đã tồn tại'));

      // 6b. Xung đột chéo: thêm "grab" vào nhóm "an uong" khi "grab" đang thuộc "di chuyen"
      final crossConflict =
          TransactionIntelligenceConfig.validateCandidateKeyword(
        rawKeyword: 'Grab',
        targetGroupKey: 'an uong',
        isIncomeGroup: false,
        builtInKeywordsByGroup: builtInExpense,
        addedKeywordsByGroup: addedExpense,
      );
      expect(crossConflict.isValid, isFalse);
      expect(crossConflict.conflictingGroupKey, 'di chuyen');
      expect(crossConflict.errorMessage, contains('Xung đột từ khóa'));

      // 6c. Không cho phép truyền categoryId cá nhân làm groupKey
      final invalidGroup =
          TransactionIntelligenceConfig.validateCandidateKeyword(
        rawKeyword: 'phe la',
        targetGroupKey: 'user_personal_cat_123',
        isIncomeGroup: false,
        builtInKeywordsByGroup: builtInExpense,
        addedKeywordsByGroup: addedExpense,
      );
      expect(invalidGroup.isValid, isFalse);

      // 6d. Từ khóa mới hợp lệ ("Phê La" -> "phe la")
      final validNew = TransactionIntelligenceConfig.validateCandidateKeyword(
        rawKeyword: 'Phê La',
        targetGroupKey: 'an uong',
        isIncomeGroup: false,
        builtInKeywordsByGroup: builtInExpense,
        addedKeywordsByGroup: addedExpense,
      );
      expect(validNew.isValid, isTrue);
      expect(validNew.normalizedKeyword, 'phe la');
    });
  });

  group('Giai đoạn 1.5: AiConfigSyncService (Tách Draft/Published & Giới hạn tiêm Tri thức)', () {
    late FakeFirebaseFirestore fakeFirestore;
    late AiConfigSyncService syncService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      syncService = AiConfigSyncService.forTest(firestore: fakeFirestore);
    });

    test('7. User App chỉ đọc published_configs, tuyệt đối không bị ảnh hưởng bởi draft_configs chưa xuất bản', () async {
      // Admin lưu bản nháp vào draft_configs nhưng chưa xuất bản
      await fakeFirestore
          .collection(AiConfigSyncService.kDraftConfigsCollection)
          .doc(AiConfigSyncService.kDocFinancialHeuristics)
          .set({
        'configType': 'financial_heuristics',
        'draftPayload': {'categorySpikeRatio': 0.55},
        'draftHash': 'hash_draft',
      });

      await syncService.syncPublishedConfigsIfNeeded(forceRefresh: true);
      // User vẫn dùng ngưỡng mặc định 0.30, không đọc bản nháp 0.55
      expect(syncService.currentHeuristics.categorySpikeRatio, 0.30);

      // Khi Backend Publish lên published_configs v2
      await fakeFirestore
          .collection(AiConfigSyncService.kPublishedConfigsCollection)
          .doc(AiConfigSyncService.kDocFinancialHeuristics)
          .set({
        'configType': 'financial_heuristics',
        'version': 2,
        'payload': {'categorySpikeRatio': 0.42},
      });

      await syncService.syncPublishedConfigsIfNeeded(forceRefresh: true);
      expect(syncService.currentHeuristics.version, 2);
      expect(syncService.currentHeuristics.categorySpikeRatio, 0.42);
    });

    test('8. Giới hạn tối đa 3 đoạn tri thức (<= 300 ký tự/đoạn) được tiêm vào Prompt theo đúng triggerCondition', () {
      final customArticles = List.generate(
        5,
        (i) => FinancialKnowledgeArticle(
          articleId: 'kb_$i',
          title: 'Chiến lược $i',
          topic: 'saving_strategy',
          triggerCondition: KnowledgeTriggerCondition.lowSavingRate,
          priority: i + 1,
          summaryForUser: 'Tóm tắt $i',
          aiGroundingSnippet: 'A' * 400, // Vượt 300 ký tự
        ),
      );

      // Khi tỷ lệ tiết kiệm thấp -> Chọn tối đa 3 bài có priority cao nhất (5, 4, 3)
      final snippets = syncService.selectKnowledgeSnippetsForPrompt(
        isLowSavingRate: true,
        overrideArticles: customArticles,
      );

      expect(
        snippets.length,
        FinancialKnowledgeArticle.kMaxInjectedSnippetsPerPrompt,
      );
      expect(snippets.first, contains('Chiến lược 4')); // priority = 5
      // Mỗi đoạn đã bị cắt về <= 300 ký tự nội dung
      for (final s in snippets) {
        expect(s.length, lessThanOrEqualTo(330));
      }
    });

    test('9. AiFeedbackReport ẩn danh hóa chuỗi số nhạy cảm và tuân thủ đúng tập khóa hasAll/hasOnly', () {
      final report = AiFeedbackReport(
        reportId: 'rep_001',
        targetFeature: 'ocr_suggestion',
        rating: 'negative',
        reasonCode: 'ocr_missed_merchant',
        userNote: 'Quét hóa đơn số TK 19034567890123 số tiền 15.000.000 chưa nhận diện đúng',
        suggestedKeywordOrMerchant: 'Katinat Saigon Kafe',
        feedbackMode: 'anonymous',
        createdAt: DateTime(2026, 11, 14),
      );

      final createMap = report.toCreateMap();
      // Kiểm tra mọi khóa bắt buộc đều có mặt (hasAll)
      for (final reqKey in AiFeedbackReport.requiredCreateKeys) {
        expect(createMap.containsKey(reqKey), isTrue, reason: 'Thiếu khóa $reqKey');
      }
      // Kiểm tra không có bất kỳ khóa lạ nào ngoài danh sách cho phép (hasOnly)
      for (final k in createMap.keys) {
        expect(AiFeedbackReport.allowedCreateKeys.contains(k), isTrue);
      }
      expect(createMap['status'], 'open');
      // Số tài khoản và số tiền dài đã bị che tự động
      expect(createMap['userNote'], contains('[SỐ_ẨN_DANH]'));
      expect(createMap['userNote'], isNot(contains('19034567890123')));
    });
  });
}
