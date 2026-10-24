import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import '../../services/otp_auth_service.dart';
import '../../utils/constants.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import 'otp_verification_screen.dart';

/// Màn hình Quên mật khẩu — Hỗ trợ cả 2 phương thức:
/// 1. Xác thực bằng mã OTP 6 số ngay trên ứng dụng (Phương thức chính).
/// 2. Gửi liên kết đặt lại mật khẩu qua Firebase Auth (Phương thức dự phòng).
class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  final _authService = AuthService();
  final _otpAuthService = OtpAuthService();

  bool _isSendingOtp = false;
  bool _isSendingLink = false;
  bool _emailLinkSent = false;
  String? _errorMessage;

  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown([int seconds = 60]) {
    setState(() => _cooldownSeconds = seconds);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds--);
      }
    });
  }

  String _maskEmail(String email) {
    if (!email.contains('@')) return email;
    final parts = email.split('@');
    final name = parts[0];
    final domain = parts[1];
    if (name.length <= 2) return '$name***@$domain';
    final first = name[0];
    final last = name[name.length - 1];
    return '$first***$last@$domain';
  }

  /// 1. Gửi mã OTP 6 số và mở màn hình nhập mã OTP
  Future<void> _handleSendOtp() async {
    if (_cooldownSeconds > 0) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSendingOtp = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final result = await _otpAuthService.sendPasswordResetOtp(email);

    if (!mounted) return;
    setState(() => _isSendingOtp = false);

    if (result.isSuccess) {
      _startCooldown(result.cooldownSeconds);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(email: email),
        ),
      );
    } else {
      setState(() => _errorMessage = result.message);
    }
  }

  /// 2. Gửi liên kết dự phòng qua Firebase Action Link
  Future<void> _handleSendFirebaseLink() async {
    if (_cooldownSeconds > 0) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSendingLink = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();

    try {
      await _authService.sendPasswordResetEmail(email);
      if (mounted) {
        setState(() => _emailLinkSent = true);
        _startCooldown(60);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        if (e.code == 'too-many-requests') {
          setState(() => _errorMessage =
              'Bạn đã gửi quá nhiều yêu cầu liên tiếp. Vui lòng chờ vài phút.');
        } else if (e.code == 'user-not-found') {
          setState(() => _errorMessage =
              'Không tìm thấy tài khoản mật khẩu với email này trên Firebase.');
        } else {
          setState(() => _errorMessage =
              'Không thể gửi email (${e.code}): ${e.message ?? 'Thử lại sau.'}');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Không thể gửi email do lỗi mạng.');
      }
    } finally {
      if (mounted) setState(() => _isSendingLink = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: context.appTextPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: _emailLinkSent
            ? _buildFirebaseLinkSuccessView()
            : _buildRequestForm(),
      ),
    );
  }

  /// Giao diện khi người dùng chọn nhận link Firebase
  Widget _buildFirebaseLinkSuccessView() {
    final email = _emailController.text.trim();
    final masked = _maskEmail(email);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        Container(
          width: 76,
          height: 76,
          decoration: const BoxDecoration(
            color: AppColors.incomeBackground,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mark_email_read_rounded,
            size: 38,
            color: AppColors.income,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Đã gửi liên kết khôi phục!',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: context.appTextPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Hệ thống đã gửi thư xác nhận đặt lại mật khẩu đến địa chỉ $masked.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.appTextSecondary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),

        // Cảnh báo Thư rác
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.warningBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.warning.withAlpha(60)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'LƯU Ý QUAN TRỌNG TỪ HỆ THỐNG',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.warning,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '1. Email từ Firebase chứa LIÊN KẾT (link web) để tạo mật khẩu mới.\n'
                '2. Nếu không thấy trong Hộp thư đến, BẮT BUỘC kiểm tra mục THƯ RÁC (SPAM) hoặc THƯ QUẢNG CÁO (Promotions) vì bộ lọc Gmail thường nhận nhầm thư này.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: context.appTextPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        AppButton(
          text: 'Quay lại đăng nhập',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  /// Form yêu cầu nhập email
  Widget _buildRequestForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text(
            'Quên mật khẩu?',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: context.appTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Nhập địa chỉ email đăng ký tài khoản của bạn để nhận mã xác minh OTP gồm 6 chữ số.',
            style: TextStyle(
              color: context.appTextSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // Email Input
          AppTextField(
            controller: _emailController,
            labelText: 'Địa chỉ Email',
            hintText: 'nguyenvana@gmail.com',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              final val = v?.trim() ?? '';
              if (val.isEmpty) return 'Vui lòng nhập địa chỉ email';
              final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
              if (!emailRegex.hasMatch(val)) {
                return 'Email không đúng định dạng';
              }
              return null;
            },
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.expenseBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.expense.withAlpha(50)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.expense, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: AppColors.expense,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Nút 1: Gửi mã OTP xác minh (Chính)
          AppButton(
            text: _cooldownSeconds > 0
                ? 'Vui lòng chờ ($_cooldownSeconds s)'
                : 'Nhận mã OTP qua Email',
            isLoading: _isSendingOtp,
            onPressed: _cooldownSeconds > 0 ? null : _handleSendOtp,
          ),
          const SizedBox(height: 16),

          // Tùy chọn gửi link dự phòng
          Center(
            child: TextButton(
              onPressed: _isSendingLink ? null : _handleSendFirebaseLink,
              child: Text(
                _isSendingLink
                    ? 'Đang gửi liên kết...'
                    : 'Hoặc gửi liên kết đặt lại mật khẩu trực tiếp',
                style: const TextStyle(
                  color: AppColors.primaryLight,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Quay lại đăng nhập
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Quay lại Đăng nhập',
                style: TextStyle(
                  color: context.appTextSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
