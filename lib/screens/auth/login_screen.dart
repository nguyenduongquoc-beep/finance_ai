import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_localizations.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/main_navigation.dart';
import '../setup/wallet_setup_screen.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';

/// Login Screen - Đăng nhập bằng Email hoặc Google
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  String? _errorMessage;

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final credential = await _authService.loginWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final user = credential.user;
      if (user != null) {
        final firestore = FirestoreService();
        final profile = await firestore.getUserProfile(user.uid);
        if (profile != null && profile.isLocked) {
          await _authService.signOut();
          if (!mounted) return;
          setState(() {
            _errorMessage = AppLocalizations.tr('auth_err_locked');
          });
          return;
        }
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavigation()),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-disabled') {
        setState(() {
          _errorMessage = AppLocalizations.tr('auth_err_locked');
        });
      } else {
        setState(() => _errorMessage = AppLocalizations.tr('auth_err_invalid_creds'));
      }
    } catch (e) {
      setState(() => _errorMessage = AppLocalizations.tr('auth_err_invalid_creds'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final credential = await _authService.loginWithGoogle();
      if (credential == null || !mounted) return;

      final user = credential.user!;
      final firestore = FirestoreService();
      final profile = await firestore.getUserProfile(user.uid);
      if (profile != null && profile.isLocked) {
        await _authService.signOut();
        if (!mounted) return;
        setState(() {
          _errorMessage = AppLocalizations.tr('auth_err_locked');
        });
        return;
      }

      if (profile == null) {
        final displayName = (user.displayName?.trim().isNotEmpty == true)
            ? user.displayName!.trim()
            : AppLocalizations.tr('common_user');
        await firestore.createUserProfile(
          AppUser(
            uid: user.uid,
            name: displayName,
            email: user.email ?? '',
            createdAt: DateTime.now(),
          ),
        );
      }

      final wallets = await firestore.getWalletsSafely(user.uid);
      if (!mounted) return;
      if (wallets.isEmpty) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const WalletSetupScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainNavigation()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-disabled') {
        setState(() {
          _errorMessage = AppLocalizations.tr('auth_err_locked');
        });
      } else {
        setState(() => _errorMessage = AppLocalizations.tr('auth_err_google_failed'));
      }
    } catch (e) {
      setState(() => _errorMessage = AppLocalizations.tr('auth_err_google_failed'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  // App Icon Branding & Tiêu đề căn giữa cân đối (màu gốc dự án)
                  Center(
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    context.tr('auth_welcome_back'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('auth_login_sub'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: context.appTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Email Input
                  AppTextField(
                    controller: _emailController,
                    labelText: context.tr('auth_email_label'),
                    hintText: context.tr('auth_email_hint'),
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || !v.contains('@'))
                        ? context.tr('auth_email_invalid')
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // Password Input
                  AppTextField(
                    controller: _passwordController,
                    labelText: context.tr('auth_password_label'),
                    hintText: '••••••••',
                    prefixIcon: Icons.lock_outline_rounded,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: context.appTextSecondary,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? context.tr('auth_password_min')
                        : null,
                  ),
                  const SizedBox(height: 10),

                  // Remember Me & Forgot Password Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _rememberMe,
                                activeColor: AppColors.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                side: BorderSide(
                                    color: context.appBorder, width: 1.5),
                                onChanged: (v) =>
                                    setState(() => _rememberMe = v ?? false),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                context.tr('auth_remember_me'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: context.appTextSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const ForgotPasswordScreen()),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              context.tr('auth_forgot_password'),
                              maxLines: 1,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.primaryLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Error Banner
                  if (_errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.expenseBackground,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppColors.expense.withAlpha(80)),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.inter(
                            color: AppColors.expense, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // CTA Button (Đồng bộ màu Dark Slate #161F28 của thẻ màn hình chính)
                  AppButton(
                    text: context.tr('auth_login_btn'),
                    backgroundColor: const Color(0xFF161F28),
                    textColor: Colors.white,
                    isLoading: _isLoading,
                    onPressed: _handleLogin,
                  ),
                  const SizedBox(height: 24),

                  // Divider
                  Row(
                    children: [
                      Expanded(child: Divider(color: context.appBorder)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          context.tr('auth_or_login_with'),
                          style: GoogleFonts.inter(
                            color: context.appTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: context.appBorder)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Google SSO Button với logo Google chuẩn 4 màu
                  AppOutlinedButton(
                    text: context.tr('auth_login_google'),
                    isLoading: _isLoading,
                    leading: const GoogleLogoIcon(size: 20),
                    onPressed: _handleGoogleLogin,
                  ),
                  const SizedBox(height: 28),

                  // Footer Register Link
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const RegisterScreen()),
                      ),
                      child: Text.rich(
                        TextSpan(
                          text: context.tr('auth_no_account'),
                          style: GoogleFonts.inter(
                            color: context.appTextSecondary,
                            fontSize: 14,
                          ),
                          children: [
                            TextSpan(
                              text: context.tr('auth_register_now'),
                              style: GoogleFonts.inter(
                                color: AppColors.primaryLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
