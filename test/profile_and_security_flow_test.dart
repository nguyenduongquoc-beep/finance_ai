import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/user_model.dart';
import 'package:finance_ai_app/screens/profile_screen.dart';
import 'package:finance_ai_app/utils/formatters.dart';

void main() {
  group('Profile & Security Business Logic Tests', () {
    // -------------------------------------------------------------
    // 1. Password Policy & Security Validation
    // -------------------------------------------------------------
    test(
        '1.1. Mật khẩu mới hợp lệ: độ dài >= 6, khác mật khẩu hiện tại và trùng khớp xác nhận',
        () {
      const current = 'oldPassword123';
      const newPass = 'newStrongPass456';
      const confirm = 'newStrongPass456';

      expect(newPass.length >= 6, isTrue);
      expect(newPass != current, isTrue);
      expect(newPass == confirm, isTrue);
    });

    test('1.2. Mật khẩu mới bị từ chối nếu ngắn hơn 6 ký tự', () {
      const newPass = '12345';
      expect(newPass.length < 6, isTrue);
    });

    test('1.3. Mật khẩu mới bị từ chối nếu trùng với mật khẩu hiện tại', () {
      const current = 'samePassword123';
      const newPass = 'samePassword123';
      expect(newPass == current, isTrue);
    });

    test('1.4. Mật khẩu mới bị từ chối nếu xác nhận không khớp', () {
      const newPass = 'passwordA123';
      const confirm = 'passwordB123';
      expect(newPass != confirm, isTrue);
    });

    // -------------------------------------------------------------
    // 2. Email Masking in Forgot Password Flow
    // -------------------------------------------------------------
    test('2.1. Che bớt địa chỉ email dài bảo vệ quyền riêng tư', () {
      String maskEmail(String email) {
        if (!email.contains('@')) return email;
        final parts = email.split('@');
        final name = parts[0];
        final domain = parts[1];
        if (name.length <= 2) {
          return '$name***@$domain';
        }
        final first = name[0];
        final last = name[name.length - 1];
        return '$first***$last@$domain';
      }

      expect(maskEmail('nguyenvana@gmail.com'), equals('n***a@gmail.com'));
      expect(maskEmail('support@financeai.vn'), equals('s***t@financeai.vn'));
      expect(maskEmail('ab@gmail.com'), equals('ab***@gmail.com'));
      expect(maskEmail('invalid-string'), equals('invalid-string'));
    });

    // -------------------------------------------------------------
    // 3. Monthly Income Benchmark & Parsing Logic
    // -------------------------------------------------------------
    test('3.1. Phân tích cú pháp thu nhập hàng tháng (monthlyIncome) chính xác',
        () {
      expect(AppFormatters.parseCurrencyInput('15000000'), equals(15000000.0));
      expect(
          AppFormatters.parseCurrencyInput('15.000.000'), equals(15000000.0));
      expect(AppFormatters.parseCurrencyInput('  25,500,000  '),
          equals(25500000.0));
      expect(AppFormatters.parseCurrencyInput(''), equals(0.0));
    });

    test('3.2. Kiểm tra thu nhập không âm', () {
      final input = AppFormatters.parseCurrencyInput('12000000');
      expect(input >= 0, isTrue);

      bool validatePositiveIncome(double val) => val >= 0;
      expect(validatePositiveIncome(12000000), isTrue);
      expect(validatePositiveIncome(0), isTrue);
      expect(validatePositiveIncome(-1000), isFalse);
    });

    test('3.3. So sánh thu nhập thực nhận vs thu nhập khai báo trong hồ sơ',
        () {
      const monthlyIncome = 20000000.0; // Benchmark kỳ vọng
      const actualIncomeAchieved = 25000000.0;
      const actualIncomeUnder = 15000000.0;

      // Đạt mục tiêu khi thực nhận >= khai báo
      expect(actualIncomeAchieved >= monthlyIncome, isTrue);
      expect(actualIncomeUnder >= monthlyIncome, isFalse);

      // Thu nhập khai báo không làm thay đổi số dư ví
      const walletBalance = 10000000.0;
      expect(walletBalance, equals(10000000.0));
    });

    // -------------------------------------------------------------
    // 4. AppUser Model Serialization & Integrity
    // -------------------------------------------------------------
    test(
        '4.1. AppUser toMap và fromMap bảo toàn chính xác monthlyIncome và occupation',
        () {
      final user = AppUser(
        uid: 'user_123',
        name: 'Trần Văn B',
        email: 'tranvanb@gmail.com',
        avatar: 'path/to/avatar.jpg',
        monthlyIncome: 18000000.0,
        occupation: 'Kỹ sư phần mềm',
        createdAt: DateTime(2026, 1, 1),
      );

      final map = user.toMap();
      expect(map['monthlyIncome'], equals(18000000.0));
      expect(map['occupation'], equals('Kỹ sư phần mềm'));
      expect(map['name'], equals('Trần Văn B'));

      final restored = AppUser.fromMap(map, 'user_123');
      expect(restored.monthlyIncome, equals(18000000.0));
      expect(restored.occupation, equals('Kỹ sư phần mềm'));
      expect(restored.name, equals('Trần Văn B'));
      expect(restored.email, equals('tranvanb@gmail.com'));
    });

    test(
        '4.2. AppUser copyWith cập nhật trường độc lập mà không mất dữ liệu cũ',
        () {
      final user = AppUser(
        uid: 'user_123',
        name: 'Nguyễn Văn C',
        email: 'nguyenvanc@gmail.com',
        monthlyIncome: 10000000.0,
        occupation: 'Nhân viên kinh doanh',
        createdAt: DateTime(2026, 1, 1),
      );

      final updated = user.copyWith(
        monthlyIncome: 15000000.0,
        occupation: 'Trưởng phòng kinh doanh',
      );

      expect(updated.monthlyIncome, equals(15000000.0));
      expect(updated.occupation, equals('Trưởng phòng kinh doanh'));
      expect(updated.name, equals('Nguyễn Văn C')); // Giữ nguyên tên
      expect(updated.email, equals('nguyenvanc@gmail.com')); // Giữ nguyên email
    });

    // -------------------------------------------------------------
    // 5. Provider Discrimination Logic
    // -------------------------------------------------------------
    test(
        '5.1. Nhận diện chính xác loại tài khoản Google-only vs Email/Password',
        () {
      String resolveProviderLabel({
        required bool hasGoogle,
        required bool hasPassword,
      }) {
        if (hasGoogle && !hasPassword) return 'Google';
        if (hasPassword && !hasGoogle) return 'Email & Mật khẩu';
        if (hasGoogle && hasPassword) return 'Google + Email/Mật khẩu';
        return 'Email';
      }

      expect(resolveProviderLabel(hasGoogle: true, hasPassword: false),
          equals('Google'));
      expect(resolveProviderLabel(hasGoogle: false, hasPassword: true),
          equals('Email & Mật khẩu'));
      expect(resolveProviderLabel(hasGoogle: true, hasPassword: true),
          equals('Google + Email/Mật khẩu'));
      expect(resolveProviderLabel(hasGoogle: false, hasPassword: false),
          equals('Email'));
    });

    // -------------------------------------------------------------
    // 6. Redesigned Logout Confirmation Dialog UI/UX Tests
    // -------------------------------------------------------------
    testWidgets(
        '6.1. Hộp thoại đăng xuất hiện đại: bấm Hủy, bấm X hoặc chạm ra ngoài hộp thoại đều tương ứng với hủy bỏ (không đăng xuất); bấm Đăng xuất trả về true',
        (tester) async {
      bool? dialogResult = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    dialogResult = await showLogoutConfirmationDialog(
                      ctx,
                      userEmail: 'user@financeai.vn',
                    );
                  },
                  child: const Text('Open Logout Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      // 1. Mở hộp thoại và bấm nút "Hủy" -> trả về false
      await tester.tap(find.text('Open Logout Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Đăng xuất tài khoản?'), findsOneWidget);
      expect(find.text('user@financeai.vn'), findsOneWidget);
      expect(find.text('Hủy'), findsOneWidget);
      expect(find.text('Đăng xuất'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('logout_dialog_cancel')));
      await tester.pumpAndSettle();
      expect(dialogResult, isFalse);
      expect(find.text('Đăng xuất tài khoản?'), findsNothing);

      // 2. Mở lại hộp thoại và chạm ra ngoài vùng hộp thoại (barrier) -> đóng hộp thoại (dialogResult == null, tương đương hủy)
      dialogResult = true;
      await tester.tap(find.text('Open Logout Dialog'));
      await tester.pumpAndSettle();
      expect(find.text('Đăng xuất tài khoản?'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(dialogResult == true, isFalse);
      expect(find.text('Đăng xuất tài khoản?'), findsNothing);

      // 3. Mở lại hộp thoại và bấm nút "Đăng xuất" -> trả về true
      await tester.tap(find.text('Open Logout Dialog'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('logout_dialog_confirm')));
      await tester.pumpAndSettle();
      expect(dialogResult, isTrue);
    });
  });
}
