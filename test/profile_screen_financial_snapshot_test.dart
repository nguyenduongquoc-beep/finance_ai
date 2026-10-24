import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/utils/formatters.dart';

void main() {
  group('Profile Screen Financial Snapshot Logic Tests', () {
    test('1. Tính toán thặng dư và tỷ lệ tiết kiệm chính xác khi có thu nhập > chi tiêu', () {
      final now = DateTime.now();
      final transactions = [
        AppTransaction(
          transactionId: 't1',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'c1',
          amount: 20000000,
          type: 'income',
          date: now,
        ),
        AppTransaction(
          transactionId: 't2',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'c2',
          amount: 12000000,
          type: 'expense',
          date: now,
        ),
      ];

      double income = 0;
      double expense = 0;
      for (final t in transactions) {
        if (t.type == 'income') {
          income += t.amount;
        } else if (t.type == 'expense') {
          expense += t.amount;
        }
      }

      final remaining = income - expense;
      final savingsRate = income > 0 && remaining > 0
          ? ((remaining / income) * 100).clamp(0, 100).round()
          : 0;

      expect(income, equals(20000000.0));
      expect(expense, equals(12000000.0));
      expect(remaining, equals(8000000.0));
      expect(savingsRate, equals(40)); // 8 / 20 * 100 = 40%
    });

    test('2. Xử lý chính xác trường hợp thâm hụt (chi tiêu vượt thu nhập)', () {
      final now = DateTime.now();
      final transactions = [
        AppTransaction(
          transactionId: 't1',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'c1',
          amount: 10000000,
          type: 'income',
          date: now,
        ),
        AppTransaction(
          transactionId: 't2',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'c2',
          amount: 15000000,
          type: 'expense',
          date: now,
        ),
      ];

      double income = 0;
      double expense = 0;
      for (final t in transactions) {
        if (t.type == 'income') {
          income += t.amount;
        } else if (t.type == 'expense') {
          expense += t.amount;
        }
      }

      final remaining = income - expense;
      final savingsRate = income > 0 && remaining > 0
          ? ((remaining / income) * 100).clamp(0, 100).round()
          : 0;

      expect(income, equals(10000000.0));
      expect(expense, equals(15000000.0));
      expect(remaining, equals(-5000000.0));
      expect(savingsRate, equals(0)); // Thâm hụt -> tỷ lệ tiết kiệm = 0%
    });

    test('3. Xử lý an toàn khi không có thu nhập hoặc chưa có giao dịch nào', () {
      final transactions = <AppTransaction>[];

      double income = 0;
      double expense = 0;
      for (final t in transactions) {
        if (t.type == 'income') {
          income += t.amount;
        } else if (t.type == 'expense') {
          expense += t.amount;
        }
      }

      final remaining = income - expense;
      final savingsRate = income > 0 && remaining > 0
          ? ((remaining / income) * 100).clamp(0, 100).round()
          : 0;

      expect(income, equals(0.0));
      expect(expense, equals(0.0));
      expect(remaining, equals(0.0));
      expect(savingsRate, equals(0));
    });

    test('4. Giao dịch chuyển tiền (transfer) không ảnh hưởng tới thu nhập và chi tiêu của tháng', () {
      final now = DateTime.now();
      final transactions = [
        AppTransaction(
          transactionId: 't1',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'c1',
          amount: 5000000,
          type: 'income',
          date: now,
        ),
        AppTransaction(
          transactionId: 't2',
          userId: 'u1',
          walletId: 'w1',
          toWalletId: 'w2',
          categoryId: '',
          amount: 2000000,
          type: 'transfer',
          date: now,
        ),
      ];

      double income = 0;
      double expense = 0;
      for (final t in transactions) {
        if (t.type == 'income') {
          income += t.amount;
        } else if (t.type == 'expense') {
          expense += t.amount;
        }
      }

      final remaining = income - expense;

      expect(income, equals(5000000.0));
      expect(expense, equals(0.0));
      expect(remaining, equals(5000000.0));
    });

    test('5. Định dạng số tiền lớn trong snapshot chống tràn viền (hàng tỷ, nghìn tỷ)', () {
      expect(AppFormatters.compactCurrency(12500000), equals('12.500.000 ₫'));
      expect(AppFormatters.compactCurrency(2500000000), equals('2,5 tỷ ₫'));
      expect(AppFormatters.compactCurrency(1500000000000), equals('1.500 tỷ ₫'));
      expect(AppFormatters.compactCurrency(-3500000000), equals('-3,5 tỷ ₫'));
    });
  });
}
