import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/otp_auth_service.dart';
import '../../utils/constants.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_snackbar.dart';
import 'reset_password_screen.dart';

/// Màn hình Nhập mã xác minh OTP gồm 6 chữ số
/// Thiết kế chuẩn Fintech:
/// - 6 ô nhập mã riêng biệt, tự động chuyển focus khi gõ hoặc xóa (Backspace).
/// - Hỗ trợ dán (Paste) tự động chuỗi 6 số từ Clipboard.
/// - Đồng hồ đếm ngược thời gian hết hạn (5 phút).
/// - Nút gửi lại mã kèm thời gian chờ chống lạm dụng (60 giây).
class OtpVerificationScreen extends StatefulWidget {
  final String email;

  const OtpVerificationScreen({
    super.key,
    required this.email,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _otpAuthService = OtpAuthService();

  static const int _otpLength = 6;
  final List<TextEditingController> _controllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(_otpLength, (_) => FocusNode());

  bool _isVerifying = false;
  String? _errorMessage;

  // Bộ đếm thời gian hiệu lực OTP (5 phút = 300 giây)
  Timer? _expiryTimer;
  int _expirySeconds = 300;

  // Bộ đếm gửi lại mã (60 giây)
  Timer? _resendTimer;
  int _resendCooldownSeconds = 60;

  @override
  void initState() {
    super.initState();
    _startExpiryTimer();
    _startResendTimer();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final fn in _focusNodes) {
      fn.dispose();
    }
    _expiryTimer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startExpiryTimer([int seconds = 300]) {
    setState(() => _expirySeconds = seconds);
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_expirySeconds <= 1) {
        timer.cancel();
        setState(() {
          _expirySeconds = 0;
          _errorMessage = 'Mã OTP đã hết hạn. Vui lòng yêu cầu gửi lại mã mới.';
        });
      } else {
        setState(() => _expirySeconds--);
      }
    });
  }

  void _startResendTimer([int seconds = 60]) {
    setState(() => _resendCooldownSeconds = seconds);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _resendCooldownSeconds = 0);
      } else {
        setState(() => _resendCooldownSeconds--);
      }
    });
  }

  String _formatTime(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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

  String get _currentOtpCode {
    return _controllers.map((c) => c.text).join();
  }

  void _onDigitChanged(int index, String value) {
    // Xử lý khi người dùng dán toàn bộ chuỗi 6 ký tự
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.length == _otpLength) {
        for (int i = 0; i < _otpLength; i++) {
          _controllers[i].text = digits[i];
        }
        _focusNodes[_otpLength - 1].requestFocus();
        _handleVerifyOtp();
        return;
      }
    }

    if (value.isNotEmpty) {
      if (index < _otpLength - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        // Tự động kiểm tra khi đã điền đủ 6 số
        if (_currentOtpCode.length == _otpLength) {
          _handleVerifyOtp();
        }
      }
    }
    setState(() => _errorMessage = null);
  }

  Future<void> _handleResendOtp() async {
    if (_resendCooldownSeconds > 0) return;

    // Reset các ô nhập
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();

    setState(() {
      _errorMessage = null;
    });

    final result = await _otpAuthService.sendPasswordResetOtp(widget.email);

    if (!mounted) return;
    if (result.isSuccess) {
      _startExpiryTimer(300);
      _startResendTimer(result.cooldownSeconds);
      AppSnackbar.show(context, 'Đã gửi lại mã OTP đến email của bạn.');
    } else {
      setState(() => _errorMessage = result.message);
    }
  }

  Future<void> _handleVerifyOtp() async {
    final otp = _currentOtpCode;
    if (otp.length != _otpLength) {
      setState(() => _errorMessage = 'Vui lòng nhập đủ 6 chữ số mã OTP.');
      return;
    }

    if (_expirySeconds <= 0) {
      setState(() => _errorMessage =
          'Mã OTP đã hết thời hạn sử dụng. Vui lòng nhấn gửi lại.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final result = await _otpAuthService.verifyOtp(
      email: widget.email,
      otp: otp,
    );

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (result.isValid) {
      // Chuyển sang Màn hình Đặt mật khẩu mới
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(
            email: widget.email,
            otp: otp,
            resetToken: result.resetToken,
          ),
        ),
      );
    } else {
      setState(() => _errorMessage = result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maskedEmail = _maskEmail(widget.email);

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_email_read_outlined,
                size: 36,
                color: AppColors.primaryLight,
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Xác thực mã OTP',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: context.appTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vui lòng nhập mã số gồm 6 chữ số vừa được gửi đến hòm thư:',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.appTextSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              maskedEmail,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.appTextPrimary,
              ),
            ),
            const SizedBox(height: 32),

            // 6 Ô nhập OTP
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(_otpLength, (index) {
                return _buildOtpBox(index);
              }),
            ),
            const SizedBox(height: 18),

            // Báo lỗi nếu có
            if (_errorMessage != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.expenseBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.expense, size: 16),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppColors.expense,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Đếm ngược thời gian hiệu lực
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: _expirySeconds > 60
                      ? context.appTextSecondary
                      : AppColors.warning,
                ),
                const SizedBox(width: 6),
                Text(
                  'Mã hết hạn sau: ${_formatTime(_expirySeconds)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _expirySeconds > 60
                        ? context.appTextSecondary
                        : AppColors.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Nút Xác thực
            AppButton(
              text: 'Xác nhận mã',
              isLoading: _isVerifying,
              onPressed: _currentOtpCode.length == _otpLength
                  ? _handleVerifyOtp
                  : null,
            ),
            const SizedBox(height: 20),

            // Hàng gửi lại mã
            if (_resendCooldownSeconds > 0)
              Text(
                'Có thể gửi lại mã sau ${_resendCooldownSeconds}s',
                style: TextStyle(
                  fontSize: 13,
                  color: context.appTextSecondary,
                ),
              )
            else
              TextButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Gửi lại mã OTP'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryLight,
                ),
                onPressed: _handleResendOtp,
              ),

            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Thay đổi địa chỉ email',
                style: TextStyle(
                  fontSize: 13,
                  color: context.appTextSecondary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 46,
      height: 56,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          // Xử lý phím backspace khi ô hiện tại đang trống để nhảy về ô trước
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace) {
            if (_controllers[index].text.isEmpty && index > 0) {
              _focusNodes[index - 1].requestFocus();
            }
          }
        },
        child: TextFormField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: context.appTextPrimary,
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            filled: true,
            fillColor: context.appInputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: context.appBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: context.appBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
          onChanged: (val) => _onDigitChanged(index, val),
        ),
      ),
    );
  }
}
