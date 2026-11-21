import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/screens/home/transaction_list_screen.dart';

void main() {
  group('TransactionSearchFilterHelper Tests', () {
    late AppTransaction txCoffee;
    late AppTransaction txSalary;
    late AppTransaction txTransfer;
    late AppTransaction txShopping;
    late Category catCoffee;
    late Category catSalary;
    late Wallet walletCash;
    late Wallet walletBank;

    final fixedDate = DateTime(2026, 10, 11, 14, 0);

    setUp(() {
      txCoffee = AppTransaction(
        transactionId: 'tx_1',
        userId: 'u_1',
        walletId: 'w_cash',
        categoryId: 'c_coffee',
        amount: 45000.0,
        type: 'expense',
        date: fixedDate,
        note: 'Cà phê sáng cùng bạn bè Highland Coffee',
      );

      txSalary = AppTransaction(
        transactionId: 'tx_2',
        userId: 'u_1',
        walletId: 'w_bank',
        categoryId: 'c_salary',
        amount: 15000000.0,
        type: 'income',
        date: fixedDate.subtract(const Duration(days: 1)), // Hôm qua
        note: 'Nhận lương tháng 10 công ty chuyển khoản',
      );

      txTransfer = AppTransaction(
        transactionId: 'tx_3',
        userId: 'u_1',
        walletId: 'w_bank',
        toWalletId: 'w_cash',
        categoryId: '',
        amount: 500000.0,
        type: 'transfer',
        date: fixedDate.subtract(const Duration(days: 3)),
        note: 'Rút tiền ATM tiêu vặt',
      );

      txShopping = AppTransaction(
        transactionId: 'tx_4',
        userId: 'u_1',
        walletId: 'w_bank',
        categoryId: 'c_shopping',
        amount: 250000.0,
        type: 'expense',
        date: DateTime(2026, 9, 20),
        note: 'Mua sắm áo thun Shopee',
      );

      catCoffee = Category(
        categoryId: 'c_coffee',
        userId: 'u_1',
        name: 'Ăn uống & Cà phê',
        type: 'expense',
        icon: 'local_cafe',
        color: 0xFFFF9800,
      );

      catSalary = Category(
        categoryId: 'c_salary',
        userId: 'u_1',
        name: 'Tiền lương',
        type: 'income',
        icon: 'payments',
        color: 0xFF4CAF50,
      );

      walletCash = Wallet(
        walletId: 'w_cash',
        userId: 'u_1',
        walletName: 'Ví Tiền Mặt',
        type: 'cash',
        balance: 200000.0,
        createdAt: DateTime.now(),
      );

      walletBank = Wallet(
        walletId: 'w_bank',
        userId: 'u_1',
        walletName: 'Ngân Hàng MB',
        type: 'bank',
        balance: 10000000.0,
        createdAt: DateTime.now(),
      );
    });

    test('1. Tìm kiếm theo ghi chú có dấu và không dấu', () {
      // Có dấu
      expect(
        TransactionSearchFilterHelper.matchesSearch(txCoffee, catCoffee, walletCash, null, 'Cà phê'),
        isTrue,
      );
      // Không dấu
      expect(
        TransactionSearchFilterHelper.matchesSearch(txCoffee, catCoffee, walletCash, null, 'ca phe'),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(txCoffee, catCoffee, walletCash, null, 'highland'),
        isTrue,
      );
      // Không khớp
      expect(
        TransactionSearchFilterHelper.matchesSearch(txCoffee, catCoffee, walletCash, null, 'xăng xe'),
        isFalse,
      );
    });

    test('2. Tìm kiếm theo danh mục', () {
      expect(
        TransactionSearchFilterHelper.matchesSearch(txSalary, catSalary, walletBank, null, 'Tiền lương'),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(txSalary, catSalary, walletBank, null, 'luong'),
        isTrue,
      );
    });

    test('3. Tìm kiếm theo tên ví nguồn và ví đích', () {
      expect(
        TransactionSearchFilterHelper.matchesSearch(txCoffee, catCoffee, walletCash, null, 'Tien Mat'),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(txTransfer, null, walletBank, walletCash, 'MB'),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(txTransfer, null, walletBank, walletCash, 'tien mat'),
        isTrue,
      );
    });

    test('4. Tìm kiếm theo từ khóa loại giao dịch tiếng Việt', () {
      expect(
        TransactionSearchFilterHelper.matchesSearch(txSalary, catSalary, walletBank, null, 'thu nhap'),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(txSalary, catSalary, walletBank, null, 'tien vao'),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(txCoffee, catCoffee, walletCash, null, 'chi tieu'),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(txTransfer, null, walletBank, walletCash, 'chuyen khoan'),
        isTrue,
      );
    });

    test('5. Parse số tiền linh hoạt: k, tr, m, dấu chấm', () {
      expect(TransactionSearchFilterHelper.parseAmountString('50k'), equals(50000.0));
      expect(TransactionSearchFilterHelper.parseAmountString('1.5k'), equals(1500.0));
      expect(TransactionSearchFilterHelper.parseAmountString('15tr'), equals(15000000.0));
      expect(TransactionSearchFilterHelper.parseAmountString('2.5m'), equals(2500000.0));
      expect(TransactionSearchFilterHelper.parseAmountString('50.000'), equals(50000.0));
      expect(TransactionSearchFilterHelper.parseAmountString('1.000.000'), equals(1000000.0));
    });

    test('6. Tìm kiếm theo số tiền chính xác, chữ số con và so sánh lớn/nhỏ', () {
      // Số tiền chính xác
      expect(
        TransactionSearchFilterHelper.matchesSearch(txCoffee, catCoffee, walletCash, null, '45k'),
        isTrue,
      );
      // Chuỗi số con
      expect(
        TransactionSearchFilterHelper.matchesSearch(txShopping, null, walletBank, null, '250'),
        isTrue,
      );
      // So sánh lớn hơn (> 10tr)
      expect(
        TransactionSearchFilterHelper.matchesSearch(txSalary, catSalary, walletBank, null, '> 10tr'),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(txCoffee, catCoffee, walletCash, null, '> 100k'),
        isFalse,
      );
      // So sánh nhỏ hơn (< 100k)
      expect(
        TransactionSearchFilterHelper.matchesSearch(txCoffee, catCoffee, walletCash, null, '< 100k'),
        isTrue,
      );
    });

    test('7. Tìm kiếm theo ngày tháng: hom nay, hom qua, thang X', () {
      expect(
        TransactionSearchFilterHelper.matchesSearch(
          txCoffee,
          catCoffee,
          walletCash,
          null,
          'hom nay',
          referenceDate: fixedDate,
        ),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(
          txSalary,
          catSalary,
          walletBank,
          null,
          'hom qua',
          referenceDate: fixedDate,
        ),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(
          txCoffee,
          catCoffee,
          walletCash,
          null,
          'thang 10',
          referenceDate: fixedDate,
        ),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(
          txShopping,
          null,
          walletBank,
          null,
          'thang 9',
          referenceDate: fixedDate,
        ),
        isTrue,
      );
    });

    test('8. Tính tổng dòng tiền Financial Overview chính xác', () {
      final list = [txCoffee, txSalary, txTransfer, txShopping];
      final overview = TransactionSearchFilterHelper.calculateOverview(list);

      // Thu nhập: 15,000,000
      expect(overview.totalIncome, equals(15000000.0));
      // Chi tiêu: 45,000 + 250,000 = 295,000 (transfer không tính vào thu/chi)
      expect(overview.totalExpense, equals(295000.0));
      // Dòng tiền ròng: 15,000,000 - 295,000 = 14,705,000
      expect(overview.netFlow, equals(14705000.0));
    });

    test('9. Tìm kiếm song ngữ Anh-Việt cho danh mục hệ thống, loại giao dịch và ngày tháng',
        () {
      final catFood = Category(
        categoryId: 'cat_food_sys',
        userId: 'u1',
        name: 'Ăn uống',
        type: 'expense',
        icon: 'restaurant',
        color: 0xFF000000,
      );
      final catCustom = Category(
        categoryId: 'cat_custom',
        userId: 'u1',
        name: 'Quỹ trà sữa',
        type: 'expense',
        icon: 'cafe',
        color: 0xFF000000,
      );

      final catSysSalary = Category(
        categoryId: 'cat_salary_sys',
        userId: 'u1',
        name: 'Lương',
        type: 'income',
        icon: 'work',
        color: 0xFF10B981,
      );

      // Danh mục hệ thống lưu bằng tiếng Việt vẫn tìm được bằng tiếng Anh
      expect(
        TransactionSearchFilterHelper.matchesSearch(
            txCoffee, catFood, walletCash, null, 'Food'),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(
            txSalary, catSysSalary, walletBank, null, 'Salary'),
        isTrue,
      );

      // Danh mục cá nhân giữ nguyên, không bị dịch sai sang tiếng Anh
      expect(
        TransactionSearchFilterHelper.matchesSearch(
            txCoffee, catCustom, walletCash, null, 'tra sua'),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(
            txCoffee, catCustom, walletCash, null, 'milk tea'),
        isFalse,
      );

      // Loại giao dịch bằng tiếng Anh
      expect(
        TransactionSearchFilterHelper.matchesSearch(
            txSalary, catSalary, walletBank, null, 'income'),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(
            txCoffee, catFood, walletCash, null, 'expense'),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(
            txTransfer, null, walletBank, walletCash, 'transfer'),
        isTrue,
      );

      // Ngày tháng bằng tiếng Anh
      expect(
        TransactionSearchFilterHelper.matchesSearch(
          txCoffee,
          catFood,
          walletCash,
          null,
          'today',
          referenceDate: fixedDate,
        ),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(
          txSalary,
          catSalary,
          walletBank,
          null,
          'yesterday',
          referenceDate: fixedDate,
        ),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(
          txCoffee,
          catFood,
          walletCash,
          null,
          'oct',
          referenceDate: fixedDate,
        ),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(
          txShopping,
          null,
          walletBank,
          null,
          'month 9',
          referenceDate: fixedDate,
        ),
        isTrue,
      );
    });

    test('10. Tim kiem hai chieu cho vi Tien mat mac dinh va giao dich muc tieu tiet kiem',
        () {
      final presetCash = Wallet(
        walletId: 'w_sys_cash',
        userId: 'u1',
        walletName: 'Tiền mặt',
        balance: 500000,
        type: 'cash',
        isUserNamed: false,
        createdAt: fixedDate,
      );
      final customCash = Wallet(
        walletId: 'w_usr_cash',
        userId: 'u1',
        walletName: 'Tiền mặt',
        balance: 500000,
        type: 'cash',
        isUserNamed: true,
        createdAt: fixedDate,
      );
      final goalDep = AppTransaction(
        transactionId: 'tx_g1',
        userId: 'u1',
        walletId: 'w_sys_cash',
        categoryId: '',
        amount: 2000000,
        type: 'goal_deposit',
        goalId: 'g1',
        note: 'Nạp vào mục tiêu "Laptop" từ ví Tiền mặt',
        date: fixedDate,
      );

      expect(
        TransactionSearchFilterHelper.matchesSearch(
          goalDep,
          null,
          presetCash,
          null,
          'Cash',
        ),
        isTrue,
      );
      expect(
        TransactionSearchFilterHelper.matchesSearch(
          goalDep,
          null,
          presetCash,
          null,
          'Deposit to goal',
        ),
        isTrue,
      );
      // Vi do nguoi dung tu dat "Tien mat" giu nguyen khong map thanh Cash
      expect(
        TransactionSearchFilterHelper.matchesSearch(
          txShopping,
          null,
          customCash,
          null,
          'Cash',
        ),
        isFalse,
      );
    });
  });
}
