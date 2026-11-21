import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_service.dart';
import '../../utils/constants.dart';
import '../services/admin_web_service.dart';
import 'admin_web_shell_screen.dart';

/// Màn hình Đăng nhập dành riêng cho Cổng Quản trị Web (Admin Web Portal).
/// Nguyên tắc bảo mật:
/// - Không có chức năng đăng ký công khai.
/// - Sau khi xác thực Firebase Auth, kiểm tra nghiêm ngặt quyền Admin (Custom Claims / Firestore role)
///   và trạng thái khóa (`status != 'locked'`).
/// - Nếu là tài khoản User thường hoặc bị khóa -> Đăng xuất ngay lập tức và từ chối truy cập.
class AdminLoginScreen extends StatefulWidget {
  final AdminWebService? adminService;
  final Future<String?> Function(String email, String password)?
      customSignInUidProvider;
  final Future<void> Function()? customSignOutHandler;
  final Map<String, dynamic>? tokenClaimsOverride;

  const AdminLoginScreen({
    super.key,
    this.adminService,
    this.customSignInUidProvider,
    this.customSignOutHandler,
    this.tokenClaimsOverride,
  });

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  late final AdminWebService _adminService;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _adminService = widget.adminService ?? AdminWebService();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signOutSafely() async {
    if (widget.customSignOutHandler != null) {
      await widget.customSignOutHandler!();
      return;
    }
    try {
      await AuthService().signOut();
    } catch (_) {}
  }

  Future<void> _handleAdminLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String? uid;
      if (widget.customSignInUidProvider != null) {
        uid = await widget.customSignInUidProvider!(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
        );
      } else {
        final credential = await AuthService().loginWithEmail(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
        uid = credential.user?.uid;
      }

      if (uid == null || uid.isEmpty) {
        setState(() {
          _errorMessage = 'Xác thực không thành công. Vui lòng thử lại.';
        });
        return;
      }

      final accessCheck = await _adminService.verifyAdminAccess(
        uidOverride: uid,
        tokenClaimsOverride: widget.tokenClaimsOverride,
      );

      if (!accessCheck.isAuthorized) {
        await _signOutSafely();
        if (!mounted) return;
        setState(() {
          _errorMessage = accessCheck.errorMessage ??
              'Tài khoản không có quyền truy cập Cổng Quản trị Hệ thống.';
        });
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AdminWebShellScreen(
            adminService: _adminService,
            adminUidOverride: uid,
            tokenClaimsOverride: widget.tokenClaimsOverride,
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-disabled') {
        setState(() {
          _errorMessage =
              'Tài khoản này đã bị vô hiệu hóa trên Firebase Authentication.';
        });
      } else {
        setState(() {
          _errorMessage = 'Email hoặc mật khẩu quản trị không chính xác.';
        });
      }
    } catch (_) {
      setState(() {
        _errorMessage = 'Email hoặc mật khẩu quản trị không chính xác.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slate100,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.slate200),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Finance AI — Admin Portal',
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.slate900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Cổng quản trị & vận hành hệ thống',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: AppColors.slate500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.infoBackground,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.verified_user_outlined,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Khu vực giới hạn quyền hạn. Chỉ tài khoản được cấp quyền Quản trị viên (Admin) mới được phép truy cập.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.slate700,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      key: const ValueKey('admin_login_email'),
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email Quản trị viên',
                        hintText: 'admin@financeai.vn',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) {
                        if (v == null || !v.trim().contains('@')) {
                          return 'Vui lòng nhập email hợp lệ';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('admin_login_password'),
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      onFieldSubmitted: (_) => _handleAdminLogin(),
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu',
                        hintText: '••••••••',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(
                                () => _obscurePassword = !_obscurePassword);
                          },
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.length < 6) {
                          return 'Mật khẩu tối thiểu 6 ký tự';
                        }
                        return null;
                      },
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        key: const ValueKey('admin_login_error_banner'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.expenseBackground,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.expense.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: AppColors.expense,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: AppColors.expense,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        key: const ValueKey('admin_login_submit_btn'),
                        onPressed: _isLoading ? null : _handleAdminLogin,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.login_rounded, size: 18),
                        label: Text(
                          _isLoading
                              ? 'Đang xác thực quyền Admin...'
                              : 'Đăng nhập Quản trị',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
