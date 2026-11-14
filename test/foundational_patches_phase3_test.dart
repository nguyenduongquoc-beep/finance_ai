import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_ai_app/admin_web/services/admin_ai_sandbox_service.dart';
import 'package:finance_ai_app/admin_web/services/admin_http_helper.dart';
import 'package:finance_ai_app/admin_web/services/admin_web_service.dart';
import 'package:finance_ai_app/models/admin_audit_log_model.dart';
import 'package:finance_ai_app/models/ai_runtime_config_model.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/monthly_financial_plan.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/services/ai_prompt_builder.dart';
import 'package:finance_ai_app/services/ai_service.dart';
import 'package:finance_ai_app/services/firestore_service.dart';
import 'package:finance_ai_app/services/transaction_intelligence_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Bản vá 1: HTTP Client thực & chuẩn hóa AdminCloudResponse', () {
    test('200 OK trả về AdminCloudResponse thành công và unwrap data map',
        () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'success': true,
              'data': {'publishedVersion': 7, 'configType': 'ai_runtime'},
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final response = await postAdminCloudEndpoint(
        url: 'https://example.cloudfunctions.net/adminPublishConfig',
        idToken: 'fake-id-token-123',
        body: {'configType': 'ai_runtime'},
        client: client,
      );

      expect(capturedRequest.method, 'POST');
      expect(
        capturedRequest.headers['Authorization'],
        'Bearer fake-id-token-123',
      );
      expect(response.isSuccess, isTrue);
      expect(response.statusCode, 200);
      expect(response.errorKind, AdminCloudErrorKind.none);
      expect(response.requireSuccessData()['publishedVersion'], 7);
    });

    test('GET request chuẩn hóa response và không gửi body JSON thừa', () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'success': true,
            'uid': 'admin_1',
            'claimsSynced': true,
          }),
          200,
        );
      });

      final response = await sendAdminCloudRequest(
        method: 'GET',
        url: 'https://example.cloudfunctions.net/adminVerifySession',
        idToken: 'tok-get',
        client: client,
      );

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.body, isEmpty);
      expect(response.requireSuccessData()['claimsSynced'], isTrue);
    });

    test(
        'Không nuốt lỗi HTTP 400/401/403/429/500 & phân loại chính xác validationErrors/errorKind',
        () async {
      Future<AdminCloudResponse> callWithStatus(
        int statusCode,
        Map<String, dynamic> body,
      ) {
        final client = MockClient((_) async {
          return http.Response.bytes(
            utf8.encode(jsonEncode(body)),
            statusCode,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        return postAdminCloudEndpoint(
          url: 'https://example.cloudfunctions.net/testEndpoint',
          idToken: 'tok',
          body: {'x': 1},
          client: client,
        );
      }

      // 400 validation
      final r400 = await callWithStatus(400, {
        'error': 'Dữ liệu không hợp lệ',
        'validationErrors': ['Lỗi nhiệt độ', 'Lỗi model chính'],
      });
      expect(r400.isSuccess, isFalse);
      expect(r400.errorKind, AdminCloudErrorKind.validation);
      expect(r400.validationErrors, ['Lỗi nhiệt độ', 'Lỗi model chính']);
      expect(
        () => r400.requireSuccessData(),
        throwsA(
          isA<AdminCloudCallException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.kind, 'kind', AdminCloudErrorKind.validation)
              .having((e) => e.validationErrors.length, 'validationErrors', 2),
        ),
      );

      // 401 unauthenticated
      final r401 = await callWithStatus(401, {'error': 'Thiếu ID Token'});
      expect(r401.errorKind, AdminCloudErrorKind.unauthenticated);
      expect(
        () => r401.requireSuccessData(),
        throwsA(
          isA<AdminCloudCallException>()
              .having((e) => e.kind, 'kind', AdminCloudErrorKind.unauthenticated),
        ),
      );

      // 403 forbidden
      final r403 = await callWithStatus(403, {'error': 'Không có quyền Admin'});
      expect(r403.errorKind, AdminCloudErrorKind.forbidden);

      // 429 rateLimited
      final r429 = await callWithStatus(429, {'error': 'Vượt giới hạn Sandbox'});
      expect(r429.errorKind, AdminCloudErrorKind.rateLimited);

      // 500 server
      final r500 = await callWithStatus(500, {'error': 'Lỗi máy chủ nội bộ'});
      expect(r500.errorKind, AdminCloudErrorKind.server);
    });

    test('Phân biệt lỗi mạng ClientException và TimeoutException', () async {
      final netClient = MockClient(
        (_) async => throw http.ClientException('Socket closed'),
      );
      final netRes = await postAdminCloudEndpoint(
        url: 'https://example.cloudfunctions.net/test',
        idToken: 'tok',
        body: const {},
        client: netClient,
      );
      expect(netRes.isSuccess, isFalse);
      expect(netRes.statusCode, 0);
      expect(netRes.errorKind, AdminCloudErrorKind.network);

      final timeoutClient = MockClient(
        (_) => throw TimeoutException('Request timed out'),
      );
      final timeoutRes = await postAdminCloudEndpoint(
        url: 'https://example.cloudfunctions.net/test',
        idToken: 'tok',
        body: const {},
        client: timeoutClient,
      );
      expect(timeoutRes.isSuccess, isFalse);
      expect(timeoutRes.errorKind, AdminCloudErrorKind.timeout);
    });
  });

  group('Bản vá 2, 3, 7 & 8: AdminWebService đi qua Backend & không fallback client',
      () {
    test(
        'verifyAdminAccess(verifyWithBackend: true) đồng bộ từ server và từ chối 401/403 không fallback',
        () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final firestoreService = FirestoreService(firestore: fakeFirestore);

      // Server trả 200 kèm claimsSynced = true
      final okService = AdminWebService(
        firestoreService: firestoreService,
        cloudCaller: (fn, payload) async {
          expect(fn, 'adminVerifySession');
          return {
            'success': true,
            'uid': 'admin_srv',
            'email': 'admin@srv.vn',
            'name': 'Admin Server',
            'role': 'admin',
            'status': 'active',
            'hasAdminClaim': true,
            'hasFirestoreRole': true,
            'claimsSynced': true,
          };
        },
      );
      final okRes = await okService.verifyAdminAccess(verifyWithBackend: true);
      expect(okRes.isAuthorized, isTrue);
      expect(okRes.verifiedByServer, isTrue);
      expect(okRes.claimsSynced, isTrue);
      expect(okRes.hasAdminCustomClaim, isTrue);

      // Server trả 403 -> từ chối thẳng, tuyệt đối không fallback sang client
      final denyService = AdminWebService(
        firestoreService: firestoreService,
        cloudCaller: (fn, payload) async => {
          'success': false,
          'statusCode': 403,
          'error': 'Tài khoản không có quyền Admin.',
        },
      );
      final denyRes =
          await denyService.verifyAdminAccess(verifyWithBackend: true);
      expect(denyRes.isAuthorized, isFalse);
      expect(denyRes.verifiedByServer, isTrue);
      expect(denyRes.errorMessage, contains('không có quyền Admin'));
    });

    test(
        'Các thao tác publishKnowledgeArticle, runLiveGeminiSandbox, listUsersViaBackend, fetchDashboardStatsViaBackend và CRUD System Category/Announcement đều đi qua Backend',
        () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final firestoreService = FirestoreService(firestore: fakeFirestore);
      final called = <Map<String, dynamic>>[];

      final service = AdminWebService(
        firestoreService: firestoreService,
        cloudCaller: (fn, payload) async {
          called.add({'fn': fn, 'payload': payload});
          switch (fn) {
            case 'adminVerifySession':
              return {
                'success': true,
                'uid': 'admin_1',
                'email': 'admin@app.vn',
                'role': 'admin',
                'status': 'active',
                'hasAdminClaim': true,
                'hasFirestoreRole': true,
              };
            case 'adminListUsers':
              return {
                'success': true,
                'users': [
                  {
                    'uid': 'u1',
                    'name': 'User One',
                    'email': 'u1@app.vn',
                    'role': 'user',
                    'status': 'active',
                  }
                ],
              };
            case 'adminGetDashboardStats':
              return {
                'success': true,
                'stats': {'totalUsers': 42, 'lockedUsers': 1},
              };
            case 'adminPublishKnowledgeBase':
              return {'success': true, 'articleId': payload['articleId']};
            case 'adminRunSandbox':
              return {
                'success': true,
                'modelUsed': 'gemini-3.5-flash',
                'triedModels': ['gemini-3.5-flash'],
                'responseText': '{"summarySummary":"OK"}',
                'jsonValid': true,
                'jsonValidationErrors': [],
                'latencyMs': 185,
                'logId': 'log_sb_1',
                'draftVerificationNote': 'Khong thay doi trang thai Draft',
              };
            case 'adminManageSystemCategory':
              return {'success': true, 'categoryId': 'sys_food'};
            case 'adminManageAnnouncement':
              return {'success': true, 'announcementId': 'ann_1'};
            default:
              return {'success': true};
          }
        },
      );

      final users = await service.listUsersViaBackend(adminUid: 'admin_1');
      expect(users.length, 1);
      expect(users.first.uid, 'u1');

      final stats =
          await service.fetchDashboardStatsViaBackend(adminUid: 'admin_1');
      expect(stats['totalUsers'], 42);

      final pubRes = await service.publishKnowledgeArticle(
        adminUid: 'admin_1',
        articleId: 'kb_rule_1',
        action: 'publish',
        isActive: true,
      );
      expect(pubRes['articleId'], 'kb_rule_1');

      final sandboxRes = await service.runLiveGeminiSandbox(
        adminUid: 'admin_1',
        prompt: 'Phân tích thử',
        expectStructuredPlanJson: true,
      );
      expect(sandboxRes.modelUsed, 'gemini-3.5-flash');
      expect(sandboxRes.jsonValid, isTrue);
      expect(sandboxRes.latencyMs, 185);
      expect(sandboxRes.logId, 'log_sb_1');

      await service.saveSystemCategory(
        adminUid: 'admin_1',
        adminEmail: 'admin@app.vn',
        template: const SystemCategoryTemplate(
          id: 'sys_food',
          name: 'Ăn uống',
          type: 'expense',
          icon: 'restaurant',
          color: 0xFFEF4444,
        ),
        isNew: true,
      );

      await service.saveAnnouncement(
        adminUid: 'admin_1',
        adminEmail: 'admin@app.vn',
        announcement: SystemAnnouncement(
          id: 'ann_1',
          title: 'Thông báo mới',
          content: 'Nội dung chuẩn',
          createdAt: DateTime(2026, 11, 14),
        ),
        isNew: true,
      );

      // Đảm bảo Client hoàn toàn KHÔNG tự ghi trực tiếp vào admin_logs hay collection hệ thống
      final logs = await fakeFirestore.collection('admin_logs').get();
      expect(logs.docs, isEmpty);
      expect(called.any((c) => c['fn'] == 'adminPublishKnowledgeBase'), isTrue);
      expect(called.any((c) => c['fn'] == 'adminRunSandbox'), isTrue);
      expect(called.any((c) => c['fn'] == 'adminManageSystemCategory'), isTrue);
      expect(called.any((c) => c['fn'] == 'adminManageAnnouncement'), isTrue);
    });
  });

  group('Bản vá 4 & 5: Transaction Rules, Protected Keywords, disabledAdminKeywords & Provider isActive',
      () {
    test(
        'validateCandidateKeyword KHÔNG bao giờ bỏ qua built-in keywords kể cả khi truyền disabledBuiltInKeywords',
        () {
      // "quần áo" thuộc built-in nhóm "mua sam"; truyền disabledBuiltInKeywords cũng phải từ chối
      final sameGroupRes = TransactionIntelligenceConfig.validateCandidateKeyword(
        rawKeyword: 'quần áo',
        targetGroupKey: 'mua sam',
        isIncomeGroup: false,
        builtInKeywordsByGroup: kProtectedBuiltInExpenseKeywords,
        addedKeywordsByGroup: const {},
        disabledBuiltInKeywords: const ['quan ao'],
      );
      expect(sameGroupRes.isValid, isFalse);

      final crossGroupRes =
          TransactionIntelligenceConfig.validateCandidateKeyword(
        rawKeyword: 'Tiền nhà',
        targetGroupKey: 'an uong',
        isIncomeGroup: false,
        builtInKeywordsByGroup: kProtectedBuiltInExpenseKeywords,
        addedKeywordsByGroup: const {},
        disabledBuiltInKeywords: const ['tien nha'],
      );
      expect(crossGroupRes.isValid, isFalse);
      expect(crossGroupRes.conflictingGroupKey, 'hoa don');
    });

    test(
        'TransactionIntelligenceConfig.validateRawInput chặn disabledBuiltInKeywords, provider key được bảo vệ & walletType sai',
        () {
      final badDisabled = TransactionIntelligenceConfig.validateRawInput({
        'disabledBuiltInKeywords': ['pho'],
      });
      expect(
        badDisabled.any((e) => e.contains('Built-in Keywords')),
        isTrue,
      );

      final badProviderKey = TransactionIntelligenceConfig.validateRawInput({
        'customPaymentProviders': [
          {
            'key': 'momo',
            'displayLabel': 'MoMo Custom',
            'walletType': 'eWallet',
            'receiptKeywords': ['momo custom'],
            'walletNameAliases': ['momo'],
            'isActive': true,
          }
        ],
      });
      expect(
        badProviderKey.any((e) => e.contains('mặc định được bảo vệ')),
        isTrue,
      );

      final badWalletType = TransactionIntelligenceConfig.validateRawInput({
        'customPaymentProviders': [
          {
            'key': 'crypto_pay_custom',
            'displayLabel': 'Crypto Pay',
            'walletType': 'crypto',
            'receiptKeywords': ['crypto pay'],
            'walletNameAliases': ['crypto'],
            'isActive': true,
          }
        ],
      });
      expect(badWalletType.any((e) => e.contains('walletType')), isTrue);

      final valid = TransactionIntelligenceConfig.validateRawInput({
        'addedExpenseKeywords': {
          'an uong': ['katinat'],
        },
        'disabledAdminKeywords': ['katinat'],
        'customPaymentProviders': [
          {
            'key': 'kredivo_vn',
            'displayLabel': 'Kredivo',
            'walletType': 'eWallet',
            'receiptKeywords': ['kredivo'],
            'walletNameAliases': ['kredivo'],
            'isActive': true,
          }
        ],
      });
      expect(valid, isEmpty);
    });

    test(
        'disabledAdminKeywords bật/tắt từ khóa Admin và CustomPaymentProviderRule.isActive mặc định true & lọc khi false',
        () {
      // Backwards compatibility: doc cũ không có 'isActive' mặc định true
      final legacyProvider = CustomPaymentProviderRule.fromMap(const {
        'key': 'payoo_custom',
        'displayLabel': 'Payoo',
        'walletType': 'eWallet',
        'receiptKeywords': ['payoo'],
        'walletNameAliases': ['payoo'],
      });
      expect(legacyProvider.isActive, isTrue);

      final categories = [
        Category(
          categoryId: 'cat_food',
          userId: 'u1',
          name: 'Ăn uống',
          type: 'expense',
          icon: 'restaurant',
          color: 0xFFEF4444,
        ),
      ];
      final wallets = <Wallet>[
        Wallet(
          walletId: 'w_kredivo',
          userId: 'u1',
          walletName: 'Ví Kredivo',
          balance: 1000000,
          type: 'eWallet',
          isActive: true,
          createdAt: DateTime(2026, 11, 14),
        ),
      ];

      // 1. Khi Admin keyword và Custom Provider đang bật
      final activeService = TransactionIntelligenceService(
        rulesOverride: const TransactionIntelligenceConfig(
          addedExpenseKeywords: {
            'an uong': ['katinat saigon'],
          },
          disabledAdminKeywords: [],
          customPaymentProviders: [
            CustomPaymentProviderRule(
              key: 'kredivo_vn',
              displayLabel: 'Kredivo',
              walletType: 'eWallet',
              receiptKeywords: ['kredivo paylater'],
              walletNameAliases: ['kredivo'],
              isActive: true,
            ),
          ],
        ),
      );
      expect(
        activeService
            .suggestCategory(
              note: 'Thanh toán tại katinat saigon',
              transactionType: 'expense',
              categories: categories,
            )
            .categoryId,
        'cat_food',
      );
      expect(
        activeService
            .suggestWallet(
              ocrRawText: 'Thanh toan qua kredivo paylater',
              wallets: wallets,
            )
            .walletId,
        'w_kredivo',
      );

      // 2. Khi Admin tắt từ khóa 'katinat saigon' qua disabledAdminKeywords và tắt isActive: false
      //    nhưng từ khóa built-in 'phở bò' vẫn hoạt động bình thường
      final disabledService = TransactionIntelligenceService(
        rulesOverride: const TransactionIntelligenceConfig(
          addedExpenseKeywords: {
            'an uong': ['katinat saigon'],
          },
          disabledAdminKeywords: ['katinat saigon'],
          customPaymentProviders: [
            CustomPaymentProviderRule(
              key: 'kredivo_vn',
              displayLabel: 'Kredivo',
              walletType: 'eWallet',
              receiptKeywords: ['kredivo paylater'],
              walletNameAliases: ['kredivo'],
              isActive: false,
            ),
          ],
        ),
      );
      expect(
        disabledService
            .suggestCategory(
              note: 'Thanh toán tại katinat saigon',
              transactionType: 'expense',
              categories: categories,
            )
            .categoryId,
        isEmpty,
      );
      expect(
        disabledService
            .suggestCategory(
              note: 'Ăn phở bò buổi sáng',
              transactionType: 'expense',
              categories: categories,
            )
            .categoryId,
        'cat_food',
      );
      expect(
        disabledService
            .suggestWallet(
              ocrRawText: 'Thanh toan qua kredivo paylater',
              wallets: wallets,
            )
            .isMatched,
        isFalse,
      );
    });
  });

  group('Bản vá 4: FinancialHeuristicsConfig.validateRawInput 1:1 với Server',
      () {
    test(
        'Kiểm tra đủ 18 trường số, ép kiểu nguyên health*Penalty và 4 ràng buộc chéo',
        () {
      final base = FinancialHeuristicsConfig.defaults().toMap();
      expect(FinancialHeuristicsConfig.validateRawInput(base), isEmpty);

      // 1. incomeDropWarningRatio ngoài biên [0.10..0.40]
      final badWarn = {...base, 'incomeDropWarningRatio': 0.45};
      expect(FinancialHeuristicsConfig.validateRawInput(badWarn), isNotEmpty);

      // 2. Khoảng cách incomeDropCriticalRatio - incomeDropWarningRatio < 0.10
      final badGap = {
        ...base,
        'incomeDropWarningRatio': 0.25,
        'incomeDropCriticalRatio': 0.30,
      };
      expect(
        FinancialHeuristicsConfig.validateRawInput(badGap)
            .any((e) => e.contains('ít nhất 0.10')),
        isTrue,
      );

      // 3. health*Penalty phải là số nguyên
      final floatPenalty = {...base, 'healthBudgetExceededPenalty': 12.5};
      expect(
        FinancialHeuristicsConfig.validateRawInput(floatPenalty)
            .any((e) => e.contains('số nguyên')),
        isTrue,
      );

      // 4. categoryForecastMinDiffVnd & txAnomalyMinDiffVnd ngoài [50000..500000]
      final badVnd = {
        ...base,
        'categoryForecastMinDiffVnd': 10000.0,
        'txAnomalyMinDiffVnd': 900000.0,
      };
      expect(FinancialHeuristicsConfig.validateRawInput(badVnd).length, 2);

      // 5. defaultSavingRateNoGoal > minRecommendedSavingRate
      final badSaving = {
        ...base,
        'minRecommendedSavingRate': 0.15,
        'defaultSavingRateNoGoal': 0.25,
      };
      expect(
        FinancialHeuristicsConfig.validateRawInput(badSaving)
            .any((e) => e.contains('không được lớn hơn')),
        isTrue,
      );
    });
  });

  group('Bản vá 6 & 8: AiPromptBuilder, AdminAiSandboxService, AiService clamp 0.1..0.8 & Audit Labels',
      () {
    test('AdminAiSandboxService chạy mượt cả 3 SyntheticPersona chuẩn', () {
      const sandboxService = AdminAiSandboxService();
      final personas = SyntheticPersona.builtInPersonas();
      expect(personas.length, 3);

      for (final persona in personas) {
        final sim = sandboxService.simulatePersona(
          persona: persona,
          runtimeConfig: AiRuntimeConfig.defaults(),
          heuristicsConfig: FinancialHeuristicsConfig.defaults(),
          transactionRules: TransactionIntelligenceConfig.defaults(),
          sampleCategoryText: 'Ăn phở bò 55k',
          sampleReceiptText: 'Thanh toán MoMo 55.000đ',
        );
        expect(sim.personaId, persona.id);
        expect(sim.healthScore, inInclusiveRange(0, 100));
        expect(sim.systemPromptPreview, contains('DATA GROUNDING'));
        expect(sim.structuredPlanPromptPreview, contains('JSON'));
      }
    });

    test('AiService clamp temperature vào đúng [0.1, 0.8] (không còn 0.0)',
        () async {
      double? capturedTemp;
      final aiLow = AiService(
        allowMissingApiKeyForTest: true,
        runtimeConfigOverride: const AiRuntimeConfig(temperature: 0.0),
        contentGeneratorOverride: (model, content, temp) async {
          capturedTemp = temp;
          return 'OK';
        },
      );
      await aiLow.analyzeSpendingHabits(transactions: const [], categories: const []);
      expect(capturedTemp, AiRuntimeConfig.kMinTemperature);
      expect(capturedTemp, 0.1);

      final aiHigh = AiService(
        allowMissingApiKeyForTest: true,
        runtimeConfigOverride: const AiRuntimeConfig(temperature: 1.5),
        contentGeneratorOverride: (model, content, temp) async {
          capturedTemp = temp;
          return 'OK';
        },
      );
      await aiHigh.chatWithFinancialDataStream(
        userQuestion: 'Tôi chi bao nhiêu?',
        contextData: 'Thu nhập 10 triệu',
      ).drain<void>();
      expect(capturedTemp, AiRuntimeConfig.kMaxTemperature);
      expect(capturedTemp, 0.8);
    });

    test('AdminWeb & AiPromptBuilder tuyệt đối không import config/api_keys.dart hay dart:io',
        () {
      final promptBuilderSrc =
          File('lib/services/ai_prompt_builder.dart').readAsStringSync();
      for (final forbiddenImport in const [
        'api_keys.dart',
        'dart:io',
        'google_generative_ai',
        'google_mlkit',
      ]) {
        expect(
          RegExp(r'^import\s+.*' + RegExp.escape(forbiddenImport), multiLine: true)
              .hasMatch(promptBuilderSrc),
          isFalse,
          reason: 'AiPromptBuilder không được import $forbiddenImport',
        );
      }

      final sandboxSrc =
          File('lib/admin_web/services/admin_ai_sandbox_service.dart')
              .readAsStringSync();
      expect(
        RegExp(r'^import\s+.*api_keys\.dart', multiLine: true)
            .hasMatch(sandboxSrc),
        isFalse,
      );
      expect(
        RegExp(r'^import\s+.*ai_service\.dart', multiLine: true)
            .hasMatch(sandboxSrc),
        isFalse,
      );
      expect(AiPromptBuilder.stripMarkdownCodeFence('```json\n{}\n```'), '{}');

      // Kiểm tra toàn bộ đồ thị import bắc cầu từ lib/main_admin.dart
      final libRoot = Directory('lib').absolute;
      final entryFile = File('${libRoot.path}/main_admin.dart');
      final visited = <String>{entryFile.resolveSymbolicLinksSync()};
      final queue = <File>[entryFile];
      final directiveRegex = RegExp(
        r"""^\s*(?:import|export|part)\s+['"]([^'"]+)['"]""",
        multiLine: true,
      );

      while (queue.isNotEmpty) {
        final current = queue.removeAt(0);
        if (!current.existsSync()) continue;
        final src = current.readAsStringSync();
        for (final match in directiveRegex.allMatches(src)) {
          final uri = match.group(1)!;
          if (uri.startsWith('dart:')) continue;
          File? nextFile;
          if (uri.startsWith('package:finance_ai_app/')) {
            final rel = uri.substring('package:finance_ai_app/'.length);
            nextFile = File('${libRoot.path}/$rel');
          } else if (!uri.startsWith('package:')) {
            nextFile = File.fromUri(current.parent.uri.resolve(uri));
          }
          if (nextFile != null && nextFile.existsSync()) {
            final canonical = nextFile.resolveSymbolicLinksSync();
            if (visited.add(canonical)) {
              queue.add(nextFile);
            }
          }
        }
      }

      final forbiddenApiKeys =
          File('${libRoot.path}/config/api_keys.dart').resolveSymbolicLinksSync();
      final forbiddenAiService =
          File('${libRoot.path}/services/ai_service.dart').resolveSymbolicLinksSync();
      expect(visited.contains(forbiddenApiKeys), isFalse,
          reason: 'lib/main_admin.dart không được kéo bắc cầu config/api_keys.dart');
      expect(visited.contains(forbiddenAiService), isFalse,
          reason: 'lib/main_admin.dart không được kéo bắc cầu services/ai_service.dart');
    });

    test('AdminAuditLog.actionDisplayLabel hỗ trợ đủ các action Phase 2/3 mới',
        () {
      AdminAuditLog buildLog(String action) => AdminAuditLog(
            id: '1',
            adminId: 'a',
            adminEmail: 'a@b.c',
            action: action,
            targetType: 'config',
            targetId: 't1',
            details: '',
            createdAt: DateTime(2026, 11, 14),
          );

      for (final action in const [
        'VERIFY_SANDBOX_DRAFT',
        'PUBLISH_CONFIG',
        'ROLLBACK_CONFIG',
        'RESOLVE_AI_FEEDBACK',
        'PUBLISH_KNOWLEDGE',
        'RUN_SANDBOX',
      ]) {
        final label = buildLog(action).actionDisplayLabel;
        expect(label, isNot(equals(action)));
        expect(label.trim(), isNotEmpty);
      }
    });
  });
}
