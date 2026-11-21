import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/app_text_field.dart';
import 'auth/forgot_password_screen.dart';
import 'auth/login_screen.dart';
import '../l10n/app_localizations.dart';

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
      AppSnackbar.show(context, context.tr('sec_err_cur_empty'), isError: true);
      return;
    }
    if (newPass.isEmpty) {
      AppSnackbar.show(context, context.tr('sec_err_new_empty'), isError: true);
      return;
    }
    if (newPass.length < 6) {
      AppSnackbar.show(context, context.tr('sec_err_new_short'), isError: true);
      return;
    }
    if (newPass == current) {
      AppSnackbar.show(
        context,
        context.tr('sec_err_new_same'),
        isError: true,
      );
      return;
    }
    if (newPass != confirm) {
      AppSnackbar.show(context, context.tr('sec_err_mismatch'), isError: true);
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
        AppSnackbar.show(context, context.tr('sec_pwd_updated'));
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
            message = context.tr('sec_err_wrong_pwd');
            break;
          case 'weak-password':
            message = context.tr('sec_err_weak_pwd');
            break;
          case 'requires-recent-login':
            message = context.tr('sec_err_recent_login');
            break;
          case 'network-request-failed':
            message = context.tr('sec_err_network');
            break;
          default:
            message = context.tr(
              'sec_err_change_failed',
              params: {'error': e.message ?? e.code},
            );
        }
        AppSnackbar.show(context, message, isError: true);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(
          context,
          context.tr('sec_err_unknown'),
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
        title: Text(context.tr('sec_title')),
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
            const SizedBox(height: 24),

            // 4. Vùng nguy hiểm: Xóa tài khoản
            _buildDeleteAccountSection(isEmailPasswordUser),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// Thẻ tổng quan phương thức đăng nhập
  Widget _buildAuthMethodCard(
      User? user, bool isGoogleOnly, bool isEmailPassword) {
    final email = user?.email ?? context.tr('sec_no_email');
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
                      isGoogleOnly
                          ? context.tr('sec_provider_google')
                          : context.tr('sec_provider_email'),
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
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.incomeBackground,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      context.tr('sec_verified'),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.income,
                      ),
                    ),
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
              Expanded(
                child: Text(
                  context.tr('sec_google_title'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('sec_google_desc', params: {'email': email}),
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
                    context.tr('sec_google_2fa'),
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
            context.tr('sec_google_hint'),
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
            context.tr('sec_change_pwd_title'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.appTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('sec_change_pwd_sub'),
            style: TextStyle(
              fontSize: 12,
              color: context.appTextSecondary,
            ),
          ),
          const SizedBox(height: 18),

          // Mật khẩu hiện tại
          AppTextField(
            controller: _currentPasswordController,
            labelText: context.tr('sec_cur_pwd_label'),
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
            labelText: context.tr('sec_new_pwd_label'),
            hintText: context.tr('sec_min_6_chars'),
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
              Expanded(
                child: Text(
                  context.tr('sec_min_6_chars'),
                  style: TextStyle(
                    fontSize: 11,
                    color: _newPasswordController.text.length >= 6
                        ? AppColors.income
                        : context.appTextSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Xác nhận mật khẩu mới
          AppTextField(
            controller: _confirmPasswordController,
            labelText: context.tr('sec_confirm_pwd_label'),
            hintText: context.tr('sec_confirm_pwd_hint'),
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
            text: context.tr('sec_update_pwd_btn'),
            backgroundColor: const Color(0xFF161F28),
            textColor: Colors.white,
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
              child: Text(
                context.tr('sec_forgot_cur_pwd'),
                style: const TextStyle(
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
                  context.tr('sec_notice_title'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr('sec_notice_desc'),
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

  /// Vùng nguy hiểm: Xóa tài khoản
  Widget _buildDeleteAccountSection(bool isEmailPasswordUser) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.expense.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.expense.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.delete_forever_rounded,
                color: AppColors.expense,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Xóa tài khoản',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.expense,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Sau khi xóa, tài khoản và toàn bộ dữ liệu tài chính của bạn (ví, giao dịch, ngân sách, mục tiêu) sẽ bị xóa vĩnh viễn và không thể khôi phục.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: context.appTextSecondary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.expense,
                side: const BorderSide(color: AppColors.expense),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _isUpdating
                  ? null
                  : () => _handleDeleteAccount(isEmailPasswordUser),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text(
                'Xóa vĩnh viễn tài khoản',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeleteAccount(bool isEmailPasswordUser) async {
    final passwordCtrl = TextEditingController();
    bool obscureConfirmPass = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: AppColors.expense,
                size: 24,
              ),
              SizedBox(width: 8),
              Expanded(child: Text('Xác nhận Xóa tài khoản')),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CẢNH BÁO NGUY HIỂM:\n\n'
                  '• Tài khoản của bạn sẽ bị xóa vĩnh viễn khỏi hệ thống.\n'
                  '• Toàn bộ dữ liệu hồ sơ, ví, giao dịch, ngân sách, mục tiêu sẽ được dọn dẹp sạch sẽ.\n'
                  '• Thao tác này KHÔNG THỂ HOÀN TÁC.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.expense,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isEmailPasswordUser) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Vui lòng nhập mật khẩu hiện tại để xác thực:',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: obscureConfirmPass,
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu hiện tại',
                      prefixIcon:
                          const Icon(Icons.lock_outline_rounded, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureConfirmPass
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () => setDialogState(
                            () => obscureConfirmPass = !obscureConfirmPass),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.expense,
              ),
              onPressed: () {
                if (isEmailPasswordUser && passwordCtrl.text.isEmpty) {
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              icon: const Icon(Icons.delete_forever_rounded, size: 16),
              label: const Text('Xóa Vĩnh Viễn'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isUpdating = true);
    try {
      await _authService.deleteCurrentUser(
        currentPassword: isEmailPasswordUser ? passwordCtrl.text : null,
      );

      if (!mounted) return;
      AppSnackbar.show(context, 'Tài khoản của bạn đã được xóa thành công.');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message = 'Không thể xóa tài khoản.';
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'Mật khẩu hiện tại không chính xác.';
      } else if (e.code == 'requires-recent-login') {
        message =
            'Yêu cầu bảo mật: Vui lòng đăng nhập lại trước khi thực hiện xóa tài khoản.';
      }
      AppSnackbar.show(context, message, isError: true);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        'Không thể xóa tài khoản. Vui lòng thử lại sau.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }
}
