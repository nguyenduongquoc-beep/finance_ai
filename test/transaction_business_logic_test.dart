import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/models/saving_goal_model.dart';
import 'package:finance_ai_app/utils/formatters.dart';
import 'package:finance_ai_app/utils/transaction_business_logic.dart';

void main() {
  group('TransactionBusinessLogic Tests', () {
    late Wallet sourceWallet;
    late Wallet targetWallet;
    late Wallet inactiveWallet;
    late SavingGoal goal;

    setUp(() {
      sourceWallet = Wallet(
        walletId: 'w_source',
        userId: 'u_1',
        walletName: 'Ví Tiền Mặt',
        type: 'cash',
        balance: 500000.0,
        createdAt: DateTime.now(),
        isActive: true,
      );

      targetWallet = Wallet(
        walletId: 'w_target',
        userId: 'u_1',
        walletName: 'Ví Ngân Hàng',
        type: 'bank',
        balance: 200000.0,
        createdAt: DateTime.now(),
        isActive: true,
      );

      inactiveWallet = Wallet(
        walletId: 'w_inactive',
        userId: 'u_1',
        walletName: 'Ví Đã Ẩn',
        type: 'cash',
        balance: 100000.0,
        createdAt: DateTime.now(),
        isActive: false,
      );

      goal = SavingGoal(
        goalId: 'g_laptop',
        userId: 'u_1',
        name: 'Mua Laptop',
        targetAmount: 1000000.0,
        savedAmount: 800000.0, // Còn thiếu 200,000đ
        months: 6,
        createdAt: DateTime.now(),
      );
    });

    test('1. Nạp mục tiêu bằng đúng số tiền còn thiếu: thành công', () {
      final tx = AppTransaction(
        transactionId: 'tx_1',
        userId: 'u_1',
        walletId: 'w_source',
        categoryId: '',
        amount: 200000.0, // Đúng 200,000đ còn thiếu
        type: 'goal_deposit',
        goalId: 'g_laptop',
        date: DateTime.now(),
      );

      final effects = TransactionBusinessLogic.processCreateTransaction(
        tx: tx,
        wallet: sourceWallet,
        goal: goal,
      );

      expect(effects.newSourceBalance, equals(300000.0)); // 500,000 - 200,000
      expect(effects.newGoalSavedAmount,
          equals(1000000.0)); // 800,000 + 200,000 = 1,000,000
    });

    test('2. Nạp vượt số tiền còn thiếu: thất bại, không trừ ví', () {
      final tx = AppTransaction(
        transactionId: 'tx_2',
        userId: 'u_1',
        walletId: 'w_source',
        categoryId: '',
        amount: 300000.0, // Vượt 200,000đ còn thiếu
        type: 'goal_deposit',
        goalId: 'g_laptop',
        date: DateTime.now(),
      );

      expect(
        () => TransactionBusinessLogic.processCreateTransaction(
          tx: tx,
          wallet: sourceWallet,
          goal: goal,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Số tiền nạp vượt quá số tiền còn thiếu'),
          ),
        ),
      );
    });

    test('3. Chi tiêu vượt số dư ví: thất bại', () {
      final tx = AppTransaction(
        transactionId: 'tx_3',
        userId: 'u_1',
        walletId: 'w_source',
        categoryId: 'cat_food',
        amount: 600000.0, // Vượt số dư 500,000đ
        type: 'expense',
        date: DateTime.now(),
      );

      expect(
        () => TransactionBusinessLogic.processCreateTransaction(
          tx: tx,
          wallet: sourceWallet,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Số dư ví không đủ để thực hiện giao dịch này'),
          ),
        ),
      );
    });

    test('4. Chuyển tiền vượt số dư ví hoặc ví trùng nhau: thất bại', () {
      final txExceed = AppTransaction(
        transactionId: 'tx_4a',
        userId: 'u_1',
        walletId: 'w_source',
        toWalletId: 'w_target',
        categoryId: '',
        amount: 600000.0, // Vượt số dư
        type: 'transfer',
        date: DateTime.now(),
      );

      expect(
        () => TransactionBusinessLogic.processCreateTransaction(
          tx: txExceed,
          wallet: sourceWallet,
          toWallet: targetWallet,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Số dư ví không đủ để thực hiện giao dịch này'),
          ),
        ),
      );

      final txSameWallet = AppTransaction(
        transactionId: 'tx_4b',
        userId: 'u_1',
        walletId: 'w_source',
        toWalletId: 'w_source',
        categoryId: '',
        amount: 100000.0,
        type: 'transfer',
        date: DateTime.now(),
      );

      expect(
        () => TransactionBusinessLogic.processCreateTransaction(
          tx: txSameWallet,
          wallet: sourceWallet,
          toWallet: sourceWallet,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Ví nguồn và ví đích không được trùng nhau'),
          ),
        ),
      );
    });

    test('5. Validate số tiền amount <= 0, NaN, Infinity: thất bại', () {
      expect(
        () => TransactionBusinessLogic.validateAmount(0),
        throwsA(isA<Exception>()),
      );
      expect(
        () => TransactionBusinessLogic.validateAmount(-50000),
        throwsA(isA<Exception>()),
      );
      expect(
        () => TransactionBusinessLogic.validateAmount(double.nan),
        throwsA(isA<Exception>()),
      );
      expect(
        () => TransactionBusinessLogic.validateAmount(double.infinity),
        throwsA(isA<Exception>()),
      );
    });

    test('6. Xóa giao dịch chi (kể cả khi ví bị ẩn): hoàn tiền chính xác về ví',
        () {
      final txExpense = AppTransaction(
        transactionId: 'tx_5',
        userId: 'u_1',
        walletId: 'w_inactive', // Ví đang bị ẩn
        categoryId: 'cat_food',
        amount: 150000.0,
        type: 'expense',
        date: DateTime.now(),
      );

      final effects = TransactionBusinessLogic.processDeleteTransaction(
        tx: txExpense,
        wallet: inactiveWallet,
      );

      expect(effects.newSourceBalance,
          equals(250000.0)); // 100,000 + 150,000 = 250,000
    });

    test('7. Xóa giao dịch chuyển tiền: hoàn lại ví nguồn và trừ ví đích', () {
      final txTransfer = AppTransaction(
        transactionId: 'tx_6',
        userId: 'u_1',
        walletId: 'w_source',
        toWalletId: 'w_target',
        categoryId: '',
        amount: 100000.0,
        type: 'transfer',
        date: DateTime.now(),
      );

      final effects = TransactionBusinessLogic.processDeleteTransaction(
        tx: txTransfer,
        wallet: sourceWallet,
        toWallet: targetWallet,
      );

      expect(effects.newSourceBalance, equals(600000.0)); // 500,000 + 100,000
      expect(effects.newTargetBalance, equals(100000.0)); // 200,000 - 100,000
    });

    test('8. Xóa nạp/rút mục tiêu: ví và savedAmount được hoàn tác chính xác',
        () {
      final txDeposit = AppTransaction(
        transactionId: 'tx_7a',
        userId: 'u_1',
        walletId: 'w_source',
        categoryId: '',
        amount: 200000.0,
        type: 'goal_deposit',
        goalId: 'g_laptop',
        date: DateTime.now(),
      );

      final effectsDep = TransactionBusinessLogic.processDeleteTransaction(
        tx: txDeposit,
        wallet: sourceWallet,
        goal: goal,
      );

      expect(
          effectsDep.newSourceBalance, equals(700000.0)); // 500,000 + 200,000
      expect(
          effectsDep.newGoalSavedAmount, equals(600000.0)); // 800,000 - 200,000

      final txWithdraw = AppTransaction(
        transactionId: 'tx_7b',
        userId: 'u_1',
        walletId: 'w_source',
        categoryId: '',
        amount: 100000.0,
        type: 'goal_withdraw',
        goalId: 'g_laptop',
        date: DateTime.now(),
      );

      final effectsWith = TransactionBusinessLogic.processDeleteTransaction(
        tx: txWithdraw,
        wallet: sourceWallet,
        goal: goal,
      );

      expect(
          effectsWith.newSourceBalance, equals(400000.0)); // 500,000 - 100,000
      expect(effectsWith.newGoalSavedAmount,
          equals(900000.0)); // 800,000 + 100,000
    });

    test('9. Khóa sửa giao dịch nạp/rút mục tiêu', () {
      final oldTx = AppTransaction(
        transactionId: 'tx_8',
        userId: 'u_1',
        walletId: 'w_source',
        categoryId: '',
        amount: 100000.0,
        type: 'goal_deposit',
        goalId: 'g_laptop',
        date: DateTime.now(),
      );

      final newTx = AppTransaction(
        transactionId: 'tx_8',
        userId: 'u_1',
        walletId: 'w_source',
        categoryId: '',
        amount: 150000.0,
        type: 'goal_deposit',
        goalId: 'g_laptop',
        date: DateTime.now(),
      );

      expect(
        () => TransactionBusinessLogic.processUpdateTransaction(
          oldTx: oldTx,
          newTx: newTx,
          oldWallet: sourceWallet,
          newWallet: sourceWallet,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Giao dịch nạp/rút mục tiêu không thể sửa'),
          ),
        ),
      );
    });

    test(
        '10. Nạp mục tiêu từ nhiều ví (Tiền mặt 10tr, MB Bank 2tr) và rút theo đúng nguồn ví',
        () {
      var cashWallet = Wallet(
        walletId: 'w_cash',
        userId: 'u_1',
        walletName: 'Tiền mặt',
        type: 'cash',
        balance: 20000000.0,
        createdAt: DateTime.now(),
        isActive: true,
      );
      var mbWallet = Wallet(
        walletId: 'w_mb',
        userId: 'u_1',
        walletName: 'MB Bank',
        type: 'bank',
        balance: 10000000.0,
        createdAt: DateTime.now(),
        isActive: true,
      );
      final zaloWallet = Wallet(
        walletId: 'w_zalo',
        userId: 'u_1',
        walletName: 'ZaloPay',
        type: 'ewallet',
        balance: 500000.0,
        createdAt: DateTime.now(),
        isActive: true,
      );

      var laptopGoal = SavingGoal(
        goalId: 'g_laptop_new',
        userId: 'u_1',
        name: 'Laptop',
        targetAmount: 30000000.0,
        savedAmount: 0.0,
        months: 12,
        createdAt: DateTime.now(),
        sourcesSynced: true,
      );

      // Lần 1: Nạp 10.000.000 từ ví Tiền mặt
      final depCash = AppTransaction(
        transactionId: 'dep_cash_1',
        userId: 'u_1',
        walletId: 'w_cash',
        categoryId: '',
        amount: 10000000.0,
        type: 'goal_deposit',
        goalId: 'g_laptop_new',
        date: DateTime(2026, 11, 10),
      );
      final eff1 = TransactionBusinessLogic.processCreateTransaction(
        tx: depCash,
        wallet: cashWallet,
        goal: laptopGoal,
      );
      cashWallet = Wallet(
        walletId: cashWallet.walletId,
        userId: cashWallet.userId,
        walletName: cashWallet.walletName,
        type: cashWallet.type,
        balance: eff1.newSourceBalance!,
        createdAt: cashWallet.createdAt,
      );
      laptopGoal = TransactionBusinessLogic.applyEffectsToGoal(laptopGoal, eff1);

      // Lần 2: Nạp 2.000.000 từ ví MB Bank
      final depMb = AppTransaction(
        transactionId: 'dep_mb_1',
        userId: 'u_1',
        walletId: 'w_mb',
        categoryId: '',
        amount: 2000000.0,
        type: 'goal_deposit',
        goalId: 'g_laptop_new',
        date: DateTime(2026, 11, 11),
      );
      final eff2 = TransactionBusinessLogic.processCreateTransaction(
        tx: depMb,
        wallet: mbWallet,
        goal: laptopGoal,
      );
      mbWallet = Wallet(
        walletId: mbWallet.walletId,
        userId: mbWallet.userId,
        walletName: mbWallet.walletName,
        type: mbWallet.type,
        balance: eff2.newSourceBalance!,
        createdAt: mbWallet.createdAt,
      );
      laptopGoal = TransactionBusinessLogic.applyEffectsToGoal(laptopGoal, eff2);

      expect(laptopGoal.savedAmount, equals(12000000.0));
      expect(laptopGoal.withdrawableForWallet('w_cash'), equals(10000000.0));
      expect(laptopGoal.withdrawableForWallet('w_mb'), equals(2000000.0));

      // Thử rút về ví ZaloPay (chưa từng nạp): phải bị chặn
      final withdrawZalo = AppTransaction(
        transactionId: 'with_zalo',
        userId: 'u_1',
        walletId: 'w_zalo',
        categoryId: '',
        amount: 1000000.0,
        type: 'goal_withdraw',
        goalId: 'g_laptop_new',
        date: DateTime(2026, 11, 12),
      );
      expect(
        () => TransactionBusinessLogic.processCreateTransaction(
          tx: withdrawZalo,
          wallet: zaloWallet,
          goal: laptopGoal,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('chưa từng nạp tiền vào mục tiêu tiết kiệm này'),
          ),
        ),
      );

      // Thử rút 3.000.000 từ MB Bank (vượt quá 2.000.000 đã nạp từ MB Bank): phải bị chặn
      final withdrawMbExceed = AppTransaction(
        transactionId: 'with_mb_exceed',
        userId: 'u_1',
        walletId: 'w_mb',
        categoryId: '',
        amount: 3000000.0,
        type: 'goal_withdraw',
        goalId: 'g_laptop_new',
        date: DateTime(2026, 11, 12),
      );
      expect(
        () => TransactionBusinessLogic.processCreateTransaction(
          tx: withdrawMbExceed,
          wallet: mbWallet,
          goal: laptopGoal,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Số tiền rút vượt quá số tiền có thể rút từ ví "MB Bank"'),
          ),
        ),
      );

      // Rút hợp lệ 5.000.000 từ nguồn ví Tiền mặt -> hoàn về đúng ví Tiền mặt
      final withdrawCash5m = AppTransaction(
        transactionId: 'with_cash_5m',
        userId: 'u_1',
        walletId: 'w_cash',
        categoryId: '',
        amount: 5000000.0,
        type: 'goal_withdraw',
        goalId: 'g_laptop_new',
        date: DateTime(2026, 11, 13),
      );
      final eff3 = TransactionBusinessLogic.processCreateTransaction(
        tx: withdrawCash5m,
        wallet: cashWallet,
        goal: laptopGoal,
      );
      expect(eff3.newSourceBalance, equals(15000000.0)); // 10tr + 5tr hoàn về
      laptopGoal = TransactionBusinessLogic.applyEffectsToGoal(laptopGoal, eff3);

      expect(laptopGoal.savedAmount, equals(7000000.0));
      expect(laptopGoal.totalDepositedForWallet('w_cash'), equals(10000000.0));
      expect(laptopGoal.withdrawableForWallet('w_cash'), equals(5000000.0));
      expect(laptopGoal.totalDepositedForWallet('w_mb'), equals(2000000.0));
      expect(laptopGoal.withdrawableForWallet('w_mb'), equals(2000000.0));

      // Rút nốt 2.000.000 từ MB Bank -> MB Bank về 0 có thể rút và không thể rút thêm
      final withdrawMbAll = AppTransaction(
        transactionId: 'with_mb_all',
        userId: 'u_1',
        walletId: 'w_mb',
        categoryId: '',
        amount: 2000000.0,
        type: 'goal_withdraw',
        goalId: 'g_laptop_new',
        date: DateTime(2026, 11, 14),
      );
      final eff4 = TransactionBusinessLogic.processCreateTransaction(
        tx: withdrawMbAll,
        wallet: mbWallet,
        goal: laptopGoal,
      );
      expect(eff4.newSourceBalance, equals(10000000.0));
      laptopGoal = TransactionBusinessLogic.applyEffectsToGoal(laptopGoal, eff4);
      expect(laptopGoal.withdrawableForWallet('w_mb'), equals(0.0));
      expect(
        laptopGoal.withdrawableSources.map((s) => s.walletId).toList(),
        equals(['w_cash']),
      );

      // Thử rút thêm từ MB Bank sau khi đã rút hết -> bị chặn
      expect(
        () => TransactionBusinessLogic.processCreateTransaction(
          tx: AppTransaction(
            transactionId: 'with_mb_again',
            userId: 'u_1',
            walletId: 'w_mb',
            categoryId: '',
            amount: 100000.0,
            type: 'goal_withdraw',
            goalId: 'g_laptop_new',
            date: DateTime(2026, 11, 14),
          ),
          wallet: mbWallet,
          goal: laptopGoal,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Nguồn tiền từ ví "MB Bank" trong mục tiêu này đã được rút hết'),
          ),
        ),
      );
    });

    test(
        '11. Khôi phục nguồn ví từ lịch sử giao dịch cho mục tiêu tiết kiệm cũ (reconstructGoalSources)',
        () {
      final legacyGoal = SavingGoal(
        goalId: 'g_legacy',
        userId: 'u_1',
        name: 'Laptop',
        targetAmount: 30000000.0,
        savedAmount: 12000000.0,
        months: 12,
        createdAt: DateTime(2026, 10, 1),
      );
      expect(legacyGoal.needsSourceSync, isTrue);

      final history = [
        AppTransaction(
          transactionId: 'h_1',
          userId: 'u_1',
          walletId: 'w_cash',
          categoryId: '',
          amount: 10000000.0,
          type: 'goal_deposit',
          goalId: 'g_legacy',
          date: DateTime(2026, 10, 5),
        ),
        AppTransaction(
          transactionId: 'h_2',
          userId: 'u_1',
          walletId: 'w_mb',
          categoryId: '',
          amount: 2000000.0,
          type: 'goal_deposit',
          goalId: 'g_legacy',
          date: DateTime(2026, 10, 10),
        ),
      ];

      final synced = TransactionBusinessLogic.reconstructGoalSources(
        goal: legacyGoal,
        goalTransactions: history,
        walletNamesById: {
          'w_cash': 'Tiền mặt',
          'w_mb': 'MB Bank',
        },
      );

      expect(synced.needsSourceSync, isFalse);
      expect(synced.withdrawableForWallet('w_cash'), equals(10000000.0));
      expect(synced.withdrawableForWallet('w_mb'), equals(2000000.0));
      expect(synced.unattributedSavedAmount, equals(0.0));
    });
  });

  group('CurrencyInputFormatter & AppFormatters Tests', () {
    const formatter = CurrencyInputFormatter();

    test('Định dạng chuẩn dấu chấm phân cách hàng nghìn cho mọi mệnh giá', () {
      expect(AppFormatters.formatDigitsWithDots('5000'), equals('5.000'));
      expect(AppFormatters.formatDigitsWithDots('25000'), equals('25.000'));
      expect(AppFormatters.formatDigitsWithDots('350000'), equals('350.000'));
      expect(AppFormatters.formatDigitsWithDots('1200000'), equals('1.200.000'));
      expect(
          AppFormatters.formatDigitsWithDots('30000000'), equals('30.000.000'));
      expect(AppFormatters.formatDigitsWithDots('555855588'),
          equals('555.855.588'));
    });

    test('Định dạng trực tiếp khi nhập từng chữ số 1000000 -> 1.000.000', () {
      var value = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
      for (final ch in '1000000'.split('')) {
        final nextText = value.text + ch;
        final nextValue = TextEditingValue(
          text: nextText,
          selection: TextSelection.collapsed(offset: nextText.length),
        );
        value = formatter.formatEditUpdate(value, nextValue);
      }
      expect(value.text, equals('1.000.000'));
      expect(value.selection.baseOffset, equals('1.000.000'.length));
    });

    test('Xử lý xóa dấu chấm (Backspace) và giữ đúng vị trí con trỏ ở giữa số',
        () {
      // Giả sử đang có '1.000.000', con trỏ đặt ngay sau dấu chấm đầu tiên (offset 2)
      // và người dùng nhấn Backspace làm mất dấu chấm -> '1000.000' (offset 1)
      const oldVal = TextEditingValue(
        text: '1.000.000',
        selection: TextSelection.collapsed(offset: 2),
      );
      const afterBackspaceDot = TextEditingValue(
        text: '1000.000',
        selection: TextSelection.collapsed(offset: 1),
      );
      final updated = formatter.formatEditUpdate(oldVal, afterBackspaceDot);
      // Chữ số '1' bị xóa, còn '000000' -> chuẩn hóa thành '0'
      expect(updated.text, equals('0'));

      // Thêm chữ số ở giữa chuỗi: '1.200.000' -> chèn '5' sau '1.2' -> '1.2500.000'
      const oldMid = TextEditingValue(
        text: '1.200.000',
        selection: TextSelection.collapsed(offset: 3),
      );
      const newMid = TextEditingValue(
        text: '1.2500.000',
        selection: TextSelection.collapsed(offset: 4),
      );
      final formattedMid = formatter.formatEditUpdate(oldMid, newMid);
      expect(formattedMid.text, equals('12.500.000'));
      // Sau 3 chữ số '1', '2', '5' -> vị trí con trỏ phải nằm ngay sau '12.5' (offset 4)
      expect(formattedMid.selection.baseOffset, equals(4));
    });

    test('AppFormatters.parseCurrencyInput loại bỏ dấu chấm để lưu số thuần',
        () {
      expect(AppFormatters.parseCurrencyInput('1.000.000'), equals(1000000.0));
      expect(
          AppFormatters.parseCurrencyInput('555.855.588 ₫'), equals(555855588.0));
      expect(
          AppFormatters.parseCurrencyInput('855.668.888 VNĐ'), equals(855668888.0));
      expect(AppFormatters.parseCurrencyInput(''), equals(0.0));
    });
  });
}
