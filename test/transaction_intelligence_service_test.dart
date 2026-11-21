import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/receipt_info.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/services/transaction_intelligence_service.dart';

void main() {
  group('TransactionIntelligenceService Unit Tests', () {
    late TransactionIntelligenceService intelligenceService;
    late List<Category> testCategories;

    setUp(() {
      intelligenceService = TransactionIntelligenceService();
      testCategories = [
        Category(
          categoryId: 'cat_food',
          userId: 'user_1',
          name: 'Ăn uống',
          type: 'expense',
          icon: 'restaurant',
          color: 0xFFD32F2F,
        ),
        Category(
          categoryId: 'cat_transport',
          userId: 'user_1',
          name: 'Di chuyển',
          type: 'expense',
          icon: 'directions_car',
          color: 0xFF1976D2,
        ),
        Category(
          categoryId: 'cat_shopping',
          userId: 'user_1',
          name: 'Mua sắm',
          type: 'expense',
          icon: 'shopping_cart',
          color: 0xFF388E3C,
        ),
        Category(
          categoryId: 'cat_bills',
          userId: 'user_1',
          name: 'Hóa đơn',
          type: 'expense',
          icon: 'receipt',
          color: 0xFFF57C00,
        ),
        Category(
          categoryId: 'cat_salary',
          userId: 'user_1',
          name: 'Lương',
          type: 'income',
          icon: 'attach_money',
          color: 0xFF4CAF50,
        ),
      ];
    });

    // 1. Keyword gợi ý đúng category
    test('1. Keyword suggestion matches correct category (case & diacritics insensitive)', () {
      final suggestionFood = intelligenceService.suggestCategory(
        note: 'Cà phê Starbucks sáng nay',
        categories: testCategories,
        transactionType: 'expense',
      );
      expect(suggestionFood.categoryId, equals('cat_food'));
      expect(suggestionFood.confidence, equals(85));
      expect(suggestionFood.source, equals('keyword'));

      final suggestionTransport = intelligenceService.suggestCategory(
        note: 'Chuyến Grab bike sang công ty',
        categories: testCategories,
        transactionType: 'expense',
      );
      expect(suggestionTransport.categoryId, equals('cat_transport'));

      final suggestionBills = intelligenceService.suggestCategory(
        note: 'Tien dien thang nay',
        categories: testCategories,
        transactionType: 'expense',
      );
      expect(suggestionBills.categoryId, equals('cat_bills'));
    });

    // 2. Không gợi ý category sai loại income/expense
    test('2. Does not suggest category of wrong transaction type', () {
      final suggestionIncome = intelligenceService.suggestCategory(
        note: 'Highlands coffee', // Keyword 'coffee' is for food (expense)
        categories: testCategories,
        transactionType: 'income', // But transaction type is income!
      );
      // Food is expense, so it should not match income category
      expect(suggestionIncome.categoryId, isNot(equals('cat_food')));

      final suggestionSalary = intelligenceService.suggestCategory(
        note: 'Tien luong thang 9',
        categories: testCategories,
        transactionType: 'expense', // Type is expense, salary is income
      );
      expect(suggestionSalary.categoryId, isNot(equals('cat_salary')));
    });

    // 3. Lịch sử merchant tạo gợi ý đúng
    test('3. Merchant/note history generates correct category suggestion', () {
      final history = [
        AppTransaction(
          transactionId: 't1',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_shopping',
          amount: 50000,
          type: 'expense',
          note: 'Cửa hàng bách hóa An Bình',
          date: DateTime.now().subtract(const Duration(days: 10)),
        ),
        AppTransaction(
          transactionId: 't2',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_shopping',
          amount: 55000,
          type: 'expense',
          note: 'Cửa hàng bách hóa An Bình',
          date: DateTime.now().subtract(const Duration(days: 5)),
        ),
      ];

      final suggestion = intelligenceService.suggestCategory(
        note: 'Cửa hàng bách hóa An Bình',
        categories: testCategories,
        transactionType: 'expense',
        userHistory: history,
      );

      expect(suggestion.categoryId, equals('cat_shopping'));
      expect(suggestion.source, equals('history'));
      expect(suggestion.confidence, equals(80));
    });


    // 4. Confidence thấp không tự chọn category
    test('4. Low confidence note returns no suggestion (confidence 0 / source none)', () {
      final suggestion = intelligenceService.suggestCategory(
        note: 'XYZ123 random note không có trong từ khóa',
        categories: testCategories,
        transactionType: 'expense',
      );
      expect(suggestion.confidence, equals(0));
      expect(suggestion.source, equals('none'));
      expect(suggestion.categoryId, isEmpty);
    });

    // 5. Không anomaly khi ít hơn 5 giao dịch lịch sử
    test('5. No anomaly detected when history has fewer than 5 transactions', () {
      final now = DateTime.now();
      final smallHistory = List.generate(
        4,
        (i) => AppTransaction(
          transactionId: 't_$i',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 50000,
          type: 'expense',
          date: now.subtract(Duration(days: i + 1)),
        ),
      );

      final result = intelligenceService.detectAnomaly(
        amount: 500000, // Very large amount (10x)
        categoryId: 'cat_food',
        categoryName: 'Ăn uống',
        transactionType: 'expense',
        userHistory: smallHistory,
      );

      expect(result.isAnomalous, isFalse);
      expect(result.severity, equals('info'));
    });

    // 6. Warning khi giao dịch >= 2 lần median và chênh >= 100.000đ
    test('6. Warning severity when amount >= 2x median and difference >= 100,000 VND', () {
      final now = DateTime.now();
      // Median of [100k, 100k, 100k, 100k, 100k] is 100k
      final history = List.generate(
        5,
        (i) => AppTransaction(
          transactionId: 't_$i',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 100000,
          type: 'expense',
          date: now.subtract(Duration(days: i + 1)),
        ),
      );

      final result = intelligenceService.detectAnomaly(
        amount: 250000, // 2.5x median (250k - 100k = 150k >= 100k)
        categoryId: 'cat_food',
        categoryName: 'Ăn uống',
        transactionType: 'expense',
        userHistory: history,
      );

      expect(result.isAnomalous, isTrue);
      expect(result.severity, equals('warning'));
      expect(result.ratio, equals(2.5));
      expect(result.difference, equals(150000));
      expect(result.expectedAmount, equals(100000));
    });

    // 7. Critical khi giao dịch >= 4 lần median
    test('7. Critical severity when amount >= 4x median and difference >= 100,000 VND', () {
      final now = DateTime.now();
      final history = List.generate(
        5,
        (i) => AppTransaction(
          transactionId: 't_$i',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 100000,
          type: 'expense',
          date: now.subtract(Duration(days: i + 1)),
        ),
      );

      final result = intelligenceService.detectAnomaly(
        amount: 450000, // 4.5x median
        categoryId: 'cat_food',
        categoryName: 'Ăn uống',
        transactionType: 'expense',
        userHistory: history,
      );

      expect(result.isAnomalous, isTrue);
      expect(result.severity, equals('critical'));
      expect(result.ratio, equals(4.5));
    });

    // 8. Không anomaly khi chênh tiền nhỏ hơn 100.000đ
    test('8. No anomaly when difference is less than 100,000 VND (even if ratio >= 2x)', () {
      final now = DateTime.now();
      // Median of [20k, 20k, 20k, 20k, 20k] is 20k
      final history = List.generate(
        5,
        (i) => AppTransaction(
          transactionId: 't_$i',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 20000,
          type: 'expense',
          date: now.subtract(Duration(days: i + 1)),
        ),
      );

      final result = intelligenceService.detectAnomaly(
        amount: 60000, // 3x median! But difference is 60k - 20k = 40k < 100k
        categoryId: 'cat_food',
        categoryName: 'Ăn uống',
        transactionType: 'expense',
        userHistory: history,
      );

      expect(result.isAnomalous, isFalse);
    });

    // 9. Transfer và giao dịch mục tiêu không bị kiểm tra anomaly
    test('9. Non-expense transaction types are ignored for anomaly detection', () {
      final now = DateTime.now();
      final history = List.generate(
        5,
        (i) => AppTransaction(
          transactionId: 't_$i',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 100000,
          type: 'expense',
          date: now.subtract(Duration(days: i + 1)),
        ),
      );

      for (final type in ['income', 'transfer', 'goal_deposit', 'goal_withdraw']) {
        final result = intelligenceService.detectAnomaly(
          amount: 10000000, // Very high amount
          categoryId: 'cat_food',
          categoryName: 'Ăn uống',
          transactionType: type,
          userHistory: history,
        );

        expect(result.isAnomalous, isFalse, reason: 'Type $type should not trigger anomaly');
      }
    });

    // 10. Kết quả xác định với input cố định
    test('10. Deterministic output for fixed inputs', () {
      final now = DateTime(2026, 9, 21, 10, 0);
      final history = List.generate(
        5,
        (i) => AppTransaction(
          transactionId: 't_$i',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 100000.0 + (i * 10000), // 100k, 110k, 120k, 130k, 140k -> median 120k
          type: 'expense',
          date: now.subtract(Duration(days: i + 1)),
        ),
      );

      final result1 = intelligenceService.detectAnomaly(
        amount: 300000,
        categoryId: 'cat_food',
        categoryName: 'Ăn uống',
        transactionType: 'expense',
        userHistory: history,
        currentDate: now,
      );

      final result2 = intelligenceService.detectAnomaly(
        amount: 300000,
        categoryId: 'cat_food',
        categoryName: 'Ăn uống',
        transactionType: 'expense',
        userHistory: history,
        currentDate: now,
      );

      expect(result1.isAnomalous, equals(result2.isAnomalous));
      expect(result1.severity, equals(result2.severity));
      expect(result1.expectedAmount, equals(result2.expectedAmount));
      expect(result1.ratio, equals(result2.ratio));
      expect(result1.difference, equals(result2.difference));
      expect(result1.reason, equals(result2.reason));
      expect(result1.expectedAmount, equals(120000));
      expect(result1.ratio, equals(2.5));
    });

    // 11. Loại trừ giao dịch đang sửa (excludeTransactionId) khỏi mẫu median lịch sử
    test('11. Excludes transaction matching excludeTransactionId from anomaly history sample', () {
      final now = DateTime.now();
      final history = List.generate(
        5,
        (i) => AppTransaction(
          transactionId: i == 0 ? 'editing_tx_100' : 'tx_$i',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 100000,
          type: 'expense',
          date: now.subtract(Duration(days: i + 1)),
        ),
      );

      // Khi chưa loại trừ: có 5 mẫu -> báo anomaly
      final withSelf = intelligenceService.detectAnomaly(
        amount: 300000,
        categoryId: 'cat_food',
        categoryName: 'Ăn uống',
        transactionType: 'expense',
        userHistory: history,
      );
      expect(withSelf.isAnomalous, isTrue);

      // Khi loại trừ giao dịch đang sửa: còn 4 mẫu (< 5) -> không báo anomaly
      final withoutSelf = intelligenceService.detectAnomaly(
        amount: 300000,
        categoryId: 'cat_food',
        categoryName: 'Ăn uống',
        transactionType: 'expense',
        userHistory: history,
        excludeTransactionId: 'editing_tx_100',
      );
      expect(withoutSelf.isAnomalous, isFalse);
    });

    // 12. Gợi ý ví từ OCR hóa đơn tiền mặt (như hóa đơn Kang Tea & Coffee)
    test('12. Suggests cash wallet when receipt has cash payment or Tiền nhận/Tiền thừa', () {
      final wallets = [
        Wallet(
          walletId: 'w_cash',
          userId: 'user_1',
          walletName: 'Tiền mặt',
          balance: 500000,
          type: 'cash',
          createdAt: DateTime.now(),
        ),
        Wallet(
          walletId: 'w_mb',
          userId: 'user_1',
          walletName: 'MB Bank',
          balance: 2000000,
          type: 'bank',
          createdAt: DateTime.now(),
        ),
      ];

      final fromRawText = intelligenceService.suggestWallet(
        ocrRawText: '+Thanh toán tiền mặt 50,000 đ\nTiền nhận 50,000 đ\nTiền thừa 0 đ',
        wallets: wallets,
      );
      expect(fromRawText.isMatched, isTrue);
      expect(fromRawText.walletId, equals('w_cash'));
      expect(fromRawText.walletName, equals('Tiền mặt'));
      expect(fromRawText.confidence, equals(90));
    });

    // 13. Khi hóa đơn thanh toán qua loại ví mà người dùng không có -> isMatched = false, báo đúng tên ví
    test('13. Returns isMatched=false with detectedPaymentLabel when user does not have that wallet', () {
      final wallets = [
        Wallet(
          walletId: 'w_cash',
          userId: 'user_1',
          walletName: 'Tiền mặt',
          balance: 500000,
          type: 'cash',
          createdAt: DateTime.now(),
        ),
        Wallet(
          walletId: 'w_zalo',
          userId: 'user_1',
          walletName: 'ZaloPay',
          balance: 300000,
          type: 'eWallet',
          createdAt: DateTime.now(),
        ),
      ];

      // Hóa đơn thanh toán qua MoMo nhưng user chỉ có Tiền mặt và ZaloPay
      final momoSuggestion = intelligenceService.suggestWallet(
        paymentMethod: 'MoMo',
        wallets: wallets,
      );
      expect(momoSuggestion.hasDetection, isTrue);
      expect(momoSuggestion.isMatched, isFalse);
      expect(momoSuggestion.walletId, isEmpty);
      expect(momoSuggestion.detectedPaymentLabel, equals('MoMo'));

      // Hóa đơn thanh toán qua Vietcombank nhưng user không có ví Vietcombank
      final vcbSuggestion = intelligenceService.suggestWallet(
        paymentMethod: 'Vietcombank',
        wallets: wallets,
      );
      expect(vcbSuggestion.hasDetection, isTrue);
      expect(vcbSuggestion.isMatched, isFalse);
      expect(vcbSuggestion.walletId, isEmpty);
      expect(vcbSuggestion.detectedPaymentLabel, equals('Vietcombank'));
    });

    // 14. Không khớp nhầm chữ "mb" trong "Combo" thành MB Bank
    test('14. Word boundary prevents matching "Combo" as "MB Bank"', () {
      final wallets = [
        Wallet(
          walletId: 'w_mb',
          userId: 'user_1',
          walletName: 'MB Bank',
          balance: 2000000,
          type: 'bank',
          createdAt: DateTime.now(),
        ),
      ];

      final res = intelligenceService.suggestWallet(
        ocrRawText: 'Combo 1 Gà Rán: 89,000 đ',
        wallets: wallets,
      );
      expect(res.hasDetection, isFalse);
    });

    // 15. ReceiptInfo.fromJson parse linh hoạt ngày dd/MM/yyyy và paymentMethod
    test('15. ReceiptInfo.fromJson parses dd/MM/yyyy date and paymentMethod safely', () {
      final info = ReceiptInfo.fromJson({
        'merchant': 'Kang Tea & Coffee - Bạch Đằng',
        'total': '50.000',
        'date': '13/11/2026',
        'paymentMethod': 'Tiền mặt',
      }, rawText: '+Thanh toán tiền mặt 50,000 đ');

      expect(info.merchant, equals('Kang Tea & Coffee - Bạch Đằng'));
      expect(info.total, equals(50000));
      expect(info.date, equals(DateTime(2026, 11, 13)));
      expect(info.paymentMethod, equals('Tiền mặt'));
      expect(info.rawText, contains('Thanh toán tiền mặt'));
    });

    // 16. Định dạng ghi chú linh hoạt theo 4 thành phần (Tên mặt hàng, SL, Đơn giá, Thành tiền)
    test('16. ReceiptItem & ReceiptInfo format notes flexibly without fabricating missing fields', () {
      // Trường hợp 1: Có đủ Tên món, SL, Đơn giá, Thành tiền (như hóa đơn Kang Tea & Coffee)
      final fullItem = ReceiptItem.fromJson({
        'description': 'Cà Phê Sữa Đá\nMáy',
        'quantity': 2,
        'unitPrice': 25000,
        'amount': 50000,
      });
      expect(fullItem.description, equals('Cà Phê Sữa Đá Máy'));
      expect(fullItem.quantity, equals(2));
      expect(fullItem.unitPrice, equals(25000));
      expect(fullItem.amount, equals(50000));
      expect(fullItem.isPriceConsistent, isTrue);
      expect(
        fullItem.formatNoteLine(),
        equals('Cà Phê Sữa Đá Máy: 2 x 25.000₫ = 50.000₫'),
      );

      // Trường hợp 2: Chỉ có Tên món, SL và Thành tiền (không có Đơn giá)
      final qtyAndTotalItem = ReceiptItem.fromJson({
        'description': 'Cà Phê Sữa Đá Máy',
        'quantity': 2,
        'amount': 50000,
      });
      expect(qtyAndTotalItem.unitPrice, isNull);
      expect(
        qtyAndTotalItem.formatNoteLine(),
        equals('Cà Phê Sữa Đá Máy (SL: 2, tổng: 50.000₫)'),
      );

      // Trường hợp 3: Chỉ có Tên món và Thành tiền (không có SL, không có Đơn giá -> không tự suy diễn)
      final nameAndTotalOnly = ReceiptItem.fromJson({
        'description': 'Bánh ngọt',
        'amount': 35000,
      });
      expect(nameAndTotalOnly.quantity, isNull);
      expect(nameAndTotalOnly.unitPrice, isNull);
      expect(
        nameAndTotalOnly.formatNoteLine(),
        equals('Bánh ngọt: 35.000₫'),
      );
    });

    // 17. Khôi phục ngữ cảnh khi chữ bị mờ (Cà Phê Sữa Đa Máy -> Cà Phê Sữa Đá Máy) và phân biệt dữ liệu suy luận
    test('17. Contextual restoration of blurry item names and location with inference tracking', () {
      final info = ReceiptInfo.fromJson({
        'merchant': 'Kang Tea & Coffee - Bach Dang',
        'total': 50000,
        'date': '2026-11-13',
        'address': 'Địa chỉ: 20 Bach Dang, Phu Cuong, Tp Thu Dau Mot, Binh Duong',
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

      // Đã khôi phục "Cà Phê Sữa Đa Máy" -> "Cà Phê Sữa Đá Máy" và đánh dấu isInferred
      expect(info.items, isNotNull);
      expect(info.items!.first.description, equals('Cà Phê Sữa Đá Máy'));
      expect(info.items!.first.isInferred, isTrue);

      // Đã khôi phục dấu địa điểm và kết hợp Tên cửa hàng + Địa chỉ hợp lý
      expect(info.merchant, equals('Kang Tea & Coffee - Bạch Đằng'));
      expect(
        info.address,
        equals('20 Bạch Đằng, Phú Cường, Tp Thủ Dầu Một, Bình Dương'),
      );
      expect(
        info.resolvedLocation,
        equals(
          'Kang Tea & Coffee - Bạch Đằng - 20 Bạch Đằng, Phú Cường, Tp Thủ Dầu Một, Bình Dương',
        ),
      );
      expect(info.isLocationInferred, isTrue);
      expect(info.hasInferredData, isTrue);
      expect(info.inferredFields, isNotEmpty);
      expect(
        info.buildFormattedNote(),
        equals('Cà Phê Sữa Đá Máy: 2 x 25.000₫ = 50.000₫'),
      );
    });
  });
}

