import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Kết quả gửi mã OTP
class OtpSendResult {
  final bool isSuccess;
  final String message;
  final int cooldownSeconds;
  final bool isDevelopmentMock;

  const OtpSendResult({
    required this.isSuccess,
    required this.message,
    this.cooldownSeconds = 60,
    this.isDevelopmentMock = false,
  });
}

/// Kết quả xác thực mã OTP
class OtpVerifyResult {
  final bool isValid;
  final String message;
  final String? resetToken;

  const OtpVerifyResult({
    required this.isValid,
    required this.message,
    this.resetToken,
  });
}

/// Kết quả đặt lại mật khẩu bằng OTP
class OtpResetPasswordResult {
  final bool isSuccess;
  final String message;

  const OtpResetPasswordResult({
    required this.isSuccess,
    required this.message,
  });
}

/// Service quản lý vòng đời xác thực mã OTP qua Email
///
/// Kiến trúc chuẩn Enterprise & Fintech:
/// 1. Giao tiếp an toàn với Firebase Cloud Functions endpoint qua HTTPS.
/// 2. Máy chủ Cloud Functions chịu trách nhiệm:
///    - Sinh mã 6 số ngẫu nhiên mật mã (CSPRNG).
///    - Băm mã (Hash) lưu trong Firestore nội bộ (Client không được đọc/ghi).
///    - Gửi email qua dịch vụ gửi mail (Gmail SMTP / Resend API).
///    - Xác minh số lần thử (Tối đa 5 lần).
///    - Đổi mật khẩu qua Firebase Admin SDK (`admin.auth().updateUser`).
/// 3. Hỗ trợ chế độ Debug Mock khi backend chưa deploy để kiểm thử UI/UX mượt mà.
class OtpAuthService {
  static final OtpAuthService _instance = OtpAuthService._internal();
  factory OtpAuthService() => _instance;
  OtpAuthService._internal();

  // Cấu hình URL Cloud Function backend
  static const String _defaultBaseUrl =
      'https://us-central1-finance-ai-app-6df28.cloudfunctions.net';

  String get baseUrl => _defaultBaseUrl;

  // Bộ nhớ tạm thời cho Mock trong chế độ kDebugMode khi backend chưa chạy
  static final Map<String, String> _debugOtpStore = {};
  static final Map<String, DateTime> _debugOtpExpiry = {};

  /// Gửi mã OTP 6 số đến Email
  Future<OtpSendResult> sendPasswordResetOtp(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      return const OtpSendResult(
        isSuccess: false,
        message: 'Địa chỉ email không hợp lệ.',
      );
    }

    try {
      debugPrint(
          '[OtpAuthService] Gửi yêu cầu OTP đến backend cho: $cleanEmail');
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);

