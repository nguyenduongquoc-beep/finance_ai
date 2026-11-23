import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/screens/auth/forgot_password_screen.dart';
import 'package:finance_ai_app/services/language_controller.dart';

void main() {
  group('ForgotPasswordScreen Firebase Auth Reset Flow Tests', () {
    setUp(() async {
      await LanguageController.setLanguage('vi');
    });

    testWidgets('1. Từ chối email rỗng và email sai định dạng', (tester) async {
      bool sendCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordScreen(
            onSendResetEmail: (_) async {
              sendCalled = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(sendCalled, isFalse);

      await tester.enterText(find.byType(TextFormField), 'invalid-email');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(sendCalled, isFalse);
    });

    testWidgets('2. Gửi liên kết đặt lại mật khẩu thành công với email hợp lệ',
        (tester) async {
      String? sentEmail;

      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordScreen(
            initialEmail: 'user@financeai.vn',
            onSendResetEmail: (email) async {
              sentEmail = email;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('user@financeai.vn'), findsOneWidget);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(sentEmail, equals('user@financeai.vn'));
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    });

    testWidgets(
        '3. Chấp nhận email có dấu + và tên miền dài hơn 4 ký tự (VD: test+tag@my.finance)',
        (tester) async {
      String? sentEmail;

      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordScreen(
            onSendResetEmail: (email) async {
              sentEmail = email;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField), 'test+tag@my.finance');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(sentEmail, equals('test+tag@my.finance'));
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    });

    test('4. Regex email chấp nhận biến thể hợp lệ và chặn định dạng sai', () {
      final regex = ForgotPasswordScreen.emailValidationRegex;

      expect(regex.hasMatch('test+tag@my.finance'), isTrue);
      expect(regex.hasMatch('first.last+promo@sub.company'), isTrue);
      expect(regex.hasMatch('user@financeai.vn'), isTrue);

      expect(regex.hasMatch('invalid-email'), isFalse);
      expect(regex.hasMatch('user@domain'), isFalse);
      expect(regex.hasMatch('user@domain.c'), isFalse);
      expect(regex.hasMatch('user@.com'), isFalse);
      expect(regex.hasMatch('user@domain..com'), isFalse);
      expect(regex.hasMatch('user name@gmail.com'), isFalse);
    });
  });
}
