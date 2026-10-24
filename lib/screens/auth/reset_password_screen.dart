import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/otp_auth_service.dart';
import '../../utils/constants.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import 'login_screen.dart';

/// Màn hình Đặt mật khẩu mới sau khi xác thực OTP thành công
/// Hoàn tất luồng Quên mật khẩu nội bộ ngay trong ứng dụng mà không cần rời sang web.
class ResetPasswordScreen extends StatefulWidget {
  final String email;
  final String otp;
  final String? resetToken;

  const ResetPasswordScreen({
    super.key,
    required this.email,
    required this.otp,
    this.resetToken,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _otpAuthService = OtpAuthService();

  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (newPass.length < 6) {
      setState(() => _errorMessage = 'Mật khẩu mới phải có ít nhất 6 ký tự.');
      return;
    }

    if (newPass != confirm) {
      setState(() => _errorMessage = 'Xác nhận mật khẩu mới không trùng khớp.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _otpAuthService.resetPasswordWithOtp(
      email: widget.email,
      otp: widget.otp,
      newPassword: newPass,
      resetToken: widget.resetToken,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      _showSuccessDialog();
    } else {
      setState(() => _errorMessage = result.message);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.appBorder),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        title: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.incomeBackground,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.income,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Đổi mật khẩu thành công!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.appTextPrimary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Mật khẩu tài khoản của bạn đã được cập nhật thành công. Vui lòng đăng nhập lại với mật khẩu mới.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: context.appTextSecondary,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
                child: const Text(
                  'Đăng nhập ngay',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        title: const Text('Đặt lại mật khẩu'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tạo mật khẩu mới',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: context.appTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vui lòng nhập mật khẩu mới cho tài khoản ${widget.email}. Mật khẩu phải có độ dài tối thiểu 6 ký tự.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: context.appTextSecondary,
              ),
            ),
            const SizedBox(height: 28),

            // Mật khẩu mới
            AppTextField(
              controller: _newPasswordController,
              labelText: 'Mật khẩu mới',
              hintText: 'Tối thiểu 6 ký tự',
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: _obscureNew,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNew
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: context.appTextSecondary,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),

            // Checklist độ dài
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 14,
                  color: _newPasswordController.text.length >= 6
                      ? AppColors.income
                      : context.appTextSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Tối thiểu 6 ký tự',
                  style: TextStyle(
                    fontSize: 11,
                    color: _newPasswordController.text.length >= 6
                        ? AppColors.income
                        : context.appTextSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Xác nhận mật khẩu mới
            AppTextField(
              controller: _confirmPasswordController,
              labelText: 'Xác nhận mật khẩu mới',
              hintText: 'Nhập lại mật khẩu mới',
              prefixIcon: Icons.lock_reset_rounded,
              obscureText: _obscureConfirm,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: context.appTextSecondary,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),

            // Checklist trùng khớp
            if (_confirmPasswordController.text.isNotEmpty)
              Row(
                children: [
                  Icon(
                    _newPasswordController.text ==
                            _confirmPasswordController.text
                        ? Icons.check_circle_outline_rounded
                        : Icons.cancel_outlined,
                    size: 14,
                    color: _newPasswordController.text ==
                            _confirmPasswordController.text
                        ? AppColors.income
                        : AppColors.expense,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _newPasswordController.text ==
                            _confirmPasswordController.text
                        ? 'Mật khẩu xác nhận trùng khớp'
                        : 'Mật khẩu xác nhận chưa khớp',
                    style: TextStyle(
                      fontSize: 11,
                      color: _newPasswordController.text ==
                              _confirmPasswordController.text
                          ? AppColors.income
                          : AppColors.expense,
                    ),
                  ),
                ],
              ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.expenseBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.expense, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppColors.expense,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),

            // Nút Lưu mật khẩu
            AppButton(
              text: 'Cập nhật mật khẩu',
              isLoading: _isLoading,
              onPressed: _newPasswordController.text.length >= 6 &&
                      _newPasswordController.text ==
                          _confirmPasswordController.text
                  ? _handleResetPassword
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