      final uri = Uri.parse('$baseUrl/sendPasswordResetOtp');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'email': cleanEmail}));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody) as Map<String, dynamic>;
        return OtpSendResult(
          isSuccess: true,
          message: data['message'] ??
              'Đã gửi mã OTP gồm 6 chữ số đến email của bạn.',
          cooldownSeconds: (data['cooldownSeconds'] as num?)?.toInt() ?? 60,
        );
      } else {
        final data = jsonDecode(responseBody) as Map<String, dynamic>?;
        final errorMsg =
            data?['error'] ?? 'Không thể gửi mã OTP (${response.statusCode})';
        return OtpSendResult(isSuccess: false, message: errorMsg);
      }
    } catch (e) {
      debugPrint('[OtpAuthService] Lỗi kết nối Cloud Function: $e');

      // Trong môi trường debug nếu chưa deploy backend live, hỗ trợ Mock Test
      if (kDebugMode) {
        const mockOtp = '123456';
        _debugOtpStore[cleanEmail] = mockOtp;
        _debugOtpExpiry[cleanEmail] =
            DateTime.now().add(const Duration(minutes: 5));

        debugPrint('====================================================');
        debugPrint(
            '[DEV OTP MOCK] Backend chưa deploy online. Sinh mã test cho $cleanEmail: $mockOtp');
        debugPrint('====================================================');

        return const OtpSendResult(
          isSuccess: true,
          message: 'Đã gửi mã xác nhận OTP gồm 6 chữ số đến email của bạn.',
          cooldownSeconds: 60,
          isDevelopmentMock: true,
        );
      }

      return const OtpSendResult(
        isSuccess: false,
        message:
            'Không thể kết nối đến máy chủ OTP. Vui lòng kiểm tra kết nối mạng hoặc thử lại sau.',
      );
    }
  }

  /// Xác thực mã OTP 6 số người dùng nhập
  Future<OtpVerifyResult> verifyOtp({
    required String email,
    required String otp,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanOtp = otp.trim();

    if (cleanOtp.length != 6) {
      return const OtpVerifyResult(
        isValid: false,
        message: 'Mã OTP phải bao gồm đúng 6 chữ số.',
      );
    }

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);

      final uri = Uri.parse('$baseUrl/verifyOtp');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'email': cleanEmail, 'otp': cleanOtp}));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody) as Map<String, dynamic>;
        return OtpVerifyResult(
          isValid: true,
          message: 'Xác thực mã OTP thành công.',
          resetToken: data['resetToken'] as String?,
        );
      } else {
        final data = jsonDecode(responseBody) as Map<String, dynamic>?;
        return OtpVerifyResult(
          isValid: false,
          message: data?['error'] ?? 'Mã OTP không chính xác hoặc đã hết hạn.',
        );
      }
    } catch (e) {
      debugPrint('[OtpAuthService] Lỗi verify OTP: $e');

      // Fallback debug mock
      if (kDebugMode) {
        final stored = _debugOtpStore[cleanEmail];
        final expiry = _debugOtpExpiry[cleanEmail];

        if (stored != null &&
            expiry != null &&
            DateTime.now().isBefore(expiry)) {
          if (cleanOtp == stored) {
            return const OtpVerifyResult(
              isValid: true,
              message: 'Xác thực mã OTP thành công (Dev Mode).',
              resetToken: 'dev-mock-reset-token',
            );
          } else {
            return const OtpVerifyResult(
              isValid: false,
              message: 'Mã OTP không chính xác. Vui lòng kiểm tra lại.',
            );
          }
        }
      }

      return const OtpVerifyResult(
        isValid: false,
        message:
            'Không thể kết nối đến máy chủ xác minh. Vui lòng thử lại sau.',
      );
    }
  }

  /// Cập nhật mật khẩu mới sau khi mã OTP đã được xác minh thành công
  Future<OtpResetPasswordResult> resetPasswordWithOtp({
    required String email,
    required String otp,
    required String newPassword,
    String? resetToken,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    if (newPassword.length < 6) {
      return const OtpResetPasswordResult(
        isSuccess: false,
        message: 'Mật khẩu mới phải có ít nhất 6 ký tự.',
      );
    }

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      final uri = Uri.parse('$baseUrl/resetPasswordWithOtp');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'email': cleanEmail,
        'otp': otp.trim(),
        'newPassword': newPassword,
        'resetToken': resetToken,
      }));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        return const OtpResetPasswordResult(
          isSuccess: true,
          message: 'Đặt lại mật khẩu thành công! Bạn có thể đăng nhập ngay.',
        );
      } else {
        final data = jsonDecode(responseBody) as Map<String, dynamic>?;
        return OtpResetPasswordResult(
          isSuccess: false,
          message: data?['error'] ?? 'Không thể cập nhật mật khẩu lúc này.',
        );
      }
    } catch (e) {
      debugPrint('[OtpAuthService] Lỗi reset mật khẩu backend: $e');

      // Trong kDebugMode nếu backend chưa deploy, hoàn tất bằng Mock thông báo
      if (kDebugMode) {
        _debugOtpStore.remove(cleanEmail);
        _debugOtpExpiry.remove(cleanEmail);

        return const OtpResetPasswordResult(
          isSuccess: true,
          message: 'Đặt lại mật khẩu thành công (Chế độ Dev Mock)!',
        );
      }

      return const OtpResetPasswordResult(
        isSuccess: false,
        message: 'Không thể cập nhật mật khẩu do lỗi mạng. Vui lòng thử lại.',
      );
    }
  }
}
