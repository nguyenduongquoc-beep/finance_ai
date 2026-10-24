import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_text_field.dart';
import 'auth/forgot_password_screen.dart';

/// Màn hình Bảo mật tài khoản & Đổi mật khẩu
///
/// Thiết kế chuyên biệt theo chuẩn Fintech:
/// 1. Tự động nhận diện phương thức xác thực (Google Sign-In vs Email/Password).
/// 2. Ẩn form đổi mật khẩu đối với tài khoản Google-only để tránh gây hiểu nhầm,
///    thay vào đó cung cấp hướng dẫn bảo mật chính thức.
/// 3. Đối với Email/Password: Kiểm tra Re-authentication bằng mật khẩu hiện tại
///    trước khi cập nhật mật khẩu mới qua Firebase Authentication.
/// 4. Không dùng mã OTP giả lập ở Client-side. Luồng đặt lại mật khẩu tuân theo
///    tiêu chuẩn an toàn của Firebase Auth (Action Link / Re-auth).
class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  final _authService = AuthService();

  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isUpdating = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleChangePassword() async {
    final current = _currentPasswordController.text;
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (current.isEmpty) {
      AppSnackbar.show(context, 'Vui lòng nhập mật khẩu hiện tại',
          isError: true);
      return;
    }
    if (newPass.isEmpty) {
      AppSnackbar.show(context, 'Vui lòng nhập mật khẩu mới', isError: true);
      return;
    }
    if (newPass.length < 6) {
      AppSnackbar.show(context, 'Mật khẩu mới phải có ít nhất 6 ký tự',
          isError: true);
      return;
    }
    if (newPass == current) {
      AppSnackbar.show(
        context,
        'Mật khẩu mới không được trùng với mật khẩu hiện tại',
        isError: true,
      );
      return;
    }
    if (newPass != confirm) {
      AppSnackbar.show(context, 'Xác nhận mật khẩu không khớp', isError: true);
      return;
    }

    setState(() => _isUpdating = true);
    try {
      await _authService.changePassword(
        currentPassword: current,
        newPassword: newPass,
      );

      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();

      if (mounted) {
        AppSnackbar.show(context, 'Cập nhật mật khẩu thành công!');
        // Tự động đóng màn hình sau khi đổi thành công để bảo vệ phiên làm việc
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String message;
        switch (e.code) {
          case 'wrong-password':
          case 'invalid-credential':
            message = 'Mật khẩu hiện tại không chính xác';
            break;
          case 'weak-password':
            message =
                'Mật khẩu mới quá yếu, vui lòng chọn mật khẩu phức tạp hơn';
            break;
          case 'requires-recent-login':
            message =
                'Phiên đăng nhập đã hết hạn. Vui lòng đăng xuất và đăng nhập lại trước khi đổi mật khẩu.';
            break;
          case 'network-request-failed':
            message = 'Lỗi kết nối mạng. Vui lòng kiểm tra lại đường truyền.';
            break;
          default:
            message = 'Không thể đổi mật khẩu: ${e.message ?? e.code}';
        }
        AppSnackbar.show(context, message, isError: true);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(
          context,
          'Đã xảy ra lỗi không xác định, vui lòng thử lại sau',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isEmailPasswordUser = _authService.isEmailPasswordUser;
    final isGoogleUser = _authService.isGoogleUser;
    final isGoogleOnly = isGoogleUser && !isEmailPasswordUser;

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: const Text('Bảo mật tài khoản'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Thẻ thông tin phương thức đăng nhập
            _buildAuthMethodCard(user, isGoogleOnly, isEmailPasswordUser),
            const SizedBox(height: 24),

            // 2. Nội dung bảo mật theo Provider
            if (isGoogleOnly)
              _buildGoogleOnlySection(user?.email ?? '')
            else
              _buildPasswordChangeForm(),

            const SizedBox(height: 24),

            // 3. Quy chuẩn an toàn dữ liệu
            _buildSecurityNotice(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// Thẻ tổng quan phương thức đăng nhập
  Widget _buildAuthMethodCard(
      User? user, bool isGoogleOnly, bool isEmailPassword) {
    final email = user?.email ?? 'Không có email';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isGoogleOnly
                      ? const Color(0xFFEA4335).withAlpha(20)
                      : AppColors.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isGoogleOnly
                      ? Icons.g_mobiledata_rounded
                      : Icons.shield_outlined,
                  color: isGoogleOnly
                      ? const Color(0xFFEA4335)
                      : AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isGoogleOnly ? 'Tài khoản Google' : 'Email & Mật khẩu',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.appTextSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.incomeBackground,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Đã xác minh',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.income,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Giao diện dành riêng cho tài khoản Google-only
  Widget _buildGoogleOnlySection(String email) {
    return AppCard(
      borderColor: AppColors.info.withAlpha(50),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppColors.info, size: 20),
              const SizedBox(width: 8),
              Text(
                'Quản lý mật khẩu qua Google',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.appTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Tài khoản này được đăng nhập thông qua xác thực Google ($email). '
            'Ứng dụng không lưu trữ mật khẩu riêng của bạn nhằm tuân thủ quy chuẩn bảo mật OAuth 2.0.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: context.appTextSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.appBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.appBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded,
                    size: 18, color: AppColors.income),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bảo vệ bởi xác thực đa lớp (2FA) của Google',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: context.appTextPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Nếu muốn đổi mật khẩu hoặc xem cài đặt đăng nhập, bạn có thể truy cập trang Quản lý tài khoản Google của thiết bị.',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: context.appTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Form đổi mật khẩu cho tài khoản Email/Password
  Widget _buildPasswordChangeForm() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Đổi mật khẩu',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.appTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Vui lòng nhập mật khẩu hiện tại để xác thực trước khi thiết lập mật khẩu mới.',
            style: TextStyle(
              fontSize: 12,
              color: context.appTextSecondary,
            ),
          ),
          const SizedBox(height: 18),

          // Mật khẩu hiện tại
          AppTextField(
            controller: _currentPasswordController,
            labelText: 'Mật khẩu hiện tại',
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _obscureCurrent,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureCurrent
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: context.appTextSecondary,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscureCurrent = !_obscureCurrent),
            ),
          ),
          const SizedBox(height: 16),

          // Mật khẩu mới
          AppTextField(
            controller: _newPasswordController,
            labelText: 'Mật khẩu mới',
            hintText: 'Tối thiểu 6 ký tự',
            prefixIcon: Icons.lock_reset_rounded,
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
          ),
          const SizedBox(height: 8),

          // Chỉ dẫn độ mạnh
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
            prefixIcon: Icons.lock_outline_rounded,
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
          ),
          const SizedBox(height: 24),

          // Nút cập nhật mật khẩu
          AppButton(
            text: 'Cập nhật mật khẩu',
            isLoading: _isUpdating,
            onPressed: _handleChangePassword,
          ),
          const SizedBox(height: 8),

          // Quên mật khẩu link
          Center(
            child: TextButton(
              onPressed: () {
                final currentEmail = FirebaseAuth.instance.currentUser?.email;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ForgotPasswordScreen(initialEmail: currentEmail),
                  ),
                );
              },
              child: const Text(
                'Quên mật khẩu hiện tại?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primaryLight,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Thông báo bảo mật an toàn
  Widget _buildSecurityNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_clock_outlined,
              size: 20, color: context.appTextSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bảo mật dữ liệu',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Mọi thao tác thay đổi mật khẩu đều yêu cầu xác thực chính thức với máy chủ. '
                  'Dữ liệu tài chính của bạn được mã hóa an toàn trên hệ thống đám mây.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: context.appTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
