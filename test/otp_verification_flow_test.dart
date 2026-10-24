import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/services/otp_auth_service.dart';

void main() {
  group('OTP Authentication & Password Reset Flow Tests', () {
    final otpService = OtpAuthService();

    test('1. Kiểm tra gửi mã OTP từ chối địa chỉ email không hợp lệ', () async {
      final resEmpty = await otpService.sendPasswordResetOtp('');
      expect(resEmpty.isSuccess, isFalse);
      expect(resEmpty.message, contains('không hợp lệ'));

      final resNoAt = await otpService.sendPasswordResetOtp('invalid-email-domain');
      expect(resNoAt.isSuccess, isFalse);
    });

    test('2. Kiểm tra gửi mã OTP thành công trong môi trường Dev Mock', () async {
      final res = await otpService.sendPasswordResetOtp('test.finance@gmail.com');
      expect(res.isSuccess, isTrue);
      expect(res.cooldownSeconds, equals(60));
    });

    test('3. Xác thực OTP từ chối mã không đủ 6 chữ số', () async {
      final resShort = await otpService.verifyOtp(
        email: 'test.finance@gmail.com',
        otp: '123',
      );
      expect(resShort.isValid, isFalse);
      expect(resShort.message, contains('đúng 6 chữ số'));
    });

    test('4. Xác thực OTP thành công với mã 6 số chuẩn', () async {
      // Đầu tiên gọi send để kích hoạt mock
      await otpService.sendPasswordResetOtp('test.finance@gmail.com');

      final res = await otpService.verifyOtp(
        email: 'test.finance@gmail.com',
        otp: '123456',
      );
      expect(res.isValid, isTrue);
      expect(res.resetToken, isNotNull);
    });

    test('5. Đặt lại mật khẩu từ chối mật khẩu mới dưới 6 ký tự', () async {
      final res = await otpService.resetPasswordWithOtp(
        email: 'test.finance@gmail.com',
        otp: '123456',
        newPassword: '123',
      );
      expect(res.isSuccess, isFalse);
      expect(res.message, contains('ít nhất 6 ký tự'));
    });

    test('6. Đặt lại mật khẩu thành công khi đầy đủ điều kiện', () async {
      final res = await otpService.resetPasswordWithOtp(
        email: 'test.finance@gmail.com',
        otp: '123456',
        newPassword: 'newStrongPassword999',
        resetToken: 'dev-mock-reset-token',
      );
      expect(res.isSuccess, isTrue);
    });
  });
}
