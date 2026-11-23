import 'dart:io';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_ai_app/models/budget_model.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/screens/ai/ai_chat_screen.dart';
import 'package:finance_ai_app/services/ai_service.dart';
import 'package:finance_ai_app/services/financial_chat_context_service.dart';
import 'package:finance_ai_app/services/firestore_service.dart';
import 'package:finance_ai_app/services/language_controller.dart';
import 'package:finance_ai_app/utils/constants.dart';
import 'package:finance_ai_app/utils/formatters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LanguageController.loadSavedLanguage();
    await LanguageController.setLanguage('vi');
  });

  Future<void> seedBaseUserAndCategories(
    FakeFirebaseFirestore db,
    String uid,
  ) async {
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'name': 'Nguyễn Minh',
      'email': 'minh@example.com',
      'monthlyIncome': 15000000,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await db.collection('categories').doc('cat_food').set(
      Category(
        categoryId: 'cat_food',
        userId: uid,
        name: 'Ăn uống',
        type: 'expense',
        icon: 'restaurant',
        color: 0xFFD32F2F,
      ).toMap(),
    );
    await db.collection('categories').doc('cat_salary').set(
      Category(
        categoryId: 'cat_salary',
        userId: uid,
        name: 'Lương',
        type: 'income',
        icon: 'work',
        color: 0xFF2E8B57,
      ).toMap(),
    );
  }

  Future<void> seedSufficient90DayData(
    FakeFirebaseFirestore db,
    String uid, {
    double foodBudgetLimit = 6000000,
    double foodExpensePerTx = 500000,
  }) async {
    await seedBaseUserAndCategories(db, uid);
    final now = DateTime.now();
    await db.collection('wallets').doc('w_main').set(
      Wallet(
        walletId: 'w_main',
        userId: uid,
        walletName: 'Ví chính',
        type: 'bank',
        balance: 10000000,
        createdAt: DateTime(now.year, now.month - 2, 1),
      ).toMap(),
    );
    await db.collection('budgets').doc('b_food').set(
      Budget(
        budgetId: 'b_food',
        userId: uid,
        categoryId: 'cat_food',
        limit: foodBudgetLimit,
        month: AppFormatters.month(now),
      ).toMap(),
    );
    // Thu nhập tháng này
    await db.collection('transactions').doc('tx_inc_1').set(
      AppTransaction(
        transactionId: 'tx_inc_1',
        userId: uid,
        walletId: 'w_main',
        categoryId: 'cat_salary',
        amount: 15000000,
        type: 'income',
        date: DateTime(now.year, now.month, 1),
      ).toMap(),
    );
    // 5 giao dịch chi tiêu trên 5 ngày khác nhau trong tháng hiện tại (đạt đủ mật độ)
    for (var i = 0; i < 5; i++) {
      final day = (i + 1).clamp(1, now.day);
      final txDate = DateTime(now.year, now.month, i < now.day ? i + 1 : day)
          .subtract(Duration(days: i < now.day ? 0 : 0));
      // Đảm bảo nằm trong tháng hiện tại và trải >= 3 ngày
      final safeDay = (i + 1) <= DateTime(now.year, now.month + 1, 0).day
          ? i + 1
          : 1;
      await db.collection('transactions').doc('tx_exp_$i').set(
        AppTransaction(
          transactionId: 'tx_exp_$i',
          userId: uid,
          walletId: 'w_main',
          categoryId: 'cat_food',
          amount: foodExpensePerTx,
          type: 'expense',
          date: DateTime(now.year, now.month, safeDay, 12, txDate.minute),
        ).toMap(),
      );
    }
  }

  group('AI Chat UI & Logic Components Tests', () {
    testWidgets(
      '1. ActionableInsightCard renders budget overrun warning correctly',
      (tester) async {
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
      },
    );

    test('2. DynamicPromptChip filtering by category works as expected', () {
      const prompts = [
        DynamicPromptChip(label: 'Tóm tắt tình hình', category: 'overview'),
        DynamicPromptChip(label: 'Chi tiêu nhiều nhất', category: 'expense'),
        DynamicPromptChip(
          label: 'Ăn uống vượt ngân sách!',
          category: 'budget',
          isAlert: true,
        ),
        DynamicPromptChip(label: 'Gợi ý tiết kiệm', category: 'saving'),
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

    testWidgets(
      '4. AppBar hiển thị đủ 3 trạng thái: rỗng, preliminary (hạn chế) và 90 ngày (hỗ trợ cả Vi & En)',
      (tester) async {
        // 4a. Trạng thái rỗng (isEmptyData == true)
        final emptyDb = FakeFirebaseFirestore();
        final emptyFs = FirestoreService(firestore: emptyDb);
        await tester.pumpWidget(
          MaterialApp(
            home: AiChatScreen(
              key: const ValueKey('screen_empty'),
              aiService: AiService(allowMissingApiKeyForTest: true),
              firestoreService: emptyFs,
              contextService: FinancialChatContextService(firestoreService: emptyFs),
              userIdOverride: 'u_empty',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Chưa có dữ liệu giao dịch'), findsOneWidget);

        await LanguageController.setLanguage('en');
        await tester.pumpAndSettle();
        expect(find.text('No transaction data yet'), findsOneWidget);

        // 4b. Trạng thái preliminary (chỉ có 2 giao dịch -> !hasSufficientData)
        await LanguageController.setLanguage('vi');
        final prelimDb = FakeFirebaseFirestore();
        final prelimFs = FirestoreService(firestore: prelimDb);
        await seedBaseUserAndCategories(prelimDb, 'u_prelim');
        final now = DateTime.now();
        await prelimDb.collection('transactions').doc('t1').set(
          AppTransaction(
            transactionId: 't1',
            userId: 'u_prelim',
            walletId: 'w1',
            categoryId: 'cat_food',
            amount: 50000,
            type: 'expense',
            date: DateTime(now.year, now.month, 1),
          ).toMap(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: AiChatScreen(
              key: const ValueKey('screen_prelim'),
              aiService: AiService(allowMissingApiKeyForTest: true),
              firestoreService: prelimFs,
              contextService: FinancialChatContextService(firestoreService: prelimFs),
              userIdOverride: 'u_prelim',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Dữ liệu sơ khởi (hạn chế)'), findsOneWidget);

        await LanguageController.setLanguage('en');
        await tester.pumpAndSettle();
        expect(find.text('Preliminary data (limited)'), findsOneWidget);

        // 4c. Trạng thái đủ dữ liệu 90 ngày
        await LanguageController.setLanguage('vi');
        final fullDb = FakeFirebaseFirestore();
        final fullFs = FirestoreService(firestore: fullDb);
        await seedSufficient90DayData(fullDb, 'u_full');
        await tester.pumpWidget(
          MaterialApp(
            home: AiChatScreen(
              key: const ValueKey('screen_full'),
              aiService: AiService(allowMissingApiKeyForTest: true),
              firestoreService: fullFs,
              contextService: FinancialChatContextService(firestoreService: fullFs),
              userIdOverride: 'u_full',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Hiểu dữ liệu 90 ngày'), findsOneWidget);

        await LanguageController.setLanguage('en');
        await tester.pumpAndSettle();
        expect(find.text('90-day data synced'), findsOneWidget);
      },
    );

    testWidgets(
      '5. Gỡ thanh 6 tab lọc chủ đề, chỉ giữ 1 hàng 4-5 chip ưu tiên cảnh báo đỏ và giữ nút Phân tích nhanh',
      (tester) async {
        final db = FakeFirebaseFirestore();
        final fs = FirestoreService(firestore: db);
        // Chi 5 x 1.000.000 = 5.000.000 > limit 3.000.000 -> có chip cảnh báo đỏ vượt ngân sách
        await seedSufficient90DayData(
          db,
          'u_compact',
          foodBudgetLimit: 3000000,
          foodExpensePerTx: 1000000,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AiChatScreen(
              aiService: AiService(allowMissingApiKeyForTest: true),
              firestoreService: fs,
              contextService: FinancialChatContextService(firestoreService: fs),
              userIdOverride: 'u_compact',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Không còn các tab của thanh filter 6 chủ đề
        expect(find.text('Tất cả'), findsNothing);
        expect(find.text('⚡ Nổi bật'), findsNothing);
        expect(find.text('📊 Tổng quan'), findsNothing);
        expect(find.text('💸 Chi tiêu'), findsNothing);
        expect(find.text('🎯 Ngân sách'), findsNothing);
        expect(find.text('💎 Tiết kiệm'), findsNothing);

        // Chỉ giữ 1 hàng gọn chứa <= 5 ActionChip và ưu tiên chip cảnh báo đỏ ở đầu
        expect(find.byKey(const ValueKey('ai_chat_compact_prompts_bar')), findsOneWidget);
        final chips = tester.widgetList<ActionChip>(find.byType(ActionChip)).toList();
        expect(chips.length, inInclusiveRange(1, 5));
        expect(chips.first.backgroundColor, AppColors.expenseBackground);

        // Vẫn giữ nút ⚡ Phân tích nhanh trên AppBar
        expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
        await tester.tap(find.byIcon(Icons.bolt_rounded));
        await tester.pumpAndSettle();
        expect(find.text('⚡ Phân tích tài chính nhanh'), findsOneWidget);
      },
    );

    testWidgets(
      '6. Thẻ ngân sách an toàn dùng màu xanh tích cực, thẻ vượt ngân sách dùng màu đỏ cảnh báo',
      (tester) async {
        final db = FakeFirebaseFirestore();
        final fs = FirestoreService(firestore: db);
        // 5 x 500k = 2.5M <= limit 6M -> ngân sách Ăn uống đang an toàn
        await seedSufficient90DayData(
          db,
          'u_safe_budget',
          foodBudgetLimit: 6000000,
          foodExpensePerTx: 500000,
        );

        final aiSvc = AiService(
          allowMissingApiKeyForTest: true,
          streamGeneratorOverride: (model, content, temp) async* {
            yield 'Bạn đã chi 2500000đ cho Ăn uống, vẫn trong hạn mức an toàn.';
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AiChatScreen(
              key: const ValueKey('screen_safe_budget'),
              aiService: aiSvc,
              firestoreService: fs,
              contextService: FinancialChatContextService(firestoreService: fs),
              userIdOverride: 'u_safe_budget',
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField),
          'Tôi chi bao nhiêu cho ăn uống tháng này?',
        );
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        // Kiểm tra chuẩn hóa số tiền sau streaming
        expect(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().contains('2.500.000đ'),
          ),
          findsOneWidget,
        );

        // Thẻ ngân sách an toàn phải hiển thị icon xanh tích cực, không dùng icon cảnh báo đỏ
        final safeIconFinder = find.byIcon(Icons.check_circle_outline_rounded);
        expect(safeIconFinder, findsOneWidget);
        final safeIcon = tester.widget<Icon>(safeIconFinder);
        expect(safeIcon.color, AppColors.income);

        // Kiểm tra trường hợp vượt ngân sách (initial greeting card màu đỏ)
        final overDb = FakeFirebaseFirestore();
        final overFs = FirestoreService(firestore: overDb);
        await seedSufficient90DayData(
          overDb,
          'u_over_budget',
          foodBudgetLimit: 2000000,
          foodExpensePerTx: 600000, // 3M > 2M
        );
        await tester.pumpWidget(
          MaterialApp(
            home: AiChatScreen(
              key: const ValueKey('screen_over_budget'),
              aiService: AiService(allowMissingApiKeyForTest: true),
              firestoreService: overFs,
              contextService: FinancialChatContextService(firestoreService: overFs),
              userIdOverride: 'u_over_budget',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Thẻ cảnh báo vượt ngân sách có tiêu đề "Cảnh báo: Ăn uống" và icon đỏ
        expect(find.text('Cảnh báo: Ăn uống'), findsOneWidget);
        final warnIcons = tester
            .widgetList<Icon>(find.byIcon(Icons.warning_amber_rounded))
            .where((i) => i.size == 16)
            .toList();
        expect(warnIcons, isNotEmpty);
        expect(warnIcons.first.color, AppColors.expense);
      },
    );

    testWidgets(
      '7. Không lưu bubble lỗi vào Firestore, xóa bubble lỗi khi Thử lại thành công và không nối chữ khi fallback stream',
      (tester) async {
        final db = FakeFirebaseFirestore();
        final fs = FirestoreService(firestore: db);
        await seedSufficient90DayData(db, 'u_retry_flow');

        int callCount = 0;
        final aiSvc = AiService(
          allowMissingApiKeyForTest: true,
          streamGeneratorOverride: (model, content, temp) async* {
            callCount++;
            if (callCount == 1) {
              throw const SocketException('Failed host lookup');
            }
            if (model == 'gemini-3.5-flash') {
              yield 'Đoạn rác đứt giữa chừng ';
              throw Exception('Stream broken');
            }
            yield 'Tổng chi tháng này là ';
            yield '5000000đ.';
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AiChatScreen(
              aiService: aiSvc,
              firestoreService: fs,
              contextService: FinancialChatContextService(firestoreService: fs),
              userIdOverride: 'u_retry_flow',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Bước 1: Gửi tin nhắn khi mất mạng -> hiện bubble lỗi + nút Thử lại
        await tester.enterText(find.byType(TextField), 'Tổng chi tháng này?');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Không có kết nối mạng'),
          findsOneWidget,
        );
        expect(find.text('Thử lại'), findsOneWidget);

        // Firestore chưa lưu bubble lỗi nào
        final sessionsAfterErr = await fs.getUserChatSessions('u_retry_flow');
        expect(sessionsAfterErr, isEmpty);

        // Bước 2: Bấm "Thử lại" -> Model 1 đứt giữa chừng -> fallback model 2 thành công
        await tester.tap(find.text('Thử lại'));
        await tester.pumpAndSettle();

        // Bubble lỗi cũ đã bị xóa khỏi UI
        expect(find.textContaining('Không có kết nối mạng'), findsNothing);
        expect(find.text('Thử lại'), findsNothing);

        // Không nhân đôi câu hỏi user
        expect(find.text('Tổng chi tháng này?'), findsOneWidget);

        // Không bị nối chữ từ model 1 và số tiền được chuẩn hóa thành 5.000.000đ
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is RichText &&
                w.text.toPlainText().contains('Đoạn rác đứt giữa chừng'),
          ),
          findsNothing,
        );
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is RichText &&
                w.text.toPlainText().contains('Tổng chi tháng này là 5.000.000đ.'),
          ),
          findsOneWidget,
        );

        // Bước 3: Kiểm tra Firestore chỉ lưu tin nhắn hợp lệ, tuyệt đối không có isError == true
        final sessionsAfterRetry = await fs.getUserChatSessions('u_retry_flow');
        expect(sessionsAfterRetry.length, 1);
        final savedMsgs = sessionsAfterRetry.first['messages'] as List<dynamic>;
        expect(
          savedMsgs.any((m) => m is Map && m['isError'] == true),
          isFalse,
        );
        expect(
          savedMsgs.any((m) =>
              m is Map &&
              m['text'] == 'Tổng chi tháng này là 5.000.000đ.'),
          isTrue,
        );
      },
    );

    testWidgets(
      '8. Khi có bubble lỗi cũ chưa bấm Thử lại và user gửi câu mới thành công, Firestore vẫn lọc bỏ hoàn toàn bubble lỗi',
      (tester) async {
        final db = FakeFirebaseFirestore();
        final fs = FirestoreService(firestore: db);
        await seedSufficient90DayData(db, 'u_filter_err_save');

        int callCount = 0;
        final aiSvc = AiService(
          allowMissingApiKeyForTest: true,
          streamGeneratorOverride: (model, content, temp) async* {
            callCount++;
            if (callCount == 1) {
              throw const SocketException('Failed host lookup');
            }
            yield 'Dòng tiền tháng này đang dương **12500000đ**.';
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AiChatScreen(
              key: const ValueKey('screen_filter_err'),
              aiService: aiSvc,
              firestoreService: fs,
              contextService: FinancialChatContextService(firestoreService: fs),
              userIdOverride: 'u_filter_err_save',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Lượt 1: Lỗi mất mạng -> xuất hiện bubble lỗi trên UI
        await tester.enterText(find.byType(TextField), 'Câu hỏi khi mất mạng');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();
        expect(find.textContaining('Không có kết nối mạng'), findsOneWidget);

        // Lượt 2: User bỏ qua nút Thử lại, nhập câu mới và gửi thành công
        await tester.enterText(find.byType(TextField), 'Dòng tiền tháng này?');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        final sessions = await fs.getUserChatSessions('u_filter_err_save');
        expect(sessions.length, 1);
        final savedMsgs = sessions.first['messages'] as List<dynamic>;
        // Bubble lỗi tuyệt đối không được lưu vào Firestore
        expect(
          savedMsgs.any((m) => m is Map && m['isError'] == true),
          isFalse,
        );
        expect(
          savedMsgs.any((m) =>
              m is Map &&
              (m['text'] as String? ?? '').contains('12.500.000đ')),
          isTrue,
        );
      },
    );
  });
}
