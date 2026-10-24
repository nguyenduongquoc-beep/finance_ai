import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/budget_model.dart';
import 'package:finance_ai_app/models/saving_goal_model.dart';
import 'package:finance_ai_app/services/firestore_service.dart';
import 'package:finance_ai_app/services/financial_chat_context_service.dart';

void main() {
  group('FinancialChatContextService Tests', () {
    late FinancialChatContextService service;

    setUp(() {
      final fakeFirestore = FakeFirebaseFirestore();
      final firestoreService = FirestoreService(firestore: fakeFirestore);
      service = FinancialChatContextService(firestoreService: firestoreService);
    });

    final testCategories = [
      Category(
        categoryId: 'cat_food',
        userId: 'user_1',
        name: 'Ăn uống',
        type: 'expense',
        icon: 'restaurant',
        color: 0xFFD32F2F,
      ),
      Category(
        categoryId: 'cat_shopping',
        userId: 'user_1',
        name: 'Mua sắm',
        type: 'expense',
        icon: 'shopping_bag',
        color: 0xFFE64A19,
      ),
    ];

    test('detectInsightCard: returns emptyDataPrompt when isEmptyData is true', () {
      const emptyContext = FinancialChatContext(
        rawPromptContext: 'Chưa có dữ liệu',
        incomeThisMonth: 0,
        expenseThisMonth: 0,
        netCashFlow: 0,
        savingsRate: 0,
        totalActiveBalance: 0,
        averageMonthlySavings: 0,
        overBudgets: [],
        nearLimitBudgets: [],
        savingGoals: [],
        issues: [],
        dynamicPrompts: [],
        hasSufficientData: false,
        isEmptyData: true,
      );

      final card = service.detectInsightCard(
        question: 'Tháng này tôi chi bao nhiêu?',
        answer: 'Bạn chưa có dữ liệu giao dịch.',
        context: emptyContext,
        categories: testCategories,
      );

      expect(card, isNotNull);
      expect(card!.type, ChatInsightCardType.emptyDataPrompt);
      expect(card.actionLabel, 'Thêm giao dịch ngay');
    });

    test('detectInsightCard: returns budgetOverrun when overBudgets exists', () {
      final overBudgetContext = FinancialChatContext(
        rawPromptContext: 'Ăn uống: đã chi 3.500.000 / 3.000.000',
        incomeThisMonth: 10000000,
        expenseThisMonth: 8000000,
        netCashFlow: 2000000,
        savingsRate: 20,
        totalActiveBalance: 15000000,
        averageMonthlySavings: 2000000,
        overBudgets: [
          Budget(
            budgetId: 'b1',
            userId: 'user_1',
            categoryId: 'cat_food',
            limit: 3000000,
            month: '10/2026',
          ),
        ],
        nearLimitBudgets: [],
        savingGoals: [],
        issues: [],
        dynamicPrompts: [],
        hasSufficientData: true,
        isEmptyData: false,
      );

      final card = service.detectInsightCard(
        question: 'Có ngân sách nào bị vượt hạn mức không?',
        answer: 'Danh mục Ăn uống đã vượt ngân sách 500.000 đ.',
        context: overBudgetContext,
        categories: testCategories,
      );

      expect(card, isNotNull);
      expect(card!.type, ChatInsightCardType.budgetOverrun);
      expect(card.title, contains('Ăn uống'));
      expect(card.actionLabel, 'Xem ngân sách');
    });

    test('detectInsightCard: returns savingGoalProgress when asked about saving goals', () {
      final goalContext = FinancialChatContext(
        rawPromptContext: 'Mục tiêu Laptop',
        incomeThisMonth: 12000000,
        expenseThisMonth: 7000000,
        netCashFlow: 5000000,
        savingsRate: 41,
        totalActiveBalance: 20000000,
        averageMonthlySavings: 4000000,
        overBudgets: [],
        nearLimitBudgets: [],
        savingGoals: [
          SavingGoal(
            goalId: 'g1',
            userId: 'user_1',
            name: 'Mua Laptop',
            targetAmount: 20000000,
            savedAmount: 10000000,
            months: 5,
            createdAt: DateTime.now(),
          ),
        ],
        issues: [],
        dynamicPrompts: [],
        hasSufficientData: true,
        isEmptyData: false,
      );

      final card = service.detectInsightCard(
        question: 'Tiến độ mục tiêu tiết kiệm của tôi thế nào?',
        answer: 'Bạn đã đạt 50% mục tiêu Mua Laptop.',
        context: goalContext,
        categories: testCategories,
      );

      expect(card, isNotNull);
      expect(card!.type, ChatInsightCardType.savingGoalProgress);
      expect(card.title, contains('Mua Laptop'));
      expect(card.progressPercent, 0.5);
      expect(card.actionLabel, 'Xem mục tiêu');
    });

    test('detectInsightCard: returns cashFlowSnapshot when asked about general cashflow', () {
      const normalContext = FinancialChatContext(
        rawPromptContext: 'Tổng quan dòng tiền',
        incomeThisMonth: 15000000,
        expenseThisMonth: 10000000,
        netCashFlow: 5000000,
        savingsRate: 33,
        totalActiveBalance: 25000000,
        averageMonthlySavings: 4500000,
        overBudgets: [],
        nearLimitBudgets: [],
        savingGoals: [],
        issues: [],
        dynamicPrompts: [],
        hasSufficientData: true,
        isEmptyData: false,
      );

      final card = service.detectInsightCard(
        question: 'Tình hình dòng tiền tháng này của tôi thế nào?',
        answer: 'Thu nhập 15 triệu, chi tiêu 10 triệu, thặng dư 5 triệu.',
        context: normalContext,
        categories: testCategories,
      );

      expect(card, isNotNull);
      expect(card!.type, ChatInsightCardType.cashFlowSnapshot);
      expect(card.title, 'Dòng tiền tháng này');
      expect(card.actionLabel, 'Xem giao dịch');
    });

    test('detectInsightCard: 7 Scenario tests ensuring no false Laptop goal cards', () {
      final multiGoalContext = FinancialChatContext(
        rawPromptContext: 'Context dữ liệu đa mục tiêu',
        incomeThisMonth: 20000000,
        expenseThisMonth: 12000000,
        netCashFlow: 8000000,
        savingsRate: 40,
        totalActiveBalance: 30000000,
        averageMonthlySavings: 7000000,
        budgets: [
          Budget(
            budgetId: 'b_food',
            userId: 'user_1',
            categoryId: 'cat_food',
            limit: 4000000,
            month: '10/2026',
          ),
        ],
        currentExpenseByCat: {
          'cat_food': 3500000,
          'cat_shopping': 2000000,
        },
        overBudgets: [],
        nearLimitBudgets: [],
        savingGoals: [
          SavingGoal(
            goalId: 'g_laptop',
            userId: 'user_1',
            name: 'Mua Laptop',
            targetAmount: 25000000,
            savedAmount: 15000000,
            months: 6,
            createdAt: DateTime.now(),
          ),
          SavingGoal(
            goalId: 'g_travel',
            userId: 'user_1',
            name: 'Du lịch Đà Nẵng',
            targetAmount: 10000000,
            savedAmount: 3000000,
            months: 3,
            createdAt: DateTime.now(),
          ),
        ],
        issues: [],
        dynamicPrompts: [],
        hasSufficientData: true,
        isEmptyData: false,
      );

      // Kịch bản 1: Hỏi về ăn uống -> Tuyệt đối KHÔNG ra thẻ Mua Laptop!
      final card1 = service.detectInsightCard(
        question: 'Tôi chi bao nhiêu cho ăn uống tháng này?',
        answer: 'Bạn đã chi 3.500.000 đ cho danh mục Ăn uống.',
        context: multiGoalContext,
        categories: testCategories,
      );
      expect(card1, isNotNull);
      expect(card1!.title, contains('Ăn uống'));
      expect(card1.type, isNot(ChatInsightCardType.savingGoalProgress));

      // Kịch bản 2: Hỏi đích danh mục tiêu Laptop -> Ra đúng thẻ Mua Laptop
      final card2 = service.detectInsightCard(
        question: 'Tiến độ mục tiêu mua Laptop của tôi thế nào?',
        answer: 'Mục tiêu Mua Laptop đã đạt 60%.',
        context: multiGoalContext,
        categories: testCategories,
      );
      expect(card2, isNotNull);
      expect(card2!.type, ChatInsightCardType.savingGoalProgress);
      expect(card2.title, contains('Mua Laptop'));
      expect(card2.targetId, 'g_laptop');

      // Kịch bản 3: Hỏi tư vấn tiết kiệm chung -> KHÔNG chèn thẻ Laptop bừa bãi
      final card3 = service.detectInsightCard(
        question: 'Làm thế nào để tiết kiệm 2 triệu mỗi tháng?',
        answer: 'Bạn nên rà soát các khoản chi tiêu không thiết yếu.',
        context: multiGoalContext,
        categories: testCategories,
      );
      expect(card3, isNull);

      final card3b = service.detectInsightCard(
        question: 'Tư vấn cách tiết kiệm chi phí sinh hoạt cho tôi',
        answer: 'Hãy lập hạn mức cho các danh mục linh hoạt.',
        context: multiGoalContext,
        categories: testCategories,
      );
      expect(card3b, isNull);

      // Kịch bản 4: Kiểm tra ngân sách có bị vượt không (khi chưa vượt)
      final card4 = service.detectInsightCard(
        question: 'Ngân sách tháng này của tôi có bị vượt không?',
        answer: 'Chưa có ngân sách nào bị vượt hạn mức.',
        context: multiGoalContext,
        categories: testCategories,
      );
      expect(card4, isNotNull);
      expect(card4!.title, contains('Ngân sách'));

      // Kịch bản 5: Dòng tiền tháng này
      final card5 = service.detectInsightCard(
        question: 'Dòng tiền tháng này của tôi ra sao?',
        answer: 'Tháng này bạn thặng dư 8 triệu đồng.',
        context: multiGoalContext,
        categories: testCategories,
      );
      expect(card5, isNotNull);
      expect(card5!.type, ChatInsightCardType.cashFlowSnapshot);

      // Kịch bản 6: Thu nhập tháng này
      final card6 = service.detectInsightCard(
        question: 'Thu nhập tháng này của tôi bao nhiêu?',
        answer: 'Thu nhập tháng này là 20.000.000 đ.',
        context: multiGoalContext,
        categories: testCategories,
      );
      expect(card6, isNotNull);
      expect(card6!.type, ChatInsightCardType.cashFlowSnapshot);

      // Kịch bản 7: Chào hỏi / Hỏi trợ lý có thể làm gì -> KHÔNG hiện thẻ
      final card7 = service.detectInsightCard(
        question: 'Chào bạn, bạn có thể làm gì?',
        answer: 'Chào bạn! Mình có thể phân tích chi tiêu, kiểm tra ngân sách...',
        context: multiGoalContext,
        categories: testCategories,
      );
      expect(card7, isNull);
    });

    test('ChatInsightCardData toMap and fromMap serialization works symmetrically', () {
      const original = ChatInsightCardData(
        type: ChatInsightCardType.budgetOverrun,
        title: 'Cảnh báo Ăn uống',
        subtitle: 'Vượt ngân sách',
        primaryMetric: '500.000 ₫',
        secondaryMetric: 'Cần kiểm soát',
        progressPercent: 1.15,
        actionLabel: 'Xem ngân sách',
        targetId: 'b_123',
      );

      final map = original.toMap();
      final reconstructed = ChatInsightCardData.fromMap(map);

      expect(reconstructed.type, equals(original.type));
      expect(reconstructed.title, equals(original.title));
      expect(reconstructed.subtitle, equals(original.subtitle));
      expect(reconstructed.primaryMetric, equals(original.primaryMetric));
      expect(reconstructed.secondaryMetric, equals(original.secondaryMetric));
      expect(reconstructed.progressPercent, equals(original.progressPercent));
      expect(reconstructed.actionLabel, equals(original.actionLabel));
      expect(reconstructed.targetId, equals(original.targetId));
    });

    test('Firestore Chat Session storage: save, fetch and delete session', () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final firestoreService = FirestoreService(firestore: fakeFirestore);

      const userId = 'user_test_99';
      const sessionId = 'session_1';
      final messages = [
        {
          'id': 'm1',
          'text': 'Tình hình tài chính tháng này?',
          'isUser': true,
          'timestamp': DateTime.now().toIso8601String(),
        },
        {
          'id': 'm2',
          'text': 'Tháng này bạn thặng dư 2 triệu.',
          'isUser': false,
          'timestamp': DateTime.now().toIso8601String(),
        },
      ];

      // 1. Lưu session
      await firestoreService.saveChatSession(
        userId: userId,
        sessionId: sessionId,
        title: 'Tình hình tài chính tháng này',
        messages: messages,
      );

      // 2. Lấy danh sách session
      final sessions = await firestoreService.getUserChatSessions(userId);
      expect(sessions.length, equals(1));
      expect(sessions.first['sessionId'], equals(sessionId));
      expect(sessions.first['title'], equals('Tình hình tài chính tháng này'));

      // 3. Lấy chi tiết session
      final detail = await firestoreService.getChatSession(userId, sessionId);
      expect(detail, isNotNull);
      final loadedMessages = detail!['messages'] as List;
      expect(loadedMessages.length, equals(2));

      // 4. Xóa session
      await firestoreService.deleteChatSession(userId, sessionId);
      final remaining = await firestoreService.getUserChatSessions(userId);
      expect(remaining, isEmpty);
    });
  });
}
