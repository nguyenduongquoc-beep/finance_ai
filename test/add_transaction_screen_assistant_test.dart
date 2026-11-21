import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/receipt_info.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/screens/home/add_transaction_screen.dart';
import 'package:finance_ai_app/services/transaction_intelligence_service.dart';
import 'package:finance_ai_app/utils/category_utils.dart';

void main() {
  group('areCategoryListsEqual (shared production helper)', () {
    Category makeCat(String id, String name, String type) => Category(
          categoryId: id,
          userId: 'u1',
          name: name,
          type: type,
          icon: 'icon',
          color: 0,
        );

    test('1. Returns true for identical lists – StreamBuilder should NOT re-trigger intelligence check', () {
      final list1 = [makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Di chuyển', 'expense')];
      final list2 = [makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Di chuyển', 'expense')];
      expect(areCategoryListsEqual(list1, list2), isTrue);
    });

    test('2. Returns false when a category name changes – StreamBuilder SHOULD re-trigger intelligence check', () {
      final list1 = [makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Di chuyển', 'expense')];
      final list2 = [makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Giao thông', 'expense')];
      expect(areCategoryListsEqual(list1, list2), isFalse);
    });

    test('3. Returns false when list lengths differ', () {
      final list1 = [makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Di chuyển', 'expense')];
      final list2 = [makeCat('c1', 'Ăn uống', 'expense')];
      expect(areCategoryListsEqual(list1, list2), isFalse);
    });

    test('4. Returns false when a category ID changes', () {
      final list1 = [makeCat('c1', 'Ăn uống', 'expense')];
      final list2 = [makeCat('c99', 'Ăn uống', 'expense')];
      expect(areCategoryListsEqual(list1, list2), isFalse);
    });

    test('5. Returns false when category type changes', () {
      final list1 = [makeCat('c1', 'Lương', 'income')];
      final list2 = [makeCat('c1', 'Lương', 'expense')];
      expect(areCategoryListsEqual(list1, list2), isFalse);
    });

    test('6. Returns true for two empty lists', () {
      expect(areCategoryListsEqual([], []), isTrue);
    });

    test('7. Returns false when a new category is appended (simulates Firestore stream adding category)', () {
      final list1 = [makeCat('c1', 'Ăn uống', 'expense')];
      final list2 = [makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Mua sắm', 'expense')];
      expect(areCategoryListsEqual(list1, list2), isFalse);
    });

    test('8. Returns false when order changes (same items, different order)', () {
      final list1 = [makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Di chuyển', 'expense')];
      final list2 = [makeCat('c2', 'Di chuyển', 'expense'), makeCat('c1', 'Ăn uống', 'expense')];
      expect(areCategoryListsEqual(list1, list2), isFalse);
    });


    test('9. Guard logic: unchanged emit does not trigger, changed emit triggers exactly once', () {
      // Simulate the StreamBuilder guard logic from AddTransactionScreen:
      //   if (!areCategoryListsEqual(_allCategories, newCategories)) {
      //     _allCategories = newCategories;
      //     // schedule _runIntelligenceCheck
      //   }
      var cachedCategories = <Category>[];
      int intelligenceCheckCount = 0;

      void simulateStreamEmit(List<Category> newCategories) {
        if (!areCategoryListsEqual(cachedCategories, newCategories)) {
          cachedCategories = newCategories;
          intelligenceCheckCount++;
        }
      }

      final cats1 = [makeCat('c1', 'Ăn uống', 'expense')];
      final cats1Clone = [makeCat('c1', 'Ăn uống', 'expense')];
      final cats2 = [makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Mua sắm', 'expense')];

      // First emit – new data – should trigger
      simulateStreamEmit(cats1);
      expect(intelligenceCheckCount, 1);

      // Same data re-emitted – should NOT trigger (no infinite rebuild loop)
      simulateStreamEmit(cats1Clone);
      expect(intelligenceCheckCount, 1);

      // Actually changed data – should trigger exactly once more
      simulateStreamEmit(cats2);
      expect(intelligenceCheckCount, 2);

      // Same changed data re-emitted – should NOT trigger
      simulateStreamEmit([makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Mua sắm', 'expense')]);
      expect(intelligenceCheckCount, 2);
    });
  });

  group('detectAnomaly excludeTransactionId', () {
    final service = TransactionIntelligenceService();

    test('10. Excludes transactionToEdit.transactionId from history median sample', () {
      final now = DateTime.now();
      const editingTxId = 'editing_tx_999';

      final history = [
        AppTransaction(
          transactionId: editingTxId,
          userId: 'u1', walletId: 'w1', categoryId: 'c1',
          amount: 100000, type: 'expense',
          date: now.subtract(const Duration(days: 1)),
        ),
        AppTransaction(
          transactionId: 't2',
          userId: 'u1', walletId: 'w1', categoryId: 'c1',
          amount: 100000, type: 'expense',
          date: now.subtract(const Duration(days: 2)),
        ),
        AppTransaction(
          transactionId: 't3',
          userId: 'u1', walletId: 'w1', categoryId: 'c1',
          amount: 100000, type: 'expense',
          date: now.subtract(const Duration(days: 3)),
        ),
        AppTransaction(
          transactionId: 't4',
          userId: 'u1', walletId: 'w1', categoryId: 'c1',
          amount: 100000, type: 'expense',
          date: now.subtract(const Duration(days: 4)),
        ),
        AppTransaction(
          transactionId: 't5',
          userId: 'u1', walletId: 'w1', categoryId: 'c1',
          amount: 100000, type: 'expense',
          date: now.subtract(const Duration(days: 5)),
        ),
      ];

      // Without exclusion: sample size = 5 → anomaly detected
      final resultWithSelf = service.detectAnomaly(
        amount: 300000,
        categoryId: 'c1',
        categoryName: 'Ăn uống',
        transactionType: 'expense',
        userHistory: history,
      );
      expect(resultWithSelf.isAnomalous, isTrue);

      // With exclusion: sample size = 4 (< 5) → no anomaly
      final resultWithoutSelf = service.detectAnomaly(
        amount: 300000,
        categoryId: 'c1',
        categoryName: 'Ăn uống',
        transactionType: 'expense',
        userHistory: history,
        excludeTransactionId: editingTxId,
      );
      expect(resultWithoutSelf.isAnomalous, isFalse);
    });
  });

  group('AddTransactionScreen OCR vs Manual Entry Widget Tests', () {
    final testWallets = [
      Wallet(
        walletId: 'w_cash',
        userId: 'u1',
        walletName: 'Tiền mặt',
        balance: 16000000,
        type: 'cash',
        createdAt: DateTime(2026, 1, 1),
      ),
      Wallet(
        walletId: 'w_mb',
        userId: 'u1',
        walletName: 'MB Bank',
        balance: 5000000,
        type: 'bank',
        createdAt: DateTime(2026, 1, 1),
      ),
    ];

    final testCategories = [
      Category(
        categoryId: 'cat_food',
        userId: 'u1',
        name: 'Ăn uống',
        type: 'expense',
        icon: 'restaurant',
        color: 0xFFE53935,
      ),
      Category(
        categoryId: 'cat_bonus',
        userId: 'u1',
        name: 'Thưởng',
        type: 'income',
        icon: 'card_giftcard',
        color: 0xFFFB8C00,
      ),
      Category(
        categoryId: 'cat_salary',
        userId: 'u1',
        name: 'Lương',
        type: 'income',
        icon: 'work',
        color: 0xFF43A047,
      ),
    ];

    testWidgets(
      '11. Nhập thủ công (Manual entry): KHÔNG hiển thị chip "AI gợi ý" khi chọn danh mục hoặc nhập ghi chú thủ công',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: AddTransactionScreen(
              initialType: 'income',
              walletsStream: Stream.value(testWallets),
              categoriesStream: Stream.value(testCategories),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Nhập ghi chú thủ công có chứa từ khóa "thưởng" / "lương"
        await tester.enterText(
          find.widgetWithText(TextField, 'Ghi chú'),
          'Thưởng dự án tháng 11',
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        // Không được hiển thị câu đề xuất "AI gợi ý:" khi nhập thủ công
        expect(find.textContaining('AI gợi ý:'), findsNothing);
      },
    );

    testWidgets(
      '12. Trích xuất OCR (khi người dùng CÓ ví tương ứng): Tự động chọn cả Ví ("Tiền mặt") và Danh mục ("Ăn uống"), hiển thị gợi ý AI',
      (tester) async {
        final ocrReceipt = ReceiptInfo(
          merchant: 'Kang Tea & Coffee - Bạch Đằng',
          total: 50000,
          date: DateTime(2026, 11, 13),
          address: '20 Bạch Đằng, Phú Cường, Tp Thủ Dầu Một, Bình Dương',
          paymentMethod: 'Tiền mặt',
          rawText:
              'Kang Tea & Coffee\nCà Phê Sữa Đá Máy 50,000\n+Thanh toán tiền mặt 50,000 đ\nTiền nhận 50,000 đ\nTiền thừa 0 đ',
          items: [
            ReceiptItem(description: 'Cà Phê Sữa Đá Máy', amount: 50000),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AddTransactionScreen(
              walletsStream: Stream.value(testWallets),
              categoriesStream: Stream.value(testCategories),
              initialOcrReceiptForTest: ocrReceipt,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Số tiền 50.000 đã được điền
        expect(find.text('50.000'), findsOneWidget);

        // Ví "Tiền mặt" và Danh mục "Ăn uống" đều hiển thị chip AI gợi ý và đã được tự động chọn
        expect(find.text('AI gợi ý: Tiền mặt (90% tin cậy)'), findsOneWidget);
        expect(
          find.textContaining('AI gợi ý: Ăn uống'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '13. Trích xuất OCR (khi người dùng KHÔNG CÓ loại ví trên hóa đơn): Không chọn nhầm ví, hiển thị thông báo không có loại ví này',
      (tester) async {
        final ocrReceipt = ReceiptInfo(
          merchant: 'Kang Tea & Coffee - Bạch Đằng',
          total: 50000,
          date: DateTime(2026, 11, 13),
          paymentMethod: 'MoMo',
          items: [
            ReceiptItem(description: 'Cà Phê Sữa Đá Máy', amount: 50000),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AddTransactionScreen(
              walletsStream: Stream.value(testWallets), // Chỉ có Tiền mặt & MB Bank, không có MoMo
              categoriesStream: Stream.value(testCategories),
              initialOcrReceiptForTest: ocrReceipt,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Hiển thị cảnh báo không có loại ví MoMo
        expect(
          find.text(
            'Bạn không có loại ví "MoMo" như trên hóa đơn. Vui lòng chọn ví khác.',
          ),
          findsOneWidget,
        );

        // Danh mục vẫn được nhận diện bình thường
        expect(
          find.textContaining('AI gợi ý: Ăn uống'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '14. Trích xuất OCR chi tiết (SL, Đơn giá, Thành tiền), kết hợp Địa điểm và hiển thị thông báo khi AI khôi phục chữ mờ',
      (tester) async {
        final ocrReceipt = ReceiptInfo.fromJson({
          'merchant': 'Kang Tea & Coffee - Bạch Đằng',
          'total': 50000,
          'date': '2026-11-13',
          'address': '20 Bạch Đằng, Phú Cường, Tp Thủ Dầu Một, Bình Dương',
          'paymentMethod': 'Tiền mặt',
          'items': [
            {
              'description': 'Cà Phê Sữa Đa Máy',
              'quantity': 2,
              'unitPrice': 25000,
              'amount': 50000,
            },
          ],
        });

        await tester.pumpWidget(
          MaterialApp(
            home: AddTransactionScreen(
              walletsStream: Stream.value(testWallets),
              categoriesStream: Stream.value(testCategories),
              initialOcrReceiptForTest: ocrReceipt,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Ghi chú hiển thị đầy đủ Tên mặt hàng + SL + Đơn giá + Thành tiền (đã khôi phục "Đa" -> "Đá")
        expect(
          find.text('Cà Phê Sữa Đá Máy: 2 x 25.000₫ = 50.000₫'),
          findsOneWidget,
        );

        // Địa điểm kết hợp cả Tên cửa hàng và Địa chỉ
        expect(
          find.text(
            'Kang Tea & Coffee - Bạch Đằng - 20 Bạch Đằng, Phú Cường, Tp Thủ Dầu Một, Bình Dương',
          ),
          findsOneWidget,
        );

        // Hiển thị cảnh báo nhẹ để người dùng biết AI đã hỗ trợ khôi phục chữ mờ và có thể chỉnh sửa lại
        expect(
          find.textContaining('AI đã hỗ trợ khôi phục một số chữ mờ trên hóa đơn'),
          findsOneWidget,
        );
      },
    );
  });
}
