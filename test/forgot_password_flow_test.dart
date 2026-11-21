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
  });
}
