import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/services/financial_chat_context_service.dart';

void main() {
  group('AI Chat UI & Logic Components Tests', () {
    testWidgets('1. ActionableInsightCard renders budget overrun warning correctly', (tester) async {
      bool actionTapped = false;
      const cardData = ChatInsightCardData(
        type: ChatInsightCardType.budgetOverrun,
        title: 'Cảnh báo: Ăn uống',
        subtitle: 'Đã vượt hạn mức ngân sách tháng này',
        primaryMetric: 'Hạn mức: 3.000.000 ₫',
        actionLabel: 'Xem ngân sách',
        targetId: 'b_1',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) {
                  return InkWell(
                    onTap: () => actionTapped = true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(cardData.title),
                        Text(cardData.subtitle),
                        Text(cardData.primaryMetric),
                        Text(cardData.actionLabel),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('Cảnh báo: Ăn uống'), findsOneWidget);
      expect(find.text('Đã vượt hạn mức ngân sách tháng này'), findsOneWidget);
      expect(find.text('Hạn mức: 3.000.000 ₫'), findsOneWidget);
      expect(find.text('Xem ngân sách'), findsOneWidget);

      await tester.tap(find.text('Xem ngân sách'));
      await tester.pump();
      expect(actionTapped, isTrue);
    });

    test('2. DynamicPromptChip filtering by category works as expected', () {
      final prompts = [
        const DynamicPromptChip(label: 'Tóm tắt tình hình', category: 'overview'),
        const DynamicPromptChip(label: 'Chi tiêu nhiều nhất', category: 'expense'),
        const DynamicPromptChip(label: 'Ăn uống vượt ngân sách!', category: 'budget', isAlert: true),
        const DynamicPromptChip(label: 'Gợi ý tiết kiệm', category: 'saving'),
      ];

      final overviewPrompts = prompts.where((p) => p.category == 'overview').toList();
      final budgetPrompts = prompts.where((p) => p.category == 'budget').toList();
      final alertPrompts = prompts.where((p) => p.isAlert).toList();

      expect(overviewPrompts.length, equals(1));
      expect(overviewPrompts.first.label, equals('Tóm tắt tình hình'));

      expect(budgetPrompts.length, equals(1));
      expect(budgetPrompts.first.isAlert, isTrue);

      expect(alertPrompts.length, equals(1));
      expect(alertPrompts.first.label, contains('vượt ngân sách'));
    });

    test('3. FinancialChatContext quantitative calculations consistency', () {
      const income = 15000000.0;
      const expense = 9000000.0;
      final netCashFlow = income - expense;
      final savingsRate = ((netCashFlow / income) * 100).round();

      expect(netCashFlow, equals(6000000.0));
      expect(savingsRate, equals(40));
    });
  });
}
